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
