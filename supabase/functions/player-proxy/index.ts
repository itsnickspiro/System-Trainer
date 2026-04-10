import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-app-secret",
};

// ── Rate limiting ──────────────────────────────────────────────────────────
// Per-action budgets. Each entry is [maxCallsPerWindow, windowSeconds].
// Budgets are generous for normal usage and aggressive for destructive
// actions. `delete_account` is the most restrictive: a user shouldn't
// legitimately delete their account more than a handful of times per day.
const DESTRUCTIVE_ACTIONS = new Set(["delete_account", "revoke_siwa"]);

function redactId(id: string): string {
  if (id.length <= 8) return "***";
  return id.substring(0, 4) + "..." + id.substring(id.length - 4);
}

const RATE_BUDGETS: Record<string, [number, number]> = {
  get_profile:          [120, 60],   // 120 reads/min — fine for normal app usage
  get_public_profile:   [60, 60],    // 60 reads/min — viewing other players
  upsert_profile:       [60, 60],    // 60 writes/min — generous (usually 1-2/min)
  save_backup:          [10, 60],    // 10 backups/min — usually 1-2 per session
  mark_override_applied:[10, 60],
  add_credits:          [30, 60],    // 30 credit txns/min — quest completion burst
  get_credit_history:   [30, 60],
  link_apple_id:        [5, 60],     // 5 link attempts/min — suspicious above this
  lookup_by_apple_id:   [10, 60],
  store_auth_code:      [5, 60],     // 5 auth-code stores/min
  delete_account:       [3, 3600],   // 3 deletes/hour — destructive action
  revoke_siwa:          [3, 3600],   // 3 revokes/hour
};

async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  action: string,
): Promise<{ allowed: boolean; status: number }> {
  const budget = RATE_BUDGETS[action];
  if (!budget || !userId) return { allowed: true, status: 200 };
  const [max, windowSec] = budget;
  try {
    const { data, error } = await supabase.rpc("rate_limit_check", {
      p_user_id: userId,
      p_action: action,
      p_max_per_window: max,
      p_window_seconds: windowSec,
    });
    if (error) {
      console.error(`rate_limit_check RPC failed for ${redactId(userId)}:${action}:`, error);
      if (DESTRUCTIVE_ACTIONS.has(action)) {
        return { allowed: false, status: 503 };
      }
      return { allowed: true, status: 200 };
    }
    if (data === false) {
      return { allowed: false, status: 429 };
    }
    return { allowed: true, status: 200 };
  } catch (e) {
    console.error(`rate_limit_check threw for ${redactId(userId)}:${action}:`, e);
    if (DESTRUCTIVE_ACTIONS.has(action)) {
      return { allowed: false, status: 503 };
    }
    return { allowed: true, status: 200 };
  }
}

function rateLimitedResponse(action: string) {
  return new Response(
    JSON.stringify({
      error: "Too many requests",
      action,
      retry_after_seconds: 60,
    }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": "60",
      },
    }
  );
}

// ── Sign in with Apple server-side REST revocation ────────────────────────
// Apple Guideline 5.1.1(v) compliance. When a user taps Delete Account we
// should not only wipe our own database — we should also invalidate their
// Sign in with Apple session at Apple's end so the credential can't be
// silently re-used. The REST flow is:
//
//   1. Build a short-lived ES256 "client_secret" JWT signed with the
//      Apple Services Key (.p8 file, Sign in with Apple capability)
//   2. POST the authorization_code (captured from the original SIWA sign-in)
//      to https://appleid.apple.com/auth/token to exchange it for a
//      refresh_token
//   3. POST the refresh_token to https://appleid.apple.com/auth/revoke
//
// Required environment variables (set in Supabase Vault → Edge Functions):
//   APPLE_TEAM_ID           — 10-char Apple Developer Team ID
//   APPLE_KEY_ID            — 10-char Key ID from the Services Key
//   APPLE_P8_KEY            — contents of the .p8 file (entire PEM, including
//                             BEGIN/END PRIVATE KEY lines)
//   APPLE_CLIENT_ID         — bundle identifier used as the SIWA service ID
//                             (defaults to com.SpiroTechnologies.RPT if unset)
//
// If any of these are missing we log a warning and return false so the
// caller falls back to client-side best-effort revocation. Delete Account
// still proceeds — we never block a deletion on a missing Apple key.

interface AppleRevokeResult {
  success: boolean;
  skipped?: boolean;
  reason?: string;
  detail?: string;
}

// PEM → raw key bytes for ES256 signing via SubtleCrypto.importKey
function pemToPkcs8Bytes(pem: string): Uint8Array {
  const cleaned = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64UrlEncode(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Build the Apple client_secret JWT. This is a short-lived (3-minute) JWT
// the Apple token endpoint accepts in place of a static secret. It must be
// signed with ES256 using the .p8 key generated in Apple Developer Portal.
async function buildAppleClientSecret(
  teamId: string,
  keyId: string,
  clientId: string,
  p8Pem: string,
): Promise<string> {
  const header = { alg: "ES256", kid: keyId };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: teamId,
    iat: now,
    exp: now + 180, // Apple rejects JWTs with exp > 6 months; 3 minutes is safe
    aud: "https://appleid.apple.com",
    sub: clientId,
  };
  const signingInput =
    base64UrlEncode(JSON.stringify(header)) +
    "." +
    base64UrlEncode(JSON.stringify(payload));

  // Import the PKCS#8 private key for signing
  const keyBytes = pemToPkcs8Bytes(p8Pem);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  // Sign. The output is 64 raw bytes (r||s) per WebCrypto spec, which
  // is exactly what JWT ES256 expects (no DER wrapping).
  const signatureBytes = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: { name: "SHA-256" } },
      cryptoKey,
      new TextEncoder().encode(signingInput),
    ),
  );

  return signingInput + "." + base64UrlEncode(signatureBytes);
}

async function appleRevokeSIWA(
  authorizationCode: string,
): Promise<AppleRevokeResult> {
  const teamId = Deno.env.get("APPLE_TEAM_ID") ?? "";
  const keyId = Deno.env.get("APPLE_KEY_ID") ?? "";
  const p8Pem = Deno.env.get("APPLE_P8_KEY") ?? "";
  const clientId = Deno.env.get("APPLE_CLIENT_ID") ?? "com.SpiroTechnologies.RPT";

  if (!teamId || !keyId || !p8Pem) {
    console.warn("appleRevokeSIWA: Apple Services Key not configured in Vault — skipping server-side revocation");
    return { success: false, skipped: true, reason: "apple_key_not_configured" };
  }
  if (!authorizationCode) {
    return { success: false, skipped: true, reason: "no_auth_code_on_profile" };
  }

  try {
    const clientSecret = await buildAppleClientSecret(teamId, keyId, clientId, p8Pem);

    // Step 1: exchange authorization_code → refresh_token
    const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        code: authorizationCode,
        grant_type: "authorization_code",
      }),
    });

    if (!tokenRes.ok) {
      const errText = await tokenRes.text();
      console.error("appleRevokeSIWA: token exchange failed", tokenRes.status, errText);
      return { success: false, reason: "token_exchange_failed", detail: `${tokenRes.status}: ${errText}` };
    }

    const tokenData = await tokenRes.json();
    const refreshToken: string | undefined = tokenData.refresh_token;
    if (!refreshToken) {
      return { success: false, reason: "no_refresh_token_returned" };
    }

    // Step 2: revoke the refresh token
    const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        token: refreshToken,
        token_type_hint: "refresh_token",
      }),
    });

    if (!revokeRes.ok) {
      const errText = await revokeRes.text();
      console.error("appleRevokeSIWA: revoke failed", revokeRes.status, errText);
      return { success: false, reason: "revoke_failed", detail: `${revokeRes.status}: ${errText}` };
    }

    return { success: true };
  } catch (e) {
    console.error("appleRevokeSIWA: exception", e);
    return { success: false, reason: "exception", detail: String(e) };
  }
}

// Whitelist of columns that upsert_profile is allowed to write to
// player_profiles. Anything not on this list is silently ignored to
// prevent injection of arbitrary fields from the client.
const UPSERT_ALLOWED_COLUMNS = [
  "display_name",
  "level",
  "total_xp",
  "current_streak",
  "longest_streak",
  "active_anime_plan_key",
  "avatar_key",
  "app_version",
  "device_model",
  "weight_kg",
  "height_cm",
  "date_of_birth",
  "biological_sex",
  "fitness_goal",
  "diet_type",
  "player_class",
  "gym_environment",
  "use_metric",
  "activity_level_index",
  "goal_survey_completed",
  "goal_survey_days_per_week",
  "goal_survey_split_raw",
  "goal_survey_session_minutes",
  "goal_survey_intensity_raw",
  "goal_survey_focus_areas_raw",
  "goal_survey_cardio_raw",
  "rival_cloudkit_user_id",
  "rival_display_name",
  "guild_id",
  "guild_name",
  "guild_role",
  "rank",
  "system_credits",
  "lifetime_credits_earned",
  "total_workouts_logged",
  "total_quests_completed",
  "total_days_active",
  "daily_calorie_goal",
  "daily_protein_goal",
  "daily_step_goal",
  "daily_water_goal_oz",
  "onboarding_completed",
  "is_profile_public",
  "showcase_achievement_keys",
];

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  if (!appSecret || !incomingSecret || incomingSecret !== appSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }

  try {
    const body = await req.json();
    const action = body.action ?? "get_profile";
    const cloudkitUserId = body.cloudkit_user_id ?? "";

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    // ── Rate limit check (before any real work) ──────────────────────────
    // For actions keyed by cloudkit_user_id, the rate limit is per-user.
    // For actions that don't require cloudkit_user_id (lookup_by_apple_id),
    // we rate-limit by apple_user_id instead so the same caller can't
    // brute-force the lookup endpoint with different Apple IDs.
    {
      const rateLimitKey =
        action === "lookup_by_apple_id"
          ? `apple:${body.apple_user_id ?? ""}`
          : cloudkitUserId;
      if (rateLimitKey) {
        const rl = await checkRateLimit(supabase, rateLimitKey, action);
        if (!rl.allowed) return rateLimitedResponse(action);
      }
    }

    // LOOKUP BY APPLE ID — does NOT require cloudkit_user_id
    if (action === "lookup_by_apple_id") {
      const appleUserId: string = body.apple_user_id ?? "";
      if (!appleUserId) {
        return new Response(JSON.stringify({ error: "apple_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      const { data, error } = await supabase.from("player_profiles").select("*").eq("apple_user_id", appleUserId).limit(1).maybeSingle();
      if (error && error.code !== "PGRST116") throw error;
      if (data) {
        return new Response(JSON.stringify({ found: true, profile: data }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({ found: false }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // All other actions require cloudkit_user_id
    if (!cloudkitUserId) return new Response(JSON.stringify({ error: "cloudkit_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    // GET PUBLIC PROFILE — returns limited public info for another player.
    // Privacy-safe: no weight, height, age, diet, or personal details.
    if (action === "get_public_profile") {
      const targetId = body.target_cloudkit_user_id ?? body.target_player_id ?? "";
      if (!targetId) {
        return new Response(JSON.stringify({ error: "target_cloudkit_user_id or target_player_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      // Look up by player_id or cloudkit_user_id
      let query = supabase.from("player_profiles").select(
        "player_id, cloudkit_user_id, display_name, avatar_key, level, total_xp, current_streak, longest_streak, player_class, fitness_goal, guild_id, guild_name, guild_role, is_profile_public, showcase_achievement_keys, total_workouts_logged, total_quests_completed, total_days_active"
      );
      if (targetId.startsWith("ST-") || targetId.startsWith("RPT-")) {
        query = query.eq("player_id", targetId);
      } else {
        query = query.eq("cloudkit_user_id", targetId);
      }
      const { data, error } = await query.maybeSingle();
      if (error && error.code !== "PGRST116") throw error;
      if (!data) {
        return new Response(JSON.stringify({ success: false, error: "not_found" }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      // Respect privacy setting
      if (data.is_profile_public === false) {
        return new Response(JSON.stringify({
          success: true,
          is_private: true,
          display_name: data.display_name,
          avatar_key: data.avatar_key,
          player_id: data.player_id,
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      return new Response(JSON.stringify({
        success: true,
        is_private: false,
        player_id: data.player_id,
        cloudkit_user_id: data.cloudkit_user_id,
        display_name: data.display_name,
        avatar_key: data.avatar_key,
        level: data.level,
        total_xp: data.total_xp,
        current_streak: data.current_streak,
        longest_streak: data.longest_streak,
        player_class: data.player_class,
        fitness_goal: data.fitness_goal,
        guild_id: data.guild_id,
        guild_name: data.guild_name,
        guild_role: data.guild_role,
        showcase_achievement_keys: data.showcase_achievement_keys ?? [],
        total_workouts_logged: data.total_workouts_logged,
        total_quests_completed: data.total_quests_completed,
        total_days_active: data.total_days_active,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // GET PROFILE — returns the row as flat top-level fields (no envelope).
    // The previous { profile, override } envelope is dropped per the new
    // shared contract; the override system is unused on the client.
    if (action === "get_profile") {
      const { data, error } = await supabase.from("player_profiles").select("*").eq("cloudkit_user_id", cloudkitUserId).maybeSingle();
      if (error && error.code !== "PGRST116") throw error;
      if (!data) {
        return new Response(JSON.stringify({ success: false, error: "not_found" }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({ success: true, ...data }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // UPSERT PROFILE — reads FLAT top-level fields from body (NOT body.profile).
    // Only whitelisted columns are written, and undefined/null values are
    // skipped so the client can do partial updates without nuking existing data.
    if (action === "upsert_profile") {
      const upsertPayload: Record<string, unknown> = {
        cloudkit_user_id: cloudkitUserId,
        updated_at: new Date().toISOString(),
      };
      for (const key of UPSERT_ALLOWED_COLUMNS) {
        if (body[key] !== undefined && body[key] !== null) {
          upsertPayload[key] = body[key];
        }
      }
      const { data, error } = await supabase.from("player_profiles").upsert(upsertPayload, { onConflict: "cloudkit_user_id" }).select().single();
      if (error) throw error;
      return new Response(JSON.stringify({ success: true, profile: data }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // SAVE BACKUP — accepts flat top-level progression fields. Previously
    // this read body.backup which iOS never sends, so every backup row was
    // inserted with only cloudkit_user_id and zero progression data.
    if (action === "save_backup") {
      // Whitelist the columns we accept for backups so the client can't
      // inject arbitrary fields.
      const BACKUP_ALLOWED_COLUMNS = [
        "level",
        "total_xp",
        "current_streak",
        "longest_streak",
        "system_credits",
        "lifetime_credits_earned",
      ];
      const backupRow: Record<string, unknown> = {
        cloudkit_user_id: cloudkitUserId,
        backed_up_at: new Date().toISOString(),
      };
      // Backwards-compat: still accept body.backup if a future client sends it
      const nestedBackup = (body.backup ?? {}) as Record<string, unknown>;
      for (const key of BACKUP_ALLOWED_COLUMNS) {
        if (body[key] !== undefined && body[key] !== null) {
          backupRow[key] = body[key];
        } else if (nestedBackup[key] !== undefined && nestedBackup[key] !== null) {
          backupRow[key] = nestedBackup[key];
        }
      }
      const { error } = await supabase.from("player_backups").insert(backupRow);
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // MARK OVERRIDE APPLIED
    if (action === "mark_override_applied") {
      const { error } = await supabase.from("player_overrides").update({ is_active: false, applied_at: new Date().toISOString() }).eq("cloudkit_user_id", cloudkitUserId);
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // ADD CREDITS — atomic credit transaction
    if (action === "add_credits") {
      const amount: number = body.amount ?? 0;
      const txType: string = body.transaction_type ?? "quest_reward";
      const refKey: string = body.reference_key ?? "";
      const notes: string = body.notes ?? "";

      if (amount === 0) return new Response(JSON.stringify({ success: true, credits: 0 }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });

      // Get current balance
      const { data: profile, error: pErr } = await supabase.from("player_profiles").select("system_credits, lifetime_credits_earned").eq("cloudkit_user_id", cloudkitUserId).single();
      if (pErr) throw pErr;

      const currentBalance = profile?.system_credits ?? 0;
      const lifetimeEarned = profile?.lifetime_credits_earned ?? 0;
      const newBalance = Math.max(0, currentBalance + amount);
      const newLifetime = amount > 0 ? lifetimeEarned + amount : lifetimeEarned;

      // Update balance
      const { error: uErr } = await supabase.from("player_profiles").update({ system_credits: newBalance, lifetime_credits_earned: newLifetime, updated_at: new Date().toISOString() }).eq("cloudkit_user_id", cloudkitUserId);
      if (uErr) throw uErr;

      // Log transaction
      await supabase.from("credit_transactions").insert({ cloudkit_user_id: cloudkitUserId, amount, balance_after: newBalance, transaction_type: txType, reference_key: refKey, notes });

      // Return both the new balance AND the lifetime total in the keys
      // the iOS CreditUpdatePayload struct expects (system_credits +
      // lifetime_credits_earned). new_balance is kept for backwards
      // compatibility with any older client that decodes that field.
      return new Response(JSON.stringify({
        success: true,
        new_balance: newBalance,
        system_credits: newBalance,
        lifetime_credits_earned: newLifetime,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // GET CREDIT HISTORY
    if (action === "get_credit_history") {
      const limit = Math.min(parseInt(body.limit ?? "20", 10), 50);
      const { data, error } = await supabase.from("credit_transactions").select("*").eq("cloudkit_user_id", cloudkitUserId).order("created_at", { ascending: false }).limit(limit);
      if (error) throw error;
      return new Response(JSON.stringify({ transactions: data ?? [] }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // LINK APPLE ID — associate an Apple user id with the calling cloudkit user
    if (action === "link_apple_id") {
      const appleUserId: string = body.apple_user_id ?? "";
      const displayName: string | null = body.display_name ?? null;
      const email: string | null = body.email ?? null;
      // authorization_code is the one-time SIWA code used for
      // server-side revocation. It's only present on fresh sign-ins
      // (Apple does not return it when the credential comes from Keychain).
      // We store it on player_profiles so delete_account can call
      // /auth/revoke via appleRevokeSIWA.
      const authorizationCode: string | null = body.authorization_code ?? null;
      if (!appleUserId) {
        return new Response(JSON.stringify({ error: "apple_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      // Case A: Does another row already own this apple_user_id?
      const { data: existingByApple, error: lookupErr } = await supabase.from("player_profiles").select("*").eq("apple_user_id", appleUserId).limit(1).maybeSingle();
      if (lookupErr && lookupErr.code !== "PGRST116") throw lookupErr;

      if (existingByApple && existingByApple.cloudkit_user_id !== cloudkitUserId) {
        // Cross-device sign-in: return existing profile without overwriting.
        return new Response(JSON.stringify({
          success: true,
          linked: false,
          profile: existingByApple,
          message: "Apple ID is already linked to another device's profile. Returning existing profile data.",
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      // Does a row exist for the calling cloudkit_user_id?
      const { data: existingByCk, error: ckErr } = await supabase.from("player_profiles").select("*").eq("cloudkit_user_id", cloudkitUserId).maybeSingle();
      if (ckErr && ckErr.code !== "PGRST116") throw ckErr;

      if (existingByCk) {
        // Case B: update existing row with apple_user_id
        const updateRow: Record<string, unknown> = {
          apple_user_id: appleUserId,
          apple_user_id_linked_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        };
        // Only overwrite the auth code when we actually have a new one.
        // Apple only returns it on fresh sign-ins; a Keychain-restored
        // credential has no auth_code and we shouldn't wipe the stored value.
        if (authorizationCode) {
          updateRow.apple_authorization_code = authorizationCode;
        }
        const { data: updated, error: upErr } = await supabase.from("player_profiles").update(updateRow).eq("cloudkit_user_id", cloudkitUserId).select().single();
        if (upErr) throw upErr;

        // Mirror onto leaderboard row if present
        await supabase.from("leaderboard").update({ apple_user_id: appleUserId }).eq("cloudkit_user_id", cloudkitUserId);

        return new Response(JSON.stringify({ success: true, linked: true, profile: updated }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      // Case C: no row for this cloudkit_user_id — create one
      const insertRow: Record<string, unknown> = {
        cloudkit_user_id: cloudkitUserId,
        apple_user_id: appleUserId,
        apple_user_id_linked_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
      if (displayName) insertRow.display_name = displayName;
      if (email) insertRow.email = email;
      if (authorizationCode) insertRow.apple_authorization_code = authorizationCode;

      const { data: created, error: insErr } = await supabase.from("player_profiles").insert(insertRow).select().single();
      if (insErr) throw insErr;

      return new Response(JSON.stringify({ success: true, linked: true, created: true, profile: created }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // STORE AUTH CODE — captures the one-time authorizationCode that
    // ASAuthorizationAppleIDCredential returned during the original
    // Sign in with Apple flow, so we can later exchange it for a
    // refresh_token and revoke the credential via /auth/revoke on
    // Delete Account (Guideline 5.1.1(v)). Idempotent; a fresh sign-in
    // on the same device will overwrite with the newer code.
    if (action === "store_auth_code") {
      const authCode: string = body.authorization_code ?? "";
      if (!authCode) {
        return new Response(JSON.stringify({ error: "authorization_code required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      const { error } = await supabase
        .from("player_profiles")
        .update({
          apple_authorization_code: authCode,
          updated_at: new Date().toISOString(),
        })
        .eq("cloudkit_user_id", cloudkitUserId);
      if (error) {
        console.error("store_auth_code: update failed:", error);
        return new Response(JSON.stringify({ success: false, error: "update_failed" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // REVOKE SIWA — standalone endpoint that can be called independently of
    // delete_account (e.g., for testing, for a future "unlink Apple ID"
    // feature). Reads the stored auth_code from player_profiles, calls
    // Apple's /auth/token then /auth/revoke REST APIs, clears the stored
    // code on success. Returns success: true even if Apple's API fails —
    // the caller is responsible for deciding whether to proceed with the
    // rest of the delete flow.
    if (action === "revoke_siwa") {
      const { data: profile, error: profileErr } = await supabase
        .from("player_profiles")
        .select("apple_authorization_code")
        .eq("cloudkit_user_id", cloudkitUserId)
        .maybeSingle();
      if (profileErr) {
        console.error("revoke_siwa: profile lookup failed:", profileErr);
        return new Response(JSON.stringify({ success: false, error: "profile_lookup_failed" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      const authCode = profile?.apple_authorization_code ?? "";
      const result = await appleRevokeSIWA(authCode);
      if (result.success) {
        // Clear the stored code so we can't accidentally re-revoke.
        await supabase
          .from("player_profiles")
          .update({ apple_authorization_code: null })
          .eq("cloudkit_user_id", cloudkitUserId);
      }
      return new Response(JSON.stringify(result), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // DELETE ACCOUNT — irreversibly wipes the user's data from every table
    // that has a cloudkit_user_id column. Optionally also nukes rows keyed
    // by apple_user_id for defense in depth. Requires service role (already
    // in use above) so it bypasses RLS.
    if (action === "delete_account") {
      const appleUserId: string = body.apple_user_id ?? "";
      const deletedFrom: string[] = [];
      const failedTables: string[] = [];

      // Step 0: attempt server-side Sign in with Apple revocation BEFORE
      // wiping the player_profiles row (which is where the auth code lives).
      // If the Apple REST API fails, we log and continue — we never block a
      // deletion on Apple's endpoint being unreachable.
      let siwaRevokeResult: AppleRevokeResult = { success: false, skipped: true, reason: "not_attempted" };
      try {
        const { data: profile } = await supabase
          .from("player_profiles")
          .select("apple_authorization_code")
          .eq("cloudkit_user_id", cloudkitUserId)
          .maybeSingle();
        const authCode = profile?.apple_authorization_code ?? "";
        if (authCode) {
          siwaRevokeResult = await appleRevokeSIWA(authCode);
          if (siwaRevokeResult.success) {
            console.log(`delete_account: SIWA server-side revocation succeeded for ${redactId(cloudkitUserId)}`);
          } else if (siwaRevokeResult.skipped) {
            console.log(`delete_account: SIWA revocation skipped (${siwaRevokeResult.reason})`);
          } else {
            console.warn(`delete_account: SIWA revocation failed (${siwaRevokeResult.reason}) — proceeding with wipe anyway`);
          }
        } else {
          siwaRevokeResult = { success: false, skipped: true, reason: "no_auth_code_on_profile" };
        }
      } catch (e) {
        console.error("delete_account: SIWA revoke step threw:", e);
        siwaRevokeResult = { success: false, reason: "exception", detail: String(e) };
      }

      // ── Step 1: Delete secondary tables FIRST ──────────────────────────
      // Secondary tables are cleaned up before player_profiles so that any
      // foreign-key constraints referencing player_profiles don't block the
      // profile delete, and so that if the profile delete later fails we
      // haven't left orphaned rows that reference a still-existing profile.
      const secondaryTables = [
        "leaderboard",
        "player_inventory",
        "credit_transactions",
        "player_backups",
        "event_participants",
        "guild_members",
        "guild_raid_contributions",
      ];

      for (const table of secondaryTables) {
        const { data, error } = await supabase
          .from(table)
          .delete({ count: "exact" })
          .eq("cloudkit_user_id", cloudkitUserId)
          .select("cloudkit_user_id");
        if (error) {
          console.error(`delete_account: failed to delete from ${table}:`, error);
          failedTables.push(table);
          continue;
        }
        if (data && data.length > 0) deletedFrom.push(table);
      }

      // friend_connections has TWO columns referencing the user
      try {
        const { data: f1 } = await supabase
          .from("friend_connections")
          .delete()
          .eq("cloudkit_user_id", cloudkitUserId)
          .select("cloudkit_user_id");
        const { data: f2 } = await supabase
          .from("friend_connections")
          .delete()
          .eq("friend_cloudkit_user_id", cloudkitUserId)
          .select("cloudkit_user_id");
        if ((f1 && f1.length > 0) || (f2 && f2.length > 0)) {
          deletedFrom.push("friend_connections");
        }
      } catch (e) {
        console.error("delete_account: friend_connections delete failed:", e);
      }

      // ── Step 2: Delete player_profiles (the primary record) ────────────
      // CRITICAL: this must succeed for the delete to be honored. If it
      // fails (RLS blocked, network glitch), return a non-200 so the
      // client does NOT proceed to wipe local state and leave the user
      // half-deleted with orphaned cloud rows.
      const { data: profileDeleted, error: profileErr } = await supabase
        .from("player_profiles")
        .delete({ count: "exact" })
        .eq("cloudkit_user_id", cloudkitUserId)
        .select("cloudkit_user_id");
      if (profileErr) {
        console.error("delete_account: CRITICAL — player_profiles delete failed:", profileErr);
        return new Response(JSON.stringify({
          success: false,
          error: `player_profiles delete failed: ${profileErr.message ?? "unknown error"}`,
        }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      if (profileDeleted && profileDeleted.length > 0) deletedFrom.push("player_profiles");

      // Defense in depth: also wipe by apple_user_id if provided
      if (appleUserId) {
        try {
          const { data: appleRows } = await supabase
            .from("player_profiles")
            .delete()
            .eq("apple_user_id", appleUserId)
            .select("apple_user_id");
          if (appleRows && appleRows.length > 0 && !deletedFrom.includes("player_profiles")) {
            deletedFrom.push("player_profiles");
          }
        } catch (e) {
          console.error("delete_account: apple_user_id wipe failed:", e);
        }
      }

      return new Response(JSON.stringify({
        success: true,
        deleted_from: deletedFrom,
        failed_tables: failedTables,
        siwa_revoke: siwaRevokeResult,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (err) {
    console.error("player-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
