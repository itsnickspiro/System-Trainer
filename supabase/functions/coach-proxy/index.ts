import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
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
    const body = await req.json().catch(() => ({}));
    const action = body.action ?? "get_history";
    const cloudkitUserId = body.cloudkit_user_id ?? "";
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    // SAVE MESSAGE
    if (action === "save_message") {
      const { error } = await supabase.from("coach_conversations").insert({
        cloudkit_user_id: cloudkitUserId,
        session_id: body.session_id ?? crypto.randomUUID(),
        role: body.role ?? "user",
        content: body.content ?? "",
        tokens_used: body.tokens_used ?? 0,
        fitness_context: body.fitness_context ?? {}
      });
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // GET HISTORY
    if (action === "get_history") {
      const limit = Math.min(parseInt(body.limit ?? "50", 10), 200);
      const { data, error } = await supabase.from("coach_conversations").select("role, content, created_at, session_id").eq("cloudkit_user_id", cloudkitUserId).order("created_at", { ascending: false }).limit(limit);
      if (error) throw error;
      return new Response(JSON.stringify({ messages: (data ?? []).reverse() }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // GET KNOWLEDGE BASE
    if (action === "get_knowledge") {
      const category = body.category ?? null;
      let query = supabase.from("coach_knowledge").select("category, question, answer, tags").eq("is_active", true).order("sort_order");
      if (category) query = query.eq("category", category);
      const { data, error } = await query;
      if (error) throw error;
      return new Response(JSON.stringify({ knowledge: data ?? [] }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // CLEAR HISTORY
    if (action === "clear_history") {
      const { error } = await supabase.from("coach_conversations").delete().eq("cloudkit_user_id", cloudkitUserId);
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (err) {
    console.error("coach-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
