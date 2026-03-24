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

    // Optional filters
    const gender:  string = (body.gender   ?? "").trim();
    const planKey: string = (body.plan_key ?? body.planKey ?? "").trim();

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = Deno.env.get("DB_SERVICE_ROLE_KEY")!;
    const supabase    = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });

    const { data, error } = await supabase.rpc("fetch_anime_plans", {
      p_gender:   gender,
      p_plan_key: planKey,
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

    // Map DB rows → shape AnimeWorkoutPlanService expects.
    // weekly_schedule is returned as parsed JSON (JSONB column).
    const plans = (data ?? []).map((row: Record<string, unknown>) => ({
      id:             row.id,
      planKey:        row.plan_key,
      characterName:  row.character_name,
      anime:          row.anime,
      tagline:        row.tagline,
      description:    row.description,
      difficulty:     row.difficulty,
      accentColor:    row.accent_color,
      iconSymbol:     row.icon_symbol,
      targetGender:   row.target_gender ?? null,
      weeklySchedule: row.weekly_schedule,   // already parsed JSONB
      dailyCalories:  row.daily_calories,
      proteinGrams:   row.protein_grams,
      carbGrams:      row.carb_grams,
      fatGrams:       row.fat_grams,
      waterGlasses:   row.water_glasses,
      mealPrepTips:   row.meal_prep_tips  ?? [],
      avoidList:      row.avoid_list      ?? [],
      sortOrder:      row.sort_order,
    }));

    return new Response(JSON.stringify(plans), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("anime-plans-proxy error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
