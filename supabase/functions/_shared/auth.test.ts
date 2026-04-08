// Deno tests for _shared/auth.ts
//
// Run with:  deno test _shared/auth.test.ts --allow-env --allow-net
//
// The test private key / public key below are a test-only ES256 keypair
// generated with `openssl ecparam -name prime256v1 -genkey -noout` and
// converted to PKCS#8 via `openssl pkcs8 -topk8 ... -nocrypt`.
// NEVER reuse these keys in production. The real production keys live
// in Supabase Vault under AUTH_JWT_ES256_PRIVATE_KEY / _PUBLIC_KEY.

import { assertEquals, assertNotEquals, assert } from "https://deno.land/std@0.210.0/assert/mod.ts";
import { sha256, mintJWT, verifyJWT, verifyAppleIdToken } from "./auth.ts";

// ── Test fixtures ─────────────────────────────────────────────────────────

const TEST_PRIVATE_KEY_PEM = `-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgsBifaMmdEm9WxKOE
pmiQ82Bq0LgTBmYfih7x969yqQmhRANCAATkroNWPKFH1Sg59f3NpHMYx5vBaLgC
rCdiotShVl767O5oEFAwRdTSFR0QMHyweE2DgRA6xfPzMEghzxPEnZqu
-----END PRIVATE KEY-----`;

const TEST_PUBLIC_KEY_PEM = `-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE5K6DVjyhR9UoOfX9zaRzGMebwWi4
AqwnYqLUoVZe+uzuaBBQMEXU0hUdEDB8sHhNg4EQOsXz8zBIIc8TxJ2arg==
-----END PUBLIC KEY-----`;

// Set env vars BEFORE any auth.ts function is called (module-level caching).
Deno.env.set("AUTH_JWT_ES256_PRIVATE_KEY", TEST_PRIVATE_KEY_PEM);
Deno.env.set("AUTH_JWT_ES256_PUBLIC_KEY", TEST_PUBLIC_KEY_PEM);

// ── sha256 ────────────────────────────────────────────────────────────────

Deno.test("sha256: known hash for empty string", async () => {
  const hash = await sha256("");
  assertEquals(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
});

Deno.test("sha256: known hash for 'hello'", async () => {
  const hash = await sha256("hello");
  assertEquals(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
});

Deno.test("sha256: accepts Uint8Array input", async () => {
  const bytes = new TextEncoder().encode("hello");
  const hash = await sha256(bytes);
  assertEquals(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
});

// ── mintJWT ────────────────────────────────────────────────────────────────

Deno.test("mintJWT: produces a 3-part JWT", async () => {
  const token = await mintJWT("test_user", "device-uuid-1", true);
  const parts = token.split(".");
  assertEquals(parts.length, 3);
});

Deno.test("mintJWT: round-trips through verifyJWT", async () => {
  const token = await mintJWT("test_user", "device-uuid-1", true);
  const claims = await verifyJWT(token);
  assertNotEquals(claims, null);
  assertEquals(claims!.sub, "test_user");
  assertEquals(claims!.device_id, "device-uuid-1");
  assertEquals(claims!.attested, true);
  assertEquals(claims!.iss, "rpt.supabase");
  assertEquals(claims!.aud, "rpt");
});

Deno.test("mintJWT: exp is ~15 minutes in the future", async () => {
  const before = Math.floor(Date.now() / 1000);
  const token = await mintJWT("test_user", "device-1", true);
  const claims = await verifyJWT(token);
  assert(claims !== null);
  assert(
    claims.exp >= before + 890 && claims.exp <= before + 910,
    `exp should be ~900s from now, got ${claims.exp - before}`,
  );
});

Deno.test("mintJWT: attested=false for simulator bypass", async () => {
  const token = await mintJWT("test_user", "device-1", false);
  const claims = await verifyJWT(token);
  assertEquals(claims!.attested, false);
});

// ── verifyJWT (negative cases) ────────────────────────────────────────────

Deno.test("verifyJWT: rejects a non-JWT string", async () => {
  const claims = await verifyJWT("not a jwt");
  assertEquals(claims, null);
});

Deno.test("verifyJWT: rejects a token with only 2 parts", async () => {
  const claims = await verifyJWT("header.payload");
  assertEquals(claims, null);
});

Deno.test("verifyJWT: rejects a tampered signature", async () => {
  const token = await mintJWT("test_user", "device-1", true);
  const parts = token.split(".");
  // Flip the last character of the signature
  parts[2] = parts[2].slice(0, -1) + (parts[2].slice(-1) === "A" ? "B" : "A");
  const tampered = parts.join(".");
  const claims = await verifyJWT(tampered);
  assertEquals(claims, null);
});

Deno.test("verifyJWT: rejects a token with tampered payload", async () => {
  const token = await mintJWT("test_user", "device-1", true);
  const parts = token.split(".");
  // Decode, modify, re-encode payload
  const padded = parts[1] + "=".repeat((4 - (parts[1].length % 4)) % 4);
  const decoded = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  const payload = JSON.parse(decoded);
  payload.sub = "attacker";
  const modified = btoa(JSON.stringify(payload))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  parts[1] = modified;
  const tampered = parts.join(".");
  const claims = await verifyJWT(tampered);
  assertEquals(claims, null);
});

// ── verifyAppleIdToken (negative cases only — happy path needs real JWT) ──

Deno.test("verifyAppleIdToken: rejects a non-JWT string", async () => {
  const result = await verifyAppleIdToken("not a jwt");
  assertEquals(result, null);
});

Deno.test("verifyAppleIdToken: rejects an empty string", async () => {
  const result = await verifyAppleIdToken("");
  assertEquals(result, null);
});
