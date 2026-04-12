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

      if (!cloudkitUserId || !targetId || !challengeType) {
        return jsonResponse({ error: "Missing required fields" }, 400);
      }
      if (cloudkitUserId === targetId) {
        return jsonResponse({ error: "Cannot challenge yourself" }, 400);
      }

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
        })
        .select("*")
        .single();
      if (error) throw error;

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

        return jsonResponse({ success: true, status: "declined" });
      }
    }

    // ----- GET MY CHALLENGES -----
    if (action === "get_my_challenges") {
      if (!cloudkitUserId) return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      // Expire any pending/active challenges past their expiry
      await supabase
        .from("challenges")
        .update({ status: "expired" })
        .in("status", ["pending", "active"])
        .lt("expires_at", new Date().toISOString());

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
        if (c.target_value && newProgress >= c.target_value) {
          updates.status = "completed";
          updates.winner_cloudkit_user_id = cloudkitUserId;
          updates.completed_at = new Date().toISOString();
        }

        await supabase.from("challenges").update(updates).eq("id", c.id);
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
