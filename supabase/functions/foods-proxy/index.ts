import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-app-secret",
};

// Fields requested from Open Food Facts to keep responses lean.
const OFF_FIELDS = [
  "code", "product_name", "brands", "categories_tags",
  "serving_size", "serving_quantity", "nutriments",
  "nova_group", "additives_tags",
  "ingredients_text",
].join(",");

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Verify the request comes from the RPT app
  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  if (!appSecret || !incomingSecret || incomingSecret !== appSecret) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  try {
    const body = await req.json();

    // ── Dispatch ────────────────────────────────────────────────────────────
    // F10: community food submissions. These actions come before the
    // legacy dispatch checks below. If `action` is set, route to the
    // corresponding handler; otherwise fall through to the legacy
    // off_barcode / off_search / Supabase search flow.
    if (typeof body.action === "string" && body.action.length > 0) {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("DB_SERVICE_ROLE_KEY")!,
        { auth: { persistSession: false } },
      );
      switch (body.action) {
        case "submit_pending_food":
          return await handleSubmitPendingFood(supabase, body);
        case "get_pending_food_by_barcode":
          return await handleGetPendingByBarcode(supabase, body);
        case "vote_pending_food":
          return await handleVotePendingFood(supabase, body);
        case "get_my_pending_submissions":
          return await handleGetMyPendingSubmissions(supabase, body);
        case "admin_insert_food":
          return await handleAdminInsertFood(supabase, body);
        case "admin_edit_food":
          return await handleAdminEditFood(supabase, body);
        default:
          // Unknown action — fall through to legacy dispatch. Don't 404
          // because old clients may send other action strings the server
          // hasn't learned about yet.
          break;
      }
    }

    // off_barcode: barcode lookup via Open Food Facts product API
    if (body.off_barcode) {
      return await handleOFFBarcode(body.off_barcode.trim());
    }

    // off_search: text search via Open Food Facts search API
    if (body.off_search) {
      const limit = Math.min(parseInt(body.limit ?? "25", 10), 100);
      return await handleOFFSearch(body.off_search.trim(), limit);
    }

    // Default: Supabase curated foods table
    return await handleSupabaseSearch(body);

  } catch (err) {
    console.error("foods-proxy error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

// ── Open Food Facts — barcode lookup ────────────────────────────────────────

async function handleOFFBarcode(barcode: string): Promise<Response> {
  const url = `https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(barcode)}.json?fields=${OFF_FIELDS}`;
  const upstream = await fetch(url, {
    headers: { "User-Agent": "RPT-FitnessApp/1.0 (iOS; contact@rpt.app)" },
  });

  const data = await upstream.json();

  if (!upstream.ok || data.status !== 1 || !data.product) {
    return new Response(JSON.stringify(null), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const item = mapOFFProduct(data.product, barcode);
  return new Response(JSON.stringify(item), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Open Food Facts — text search ───────────────────────────────────────────

async function handleOFFSearch(query: string, limit: number): Promise<Response> {
  const params = new URLSearchParams({
    q: query,
    fields: OFF_FIELDS,
    page_size: String(limit),
    json: "true",
  });
  const url = `https://search.openfoodfacts.org/search?${params}`;
  const upstream = await fetch(url, {
    headers: { "User-Agent": "RPT-FitnessApp/1.0 (iOS; contact@rpt.app)" },
  });

  const data = await upstream.json();
  const hits: unknown[] = Array.isArray(data.hits) ? data.hits : [];
  const items = hits
    .map((p) => mapOFFProduct(p as Record<string, unknown>, null))
    .filter(Boolean);

  return new Response(JSON.stringify(items), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Supabase curated foods table ─────────────────────────────────────────────

async function handleSupabaseSearch(body: Record<string, unknown>): Promise<Response> {
  const query: string    = ((body.query    ?? body.name ?? "") as string).trim();
  const barcode: string  = ((body.barcode  ?? "") as string).trim();
  const category: string = ((body.category ?? "") as string).trim();
  const limit: number    = Math.min(parseInt((body.limit  ?? "30") as string, 10), 100);
  const offset: number   = Math.max(parseInt((body.offset ?? "0")  as string, 10), 0);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey  = Deno.env.get("DB_SERVICE_ROLE_KEY")!;
  const supabase    = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const { data, error } = await supabase.rpc("search_foods", {
    p_query:    query,
    p_category: category,
    p_barcode:  barcode,
    lim:        limit,
    off:        offset,
  });

  if (error) {
    console.error("RPC error:", error);
    return new Response(
      JSON.stringify({ error: "Database query failed", detail: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  // Map DB rows to the FoodItem-shaped JSON the Swift client expects.
  const foods = (data ?? []).map((row: Record<string, unknown>) => ({
    id:               row.id,
    name:             row.name,
    brand:            row.brand            ?? null,
    barcode:          row.barcode          ?? null,
    caloriesPer100g:  row.calories_per_100g,
    servingSize:      row.serving_size_g,
    carbohydrates:    row.carbohydrates,
    protein:          row.protein,
    fat:              row.fat,
    fiber:            row.fiber,
    sugar:            row.sugar,
    sodium:           row.sodium_mg,
    potassiumMg:      row.potassium_mg     ?? null,
    calciumMg:        row.calcium_mg       ?? null,
    ironMg:           row.iron_mg          ?? null,
    vitaminCMg:       row.vitamin_c_mg     ?? null,
    vitaminDMcg:      row.vitamin_d_mcg    ?? null,
    vitaminAMcg:      row.vitamin_a_mcg    ?? null,
    saturatedFat:     row.saturated_fat    ?? null,
    cholesterolMg:    row.cholesterol_mg   ?? null,
    category:         row.category         ?? null,
    isVerified:       row.is_verified      ?? false,
    dataSource:       row.data_source      ?? "rpt",
    // Diet tags (Phase D1)
    containsMeat:     row.contains_meat       ?? false,
    containsFish:     row.contains_fish       ?? false,
    containsDairy:    row.contains_dairy      ?? false,
    containsEggs:     row.contains_eggs       ?? false,
    containsGluten:   row.contains_gluten     ?? false,
    containsAlcohol:  row.contains_alcohol    ?? false,
    isHalalCertified: row.is_halal_certified  ?? false,
    // Yuka-style ingredient grading (Phase D session 7)
    ingredientText:   row.ingredient_text     ?? "",
  }));

  return new Response(JSON.stringify(foods), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── OFF product → FoodItem-shaped JSON ──────────────────────────────────────
// Produces the same camelCase shape as the Supabase path so the Swift
// SupabaseFoodRow decoder handles both without any changes.

function mapOFFProduct(
  p: Record<string, unknown>,
  barcodeOverride: string | null
): Record<string, unknown> | null {
  const rawName = (p.product_name as string | undefined)?.trim();
  if (!rawName) return null;

  const n = (p.nutriments ?? {}) as Record<string, number | undefined>;

  // Calories: prefer energy-kcal_100g, fall back to kJ / 4.184
  const cal100g =
    n["energy-kcal_100g"] ??
    n["energy_kcal_100g"] ??
    ((n["energy_100g"] ?? 0) / 4.184);

  // Serving size in grams
  let servingGrams = 100.0;
  const servingQty = p.serving_quantity as number | undefined;
  if (servingQty && servingQty > 0) {
    servingGrams = servingQty;
  } else if (p.serving_size) {
    const parsed = parseServingGrams(p.serving_size as string);
    if (parsed) servingGrams = parsed;
  }

  const brand = (p.brands as string | undefined)
    ?.split(",")[0]
    ?.trim() ?? null;

  const tags = (p.categories_tags as string[] | undefined) ?? [];
  const additiveTags = (p.additives_tags as string[] | undefined) ?? [];
  const novaGroup = (p.nova_group as number | undefined) ?? 0;

  return {
    id:             null,
    name:           rawName,
    brand:          brand,
    barcode:        barcodeOverride ?? (p.code as string | undefined) ?? null,
    caloriesPer100g: cal100g,
    servingSize:    servingGrams,
    carbohydrates:  n["carbohydrates_100g"] ?? 0,
    protein:        n["proteins_100g"]      ?? 0,
    fat:            n["fat_100g"]           ?? 0,
    fiber:          n["fiber_100g"]         ?? 0,
    sugar:          n["sugars_100g"]        ?? 0,
    sodium:         (n["sodium_100g"] ?? 0) * 1000,  // g → mg
    potassiumMg:    null,
    calciumMg:      null,
    ironMg:         null,
    vitaminCMg:     null,
    vitaminDMcg:    null,
    vitaminAMcg:    null,
    saturatedFat:   n["saturated-fat_100g"] ?? null,
    cholesterolMg:  null,
    category:       detectCategory(tags),
    isVerified:     false,
    dataSource:     "OpenFoodFacts",
    novaGroup:      novaGroup,
    additiveRisk:   computeAdditiveRisk(additiveTags),
    // Diet tags (Phase D1) — OFF doesn't supply these directly; defaults are safe.
    containsMeat:     false,
    containsFish:     false,
    containsDairy:    false,
    containsEggs:     false,
    containsGluten:   false,
    containsAlcohol:  false,
    isHalalCertified: false,
    // Yuka-style ingredient grading (Phase D session 7)
    ingredientText:   (p.ingredients_text as string | undefined) ?? "",
  };
}

function parseServingGrams(raw: string): number | null {
  const lower = raw.toLowerCase();
  const gMatch = lower.match(/(\d+(?:\.\d+)?)\s*g(?:ram)?/);
  if (gMatch) return parseFloat(gMatch[1]);
  const numMatch = lower.match(/(\d+(?:\.\d+)?)/);
  return numMatch ? parseFloat(numMatch[1]) : null;
}

function detectCategory(tags: string[]): string {
  for (const tag of tags) {
    const t = tag.toLowerCase();
    if (t.includes("protein") || t.includes("meat") || t.includes("fish") ||
        t.includes("poultry") || t.includes("egg")) return "proteins";
    if (t.includes("fruit"))                          return "fruits";
    if (t.includes("vegetable"))                      return "vegetables";
    if (t.includes("grain") || t.includes("bread") ||
        t.includes("cereal") || t.includes("pasta") ||
        t.includes("rice"))                           return "grains";
    if (t.includes("dairy") || t.includes("milk") ||
        t.includes("cheese") || t.includes("yogurt")) return "dairy";
    if (t.includes("snack") || t.includes("sweet") ||
        t.includes("chocolate") || t.includes("candy")) return "snacks";
    if (t.includes("beverage") || t.includes("drink") ||
        t.includes("juice"))                          return "beverages";
    if (t.includes("fat") || t.includes("oil") ||
        t.includes("butter"))                         return "fats";
  }
  return "other";
}

function computeAdditiveRisk(tags: string[]): number {
  const count = tags.length;
  if (count === 0) return 0;
  if (count <= 2)  return 1;
  if (count <= 5)  return 2;
  return 3;
}

// ── F10: Community food submission handlers ───────────────────────────────────
//
// The server-side auto-promotion pipeline is already in place:
//   - trg_update_vote_count on food_votes: recomputes foods_pending.vote_count
//     as (confirms - disputes) on every vote insert/update
//   - trg_auto_promote_food on foods_pending UPDATE: when vote_count crosses
//     threshold (3), checks for barcode/name duplicates and inserts into
//     public.foods with data_source='community' + is_verified=true
//
// These 4 handlers expose the CRUD surface the iOS client needs.

// F9 phase 1: banned players can't submit or vote.
async function isBanned(
  supabase: ReturnType<typeof createClient>,
  cloudkitUserId: string,
): Promise<boolean> {
  if (!cloudkitUserId) return false;
  try {
    const { data, error } = await supabase.rpc("is_player_banned", {
      p_cloudkit_user_id: cloudkitUserId,
    });
    if (error) return false;
    return data === true;
  } catch (_) {
    return false;
  }
}

// Admin check: query player_profiles.is_admin. Fails CLOSED (returns false on error).
async function isAdmin(
  supabase: ReturnType<typeof createClient>,
  cloudkitUserId: string,
): Promise<boolean> {
  if (!cloudkitUserId) return false;
  try {
    const { data, error } = await supabase
      .from("player_profiles")
      .select("is_admin")
      .eq("cloudkit_user_id", cloudkitUserId)
      .maybeSingle();
    if (error) return false;
    return data?.is_admin === true;
  } catch (_) {
    return false;
  }
}

function foodsJsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function handleSubmitPendingFood(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const cloudkitUserId = (body.cloudkit_user_id as string) ?? "";
  if (!cloudkitUserId) return foodsJsonResponse({ error: "cloudkit_user_id required" }, 400);
  if (await isBanned(supabase, cloudkitUserId)) {
    return foodsJsonResponse({ success: false, error: "service_unavailable" }, 503);
  }

  const name = ((body.name as string) ?? "").trim();
  const brand = ((body.brand as string) ?? "").trim() || null;
  const barcode = ((body.barcode as string) ?? "").trim() || null;
  if (!name) return foodsJsonResponse({ error: "name required" }, 400);

  // If the barcode already exists in foods or foods_pending, return the
  // existing record so the client can route to "vote on this" instead of
  // creating a duplicate.
  if (barcode) {
    const { data: existing } = await supabase
      .from("foods")
      .select("id, name, brand, data_source")
      .eq("barcode", barcode)
      .maybeSingle();
    if (existing) {
      return foodsJsonResponse({
        success: false,
        error: "already_in_catalog",
        existing_food: existing,
      }, 200);
    }
    const { data: existingPending } = await supabase
      .from("foods_pending")
      .select("id, name, brand, vote_count, status")
      .eq("barcode", barcode)
      .eq("status", "pending")
      .maybeSingle();
    if (existingPending) {
      return foodsJsonResponse({
        success: false,
        error: "already_pending",
        existing_pending: existingPending,
      }, 200);
    }
  }

  // Rate limit: at most N pending submissions per user per 24h
  const rateLimit = 10;
  const { count: recentCount } = await supabase
    .from("foods_pending")
    .select("*", { count: "exact", head: true })
    .eq("submitted_by", cloudkitUserId)
    .gt("created_at", new Date(Date.now() - 86400000).toISOString());
  if ((recentCount ?? 0) >= rateLimit) {
    return foodsJsonResponse({
      success: false,
      error: "rate_limit_exceeded",
      message: `You can submit at most ${rateLimit} foods per day.`,
    }, 429);
  }

  const insertRow: Record<string, unknown> = {
    name,
    brand,
    barcode,
    calories_per_100g:  (body.calories_per_100g as number) ?? 0,
    serving_size_g:     (body.serving_size_g as number) ?? 100,
    carbohydrates:      (body.carbohydrates as number) ?? 0,
    protein:            (body.protein as number) ?? 0,
    fat:                (body.fat as number) ?? 0,
    fiber:              (body.fiber as number) ?? 0,
    sugar:              (body.sugar as number) ?? 0,
    sodium_mg:          (body.sodium_mg as number) ?? 0,
    category:           (body.category as string) ?? "other",
    notes:              (body.notes as string) ?? null,
    submitted_by:       cloudkitUserId,
    submitted_by_display_name: (body.submitted_by_display_name as string) ?? null,
    source_type:        "barcode_miss",
    status:             "pending",
    vote_count:         0,
  };

  const { data, error } = await supabase
    .from("foods_pending")
    .insert(insertRow)
    .select("*")
    .single();
  if (error) {
    console.error("submit_pending_food error:", error);
    return foodsJsonResponse({ error: "insert_failed" }, 500);
  }
  return foodsJsonResponse({ success: true, pending: data });
}

async function handleGetPendingByBarcode(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const barcode = ((body.barcode as string) ?? "").trim();
  if (!barcode) return foodsJsonResponse({ error: "barcode required" }, 400);
  const { data, error } = await supabase
    .from("foods_pending")
    .select("*")
    .eq("barcode", barcode)
    .eq("status", "pending")
    .maybeSingle();
  if (error) return foodsJsonResponse({ error: "query_failed" }, 500);
  return foodsJsonResponse({ found: data !== null, pending: data });
}

async function handleVotePendingFood(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const cloudkitUserId = (body.cloudkit_user_id as string) ?? "";
  if (!cloudkitUserId) return foodsJsonResponse({ error: "cloudkit_user_id required" }, 400);
  if (await isBanned(supabase, cloudkitUserId)) {
    return foodsJsonResponse({ success: false, error: "service_unavailable" }, 503);
  }

  const pendingFoodId = (body.pending_food_id as string) ?? "";
  const voteType = ((body.vote_type as string) ?? "").toLowerCase();
  if (!pendingFoodId) return foodsJsonResponse({ error: "pending_food_id required" }, 400);
  if (voteType !== "confirm" && voteType !== "dispute") {
    return foodsJsonResponse({ error: "vote_type must be 'confirm' or 'dispute'" }, 400);
  }

  // Prevent self-voting. A submitter shouldn't boost their own submission.
  const { data: pending } = await supabase
    .from("foods_pending")
    .select("submitted_by, status")
    .eq("id", pendingFoodId)
    .maybeSingle();
  if (!pending) return foodsJsonResponse({ error: "not_found" }, 404);
  if (pending.status !== "pending") {
    return foodsJsonResponse({ error: "already_resolved", status: pending.status }, 400);
  }
  if (pending.submitted_by === cloudkitUserId) {
    return foodsJsonResponse({ error: "cannot_vote_on_own_submission" }, 403);
  }

  // Upsert the vote. Users can change their vote. The trigger recomputes
  // vote_count from scratch on every insert/update.
  const { error: voteErr } = await supabase
    .from("food_votes")
    .upsert({
      pending_food_id: pendingFoodId,
      cloudkit_user_id: cloudkitUserId,
      vote_type: voteType,
      notes: (body.notes as string) ?? null,
    }, { onConflict: "pending_food_id,cloudkit_user_id" });
  if (voteErr) {
    console.error("vote_pending_food upsert error:", voteErr);
    return foodsJsonResponse({ error: "vote_failed" }, 500);
  }

  // Return the (now recomputed) pending row so the client UI can
  // immediately reflect the new vote_count.
  const { data: updated } = await supabase
    .from("foods_pending")
    .select("*")
    .eq("id", pendingFoodId)
    .maybeSingle();
  return foodsJsonResponse({ success: true, pending: updated });
}

async function handleGetMyPendingSubmissions(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const cloudkitUserId = (body.cloudkit_user_id as string) ?? "";
  if (!cloudkitUserId) return foodsJsonResponse({ error: "cloudkit_user_id required" }, 400);
  const { data, error } = await supabase
    .from("foods_pending")
    .select("*")
    .eq("submitted_by", cloudkitUserId)
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) return foodsJsonResponse({ error: "query_failed" }, 500);
  return foodsJsonResponse({ submissions: data ?? [] });
}

// ── ADMIN: Direct food insert (bypasses community pipeline) ─────────────
async function handleAdminInsertFood(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const cloudkitUserId = (body.cloudkit_user_id as string) ?? "";
  if (!cloudkitUserId) return foodsJsonResponse({ error: "cloudkit_user_id required" }, 400);
  if (!(await isAdmin(supabase, cloudkitUserId))) {
    return foodsJsonResponse({ error: "admin_required" }, 403);
  }

  const name = ((body.name as string) ?? "").trim();
  if (!name) return foodsJsonResponse({ error: "name required" }, 400);

  const barcode = ((body.barcode as string) ?? "").trim() || null;
  const brand = ((body.brand as string) ?? "").trim() || null;

  // Check for barcode duplicate
  if (barcode) {
    const { data: existing } = await supabase
      .from("foods")
      .select("id")
      .eq("barcode", barcode)
      .limit(1)
      .maybeSingle();
    if (existing) {
      return foodsJsonResponse({ error: "barcode_exists", food_id: existing.id }, 400);
    }
  }

  const row: Record<string, unknown> = {
    name,
    brand,
    barcode,
    calories_per_100g: parseFloat(String(body.calories_per_100g ?? "0")) || null,
    serving_size_g: parseFloat(String(body.serving_size_g ?? "0")) || null,
    carbohydrates: parseFloat(String(body.carbohydrates ?? "0")) || null,
    protein: parseFloat(String(body.protein ?? "0")) || null,
    fat: parseFloat(String(body.fat ?? "0")) || null,
    fiber: parseFloat(String(body.fiber ?? "0")) || null,
    sugar: parseFloat(String(body.sugar ?? "0")) || null,
    sodium_mg: parseFloat(String(body.sodium_mg ?? "0")) || null,
    category: ((body.category as string) ?? "").trim() || null,
    data_source: "admin",
    is_verified: true,
  };

  const { data: food, error } = await supabase
    .from("foods")
    .insert(row)
    .select("*")
    .single();
  if (error) {
    console.error("admin_insert_food error:", error);
    return foodsJsonResponse({ error: "insert_failed", detail: error.message }, 500);
  }

  return foodsJsonResponse({ success: true, food });
}

// ── ADMIN: Edit an existing food entry ──────────────────────────────────
async function handleAdminEditFood(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const cloudkitUserId = (body.cloudkit_user_id as string) ?? "";
  if (!cloudkitUserId) return foodsJsonResponse({ error: "cloudkit_user_id required" }, 400);
  if (!(await isAdmin(supabase, cloudkitUserId))) {
    return foodsJsonResponse({ error: "admin_required" }, 403);
  }

  const foodId = (body.food_id as string) ?? "";
  if (!foodId) return foodsJsonResponse({ error: "food_id required" }, 400);

  // Whitelist editable fields
  const allowed = [
    "name", "brand", "barcode", "calories_per_100g", "serving_size_g",
    "carbohydrates", "protein", "fat", "fiber", "sugar", "sodium_mg",
    "category", "is_verified",
  ];
  const updates: Record<string, unknown> = {};
  for (const key of allowed) {
    if (body[key] !== undefined && body[key] !== null) {
      updates[key] = body[key];
    }
  }

  if (Object.keys(updates).length === 0) {
    return foodsJsonResponse({ error: "no_fields_to_update" }, 400);
  }

  const { data: food, error } = await supabase
    .from("foods")
    .update(updates)
    .eq("id", foodId)
    .select("*")
    .single();
  if (error) {
    console.error("admin_edit_food error:", error);
    return foodsJsonResponse({ error: "update_failed", detail: error.message }, 500);
  }

  return foodsJsonResponse({ success: true, food });
}
