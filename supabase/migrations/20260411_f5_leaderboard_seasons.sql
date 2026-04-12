-- F5: Leaderboard Seasons
-- See apply_migration for the full version applied to the DB.
-- This file is kept in the repo for reference.

CREATE TABLE IF NOT EXISTS leaderboard_seasons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  season_number int NOT NULL UNIQUE,
  label text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'active', 'finalizing', 'completed')),
  reward_gp_first int DEFAULT 5000,
  reward_gp_top10 int DEFAULT 2000,
  reward_gp_top50 int DEFAULT 500,
  reward_gp_top100 int DEFAULT 200,
  reward_avatar_key text,
  reward_title_key text,
  finalized_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS season_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id uuid NOT NULL REFERENCES leaderboard_seasons(id),
  cloudkit_user_id text NOT NULL,
  display_name text,
  final_rank int NOT NULL,
  season_xp bigint NOT NULL DEFAULT 0,
  reward_gp int NOT NULL DEFAULT 0,
  reward_avatar_key text,
  reward_title_key text,
  claimed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (season_id, cloudkit_user_id)
);

ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS season_xp bigint DEFAULT 0;
ALTER TABLE player_profiles ADD COLUMN IF NOT EXISTS active_title_key text;
ALTER TABLE leaderboard ADD COLUMN IF NOT EXISTS season_xp bigint DEFAULT 0;
