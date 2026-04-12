import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-app-secret",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // Admin-only: requires APP_ADMIN_SECRET or RPT_APP_SECRET
  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const adminSecret = Deno.env.get("APP_ADMIN_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  const isAuth = (appSecret && incomingSecret === appSecret) ||
                 (adminSecret && incomingSecret === adminSecret);
  if (!isAuth) return jsonResponse({ error: "Unauthorized" }, 401);

  try {
    const body = await req.json();
    const action = body.action ?? "upload";

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("DB_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // ── UPLOAD AVATAR ─────────────────────────────────────────────────
    if (action === "upload") {
      const key = (body.key ?? "").toString();
      const base64Data = (body.image_base64 ?? "").toString();
      const contentType = (body.content_type ?? "image/png").toString();

      if (!key || !base64Data) {
        return jsonResponse({ error: "Missing key or image_base64" }, 400);
      }

      // Decode base64 to bytes
      const binaryStr = atob(base64Data);
      const bytes = new Uint8Array(binaryStr.length);
      for (let i = 0; i < binaryStr.length; i++) {
        bytes[i] = binaryStr.charCodeAt(i);
      }

      const ext = contentType === "image/jpeg" ? "jpg" : "png";
      const filePath = `${key}.${ext}`;

      // Upload to storage
      const { error: uploadErr } = await supabase.storage
        .from("avatars")
        .upload(filePath, bytes, {
          contentType,
          upsert: true,
        });
      if (uploadErr) throw uploadErr;

      // Get public URL
      const { data: urlData } = supabase.storage
        .from("avatars")
        .getPublicUrl(filePath);

      const publicUrl = urlData?.publicUrl ?? "";

      // Update the avatars table with the URL
      await supabase
        .from("avatars")
        .update({ image_url: publicUrl })
        .eq("key", key);

      return jsonResponse({ success: true, image_url: publicUrl, key });
    }

    // ── ADD NEW AVATAR ────────────────────────────────────────────────
    // Creates the DB row AND uploads the image in one call.
    if (action === "add_avatar") {
      const key = (body.key ?? "").toString();
      const name = (body.name ?? "").toString();
      const base64Data = (body.image_base64 ?? "").toString();
      const contentType = (body.content_type ?? "image/png").toString();
      const category = (body.category ?? "free").toString();
      const gender = (body.gender ?? "neutral").toString();
      const unlockType = (body.unlock_type ?? "free").toString();
      const gpCost = parseInt(body.gp_cost ?? "0", 10) || 0;
      const sortOrder = parseInt(body.sort_order ?? "100", 10);

      if (!key || !name || !base64Data) {
        return jsonResponse({ error: "Missing key, name, or image_base64" }, 400);
      }

      // Upload image
      const binaryStr = atob(base64Data);
      const bytes = new Uint8Array(binaryStr.length);
      for (let i = 0; i < binaryStr.length; i++) {
        bytes[i] = binaryStr.charCodeAt(i);
      }

      const ext = contentType === "image/jpeg" ? "jpg" : "png";
      const filePath = `${key}.${ext}`;

      const { error: uploadErr } = await supabase.storage
        .from("avatars")
        .upload(filePath, bytes, { contentType, upsert: true });
      if (uploadErr) throw uploadErr;

      const { data: urlData } = supabase.storage
        .from("avatars")
        .getPublicUrl(filePath);
      const publicUrl = urlData?.publicUrl ?? "";

      // Insert DB row
      const { data: avatar, error: insertErr } = await supabase
        .from("avatars")
        .upsert({
          key,
          name,
          category,
          gender,
          unlock_type: unlockType,
          gp_cost: gpCost,
          image_url: publicUrl,
          sort_order: sortOrder,
          is_active: true,
        }, { onConflict: "key" })
        .select("*")
        .single();
      if (insertErr) throw insertErr;

      return jsonResponse({ success: true, avatar });
    }

    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (err) {
    console.error("avatar-upload-proxy error:", err);
    return jsonResponse({ error: String(err) }, 500);
  }
});
