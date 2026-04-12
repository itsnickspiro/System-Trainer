import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
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
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = Deno.env.get("DB_SERVICE_ROLE_KEY")!;
    const supabase    = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });

    // Fetch templates and arcs concurrently
    const [templatesResult, arcsResult] = await Promise.all([
      supabase
        .from("quest_templates")
        .select(
          "key, requires_arc, title, subtitle, quest_type, category, " +
          "condition_type, condition_target, xp_reward, credit_reward, " +
          "difficulty, sort_order, is_active"
        )
        .eq("is_active", true)
        .order("sort_order", { ascending: true }),

      supabase
        .from("quest_arcs")
        .select(
          "arc_key, display_name, description, icon_symbol, accent_color, sort_order, is_enabled"
        )
        .eq("is_enabled", true)
        .order("sort_order", { ascending: true }),
    ]);

    if (templatesResult.error) {
      console.error("quest_templates query error:", templatesResult.error);
      return new Response(
        JSON.stringify({ error: "Database query failed", detail: templatesResult.error.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    if (arcsResult.error) {
      console.error("quest_arcs query error:", arcsResult.error);
      return new Response(
        JSON.stringify({ error: "Database query failed", detail: arcsResult.error.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Map DB condition_type → client completionCondition format
    const conditionTypeMap: Record<string, string> = {
      steps: "steps",
      calories_burned: "calories",
      workout_logged: "workout",
      food_logged: "meals",
      water_logged: "water",
      sleep_hours: "sleep",
      streak_days: "streak",
      weight_logged: "weight",
      coach_interaction: "coach",
      manual: "manual",
      custom: "custom",
    };

    // Map snake_case DB columns → camelCase to match Swift Codable structs
    const templates = (templatesResult.data ?? []).map((row: Record<string, unknown>) => {
      // Build completionCondition from condition_type + condition_target
      const dbType = (row.condition_type as string) ?? "";
      const clientType = conditionTypeMap[dbType] ?? dbType;
      const target = row.condition_target as string | null;
      const condition = clientType && target ? `${clientType}:${target}` : (clientType || null);

      return {
        key:           row.key,
        arcKey:        row.requires_arc ?? null,
        title:         row.title,
        subtitle:      row.subtitle     ?? null,
        questType:     row.quest_type,
        category:      row.category     ?? null,
        condition,
        conditionType: row.condition_type,
        conditionTarget: row.condition_target,
        xpReward:      row.xp_reward,
        creditReward:  row.credit_reward ?? 0,
        difficulty:    row.difficulty    ?? "normal",
        sortOrder:     row.sort_order   ?? 0,
        isEnabled:     row.is_active,
      };
    });

    const arcs = (arcsResult.data ?? []).map((row: Record<string, unknown>) => ({
      arcKey:      row.arc_key,
      displayName: row.display_name,
      description: row.description,
      iconSymbol:  row.icon_symbol,
      accentColor: row.accent_color,
      sortOrder:   row.sort_order,
      isEnabled:   row.is_enabled,
    }));

    // Default: return templates + arcs (backwards compatible)
    const body = await req.json().catch(() => ({}));
    const action = body?.action ?? "";

    if (action === "admin_create_quest_template") {
      const cloudkitUserId = body.cloudkit_user_id ?? "";
      const { data: me } = await supabase.from("player_profiles").select("is_admin").eq("cloudkit_user_id", cloudkitUserId).maybeSingle();
      if (!me?.is_admin) return new Response(JSON.stringify({ error: "admin_required" }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } });

      const key = (body.key ?? "").toString();
      const title = (body.title ?? "").toString();
      if (!key || !title) return new Response(JSON.stringify({ error: "key and title required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

      const { data: quest, error: insErr } = await supabase.from("quest_templates").insert({
        key,
        title,
        subtitle: body.subtitle ?? null,
        quest_type: body.quest_type ?? "daily",
        category: body.category ?? null,
        condition_type: body.condition_type ?? "manual",
        condition_target: body.condition_target ?? null,
        xp_reward: parseInt(body.xp_reward ?? "50", 10) || 50,
        credit_reward: parseInt(body.credit_reward ?? "0", 10) || 0,
        difficulty: body.difficulty ?? "normal",
        sort_order: parseInt(body.sort_order ?? "100", 10) || 100,
        is_active: true,
        requires_arc: body.requires_arc ?? null,
      }).select("*").single();
      if (insErr) {
        console.error("admin_create_quest_template error:", insErr);
        return new Response(JSON.stringify({ error: insErr.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({ success: true, quest }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ templates, arcs }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("quest-templates-proxy error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
