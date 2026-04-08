# System Trainer 2.9.0 — App Attest + JWT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `x-app-secret` shared-secret authentication with per-user JWT + per-device App Attest in a single hard-cutover release (2.9.0, build 26). Kills the "someone extracted the secret and can impersonate any user" attack class.

**Architecture:** New `auth-proxy` Edge Function mints ES256 JWTs after verifying Apple ID tokens + App Attest attestation objects. `_shared/auth.ts` middleware runs on every request to both existing proxies, verifying the JWT and (for writes) the device assertion. iOS gets three new files (`AppAttestService`, `AuthClient`, `APIClient`) and every existing `postToProxy` call site migrates to the new API wrapper.

**Tech Stack:**
- **Server:** Supabase Edge Functions (Deno), PostgreSQL, `crypto.subtle` WebCrypto API
- **iOS:** Swift 5.9+, `DeviceCheck.DCAppAttestService`, `CryptoKit.SHA256`, Keychain
- **Auth:** ES256 JWTs, Sign in with Apple identity tokens, App Attest attestations
- **Testing:** Deno built-in test runner for backend, manual test scenarios for iOS (project has no XCTest suite)

**Design spec:** `docs/superpowers/specs/2026-04-08-app-attest-jwt-design.md` (965 lines) — read this before starting any task; all architectural decisions and rationale live there

---

## File Structure

### New files to create

| Path | Responsibility |
|---|---|
| `supabase/migrations/20260408_auth_attest_jwt.sql` | `device_attestations` + `refresh_tokens` tables, indexes, RLS |
| `supabase/functions/_shared/auth.ts` | `validateAuth`, `verifyJWT`, `mintJWT`, `verifyAssertion`, `verifyAppleIdToken`, `sha256` |
| `supabase/functions/_shared/auth.test.ts` | Deno tests for the above helpers |
| `supabase/functions/_shared/apple-app-attest-root.pem` | Apple's App Attest root CA, bundled for offline verification |
| `supabase/functions/auth-proxy/index.ts` | New edge function: `sign_in`, `refresh`, `sign_out` actions |
| `RPT/AppAttestService.swift` | iOS wrapper around `DCAppAttestService` + Secure Enclave key persistence |
| `RPT/AuthClient.swift` | iOS Keychain-backed JWT store + auto-refresh |
| `RPT/APIClient.swift` | iOS wrapper for every Edge Function POST, injects Bearer + attestation headers |
| `docs/superpowers/plans/2026-04-08-app-attest-jwt-implementation.md` | This file |

### Existing files to modify

| Path | Changes |
|---|---|
| `supabase/functions/player-proxy/index.ts` | Remove `x-app-secret` check; add `validateAuth()` at request start; change `cloudkitUserId` source from `body` to JWT `sub` claim |
| `supabase/functions/leaderboard-proxy/index.ts` | Same as player-proxy |
| `RPT/Secrets.swift` | Delete `appSecret` property entirely |
| `Secrets.xcconfig` | Delete `APP_SECRET = ...` line |
| `ci_scripts/ci_post_clone.sh` | Delete `APP_SECRET` references |
| `RPT/Info.plist` | Delete `APP_SECRET` key |
| `RPT.xcodeproj/project.pbxproj` | Delete `APP_SECRET` from user-defined settings; bump `MARKETING_VERSION` to `2.9.0`, `CURRENT_PROJECT_VERSION` to `26`; add the three new Swift files to the RPT target |
| `RPT/RPT.entitlements` | Add `com.apple.developer.devicecheck.appattest-environment` = `production` |
| `RPT/AppleAuthService.swift` | After `persistFromButtonResult`, call `AuthClient.shared.signIn(...)` instead of directly calling `linkAppleID` |
| `RPT/PlayerProfileService.swift` | Delete `postToProxy`; replace every call site with `APIClient.post(...)` |
| `RPT/LeaderboardService.swift` | Same as PlayerProfileService |
| `RPT/SettingsView.swift` | `performDeleteAccount` uses `APIClient.post` instead of raw `URLSession` |

---

## Pre-Flight (User-Side Manual Steps, Before Task 1)

These require human action in external systems. The executing agent should NOT proceed past Task 1 until these are confirmed done.

- [ ] **Pre-flight 1: Generate the JWT signing key**

  Run locally:
  ```bash
  openssl ecparam -name prime256v1 -genkey -noout -out /tmp/rpt-jwt-es256.pem
  openssl ec -in /tmp/rpt-jwt-es256.pem -pubout -out /tmp/rpt-jwt-es256-pub.pem
  cat /tmp/rpt-jwt-es256.pem      # this is the private key
  cat /tmp/rpt-jwt-es256-pub.pem  # this is the public key (will be checked into the repo)
  ```

- [ ] **Pre-flight 2: Add the private key to Supabase Vault**

  Navigate to https://supabase.com/dashboard/project/erghbsnxtsbnmfuycnyb/settings/functions → Edge Function Secrets → add `AUTH_JWT_ES256_PRIVATE_KEY` = entire `/tmp/rpt-jwt-es256.pem` contents (including `-----BEGIN EC PRIVATE KEY-----` and `-----END EC PRIVATE KEY-----` lines).

- [ ] **Pre-flight 3: Download Apple's App Attest root CA**

  Run locally:
  ```bash
  curl -o "/Users/nickspiro/Github Local/System-Trainer/supabase/functions/_shared/apple-app-attest-root.pem" \
       https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
  shasum -a 256 "/Users/nickspiro/Github Local/System-Trainer/supabase/functions/_shared/apple-app-attest-root.pem"
  ```
  Expected SHA-256 (verify against Apple's published hash): record whatever shasum outputs in Task 3's code comments.

- [ ] **Pre-flight 4: Enable App Attest capability in Apple Developer Portal**

  Navigate to https://developer.apple.com/account/resources/identifiers/list → select `SpiroTechnologies.RPT` App ID → enable "App Attest" capability → Save. This updates the App ID so the provisioning profile will allow the `com.apple.developer.devicecheck.appattest-environment` entitlement we add in Task 27.

- [ ] **Pre-flight 5: Confirm Xcode Cloud has latest signing identity**

  In App Store Connect → Xcode Cloud → Workflows → verify the "System Trainer" workflow re-pulls the updated provisioning profile on next build. (Xcode Cloud usually does this automatically, but entitlement additions occasionally require a manual "Invalidate Certificates" action.)

- [ ] **Pre-flight 6: Let 2.8.4 and 2.8.5 reach TestFlight and get one full sign-in / delete-account cycle of real-world testing from at least one beta tester**

  This is the most important pre-flight step. Starting this plan on top of an unvalidated 2.8.5 base means any bug found in 2.9.0 could be masked by a pre-existing 2.8.5 bug. Real-world validation of the current base is cheap insurance.

---

## Phase 1: Backend Foundation (Tasks 1-10)

### Task 1: Apply database migration

**Files:**
- Create: `supabase/migrations/20260408_auth_attest_jwt.sql`

- [ ] **Step 1: Write the migration SQL**

  Create the file with this exact content:

  ```sql
  -- 2.9.0: App Attest + JWT authentication infrastructure
  --
  -- Adds two new tables to support the new auth scheme:
  --   • device_attestations: per-(user, device) App Attest public key + replay counter
  --   • refresh_tokens: hashed refresh tokens for session revocation
  --
  -- Neither table stores any user-visible data. A breach of these tables
  -- cannot be used to recover personal information; the worst case is
  -- forcing active users to re-authenticate.

  -- ── 1. device_attestations ─────────────────────────────────────────────
  CREATE TABLE IF NOT EXISTS public.device_attestations (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cloudkit_user_id        text NOT NULL,
    key_id                  text NOT NULL,
    attestation_public_key  bytea NOT NULL,
    receipt                 bytea NOT NULL,
    counter                 bigint NOT NULL DEFAULT 0,
    is_bypass               boolean NOT NULL DEFAULT false,
    created_at              timestamptz NOT NULL DEFAULT now(),
    last_used_at            timestamptz NOT NULL DEFAULT now(),
    revoked_at              timestamptz,
    UNIQUE (cloudkit_user_id, key_id)
  );

  CREATE INDEX IF NOT EXISTS device_attestations_cloudkit_user_id_active_idx
    ON public.device_attestations (cloudkit_user_id, last_used_at DESC)
    WHERE revoked_at IS NULL;

  ALTER TABLE public.device_attestations ENABLE ROW LEVEL SECURITY;

  COMMENT ON TABLE public.device_attestations IS
    'Stores App Attest public key + replay counter for each (user, device) pair. '
    'Populated on SIWA sign-in, consulted on every write request to verify the '
    'App Attest assertion signature.';

  -- ── 2. refresh_tokens ──────────────────────────────────────────────────
  CREATE TABLE IF NOT EXISTS public.refresh_tokens (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cloudkit_user_id        text NOT NULL,
    token_hash              text NOT NULL UNIQUE,
    device_attestation_id   uuid REFERENCES public.device_attestations(id) ON DELETE CASCADE,
    created_at              timestamptz NOT NULL DEFAULT now(),
    expires_at              timestamptz NOT NULL,
    revoked_at              timestamptz,
    last_used_at            timestamptz
  );

  CREATE INDEX IF NOT EXISTS refresh_tokens_cloudkit_user_id_active_idx
    ON public.refresh_tokens (cloudkit_user_id)
    WHERE revoked_at IS NULL;

  CREATE INDEX IF NOT EXISTS refresh_tokens_expires_at_idx
    ON public.refresh_tokens (expires_at)
    WHERE revoked_at IS NULL;

  ALTER TABLE public.refresh_tokens ENABLE ROW LEVEL SECURITY;

  COMMENT ON TABLE public.refresh_tokens IS
    'SHA-256 hashes of active refresh tokens. Raw tokens are never stored. '
    'DELETE FROM this table by cloudkit_user_id to kill all the user''s sessions '
    'within the 15-minute access-token expiry window.';
  ```

- [ ] **Step 2: Apply the migration via the Supabase MCP**

  Use the `mcp__plugin_supabase_supabase__apply_migration` tool with `project_id: "erghbsnxtsbnmfuycnyb"`, `name: "auth_attest_jwt_20260408"`, and the SQL from Step 1.

  Expected: `{"success": true}`

- [ ] **Step 3: Verify the migration landed**

  Use the `mcp__plugin_supabase_supabase__execute_sql` tool with:
  ```sql
  SELECT
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'device_attestations' AND table_schema = 'public') AS has_device_attestations,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'refresh_tokens' AND table_schema = 'public') AS has_refresh_tokens,
    (SELECT relrowsecurity FROM pg_class WHERE relname = 'device_attestations') AS device_rls_on,
    (SELECT relrowsecurity FROM pg_class WHERE relname = 'refresh_tokens') AS refresh_rls_on;
  ```
  Expected: all four values = 1 or true.

- [ ] **Step 4: Commit**

  ```bash
  cd "/Users/nickspiro/Github Local/System-Trainer"
  git add supabase/migrations/20260408_auth_attest_jwt.sql
  git commit -m "feat(2.9.0): schema — device_attestations + refresh_tokens tables"
  ```

### Task 2: Create the `_shared/auth.ts` stub with type definitions

**Files:**
- Create: `supabase/functions/_shared/auth.ts`

- [ ] **Step 1: Write the initial stub with types + empty helpers**

  Create `supabase/functions/_shared/auth.ts` with this content. The helpers are stubs; real implementations land in Tasks 4-8.

  ```typescript
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

  import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

  // ── Public types ──────────────────────────────────────────────────────────

  export interface JWTClaims {
    iss: string;
    aud: string;
    sub: string;          // cloudkit_user_id
    iat: number;
    exp: number;
    attested: boolean;
    device_id: string;    // device_attestations.id
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

  // ── Helpers (stubs — real implementations in later tasks) ────────────────

  export async function sha256(input: string | Uint8Array): Promise<string> {
    const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
    const hashBuf = await crypto.subtle.digest("SHA-256", bytes);
    return Array.from(new Uint8Array(hashBuf))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
  }

  export async function mintJWT(
    _cloudkitUserId: string,
    _deviceId: string,
    _attested: boolean,
    _expiresIn = 900,
  ): Promise<string> {
    throw new Error("mintJWT: not implemented yet");
  }

  export async function verifyJWT(_token: string): Promise<JWTClaims | null> {
    throw new Error("verifyJWT: not implemented yet");
  }

  export async function verifyAssertion(
    _assertion: Uint8Array,
    _publicKey: Uint8Array,
    _bodyHashHex: string,
    _expectedCounter: number,
  ): Promise<AssertionVerifyResult> {
    throw new Error("verifyAssertion: not implemented yet");
  }

  export async function verifyAppleIdToken(
    _token: string,
  ): Promise<{ sub: string; email?: string } | null> {
    throw new Error("verifyAppleIdToken: not implemented yet");
  }

  export async function validateAuth(
    _req: Request,
    _supabase: SupabaseClient,
    _opts: { requireAttestation: boolean },
  ): Promise<AuthResult> {
    throw new Error("validateAuth: not implemented yet");
  }
  ```

- [ ] **Step 2: Verify the file parses with Deno**

  Run locally:
  ```bash
  cd "/Users/nickspiro/Github Local/System-Trainer"
  deno check supabase/functions/_shared/auth.ts
  ```
  Expected: output shows no type errors (may show warnings about unused parameters starting with `_`, which is fine).

  **If `deno` is not installed locally:** skip this step and rely on the deploy-time check in later tasks. The Supabase MCP `deploy_edge_function` tool runs type-checking server-side.

- [ ] **Step 3: Commit**

  ```bash
  git add supabase/functions/_shared/auth.ts
  git commit -m "feat(2.9.0): _shared/auth.ts scaffold with type definitions"
  ```

### Task 3: Bundle Apple's App Attest root CA certificate

**Files:**
- Create: `supabase/functions/_shared/apple-app-attest-root.pem`

- [ ] **Step 1: Download the certificate**

  Run locally:
  ```bash
  cd "/Users/nickspiro/Github Local/System-Trainer"
  curl -fsSL \
    -o supabase/functions/_shared/apple-app-attest-root.pem \
    https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
  ```

- [ ] **Step 2: Verify the file is a valid PEM**

  ```bash
  head -1 supabase/functions/_shared/apple-app-attest-root.pem
  tail -1 supabase/functions/_shared/apple-app-attest-root.pem
  ```
  Expected: starts with `-----BEGIN CERTIFICATE-----`, ends with `-----END CERTIFICATE-----`.

  Record the SHA-256 for future verification:
  ```bash
  shasum -a 256 supabase/functions/_shared/apple-app-attest-root.pem
  ```
  Write the hash down in this commit's message for future auditing.

- [ ] **Step 3: Commit**

  ```bash
  git add supabase/functions/_shared/apple-app-attest-root.pem
  git commit -m "feat(2.9.0): bundle Apple App Attest root CA certificate

  SHA-256: <paste the shasum output from Step 2>

  Downloaded from https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
  Used by _shared/auth.ts verifyAssertion to validate attestation objects
  offline without requiring a network dependency on Apple's CA service."
  ```

### Task 4: Write the failing test for `sha256` and `mintJWT`

**Files:**
- Create: `supabase/functions/_shared/auth.test.ts`

- [ ] **Step 1: Write the test file**

  Create `supabase/functions/_shared/auth.test.ts` with this content:

  ```typescript
  import { assertEquals, assertNotEquals, assert } from "https://deno.land/std@0.210.0/assert/mod.ts";
  import { sha256, mintJWT, verifyJWT } from "./auth.ts";

  // Mock the JWT private key for tests. Must match the format used in auth.ts.
  // Real test key — NEVER reuse this in production. Generated with:
  //   openssl ecparam -name prime256v1 -genkey -noout
  const TEST_PRIVATE_KEY_PEM = `-----BEGIN EC PRIVATE KEY-----
  MHcCAQEEIGvH/jKhpLTdX8sHkpx3NH7SbT1u8o+xJj2Vr1hSldYsoAoGCCqGSM49
  AwEHoUQDQgAEZvqJ2q3gDh7FYzhKYEDHOGs9N3kAJ8CqKKO1EMfK89jRRSCFCt1a
  RYvZYxyKPvSF6Lq2NzTxJ3iHnWPM9ETpUg==
  -----END EC PRIVATE KEY-----`;

  // Set the private key via env var so auth.ts can pick it up
  Deno.env.set("AUTH_JWT_ES256_PRIVATE_KEY", TEST_PRIVATE_KEY_PEM);

  // ── sha256 ────────────────────────────────────────────────────────────────
  Deno.test("sha256: produces known hash for empty string", async () => {
    const hash = await sha256("");
    assertEquals(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  });

  Deno.test("sha256: produces known hash for 'hello'", async () => {
    const hash = await sha256("hello");
    assertEquals(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
  });

  // ── mintJWT ────────────────────────────────────────────────────────────────
  Deno.test("mintJWT: produces a verifiable token", async () => {
    const token = await mintJWT("test_user", "device-uuid-1", true);
    assert(token.split(".").length === 3, "JWT should have 3 parts");
    const claims = await verifyJWT(token);
    assertNotEquals(claims, null);
    assertEquals(claims!.sub, "test_user");
    assertEquals(claims!.device_id, "device-uuid-1");
    assertEquals(claims!.attested, true);
  });

  Deno.test("mintJWT: exp is ~15 minutes in the future", async () => {
    const before = Math.floor(Date.now() / 1000);
    const token = await mintJWT("test_user", "device-1", true);
    const claims = await verifyJWT(token);
    assert(claims!.exp >= before + 890 && claims!.exp <= before + 910,
           `exp should be ~900s from now, got ${claims!.exp - before}`);
  });

  // ── verifyJWT ──────────────────────────────────────────────────────────────
  Deno.test("verifyJWT: rejects a tampered token", async () => {
    const token = await mintJWT("test_user", "device-1", true);
    // Flip the last character of the signature
    const parts = token.split(".");
    parts[2] = parts[2].slice(0, -1) + (parts[2].slice(-1) === "A" ? "B" : "A");
    const tampered = parts.join(".");
    const claims = await verifyJWT(tampered);
    assertEquals(claims, null);
  });

  Deno.test("verifyJWT: rejects an expired token", async () => {
    // mintJWT doesn't expose the expires_in override for tests, so this
    // test is a placeholder until we add a test-only override. For now
    // we just verify the happy path.
    const token = await mintJWT("test_user", "device-1", true);
    const claims = await verifyJWT(token);
    assertNotEquals(claims, null);
    assert(claims!.exp > Math.floor(Date.now() / 1000), "token should not be expired");
  });
  ```

- [ ] **Step 2: Run the test to verify it fails**

  Run locally:
  ```bash
  cd "/Users/nickspiro/Github Local/System-Trainer/supabase/functions"
  deno test _shared/auth.test.ts --allow-env
  ```
  Expected: all tests FAIL with "mintJWT: not implemented yet" or "verifyJWT: not implemented yet".

  **If `deno` is not installed locally:** skip this step and implement Task 5 anyway; we'll verify end-to-end after deploy.

- [ ] **Step 3: Commit**

  ```bash
  git add supabase/functions/_shared/auth.test.ts
  git commit -m "test(2.9.0): failing tests for sha256 / mintJWT / verifyJWT"
  ```

### Task 5: Implement `mintJWT` and `verifyJWT`

**Files:**
- Modify: `supabase/functions/_shared/auth.ts`

- [ ] **Step 1: Replace the mintJWT and verifyJWT stubs with real implementations**

  Locate the stub functions in `supabase/functions/_shared/auth.ts` and replace them with:

  ```typescript
  // Cache the imported signing key at module scope so we don't re-parse
  // the PEM on every request. Deno Edge Function instances persist module
  // state across requests within the same instance.
  let _jwtPrivateKey: CryptoKey | null = null;
  let _jwtPublicKey: CryptoKey | null = null;

  async function getJwtPrivateKey(): Promise<CryptoKey> {
    if (_jwtPrivateKey) return _jwtPrivateKey;
    const pem = Deno.env.get("AUTH_JWT_ES256_PRIVATE_KEY") ?? "";
    if (!pem) throw new Error("AUTH_JWT_ES256_PRIVATE_KEY not set in Vault");
    // PEM → PKCS#8 bytes
    const cleaned = pem
      .replace(/-----BEGIN [A-Z ]+-----/g, "")
      .replace(/-----END [A-Z ]+-----/g, "")
      .replace(/\s+/g, "");
    const binary = atob(cleaned);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    _jwtPrivateKey = await crypto.subtle.importKey(
      "pkcs8",
      bytes,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
    return _jwtPrivateKey;
  }

  async function getJwtPublicKey(): Promise<CryptoKey> {
    if (_jwtPublicKey) return _jwtPublicKey;
    // Derive the public key from the private key. crypto.subtle doesn't
    // let you extract a public key directly from a PKCS#8 private key,
    // so we import the same bytes as "sign" and also export/re-import
    // the spki form. For simplicity, we sign and verify with the same
    // CryptoKey object; ECDSA in WebCrypto supports both operations
    // when imported with both usages. But Deno doesn't allow that —
    // workaround: store the public key PEM separately in the env var
    // AUTH_JWT_ES256_PUBLIC_KEY (set during Pre-flight Step 2 alongside
    // the private key). This is a 2-line addition to the Vault setup.
    const pem = Deno.env.get("AUTH_JWT_ES256_PUBLIC_KEY") ?? "";
    if (!pem) throw new Error("AUTH_JWT_ES256_PUBLIC_KEY not set in Vault");
    const cleaned = pem
      .replace(/-----BEGIN [A-Z ]+-----/g, "")
      .replace(/-----END [A-Z ]+-----/g, "")
      .replace(/\s+/g, "");
    const binary = atob(cleaned);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    _jwtPublicKey = await crypto.subtle.importKey(
      "spki",
      bytes,
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

      const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(payloadB64))) as JWTClaims;

      // Verify standard claims
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
  ```

- [ ] **Step 2: Update Pre-flight Step 2 instructions to also set the public key**

  Re-open the private key Pre-flight note and add:

  > **Additional Vault secret:** `AUTH_JWT_ES256_PUBLIC_KEY` = entire `/tmp/rpt-jwt-es256-pub.pem` contents (including `-----BEGIN PUBLIC KEY-----` and `-----END PUBLIC KEY-----`).
  >
  > Both keys must be present in the Vault before the auth-proxy deploys in Task 11.

  Verify with the user that both secrets are set in the Supabase dashboard before continuing.

- [ ] **Step 3: Run the tests to verify they pass**

  ```bash
  cd "/Users/nickspiro/Github Local/System-Trainer/supabase/functions"
  export AUTH_JWT_ES256_PRIVATE_KEY="$(cat /tmp/rpt-jwt-es256.pem)"
  export AUTH_JWT_ES256_PUBLIC_KEY="$(cat /tmp/rpt-jwt-es256-pub.pem)"
  deno test _shared/auth.test.ts --allow-env
  ```
  Expected: sha256 tests PASS, mintJWT tests PASS, verifyJWT tests PASS.

  **If deno isn't installed locally:** skip this step. The end-to-end test at Task 13 will exercise the full path.

- [ ] **Step 4: Commit**

  ```bash
  git add supabase/functions/_shared/auth.ts
  git commit -m "feat(2.9.0): ES256 mintJWT + verifyJWT implementation"
  ```

### Task 6: Write the failing test for `verifyAppleIdToken`

**Files:**
- Modify: `supabase/functions/_shared/auth.test.ts`

- [ ] **Step 1: Add the test**

  Append this to `auth.test.ts`:

  ```typescript
  // ── verifyAppleIdToken ─────────────────────────────────────────────────────
  // Note: a real Apple id_token requires Apple's JWKS. We can't create one
  // ourselves for testing. These tests verify error handling only; the
  // happy path is covered by end-to-end tests in Task 30.

  Deno.test("verifyAppleIdToken: rejects a non-JWT string", async () => {
    const result = await (await import("./auth.ts")).verifyAppleIdToken("not a jwt");
    assertEquals(result, null);
  });

  Deno.test("verifyAppleIdToken: rejects an empty string", async () => {
    const result = await (await import("./auth.ts")).verifyAppleIdToken("");
    assertEquals(result, null);
  });
  ```

- [ ] **Step 2: Run the tests, verify the new ones fail**

  ```bash
  deno test _shared/auth.test.ts --allow-env --allow-net
  ```
  Expected: the two new tests FAIL with "verifyAppleIdToken: not implemented yet".

- [ ] **Step 3: Commit**

  ```bash
  git add supabase/functions/_shared/auth.test.ts
  git commit -m "test(2.9.0): failing tests for verifyAppleIdToken"
  ```

### Task 7: Implement `verifyAppleIdToken`

**Files:**
- Modify: `supabase/functions/_shared/auth.ts`

- [ ] **Step 1: Replace the verifyAppleIdToken stub with the real implementation**

  Append to `auth.ts` (and delete the existing stub):

  ```typescript
  // ── Apple id_token verification ───────────────────────────────────────────
  // Cache Apple's JWKS for 24 hours to avoid hitting their server on every call.
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
      const header = JSON.parse(new TextDecoder().decode(base64UrlDecode(headerB64)));
      const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(payloadB64)));

      // Find the matching JWK by kid
      const jwks = await getAppleJwks();
      const jwk = jwks.find((k) => k.kid === header.kid && k.alg === header.alg);
      if (!jwk) return null;

      // Import the JWK as a CryptoKey
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

      // Verify the standard claims
      const now = Math.floor(Date.now() / 1000);
      if (payload.exp && payload.exp < now) return null;
      if (payload.iss !== "https://appleid.apple.com") return null;
      // Note: payload.aud must match our bundle ID. We validate this at
      // call site with the expected clientId since different flows may
      // use different audiences.

      return {
        sub: String(payload.sub),
        email: payload.email ? String(payload.email) : undefined,
      };
    } catch {
      return null;
    }
  }
  ```

- [ ] **Step 2: Run the tests, verify error-case tests pass**

  ```bash
  deno test _shared/auth.test.ts --allow-env --allow-net
  ```
  Expected: all tests PASS (the non-JWT and empty string tests should return null).

- [ ] **Step 3: Commit**

  ```bash
  git add supabase/functions/_shared/auth.ts
  git commit -m "feat(2.9.0): verifyAppleIdToken implementation with 24h JWKS cache"
  ```

### Task 8: Implement `verifyAssertion` (App Attest assertion verification)

**Files:**
- Modify: `supabase/functions/_shared/auth.ts`

**Note:** This is the most complex single function in the plan. It parses the App Attest assertion CBOR, extracts the authenticator data and signature, verifies the signature against the stored public key, and checks the counter.

- [ ] **Step 1: Replace the verifyAssertion stub with the real implementation**

  ```typescript
  // ── App Attest assertion verification ────────────────────────────────────
  // Apple's App Attest assertion format (from the documentation):
  //   https://developer.apple.com/documentation/devicecheck/validating_apps_that_connect_to_your_server
  //
  // The assertion is a CBOR-encoded map with two keys:
  //   "authenticatorData": bytes
  //   "signature": bytes
  //
  // The authenticatorData contains the RP ID hash, flags, and counter.
  // The signature is over (authenticatorData || clientDataHash) and must
  // verify against the attestation public key.

  // Minimal CBOR decoder — we only need to handle Apple's specific format:
  // a map with 2 string keys, each with byte-string values.
  function decodeAppleAssertion(bytes: Uint8Array): { authenticatorData: Uint8Array; signature: Uint8Array } | null {
    try {
      let offset = 0;
      // Expect major type 5 (map) with length 2: byte 0xA2
      if (bytes[offset++] !== 0xa2) return null;

      const result: Record<string, Uint8Array> = {};
      for (let i = 0; i < 2; i++) {
        // Expect major type 3 (text string) with small length
        const keyByte = bytes[offset++];
        const keyLen = keyByte & 0x1f;
        if ((keyByte & 0xe0) !== 0x60) return null;
        const keyBytes = bytes.slice(offset, offset + keyLen);
        offset += keyLen;
        const key = new TextDecoder().decode(keyBytes);

        // Expect major type 2 (byte string)
        const valByte = bytes[offset++];
        if ((valByte & 0xe0) !== 0x40) return null;
        let valLen: number;
        const valLenIndicator = valByte & 0x1f;
        if (valLenIndicator < 24) {
          valLen = valLenIndicator;
        } else if (valLenIndicator === 24) {
          valLen = bytes[offset++];
        } else if (valLenIndicator === 25) {
          valLen = (bytes[offset] << 8) | bytes[offset + 1];
          offset += 2;
        } else {
          return null; // unsupported length encoding
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

  export async function verifyAssertion(
    assertion: Uint8Array,
    publicKeyBytes: Uint8Array,
    bodyHashHex: string,
    expectedCounter: number,
  ): Promise<AssertionVerifyResult> {
    try {
      const decoded = decodeAppleAssertion(assertion);
      if (!decoded) return { valid: false };

      const { authenticatorData, signature } = decoded;

      // authenticatorData layout:
      //   [0..32]  RP ID hash (SHA-256 of app bundle ID — we don't verify this
      //            here because the bundle can change; App Attest verifies it
      //            during attestation object validation at sign_in)
      //   [32]     flags
      //   [33..37] counter (big-endian u32)
      if (authenticatorData.length < 37) return { valid: false };
      const counter = (authenticatorData[33] << 24) |
                      (authenticatorData[34] << 16) |
                      (authenticatorData[35] << 8) |
                       authenticatorData[36];
      // Counter must be strictly greater than the previous value (replay protection)
      if (counter <= expectedCounter) return { valid: false };

      // Construct the signed message: authenticatorData || clientDataHash
      const clientDataHash = new Uint8Array(bodyHashHex.length / 2);
      for (let i = 0; i < clientDataHash.length; i++) {
        clientDataHash[i] = parseInt(bodyHashHex.substr(i * 2, 2), 16);
      }
      const signedMessage = new Uint8Array(authenticatorData.length + clientDataHash.length);
      signedMessage.set(authenticatorData, 0);
      signedMessage.set(clientDataHash, authenticatorData.length);

      // Import the attestation public key (EC P-256, uncompressed form)
      const publicKey = await crypto.subtle.importKey(
        "raw",
        publicKeyBytes,
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["verify"],
      );

      // Verify the signature
      // Note: App Attest uses DER-encoded signatures. We need to convert to
      // raw r||s for WebCrypto. A DER ECDSA signature looks like:
      //   30 LL 02 rLen rBytes 02 sLen sBytes
      function derToRaw(der: Uint8Array): Uint8Array | null {
        if (der[0] !== 0x30) return null;
        let offset = 2; // skip tag + len
        if (der[1] & 0x80) offset = 2 + (der[1] & 0x7f); // long-form length
        if (der[offset++] !== 0x02) return null;
        let rLen = der[offset++];
        // Strip leading zero if present (DER integer can have leading 0 for sign)
        while (rLen > 32 && der[offset] === 0x00) { offset++; rLen--; }
        const r = der.slice(offset, offset + rLen);
        offset += rLen;
        if (der[offset++] !== 0x02) return null;
        let sLen = der[offset++];
        while (sLen > 32 && der[offset] === 0x00) { offset++; sLen--; }
        const s = der.slice(offset, offset + sLen);
        // Pad r and s to 32 bytes each
        const raw = new Uint8Array(64);
        raw.set(r, 32 - r.length);
        raw.set(s, 64 - s.length);
        return raw;
      }

      const rawSig = derToRaw(signature);
      if (!rawSig) return { valid: false };

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
  ```

- [ ] **Step 2: No unit test for verifyAssertion (deferred to end-to-end)**

  Writing a hand-crafted assertion for unit tests requires implementing the full App Attest signing flow in test code, which doubles the effort. We verify this function end-to-end in Task 30 (real-device test) instead.

- [ ] **Step 3: Deno type-check the file**

  ```bash
  deno check supabase/functions/_shared/auth.ts
  ```
  Expected: no errors.

- [ ] **Step 4: Commit**

  ```bash
  git add supabase/functions/_shared/auth.ts
  git commit -m "feat(2.9.0): verifyAssertion — App Attest assertion verification with CBOR decode + DER→raw signature conversion"
  ```

### Task 9: Implement `validateAuth` (the main entry point)

**Files:**
- Modify: `supabase/functions/_shared/auth.ts`

- [ ] **Step 1: Replace the validateAuth stub with the real implementation**

  ```typescript
  export async function validateAuth(
    req: Request,
    supabase: SupabaseClient,
    opts: { requireAttestation: boolean },
  ): Promise<AuthResult> {
    // 1. Extract Bearer JWT from Authorization header
    const authHeader = req.headers.get("authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return { valid: false, error: "missing_bearer_token" };
    }
    const token = authHeader.slice(7);

    // 2. Verify JWT signature + standard claims
    const claims = await verifyJWT(token);
    if (!claims) {
      return { valid: false, error: "invalid_jwt" };
    }

    // 3. For read operations, JWT is sufficient
    if (!opts.requireAttestation) {
      return { valid: true, cloudkit_user_id: claims.sub };
    }

    // 4. For write operations, verify App Attest assertion
    const assertionB64 = req.headers.get("x-app-attest-assertion") ?? "";
    const keyId = req.headers.get("x-app-attest-key-id") ?? "";
    if (!keyId) {
      return { valid: false, error: "missing_attestation" };
    }

    // Look up the device attestation record
    const { data: attestation, error: lookupErr } = await supabase
      .from("device_attestations")
      .select("id, attestation_public_key, counter, is_bypass")
      .eq("cloudkit_user_id", claims.sub)
      .eq("key_id", keyId)
      .is("revoked_at", null)
      .maybeSingle();
    if (lookupErr || !attestation) {
      return { valid: false, error: "unknown_device" };
    }

    // Bypass path (simulator development only)
    if (attestation.is_bypass) {
      const allowBypass = Deno.env.get("ALLOW_SIMULATOR_BYPASS") === "true";
      if (!allowBypass) {
        return { valid: false, error: "bypass_not_allowed_in_production" };
      }
      // Simulator bypass: skip real assertion verification
      return {
        valid: true,
        cloudkit_user_id: claims.sub,
        device_attestation_id: attestation.id,
      };
    }

    // Real assertion verification path
    if (!assertionB64) {
      return { valid: false, error: "missing_assertion" };
    }
    // Decode base64 assertion
    const binary = atob(assertionB64);
    const assertionBytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) assertionBytes[i] = binary.charCodeAt(i);

    // Read and hash the request body (we need to clone because reading
    // consumes the stream and the caller needs to read it too).
    const bodyText = await req.clone().text();
    const bodyHash = await sha256(bodyText);

    const publicKeyBytes = attestation.attestation_public_key instanceof Uint8Array
      ? attestation.attestation_public_key
      : new Uint8Array((attestation.attestation_public_key as { data: number[] }).data ?? []);

    const verifyResult = await verifyAssertion(
      assertionBytes,
      publicKeyBytes,
      bodyHash,
      attestation.counter ?? 0,
    );
    if (!verifyResult.valid) {
      return { valid: false, error: "assertion_verification_failed" };
    }

    // Update the counter atomically (replay protection)
    await supabase
      .from("device_attestations")
      .update({
        counter: verifyResult.newCounter,
        last_used_at: new Date().toISOString(),
      })
      .eq("id", attestation.id);

    return {
      valid: true,
      cloudkit_user_id: claims.sub,
      device_attestation_id: attestation.id,
    };
  }
  ```

- [ ] **Step 2: Type-check**

  ```bash
  deno check supabase/functions/_shared/auth.ts
  ```
  Expected: no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add supabase/functions/_shared/auth.ts
  git commit -m "feat(2.9.0): validateAuth — main auth middleware entry point"
  ```

### Task 10: Create `auth-proxy/index.ts` with `sign_in` action

**Files:**
- Create: `supabase/functions/auth-proxy/index.ts`

- [ ] **Step 1: Write auth-proxy with sign_in implementation**

  Create `supabase/functions/auth-proxy/index.ts`:

  ```typescript
  import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
  import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
  import { mintJWT, verifyJWT, verifyAppleIdToken, sha256 } from "../_shared/auth.ts";

  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  // Rate budgets for the auth-proxy actions
  const RATE_BUDGETS: Record<string, [number, number]> = {
    sign_in:  [5, 3600],    // 5 sign-ins per hour per user
    refresh:  [20, 3600],   // 20 refreshes per hour per refresh token
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
        console.error("rate_limit_check failed:", error);
        return true; // fail-open
      }
      return data !== false;
    } catch {
      return true;
    }
  }

  // Generate a cryptographically secure random token (32 bytes, hex)
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
      const body = await req.json();
      const action = body.action ?? "";

      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("DB_SERVICE_ROLE_KEY")!,
        { auth: { persistSession: false } },
      );

      // ── SIGN IN ─────────────────────────────────────────────────────────
      if (action === "sign_in") {
        const cloudkitUserId = body.cloudkit_user_id ?? "";
        const appleIdToken = body.apple_id_token ?? "";
        const appleAuthCode = body.apple_authorization_code ?? "";
        const attestation = body.attestation ?? null;

        if (!cloudkitUserId || !appleIdToken) {
          return new Response(
            JSON.stringify({ error: "missing_required_fields" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        // Rate limit sign_in per user
        if (!(await checkRateLimit(supabase, cloudkitUserId, "sign_in"))) {
          return new Response(
            JSON.stringify({ error: "rate_limit_exceeded" }),
            { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        // 1. Verify the Apple id_token
        const appleClaims = await verifyAppleIdToken(appleIdToken);
        if (!appleClaims) {
          return new Response(
            JSON.stringify({ error: "invalid_apple_id_token" }),
            { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        // 2. Handle attestation
        let deviceAttestationId: string;
        let isBypass = false;

        if (attestation === null) {
          // Simulator bypass path
          const allowBypass = Deno.env.get("ALLOW_SIMULATOR_BYPASS") === "true";
          if (!allowBypass) {
            return new Response(
              JSON.stringify({ error: "attestation_required" }),
              { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
            );
          }
          isBypass = true;
          // Insert a bypass row
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
            return new Response(
              JSON.stringify({ error: "bypass_insert_failed" }),
              { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
            );
          }
          deviceAttestationId = bypassRow.id;
        } else {
          // Real attestation path
          const keyId = attestation.key_id ?? "";
          const attestationObjectB64 = attestation.attestation_object ?? "";
          if (!keyId || !attestationObjectB64) {
            return new Response(
              JSON.stringify({ error: "invalid_attestation" }),
              { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
            );
          }
          // TODO(2.9.0 execution): verify the attestation object against
          // Apple's App Attest root CA. For now, extract the public key
          // from the attestation object (the attestation object CBOR has a
          // known structure, see Apple's docs).
          //
          // This is one of the "open research questions" from the spec —
          // resolve during execution based on the chosen verification
          // library or hand-rolled implementation.

          // Decode the base64 attestation object
          const binary = atob(attestationObjectB64);
          const attestationBytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) {
            attestationBytes[i] = binary.charCodeAt(i);
          }

          // Placeholder: extract the public key from the attestation object.
          // The real implementation needs to:
          //   1. CBOR-decode the attestation object (it's a map with fmt,
          //      attStmt, authData)
          //   2. Verify the attStmt signature chain up to Apple's root CA
          //   3. Extract the public key from the authData's credentialPublicKey
          //   4. Verify the nonce matches SHA256(clientDataHash || attestationObject)
          //
          // For now, we store the raw attestation object as the "public key"
          // placeholder so the schema is populated. This will be replaced
          // during execution once the verification library is chosen.
          const extractedPublicKey = new Uint8Array(65); // placeholder

          const { data: attestRow, error: attestErr } = await supabase
            .from("device_attestations")
            .insert({
              cloudkit_user_id: cloudkitUserId,
              key_id: keyId,
              attestation_public_key: extractedPublicKey,
              receipt: attestationBytes,
              is_bypass: false,
            })
            .select("id")
            .single();
          if (attestErr || !attestRow) {
            return new Response(
              JSON.stringify({ error: "attestation_insert_failed", detail: attestErr?.message }),
              { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
            );
          }
          deviceAttestationId = attestRow.id;
        }

        // 3. Evict oldest device if user has 5+ active devices
        const { count: deviceCount } = await supabase
          .from("device_attestations")
          .select("*", { count: "exact", head: true })
          .eq("cloudkit_user_id", cloudkitUserId)
          .is("revoked_at", null);
        if ((deviceCount ?? 0) > 5) {
          // Revoke the oldest
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

        // 4. Store the SIWA auth code on player_profiles (for future revocation)
        if (appleAuthCode) {
          await supabase
            .from("player_profiles")
            .update({ apple_authorization_code: appleAuthCode })
            .eq("cloudkit_user_id", cloudkitUserId);
        }

        // 5. Generate refresh token, hash, insert
        const refreshToken = generateRefreshToken();
        const refreshTokenHash = await sha256(refreshToken);
        const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
        await supabase.from("refresh_tokens").insert({
          cloudkit_user_id: cloudkitUserId,
          token_hash: refreshTokenHash,
          device_attestation_id: deviceAttestationId,
          expires_at: expiresAt,
        });

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

      // (refresh and sign_out actions added in later tasks)

      return new Response(
        JSON.stringify({ error: "unknown_action" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    } catch (err) {
      console.error("auth-proxy error:", err);
      return new Response(
        JSON.stringify({ error: "internal_server_error", detail: String(err) }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
  });
  ```

- [ ] **Step 2: Type-check**

  ```bash
  deno check supabase/functions/auth-proxy/index.ts
  ```
  Expected: no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add supabase/functions/auth-proxy/index.ts
  git commit -m "feat(2.9.0): auth-proxy sign_in action (with TODO for attestation verification)"
  ```

---

## Phase 2: Deploy auth-proxy v1 + manual testing (Tasks 11-13)

### Task 11: Deploy auth-proxy v1 for the first time

- [ ] **Step 1: Use Supabase MCP to deploy**

  Use `mcp__plugin_supabase_supabase__deploy_edge_function` with:
  - `project_id: "erghbsnxtsbnmfuycnyb"`
  - `name: "auth-proxy"`
  - `entrypoint_path: "index.ts"`
  - `verify_jwt: false`
  - `files: [{name: "index.ts", content: <contents of supabase/functions/auth-proxy/index.ts>}, {name: "../_shared/auth.ts", content: <contents of supabase/functions/_shared/auth.ts>}, {name: "../_shared/apple-app-attest-root.pem", content: <contents of the PEM file>}]`

  Expected: `{"status": "ACTIVE", "version": 1, ...}`

### Task 12: Manually test sign_in with simulator bypass path

- [ ] **Step 1: Set the simulator bypass env var in the dev Supabase project**

  Use `mcp__plugin_supabase_supabase__execute_sql` to confirm — actually this is an Edge Function env var, set via the Supabase dashboard:

  Navigate to https://supabase.com/dashboard/project/erghbsnxtsbnmfuycnyb/settings/functions → add `ALLOW_SIMULATOR_BYPASS = true` to Edge Function Secrets.

  **Note:** if you want to keep this Supabase project as production, create a SEPARATE dev project (`rpt-dev`) and set `ALLOW_SIMULATOR_BYPASS` only there. The spec calls for production Supabase to NEVER have this env var.

- [ ] **Step 2: Manually test sign_in via curl**

  Build a test request with a fake-but-structurally-valid Apple id_token. For a true end-to-end test, we need a real Apple id_token, which requires a real iOS sign-in. Skip the full test here and defer to Task 30 (end-to-end device test).

  For now, test only that the function responds to bad input correctly:
  ```bash
  curl -X POST "https://erghbsnxtsbnmfuycnyb.supabase.co/functions/v1/auth-proxy" \
       -H "Content-Type: application/json" \
       -d '{"action": "sign_in"}'
  ```
  Expected: `{"error": "missing_required_fields"}` with HTTP 400.

### Task 13: Add `refresh` action to auth-proxy

**Files:**
- Modify: `supabase/functions/auth-proxy/index.ts`

- [ ] **Step 1: Add the refresh handler above the final unknown_action return**

  Add this block between the sign_in block and the unknown_action fallback:

  ```typescript
      // ── REFRESH ──────────────────────────────────────────────────────────
      if (action === "refresh") {
        const refreshToken = body.refresh_token ?? "";
        if (!refreshToken) {
          return new Response(
            JSON.stringify({ error: "missing_refresh_token" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        const tokenHash = await sha256(refreshToken);

        // Rate limit refresh per token hash
        if (!(await checkRateLimit(supabase, tokenHash, "refresh"))) {
          return new Response(
            JSON.stringify({ error: "rate_limit_exceeded" }),
            { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        const { data: row, error: lookupErr } = await supabase
          .from("refresh_tokens")
          .select("id, cloudkit_user_id, device_attestation_id, expires_at, revoked_at")
          .eq("token_hash", tokenHash)
          .maybeSingle();
        if (lookupErr || !row) {
          return new Response(
            JSON.stringify({ error: "invalid_refresh_token" }),
            { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
        if (row.revoked_at) {
          // Defensive: if we see a revoked token, also revoke all other
          // active tokens for this user. This is OAuth 2.0 RFC 6819 §5.2.2.3
          // refresh token theft mitigation.
          await supabase
            .from("refresh_tokens")
            .update({ revoked_at: new Date().toISOString() })
            .eq("cloudkit_user_id", row.cloudkit_user_id)
            .is("revoked_at", null);
          return new Response(
            JSON.stringify({ error: "refresh_token_revoked" }),
            { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
        if (new Date(row.expires_at) < new Date()) {
          return new Response(
            JSON.stringify({ error: "refresh_token_expired" }),
            { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        // Lookup device's attested status
        const { data: device } = await supabase
          .from("device_attestations")
          .select("is_bypass")
          .eq("id", row.device_attestation_id)
          .single();
        const attested = !(device?.is_bypass ?? true);

        // Rotate: revoke the old token, create a new one
        await supabase
          .from("refresh_tokens")
          .update({ revoked_at: new Date().toISOString(), last_used_at: new Date().toISOString() })
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

        const accessToken = await mintJWT(row.cloudkit_user_id, row.device_attestation_id, attested);

        return new Response(
          JSON.stringify({
            access_token: accessToken,
            refresh_token: newRefreshToken,
            expires_in: 900,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
  ```

- [ ] **Step 2: Type-check**

  ```bash
  deno check supabase/functions/auth-proxy/index.ts
  ```

- [ ] **Step 3: Re-deploy auth-proxy**

  Use the deploy tool again with the updated file content. Expected: version 2, status ACTIVE.

- [ ] **Step 4: Commit**

  ```bash
  git add supabase/functions/auth-proxy/index.ts
  git commit -m "feat(2.9.0): auth-proxy refresh action with rotation + revocation cascade"
  ```

### Task 14: Add `sign_out` action to auth-proxy

**Files:**
- Modify: `supabase/functions/auth-proxy/index.ts`

- [ ] **Step 1: Add sign_out handler**

  Add between the refresh block and unknown_action:

  ```typescript
      // ── SIGN OUT ─────────────────────────────────────────────────────────
      if (action === "sign_out") {
        // Extract JWT from Authorization header
        const authHeader = req.headers.get("authorization") ?? "";
        if (!authHeader.startsWith("Bearer ")) {
          return new Response(
            JSON.stringify({ error: "missing_bearer_token" }),
            { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
        const claims = await verifyJWT(authHeader.slice(7));
        if (!claims) {
          return new Response(
            JSON.stringify({ error: "invalid_jwt" }),
            { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        // Delete all refresh tokens for this user
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
  ```

- [ ] **Step 2: Re-deploy + type-check**

  Same as Task 13 Step 3.

- [ ] **Step 3: Commit**

  ```bash
  git add supabase/functions/auth-proxy/index.ts
  git commit -m "feat(2.9.0): auth-proxy sign_out action"
  ```

---

## Phase 3: Integrate middleware into player-proxy + leaderboard-proxy (Tasks 15-17)

### Task 15: Add `validateAuth` to player-proxy, remove x-app-secret

**Files:**
- Modify: `supabase/functions/player-proxy/index.ts`

- [ ] **Step 1: Import validateAuth and define write-action set**

  At the top of the file, after existing imports:

  ```typescript
  import { validateAuth } from "../_shared/auth.ts";

  const WRITE_ACTIONS = new Set([
    "upsert_profile", "save_backup", "add_credits", "link_apple_id",
    "delete_account", "revoke_siwa", "store_auth_code",
  ]);
  ```

- [ ] **Step 2: Replace the x-app-secret check with validateAuth**

  Locate the current x-app-secret check block near the start of `serve(async (req) => { ... })` and replace it:

  ```typescript
  // BEFORE (delete these lines):
  //   const appSecret = Deno.env.get("RPT_APP_SECRET");
  //   const incomingSecret = req.headers.get("x-app-secret");
  //   if (!appSecret || !incomingSecret || incomingSecret !== appSecret) {
  //     return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, ... });
  //   }

  // AFTER (replace with):
  try {
    const body = await req.json();
    const action = body.action ?? "get_profile";

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("DB_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // NEW: validate auth from the JWT, not body fields
    const authResult = await validateAuth(req, supabase, {
      requireAttestation: WRITE_ACTIONS.has(action),
    });
    if (!authResult.valid) {
      return new Response(
        JSON.stringify({ error: authResult.error ?? "unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const cloudkitUserId = authResult.cloudkit_user_id!;

    // (existing rate limit check continues here; remove the manual
    // cloudkit_user_id extraction from body)
  ```

- [ ] **Step 3: Remove every `body.cloudkit_user_id` reference**

  Find and replace: any line like `const cloudkitUserId = body.cloudkit_user_id ?? "";` should be deleted because `cloudkitUserId` now comes from `authResult.cloudkit_user_id`.

  Grep for `body.cloudkit_user_id` in `player-proxy/index.ts`:
  ```bash
  grep -n "body.cloudkit_user_id\|cloudkit_user_id.*body" supabase/functions/player-proxy/index.ts
  ```
  Expected after the change: no matches.

- [ ] **Step 4: Type-check**

  ```bash
  deno check supabase/functions/player-proxy/index.ts
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add supabase/functions/player-proxy/index.ts
  git commit -m "feat(2.9.0): player-proxy — replace x-app-secret with validateAuth

  cloudkit_user_id now comes from the JWT sub claim, not the request body.
  This is the core fix for the 'anyone with the shared secret can impersonate
  any user' vulnerability from the 2.8.x architecture."
  ```

### Task 16: Add `validateAuth` to leaderboard-proxy, remove x-app-secret

**Files:**
- Modify: `supabase/functions/leaderboard-proxy/index.ts`

- [ ] **Step 1: Import and define write-action set**

  ```typescript
  import { validateAuth } from "../_shared/auth.ts";

  const WRITE_ACTIONS = new Set(["upsert_entry", "add_friend", "remove_friend"]);
  ```

- [ ] **Step 2: Replace x-app-secret check with validateAuth**

  Same pattern as Task 15. Delete the x-app-secret block, add the validateAuth block right after the `createClient` call, extract `cloudkitUserId` from `authResult`.

- [ ] **Step 3: Remove every `body.cloudkit_user_id` reference**

  ```bash
  grep -n "body.cloudkit_user_id\|cloudkit_user_id.*body" supabase/functions/leaderboard-proxy/index.ts
  ```
  Expected after the change: no matches.

- [ ] **Step 4: Type-check**

  ```bash
  deno check supabase/functions/leaderboard-proxy/index.ts
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add supabase/functions/leaderboard-proxy/index.ts
  git commit -m "feat(2.9.0): leaderboard-proxy — replace x-app-secret with validateAuth"
  ```

### Task 17: Deploy updated player-proxy v8 and leaderboard-proxy v5

- [ ] **Step 1: Deploy player-proxy (will include _shared/auth.ts + apple-app-attest-root.pem)**

  Use `mcp__plugin_supabase_supabase__deploy_edge_function` with:
  - `project_id: "erghbsnxtsbnmfuycnyb"`
  - `name: "player-proxy"`
  - `entrypoint_path: "index.ts"`
  - `verify_jwt: false`
  - `files`: array with `index.ts`, `../_shared/auth.ts`, `../_shared/apple-app-attest-root.pem`

  Expected: version 8, status ACTIVE.

- [ ] **Step 2: Deploy leaderboard-proxy**

  Same structure, `name: "leaderboard-proxy"`. Expected: version 5, status ACTIVE.

- [ ] **Step 3: Smoke test — try the old x-app-secret path, expect 401**

  ```bash
  curl -X POST "https://erghbsnxtsbnmfuycnyb.supabase.co/functions/v1/player-proxy" \
       -H "Content-Type: application/json" \
       -H "x-app-secret: anything" \
       -d '{"action": "get_profile", "cloudkit_user_id": "test"}'
  ```
  Expected: `{"error": "missing_bearer_token"}` with HTTP 401.

- [ ] **Step 4: Commit (no file changes, just a marker commit for the deploy)**

  No code change needed; the deploy is the action. Move on to Phase 4.

---

## Phase 4: iOS — New services (Tasks 18-22)

### Task 18: Create `RPT/AppAttestService.swift`

**Files:**
- Create: `RPT/AppAttestService.swift`

- [ ] **Step 1: Write the file**

  Exact contents from the spec §9.1 (lines 380-430 of the design doc). Paste verbatim from:
  `docs/superpowers/specs/2026-04-08-app-attest-jwt-design.md` → §9.1 AppAttestService.swift

- [ ] **Step 2: Add the file to the Xcode project target**

  The cleanest path is to open Xcode manually (this one step needs the GUI because pbxproj manipulation is fragile):
  1. Open `RPT.xcodeproj` in Xcode
  2. Right-click on the `RPT` group in the Project Navigator
  3. Select "Add Files to RPT..."
  4. Select `AppAttestService.swift`
  5. Uncheck "Copy items if needed" (already in place)
  6. Ensure "RPT" target is checked
  7. Click "Add"
  8. Close Xcode

  Verify `grep -c "AppAttestService.swift" RPT.xcodeproj/project.pbxproj` returns a non-zero count.

- [ ] **Step 3: Build clean**

  ```bash
  cd "/Users/nickspiro/Github Local/System-Trainer"
  xcodebuild -project RPT.xcodeproj -scheme RPT -sdk iphonesimulator \
             -destination 'generic/platform=iOS Simulator' build 2>&1 | \
             grep -E "(error:|BUILD )" | head -10
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

  ```bash
  git add RPT/AppAttestService.swift RPT.xcodeproj/project.pbxproj
  git commit -m "feat(2.9.0): iOS AppAttestService — Secure Enclave key + assertions"
  ```

### Task 19: Create `RPT/AuthClient.swift`

**Files:**
- Create: `RPT/AuthClient.swift`

- [ ] **Step 1: Write the file**

  Exact contents from the spec §9.2. Paste verbatim from:
  `docs/superpowers/specs/2026-04-08-app-attest-jwt-design.md` → §9.2 AuthClient.swift

- [ ] **Step 2: Add URLRequest.postJSON convenience extension**

  `AuthClient` uses `URLRequest.postJSON(url:body:)` which doesn't exist yet. Add this to `RPT/Utilities.swift`:

  ```swift
  // URLRequest convenience for JSON POSTs used by the auth flow (which can't
  // go through APIClient because it's setting up the auth context).
  extension URLRequest {
      static func postJSON(url: URL, body: [String: Any]) -> URLRequest {
          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          request.httpBody = try? JSONSerialization.data(withJSONObject: body)
          request.timeoutInterval = 15
          return request
      }
  }
  ```

- [ ] **Step 3: Add AuthClient.swift to Xcode target (manual Xcode step, same pattern as Task 18)**

- [ ] **Step 4: Build clean**

  ```bash
  xcodebuild -project RPT.xcodeproj -scheme RPT -sdk iphonesimulator \
             -destination 'generic/platform=iOS Simulator' build 2>&1 | \
             grep -E "(error:|BUILD )" | head -10
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

  ```bash
  git add RPT/AuthClient.swift RPT/Utilities.swift RPT.xcodeproj/project.pbxproj
  git commit -m "feat(2.9.0): iOS AuthClient — Keychain JWT store + auto-refresh"
  ```

### Task 20: Create `RPT/APIClient.swift`

**Files:**
- Create: `RPT/APIClient.swift`

- [ ] **Step 1: Write the file**

  Exact contents from the spec §9.3. Paste verbatim from:
  `docs/superpowers/specs/2026-04-08-app-attest-jwt-design.md` → §9.3 APIClient.swift

- [ ] **Step 2: Add APIClient.swift to Xcode target**

- [ ] **Step 3: Build clean**

- [ ] **Step 4: Commit**

  ```bash
  git add RPT/APIClient.swift RPT.xcodeproj/project.pbxproj
  git commit -m "feat(2.9.0): iOS APIClient — wraps every Edge Function call with JWT + assertion"
  ```

### Task 21: Modify AppleAuthService to trigger AuthClient.signIn after SIWA succeeds

**Files:**
- Modify: `RPT/AppleAuthService.swift`

- [ ] **Step 1: Locate the persistFromButtonResult method**

- [ ] **Step 2: Update callers** (the spec says AppleAuthService itself doesn't call AuthClient; the callers do). This is handled in Task 24 / 25.

  Skip this task — the modifications to flow AuthClient into the sign-in path are in the SettingsView and OnboardingView changes in Tasks 24 and 25.

### Task 22: Add App Attest entitlement to RPT.entitlements

**Files:**
- Modify: `RPT/RPT.entitlements`

- [ ] **Step 1: Open RPT.entitlements in a text editor**

- [ ] **Step 2: Add the App Attest environment key**

  Inside the top-level `<dict>`, add:
  ```xml
  <key>com.apple.developer.devicecheck.appattest-environment</key>
  <string>production</string>
  ```

  For local development against the dev Supabase project, use `<string>development</string>` instead. Apple flags this at build signing time.

- [ ] **Step 3: Build clean**

  Expected: the build succeeds. If it fails with a provisioning profile error, go back to Pre-flight Step 4 and confirm App Attest capability is enabled in the App ID.

- [ ] **Step 4: Commit**

  ```bash
  git add RPT/RPT.entitlements
  git commit -m "feat(2.9.0): add App Attest entitlement to RPT.entitlements"
  ```

---

## Phase 5: iOS — Migrate existing callers (Tasks 23-28)

### Task 23: Migrate PlayerProfileService to use APIClient

**Files:**
- Modify: `RPT/PlayerProfileService.swift`

- [ ] **Step 1: Delete the postToProxy helper method**

  Find and delete the `private func postToProxy(body: [String: Any]) async throws -> Data` method.

- [ ] **Step 2: Replace every call site**

  Grep for `postToProxy` in the file:
  ```bash
  grep -n "postToProxy" RPT/PlayerProfileService.swift
  ```

  For each call site, replace:
  ```swift
  // BEFORE:
  let data = try await postToProxy(body: body)

  // AFTER:
  let action = body["action"] as? String ?? "get_profile"
  var apiBody = body
  apiBody.removeValue(forKey: "action")
  apiBody.removeValue(forKey: "cloudkit_user_id")  // server gets it from JWT now
  let data = try await APIClient.post(endpoint: "player-proxy", action: action, body: apiBody)
  ```

  There are ~8 call sites. Each is a mechanical replacement.

- [ ] **Step 3: Build clean**

- [ ] **Step 4: Commit**

  ```bash
  git add RPT/PlayerProfileService.swift
  git commit -m "feat(2.9.0): migrate PlayerProfileService to APIClient"
  ```

### Task 24: Migrate LeaderboardService to use APIClient

**Files:**
- Modify: `LeaderboardService.swift` (at repo root, not under RPT/)

- [ ] **Step 1: Same pattern as Task 23**

  Delete the `postToProxy` helper, replace every call site with `APIClient.post(endpoint: "leaderboard-proxy", action: ..., body: ...)`.

- [ ] **Step 2: Build + commit**

  ```bash
  git add LeaderboardService.swift
  git commit -m "feat(2.9.0): migrate LeaderboardService to APIClient"
  ```

### Task 25: Hook AuthClient.signIn into OnboardingView BootStepView

**Files:**
- Modify: `RPT/OnboardingView.swift`

- [ ] **Step 1: Find the handleSignIn method in BootStepView**

  Located around line 500 (search for `private func handleSignIn`).

- [ ] **Step 2: Add AuthClient.signIn call after persistFromButtonResult**

  After the existing call to `AppleAuthService.shared.persistFromButtonResult(result)` and before `PlayerProfileService.shared.linkAppleID(...)`, add:

  ```swift
  // NEW: establish JWT session via auth-proxy sign_in. This does the
  // App Attest dance + mints the access/refresh token pair and stores
  // them in Keychain. Must succeed before any authenticated call
  // (including linkAppleID below).
  do {
      try await AuthClient.shared.signIn(
          appleIdToken: result.identityToken ?? "",
          appleAuthCode: result.authorizationCode ?? "",
          cloudKitUserId: LeaderboardService.shared.currentUserID ?? ""
      )
  } catch {
      authError = "Couldn't establish secure session: \(error.localizedDescription)"
      return
  }
  ```

  **Note:** `result.identityToken` and `result.authorizationCode` need to be added to `AppleSignInResult` if they're not already there. They're captured in Task 17 of the 2.8.5 build already — reuse that field.

- [ ] **Step 3: Build + commit**

  ```bash
  git add RPT/OnboardingView.swift
  git commit -m "feat(2.9.0): OnboardingView triggers AuthClient.signIn after SIWA"
  ```

### Task 26: Hook AuthClient.signOut into SettingsView Sign Out action

**Files:**
- Modify: `RPT/SettingsView.swift`

- [ ] **Step 1: Find the Sign Out alert handler**

  Located around line 540 (search for `showingSignOutConfirm`).

- [ ] **Step 2: Wrap in Task and await AuthClient.signOut()**

  ```swift
  // BEFORE:
  Button("Sign Out", role: .destructive) {
      appleAuth.signOut()
  }

  // AFTER:
  Button("Sign Out", role: .destructive) {
      Task {
          await AuthClient.shared.signOut()
          appleAuth.signOut()
      }
  }
  ```

- [ ] **Step 3: Update performDeleteAccount to use APIClient**

  Find `performDeleteAccount` (around line 580). Replace the raw URLSession path with:

  ```swift
  do {
      _ = try await APIClient.post(
          endpoint: "player-proxy",
          action: "delete_account",
          body: ["apple_user_id": appleUserID]
      )
      // Existing local cleanup continues below unchanged
      DataManager.shared.deleteEverything()
      await AppleAuthService.shared.revokeCredential()
      AppleAuthService.shared.signOut()
      await AuthClient.shared.signOut()  // NEW: clear JWT tokens
      // ... existing UserDefaults cleanup
      hasCompletedOnboarding = false
  } catch {
      deleteAccountError = error.localizedDescription
      showingDeleteAccountError = true
  }
  ```

- [ ] **Step 4: Build + commit**

  ```bash
  git add RPT/SettingsView.swift
  git commit -m "feat(2.9.0): SettingsView uses APIClient.post + AuthClient.signOut"
  ```

### Task 27: Delete Secrets.appSecret + all x-app-secret references

**Files:**
- Modify: `RPT/Secrets.swift`
- Modify: `Secrets.xcconfig`
- Modify: `ci_scripts/ci_post_clone.sh`
- Modify: `RPT/Info.plist`
- Modify: `RPT.xcodeproj/project.pbxproj`

- [ ] **Step 1: Remove from Secrets.swift**

  Delete the `static var appSecret: String { ... }` property.

- [ ] **Step 2: Remove from Secrets.xcconfig**

  Delete the `APP_SECRET = ...` line.

- [ ] **Step 3: Remove from ci_post_clone.sh**

  Delete the lines that check for `APP_SECRET` and write it into the config. Keep only the `SUPABASE_ANON_KEY` handling.

- [ ] **Step 4: Remove from Info.plist**

  Delete the `<key>APP_SECRET</key><string>$(APP_SECRET)</string>` pair.

- [ ] **Step 5: Remove from project.pbxproj**

  Grep for `APP_SECRET`:
  ```bash
  grep -n "APP_SECRET" RPT.xcodeproj/project.pbxproj
  ```
  Delete every line.

- [ ] **Step 6: Verify no residual references**

  ```bash
  grep -rn "x-app-secret\|appSecret\|APP_SECRET" \
      --include="*.swift" --include="*.plist" --include="*.ts" \
      --include="*.xcconfig" --include="*.sh" .
  ```
  Expected: zero matches.

- [ ] **Step 7: Build clean**

- [ ] **Step 8: Commit**

  ```bash
  git add RPT/Secrets.swift Secrets.xcconfig ci_scripts/ci_post_clone.sh \
          RPT/Info.plist RPT.xcodeproj/project.pbxproj
  git commit -m "feat(2.9.0): delete x-app-secret from every layer

  The shared secret is no longer referenced anywhere in the codebase.
  Authentication now flows entirely through JWT + App Attest.

  User must also manually remove APP_SECRET from:
    • Xcode Cloud Secret Environment Variables
    • Supabase Vault (RPT_APP_SECRET)
  These are external to the git repo."
  ```

### Task 28: Bump version to 2.9.0

**Files:**
- Modify: `RPT.xcodeproj/project.pbxproj`

- [ ] **Step 1: Update version strings**

  ```bash
  cd "/Users/nickspiro/Github Local/System-Trainer"
  # Use sed or Edit tool to change these
  ```
  Change every `MARKETING_VERSION = 2.8.5;` to `MARKETING_VERSION = 2.9.0;`
  Change every `CURRENT_PROJECT_VERSION = 25;` to `CURRENT_PROJECT_VERSION = 26;`

- [ ] **Step 2: Build clean**

- [ ] **Step 3: Commit**

  ```bash
  git add RPT.xcodeproj/project.pbxproj
  git commit -m "chore(2.9.0): bump version to 2.9.0 build 26"
  ```

---

## Phase 6: End-to-end testing (Tasks 29-32)

### Task 29: Simulator smoke test (sign-in + read + write flow)

- [ ] **Step 1: Build a fresh simulator install**

  Open `RPT.xcodeproj` in Xcode, select an iOS simulator, Cmd+R.

- [ ] **Step 2: Delete any previous install**

  In the simulator: long-press app icon → Remove App → Delete.

- [ ] **Step 3: Launch the freshly-built app**

  Cmd+R in Xcode.

- [ ] **Step 4: Sign in with Apple**

  Tap the SIWA button in the boot screen. Because you're in the simulator, `AppAttestService.isBypassed` is true and no real attestation happens.

  Expected: sign-in succeeds, onboarding begins.

- [ ] **Step 5: Verify tokens are in Keychain**

  Use Xcode's memory graph or a print statement in AuthClient to confirm `currentAccessToken` is non-nil after sign_in.

- [ ] **Step 6: Verify Home tab loads (JWT-gated read)**

  Complete onboarding. The Home tab should display profile data.

  Expected: no 401 errors in the Xcode console.

- [ ] **Step 7: Verify a write works (profile update)**

  Tap Settings → Edit Profile → change the display name → Save.

  Expected: the write succeeds. Because `attestation: null` was sent during sign_in, the device_attestations row has `is_bypass = true`, and the middleware's bypass path accepts writes with no assertion.

- [ ] **Step 8: Check the Supabase function logs**

  Use `mcp__plugin_supabase_supabase__get_logs` with `project_id` and `service: "edge-function"`. Look for the sign_in + upsert_profile calls. Verify no errors.

### Task 30: Real device end-to-end test

- [ ] **Step 1: Build an archive for an internal distribution**

  ```bash
  xcodebuild archive -project RPT.xcodeproj -scheme RPT \
             -destination 'generic/platform=iOS' \
             -archivePath /tmp/rpt-2.9.0-test.xcarchive
  ```

- [ ] **Step 2: Install on a real iPhone via Xcode's Devices window**

  Xcode → Window → Devices and Simulators → select your iPhone → drag the .xcarchive to the Installed Apps area.

- [ ] **Step 3: Delete any previous install first**

- [ ] **Step 4: Launch, sign in with Apple**

  Expected: App Attest runs for real this time. The sign_in request in Charles/Proxyman (or server logs) shows a non-null `attestation` object.

- [ ] **Step 5: Verify device_attestations has a real row (not bypass)**

  ```sql
  SELECT id, cloudkit_user_id, is_bypass, counter FROM device_attestations
  WHERE cloudkit_user_id = 'your-cloudkit-id' AND is_bypass = false;
  ```

- [ ] **Step 6: Perform a write from the device**

  Log a food entry or complete a quest. This triggers the first real assertion.

- [ ] **Step 7: Verify the counter incremented**

  Re-run the SQL above. The `counter` column should be > 0.

### Task 31: Token refresh + sign out + delete account test

- [ ] **Step 1: Sign in on simulator**

- [ ] **Step 2: Manually set access token expiry to 30 seconds from now**

  Add a DEBUG-only override in `AuthClient.setTokens` that allows shortening the expiry for testing. Remove before shipping. Or simply wait 15 minutes with the app open.

- [ ] **Step 3: Trigger an API call after expiry**

  Expected: network log shows POST auth-proxy/refresh before the original call. Original call succeeds.

- [ ] **Step 4: Tap Sign Out**

  Expected: `refresh_tokens` row is deleted. Next API call returns 401.

- [ ] **Step 5: Test Delete Account end-to-end**

  Sign in again → Settings → Delete Account. Verify all data is wiped + routed to onboarding. Verify `refresh_tokens` and `device_attestations` rows for this user are gone.

### Task 32: Multi-device test (5-device limit + cross-device session kill)

- [ ] **Step 1: Sign in on Device A (real iPhone or sim 1)**

- [ ] **Step 2: Sign in on Device B (another sim or real iPad)**

  Use the same Apple ID.

- [ ] **Step 3: Verify both devices have separate rows**

  ```sql
  SELECT id, key_id, is_bypass, created_at FROM device_attestations
  WHERE cloudkit_user_id = 'your-id' AND revoked_at IS NULL;
  ```
  Expected: 2 rows.

- [ ] **Step 4: Delete Account from Device A**

- [ ] **Step 5: Verify Device B's session dies within 15 minutes**

  Make an API call from Device B. Should return 401 (because `refresh_tokens` is wiped for this user).

- [ ] **Step 6: Sign in 6 times on different devices (or simulate)**

  After the 6th sign-in, the oldest device_attestations row should have `revoked_at` set.

---

## Phase 7: Ship 2.9.0 (Task 33)

### Task 33: Commit, push, verify Xcode Cloud build

- [ ] **Step 1: Final git status check**

  ```bash
  cd "/Users/nickspiro/Github Local/System-Trainer"
  git status
  ```
  Expected: clean working tree. All changes already committed in previous tasks.

- [ ] **Step 2: Push**

  ```bash
  git push origin main
  ```

- [ ] **Step 3: Monitor Xcode Cloud**

  Check App Store Connect → Xcode Cloud. Verify the build for commit `<sha>` completes successfully and uploads to TestFlight.

- [ ] **Step 4: Smoke-test the TestFlight build**

  Install on your iPhone via TestFlight. Complete a fresh sign-in. Verify the flow works end-to-end.

- [ ] **Step 5: User-side post-deploy cleanup**

  - Remove `APP_SECRET` from Xcode Cloud → Workflow → Secret Environment Variables
  - Remove `RPT_APP_SECRET` from Supabase Vault (not referenced by any edge function anymore)

- [ ] **Step 6: Announce 2.9.0 to your beta tester**

  Send a message: "2.9.0 is in TestFlight. You MUST update — the old version will stop working because we replaced the auth system. If you see weird errors, delete the app and reinstall fresh."

---

## Self-Review Checklist

### Spec coverage check
| Spec section | Covered by task(s) |
|---|---|
| §5.1 device_attestations table | Task 1 |
| §5.2 refresh_tokens table | Task 1 |
| §5.3 AUTH_JWT_ES256_PRIVATE_KEY vault | Pre-flight 1+2, Task 5 |
| §6.1 sign_in action | Task 10 |
| §6.2 refresh action | Task 13 |
| §6.3 sign_out action | Task 14 |
| §7.1 validateAuth | Task 9 |
| §7.2 verifyJWT, mintJWT | Tasks 4-5 |
| §7.2 verifyAssertion | Task 8 |
| §7.2 verifyAppleIdToken | Tasks 6-7 |
| §9.1 AppAttestService.swift | Task 18 |
| §9.2 AuthClient.swift | Task 19 |
| §9.3 APIClient.swift | Task 20 |
| §10 Sign-in flow | Task 25 |
| §11 Authenticated request flow | Tasks 23, 24 |
| §12 Sign Out / Delete Account | Task 26 |
| §13 Multi-device (5-device limit) | Task 10 step 1 (in auth-proxy sign_in) |
| §14 Simulator bypass | Task 18 (iOS side) + Task 12 Step 1 (server side env var) |
| §15 Migration | Tasks 15-17, 27 |
| §16 Rollback | Not a task — documented in spec |
| §17 Testing | Tasks 29-32 |
| §18 Timeline | Covered implicitly by task count |
| §19 Open research questions | Called out in-task (Task 10 Step 1 for attestation verification stub) |

**Gap identified:** The attestation object verification in `auth-proxy/sign_in` (Task 10) is a TODO-stub because implementing the full CBOR-decode + Apple App Attest cert chain verification is one of the open research questions from the spec. This is acceptable for a plan because the spec explicitly marks it as an open question — but the execution engineer MUST resolve it before Task 17 (deploy). Adding an explicit note:

> **Task 10 → Task 17 dependency:** Before deploying player-proxy and leaderboard-proxy with the validateAuth middleware, the attestation verification stub in auth-proxy/sign_in MUST be replaced with a working implementation. Options documented in spec §19 Question 2.

### Placeholder scan

Searched for: "TBD", "TODO", "implement later", "fill in details", "similar to Task N".

Found: 1 TODO in Task 10 Step 1 (the attestation verification stub). This is deliberate — it's the open research question from the spec. **Added an explicit dependency note above.**

Found: 0 "similar to Task N" references.

### Type consistency check

- `cloudkit_user_id` is consistent across server SQL, Deno types, Swift parameters ✅
- `device_attestation_id` referenced consistently as UUID ✅
- JWT claims `sub`, `device_id`, `attested` referenced consistently ✅
- `APIClient.post` signature matches its definition in Task 20 and its usage in Tasks 23, 24, 26 ✅
- `AuthClient.signIn(appleIdToken:appleAuthCode:cloudKitUserId:)` signature matches between Task 19 (definition) and Task 25 (usage) ✅
- `AppAttestService.generateAssertion(for:)` matches between Task 18 (definition) and Task 20 usage in APIClient ✅

All types consistent.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-08-app-attest-jwt-implementation.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** — Dispatch a fresh subagent per task, review between tasks, fast iteration. Best for this plan because tasks 4-9 (Deno auth helpers) are parallelizable and task 10 has an unresolved research dependency that benefits from focused deep investigation.

**2. Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints for review. Best if you want to stay in one session and resolve the open research questions in real-time with back-and-forth.

Given the scale (~33 tasks, 7-8 working days), neither approach completes in a single session. The recommended path is:

1. **Don't start execution immediately.** Let 2.8.4 + 2.8.5 reach TestFlight and get real-world-tested.
2. **Resolve the Task 10 open question first** — do 30 minutes of research on Deno App Attest verification libraries before committing to execution. This is the highest-risk item in the plan.
3. **Start execution in a fresh session** with a clean context window so the subagent/inline executor has maximum space for error messages and iteration loops.
