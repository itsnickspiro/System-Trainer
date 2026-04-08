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

// ── App Attest assertion verification ────────────────────────────────────
//
// Apple's App Attest assertion format:
//   https://developer.apple.com/documentation/devicecheck/validating_apps_that_connect_to_your_server
//
// The assertion is a CBOR-encoded map with exactly two keys:
//   "authenticatorData": bytes (RP ID hash, flags, counter)
//   "signature": bytes (DER-encoded ECDSA signature)
//
// The signature is over (authenticatorData || SHA256(clientData)) and
// must verify against the attestation public key we stored at sign_in
// time. The counter must be strictly greater than the last-seen value
// to prevent replay attacks.
//
// NOTE: This function verifies ASSERTIONS, not the attestation object
// itself. The attestation object (which contains the full X.509 cert
// chain that verifies up to Apple's root CA) is validated at sign_in
// time in auth-proxy. Assertions are the lightweight per-request proof
// that uses the stored public key from the attestation.

// Minimal CBOR decoder for the Apple assertion format specifically.
// Handles only: map of 2 (major type 5 length 2), text string keys
// (major type 3), byte string values (major type 2), byte string length
// up to u16 (indicator 25). Anything else returns null.
function decodeAppleAssertionCbor(bytes: Uint8Array): { authenticatorData: Uint8Array; signature: Uint8Array } | null {
  try {
    let offset = 0;
    // Expect major type 5 (map) with length 2: byte 0xA2
    if (bytes[offset++] !== 0xa2) return null;

    const result: Record<string, Uint8Array> = {};
    for (let i = 0; i < 2; i++) {
      // Key: major type 3 (text string) with small length
      const keyByte = bytes[offset++];
      if ((keyByte & 0xe0) !== 0x60) return null;
      const keyLen = keyByte & 0x1f;
      if (keyLen >= 24) return null; // we only handle short keys
      const keyBytes = bytes.slice(offset, offset + keyLen);
      offset += keyLen;
      const key = new TextDecoder().decode(keyBytes);

      // Value: major type 2 (byte string)
      const valByte = bytes[offset++];
      if ((valByte & 0xe0) !== 0x40) return null;
      let valLen: number;
      const lenIndicator = valByte & 0x1f;
      if (lenIndicator < 24) {
        valLen = lenIndicator;
      } else if (lenIndicator === 24) {
        valLen = bytes[offset++];
      } else if (lenIndicator === 25) {
        valLen = (bytes[offset] << 8) | bytes[offset + 1];
        offset += 2;
      } else {
        return null;
      }
      result[key] = bytes.slice(offset, offset + valLen);
      offset += valLen;
    }
    if (!result.authenticatorData || !result.signature) return null;
    return {
      authenticatorData: result.authenticatorData,
      signature: result.signature,
    };
  } catch {
    return null;
  }
}

// DER ECDSA signature format:
//   30 LL 02 rLen rBytes 02 sLen sBytes
// WebCrypto expects raw r||s (64 bytes for P-256). DER integers can
// have a leading 0x00 byte for sign, which we need to strip.
function derSignatureToRaw(der: Uint8Array): Uint8Array | null {
  try {
    if (der[0] !== 0x30) return null;
    let offset = 2; // skip tag + length
    if ((der[1] & 0x80) !== 0) {
      // Long-form length: skip the length bytes
      offset = 2 + (der[1] & 0x7f);
    }
    if (der[offset++] !== 0x02) return null;
    let rLen = der[offset++];
    while (rLen > 32 && der[offset] === 0x00) {
      offset++;
      rLen--;
    }
    const r = der.slice(offset, offset + rLen);
    offset += rLen;
    if (der[offset++] !== 0x02) return null;
    let sLen = der[offset++];
    while (sLen > 32 && der[offset] === 0x00) {
      offset++;
      sLen--;
    }
    const s = der.slice(offset, offset + sLen);
    // Pad r and s to exactly 32 bytes each (left-pad with zeros)
    const raw = new Uint8Array(64);
    raw.set(r, 32 - r.length);
    raw.set(s, 64 - s.length);
    return raw;
  } catch {
    return null;
  }
}

export async function verifyAssertion(
  assertion: Uint8Array,
  publicKeyBytes: Uint8Array,
  bodyHashHex: string,
  expectedCounter: number,
): Promise<AssertionVerifyResult> {
  try {
    // 1. CBOR-decode the assertion
    const decoded = decodeAppleAssertionCbor(assertion);
    if (!decoded) return { valid: false };

    const { authenticatorData, signature } = decoded;

    // 2. Extract + validate the counter
    //
    // authenticatorData layout:
    //   [0..32]  SHA-256 of RP ID (we don't re-validate here because
    //            the attestation object did this at sign_in)
    //   [32]     flags
    //   [33..37] counter (big-endian u32)
    if (authenticatorData.length < 37) return { valid: false };
    const counter = ((authenticatorData[33] << 24) |
      (authenticatorData[34] << 16) |
      (authenticatorData[35] << 8) |
      authenticatorData[36]) >>> 0; // coerce to unsigned
    // Counter must be strictly greater than the previous value (replay protection)
    if (counter <= expectedCounter) return { valid: false };

    // 3. Construct the signed message = authenticatorData || clientDataHash
    const clientDataHash = new Uint8Array(bodyHashHex.length / 2);
    for (let i = 0; i < clientDataHash.length; i++) {
      clientDataHash[i] = parseInt(bodyHashHex.substr(i * 2, 2), 16);
    }
    const signedMessage = new Uint8Array(authenticatorData.length + clientDataHash.length);
    signedMessage.set(authenticatorData, 0);
    signedMessage.set(clientDataHash, authenticatorData.length);

    // 4. Import the attestation public key (EC P-256 uncompressed point)
    const publicKey = await crypto.subtle.importKey(
      "raw",
      publicKeyBytes,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );

    // 5. Convert DER signature to raw r||s (WebCrypto format)
    const rawSig = derSignatureToRaw(signature);
    if (!rawSig) return { valid: false };

    // 6. Verify
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: { name: "SHA-256" } },
      publicKey,
      rawSig,
      signedMessage,
    );
    if (!valid) return { valid: false };

    return { valid: true, newCounter: counter };
  } catch (e) {
    console.error("verifyAssertion error:", e);
    return { valid: false };
  }
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
