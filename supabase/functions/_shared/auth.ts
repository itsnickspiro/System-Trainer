// Shared auth middleware for System Trainer Edge Functions.
// Imported by auth-proxy, player-proxy, leaderboard-proxy.
//
// Exports:
//   validateAuth(req, supabase, opts)  — main entry point for every authenticated request
//   mintJWT(cloudkitUserId, deviceId, attested)
//   verifyJWT(token)
//   verifyAssertion(assertion, publicKey, bodyHash, expectedCounter)
//   verifyAppleIdToken(token)
//   sha256(input)
//
// Design spec: docs/superpowers/specs/2026-04-08-app-attest-jwt-design.md
// Implementation plan: docs/superpowers/plans/2026-04-08-app-attest-jwt-implementation.md

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Public types ──────────────────────────────────────────────────────────

export interface JWTClaims {
  iss: string;
  aud: string;
  sub: string; // cloudkit_user_id
  iat: number;
  exp: number;
  attested: boolean;
  device_id: string; // device_attestations.id
}

export interface AuthResult {
  valid: boolean;
  cloudkit_user_id?: string;
  device_attestation_id?: string;
  error?: string;
}

export interface AssertionVerifyResult {
  valid: boolean;
  newCounter?: number;
}

// ── sha256 (fully implemented — needed by other stubs) ───────────────────

export async function sha256(input: string | Uint8Array): Promise<string> {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  const hashBuf = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hashBuf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ── Stubs (real implementations in Tasks 5, 7, 8, 9) ─────────────────────

export async function mintJWT(
  _cloudkitUserId: string,
  _deviceId: string,
  _attested: boolean,
  _expiresIn = 900,
): Promise<string> {
  throw new Error("mintJWT: not implemented yet (Task 5)");
}

export async function verifyJWT(_token: string): Promise<JWTClaims | null> {
  throw new Error("verifyJWT: not implemented yet (Task 5)");
}

export async function verifyAssertion(
  _assertion: Uint8Array,
  _publicKey: Uint8Array,
  _bodyHashHex: string,
  _expectedCounter: number,
): Promise<AssertionVerifyResult> {
  throw new Error("verifyAssertion: not implemented yet (Task 8)");
}

export async function verifyAppleIdToken(
  _token: string,
): Promise<{ sub: string; email?: string } | null> {
  throw new Error("verifyAppleIdToken: not implemented yet (Task 7)");
}

export async function validateAuth(
  _req: Request,
  _supabase: SupabaseClient,
  _opts: { requireAttestation: boolean },
): Promise<AuthResult> {
  throw new Error("validateAuth: not implemented yet (Task 9)");
}
