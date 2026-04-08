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

// ── ES256 JWT signing + verification ─────────────────────────────────────
//
// Keys live in Supabase Vault as PEM-encoded PKCS#8 (private) and SPKI
// (public). Both are set as environment variables and imported once per
// Deno instance — module-level caching means the PEM parse cost is paid
// on cold start only, not per request.
//
// The keypair must be generated together with:
//   openssl ecparam -name prime256v1 -genkey -noout -out priv.pem
//   openssl pkcs8 -topk8 -in priv.pem -out priv-pk8.pem -nocrypt
//   openssl ec -in priv.pem -pubout -out pub.pem
// The PKCS#8 private key goes in AUTH_JWT_ES256_PRIVATE_KEY.
// The SPKI public key goes in AUTH_JWT_ES256_PUBLIC_KEY.

let _jwtPrivateKey: CryptoKey | null = null;
let _jwtPublicKey: CryptoKey | null = null;

function pemToBytes(pem: string): Uint8Array {
  const cleaned = pem
    .replace(/-----BEGIN [A-Z0-9 ]+-----/g, "")
    .replace(/-----END [A-Z0-9 ]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function getJwtPrivateKey(): Promise<CryptoKey> {
  if (_jwtPrivateKey) return _jwtPrivateKey;
  const pem = Deno.env.get("AUTH_JWT_ES256_PRIVATE_KEY") ?? "";
  if (!pem) throw new Error("AUTH_JWT_ES256_PRIVATE_KEY not set in Vault");
  _jwtPrivateKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  return _jwtPrivateKey;
}

async function getJwtPublicKey(): Promise<CryptoKey> {
  if (_jwtPublicKey) return _jwtPublicKey;
  const pem = Deno.env.get("AUTH_JWT_ES256_PUBLIC_KEY") ?? "";
  if (!pem) throw new Error("AUTH_JWT_ES256_PUBLIC_KEY not set in Vault");
  _jwtPublicKey = await crypto.subtle.importKey(
    "spki",
    pemToBytes(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  return _jwtPublicKey;
}

function base64UrlEncode(data: string | Uint8Array): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(input: string): Uint8Array {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - (input.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function mintJWT(
  cloudkitUserId: string,
  deviceId: string,
  attested: boolean,
  expiresIn = 900,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", typ: "JWT" };
  const payload: JWTClaims = {
    iss: "rpt.supabase",
    aud: "rpt",
    sub: cloudkitUserId,
    iat: now,
    exp: now + expiresIn,
    attested,
    device_id: deviceId,
  };
  const signingInput =
    base64UrlEncode(JSON.stringify(header)) + "." +
    base64UrlEncode(JSON.stringify(payload));

  const key = await getJwtPrivateKey();
  // crypto.subtle.sign with ECDSA returns 64 raw bytes (r||s), which is
  // exactly what JWT ES256 expects (unlike openssl which returns DER).
  const signatureBytes = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: { name: "SHA-256" } },
      key,
      new TextEncoder().encode(signingInput),
    ),
  );
  return signingInput + "." + base64UrlEncode(signatureBytes);
}

export async function verifyJWT(token: string): Promise<JWTClaims | null> {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    const [headerB64, payloadB64, signatureB64] = parts;
    const signingInput = headerB64 + "." + payloadB64;
    const signature = base64UrlDecode(signatureB64);

    const key = await getJwtPublicKey();
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: { name: "SHA-256" } },
      key,
      signature,
      new TextEncoder().encode(signingInput),
    );
    if (!valid) return null;

    const payload = JSON.parse(
      new TextDecoder().decode(base64UrlDecode(payloadB64)),
    ) as JWTClaims;

    // Standard claim checks
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp && payload.exp < now) return null;
    if (payload.iat && payload.iat > now + 60) return null; // 60s clock skew tolerance
    if (payload.iss !== "rpt.supabase") return null;
    if (payload.aud !== "rpt") return null;

    return payload;
  } catch {
    return null;
  }
}

export async function verifyAssertion(
  _assertion: Uint8Array,
  _publicKey: Uint8Array,
  _bodyHashHex: string,
  _expectedCounter: number,
): Promise<AssertionVerifyResult> {
  throw new Error("verifyAssertion: not implemented yet (Task 8)");
}

// ── Apple id_token verification ───────────────────────────────────────────
// Fetches Apple's JWKS and verifies the id_token signature + standard
// claims. Apple's JWKS is cached for 24 hours at module scope to avoid
// a network round-trip on every sign-in.
//
// Apple's JWKS lives at https://appleid.apple.com/auth/keys and returns
// a set of RSA public keys in JWK format. We select the right key by
// matching the id_token header's `kid` claim.

let _appleJwksCache: { keys: Array<Record<string, unknown>>; fetchedAt: number } | null = null;

async function getAppleJwks(): Promise<Array<Record<string, unknown>>> {
  const now = Date.now();
  if (_appleJwksCache && now - _appleJwksCache.fetchedAt < 24 * 60 * 60 * 1000) {
    return _appleJwksCache.keys;
  }
  const res = await fetch("https://appleid.apple.com/auth/keys");
  if (!res.ok) throw new Error(`Failed to fetch Apple JWKS: ${res.status}`);
  const body = await res.json();
  _appleJwksCache = { keys: body.keys ?? [], fetchedAt: now };
  return _appleJwksCache.keys;
}

export async function verifyAppleIdToken(
  token: string,
): Promise<{ sub: string; email?: string } | null> {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    const [headerB64, payloadB64, signatureB64] = parts;
    const header = JSON.parse(
      new TextDecoder().decode(base64UrlDecode(headerB64)),
    );
    const payload = JSON.parse(
      new TextDecoder().decode(base64UrlDecode(payloadB64)),
    );

    // Find the matching JWK by kid and alg
    const jwks = await getAppleJwks();
    const jwk = jwks.find((k) => k.kid === header.kid && k.alg === header.alg);
    if (!jwk) return null;

    // Import the JWK as a CryptoKey. Apple uses RS256 so the alg is
    // RSASSA-PKCS1-v1_5 with SHA-256.
    const publicKey = await crypto.subtle.importKey(
      "jwk",
      jwk as JsonWebKey,
      { name: "RSASSA-PKCS1-v1_5", hash: { name: "SHA-256" } },
      false,
      ["verify"],
    );

    // Verify the signature
    const signingInput = headerB64 + "." + payloadB64;
    const signature = base64UrlDecode(signatureB64);
    const valid = await crypto.subtle.verify(
      { name: "RSASSA-PKCS1-v1_5" },
      publicKey,
      signature,
      new TextEncoder().encode(signingInput),
    );
    if (!valid) return null;

    // Verify standard claims
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp && payload.exp < now) return null;
    if (payload.iss !== "https://appleid.apple.com") return null;
    // Note: payload.aud must match our bundle ID
    // (com.SpiroTechnologies.RPT). We leave audience validation to
    // the caller so different flows can use different audiences if
    // the app ever adds multiple bundle IDs (iOS + iPad extensions).

    return {
      sub: String(payload.sub),
      email: payload.email ? String(payload.email) : undefined,
    };
  } catch {
    return null;
  }
}

export async function validateAuth(
  _req: Request,
  _supabase: SupabaseClient,
  _opts: { requireAttestation: boolean },
): Promise<AuthResult> {
  throw new Error("validateAuth: not implemented yet (Task 9)");
}
