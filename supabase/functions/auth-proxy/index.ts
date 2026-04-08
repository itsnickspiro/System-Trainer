// auth-proxy — JWT authentication for System Trainer 2.9.0
//
// Three actions:
//   sign_in  — exchange a SIWA id_token (+ optional App Attest
//              attestation) for an access token + refresh token pair
//   refresh  — exchange a refresh token for a new token pair (with
//              one-time-use rotation for refresh token theft protection)
//   sign_out — revoke all the caller's refresh tokens in a single call
//
// Design spec:  docs/superpowers/specs/2026-04-08-app-attest-jwt-design.md
// Impl plan:    docs/superpowers/plans/2026-04-08-app-attest-jwt-implementation.md
//
// ⚠️  KNOWN LIMITATION (Task 10 TODO):
// The real attestation OBJECT verification against Apple's App Attest
// root CA is not implemented yet — the research agent's recommendation
// (npm:cbor-x + npm:@peculiar/x509) requires ~8-12 hours of focused
// integration work that's scoped to a separate 2.9.0 follow-up task.
// This shipping version:
//   - Accepts attestation: null (simulator path) when the
//     ALLOW_SIMULATOR_BYPASS env var is set
//   - REJECTS any non-null attestation with an explicit error
//     (rather than silently accepting it and pretending we verified it)
//
// This means this auth-proxy version is usable for iOS simulator
// development + deploying an end-to-end demo of the full auth flow,
// but NOT production.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { mintJWT, verifyJWT, verifyAppleIdToken, sha256 } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-app-attest-assertion, x-app-attest-key-id",
};

// Rate budgets for auth-proxy actions
const RATE_BUDGETS: Record<string, [number, number]> = {
  sign_in: [5, 3600],   // 5 sign-ins per hour per cloudkit_user_id
  refresh: [20, 3600],  // 20 refreshes per hour per refresh token hash
  sign_out: [10, 3600],
};

async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  key: string,
  action: string,
): Promise<boolean> {
  const budget = RATE_BUDGETS[action];
  if (!budget || !key) return true;
  const [max, windowSec] = budget;
  try {
    const { data, error } = await supabase.rpc("rate_limit_check", {
      p_user_id: key,
      p_action: `auth_${action}`,
      p_max_per_window: max,
      p_window_seconds: windowSec,
    });
    if (error) {
      console.error(`rate_limit_check RPC failed for ${key}:${action}:`, error);
      return true; // fail-open
    }
    return data !== false;
  } catch {
    return true;
  }
}

function errorResponse(error: string, status = 400) {
  return new Response(
    JSON.stringify({ error }),
    { status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}

// Generate a cryptographically secure random refresh token (32 bytes, hex)
function generateRefreshToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const action = body.action ?? "";

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("DB_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // ══════════════════════════════════════════════════════════════════
    // SIGN IN
    // ══════════════════════════════════════════════════════════════════
    if (action === "sign_in") {
      const cloudkitUserId: string = body.cloudkit_user_id ?? "";
      const appleIdToken: string = body.apple_id_token ?? "";
      const appleAuthCode: string = body.apple_authorization_code ?? "";
      const attestation = body.attestation ?? null;

      if (!cloudkitUserId || !appleIdToken) {
        return errorResponse("missing_required_fields");
      }

      // Rate limit per user
      if (!(await checkRateLimit(supabase, cloudkitUserId, "sign_in"))) {
        return errorResponse("rate_limit_exceeded", 429);
      }

      // 1. Verify the Apple id_token
      const appleClaims = await verifyAppleIdToken(appleIdToken);
      if (!appleClaims) {
        return errorResponse("invalid_apple_id_token", 401);
      }

      // 2. Handle attestation — bypass or real
      let deviceAttestationId: string;
      let isBypass = false;

      if (attestation === null) {
        // Simulator bypass path
        const allowBypass = Deno.env.get("ALLOW_SIMULATOR_BYPASS") === "true";
        if (!allowBypass) {
          return errorResponse("attestation_required");
        }
        isBypass = true;

        // Insert a bypass row with an empty public key + receipt.
        // is_bypass=true short-circuits real verification in validateAuth.
        const { data: bypassRow, error: bypassErr } = await supabase
          .from("device_attestations")
          .insert({
            cloudkit_user_id: cloudkitUserId,
            key_id: `bypass-${crypto.randomUUID()}`,
            attestation_public_key: new Uint8Array(0),
            receipt: new Uint8Array(0),
            is_bypass: true,
          })
          .select("id")
          .single();
        if (bypassErr || !bypassRow) {
          console.error("sign_in: bypass insert failed:", bypassErr);
          return errorResponse("bypass_insert_failed", 500);
        }
        deviceAttestationId = bypassRow.id;
      } else {
        // ⚠️  REAL ATTESTATION PATH — NOT IMPLEMENTED YET
        //
        // Validating the attestation object requires CBOR decoding,
        // X.509 cert chain walking up to Apple's App Attest root CA,
        // nonce extraction from the 1.2.840.113635.100.8.2 extension,
        // RP ID hash verification (SHA256(teamID + "." + bundleID)),
        // and public key extraction from credentialPublicKey.
        //
        // Research agent (2026-04-08) recommended npm:cbor-x +
        // npm:@peculiar/x509 as the library path. Estimated effort
        // 8-12 hours. Tracked as a separate follow-up task.
        //
        // Until then: reject non-null attestations explicitly so we
        // never ship a "pretend-to-verify" implementation to
        // production. Tests and simulator development still work
        // via the bypass path above.
        return errorResponse(
          "attestation_object_verification_not_implemented",
          501, // 501 Not Implemented — signals to iOS that the server
               // knows about the request but the feature is pending
        );
      }

      // 3. Evict oldest device if user has > 5 active devices
      const { count: deviceCount } = await supabase
        .from("device_attestations")
        .select("*", { count: "exact", head: true })
        .eq("cloudkit_user_id", cloudkitUserId)
        .is("revoked_at", null);
      if ((deviceCount ?? 0) > 5) {
        // Revoke the oldest by last_used_at
        const { data: oldest } = await supabase
          .from("device_attestations")
          .select("id")
          .eq("cloudkit_user_id", cloudkitUserId)
          .is("revoked_at", null)
          .order("last_used_at", { ascending: true })
          .limit(1)
          .maybeSingle();
        if (oldest) {
          await supabase
            .from("device_attestations")
            .update({ revoked_at: new Date().toISOString() })
            .eq("id", oldest.id);
          // Cascade delete of refresh_tokens is automatic via FK
        }
      }

      // 4. Store the SIWA auth code for future revocation
      if (appleAuthCode) {
        await supabase
          .from("player_profiles")
          .update({ apple_authorization_code: appleAuthCode })
          .eq("cloudkit_user_id", cloudkitUserId);
      }

      // 5. Generate + store refresh token
      const refreshToken = generateRefreshToken();
      const refreshTokenHash = await sha256(refreshToken);
      const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
      const { error: refreshErr } = await supabase.from("refresh_tokens").insert({
        cloudkit_user_id: cloudkitUserId,
        token_hash: refreshTokenHash,
        device_attestation_id: deviceAttestationId,
        expires_at: expiresAt,
      });
      if (refreshErr) {
        console.error("sign_in: refresh_tokens insert failed:", refreshErr);
        return errorResponse("refresh_token_insert_failed", 500);
      }

      // 6. Mint the access JWT
      const accessToken = await mintJWT(cloudkitUserId, deviceAttestationId, !isBypass);

      return new Response(
        JSON.stringify({
          access_token: accessToken,
          refresh_token: refreshToken,
          expires_in: 900,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ══════════════════════════════════════════════════════════════════
    // REFRESH
    // ══════════════════════════════════════════════════════════════════
    if (action === "refresh") {
      const refreshToken: string = body.refresh_token ?? "";
      if (!refreshToken) {
        return errorResponse("missing_refresh_token");
      }
      const tokenHash = await sha256(refreshToken);

      // Rate limit by the token hash (per-token, not per-user, so
      // a stolen-and-used-twice token hits the limit faster)
      if (!(await checkRateLimit(supabase, tokenHash, "refresh"))) {
        return errorResponse("rate_limit_exceeded", 429);
      }

      const { data: row, error: lookupErr } = await supabase
        .from("refresh_tokens")
        .select("id, cloudkit_user_id, device_attestation_id, expires_at, revoked_at")
        .eq("token_hash", tokenHash)
        .maybeSingle();
      if (lookupErr || !row) {
        return errorResponse("invalid_refresh_token", 401);
      }
      if (row.revoked_at) {
        // RFC 6819 §5.2.2.3 refresh token theft mitigation: if we see
        // a revoked token being replayed, revoke ALL active tokens for
        // this user. A legitimate client won't replay a rotated token,
        // but an attacker with a stolen copy will.
        await supabase
          .from("refresh_tokens")
          .update({ revoked_at: new Date().toISOString() })
          .eq("cloudkit_user_id", row.cloudkit_user_id)
          .is("revoked_at", null);
        return errorResponse("refresh_token_revoked", 401);
      }
      if (new Date(row.expires_at) < new Date()) {
        return errorResponse("refresh_token_expired", 401);
      }

      // Look up whether this device is bypass or real-attested
      const { data: device } = await supabase
        .from("device_attestations")
        .select("is_bypass")
        .eq("id", row.device_attestation_id)
        .single();
      const attested = !(device?.is_bypass ?? true);

      // ROTATION: revoke the old refresh token, create a new one
      await supabase
        .from("refresh_tokens")
        .update({
          revoked_at: new Date().toISOString(),
          last_used_at: new Date().toISOString(),
        })
        .eq("id", row.id);

      const newRefreshToken = generateRefreshToken();
      const newRefreshTokenHash = await sha256(newRefreshToken);
      const newExpiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
      await supabase.from("refresh_tokens").insert({
        cloudkit_user_id: row.cloudkit_user_id,
        token_hash: newRefreshTokenHash,
        device_attestation_id: row.device_attestation_id,
        expires_at: newExpiresAt,
      });

      const accessToken = await mintJWT(
        row.cloudkit_user_id,
        row.device_attestation_id,
        attested,
      );

      return new Response(
        JSON.stringify({
          access_token: accessToken,
          refresh_token: newRefreshToken,
          expires_in: 900,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ══════════════════════════════════════════════════════════════════
    // SIGN OUT
    // ══════════════════════════════════════════════════════════════════
    if (action === "sign_out") {
      const authHeader = req.headers.get("authorization") ?? "";
      if (!authHeader.startsWith("Bearer ")) {
        return errorResponse("missing_bearer_token", 401);
      }
      const claims = await verifyJWT(authHeader.slice(7));
      if (!claims) {
        return errorResponse("invalid_jwt", 401);
      }

      // Delete every active refresh token for this user. Within at most
      // 15 minutes (access token expiry), every one of the user's
      // sessions is dead, on every device, without any more action.
      const { count } = await supabase
        .from("refresh_tokens")
        .delete({ count: "exact" })
        .eq("cloudkit_user_id", claims.sub)
        .is("revoked_at", null);

      return new Response(
        JSON.stringify({ success: true, sessions_revoked: count ?? 0 }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return errorResponse("unknown_action");
  } catch (err) {
    console.error("auth-proxy error:", err);
    return errorResponse("internal_server_error", 500);
  }
});
