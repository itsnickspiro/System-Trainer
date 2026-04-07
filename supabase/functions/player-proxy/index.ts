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
    const body = await req.json();
    const action = body.action ?? "get_profile";
    const cloudkitUserId = body.cloudkit_user_id ?? "";
    if (!cloudkitUserId) return new Response(JSON.stringify({ error: "cloudkit_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    // GET PROFILE
    if (action === "get_profile") {
      const { data, error } = await supabase.from("player_profiles").select("*").eq("cloudkit_user_id", cloudkitUserId).single();
      if (error && error.code !== "PGRST116") throw error;
      const { data: override } = await supabase.from("player_overrides").select("*").eq("cloudkit_user_id", cloudkitUserId).eq("is_active", true).single();
      return new Response(JSON.stringify({ profile: data ?? null, override: override ?? null }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // UPSERT PROFILE
    if (action === "upsert_profile") {
      const profile = body.profile ?? {};
      const { data, error } = await supabase.from("player_profiles").upsert({ ...profile, cloudkit_user_id: cloudkitUserId, updated_at: new Date().toISOString() }, { onConflict: "cloudkit_user_id" }).select().single();
      if (error) throw error;
      return new Response(JSON.stringify({ profile: data }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // SAVE BACKUP
    if (action === "save_backup") {
      const backup = body.backup ?? {};
      const { error } = await supabase.from("player_backups").insert({ ...backup, cloudkit_user_id: cloudkitUserId });
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // MARK OVERRIDE APPLIED
    if (action === "mark_override_applied") {
      const { error } = await supabase.from("player_overrides").update({ is_active: false, applied_at: new Date().toISOString() }).eq("cloudkit_user_id", cloudkitUserId);
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // ADD CREDITS — atomic credit transaction
    if (action === "add_credits") {
      const amount: number = body.amount ?? 0;
      const txType: string = body.transaction_type ?? "quest_reward";
      const refKey: string = body.reference_key ?? "";
      const notes: string = body.notes ?? "";

      if (amount === 0) return new Response(JSON.stringify({ success: true, credits: 0 }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });

      // Get current balance
      const { data: profile, error: pErr } = await supabase.from("player_profiles").select("system_credits, lifetime_credits_earned").eq("cloudkit_user_id", cloudkitUserId).single();
      if (pErr) throw pErr;

      const currentBalance = profile?.system_credits ?? 0;
      const lifetimeEarned = profile?.lifetime_credits_earned ?? 0;
      const newBalance = Math.max(0, currentBalance + amount);
      const newLifetime = amount > 0 ? lifetimeEarned + amount : lifetimeEarned;

      // Update balance
      const { error: uErr } = await supabase.from("player_profiles").update({ system_credits: newBalance, lifetime_credits_earned: newLifetime, updated_at: new Date().toISOString() }).eq("cloudkit_user_id", cloudkitUserId);
      if (uErr) throw uErr;

      // Log transaction
      await supabase.from("credit_transactions").insert({ cloudkit_user_id: cloudkitUserId, amount, balance_after: newBalance, transaction_type: txType, reference_key: refKey, notes });

      return new Response(JSON.stringify({ success: true, new_balance: newBalance }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // GET CREDIT HISTORY
    if (action === "get_credit_history") {
      const limit = Math.min(parseInt(body.limit ?? "20", 10), 50);
      const { data, error } = await supabase.from("credit_transactions").select("*").eq("cloudkit_user_id", cloudkitUserId).order("created_at", { ascending: false }).limit(limit);
      if (error) throw error;
      return new Response(JSON.stringify({ transactions: data ?? [] }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (err) {
    console.error("player-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
