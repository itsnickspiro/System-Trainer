# Supabase Deployment Guide

All secrets live server-side in Supabase Vault. The iOS app calls Edge Functions
which proxy/query as needed — no third-party API keys ever reach the client.

---

## Prerequisites

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref erghbsnxtsbnmfuycnyb
pip install requests  # for data pipeline scripts
```

---

## 1. Run the Database Migration

Creates the `exercises` table, tsvector + GIN full-text index, fuzzy trigram
index, RLS policy, storage bucket, and `search_exercises` RPC:

```bash
supabase db push
# or run the file directly against your DB:
supabase db execute < supabase/migrations/20240101000000_create_exercises.sql
```

---

## 2. Store Secrets in Supabase Vault

```bash
# Required for Edge Functions to query the exercises table
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="<your-service-role-key>"

# Shared secret — the iOS app sends this header on every request
supabase secrets set RPT_APP_SECRET="<your-app-secret>"

# Legacy secrets (still used by nutrition/weather proxies)
supabase secrets set API_NINJAS_KEY="<your-api-ninjas-key>"
supabase secrets set WEATHERSTACK_API_KEY="<your-weatherstack-key>"
```

Verify:
```bash
supabase secrets list
```

Get your service role key:
```
Dashboard → https://supabase.com/dashboard/project/erghbsnxtsbnmfuycnyb → Settings → API → service_role (secret)
```

---

## 3. Populate the Exercise Database

### Step 3a — Merge & Upload Exercise Data (~870–1,300 exercises)

```bash
cd supabase/scripts

# Set credentials
export SUPABASE_URL="https://erghbsnxtsbnmfuycnyb.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<your-service-role-key>"

# Dry run first to verify output
python3 build_exercise_db.py --dry-run

# Full run (fetches from 3 GitHub sources, merges, upserts to Supabase)
python3 build_exercise_db.py

# Optional: save merged JSON locally
python3 build_exercise_db.py --output merged_exercises.json
```

**What this does:**
- Fetches `yuhonas/free-exercise-db` (870+ exercises with static images, public domain)
- Fetches `wrkout/exercises.json` (structured exercises with tips, Unlicense)
- Maps GIF URLs from the same repo's animated preview files
- Merges and deduplicates by slug (URL-safe name)
- Upserts everything to `public.exercises` via the REST API

### Step 3b — Upload Media to Supabase Storage (optional but recommended)

This replaces raw GitHub CDN URLs with your own Supabase Storage URLs, giving
you full control over availability and loading speed.

> **Warning:** Images + GIFs total ~2–3 GB. This takes 20–40 minutes on a
> typical broadband connection. Run with `--limit 10` first to verify it works.

```bash
# Test with 10 exercises first
python3 upload_exercise_media.py --limit 10

# Upload everything
python3 upload_exercise_media.py

# Skip GIFs (faster, images only)
python3 upload_exercise_media.py --skip-gifs

# Re-upload even if file already in Storage
python3 upload_exercise_media.py --force
```

---

## 4. Populate the Food Database

### Step 4a — Run the Migration

```bash
supabase db push
# or run directly:
supabase db execute < supabase/migrations/20240102000000_create_foods.sql
```

### Step 4b — Seed Curated Foods (~200 items)

```bash
cd supabase/scripts

export SUPABASE_URL="https://erghbsnxtsbnmfuycnyb.supabase.co"
export DB_SERVICE_ROLE_KEY="<your-service-role-key>"

# Dry run first
python3 seed_foods.py --dry-run

# Seed (idempotent — upserts on name conflict)
python3 seed_foods.py
```

**What this does:**
- Upserts ~200 curated foods from `SampleFoodData.swift` to the `public.foods` table
- Marks all rows `is_verified=true`, `data_source="rpt"`
- Idempotent — safe to re-run

---

## 5. Deploy the Edge Functions

```bash
# Deploy all at once
supabase functions deploy

# Or deploy individually
supabase functions deploy exercises-proxy
supabase functions deploy nutrition-proxy
supabase functions deploy weather-proxy
supabase functions deploy recipe-proxy
supabase functions deploy foods-proxy
```

---

## 5. Add Keys to Xcode

### Supabase Anon Key (public — safe to ship)

1. Open Xcode → RPT target → **Build Settings**
2. Click **+** → **Add User-Defined Setting**
3. Name: `SUPABASE_ANON_KEY`
4. Value: from Dashboard → Settings → API → `anon public`

### App Secret (private — never commit)

Add a second User-Defined Setting:
- Name: `APP_SECRET`
- Value: same value you set with `supabase secrets set RPT_APP_SECRET`

Both flow into `Info.plist` and are read by `Secrets.swift` at runtime.

Get your anon key:
```
https://supabase.com/dashboard/project/erghbsnxtsbnmfuycnyb → Settings → API → anon public
```

---

## 6. Test the Exercise Search

```bash
# Test exercises-proxy (queries Supabase exercises table)
curl -X POST https://erghbsnxtsbnmfuycnyb.supabase.co/functions/v1/exercises-proxy \
  -H "Authorization: Bearer <anon-key>" \
  -H "x-app-secret: <app-secret>" \
  -H "Content-Type: application/json" \
  -d '{"query": "squat", "limit": 5}'

# Test nutrition proxy (unchanged)
curl -X POST https://erghbsnxtsbnmfuycnyb.supabase.co/functions/v1/nutrition-proxy \
  -H "Authorization: Bearer <anon-key>" \
  -H "x-app-secret: <app-secret>" \
  -H "Content-Type: application/json" \
  -d '{"query": "chicken breast"}'
```

---

## 7. Test Locally

```bash
# Create .env.local (never commit this file)
cat > .env.local <<EOF
SUPABASE_URL=https://erghbsnxtsbnmfuycnyb.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>
RPT_APP_SECRET=<your-app-secret>
API_NINJAS_KEY=<your-api-ninjas-key>
WEATHERSTACK_API_KEY=<your-weatherstack-key>
EOF

# Serve functions locally
supabase functions serve --env-file .env.local

# Test in another terminal
curl -X POST http://localhost:54321/functions/v1/exercises-proxy \
  -H "Content-Type: application/json" \
  -H "x-app-secret: <app-secret>" \
  -d '{"query": "bench press"}'
```

---

## Architecture Overview

```
iOS App
  └── ExercisesAPI.fetchExercises(name: "squat")
        └── POST /functions/v1/exercises-proxy
              └── Supabase Edge Function
                    └── supabase.rpc("search_exercises", { query: "squat" })
                          └── PostgreSQL
                                ├── tsvector GIN index (full-text)
                                └── pg_trgm GIN index (fuzzy/partial match)

Exercise Data Sources (one-time import)
  ├── yuhonas/free-exercise-db  →  870+ exercises + static images
  ├── wrkout/exercises.json     →  enriched tips + mechanic fields
  └── ExerciseDB GIF map        →  animated GIF previews

Media Storage
  └── Supabase Storage bucket: exercise-media
        ├── exercises/<slug>/0.jpg  (static image 1)
        ├── exercises/<slug>/1.jpg  (static image 2)
        └── exercises/<slug>/<slug>.gif  (animation)
```

---

## Refreshing Exercise Data

To pull in updated exercises from the upstream sources:

```bash
python3 supabase/scripts/build_exercise_db.py
python3 supabase/scripts/upload_exercise_media.py --skip-gifs  # only new images
```

The upsert uses `slug` as the conflict key so re-running is idempotent.

---

## Adding Future API Keys

1. Store: `supabase secrets set NEW_SERVICE_KEY="<value>"`
2. Create `supabase/functions/new-service-proxy/index.ts` (follow existing pattern)
3. Deploy: `supabase functions deploy new-service-proxy`
4. Call from Swift via `Secrets.supabaseURL + "/functions/v1/new-service-proxy"`
5. **Never** put the raw key in `Info.plist` or `Secrets.swift`
