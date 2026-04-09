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
    const action = body.action ?? "get_events";
    const cloudkitUserId = body.cloudkit_user_id ?? "";
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    if (action === "get_events") {
      const { data: events, error: eErr } = await supabase.from("special_events").select("*").eq("is_active", true).gt("ends_at", new Date().toISOString()).order("sort_order");
      if (eErr) throw eErr;
      let participation: unknown[] = [];
      if (cloudkitUserId) {
        const eventKeys = (events ?? []).map((e: Record<string, unknown>) => e.key);
        if (eventKeys.length > 0) {
          const { data: parts } = await supabase.from("event_participants").select("*").eq("cloudkit_user_id", cloudkitUserId).in("event_key", eventKeys);
          participation = parts ?? [];
        }
      }
      return new Response(JSON.stringify({ events: events ?? [], participation }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (action === "join_event") {
      const eventKey = body.event_key ?? "";
      const displayName = body.display_name ?? "Warrior";
      if (!cloudkitUserId || !eventKey) return new Response(JSON.stringify({ error: "Missing params" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      const { error } = await supabase.from("event_participants").upsert({ event_key: eventKey, cloudkit_user_id: cloudkitUserId, display_name: displayName }, { onConflict: "event_key,cloudkit_user_id" });
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (action === "update_progress") {
      const eventKey = body.event_key ?? "";
      const progress = body.progress ?? 0;
      const completed = body.goal_completed ?? false;
      if (!cloudkitUserId || !eventKey) return new Response(JSON.stringify({ error: "Missing params" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      const updateData: Record<string, unknown> = { current_progress: progress, goal_completed: completed };
      if (completed) updateData.completed_at = new Date().toISOString();
      const { error } = await supabase.from("event_participants").update(updateData).eq("event_key", eventKey).eq("cloudkit_user_id", cloudkitUserId);
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (err) {
    console.error("events-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
