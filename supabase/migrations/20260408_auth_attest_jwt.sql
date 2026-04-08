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
  'App Attest assertion signature. RLS enabled with zero policies: service '
  'role only. See docs/superpowers/specs/2026-04-08-app-attest-jwt-design.md §5.1';

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
  'within the 15-minute access-token expiry window. Cascade-deletes via '
  'device_attestation_id FK when the underlying device is revoked. '
  'See docs/superpowers/specs/2026-04-08-app-attest-jwt-design.md §5.2';
