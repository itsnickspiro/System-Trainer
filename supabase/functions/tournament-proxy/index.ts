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

async function isBanned(
  supabase: ReturnType<typeof createClient>,
  cloudkitUserId: string,
): Promise<boolean> {
  if (!cloudkitUserId) return false;
  try {
    const { data, error } = await supabase.rpc("is_player_banned", {
      p_cloudkit_user_id: cloudkitUserId,
    });
    if (error) return false;
    return data === true;
  } catch (_) {
    return false;
  }
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
      .eq("key", "tournaments_enabled")
      .eq("is_active", true)
      .maybeSingle();
    if (sw?.value === "false") {
      return jsonResponse({ error: "Tournaments are currently disabled" }, 503);
    }

    // ── LIST TOURNAMENTS ──────────────────────────────────────────────
    if (action === "list_tournaments") {
      const { data, error } = await supabase
        .from("tournaments")
        .select("*")
        .eq("is_enabled", true)
        .in("status", ["upcoming", "registering", "active"])
        .order("starts_at", { ascending: true })
        .limit(20);
      if (error) throw error;

      return jsonResponse({ tournaments: data ?? [] });
    }

    // ── GET TOURNAMENT ────────────────────────────────────────────────
    if (action === "get_tournament") {
      const tournamentId = (body.tournament_id ?? "").toString();
      if (!tournamentId)
        return jsonResponse({ error: "Missing tournament_id" }, 400);

      const { data: tournament, error: tErr } = await supabase
        .from("tournaments")
        .select("*")
        .eq("id", tournamentId)
        .single();
      if (tErr) throw tErr;

      const { data: participants } = await supabase
        .from("tournament_participants")
        .select("cloudkit_user_id, display_name, avatar_key, level, seed, current_xp_delta, eliminated_at_round, final_placement")
        .eq("tournament_id", tournamentId)
        .order("seed", { ascending: true });

      const { data: brackets } = await supabase
        .from("tournament_brackets")
        .select("*")
        .eq("tournament_id", tournamentId)
        .order("round", { ascending: true })
        .order("match_index", { ascending: true });

      // My participation
      let myParticipation = null;
      if (cloudkitUserId) {
        const { data: me } = await supabase
          .from("tournament_participants")
          .select("*")
          .eq("tournament_id", tournamentId)
          .eq("cloudkit_user_id", cloudkitUserId)
          .maybeSingle();
        myParticipation = me;
      }

      return jsonResponse({
        tournament,
        participants: participants ?? [],
        brackets: brackets ?? [],
        my_participation: myParticipation,
      });
    }

    // ── REGISTER ──────────────────────────────────────────────────────
    if (action === "register") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);
      if (await isBanned(supabase, cloudkitUserId))
        return jsonResponse({ success: false, error: "service_unavailable" }, 503);

      const tournamentId = (body.tournament_id ?? "").toString();
      if (!tournamentId)
        return jsonResponse({ error: "Missing tournament_id" }, 400);

      const { data: tournament } = await supabase
        .from("tournaments")
        .select("*")
        .eq("id", tournamentId)
        .single();
      if (!tournament)
        return jsonResponse({ error: "Tournament not found" }, 404);
      if (tournament.status !== "registering")
        return jsonResponse({ error: "Registration is not open" }, 400);

      // Check player level
      const { data: profile } = await supabase
        .from("player_profiles")
        .select("level, display_name, avatar_key, player_id, system_credits")
        .eq("cloudkit_user_id", cloudkitUserId)
        .single();
      if (!profile)
        return jsonResponse({ error: "Profile not found" }, 400);

      // Global min level floor from remote config
      let minLevelFloor = 5;
      try {
        const { data: cfg } = await supabase
          .from("remote_config")
          .select("value")
          .eq("key", "tournament_min_level_floor")
          .eq("is_active", true)
          .maybeSingle();
        const p = cfg?.value ? parseInt(String(cfg.value), 10) : NaN;
        if (Number.isFinite(p) && p > 0) minLevelFloor = p;
      } catch (_) { /* default */ }

      const effectiveMinLevel = Math.max(tournament.min_level ?? 1, minLevelFloor);
      if ((profile.level ?? 1) < effectiveMinLevel)
        return jsonResponse({ error: `Minimum level ${effectiveMinLevel} required` }, 400);

      // Check capacity
      const { count: currentCount } = await supabase
        .from("tournament_participants")
        .select("*", { count: "exact", head: true })
        .eq("tournament_id", tournamentId);
      if ((currentCount ?? 0) >= (tournament.max_participants ?? tournament.bracket_size))
        return jsonResponse({ error: "Tournament is full" }, 400);

      // Check duplicate registration
      const { data: existing } = await supabase
        .from("tournament_participants")
        .select("id")
        .eq("tournament_id", tournamentId)
        .eq("cloudkit_user_id", cloudkitUserId)
        .maybeSingle();
      if (existing)
        return jsonResponse({ success: true, already_registered: true });

      // Deduct entry fee if applicable
      if (tournament.entry_gp_cost > 0) {
        const balance = profile.system_credits ?? 0;
        if (balance < tournament.entry_gp_cost)
          return jsonResponse({ error: "Insufficient GP for entry fee" }, 400);
        await supabase
          .from("player_profiles")
          .update({
            system_credits: balance - tournament.entry_gp_cost,
            updated_at: new Date().toISOString(),
          })
          .eq("cloudkit_user_id", cloudkitUserId);
        await supabase.from("credit_transactions").insert({
          cloudkit_user_id: cloudkitUserId,
          amount: -tournament.entry_gp_cost,
          balance_after: balance - tournament.entry_gp_cost,
          transaction_type: "tournament_entry_fee",
          reference_key: tournamentId,
        });
      }

      const { error: insErr } = await supabase
        .from("tournament_participants")
        .insert({
          tournament_id: tournamentId,
          cloudkit_user_id: cloudkitUserId,
          display_name: profile.display_name ?? "Player",
          player_id: profile.player_id,
          avatar_key: profile.avatar_key,
          level: profile.level ?? 1,
        });
      if (insErr) throw insErr;

      return jsonResponse({ success: true });
    }

    // ── GET MY TOURNAMENTS ────────────────────────────────────────────
    if (action === "get_my_tournaments") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      const { data, error } = await supabase
        .from("tournament_participants")
        .select("*, tournaments!inner(*)")
        .eq("cloudkit_user_id", cloudkitUserId)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;

      return jsonResponse({ entries: data ?? [] });
    }

    // ── CLAIM PRIZE ───────────────────────────────────────────────────
    if (action === "claim_prize") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);
      const tournamentId = (body.tournament_id ?? "").toString();
      if (!tournamentId)
        return jsonResponse({ error: "Missing tournament_id" }, 400);

      const { data: participation } = await supabase
        .from("tournament_participants")
        .select("*, tournaments!inner(*)")
        .eq("tournament_id", tournamentId)
        .eq("cloudkit_user_id", cloudkitUserId)
        .maybeSingle();
      if (!participation)
        return jsonResponse({ error: "Not a participant" }, 400);
      if (participation.prize_claimed_at)
        return jsonResponse({ success: true, already_claimed: true });

      const tournament = participation.tournaments;
      if (tournament.status !== "completed")
        return jsonResponse({ error: "Tournament not yet completed" }, 400);

      // Calculate prize based on placement
      const placement = participation.final_placement;
      let prizeGp = 0;
      if (placement === 1) prizeGp = tournament.prize_pool_gp ?? 0;
      else if (placement === 2) prizeGp = Math.floor((tournament.prize_pool_gp ?? 0) * 0.3);
      else if (placement && placement <= 4) prizeGp = Math.floor((tournament.prize_pool_gp ?? 0) * 0.1);

      if (prizeGp > 0) {
        const { data: profile } = await supabase
          .from("player_profiles")
          .select("system_credits, lifetime_credits_earned")
          .eq("cloudkit_user_id", cloudkitUserId)
          .single();
        const balance = profile?.system_credits ?? 0;
        const lifetime = profile?.lifetime_credits_earned ?? 0;
        await supabase
          .from("player_profiles")
          .update({
            system_credits: balance + prizeGp,
            lifetime_credits_earned: lifetime + prizeGp,
            updated_at: new Date().toISOString(),
          })
          .eq("cloudkit_user_id", cloudkitUserId);
        await supabase.from("credit_transactions").insert({
          cloudkit_user_id: cloudkitUserId,
          amount: prizeGp,
          balance_after: balance + prizeGp,
          transaction_type: "tournament_prize",
          reference_key: tournamentId,
        });
      }

      await supabase
        .from("tournament_participants")
        .update({ prize_claimed_at: new Date().toISOString() })
        .eq("tournament_id", tournamentId)
        .eq("cloudkit_user_id", cloudkitUserId);

      return jsonResponse({ success: true, prize_gp: prizeGp });
    }

    // ── ADMIN: CREATE TOURNAMENT ──────────────────────────────────────
    if (action === "admin_create_tournament") {
      if (!isAdminAuth)
        return jsonResponse({ error: "Admin only" }, 403);

      const { data, error } = await supabase.rpc("admin_create_tournament", {
        p_title: body.title ?? "Tournament",
        p_description: body.description ?? null,
        p_bracket_size: body.bracket_size ?? 8,
        p_entry_gp_cost: body.entry_gp_cost ?? 0,
        p_starts_at: body.starts_at ?? new Date(Date.now() + 7 * 86400000).toISOString(),
        p_min_level: body.min_level ?? 5,
        p_prize_pool_gp: body.prize_pool_gp ?? 1000,
      });
      if (error) throw error;

      return jsonResponse({ success: true, tournament_id: data });
    }

    // ── ADMIN: START TOURNAMENT ───────────────────────────────────────
    if (action === "admin_start_tournament") {
      if (!isAdminAuth)
        return jsonResponse({ error: "Admin only" }, 403);
      const tournamentId = (body.tournament_id ?? "").toString();
      if (!tournamentId)
        return jsonResponse({ error: "Missing tournament_id" }, 400);

      const { data, error } = await supabase.rpc(
        "generate_tournament_bracket",
        { p_tournament_id: tournamentId },
      );
      if (error) throw error;
      return jsonResponse(data);
    }

    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (err) {
    console.error("tournament-proxy error:", err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
