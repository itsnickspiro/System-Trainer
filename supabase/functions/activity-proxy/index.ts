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
    const action = body.action ?? "log_workout";
    const cloudkitUserId = body.cloudkit_user_id ?? "";
    if (!cloudkitUserId) return new Response(JSON.stringify({ error: "cloudkit_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    // LOG WORKOUT SUMMARY
    if (action === "log_workout") {
      const workout = body.workout ?? {};
      const { data, error } = await supabase.from("workout_summaries").insert({ ...workout, cloudkit_user_id: cloudkitUserId }).select().single();
      if (error) throw error;
      return new Response(JSON.stringify({ success: true, workout: data }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // GET WORKOUT HISTORY
    if (action === "get_workouts") {
      const limit = Math.min(parseInt(body.limit ?? "30", 10), 100);
      const { data, error } = await supabase.from("workout_summaries").select("*").eq("cloudkit_user_id", cloudkitUserId).order("workout_date", { ascending: false }).limit(limit);
      if (error) throw error;
      return new Response(JSON.stringify({ workouts: data ?? [] }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // LOG STREAK DAY
    if (action === "log_streak_day") {
      const streakDay = body.streak_day ?? {};
      const { error } = await supabase.from("streak_history").upsert({ ...streakDay, cloudkit_user_id: cloudkitUserId }, { onConflict: "cloudkit_user_id,activity_date" });
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // GET STREAK HISTORY
    if (action === "get_streak_history") {
      const days = Math.min(parseInt(body.days ?? "90", 10), 365);
      const since = new Date();
      since.setDate(since.getDate() - days);
      const { data, error } = await supabase.from("streak_history").select("*").eq("cloudkit_user_id", cloudkitUserId).gte("activity_date", since.toISOString().split("T")[0]).order("activity_date", { ascending: false });
      if (error) throw error;
      // Reconstruct streak from history
      const activeDates = new Set((data ?? []).filter((d: Record<string, unknown>) => d.was_active).map((d: Record<string, unknown>) => d.activity_date));
      let reconstructedStreak = 0;
      const today = new Date();
      for (let i = 0; i < days; i++) {
        const checkDate = new Date(today);
        checkDate.setDate(today.getDate() - i);
        const dateStr = checkDate.toISOString().split("T")[0];
        if (activeDates.has(dateStr)) reconstructedStreak++;
        else if (i > 0) break;
      }
      return new Response(JSON.stringify({ history: data ?? [], reconstructed_streak: reconstructedStreak }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (err) {
    console.error("activity-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
