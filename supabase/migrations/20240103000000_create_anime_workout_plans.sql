-- =============================================================================
-- Anime Workout Plans Migration
-- Stores the curated anime workout plans that ship in AnimeWorkouts.swift.
-- Keeps plan data server-side so plans can be updated without an App Store
-- release.  The iOS app fetches on launch and falls back to the bundled data.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =============================================================================
-- Main table
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.anime_workout_plans (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identity / display
    plan_key        text NOT NULL UNIQUE,   -- stable string key (e.g. "saitama")
    character_name  text NOT NULL,
    anime           text NOT NULL,
    tagline         text NOT NULL DEFAULT '',
    description     text NOT NULL DEFAULT '',

    -- Classification
    difficulty      text NOT NULL DEFAULT 'intermediate',
                                            -- beginner | intermediate | advanced | elite
    accent_color    text NOT NULL DEFAULT 'blue',
                                            -- SwiftUI Color name stored as string
    icon_symbol     text NOT NULL DEFAULT 'figure.run',
                                            -- SF Symbol name
    target_gender   text,                   -- 'male' | 'female' | NULL = unisex

    -- Weekly schedule — 7-element JSON array (index 0 = Monday)
    -- Each element: { dayName, focus, isRest, exercises[], questTitle,
    --                 questDetails, xpReward }
    -- exercises[]: { name, sets, reps, restSeconds, notes }
    weekly_schedule jsonb NOT NULL DEFAULT '[]'::jsonb,

    -- Nutrition targets
    daily_calories  integer NOT NULL DEFAULT 2000,
    protein_grams   integer NOT NULL DEFAULT 150,
    carb_grams      integer NOT NULL DEFAULT 200,
    fat_grams       integer NOT NULL DEFAULT 65,
    water_glasses   integer NOT NULL DEFAULT 8,
    meal_prep_tips  text[]  NOT NULL DEFAULT '{}',
    avoid_list      text[]  NOT NULL DEFAULT '{}',

    -- Ordering / visibility
    sort_order      integer NOT NULL DEFAULT 0,
    is_active       boolean NOT NULL DEFAULT true,

    -- Provenance
    data_source     text    NOT NULL DEFAULT 'rpt',

    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- updated_at trigger (reuses function from exercises migration)
-- =============================================================================

DROP TRIGGER IF EXISTS anime_plans_updated_at ON public.anime_workout_plans;
CREATE TRIGGER anime_plans_updated_at
    BEFORE UPDATE ON public.anime_workout_plans
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS anime_plans_key_idx      ON public.anime_workout_plans (plan_key);
CREATE INDEX IF NOT EXISTS anime_plans_active_idx   ON public.anime_workout_plans (is_active) WHERE is_active;
CREATE INDEX IF NOT EXISTS anime_plans_order_idx    ON public.anime_workout_plans (sort_order);
CREATE INDEX IF NOT EXISTS anime_plans_gender_idx   ON public.anime_workout_plans (target_gender);
CREATE INDEX IF NOT EXISTS anime_plans_schedule_idx ON public.anime_workout_plans USING GIN (weekly_schedule);

-- =============================================================================
-- Row-Level Security — public read, writes via service_role only
-- =============================================================================

ALTER TABLE public.anime_workout_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anime_plans_public_read" ON public.anime_workout_plans;
CREATE POLICY "anime_plans_public_read"
    ON public.anime_workout_plans
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- =============================================================================
-- RPC — fetch_anime_plans
-- Called by iOS via anime-plans-proxy Edge Function.
-- Returns all active plans ordered by sort_order.
-- Optionally filter by gender.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fetch_anime_plans(
    p_gender    text    DEFAULT '',
    p_plan_key  text    DEFAULT ''
)
RETURNS TABLE (
    id              uuid,
    plan_key        text,
    character_name  text,
    anime           text,
    tagline         text,
    description     text,
    difficulty      text,
    accent_color    text,
    icon_symbol     text,
    target_gender   text,
    weekly_schedule jsonb,
    daily_calories  integer,
    protein_grams   integer,
    carb_grams      integer,
    fat_grams       integer,
    water_glasses   integer,
    meal_prep_tips  text[],
    avoid_list      text[],
    sort_order      integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
BEGIN
    -- Single-plan lookup by key
    IF p_plan_key IS NOT NULL AND trim(p_plan_key) <> '' THEN
        RETURN QUERY
        SELECT
            p.id, p.plan_key, p.character_name, p.anime, p.tagline,
            p.description, p.difficulty, p.accent_color, p.icon_symbol,
            p.target_gender, p.weekly_schedule,
            p.daily_calories, p.protein_grams, p.carb_grams,
            p.fat_grams, p.water_glasses, p.meal_prep_tips, p.avoid_list,
            p.sort_order
        FROM public.anime_workout_plans p
        WHERE p.is_active = true
          AND p.plan_key = trim(p_plan_key)
        LIMIT 1;
        RETURN;
    END IF;

    -- All active plans, optionally filtered by gender
    RETURN QUERY
    SELECT
        p.id, p.plan_key, p.character_name, p.anime, p.tagline,
        p.description, p.difficulty, p.accent_color, p.icon_symbol,
        p.target_gender, p.weekly_schedule,
        p.daily_calories, p.protein_grams, p.carb_grams,
        p.fat_grams, p.water_glasses, p.meal_prep_tips, p.avoid_list,
        p.sort_order
    FROM public.anime_workout_plans p
    WHERE p.is_active = true
      AND (
          p_gender IS NULL OR trim(p_gender) = ''
          OR p.target_gender IS NULL
          OR lower(p.target_gender) = lower(trim(p_gender))
      )
    ORDER BY p.sort_order ASC, p.character_name ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fetch_anime_plans TO anon, authenticated;
