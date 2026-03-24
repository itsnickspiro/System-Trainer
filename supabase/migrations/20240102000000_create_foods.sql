-- =============================================================================
-- Foods Database Migration
-- Curated baseline food database seeded from SampleFoodData.swift.
-- iOS app queries this first, then falls back to USDA / Open Food Facts.
-- =============================================================================

-- Enable pg_trgm for fuzzy name search (already enabled by exercises migration,
-- but idempotent so safe to call again)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =============================================================================
-- Main foods table
-- Column names mirror FoodItem @Model in Models.swift
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.foods (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Core identity
    name            text NOT NULL UNIQUE,  -- dedup key for upserts
    brand           text,
    barcode         text UNIQUE,           -- EAN-13 / UPC-A for barcode lookup

    -- Macros (per 100 g)
    calories_per_100g   double precision NOT NULL DEFAULT 0,
    serving_size_g      double precision NOT NULL DEFAULT 100,
    carbohydrates       double precision NOT NULL DEFAULT 0,
    protein             double precision NOT NULL DEFAULT 0,
    fat                 double precision NOT NULL DEFAULT 0,
    fiber               double precision NOT NULL DEFAULT 0,
    sugar               double precision NOT NULL DEFAULT 0,
    sodium_mg           double precision NOT NULL DEFAULT 0,

    -- Extended micros (nullable — not all sources provide these)
    potassium_mg        double precision,
    calcium_mg          double precision,
    iron_mg             double precision,
    vitamin_c_mg        double precision,
    vitamin_d_mcg       double precision,
    vitamin_a_mcg       double precision,
    saturated_fat       double precision,
    cholesterol_mg      double precision,

    -- Classification / provenance
    category        text,               -- 'proteins' | 'grains' | 'vegetables' | 'fruits' |
                                        -- 'dairy' | 'nuts_seeds' | 'oils' | 'beverages' |
                                        -- 'snacks' | 'prepared' | 'supplements'
    is_verified     boolean NOT NULL DEFAULT true,   -- curated = true, user-added = false
    data_source     text NOT NULL DEFAULT 'rpt',     -- 'rpt' | 'usda' | 'off'

    -- Full-text search vector
    fts             tsvector,

    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- Full-text search trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION public.foods_fts_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.fts :=
        setweight(to_tsvector('english', coalesce(NEW.name,     '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.brand,    '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.category, '')), 'C');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS foods_fts_trigger ON public.foods;
CREATE TRIGGER foods_fts_trigger
    BEFORE INSERT OR UPDATE ON public.foods
    FOR EACH ROW EXECUTE FUNCTION public.foods_fts_update();

-- =============================================================================
-- Updated_at trigger
-- =============================================================================

DROP TRIGGER IF EXISTS foods_updated_at ON public.foods;
CREATE TRIGGER foods_updated_at
    BEFORE UPDATE ON public.foods
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();   -- defined in exercises migration

-- =============================================================================
-- Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS foods_fts_idx        ON public.foods USING GIN (fts);
CREATE INDEX IF NOT EXISTS foods_name_trgm_idx  ON public.foods USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS foods_category_idx   ON public.foods (category);
CREATE INDEX IF NOT EXISTS foods_barcode_idx    ON public.foods (barcode) WHERE barcode IS NOT NULL;

-- =============================================================================
-- Row-Level Security
-- Public read; writes only via service_role (seeding / admin)
-- =============================================================================

ALTER TABLE public.foods ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "foods_public_read" ON public.foods;
CREATE POLICY "foods_public_read"
    ON public.foods
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- =============================================================================
-- Search RPC
-- Called by iOS via foods-proxy Edge Function
-- =============================================================================

CREATE OR REPLACE FUNCTION public.search_foods(
    p_query     text    DEFAULT '',
    p_category  text    DEFAULT '',
    p_barcode   text    DEFAULT '',
    lim         integer DEFAULT 30,
    off         integer DEFAULT 0
)
RETURNS TABLE (
    id                  uuid,
    name                text,
    brand               text,
    barcode             text,
    calories_per_100g   double precision,
    serving_size_g      double precision,
    carbohydrates       double precision,
    protein             double precision,
    fat                 double precision,
    fiber               double precision,
    sugar               double precision,
    sodium_mg           double precision,
    potassium_mg        double precision,
    calcium_mg          double precision,
    iron_mg             double precision,
    vitamin_c_mg        double precision,
    vitamin_d_mcg       double precision,
    vitamin_a_mcg       double precision,
    saturated_fat       double precision,
    cholesterol_mg      double precision,
    category            text,
    is_verified         boolean,
    data_source         text,
    rank                real
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    tsq         tsquery;
    clean_query text;
BEGIN
    -- Barcode lookup takes priority
    IF p_barcode IS NOT NULL AND trim(p_barcode) <> '' THEN
        RETURN QUERY
        SELECT
            f.id, f.name, f.brand, f.barcode,
            f.calories_per_100g, f.serving_size_g,
            f.carbohydrates, f.protein, f.fat, f.fiber, f.sugar, f.sodium_mg,
            f.potassium_mg, f.calcium_mg, f.iron_mg,
            f.vitamin_c_mg, f.vitamin_d_mcg, f.vitamin_a_mcg,
            f.saturated_fat, f.cholesterol_mg,
            f.category, f.is_verified, f.data_source,
            1.0::real AS rank
        FROM public.foods f
        WHERE f.barcode = trim(p_barcode)
        LIMIT 1;
        RETURN;
    END IF;

    -- Build tsquery for free-text search
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
        f.id, f.name, f.brand, f.barcode,
        f.calories_per_100g, f.serving_size_g,
        f.carbohydrates, f.protein, f.fat, f.fiber, f.sugar, f.sodium_mg,
        f.potassium_mg, f.calcium_mg, f.iron_mg,
        f.vitamin_c_mg, f.vitamin_d_mcg, f.vitamin_a_mcg,
        f.saturated_fat, f.cholesterol_mg,
        f.category, f.is_verified, f.data_source,
        CASE
            WHEN tsq IS NOT NULL AND f.fts IS NOT NULL THEN
                (ts_rank_cd(f.fts, tsq) * 0.7 +
                 similarity(lower(f.name), lower(coalesce(p_query, ''))) * 0.3)::real
            ELSE
                1.0::real
        END AS rank
    FROM public.foods f
    WHERE
        (
            clean_query IS NULL
            OR tsq IS NULL
            OR (f.fts IS NOT NULL AND f.fts @@ tsq)
            OR similarity(lower(f.name), lower(coalesce(clean_query, ''))) > 0.15
        )
        AND (p_category = '' OR p_category IS NULL OR lower(f.category) = lower(p_category))
    ORDER BY rank DESC, f.name ASC
    LIMIT lim
    OFFSET off;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_foods TO anon, authenticated;
