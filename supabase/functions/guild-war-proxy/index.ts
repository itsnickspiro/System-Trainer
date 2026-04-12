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

    // Check master switch
    const { data: sw } = await supabase
      .from("remote_config")
      .select("value")
      .eq("key", "guild_wars_enabled")
      .eq("is_active", true)
      .maybeSingle();
    if (sw?.value === "false") {
      return jsonResponse({ error: "Guild wars are currently disabled" }, 503);
    }

    // ── DECLARE WAR ───────────────────────────────────────────────────
    if (action === "declare_war") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);
      if (await isBanned(supabase, cloudkitUserId))
        return jsonResponse({ success: false, error: "service_unavailable" }, 503);

      const targetGuildId = (body.target_guild_id ?? "").toString();
      const metricType = (body.metric_type ?? "xp_total").toString();
      const durationDays = Math.min(
        Math.max(parseInt(body.duration_days ?? "3", 10), 1),
        7,
      );

      if (!targetGuildId)
        return jsonResponse({ error: "Missing target_guild_id" }, 400);

      // Verify caller is guild leader
      const { data: membership } = await supabase
        .from("guild_members")
        .select("guild_id, role")
        .eq("cloudkit_user_id", cloudkitUserId)
        .maybeSingle();
      if (!membership || membership.role !== "owner")
        return jsonResponse(
          { error: "Only the guild leader can declare war" },
          403,
        );

      const myGuildId = membership.guild_id;
      if (myGuildId === targetGuildId)
        return jsonResponse({ error: "Cannot declare war on your own guild" }, 400);

      // Check min guild level
      let minLevel = 2;
      try {
        const { data: cfg } = await supabase
          .from("remote_config")
          .select("value")
          .eq("key", "guild_war_min_guild_level")
          .eq("is_active", true)
          .maybeSingle();
        const p = cfg?.value ? parseInt(String(cfg.value), 10) : NaN;
        if (Number.isFinite(p) && p > 0) minLevel = p;
      } catch (_) { /* default */ }

      const { data: myGuild } = await supabase
        .from("guilds")
        .select("level, name")
        .eq("id", myGuildId)
        .single();
      if ((myGuild?.level ?? 1) < minLevel)
        return jsonResponse(
          { error: `Guild must be level ${minLevel}+ to declare war` },
          400,
        );

      // Check no existing active/pending war between these guilds
      const { data: existing } = await supabase
        .from("guild_wars")
        .select("id")
        .or(
          `and(challenger_guild_id.eq.${myGuildId},challenged_guild_id.eq.${targetGuildId}),and(challenger_guild_id.eq.${targetGuildId},challenged_guild_id.eq.${myGuildId})`,
        )
        .in("status", ["pending_acceptance", "active"])
        .limit(1)
        .maybeSingle();
      if (existing)
        return jsonResponse(
          { error: "You already have an active war with this guild" },
          400,
        );

      const { data: targetGuild } = await supabase
        .from("guilds")
        .select("name")
        .eq("id", targetGuildId)
        .single();

      // Read prize GP from remote config
      let prizeGp = 250;
      try {
        const { data: cfg } = await supabase
          .from("remote_config")
          .select("value")
          .eq("key", "guild_war_prize_gp_per_member")
          .eq("is_active", true)
          .maybeSingle();
        const p = cfg?.value ? parseInt(String(cfg.value), 10) : NaN;
        if (Number.isFinite(p) && p > 0) prizeGp = p;
      } catch (_) { /* default */ }

      const { data: war, error } = await supabase
        .from("guild_wars")
        .insert({
          challenger_guild_id: myGuildId,
          challenged_guild_id: targetGuildId,
          challenger_guild_name: myGuild?.name,
          challenged_guild_name: targetGuild?.name,
          metric_type: metricType,
          duration_days: durationDays,
          status: "pending_acceptance",
          prize_gp_per_member: prizeGp,
        })
        .select("*")
        .single();
      if (error) throw error;

      return jsonResponse({ success: true, war });
    }

    // ── ACCEPT / DECLINE WAR ──────────────────────────────────────────
    if (action === "accept_war" || action === "decline_war") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);
      if (await isBanned(supabase, cloudkitUserId))
        return jsonResponse({ success: false, error: "service_unavailable" }, 503);

      const warId = (body.war_id ?? "").toString();
      if (!warId)
        return jsonResponse({ error: "Missing war_id" }, 400);

      // Verify caller is leader of the challenged guild
      const { data: membership } = await supabase
        .from("guild_members")
        .select("guild_id, role")
        .eq("cloudkit_user_id", cloudkitUserId)
        .maybeSingle();
      if (!membership || membership.role !== "owner")
        return jsonResponse(
          { error: "Only the guild leader can respond to wars" },
          403,
        );

      const { data: war } = await supabase
        .from("guild_wars")
        .select("*")
        .eq("id", warId)
        .single();
      if (!war)
        return jsonResponse({ error: "War not found" }, 404);
      if (war.challenged_guild_id !== membership.guild_id)
        return jsonResponse(
          { error: "Only the challenged guild's leader can respond" },
          403,
        );
      if (war.status !== "pending_acceptance")
        return jsonResponse({ error: "War is no longer pending" }, 400);

      if (action === "decline_war") {
        await supabase
          .from("guild_wars")
          .update({ status: "declined" })
          .eq("id", warId);
        return jsonResponse({ success: true, status: "declined" });
      }

      // Accept: freeze rosters + snapshot starting values
      const startsAt = new Date();
      const endsAt = new Date();
      endsAt.setDate(endsAt.getDate() + (war.duration_days ?? 3));

      await supabase
        .from("guild_wars")
        .update({
          status: "active",
          accepted_at: startsAt.toISOString(),
          starts_at: startsAt.toISOString(),
          ends_at: endsAt.toISOString(),
        })
        .eq("id", warId);

      // Freeze rosters: snapshot current members of both guilds
      for (const guildId of [
        war.challenger_guild_id,
        war.challenged_guild_id,
      ]) {
        const { data: members } = await supabase
          .from("guild_members")
          .select("cloudkit_user_id, display_name")
          .eq("guild_id", guildId);

        for (const member of members ?? []) {
          // Get starting value from player_profiles
          const { data: profile } = await supabase
            .from("player_profiles")
            .select("total_xp")
            .eq("cloudkit_user_id", member.cloudkit_user_id)
            .maybeSingle();

          await supabase.from("guild_war_participants").insert({
            war_id: warId,
            guild_id: guildId,
            cloudkit_user_id: member.cloudkit_user_id,
            display_name: member.display_name,
            starting_value: profile?.total_xp ?? 0,
            current_value: profile?.total_xp ?? 0,
          });
        }
      }

      return jsonResponse({ success: true, status: "active" });
    }

    // ── GET ACTIVE WARS FOR MY GUILD ──────────────────────────────────
    if (action === "get_active_wars") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      const { data: membership } = await supabase
        .from("guild_members")
        .select("guild_id")
        .eq("cloudkit_user_id", cloudkitUserId)
        .maybeSingle();
      if (!membership)
        return jsonResponse({ wars: [] });

      const guildId = membership.guild_id;
      const { data, error } = await supabase
        .from("guild_wars")
        .select("*")
        .or(
          `challenger_guild_id.eq.${guildId},challenged_guild_id.eq.${guildId}`,
        )
        .in("status", ["pending_acceptance", "active", "completed"])
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;

      return jsonResponse({ wars: data ?? [], my_guild_id: guildId });
    }

    // ── GET WAR DETAIL ────────────────────────────────────────────────
    if (action === "get_war_detail") {
      const warId = (body.war_id ?? "").toString();
      if (!warId)
        return jsonResponse({ error: "Missing war_id" }, 400);

      const { data: war } = await supabase
        .from("guild_wars")
        .select("*")
        .eq("id", warId)
        .single();
      if (!war) return jsonResponse({ error: "War not found" }, 404);

      // Lazy resolve if expired
      if (
        war.status === "active" &&
        !war.resolved_at &&
        new Date(war.ends_at) < new Date()
      ) {
        await supabase.rpc("resolve_guild_war", { p_war_id: warId });
        // Re-fetch
        const { data: updated } = await supabase
          .from("guild_wars")
          .select("*")
          .eq("id", warId)
          .single();
        if (updated) Object.assign(war, updated);
      }

      // Get participants grouped by guild
      const { data: participants } = await supabase
        .from("guild_war_participants")
        .select("*")
        .eq("war_id", warId)
        .order("current_value", { ascending: false });

      const challengerMembers = (participants ?? []).filter(
        (p: Record<string, unknown>) =>
          p.guild_id === war.challenger_guild_id,
      );
      const challengedMembers = (participants ?? []).filter(
        (p: Record<string, unknown>) =>
          p.guild_id === war.challenged_guild_id,
      );

      // Compute live totals (delta from starting)
      const challengerTotal = challengerMembers.reduce(
        (sum: number, p: Record<string, unknown>) =>
          sum +
          Math.max(
            0,
            ((p.current_value as number) ?? 0) -
              ((p.starting_value as number) ?? 0),
          ),
        0,
      );
      const challengedTotal = challengedMembers.reduce(
        (sum: number, p: Record<string, unknown>) =>
          sum +
          Math.max(
            0,
            ((p.current_value as number) ?? 0) -
              ((p.starting_value as number) ?? 0),
          ),
        0,
      );

      return jsonResponse({
        war,
        challenger_members: challengerMembers,
        challenged_members: challengedMembers,
        challenger_total: challengerTotal,
        challenged_total: challengedTotal,
      });
    }

    // ── CLAIM WAR REWARD ──────────────────────────────────────────────
    if (action === "claim_war_reward") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);
      const warId = (body.war_id ?? "").toString();
      if (!warId)
        return jsonResponse({ error: "Missing war_id" }, 400);

      const { data: war } = await supabase
        .from("guild_wars")
        .select("*")
        .eq("id", warId)
        .single();
      if (!war || war.status !== "completed")
        return jsonResponse({ error: "War not completed" }, 400);
      if (war.is_draw)
        return jsonResponse({ error: "War ended in a draw — no rewards" }, 400);

      // Verify caller was on the winning team
      const { data: participation } = await supabase
        .from("guild_war_participants")
        .select("*")
        .eq("war_id", warId)
        .eq("cloudkit_user_id", cloudkitUserId)
        .maybeSingle();
      if (!participation)
        return jsonResponse({ error: "You were not in this war" }, 400);
      if (participation.guild_id !== war.winner_guild_id)
        return jsonResponse({ error: "Your guild did not win" }, 400);

      // Check already claimed (use a jsonb field on the war or a separate check)
      // Simple approach: check credit_transactions for this user + war reference
      const { data: existingClaim } = await supabase
        .from("credit_transactions")
        .select("id")
        .eq("cloudkit_user_id", cloudkitUserId)
        .eq("transaction_type", "guild_war_reward")
        .eq("reference_key", warId)
        .limit(1)
        .maybeSingle();
      if (existingClaim)
        return jsonResponse({ success: true, already_claimed: true });

      const prizeGp = war.prize_gp_per_member ?? 250;
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
        transaction_type: "guild_war_reward",
        reference_key: warId,
      });

      return jsonResponse({ success: true, prize_gp: prizeGp });
    }

    // ── ADMIN: Force resolve or cancel a war ─────────────────────────
    if (action === "admin_resolve_war" || action === "admin_cancel_war") {
      const { data: me } = await supabase.from("player_profiles").select("is_admin").eq("cloudkit_user_id", cloudkitUserId).maybeSingle();
      if (!me?.is_admin) return jsonResponse({ error: "admin_required" }, 403);
      const warId = (body.war_id ?? "").toString();
      if (!warId) return jsonResponse({ error: "war_id required" }, 400);
      if (action === "admin_cancel_war") {
        await supabase.from("guild_wars").update({ status: "cancelled" }).eq("id", warId);
        return jsonResponse({ success: true, status: "cancelled" });
      }
      const result = await supabase.rpc("resolve_guild_war", { p_war_id: warId });
      return jsonResponse(result.data ?? { success: true });
    }

    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (err) {
    console.error("guild-war-proxy error:", err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
