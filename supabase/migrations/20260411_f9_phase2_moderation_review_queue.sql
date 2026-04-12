-- F9 Phase 2: Moderation review queue
-- player_reports: user-filed reports against other players
-- moderation_flags: system-generated suspicious activity flags

-- ── player_reports ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS player_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_cloudkit_user_id text NOT NULL,
  reported_cloudkit_user_id text NOT NULL,
  reported_player_id text,
  reason text NOT NULL CHECK (reason IN (
    'cheating', 'harassment', 'impersonation',
    'inappropriate_name', 'inappropriate_avatar', 'other'
  )),
  description text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'reviewing', 'actioned', 'dismissed', 'duplicate'
  )),
  reviewed_by text,
  reviewed_at timestamptz,
  action_taken text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_player_reports_status ON player_reports (status, created_at DESC);
CREATE INDEX idx_player_reports_reporter ON player_reports (reporter_cloudkit_user_id, created_at DESC);
CREATE INDEX idx_player_reports_reported ON player_reports (reported_cloudkit_user_id);
ALTER TABLE player_reports ENABLE ROW LEVEL SECURITY;

-- ── moderation_flags ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS moderation_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cloudkit_user_id text NOT NULL,
  flag_type text NOT NULL CHECK (flag_type IN (
    'xp_velocity', 'gp_velocity', 'workout_impossible',
    'credit_anomaly', 'report_threshold'
  )),
  magnitude numeric,
  details jsonb DEFAULT '{}'::jsonb,
  auto_detected_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by text,
  reviewed_at timestamptz,
  resolution text CHECK (resolution IS NULL OR resolution IN (
    'confirmed_cheating', 'false_positive', 'warning_issued', 'banned'
  ))
);

CREATE INDEX idx_moderation_flags_unreviewed
  ON moderation_flags (reviewed_at NULLS FIRST, auto_detected_at DESC);
CREATE INDEX idx_moderation_flags_user
  ON moderation_flags (cloudkit_user_id, auto_detected_at DESC);
ALTER TABLE moderation_flags ENABLE ROW LEVEL SECURITY;

-- ── Auto-flag trigger: credit_transactions velocity ─────────────────────
CREATE OR REPLACE FUNCTION trg_check_credit_velocity()
RETURNS trigger AS $$
DECLARE
  v_threshold int := 10000;
  v_hourly_sum numeric;
  v_cfg_val text;
BEGIN
  IF NEW.amount <= 0 THEN RETURN NEW; END IF;
  SELECT value INTO v_cfg_val
    FROM remote_config
    WHERE key = 'moderation_gp_hourly_threshold' AND is_active = true
    LIMIT 1;
  IF v_cfg_val IS NOT NULL AND v_cfg_val ~ '^\d+$' THEN
    v_threshold := v_cfg_val::int;
  END IF;
  SELECT COALESCE(SUM(amount), 0) INTO v_hourly_sum
    FROM credit_transactions
    WHERE cloudkit_user_id = NEW.cloudkit_user_id
      AND amount > 0
      AND created_at >= now() - interval '1 hour';
  IF v_hourly_sum >= v_threshold THEN
    IF NOT EXISTS (
      SELECT 1 FROM moderation_flags
      WHERE cloudkit_user_id = NEW.cloudkit_user_id
        AND flag_type = 'gp_velocity'
        AND auto_detected_at >= now() - interval '1 hour'
    ) THEN
      INSERT INTO moderation_flags (cloudkit_user_id, flag_type, magnitude, details)
      VALUES (
        NEW.cloudkit_user_id, 'gp_velocity', v_hourly_sum,
        jsonb_build_object('threshold', v_threshold, 'hourly_sum', v_hourly_sum,
          'triggering_txn_type', NEW.transaction_type, 'triggering_amount', NEW.amount)
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_credit_velocity_check ON credit_transactions;
CREATE TRIGGER trg_credit_velocity_check
  AFTER INSERT ON credit_transactions FOR EACH ROW
  EXECUTE FUNCTION trg_check_credit_velocity();

-- ── Auto-flag trigger: report threshold ─────────────────────────────────
CREATE OR REPLACE FUNCTION trg_check_report_threshold()
RETURNS trigger AS $$
DECLARE
  v_threshold int := 3;
  v_cfg_val text;
  v_distinct_reporters int;
BEGIN
  SELECT value INTO v_cfg_val
    FROM remote_config
    WHERE key = 'moderation_report_auto_flag_count' AND is_active = true
    LIMIT 1;
  IF v_cfg_val IS NOT NULL AND v_cfg_val ~ '^\d+$' THEN
    v_threshold := v_cfg_val::int;
  END IF;
  SELECT COUNT(DISTINCT reporter_cloudkit_user_id) INTO v_distinct_reporters
    FROM player_reports
    WHERE reported_cloudkit_user_id = NEW.reported_cloudkit_user_id
      AND status IN ('pending', 'reviewing');
  IF v_distinct_reporters >= v_threshold THEN
    IF NOT EXISTS (
      SELECT 1 FROM moderation_flags
      WHERE cloudkit_user_id = NEW.reported_cloudkit_user_id
        AND flag_type = 'report_threshold'
        AND auto_detected_at >= now() - interval '1 day'
    ) THEN
      INSERT INTO moderation_flags (cloudkit_user_id, flag_type, magnitude, details)
      VALUES (
        NEW.reported_cloudkit_user_id, 'report_threshold', v_distinct_reporters,
        jsonb_build_object('distinct_reporters', v_distinct_reporters,
          'threshold', v_threshold, 'latest_reason', NEW.reason)
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_report_threshold_check ON player_reports;
CREATE TRIGGER trg_report_threshold_check
  AFTER INSERT ON player_reports FOR EACH ROW
  EXECUTE FUNCTION trg_check_report_threshold();

-- ── Admin stored procedures ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_review_report(
  p_report_id uuid, p_reviewer text, p_status text, p_action_taken text DEFAULT NULL
) RETURNS void AS $$
BEGIN
  IF p_status NOT IN ('reviewing', 'actioned', 'dismissed', 'duplicate') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;
  UPDATE player_reports
  SET status = p_status, reviewed_by = p_reviewer, reviewed_at = now(),
      action_taken = COALESCE(p_action_taken, action_taken)
  WHERE id = p_report_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_review_flag(
  p_flag_id uuid, p_reviewer text, p_resolution text
) RETURNS void AS $$
BEGIN
  IF p_resolution NOT IN ('confirmed_cheating', 'false_positive', 'warning_issued', 'banned') THEN
    RAISE EXCEPTION 'Invalid resolution: %', p_resolution;
  END IF;
  UPDATE moderation_flags
  SET reviewed_by = p_reviewer, reviewed_at = now(), resolution = p_resolution
  WHERE id = p_flag_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Remote config keys ──────────────────────────────────────────────────
INSERT INTO remote_config (key, value, value_type, description, is_active)
VALUES
  ('moderation_enabled', 'true', 'boolean', 'Master switch for moderation features', true),
  ('moderation_gp_hourly_threshold', '10000', 'integer', 'GP earned per hour that triggers auto-flag', true),
  ('moderation_xp_hourly_threshold', '50000', 'integer', 'XP earned per hour that triggers auto-flag', true),
  ('moderation_report_rate_limit', '5', 'integer', 'Max reports a single user can file per day', true),
  ('moderation_report_auto_flag_count', '3', 'integer', 'Distinct reporters needed to auto-flag a player', true)
ON CONFLICT (key) DO NOTHING;
