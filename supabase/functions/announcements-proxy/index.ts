import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-app-secret",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  if (!appSecret || !incomingSecret || incomingSecret !== appSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const playerLevel = body.player_level ?? 1;

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    const { data: announcements, error: aErr } = await supabase.from("app_announcements").select("*").eq("is_active", true).lte("target_min_level", playerLevel).or("target_max_level.is.null,target_max_level.gte." + playerLevel).lte("starts_at", new Date().toISOString()).or("expires_at.is.null,expires_at.gt." + new Date().toISOString()).order("sort_order", { ascending: true });
    if (aErr) throw aErr;

    const { data: notifications, error: nErr } = await supabase.from("notifications_config").select("*").eq("is_active", true).order("category", { ascending: true });
    if (nErr) throw nErr;

    return new Response(JSON.stringify({ announcements: announcements ?? [], notifications: notifications ?? [] }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (err) {
    console.error("announcements-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
