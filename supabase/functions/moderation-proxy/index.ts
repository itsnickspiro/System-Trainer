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

// F9 phase 1: write-path shadowban gate (same helper used across all proxies).
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

serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  // Two-tier auth: normal app secret for player-facing actions,
  // admin secret for review/ban actions.
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

    // ── Check master switch ─────────────────────────────────────────────
    const { data: modSwitch } = await supabase
      .from("remote_config")
      .select("value")
      .eq("key", "moderation_enabled")
      .eq("is_active", true)
      .maybeSingle();
    if (modSwitch?.value === "false") {
      return jsonResponse({ error: "Moderation is currently disabled" }, 503);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PLAYER-FACING ACTIONS (app secret)
    // ═══════════════════════════════════════════════════════════════════

    // ── REPORT PLAYER ─────────────────────────────────────────────────
    if (action === "report_player") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      // Banned players can't file reports (prevents harassment-via-reports)
      if (await isBanned(supabase, cloudkitUserId))
        return jsonResponse(
          { success: false, error: "service_unavailable" },
          503,
        );

      const reportedId = (body.reported_cloudkit_user_id ?? "").toString();
      const reportedPlayerId = (body.reported_player_id ?? "").toString() || null;
      const reason = (body.reason ?? "").toString();
      const description = (body.description ?? "").toString().slice(0, 1000);

      if (!reportedId || !reason) {
        return jsonResponse(
          { error: "Missing reported_cloudkit_user_id or reason" },
          400,
        );
      }
      if (cloudkitUserId === reportedId) {
        return jsonResponse({ error: "Cannot report yourself" }, 400);
      }

      const validReasons = [
        "cheating",
        "harassment",
        "impersonation",
        "inappropriate_name",
        "inappropriate_avatar",
        "other",
      ];
      if (!validReasons.includes(reason)) {
        return jsonResponse({ error: "Invalid reason" }, 400);
      }

      // Rate limit: max N reports per reporter per day
      let maxPerDay = 5;
      try {
        const { data: cfg } = await supabase
          .from("remote_config")
          .select("value")
          .eq("key", "moderation_report_rate_limit")
          .eq("is_active", true)
          .maybeSingle();
        const parsed = cfg?.value ? parseInt(String(cfg.value), 10) : NaN;
        if (Number.isFinite(parsed) && parsed > 0) maxPerDay = parsed;
      } catch (_) {
        /* use default */
      }

      const { count: todayCount } = await supabase
        .from("player_reports")
        .select("*", { count: "exact", head: true })
        .eq("reporter_cloudkit_user_id", cloudkitUserId)
        .gte("created_at", new Date(Date.now() - 86400000).toISOString());

      if ((todayCount ?? 0) >= maxPerDay) {
        return jsonResponse(
          {
            error: "Report limit reached",
            max_per_day: maxPerDay,
          },
          429,
        );
      }

      // Deduplicate: one report per reporter/target/day
      const { data: existing } = await supabase
        .from("player_reports")
        .select("id")
        .eq("reporter_cloudkit_user_id", cloudkitUserId)
        .eq("reported_cloudkit_user_id", reportedId)
        .gte("created_at", new Date(Date.now() - 86400000).toISOString())
        .limit(1)
        .maybeSingle();

      if (existing) {
        return jsonResponse({
          success: true,
          already_reported: true,
          message: "You already reported this player today",
        });
      }

      const { error } = await supabase.from("player_reports").insert({
        reporter_cloudkit_user_id: cloudkitUserId,
        reported_cloudkit_user_id: reportedId,
        reported_player_id: reportedPlayerId,
        reason,
        description: description || null,
      });
      if (error) throw error;

      return jsonResponse({ success: true });
    }

    // ── GET MY REPORTS ────────────────────────────────────────────────
    if (action === "get_my_reports") {
      if (!cloudkitUserId)
        return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      const { data, error } = await supabase
        .from("player_reports")
        .select("id, reported_cloudkit_user_id, reason, status, created_at")
        .eq("reporter_cloudkit_user_id", cloudkitUserId)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;

      return jsonResponse({ reports: data ?? [] });
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ADMIN ACTIONS (admin secret only)
    // ═══════════════════════════════════════════════════════════════════

    if (!isAdminAuth) {
      // All remaining actions require admin auth
      return jsonResponse({ error: "Unknown action" }, 400);
    }

    // ── LIST PENDING REPORTS ──────────────────────────────────────────
    if (action === "list_pending") {
      const statusFilter = body.status_filter ?? "pending";
      const limit = Math.min(parseInt(body.limit ?? "50", 10), 200);

      const { data, error, count } = await supabase
        .from("player_reports")
        .select("*", { count: "exact" })
        .eq("status", statusFilter)
        .order("created_at", { ascending: true })
        .limit(limit);
      if (error) throw error;

      return jsonResponse({ reports: data ?? [], total: count ?? 0 });
    }

    // ── LIST FLAGGED ─────────────────────────────────────────────────
    if (action === "list_flagged") {
      const unreviewedOnly = body.unreviewed_only !== false;
      const limit = Math.min(parseInt(body.limit ?? "50", 10), 200);

      let query = supabase
        .from("moderation_flags")
        .select("*", { count: "exact" })
        .order("auto_detected_at", { ascending: false })
        .limit(limit);

      if (unreviewedOnly) {
        query = query.is("reviewed_at", null);
      }

      const { data, error, count } = await query;
      if (error) throw error;

      return jsonResponse({ flags: data ?? [], total: count ?? 0 });
    }

    // ── ACTION REPORT ────────────────────────────────────────────────
    if (action === "action_report") {
      const reportId = body.report_id ?? "";
      const newStatus = body.new_status ?? "";
      const actionTaken = body.action_taken ?? null;
      const reviewerName = body.reviewer ?? "admin";

      if (!reportId || !newStatus) {
        return jsonResponse({ error: "Missing report_id or new_status" }, 400);
      }

      const validStatuses = [
        "reviewing",
        "actioned",
        "dismissed",
        "duplicate",
      ];
      if (!validStatuses.includes(newStatus)) {
        return jsonResponse({ error: "Invalid status" }, 400);
      }

      const { error } = await supabase.rpc("admin_review_report", {
        p_report_id: reportId,
        p_reviewer: reviewerName,
        p_status: newStatus,
        p_action_taken: actionTaken,
      });
      if (error) throw error;

      return jsonResponse({ success: true });
    }

    // ── REVIEW FLAG ──────────────────────────────────────────────────
    if (action === "review_flag") {
      const flagId = body.flag_id ?? "";
      const resolution = body.resolution ?? "";
      const reviewerName = body.reviewer ?? "admin";

      if (!flagId || !resolution) {
        return jsonResponse({ error: "Missing flag_id or resolution" }, 400);
      }

      const { error } = await supabase.rpc("admin_review_flag", {
        p_flag_id: flagId,
        p_reviewer: reviewerName,
        p_resolution: resolution,
      });
      if (error) throw error;

      return jsonResponse({ success: true });
    }

    // ── BAN PLAYER ───────────────────────────────────────────────────
    if (action === "ban_player") {
      const targetId = (body.target_cloudkit_user_id ?? "").toString();
      const banReason = (body.reason ?? "admin_action").toString();
      if (!targetId) {
        return jsonResponse(
          { error: "Missing target_cloudkit_user_id" },
          400,
        );
      }

      const { error } = await supabase.rpc("admin_ban_player", {
        p_cloudkit_user_id: targetId,
        p_reason: banReason,
      });
      if (error) throw error;

      return jsonResponse({ success: true, banned: targetId });
    }

    // ── UNBAN PLAYER ─────────────────────────────────────────────────
    if (action === "unban_player") {
      const targetId = (body.target_cloudkit_user_id ?? "").toString();
      if (!targetId) {
        return jsonResponse(
          { error: "Missing target_cloudkit_user_id" },
          400,
        );
      }

      const { error } = await supabase.rpc("admin_unban_player", {
        p_cloudkit_user_id: targetId,
      });
      if (error) throw error;

      return jsonResponse({ success: true, unbanned: targetId });
    }

    // ── GET PLAYER MODERATION SUMMARY ────────────────────────────────
    if (action === "get_player_summary") {
      const targetId = (body.target_cloudkit_user_id ?? "").toString();
      if (!targetId) {
        return jsonResponse(
          { error: "Missing target_cloudkit_user_id" },
          400,
        );
      }

      const [reportsAgainst, flagsAgainst, profile] = await Promise.all([
        supabase
          .from("player_reports")
          .select("*")
          .eq("reported_cloudkit_user_id", targetId)
          .order("created_at", { ascending: false })
          .limit(20),
        supabase
          .from("moderation_flags")
          .select("*")
          .eq("cloudkit_user_id", targetId)
          .order("auto_detected_at", { ascending: false })
          .limit(20),
        supabase
          .from("player_profiles")
          .select(
            "cloudkit_user_id, display_name, player_id, level, total_xp, is_banned, banned_at, ban_reason, system_credits, lifetime_credits_earned",
          )
          .eq("cloudkit_user_id", targetId)
          .maybeSingle(),
      ]);

      return jsonResponse({
        profile: profile.data,
        reports: reportsAgainst.data ?? [],
        flags: flagsAgainst.data ?? [],
      });
    }

    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (err) {
    console.error("moderation-proxy error:", err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
