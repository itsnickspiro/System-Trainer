import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-app-secret",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  if (!appSecret || !incomingSecret || incomingSecret !== appSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }

  try {
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    const { data, error } = await supabase.from("achievements").select("*").eq("is_active", true).order("sort_order", { ascending: true });
    if (error) throw error;

    const mapped = (data ?? []).map((row: Record<string, unknown>) => ({
      id: row.id,
      key: row.key,
      title: row.title,
      description: row.description,
      iconSymbol: row.icon_symbol,
      accentColor: row.accent_color,
      category: row.category,
      conditionType: row.condition_type,
      conditionValue: row.condition_value,
      xpReward: row.xp_reward,
      isSecret: row.is_secret,
      sortOrder: row.sort_order,
    }));

    return new Response(JSON.stringify({ achievements: mapped }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (err) {
    console.error("achievements-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
