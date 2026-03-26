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
          "template_key, arc_key, title, details, quest_type, stat_target, " +
          "xp_base, min_level, max_level, condition, is_enabled"
        )
        .eq("is_enabled", true)
        .order("min_level", { ascending: true }),

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

    // Map snake_case DB columns → camelCase to match Swift Codable structs
    const templates = (templatesResult.data ?? []).map((row: Record<string, unknown>) => ({
      templateKey: row.template_key,
      arcKey:      row.arc_key      ?? null,
      title:       row.title,
      details:     row.details,
      questType:   row.quest_type,
      statTarget:  row.stat_target  ?? null,
      xpBase:      row.xp_base,
      minLevel:    row.min_level,
      maxLevel:    row.max_level    ?? null,
      condition:   row.condition    ?? null,
      isEnabled:   row.is_enabled,
    }));

    const arcs = (arcsResult.data ?? []).map((row: Record<string, unknown>) => ({
      arcKey:      row.arc_key,
      displayName: row.display_name,
      description: row.description,
      iconSymbol:  row.icon_symbol,
      accentColor: row.accent_color,
      sortOrder:   row.sort_order,
      isEnabled:   row.is_enabled,
    }));

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
