-- =============================================================================
-- Exercise Database Migration
-- Unified table merging yuhonas/free-exercise-db, wrkout/exercises.json,
-- and ExerciseDB/exercisedb-api. All media uploaded to Supabase Storage.
-- =============================================================================

-- Enable pg_trgm for fuzzy search (trigram similarity)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =============================================================================
-- Main exercises table
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.exercises (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    slug            text UNIQUE NOT NULL,  -- URL-safe name, used as dedup key

    -- Muscle groups (stored as arrays for multi-muscle exercises)
    primary_muscles   text[] NOT NULL DEFAULT '{}',
    secondary_muscles text[] NOT NULL DEFAULT '{}',

    -- Classification
    force       text,   -- 'push' | 'pull' | 'static' | null
    level       text,   -- 'beginner' | 'intermediate' | 'expert'
    mechanic    text,   -- 'compound' | 'isolation' | null
    equipment   text,   -- 'barbell' | 'dumbbell' | 'body only' | etc.
    category    text,   -- 'strength' | 'cardio' | 'stretching' | 'plyometrics' | 'olympic weightlifting' | 'powerlifting'

    -- Content
    instructions  text[]  NOT NULL DEFAULT '{}',  -- ordered steps
    tips          text,                            -- coaching cue / tip paragraph

    -- Media (all URLs point to Supabase Storage after upload)
    image_urls    text[]  NOT NULL DEFAULT '{}',  -- static images (2 per exercise from free-exercise-db)
    gif_url       text,                            -- animated GIF from ExerciseDB

    -- Auto-generated YouTube search link built from name + category
    youtube_search_url text GENERATED ALWAYS AS (
        'https://www.youtube.com/results?search_query=' ||
        replace(replace(lower(trim(name)), ' ', '+'), '/', '%2F') ||
        '+' ||
        coalesce(replace(lower(trim(category)), ' ', '+'), 'exercise') ||
        '+tutorial'
    ) STORED,

    -- Full-text search vector (maintained by trigger below)
    fts tsvector,

    -- Source tracking (bitmask: 1=free-exercise-db, 2=wrkout, 4=exercisedb)
    source_flags  integer NOT NULL DEFAULT 0,

    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- Full-text search trigger
-- Weighted: name A (highest), muscles B, category/equipment C, instructions D
-- =============================================================================

CREATE OR REPLACE FUNCTION public.exercises_fts_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.fts :=
        setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(array_to_string(NEW.primary_muscles, ' '), '')), 'B') ||
        setweight(to_tsvector('english', coalesce(array_to_string(NEW.secondary_muscles, ' '), '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.category, '')), 'C') ||
        setweight(to_tsvector('english', coalesce(NEW.equipment, '')), 'C') ||
        setweight(to_tsvector('english', coalesce(NEW.level, '')), 'C') ||
        setweight(to_tsvector('english', coalesce(array_to_string(NEW.instructions, ' '), '')), 'D');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS exercises_fts_trigger ON public.exercises;
CREATE TRIGGER exercises_fts_trigger
    BEFORE INSERT OR UPDATE ON public.exercises
    FOR EACH ROW EXECUTE FUNCTION public.exercises_fts_update();

-- =============================================================================
-- Indexes
-- =============================================================================

-- GIN index on tsvector for fast full-text search
CREATE INDEX IF NOT EXISTS exercises_fts_idx ON public.exercises USING GIN (fts);

-- Trigram index on name for fuzzy prefix/substring matching
CREATE INDEX IF NOT EXISTS exercises_name_trgm_idx ON public.exercises USING GIN (name gin_trgm_ops);

-- Category + level filter (used for browse-by-type queries)
CREATE INDEX IF NOT EXISTS exercises_category_level_idx ON public.exercises (category, level);

-- =============================================================================
-- Updated_at trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS exercises_updated_at ON public.exercises;
CREATE TRIGGER exercises_updated_at
    BEFORE UPDATE ON public.exercises
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- Row-Level Security
-- Public read, no client writes (all writes are server-side via service_role)
-- =============================================================================

ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "exercises_public_read" ON public.exercises;
CREATE POLICY "exercises_public_read"
    ON public.exercises
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- =============================================================================
-- Search RPC
-- Called by the iOS app via Edge Function → supabase.rpc("search_exercises")
-- Returns up to `lim` exercises ranked by full-text relevance + trigram
-- similarity so partial/misspelled queries still return useful results.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.search_exercises(
    p_query     text    DEFAULT '',
    p_category  text    DEFAULT '',
    p_level     text    DEFAULT '',
    p_equipment text    DEFAULT '',
    p_muscle    text    DEFAULT '',
    lim         integer DEFAULT 30,
    off         integer DEFAULT 0
)
RETURNS TABLE (
    id                uuid,
    name              text,
    slug              text,
    primary_muscles   text[],
    secondary_muscles text[],
    force             text,
    level             text,
    mechanic          text,
    equipment         text,
    category          text,
    instructions      text[],
    tips              text,
    image_urls        text[],
    gif_url           text,
    youtube_search_url text,
    rank              real
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    tsq tsquery;
    clean_query text;
BEGIN
    -- Sanitize + build tsquery from free-form input
    IF p_query IS NOT NULL AND trim(p_query) <> '' THEN
        clean_query := trim(regexp_replace(p_query, '[^a-zA-Z0-9 ]', ' ', 'g'));
        BEGIN
            tsq := websearch_to_tsquery('english', clean_query);
        EXCEPTION WHEN OTHERS THEN
            tsq := NULL;
        END;
    END IF;

    RETURN QUERY
    SELECT
        e.id,
        e.name,
        e.slug,
        e.primary_muscles,
        e.secondary_muscles,
        e.force,
        e.level,
        e.mechanic,
        e.equipment,
        e.category,
        e.instructions,
        e.tips,
        e.image_urls,
        e.gif_url,
        e.youtube_search_url,
        CASE
            WHEN tsq IS NOT NULL AND e.fts IS NOT NULL THEN
                (ts_rank_cd(e.fts, tsq) * 0.7 +
                 similarity(lower(e.name), lower(coalesce(p_query, ''))) * 0.3)::real
            ELSE
                1.0::real
        END AS rank
    FROM public.exercises e
    WHERE
        (
            clean_query IS NULL
            OR tsq IS NULL
            OR (e.fts IS NOT NULL AND e.fts @@ tsq)
            OR similarity(lower(e.name), lower(coalesce(clean_query, ''))) > 0.15
        )
        AND (p_category  = '' OR p_category  IS NULL OR lower(e.category)  = lower(p_category))
        AND (p_level     = '' OR p_level     IS NULL OR lower(e.level)     = lower(p_level))
        AND (p_equipment = '' OR p_equipment IS NULL OR lower(e.equipment) ILIKE '%' || lower(p_equipment) || '%')
        AND (p_muscle    = '' OR p_muscle    IS NULL OR
             lower(array_to_string(e.primary_muscles,   '|')) ILIKE '%' || lower(p_muscle) || '%' OR
             lower(array_to_string(e.secondary_muscles, '|')) ILIKE '%' || lower(p_muscle) || '%'
        )
    ORDER BY rank DESC, e.name ASC
    LIMIT lim
    OFFSET off;
END;
$$;

-- Grant execute to anon + authenticated (RLS on the underlying table handles security)
GRANT EXECUTE ON FUNCTION public.search_exercises TO anon, authenticated;

-- =============================================================================
-- Storage bucket for exercise media
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'exercise-media',
    'exercise-media',
    true,         -- public bucket: all URLs are directly accessible
    5242880,      -- 5 MB per file
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Public read policy for the bucket
DROP POLICY IF EXISTS "exercise_media_public_read" ON storage.objects;
CREATE POLICY "exercise_media_public_read"
    ON storage.objects FOR SELECT
    TO anon, authenticated
    USING (bucket_id = 'exercise-media');
