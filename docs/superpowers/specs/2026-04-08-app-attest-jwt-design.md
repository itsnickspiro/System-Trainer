# System Trainer 2.9.0 — App Attest + JWT Authentication Design

**Status:** Design / pre-implementation
**Effective date:** April 8, 2026
**Target release:** 2.9.0 (build 26)
**Supersedes:** `x-app-secret` shared-secret authentication (2.0.0–2.8.5)
**Author:** Nick Spiro + Claude Opus 4.6

---

## 1. Problem Statement

Through 2.8.5, every Supabase Edge Function call is authenticated by a single shared secret:

```
POST /functions/v1/player-proxy
Headers: x-app-secret: <baked into the iOS binary>
Body:    { cloudkit_user_id: "_abc123", action: "upsert_profile", ... }
```

This has two structural weaknesses:

1. **The shared secret is extractable.** Anyone with a jailbroken device + `class-dump`/`Hopper`/`strings` can pull the `APP_SECRET` constant out of the iOS binary in ~10 minutes. Once extracted, the secret is valid for every installation of the app.

2. **The server trusts `cloudkit_user_id` from the request body.** Combined with the extractable secret, this means anyone who dumps the secret can impersonate ANY user by sending a different `cloudkit_user_id` in the body. They can read profiles, inject credit transactions, delete accounts, and post fake leaderboard entries for users they've never met.

Because System Trainer stores personal health data (demographics, Apple ID, fitness goals, biometric inputs), these two weaknesses together represent a real GDPR Article 9 and App Store HealthKit Guideline risk. 2.9.0 closes them.

## 2. Goals

1. **Replace the shared secret** with per-device hardware-backed attestation (App Attest).
2. **Replace body-trust with JWT-bearer identity** so the server never takes `cloudkit_user_id` at face value.
3. **Support session revocation** (Sign Out / Delete Account must kill a session in ≤15 minutes).
4. **Simple to reason about** — no Supabase Auth / gotrue integration, no RLS migration, minimum moving parts.
5. **Maintain iOS simulator development** via a strict debug-only bypass.
6. **Hard cutover** — 2.9.0 removes x-app-secret entirely. No dual-path.

### Explicit non-goals

- Certificate pinning (anti-pattern for Supabase; Supabase's `*.supabase.co` certs rotate via AWS ACM with no stability guarantee).
- Jailbreak detection (trivially bypassed; Apple's Tech Note TN2206 recommends App Attest as the replacement).
- Full WAF (overkill for our scale; rate limiting from 2.8.5 covers 90% of what a WAF would catch).
- Email/password login (SIWA-only by design).
- OAuth2 authorization server (we're not a third-party IdP; we mint and validate our own JWTs).
- `auth_audit_log` table (deferred to 2.9.1 or later).
- Multi-factor authentication beyond SIWA (Apple handles account-level 2FA).

## 3. Decisions (baked in from brainstorming session 2026-04-08)

| Decision | Choice | Rationale |
|---|---|---|
| **Threat model** | Pragmatic | Defense against realistic attackers (leaderboard cheaters, script kiddies, people who extracted the secret from the binary). Not nation-state level. |
| **JWT infrastructure** | Roll our own | New `auth-proxy` Edge Function with ES256 signing. Keeps `cloudkit_user_id` as the primary key everywhere, avoids Supabase Auth schema migration, full control over claim structure. |
| **Token lifecycle** | Access (15m) + Refresh (30d) | Server-side `refresh_tokens` table enables revocation. Sign Out / Delete Account kills the session in ≤15 min. Standard OAuth 2.0 pattern. |
| **Refresh rotation** | One-time-use | Each refresh returns a new refresh token; the old one is revoked. Stops refresh-token theft from being persistent. |
| **App Attest cadence** | Writes only | Reads (`get_profile`, `get_global`, `get_friends`, etc.) use JWT alone. Writes (`upsert_profile`, `add_credits`, `delete_account`, `upsert_entry`, etc.) require a fresh assertion. Best latency for reads, strong protection where it matters. |
| **Migration** | Hard cutover | 2.9.0 ships with x-app-secret removed server-side. 2.8.5 clients get HTTP 401. Pre-App-Store, only 2 beta testers, so the blast radius is manageable. |
| **Multi-device** | 5 active devices per user | Matches Google/Apple/Microsoft. Sixth sign-in evicts the oldest. |
| **Simulator bypass** | Debug-only + production-gated | `#if DEBUG && targetEnvironment(simulator)` in iOS + `ALLOW_SIMULATOR_BYPASS=true` env var in dev Supabase. Production Supabase never has the env var set, so production builds cannot bypass. |

## 4. Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         iOS (2.9.0)                              │
│                                                                  │
│  ┌────────────────┐    ┌───────────────┐    ┌─────────────────┐ │
│  │ AppleAuth      │───▶│ AppAttest     │───▶│ AuthClient      │ │
│  │ Service        │    │ Service       │    │ (new)           │ │
│  │ (existing)     │    │ (new)         │    │                 │ │
│  │ SIWA flow      │    │ generateKey   │    │ Keychain-backed │ │
│  │ id_token       │    │ attestKey     │    │ JWT store       │ │
│  │ auth_code      │    │ genAssertion  │    │ Auto-refresh    │ │
│  └────────────────┘    └───────────────┘    └─────────────────┘ │
│           │                   │                      │          │
│           └───────────────────┴──────────────────────┘          │
│                               │                                 │
│  ┌────────────────────────────▼──────────────────────────────┐  │
│  │  APIClient (new wrapper around every proxy call)          │  │
│  │  • Injects Bearer JWT in Authorization header             │  │
│  │  • Adds App Attest assertion on writes                    │  │
│  │  • Auto-refreshes JWT on 401                              │  │
│  └────────────────────────────┬──────────────────────────────┘  │
└───────────────────────────────┼──────────────────────────────────┘
                                │ HTTPS
┌───────────────────────────────▼──────────────────────────────────┐
│                    Supabase Edge Functions                       │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ auth-proxy   │  │ player-proxy │  │ leaderboard-proxy    │  │
│  │ (NEW)        │  │ (modified)   │  │ (modified)           │  │
│  │              │  │              │  │                      │  │
│  │ sign_in      │  │ validateJWT  │  │ validateJWT          │  │
│  │ refresh      │  │ + attestation│  │ + attestation        │  │
│  │ sign_out     │  │ (writes)     │  │ (writes)             │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                     │               │
│         └─────────────────┴─────────────────────┘               │
│                           │                                     │
│                           ▼                                     │
│         ┌──────────────────────────────────┐                    │
│         │  _shared/auth.ts                 │                    │
│         │  • validateAuth(req, opts)       │                    │
│         │  • verifyJWT(token)              │                    │
│         │  • verifyAssertion(assert, body) │                    │
│         │  • verifyAppleIdToken(token)     │                    │
│         │  • mintJWT(cloudkit_user_id)     │                    │
│         └──────────────────────────────────┘                    │
│                           │                                     │
│                           ▼                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    PostgreSQL                              │ │
│  │                                                            │ │
│  │  refresh_tokens (NEW)          device_attestations (NEW)   │ │
│  │  ─────────────────             ───────────────────────     │ │
│  │  id                            id                          │ │
│  │  cloudkit_user_id              cloudkit_user_id            │ │
│  │  token_hash                    key_id (App Attest)         │ │
│  │  device_attestation_id ───────▶attestation_public_key      │ │
│  │  created_at                    receipt                     │ │
│  │  expires_at                    counter (replay protection) │ │
│  │  revoked_at                    created_at                  │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

## 5. Database Schema Changes

Three changes, none touching existing user data:

### 5.1 New table: `device_attestations`

Stores the App Attest public key and replay counter for each (user, device) pair.

```sql
CREATE TABLE public.device_attestations (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cloudkit_user_id        text NOT NULL,
  key_id                  text NOT NULL,          -- App Attest key identifier (base64)
  attestation_public_key  bytea NOT NULL,         -- EC P-256 public key, uncompressed form
  receipt                 bytea NOT NULL,         -- Apple's attestation receipt for re-verification
  counter                 bigint NOT NULL DEFAULT 0,  -- monotonic counter for replay protection
  is_bypass               boolean NOT NULL DEFAULT false,  -- true for simulator bypass rows
  created_at              timestamptz NOT NULL DEFAULT now(),
  last_used_at            timestamptz NOT NULL DEFAULT now(),
  revoked_at              timestamptz,
  UNIQUE (cloudkit_user_id, key_id)
);

CREATE INDEX device_attestations_cloudkit_user_id_active_idx
  ON public.device_attestations (cloudkit_user_id, last_used_at DESC)
  WHERE revoked_at IS NULL;

ALTER TABLE public.device_attestations ENABLE ROW LEVEL SECURITY;
-- No policies: service role only
```

### 5.2 New table: `refresh_tokens`

Stores SHA-256 hashes of refresh tokens. Raw tokens are never persisted; a DB breach cannot be used to impersonate active sessions.

```sql
CREATE TABLE public.refresh_tokens (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cloudkit_user_id        text NOT NULL,
  token_hash              text NOT NULL UNIQUE,   -- SHA-256 hex of the refresh token
  device_attestation_id   uuid REFERENCES public.device_attestations(id) ON DELETE CASCADE,
  created_at              timestamptz NOT NULL DEFAULT now(),
  expires_at              timestamptz NOT NULL,
  revoked_at              timestamptz,
  last_used_at            timestamptz
);

CREATE INDEX refresh_tokens_cloudkit_user_id_active_idx
  ON public.refresh_tokens (cloudkit_user_id)
  WHERE revoked_at IS NULL;

CREATE INDEX refresh_tokens_expires_at_idx
  ON public.refresh_tokens (expires_at)
  WHERE revoked_at IS NULL;

ALTER TABLE public.refresh_tokens ENABLE ROW LEVEL SECURITY;
-- No policies: service role only
```

### 5.3 New Vault secret: `AUTH_JWT_ES256_PRIVATE_KEY`

A fresh EC P-256 private key used exclusively for minting and verifying our JWTs. Generated as part of the execution phase via `openssl ecparam -name prime256v1 -genkey -noout` then pasted into Supabase Vault. Corresponding public key is inlined in `_shared/auth.ts` for verification.

## 6. New Edge Function: `auth-proxy`

A new dedicated function handling 3 actions. Lives at `supabase/functions/auth-proxy/index.ts`.

### 6.1 Action: `sign_in`

Called once on first SIWA sign-in (and on subsequent fresh sign-ins after Sign Out).

**Request:**
```json
{
  "action": "sign_in",
  "apple_id_token": "eyJ...",
  "apple_authorization_code": "c.0.xyz",
  "cloudkit_user_id": "_abc123",
  "attestation": {
    "key_id": "base64-key-id",
    "attestation_object": "base64-attestation",
    "client_data_hash": "sha256-hex"
  },
  "device_model": "iPhone17,1",
  "app_version": "2.9.0"
}
```

**Server logic:**
1. Rate-limit check: `sign_in` budget = 5/hour per `cloudkit_user_id`
2. Verify `apple_id_token` signature against Apple's JWKS (cached 24h via `_shared/apple-jwks.ts`)
3. Extract `sub` claim from the id_token and confirm it matches the caller's claimed Apple user ID
4. If `attestation` is null: check env var `ALLOW_SIMULATOR_BYPASS` is set to `true`. If not set, reject with HTTP 400. If set, flag the row with `is_bypass = true`.
5. If `attestation` is present: verify the attestation object against Apple's App Attest root CA using the bundled root cert in `_shared/apple-app-attest-root.pem`. Extract the public key, counter starting value (0), receipt.
6. Insert into `device_attestations` — rejects on `UNIQUE (cloudkit_user_id, key_id)` conflict, which indicates re-attestation with the same key (should not happen normally).
7. Check active device count for this `cloudkit_user_id`. If ≥ 5, revoke the oldest by `last_used_at`.
8. Generate a random 32-byte refresh token via `crypto.getRandomValues()`. Store its SHA-256 hash in `refresh_tokens`.
9. Store the `apple_authorization_code` on `player_profiles.apple_authorization_code` (existing 2.8.5 behavior).
10. Mint the access JWT (see §8).
11. Return `{ access_token, refresh_token, expires_in: 900 }` where `refresh_token` is the raw (not hashed) value.

### 6.2 Action: `refresh`

Called by iOS `AuthClient.refresh()` when the access token is within 60 seconds of expiry (or after a 401).

**Request:**
```json
{
  "action": "refresh",
  "refresh_token": "raw-32-byte-token-hex"
}
```

**Server logic:**
1. Rate-limit check: `refresh` budget = 20/hour per refresh_token hash
2. Hash the raw refresh token with SHA-256. Look up in `refresh_tokens`.
3. If not found: HTTP 401
4. If `revoked_at IS NOT NULL`: HTTP 401 (also revoke all active tokens for this user as a defensive response to possible theft)
5. If `expires_at < now()`: HTTP 401
6. **Rotation:** mark the current refresh_token row as revoked
7. Generate a new 32-byte refresh token, SHA-256 hash, insert new row with same `cloudkit_user_id` and `device_attestation_id`
8. Mint a new access JWT
9. Return `{ access_token, refresh_token: <new>, expires_in: 900 }`

### 6.3 Action: `sign_out`

Called by iOS `AuthClient.signOut()`.

**Request (authenticated with Bearer JWT):**
```json
{
  "action": "sign_out"
}
```

**Server logic:**
1. `validateAuth()` to get the caller's `cloudkit_user_id` from the JWT
2. `DELETE FROM refresh_tokens WHERE cloudkit_user_id = $1`
3. Return `{ success: true, sessions_revoked: <count> }`

Within ≤15 minutes (access token expiry), every device the user was signed in on loses access. This is the hard guarantee for "Sign Out kills all sessions."

## 7. Shared Middleware: `_shared/auth.ts`

Located at `supabase/functions/_shared/auth.ts`. Imported by `auth-proxy`, `player-proxy`, and `leaderboard-proxy` via relative path.

### 7.1 `validateAuth(req, supabase, opts)`

Main entry point for every authenticated edge function. ~100 lines.

```typescript
export interface AuthResult {
  valid: boolean;
  cloudkit_user_id?: string;
  device_attestation_id?: string;
  error?: string;
}

export async function validateAuth(
  req: Request,
  supabase: SupabaseClient,
  opts: { requireAttestation: boolean }
): Promise<AuthResult> {
  // 1. Extract Bearer JWT from Authorization header
  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return { valid: false, error: "missing_bearer_token" };
  }
  const token = authHeader.slice(7);

  // 2. Verify JWT signature + standard claims (exp, iat, aud)
  const claims = await verifyJWT(token);
  if (!claims) {
    return { valid: false, error: "invalid_jwt" };
  }

  // 3. If write operation: verify App Attest assertion
  if (opts.requireAttestation) {
    const assertion = req.headers.get("x-app-attest-assertion") ?? "";
    const keyId = req.headers.get("x-app-attest-key-id") ?? "";
    if (!assertion || !keyId) {
      return { valid: false, error: "missing_attestation" };
    }

    // Load the device's attestation public key + counter
    const { data: attestation } = await supabase
      .from("device_attestations")
      .select("id, attestation_public_key, counter, is_bypass")
      .eq("cloudkit_user_id", claims.sub)
      .eq("key_id", keyId)
      .is("revoked_at", null)
      .maybeSingle();
    if (!attestation) {
      return { valid: false, error: "unknown_device" };
    }

    // Bypass path (simulator only, production never sets env var)
    if (attestation.is_bypass) {
      const allowBypass = Deno.env.get("ALLOW_SIMULATOR_BYPASS") === "true";
      if (!allowBypass) {
        return { valid: false, error: "bypass_not_allowed_in_production" };
      }
      // Simulator bypass path: skip real verification
      return {
        valid: true,
        cloudkit_user_id: claims.sub,
        device_attestation_id: attestation.id,
      };
    }

    // Real assertion verification
    const body = await req.clone().text();
    const bodyHash = await sha256(body);
    const assertionValid = await verifyAssertion(
      assertion,
      attestation.attestation_public_key,
      bodyHash,
      attestation.counter,
    );
    if (!assertionValid.valid) {
      return { valid: false, error: "assertion_verification_failed" };
    }

    // Increment counter atomically (replay protection)
    await supabase
      .from("device_attestations")
      .update({
        counter: assertionValid.newCounter,
        last_used_at: new Date().toISOString(),
      })
      .eq("id", attestation.id);

    return {
      valid: true,
      cloudkit_user_id: claims.sub,
      device_attestation_id: attestation.id,
    };
  }

  // Read-only path: JWT is sufficient
  return { valid: true, cloudkit_user_id: claims.sub };
}
```

### 7.2 Helpers

- `verifyJWT(token): Promise<JWTClaims | null>` — Verifies ES256 signature against cached public key (imported once per function instance); checks `exp`, `iat`, `aud`, `iss`.
- `mintJWT(cloudkitUserId, attested, expiresIn): Promise<string>` — Signs claims with the Vault-stored private key.
- `verifyAppleIdToken(token): Promise<AppleIdClaims | null>` — Fetches Apple's JWKS (cached 24h), verifies the id_token signature, returns the `sub` claim.
- `verifyAssertion(assertion, publicKey, bodyHash, expectedCounter): Promise<{valid, newCounter}>` — Parses the App Attest assertion, validates the signature against the stored public key, checks that the counter is strictly greater than `expectedCounter`, returns the new counter value.
- `sha256(input): Promise<string>` — Hex-encoded SHA-256 via WebCrypto.

## 8. JWT Claims Schema

```json
{
  "iss": "rpt.supabase",
  "aud": "rpt",
  "sub": "<cloudkit_user_id>",
  "iat": 1775620000,
  "exp": 1775620900,
  "attested": true,
  "device_id": "<device_attestations.id>"
}
```

- `iss`: static identifier, enables future multi-project support
- `aud`: static, enables future multi-client support
- `sub`: the authenticated user — this is the source of truth that edge functions trust instead of body-supplied `cloudkit_user_id`
- `iat` / `exp`: 15-minute lifetime
- `attested`: false only for simulator bypass rows; true in production
- `device_id`: the device_attestations row this session is bound to; used so we can quickly revoke a single device without a full sign-out

## 9. iOS Architecture

Three new files in `RPT/` + modifications to existing API callers.

### 9.1 `AppAttestService.swift`

```swift
import Foundation
import DeviceCheck
import CryptoKit

enum AppAttestError: LocalizedError {
    case unsupported
    case notAttested
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: return "App Attest is not supported on this device."
        case .notAttested: return "Device has not been attested yet."
        case .generationFailed(let s): return "App Attest generation failed: \(s)"
        }
    }
}

@MainActor
final class AppAttestService: ObservableObject {
    static let shared = AppAttestService()

    @Published private(set) var keyId: String?
    let isSupported: Bool

    var isBypassed: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private init() {
        self.isSupported = DCAppAttestService.shared.isSupported
        self.keyId = KeychainHelper.load(account: "rpt_attest_key_id")
    }

    /// Called once at first sign-in. Generates a fresh Secure Enclave key,
    /// requests an attestation object from Apple, returns both for sign-in.
    func attestDevice(challenge: Data) async throws -> (keyId: String, attestationObject: Data)? {
        if isBypassed {
            return nil  // caller sends attestation: null
        }
        guard isSupported else { throw AppAttestError.unsupported }

        let service = DCAppAttestService.shared
        let newKeyId = try await service.generateKey()
        let clientDataHash = Data(SHA256.hash(data: challenge))
        let attestation = try await service.attestKey(newKeyId, clientDataHash: clientDataHash)

        KeychainHelper.save(value: newKeyId, account: "rpt_attest_key_id")
        self.keyId = newKeyId
        return (newKeyId, attestation)
    }

    /// Called before every write request. Signs the request body with the
    /// Secure Enclave key. Fast (~5-10ms).
    func generateAssertion(for requestBody: Data) async throws -> Data {
        if isBypassed { return Data() }
        guard let keyId = self.keyId else { throw AppAttestError.notAttested }
        let clientDataHash = Data(SHA256.hash(data: requestBody))
        return try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}
```

### 9.2 `AuthClient.swift`

```swift
import Foundation
import SwiftUI

enum AuthError: LocalizedError {
    case notSignedIn
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in."
        case .refreshFailed(let s): return "Token refresh failed: \(s)"
        }
    }
}

@MainActor
final class AuthClient: ObservableObject {
    static let shared = AuthClient()

    @Published private(set) var isSignedIn: Bool = false
    private var currentAccessToken: String?
    private var currentRefreshToken: String?
    private var accessTokenExpiry: Date?

    private static let accessKey = "rpt_access_token"
    private static let refreshKey = "rpt_refresh_token"
    private static let expiryKey = "rpt_access_token_expiry"

    private init() {
        self.currentAccessToken = KeychainHelper.load(account: Self.accessKey)
        self.currentRefreshToken = KeychainHelper.load(account: Self.refreshKey)
        if let secs = UserDefaults.standard.object(forKey: Self.expiryKey) as? TimeInterval {
            self.accessTokenExpiry = Date(timeIntervalSince1970: secs)
        }
        self.isSignedIn = currentAccessToken != nil && currentRefreshToken != nil
    }

    /// Full sign-in flow: SIWA → AppAttest → auth-proxy/sign_in → store tokens.
    /// Called by OnboardingView / SettingsView after ASAuthorizationController succeeds.
    func signIn(
        appleIdToken: String,
        appleAuthCode: String,
        cloudKitUserId: String
    ) async throws {
        let challenge = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let attestation = try await AppAttestService.shared.attestDevice(challenge: challenge)

        var body: [String: Any] = [
            "action": "sign_in",
            "apple_id_token": appleIdToken,
            "apple_authorization_code": appleAuthCode,
            "cloudkit_user_id": cloudKitUserId,
            "device_model": deviceModel,
            "app_version": appVersion
        ]
        if let attestation {
            body["attestation"] = [
                "key_id": attestation.keyId,
                "attestation_object": attestation.attestationObject.base64EncodedString(),
                "client_data_hash": Data(SHA256.hash(data: challenge)).base64EncodedString()
            ]
        }

        // POST to auth-proxy — NOT via APIClient (which would require a
        // valid token we don't have yet). Raw URLSession.
        let request = URLRequest.postJSON(
            url: URL(string: "\(Secrets.supabaseURL)/functions/v1/auth-proxy")!,
            body: body
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.refreshFailed("sign_in HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        setTokens(access: tokens.accessToken, refresh: tokens.refreshToken, expiresIn: tokens.expiresIn)
    }

    func setTokens(access: String, refresh: String, expiresIn: Int) {
        KeychainHelper.save(value: access, account: Self.accessKey)
        KeychainHelper.save(value: refresh, account: Self.refreshKey)
        self.currentAccessToken = access
        self.currentRefreshToken = refresh
        let expiry = Date().addingTimeInterval(TimeInterval(expiresIn - 30))  // 30s buffer
        self.accessTokenExpiry = expiry
        UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: Self.expiryKey)
        self.isSignedIn = true
    }

    func validAccessToken() async throws -> String {
        guard let token = currentAccessToken, let expiry = accessTokenExpiry else {
            throw AuthError.notSignedIn
        }
        if expiry.timeIntervalSinceNow < 60 {
            try await refresh()
        }
        guard let fresh = currentAccessToken else { throw AuthError.notSignedIn }
        return fresh
    }

    func refresh() async throws {
        guard let refreshToken = currentRefreshToken else { throw AuthError.notSignedIn }
        let body: [String: Any] = ["action": "refresh", "refresh_token": refreshToken]
        let request = URLRequest.postJSON(
            url: URL(string: "\(Secrets.supabaseURL)/functions/v1/auth-proxy")!,
            body: body
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Refresh failed — force full re-auth
            await signOut()
            throw AuthError.refreshFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        setTokens(access: tokens.accessToken, refresh: tokens.refreshToken, expiresIn: tokens.expiresIn)
    }

    func signOut() async {
        if let token = currentAccessToken {
            let body: [String: Any] = ["action": "sign_out"]
            var request = URLRequest.postJSON(
                url: URL(string: "\(Secrets.supabaseURL)/functions/v1/auth-proxy")!,
                body: body
            )
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainHelper.delete(account: Self.accessKey)
        KeychainHelper.delete(account: Self.refreshKey)
        UserDefaults.standard.removeObject(forKey: Self.expiryKey)
        self.currentAccessToken = nil
        self.currentRefreshToken = nil
        self.accessTokenExpiry = nil
        self.isSignedIn = false
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private var deviceModel: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "unknown" }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
```

### 9.3 `APIClient.swift`

```swift
import Foundation

enum APIError: LocalizedError {
    case httpError(Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP \(code)"
        case .decodingFailed(let s): return "Decoding failed: \(s)"
        }
    }
}

/// Set of action names that require an App Attest assertion (write
/// operations). Must match isWriteAction() in _shared/auth.ts.
private let writeActions: Set<String> = [
    "upsert_profile", "save_backup", "add_credits",
    "link_apple_id", "delete_account", "revoke_siwa",
    "store_auth_code", "upsert_entry", "add_friend", "remove_friend"
]

enum APIClient {
    static func post(
        endpoint: String,
        action: String,
        body: [String: Any]
    ) async throws -> Data {
        let isWrite = writeActions.contains(action)
        let accessToken = try await AuthClient.shared.validAccessToken()

        var merged = body
        merged["action"] = action
        let bodyData = try JSONSerialization.data(withJSONObject: merged)

        var request = URLRequest(url: URL(string: "\(Secrets.supabaseURL)/functions/v1/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 15

        if isWrite {
            let assertion = try await AppAttestService.shared.generateAssertion(for: bodyData)
            request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Attest-Assertion")
            if let keyId = AppAttestService.shared.keyId {
                request.setValue(keyId, forHTTPHeaderField: "X-App-Attest-Key-Id")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            // Access token expired at the boundary — refresh and retry once
            try await AuthClient.shared.refresh()
            return try await post(endpoint: endpoint, action: action, body: body)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}
```

### 9.4 Modified files (iOS)

- **`AppleAuthService.swift`**: After `persistFromButtonResult`, call `AuthClient.shared.signIn(appleIdToken:, appleAuthCode:, cloudKitUserId:)`. This replaces the current direct call to `PlayerProfileService.shared.linkAppleID`.
- **`PlayerProfileService.swift`**: Delete `postToProxy`. Replace every call site with `APIClient.post(endpoint: "player-proxy", action: ..., body: ...)`.
- **`LeaderboardService.swift`**: Same change.
- **`Secrets.swift`**: Remove `appSecret` entirely. Remove `APP_SECRET` from `Secrets.xcconfig`. Remove `APP_SECRET` from `ci_post_clone.sh`. Remove from Xcode Cloud Secret Environment Variables (user-side manual step).
- **`RPT.entitlements`**: Add `com.apple.developer.devicecheck.appattest-environment` → `production` (or `development` for dev builds via a separate entitlement scheme).

## 10. Sign-in Flow (end to end)

```
1. User taps "Sign in with Apple" in BootStepView or SettingsView
2. iOS: ASAuthorizationController presents Apple's sheet
3. User approves
4. iOS: receives ASAuthorizationAppleIDCredential
   - identityToken (JWT)
   - authorizationCode
5. iOS: AppleAuthService.persistFromButtonResult(result)
6. iOS: AuthClient.shared.signIn(appleIdToken, authCode, cloudKitUserId)
   a. AppAttestService.attestDevice(challenge: random 32 bytes)
      - DCAppAttestService.generateKey() → keyId
      - DCAppAttestService.attestKey(keyId, clientDataHash) → attestationObject
   b. POST auth-proxy/sign_in with { apple_id_token, apple_authorization_code,
      cloudkit_user_id, attestation: { key_id, attestation_object, client_data_hash },
      device_model, app_version }
   c. Server verifies everything, inserts device_attestations row + refresh_tokens row,
      mints access JWT
   d. Returns { access_token, refresh_token, expires_in: 900 }
   e. AuthClient stores both tokens in Keychain
7. iOS: normal onboarding continues. Every subsequent API call uses
   APIClient.post which auto-adds Bearer JWT.
```

## 11. Authenticated Request Flow

```
Read (e.g. get_profile):
  iOS: APIClient.post(endpoint: "player-proxy", action: "get_profile", body: {})
  → AuthClient.validAccessToken()    # refresh if needed
  → POST player-proxy with Authorization: Bearer <JWT>
  → Server: validateAuth(requireAttestation: false)
  → verify JWT, extract sub claim as cloudkit_user_id
  → run get_profile handler
  → return response

Write (e.g. upsert_profile):
  iOS: APIClient.post(endpoint: "player-proxy", action: "upsert_profile", body: {...})
  → AuthClient.validAccessToken()
  → AppAttestService.generateAssertion(bodyData)    # ~5ms Secure Enclave op
  → POST player-proxy with:
       Authorization: Bearer <JWT>
       X-App-Attest-Assertion: <base64>
       X-App-Attest-Key-Id: <key_id>
  → Server: validateAuth(requireAttestation: true)
  → verify JWT
  → lookup device_attestations by key_id + cloudkit_user_id
  → verifyAssertion(assertion, stored_public_key, sha256(body), stored_counter)
  → update device_attestations.counter + last_used_at atomically
  → run upsert_profile handler with cloudkit_user_id from JWT
  → return response
```

## 12. Sign Out / Delete Account Flow

```
Sign Out (SettingsView):
  → AuthClient.signOut()
    a. POST auth-proxy/sign_out with Bearer JWT (server wipes refresh_tokens)
    b. Delete tokens from Keychain
    c. AppleAuthService.signOut()  # existing 2.8.4/2.8.5 behavior
  → isSignedIn = false, routes back to sign-in screen
  → Within ≤15 minutes, any cached access token anywhere is dead
    (can't refresh because refresh_tokens is gone)

Delete Account (SettingsView):
  → performDeleteAccount() (modified to use APIClient)
    a. APIClient.post(player-proxy, "delete_account", {})
       Server: runs 2.8.5 SIWA revoke → cascade wipe → DELETE refresh_tokens
              → DELETE device_attestations
    b. DataManager.deleteEverything()
    c. AuthClient.signOut()  # clears local tokens
    d. AppleAuthService.signOut()  # clears SIWA state
    e. hasCompletedOnboarding = false (routes to onboarding)
  → Same 15-minute max to full session death + Apple's server-side revocation
```

## 13. Multi-Device Handling

- One `cloudkit_user_id` can have up to 5 active `device_attestations` rows.
- Each active device has its own `refresh_tokens` row, bound via `device_attestation_id`.
- On sign-in, `auth-proxy/sign_in` checks the active device count. If already at 5, the row with the oldest `last_used_at` gets `revoked_at = now()`, and its `refresh_tokens` rows are cascaded-deleted via the FK (`ON DELETE CASCADE`).
- "Signed out of 1 device" is a silent outcome for the oldest-device's user; they see 401 on their next API call and are forced to re-sign-in.
- This matches the Google/Apple/Microsoft pattern of 5-device limits.

## 14. Simulator / Development Bypass

**iOS side:**
- `AppAttestService.isBypassed` is true only when `#if DEBUG && targetEnvironment(simulator)`
- When bypassed, `attestDevice()` returns nil (no attestation object) and `generateAssertion()` returns empty `Data()`
- iOS sends `attestation: null` in sign_in, and empty assertion headers in subsequent writes

**Server side:**
- `auth-proxy/sign_in` accepts `attestation: null` ONLY when `Deno.env.get("ALLOW_SIMULATOR_BYPASS") === "true"`
- Production Supabase **never** has this env var set. Setting it requires manual dashboard action.
- Rows inserted via the bypass path have `is_bypass = true`
- `_shared/auth.ts` double-checks: even if a bypass row exists, the write path verifies `ALLOW_SIMULATOR_BYPASS` is set at validation time. A production deploy cannot accept bypassed writes even if a stale bypass row is in the database.

**Production guarantee:** A compromised dev Supabase cannot be used to authenticate against production. The bypass is a dev-environment-only escape hatch.

## 15. Migration Plan (Hard Cutover)

### Pre-flight (before any 2.9.0 commit)
1. Apply migration: create `device_attestations`, `refresh_tokens`, insert JWT keys into Vault
2. Deploy `auth-proxy` v1 to production (exists but no clients call it yet)
3. Manually test `auth-proxy/sign_in` with a crafted request. Verify the JWT mints correctly. Inspect claims via `https://jwt.io`.
4. `player-proxy` and `leaderboard-proxy` are unchanged at this point — old 2.8.5 clients still work

### Cutover (single atomic commit)
5. Create one PR that does ALL of the following:
   - Adds `_shared/auth.ts` with `validateAuth`, `verifyJWT`, `verifyAssertion`, etc.
   - Removes `x-app-secret` header check from `player-proxy/index.ts`
   - Adds `validateAuth()` call at the top of `player-proxy` with `requireAttestation: isWriteAction(action)`
   - Replaces `cloudkit_user_id = body.cloudkit_user_id` with `cloudkit_user_id = authResult.cloudkit_user_id`
   - Same treatment for `leaderboard-proxy`
   - Adds iOS `AppAttestService.swift`, `AuthClient.swift`, `APIClient.swift`
   - Modifies `AppleAuthService.swift` to call `AuthClient.signIn()` after SIWA succeeds
   - Replaces every `postToProxy` in `PlayerProfileService.swift` and `LeaderboardService.swift` with `APIClient.post`
   - Deletes `Secrets.appSecret` from `Secrets.swift`
   - Removes `APP_SECRET` from `Secrets.xcconfig`
   - Removes `APP_SECRET` from `ci_post_clone.sh`
   - Adds `com.apple.developer.devicecheck.appattest-environment` = `production` to `RPT.entitlements`
   - Bumps version to 2.9.0, build 26
6. Deploy edge functions from the commit
7. Push the git commit → Xcode Cloud picks it up and builds
8. 2.8.5 clients start getting HTTP 401 from every endpoint within seconds
9. Both beta testers update to 2.9.0 via TestFlight

### Post-cutover
10. Manually verify both sign-in and authenticated requests work on at least one real iPhone (not simulator)
11. Monitor `auth-proxy` function logs for the first ~24 hours
12. **User-side manual steps:**
    - Remove `APP_SECRET` from Xcode Cloud Secret Environment Variables (the old build path no longer needs it)
    - Remove `RPT_APP_SECRET` from Supabase Vault (no longer referenced)

## 16. Rollback Plan

Rollback for hard cutover is non-trivial because the iOS client also changes. The only reliable rollback is:

1. `git revert <2.9.0 commit>` — restores 2.8.5 iOS code with x-app-secret path
2. Re-deploy `player-proxy` and `leaderboard-proxy` from the reverted files
3. Push to `main` to trigger Xcode Cloud rebuild
4. Beta testers update from TestFlight to get the reverted build

Wall time: ~20 minutes for code revert + build, plus TestFlight processing + user update time (can take hours).

**Mitigation:** Pre-ship testing should cover all flows on simulator + at least one real device before the commit ever lands. Do not merge until every test scenario in §17 passes.

## 17. Testing Strategy

### 17.1 Unit tests (new Deno tests in `_shared/auth.test.ts`)
- `verifyJWT` accepts a valid token
- `verifyJWT` rejects an expired token
- `verifyJWT` rejects a token signed with the wrong key
- `verifyJWT` rejects a token with tampered claims
- `verifyAssertion` accepts a valid assertion + matching body hash
- `verifyAssertion` rejects an assertion with a stale counter
- `verifyAssertion` rejects an assertion signed for a different body
- `verifyAppleIdToken` accepts a captured Apple JWT fixture
- `mintJWT` produces a token that `verifyJWT` accepts

### 17.2 End-to-end sim test
- Fresh simulator, delete + reinstall
- Launch app → sign in with Apple → verify network panel shows `POST auth-proxy/sign_in` with `attestation: null`
- Verify `refresh_tokens` has 1 row for this user
- Verify Home tab loads (implies JWT validation works on player-proxy)
- Perform a profile update (implies bypass path works on a write)

### 17.3 End-to-end real-device test
- Install 2.9.0 TestFlight build on a real iPhone
- Delete any previous install first (wipes Keychain)
- Sign in with Apple
- Verify sign_in request contains a non-null attestation
- Complete onboarding
- Perform a write (add food entry, complete quest)
- Check Supabase function logs for successful assertion verification

### 17.4 Token lifecycle test
- Sign in → wait 15 minutes with app open (don't make any API calls)
- Tap anything that triggers an API call
- Verify network panel shows `POST auth-proxy/refresh` before the original call
- Verify the original call returns 200

### 17.5 Sign Out test
- Sign in on Device A
- Check `refresh_tokens` has 1 row
- Tap Sign Out
- Check `refresh_tokens` has 0 rows
- Verify subsequent API calls from Device A return 401

### 17.6 Delete Account test
- Sign in → perform data-generating actions → tap Delete Account
- Confirm SIWA revoke runs (if Apple keys configured in Vault), cascade wipe runs, `refresh_tokens` + `device_attestations` wiped, local state wiped, routed to onboarding
- Sign in again with same Apple ID: should work, should NOT recover the deleted data

### 17.7 Multi-device test
- Sign in on Device A → sign in on Device B (same Apple ID)
- Verify both have separate `device_attestations` and `refresh_tokens` rows
- Delete Account from Device A
- Verify Device B's session dies within ≤15 minutes

## 18. Timeline Estimate

| Phase | Work | Est |
|---|---|---|
| Schema + auth-proxy | Migration, sign_in/refresh/sign_out, _shared/auth.ts, unit tests | 2d |
| Modify player-proxy + leaderboard-proxy | Remove x-app-secret, integrate middleware, update every action, deploy | 1d |
| iOS AppAttestService | Build + test against real device | 0.5d |
| iOS AuthClient | Keychain + refresh logic + auto-retry | 1d |
| iOS APIClient + migrate all callers | Wrapper + update every postToProxy call site | 1d |
| End-to-end testing | Sim + real device, all 7 test scenarios | 1d |
| Spec review + iteration | Bugs found during testing, design refinement | 0.5-1d |
| Ship 2.9.0 | Bump version, commit, push, TestFlight | 0.5d |
| **Total** | | **7-8 working days** |

## 19. Open Research Questions

These are deliberately unresolved and require research during the execution phase:

1. **Deno ES256 JWT library vs manual `crypto.subtle`.** For 2.8.5 I used raw `crypto.subtle` for Apple client_secret signing. For the more complex 2.9.0 JWT workflow (mint + verify + refresh), I should evaluate whether `djwt` from `https://deno.land/x/djwt` is worth the dependency. Decision needed before auth-proxy implementation.

2. **App Attest server-side verification library.** Apple's App Attest uses a specific WebAuthn-adjacent format (CBOR-encoded attestation object with an X.509 cert chain). I need to either write the full verification logic from scratch or find a Deno-compatible library. The Node ecosystem has `@peculiar/asn1-*`, but Deno compatibility needs verification.

3. **Apple App Attest root certificate.** The root CA is published at `https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem`. We'll bundle it in `_shared/apple-app-attest-root.pem` (checked into the repo, not fetched at runtime) to avoid a startup dependency on Apple's server.

4. **JWT verification performance.** Every request verifies the JWT signature. Does `crypto.subtle.importKey` need to run per-request? Deno function instances persist module-level state across requests, so cache the imported key at module scope — but measure startup time to be sure.

5. **Xcode project file changes.** Adding three new `.swift` files requires modifying `project.pbxproj`, which is notoriously fragile. Will use manual edits with a git safety net rather than the `xcodeproj` ruby gem.

6. **HealthKit + App Attest entitlement interaction.** Adding `com.apple.developer.devicecheck.appattest-environment` to `RPT.entitlements` may require updating the App ID in Apple Developer Portal to enable the App Attest capability. Need to verify this doesn't invalidate the current provisioning profile.

## 20. Explicit Non-Scope (Not in 2.9.0)

- Certificate pinning
- Jailbreak detection
- Full WAF protection
- Multi-factor authentication beyond SIWA
- Email/password login
- OAuth2 authorization server functionality
- Audit log table (`auth_audit_log`)
- iPad layout changes
- Apple Watch companion

## 21. References

- [Apple DeviceCheck / App Attest documentation](https://developer.apple.com/documentation/devicecheck)
- [Apple App Attest validation](https://developer.apple.com/documentation/devicecheck/validating_apps_that_connect_to_your_server)
- [Sign in with Apple REST API](https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api)
- [App Store Review Guideline 5.1.1(v) — Account Deletion](https://developer.apple.com/app-store/review/guidelines/#5.1.1)
- [OAuth 2.0 Refresh Token Rotation RFC 6819 §5.2.2.3](https://datatracker.ietf.org/doc/html/rfc6819#section-5.2.2.3)
- System Trainer 2.8.5 hardening release notes (commit `56fda17`)
