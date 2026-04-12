import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-app-secret",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const adminSecret = Deno.env.get("APP_ADMIN_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  const isAppAuth = appSecret && incomingSecret && incomingSecret === appSecret;
  const isAdminAuth =
    adminSecret && incomingSecret && incomingSecret === adminSecret;

  if (!isAppAuth && !isAdminAuth) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const action = body.action ?? "";
    const cloudkitUserId = body.cloudkit_user_id ?? "";

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("DB_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // Check master switch
    const { data: sw } = await supabase
      .from("remote_config")
      .select("value")
      .eq("key", "seasons_enabled")
      .eq("is_active", true)
      .maybeSingle();
    if (sw?.value === "false") {
      return jsonResponse({ error: "Seasons are currently disabled" }, 503);
    }

    // ── GET ACTIVE SEASON ─────────────────────────────────────────────
    if (action === "get_active_season") {
      const { data: season, error } = await supabase
        .from("leaderboard_seasons")
        .select("*")
        .eq("status", "active")
        .order("season_number", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      if (!season) return jsonResponse({ season: null });

      // Get caller's season rank + XP
      let myRank: number | null = null;
      let mySeasonXp = 0;
      if (cloudkitUserId) {
        const { data: me } = await supabase
          .from("leaderboard")
          .select("season_xp")
          .eq("cloudkit_user_id", cloudkitUserId)
          .maybeSingle();
        mySeasonXp = me?.season_xp ?? 0;

        if (mySeasonXp > 0) {
          const { count: ahead } = await supabase
            .from("leaderboard")
            .select("*", { count: "exact", head: true })
            .eq("is_banned", false)
            .gt("season_xp", mySeasonXp);
          myRank = (ahead ?? 0) + 1;
        }
      }

      // Top 10 for preview
      const { data: top10 } = await supabase
        .from("leaderboard")
        .select(
          "cloudkit_user_id, display_name, avatar_key, level, season_xp",
        )
        .eq("is_banned", false)
        .gt("season_xp", 0)
        .order("season_xp", { ascending: false })
        .limit(10);

      // Assign ranks
      (top10 ?? []).forEach(
        (e: Record<string, unknown>, i: number) => (e.rank = i + 1),
      );

      // Time remaining
      const endsAt = new Date(season.ends_at);
      const nowMs = Date.now();
      const remainingMs = Math.max(0, endsAt.getTime() - nowMs);
      const remainingDays = Math.ceil(remainingMs / 86400000);

      return jsonResponse({
        season,
        my_season_xp: mySeasonXp,
        my_rank: myRank,
        top_10: top10 ?? [],
        remaining_days: remainingDays,
      });
    }

    // ── GET SEASON LEADERBOARD ────────────────────────────────────────
    if (action === "get_season_leaderboard") {
      const page = Math.max(parseInt(body.page ?? "1", 10), 1);
      const pageSize = Math.min(parseInt(body.page_size ?? "50", 10), 100);
      const offset = (page - 1) * pageSize;

      const { data, error, count } = await supabase
        .from("leaderboard")
        .select(
          "cloudkit_user_id, player_id, display_name, level, season_xp, total_xp, avatar_key",
          { count: "exact" },
        )
        .eq("is_banned", false)
        .gt("season_xp", 0)
        .order("season_xp", { ascending: false })
        .order("total_xp", { ascending: false })
        .range(offset, offset + pageSize - 1);
      if (error) throw error;

      (data ?? []).forEach(
        (e: Record<string, unknown>, i: number) => (e.rank = offset + i + 1),
      );

      return jsonResponse({
        entries: data ?? [],
        total: count ?? 0,
        page,
      });
    }

    // ── GET SEASON HISTORY ────────────────────────────────────────────
    if (action === "get_season_history") {
      const { data, error } = await supabase
        .from("leaderboard_seasons")
        .select("*")
        .in("status", ["completed", "active"])
        .order("season_number", { ascending: false })
        .limit(20);
      if (error) throw error;

      return jsonResponse({ seasons: data ?? [] });
    }

    // ── GET MY REWARDS ────────────────────────────────────────────────
    if (action === "get_my_rewards") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      const { data, error } = await supabase
        .from("season_rewards")
        .select("*, leaderboard_seasons!inner(season_number, label)")
        .eq("cloudkit_user_id", cloudkitUserId)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;

      return jsonResponse({ rewards: data ?? [] });
    }

    // ── CLAIM SEASON REWARD ───────────────────────────────────────────
    if (action === "claim_reward") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);
      const rewardId = (body.reward_id ?? "").toString();
      if (!rewardId)
        return jsonResponse({ error: "Missing reward_id" }, 400);

      // Fetch the reward
      const { data: reward, error: rErr } = await supabase
        .from("season_rewards")
        .select("*")
        .eq("id", rewardId)
        .eq("cloudkit_user_id", cloudkitUserId)
        .maybeSingle();
      if (rErr) throw rErr;
      if (!reward)
        return jsonResponse({ error: "Reward not found" }, 404);
      if (reward.claimed_at)
        return jsonResponse({
          success: true,
          already_claimed: true,
        });

      // Credit GP
      if (reward.reward_gp > 0) {
        const { data: profile } = await supabase
          .from("player_profiles")
          .select("system_credits, lifetime_credits_earned")
          .eq("cloudkit_user_id", cloudkitUserId)
          .single();
        const balance = profile?.system_credits ?? 0;
        const lifetime = profile?.lifetime_credits_earned ?? 0;
        const newBalance = balance + reward.reward_gp;
        const newLifetime = lifetime + reward.reward_gp;
        await supabase
          .from("player_profiles")
          .update({
            system_credits: newBalance,
            lifetime_credits_earned: newLifetime,
            updated_at: new Date().toISOString(),
          })
          .eq("cloudkit_user_id", cloudkitUserId);
        await supabase.from("credit_transactions").insert({
          cloudkit_user_id: cloudkitUserId,
          amount: reward.reward_gp,
          balance_after: newBalance,
          transaction_type: "season_reward",
          reference_key: `season_${reward.season_id}`,
        });
      }

      // Set title if earned
      if (reward.reward_title_key) {
        await supabase
          .from("player_profiles")
          .update({
            active_title_key: reward.reward_title_key,
            updated_at: new Date().toISOString(),
          })
          .eq("cloudkit_user_id", cloudkitUserId);
      }

      // Mark claimed
      await supabase
        .from("season_rewards")
        .update({ claimed_at: new Date().toISOString() })
        .eq("id", rewardId);

      return jsonResponse({
        success: true,
        reward_gp: reward.reward_gp,
        reward_title_key: reward.reward_title_key,
      });
    }

    // ── ADMIN: FINALIZE SEASON ────────────────────────────────────────
    if (action === "finalize_season") {
      if (!isAdminAuth)
        return jsonResponse({ error: "Admin only" }, 403);
      const seasonId = (body.season_id ?? "").toString();
      if (!seasonId)
        return jsonResponse({ error: "Missing season_id" }, 400);

      const { data, error } = await supabase.rpc("finalize_season", {
        p_season_id: seasonId,
      });
      if (error) throw error;
      return jsonResponse(data);
    }

    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (err) {
    console.error("season-proxy error:", err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
