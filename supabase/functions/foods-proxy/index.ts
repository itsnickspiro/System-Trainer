import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-app-secret",
};

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

    // Input parameters
    const query: string   = (body.query    ?? body.name ?? "").trim();
    const barcode: string = (body.barcode  ?? "").trim();
    const category: string = (body.category ?? "").trim();
    const limit: number   = Math.min(parseInt(body.limit  ?? "30", 10), 100);
    const offset: number  = Math.max(parseInt(body.offset ?? "0",  10), 0);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = Deno.env.get("DB_SERVICE_ROLE_KEY")!;
    const supabase    = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });

    // Call the search_foods RPC defined in the migration
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

    // Map DB rows to the shape FoodDatabaseService expects.
    // Field names match the FoodItem @Model init parameters.
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
      // Extended micros (optional)
      potassiumMg:      row.potassium_mg     ?? null,
      calciumMg:        row.calcium_mg       ?? null,
      ironMg:           row.iron_mg          ?? null,
      vitaminCMg:       row.vitamin_c_mg     ?? null,
      vitaminDMcg:      row.vitamin_d_mcg    ?? null,
      vitaminAMcg:      row.vitamin_a_mcg    ?? null,
      saturatedFat:     row.saturated_fat    ?? null,
      cholesterolMg:    row.cholesterol_mg   ?? null,
      // Classification
      category:         row.category         ?? null,
      isVerified:       row.is_verified      ?? false,
      dataSource:       row.data_source      ?? "rpt",
    }));

    return new Response(JSON.stringify(foods), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
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
