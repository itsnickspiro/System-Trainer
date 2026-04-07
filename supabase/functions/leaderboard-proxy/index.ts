import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
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
    const action = body.action ?? "get_global";
    const cloudkitUserId = body.cloudkit_user_id ?? "";
    const page = Math.max(parseInt(body.page ?? "1", 10), 1);
    const pageSize = Math.min(parseInt(body.page_size ?? "50", 10), 100);
    const offset = (page - 1) * pageSize;

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    // GET GLOBAL LEADERBOARD
    if (action === "get_global") {
      const { data, error, count } = await supabase
        .from("leaderboard")
        .select("player_id, display_name, level, total_xp, rank, current_streak, avatar_key, last_active_at", { count: "exact" })
        .eq("is_banned", false)
        .order("total_xp", { ascending: false })
        .order("level", { ascending: false })
        .range(offset, offset + pageSize - 1);
      if (error) throw error;

      // Compute caller's rank correctly: fetch their total_xp first, then count
      // rows with strictly greater total_xp. The previous version passed a query
      // builder to .gt() which silently produced totalRows + 1 every time.
      let playerRank = null;
      if (cloudkitUserId) {
        const { data: me } = await supabase
          .from("leaderboard")
          .select("total_xp")
          .eq("cloudkit_user_id", cloudkitUserId)
          .maybeSingle();
        const myTotalXP = me?.total_xp ?? 0;
        const { count: ahead } = await supabase
          .from("leaderboard")
          .select("*", { count: "exact", head: true })
          .eq("is_banned", false)
          .gt("total_xp", myTotalXP);
        playerRank = (ahead ?? 0) + 1;
      }
      return new Response(JSON.stringify({ entries: data ?? [], total: count ?? 0, page, player_rank: playerRank }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // GET WEEKLY LEADERBOARD
    if (action === "get_weekly") {
      const { data, error } = await supabase.from("leaderboard").select("player_id, display_name, level, weekly_xp, weekly_workouts, rank, avatar_key").eq("is_banned", false).order("weekly_xp", { ascending: false }).range(offset, offset + pageSize - 1);
      if (error) throw error;
      return new Response(JSON.stringify({ entries: data ?? [], page }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // GET FRIENDS LEADERBOARD
    if (action === "get_friends") {
      if (!cloudkitUserId) return new Response(JSON.stringify({ error: "cloudkit_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      const { data: friends } = await supabase.from("friend_connections").select("friend_cloudkit_user_id").eq("cloudkit_user_id", cloudkitUserId).eq("status", "accepted");
      const friendIds = (friends ?? []).map((f: Record<string, unknown>) => f.friend_cloudkit_user_id).filter(Boolean);
      friendIds.push(cloudkitUserId); // include self
      const { data, error } = await supabase.from("leaderboard").select("player_id, display_name, level, total_xp, rank, current_streak, avatar_key").in("cloudkit_user_id", friendIds).eq("is_banned", false).order("total_xp", { ascending: false });
      if (error) throw error;
      return new Response(JSON.stringify({ entries: data ?? [] }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // UPSERT LEADERBOARD ENTRY
    //
    // Accepts EITHER shape:
    //   { action, cloudkit_user_id, entry: { display_name, level, total_xp, ... } }
    //   { action, cloudkit_user_id, display_name, level, total_xp, current_streak, player_id, ... }
    //
    // The iOS client sends the second (flat) shape; older callers may use the
    // first. Previously the proxy ONLY read body.entry, so flat-shaped requests
    // wrote nothing but cloudkit_user_id and the table's NOT NULL defaults
    // ("Warrior", level 1, 0 XP) filled in the rest. This is the actual root
    // cause of the leaderboard placeholder bug — yesterday's "wait for profile
    // before upserting" fix was necessary but insufficient.
    if (action === "upsert_entry") {
      if (!cloudkitUserId) return new Response(JSON.stringify({ error: "cloudkit_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

      // Build the entry from either shape. Whitelist columns to avoid letting
      // a malicious client write to forbidden fields like is_banned/is_flagged.
      const src = (body.entry && typeof body.entry === "object") ? body.entry : body;
      const allowed = ["display_name", "level", "total_xp", "current_streak", "total_workouts", "weekly_xp", "weekly_workouts", "rank", "avatar_key", "country_code", "player_id"];
      const entry: Record<string, unknown> = {};
      for (const k of allowed) {
        if (src[k] !== undefined && src[k] !== null) entry[k] = src[k];
      }

      // Anti-cheat: flag if XP gain seems suspicious
      const { data: existing } = await supabase
        .from("leaderboard")
        .select("total_xp, updated_at")
        .eq("cloudkit_user_id", cloudkitUserId)
        .maybeSingle();
      let isFlagged = false;
      if (existing && typeof entry.total_xp === "number") {
        const xpGain = (entry.total_xp as number) - (existing.total_xp ?? 0);
        const hoursSinceUpdate = (Date.now() - new Date(existing.updated_at).getTime()) / 3600000;
        if (hoursSinceUpdate < 24 && xpGain > 5000) isFlagged = true;
      }

      const { error } = await supabase.from("leaderboard").upsert({
        ...entry,
        cloudkit_user_id: cloudkitUserId,
        is_flagged: isFlagged,
        last_active_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: "cloudkit_user_id" });
      if (error) throw error;
      return new Response(JSON.stringify({ success: true, flagged: isFlagged, fields_written: Object.keys(entry).length }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // ADD FRIEND
    if (action === "add_friend") {
      const friendPlayerId = body.friend_player_id ?? "";
      if (!cloudkitUserId || !friendPlayerId) return new Response(JSON.stringify({ error: "Missing params" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      // Resolve friend's cloudkit ID from player_id
      const { data: friendProfile } = await supabase.from("player_profiles").select("cloudkit_user_id").eq("player_id", friendPlayerId).maybeSingle();
      const { error } = await supabase.from("friend_connections").upsert({ cloudkit_user_id: cloudkitUserId, friend_player_id: friendPlayerId, friend_cloudkit_user_id: friendProfile?.cloudkit_user_id ?? null, status: "accepted" }, { onConflict: "cloudkit_user_id,friend_player_id" });
      if (error) throw error;
      return new Response(JSON.stringify({ success: true, found: !!friendProfile }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (err) {
    console.error("leaderboard-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
