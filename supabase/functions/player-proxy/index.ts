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

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    // LOOKUP BY APPLE ID — does NOT require cloudkit_user_id
    if (action === "lookup_by_apple_id") {
      const appleUserId: string = body.apple_user_id ?? "";
      if (!appleUserId) {
        return new Response(JSON.stringify({ error: "apple_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      const { data, error } = await supabase.from("player_profiles").select("*").eq("apple_user_id", appleUserId).limit(1).maybeSingle();
      if (error && error.code !== "PGRST116") throw error;
      if (data) {
        return new Response(JSON.stringify({ found: true, profile: data }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({ found: false }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // All other actions require cloudkit_user_id
    if (!cloudkitUserId) return new Response(JSON.stringify({ error: "cloudkit_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

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

    // LINK APPLE ID — associate an Apple user id with the calling cloudkit user
    if (action === "link_apple_id") {
      const appleUserId: string = body.apple_user_id ?? "";
      const displayName: string | null = body.display_name ?? null;
      const email: string | null = body.email ?? null;
      if (!appleUserId) {
        return new Response(JSON.stringify({ error: "apple_user_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      // Case A: Does another row already own this apple_user_id?
      const { data: existingByApple, error: lookupErr } = await supabase.from("player_profiles").select("*").eq("apple_user_id", appleUserId).limit(1).maybeSingle();
      if (lookupErr && lookupErr.code !== "PGRST116") throw lookupErr;

      if (existingByApple && existingByApple.cloudkit_user_id !== cloudkitUserId) {
        // Cross-device sign-in: return existing profile without overwriting.
        return new Response(JSON.stringify({
          success: true,
          linked: false,
          profile: existingByApple,
          message: "Apple ID is already linked to another device's profile. Returning existing profile data.",
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      // Does a row exist for the calling cloudkit_user_id?
      const { data: existingByCk, error: ckErr } = await supabase.from("player_profiles").select("*").eq("cloudkit_user_id", cloudkitUserId).maybeSingle();
      if (ckErr && ckErr.code !== "PGRST116") throw ckErr;

      if (existingByCk) {
        // Case B: update existing row with apple_user_id
        const { data: updated, error: upErr } = await supabase.from("player_profiles").update({
          apple_user_id: appleUserId,
          apple_user_id_linked_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq("cloudkit_user_id", cloudkitUserId).select().single();
        if (upErr) throw upErr;

        // Mirror onto leaderboard row if present
        await supabase.from("leaderboard").update({ apple_user_id: appleUserId }).eq("cloudkit_user_id", cloudkitUserId);

        return new Response(JSON.stringify({ success: true, linked: true, profile: updated }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }

      // Case C: no row for this cloudkit_user_id — create one
      const insertRow: Record<string, unknown> = {
        cloudkit_user_id: cloudkitUserId,
        apple_user_id: appleUserId,
        apple_user_id_linked_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
      if (displayName) insertRow.display_name = displayName;
      if (email) insertRow.email = email;

      const { data: created, error: insErr } = await supabase.from("player_profiles").insert(insertRow).select().single();
      if (insErr) throw insErr;

      return new Response(JSON.stringify({ success: true, linked: true, created: true, profile: created }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (err) {
    console.error("player-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
