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

// F9 phase 1: write-path shadowban gate.
async function isBanned(
  supabase: ReturnType<typeof createClient>,
  cloudkitUserId: string,
): Promise<boolean> {
  if (!cloudkitUserId) return false;
  try {
    const { data, error } = await supabase.rpc("is_player_banned", {
      p_cloudkit_user_id: cloudkitUserId,
    });
    if (error) {
      console.error("is_player_banned RPC failed — failing open:", error);
      return false;
    }
    return data === true;
  } catch (e) {
    console.error("is_player_banned threw — failing open:", e);
    return false;
  }
}

function bannedResponse() {
  return jsonResponse({ success: false, error: "service_unavailable" }, 503);
}

// F2 v1: GP wager escrow helpers. Debit on challenge send (held),
// credit to winner on settle (paid_winner), or refund to sender on
// decline/expire/cancel (refunded). Uses the same credit_transactions
// ledger the store uses so the audit trail is consistent.
async function debitEscrow(
  supabase: ReturnType<typeof createClient>,
  cloudkitUserId: string,
  amount: number,
  challengeId: string,
): Promise<{ ok: boolean; error?: string }> {
  if (amount <= 0) return { ok: true };
  const { data: profile, error: pErr } = await supabase
    .from("player_profiles")
    .select("system_credits")
    .eq("cloudkit_user_id", cloudkitUserId)
    .single();
  if (pErr) return { ok: false, error: "profile_lookup_failed" };
  const balance = profile?.system_credits ?? 0;
  if (balance < amount) return { ok: false, error: "insufficient_gp" };
  const { error: uErr } = await supabase
    .from("player_profiles")
    .update({ system_credits: balance - amount, updated_at: new Date().toISOString() })
    .eq("cloudkit_user_id", cloudkitUserId);
  if (uErr) return { ok: false, error: "debit_failed" };
  await supabase.from("credit_transactions").insert({
    cloudkit_user_id: cloudkitUserId,
    amount: -amount,
    balance_after: balance - amount,
    transaction_type: "challenge_escrow_debit",
    reference_key: challengeId,
  });
  return { ok: true };
}

async function creditEscrow(
  supabase: ReturnType<typeof createClient>,
  cloudkitUserId: string,
  amount: number,
  transactionType: string,
  challengeId: string,
): Promise<void> {
  if (amount <= 0) return;
  const { data: profile } = await supabase
    .from("player_profiles")
    .select("system_credits, lifetime_credits_earned")
    .eq("cloudkit_user_id", cloudkitUserId)
    .single();
  const balance = profile?.system_credits ?? 0;
  const lifetime = profile?.lifetime_credits_earned ?? 0;
  const newBalance = balance + amount;
  const newLifetime = lifetime + amount;
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
    amount,
    balance_after: newBalance,
    transaction_type: transactionType,
    reference_key: challengeId,
  });
}

/// Settles a challenge's escrow. Idempotent on escrow_status:
/// if already paid_winner or refunded, does nothing.
async function settleChallengeEscrow(
  supabase: ReturnType<typeof createClient>,
  challenge: Record<string, unknown>,
  outcome: "winner" | "refund",
): Promise<void> {
  const status = (challenge.escrow_status as string) ?? "none";
  if (status !== "held") return; // already settled or nothing to settle
  const wager = (challenge.wager_gp as number) ?? 0;
  if (wager <= 0) return;
  const challengerId = challenge.challenger_cloudkit_user_id as string;
  const challengeId = challenge.id as string;
  if (outcome === "winner") {
    const winnerId = (challenge.winner_cloudkit_user_id as string) ?? challengerId;
    // Winner gets 2x wager (their own back + sender's stake). Note the
    // challenger already pre-paid wager_gp; we credit 2*wager to the
    // winner which nets out to +wager for them if they are the challenger.
    await creditEscrow(supabase, winnerId, wager * 2, "challenge_escrow_payout", challengeId);
    await supabase
      .from("challenges")
      .update({ escrow_status: "paid_winner" })
      .eq("id", challengeId);
  } else {
    await creditEscrow(supabase, challengerId, wager, "challenge_escrow_refund", challengeId);
    await supabase
      .from("challenges")
      .update({ escrow_status: "refunded" })
      .eq("id", challengeId);
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  if (!appSecret || !incomingSecret || incomingSecret !== appSecret) {
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

    // ----- SEND CHALLENGE -----
    if (action === "send_challenge") {
      // F9 phase 1: banned players can't send challenges.
      if (await isBanned(supabase, cloudkitUserId)) return bannedResponse();
      // Also block challenges directed AT a banned player — prevents
      // exploiting the challenge system as a harassment vector after
      // the target gets banned.
      const preTargetId = (body.target_cloudkit_user_id ?? "").toString();
      if (preTargetId && await isBanned(supabase, preTargetId)) return bannedResponse();
      const targetId = (body.target_cloudkit_user_id ?? "").toString();
      const challengerName = (body.challenger_display_name ?? "").toString();
      const challengedName = (body.challenged_display_name ?? "").toString();
      const challengeType = (body.challenge_type ?? "").toString();
      const targetValue = parseInt(body.target_value ?? "0", 10) || null;
      const durationDays = Math.min(Math.max(parseInt(body.duration_days ?? "7", 10), 1), 30);
      // F2 v1: optional GP wager. Clamped server-side to pvp_max_wager_gp.
      const rawWager = parseInt(body.wager_gp ?? "0", 10) || 0;
      const metricType = (body.metric_type ?? "").toString() || null;

      if (!cloudkitUserId || !targetId || !challengeType) {
        return jsonResponse({ error: "Missing required fields" }, 400);
      }
      if (cloudkitUserId === targetId) {
        return jsonResponse({ error: "Cannot challenge yourself" }, 400);
      }

      // Clamp the wager to the server-side ceiling from remote_config.
      let maxWager = 1000;
      try {
        const { data: cfg } = await supabase
          .from("remote_config")
          .select("value")
          .eq("key", "pvp_max_wager_gp")
          .eq("is_active", true)
          .maybeSingle();
        const parsed = cfg?.value ? parseInt(String(cfg.value), 10) : NaN;
        if (Number.isFinite(parsed) && parsed > 0) maxWager = parsed;
      } catch (_) { /* use default */ }
      const wager = Math.max(0, Math.min(rawWager, maxWager));

      // Check for existing active/pending challenge between these players
      const { data: existing } = await supabase
        .from("challenges")
        .select("id")
        .or(`and(challenger_cloudkit_user_id.eq.${cloudkitUserId},challenged_cloudkit_user_id.eq.${targetId}),and(challenger_cloudkit_user_id.eq.${targetId},challenged_cloudkit_user_id.eq.${cloudkitUserId})`)
        .in("status", ["pending", "active"])
        .limit(1)
        .maybeSingle();
      if (existing) {
        return jsonResponse({ error: "You already have an active challenge with this player" }, 400);
      }

      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + durationDays);

      // F2 v1: insert the challenge row FIRST (so we have an id for the
      // credit_transactions reference), then attempt the escrow debit.
      // If the debit fails (insufficient GP), roll back by deleting the
      // newly-inserted row so the user sees a clean failure state.
      const { data: challenge, error } = await supabase
        .from("challenges")
        .insert({
          challenger_cloudkit_user_id: cloudkitUserId,
          challenger_display_name: challengerName,
          challenged_cloudkit_user_id: targetId,
          challenged_display_name: challengedName,
          challenge_type: challengeType,
          target_value: targetValue,
          duration_days: durationDays,
          status: "pending",
          expires_at: expiresAt.toISOString(),
          wager_gp: wager,
          escrow_status: wager > 0 ? "held" : "none",
          metric_type: metricType,
        })
        .select("*")
        .single();
      if (error) throw error;

      if (wager > 0) {
        const debit = await debitEscrow(supabase, cloudkitUserId, wager, challenge.id);
        if (!debit.ok) {
          // Roll back the challenge insert so we don't leave a phantom
          // held-escrow row with no actual debit.
          await supabase.from("challenges").delete().eq("id", challenge.id);
          return jsonResponse({ success: false, error: debit.error ?? "debit_failed" }, 400);
        }
      }

      return jsonResponse({ success: true, challenge });
    }

    // ----- RESPOND TO CHALLENGE -----
    if (action === "respond_challenge") {
      // F9 phase 1: banned players can't accept or decline challenges,
      // which effectively freezes pending challenges targeting them.
      if (await isBanned(supabase, cloudkitUserId)) return bannedResponse();
      const challengeId = (body.challenge_id ?? "").toString();
      const response = (body.response ?? "").toString(); // "accept" or "decline"

      if (!challengeId || !cloudkitUserId) {
        return jsonResponse({ error: "Missing params" }, 400);
      }

      const { data: challenge, error: fetchErr } = await supabase
        .from("challenges")
        .select("*")
        .eq("id", challengeId)
        .single();
      if (fetchErr) throw fetchErr;
      if (!challenge) return jsonResponse({ error: "Challenge not found" }, 404);

      if (challenge.challenged_cloudkit_user_id !== cloudkitUserId) {
        return jsonResponse({ error: "Only the challenged player can respond" }, 403);
      }
      if (challenge.status !== "pending") {
        return jsonResponse({ error: "Challenge is no longer pending" }, 400);
      }

      if (response === "accept") {
        const expiresAt = new Date();
        expiresAt.setDate(expiresAt.getDate() + (challenge.duration_days ?? 7));

        const { error: upErr } = await supabase
          .from("challenges")
          .update({
            status: "active",
            accepted_at: new Date().toISOString(),
            expires_at: expiresAt.toISOString(),
            challenger_progress: 0,
            challenged_progress: 0,
          })
          .eq("id", challengeId);
        if (upErr) throw upErr;

        return jsonResponse({ success: true, status: "active" });
      } else {
        const { error: upErr } = await supabase
          .from("challenges")
          .update({ status: "declined" })
          .eq("id", challengeId);
        if (upErr) throw upErr;

        // F2 v1: refund the sender's wager when the challenged player declines.
        await settleChallengeEscrow(supabase, challenge, "refund");

        return jsonResponse({ success: true, status: "declined" });
      }
    }

    // ----- GET MY CHALLENGES -----
    if (action === "get_my_challenges") {
      if (!cloudkitUserId) return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      // F2 v1: BEFORE flipping to expired, fetch the rows so we can
      // refund any escrow that was held on pending challenges the
      // challenged player never accepted. Only pending (not active)
      // rows are refunded — if the challenge was accepted and went
      // active, the wager stays in play and the expiry draw is a
      // forfeit for both sides (server keeps the escrow as a sink
      // for v1; v2 could split it). Active expired rows therefore
      // do NOT refund — wager is forfeited.
      const nowIso = new Date().toISOString();
      const { data: expiringPending } = await supabase
        .from("challenges")
        .select("*")
        .eq("status", "pending")
        .gt("wager_gp", 0)
        .eq("escrow_status", "held")
        .lt("expires_at", nowIso);
      for (const row of (expiringPending ?? [])) {
        await settleChallengeEscrow(supabase, row, "refund");
      }

      // Expire any pending/active challenges past their expiry
      await supabase
        .from("challenges")
        .update({ status: "expired" })
        .in("status", ["pending", "active"])
        .lt("expires_at", nowIso);

      const { data, error } = await supabase
        .from("challenges")
        .select("*")
        .or(`challenger_cloudkit_user_id.eq.${cloudkitUserId},challenged_cloudkit_user_id.eq.${cloudkitUserId}`)
        .in("status", ["pending", "active", "completed"])
        .order("created_at", { ascending: false })
        .limit(50);
      if (error) throw error;

      return jsonResponse({ challenges: data ?? [] });
    }

    // ----- UPDATE PROGRESS -----
    if (action === "update_progress") {
      if (!cloudkitUserId) return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);
      // F9 phase 1: banned players' challenge progress is frozen at
      // pre-ban value. DataManager still calls this on XP gain, so the
      // gate prevents the banned user from winning active challenges.
      if (await isBanned(supabase, cloudkitUserId)) return bannedResponse();
      const progressDelta = Math.max(0, parseInt(body.progress_delta ?? "0", 10));
      if (progressDelta <= 0) return jsonResponse({ success: true, updated: 0 });

      // Find all active challenges for this user
      const { data: active, error: fetchErr } = await supabase
        .from("challenges")
        .select("*")
        .in("status", ["active"])
        .or(`challenger_cloudkit_user_id.eq.${cloudkitUserId},challenged_cloudkit_user_id.eq.${cloudkitUserId}`);
      if (fetchErr) throw fetchErr;

      let updated = 0;
      for (const c of (active ?? [])) {
        const isChallenger = c.challenger_cloudkit_user_id === cloudkitUserId;
        const progressField = isChallenger ? "challenger_progress" : "challenged_progress";
        const currentProgress = isChallenger ? (c.challenger_progress ?? 0) : (c.challenged_progress ?? 0);
        const newProgress = currentProgress + progressDelta;

        const updates: Record<string, unknown> = { [progressField]: newProgress };

        // Check if target reached (if target_value is set)
        let justCompleted = false;
        if (c.target_value && newProgress >= c.target_value) {
          updates.status = "completed";
          updates.winner_cloudkit_user_id = cloudkitUserId;
          updates.completed_at = new Date().toISOString();
          justCompleted = true;
        }

        await supabase.from("challenges").update(updates).eq("id", c.id);

        // F2 v1: pay out the winner's escrow inline when the challenge
        // transitions from active → completed. Reload the row with the
        // winner field set so settleChallengeEscrow has the full state.
        if (justCompleted) {
          const merged = { ...c, ...updates };
          await settleChallengeEscrow(supabase, merged, "winner");
        }

        updated++;
      }

      return jsonResponse({ success: true, updated });
    }

    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (err) {
    console.error("challenge-proxy error:", err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
