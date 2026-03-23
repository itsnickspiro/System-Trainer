# Supabase Edge Functions — Deployment Guide

API keys for API Ninjas and WeatherStack are stored in Supabase Vault and never
leave the server. The iOS app calls these Edge Functions, which proxy the request
and return the result.

---

## One-time setup

### 1. Install Supabase CLI

```bash
brew install supabase/tap/supabase
```

### 2. Log in

```bash
supabase login
```

### 3. Link this project

```bash
supabase link --project-ref erghbsnxtsbnmfuycnyb
```

---

## Store secrets in Supabase Vault

Run these once. Values are stored server-side and injected as environment
variables into the Edge Functions at runtime — never transmitted to clients.

```bash
# API Ninjas key (nutrition lookups)
supabase secrets set API_NINJAS_KEY="<your-api-ninjas-key>"

# WeatherStack key (weather data)
supabase secrets set WEATHERSTACK_API_KEY="<your-weatherstack-key>"
```

To add a new third-party key in the future:
```bash
supabase secrets set MY_NEW_KEY="<value>"
```
Then read it inside the relevant Edge Function via `Deno.env.get("MY_NEW_KEY")`.

Verify secrets are set:
```bash
supabase secrets list
```

---

## Deploy the Edge Functions

```bash
supabase functions deploy nutrition-proxy
supabase functions deploy weather-proxy
```

To deploy all functions at once:
```bash
supabase functions deploy
```

---

## Add the Supabase anon key to Xcode

The anon key is a **public** key (safe to ship in the app — it identifies the
project but grants only RLS-scoped access). Add it as an Xcode build setting so
it flows into Info.plist via `$(SUPABASE_ANON_KEY)`.

1. Open Xcode → RPT target → **Build Settings**
2. Click **+** → **Add User-Defined Setting**
3. Name: `SUPABASE_ANON_KEY`
4. Value: your anon key from Supabase Dashboard → Settings → API

Alternatively, create `RPT/Config.xcconfig` (gitignored):
```
SUPABASE_ANON_KEY = eyJ...your-anon-key...
```
And set it as the configuration file for the RPT target in Xcode project settings.

Get your anon key:
```
Supabase Dashboard → https://supabase.com/dashboard/project/erghbsnxtsbnmfuycnyb → Settings → API → Project API keys → anon public
```

---

## Test a function locally

```bash
supabase functions serve nutrition-proxy --env-file .env.local
```

`.env.local` (never commit this file):
```
API_NINJAS_KEY=your-key-here
WEATHERSTACK_API_KEY=your-key-here
```

Test with curl:
```bash
curl -X POST http://localhost:54321/functions/v1/nutrition-proxy \
  -H "Content-Type: application/json" \
  -d '{"query": "chicken breast"}'

curl -X POST http://localhost:54321/functions/v1/weather-proxy \
  -H "Content-Type: application/json" \
  -d '{"query": "New York"}'
```

---

## Adding future API keys

For any new third-party API:

1. Store the key: `supabase secrets set NEW_SERVICE_KEY="<value>"`
2. Create `supabase/functions/new-service-proxy/index.ts` following the same
   pattern as the existing functions
3. Deploy: `supabase functions deploy new-service-proxy`
4. Call it from Swift via `Secrets.supabaseURL + "/functions/v1/new-service-proxy"`
   with `Bearer \(Secrets.supabaseAnonKey)` as the Authorization header
5. **Do not add the raw key to Info.plist or Secrets.swift**
