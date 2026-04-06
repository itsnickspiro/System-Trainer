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

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("DB_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  try {
    const body = await req.json();
    const action: string = body.action ?? "";
    const cloudKitUserID: string = body.cloudkit_user_id ?? "";

    if (!cloudKitUserID) {
      return errorResponse(400, "Missing cloudkit_user_id");
    }

    switch (action) {
      case "get_store":
        return await handleGetStore(supabase, cloudKitUserID);
      case "purchase":
        return await handlePurchase(supabase, cloudKitUserID, body.item_key, body.pay_with);
      case "equip":
        return await handleEquip(supabase, cloudKitUserID, body.item_key, body.equip);
      default:
        return errorResponse(400, `Unknown action: ${action}`);
    }
  } catch (err) {
    console.error("store-proxy error:", err);
    return errorResponse(500, "Internal server error");
  }
});

// ── get_store ──────────────────────────────────────────────────────────────────
// JOINs items + item_store to build the store catalog the iOS client expects.

async function handleGetStore(supabase: any, cloudKitUserID: string) {
  // Fetch active store listings joined with item definitions
  const { data: listings, error: listErr } = await supabase
    .from("item_store")
    .select(`
      item_key,
      store_section,
      display_price_xp,
      display_price_credits,
      discount_pct,
      is_active,
      sort_order,
      starts_at,
      expires_at
    `)
    .eq("is_active", true);

  if (listErr) {
    console.error("item_store query error:", listErr);
    return errorResponse(500, "Failed to fetch store listings");
  }

  // Filter out expired or not-yet-started listings
  const now = new Date().toISOString();
  const activeListing = (listings ?? []).filter((l: any) => {
    if (l.starts_at && l.starts_at > now) return false;
    if (l.expires_at && l.expires_at < now) return false;
    return true;
  });

  // Build a set of item keys we need
  const itemKeys = activeListing.map((l: any) => l.item_key);
  if (itemKeys.length === 0) {
    return jsonResponse({
      store: [],
      inventory: [],
      currency: currencyInfo(),
      sale: { active: false, pct: 0 },
      player_credits: await getPlayerCredits(supabase, cloudKitUserID),
    });
  }

  // Fetch item definitions for listed items
  const { data: items, error: itemsErr } = await supabase
    .from("items")
    .select("*")
    .in("key", itemKeys)
    .eq("is_active", true);

  if (itemsErr) {
    console.error("items query error:", itemsErr);
    return errorResponse(500, "Failed to fetch items");
  }

  // Index items by key for fast lookup
  const itemMap = new Map<string, any>();
  for (const item of items ?? []) {
    itemMap.set(item.key, item);
  }

  // Check if any listing has a discount (for global sale banner)
  const maxDiscount = activeListing.reduce(
    (max: number, l: any) => Math.max(max, l.discount_pct ?? 0),
    0
  );

  // Map to the shape StoreService.swift expects
  const store = activeListing
    .map((listing: any) => {
      const item = itemMap.get(listing.item_key);
      if (!item) return null;

      const baseXP = listing.display_price_xp ?? item.xp_cost ?? 0;
      const baseCredits = listing.display_price_credits ?? item.credit_cost ?? 0;
      const discountPct = listing.discount_pct ?? 0;
      const finalXP = Math.max(0, Math.round(baseXP * (1 - discountPct / 100)));
      const finalCredits = Math.max(0, Math.round(baseCredits * (1 - discountPct / 100)));

      // Compute effective XP multiplier from either bonus_xp_multiplier or effect_type
      let xpMult: number | null = null;
      if (item.bonus_xp_multiplier > 1.0) {
        xpMult = item.bonus_xp_multiplier;
      } else if (item.effect_type === "xp_multiplier" && item.effect_value > 1) {
        xpMult = item.effect_value;
      }

      // For consumables with stat effects, populate bonus fields from effect_value
      let bStrength = nullIfZero(item.bonus_strength);
      let bEndurance = nullIfZero(item.bonus_endurance);
      let bEnergy: number | null = null;
      let bFocus = nullIfZero(item.bonus_focus);
      let bHealth = nullIfZero(item.bonus_vitality);

      if (item.item_type === "consumable" && item.effect_value > 0) {
        const ev = item.effect_value;
        if (item.effect_type === "all_stats_boost") {
          // Boost all stats equally
          bStrength  = (bStrength  ?? 0) + ev;
          bEndurance = (bEndurance ?? 0) + ev;
          bEnergy    = (bEnergy    ?? 0) + ev;
          bFocus     = (bFocus     ?? 0) + ev;
          bHealth    = (bHealth    ?? 0) + ev;
        } else if (item.effect_type === "stat_bonus") {
          // Generic stat bonus — apply to all stats
          bStrength  = (bStrength  ?? 0) + ev;
          bEndurance = (bEndurance ?? 0) + ev;
          bFocus     = (bFocus     ?? 0) + ev;
          bHealth    = (bHealth    ?? 0) + ev;
        } else if (item.effect_type === "recovery_boost") {
          // Recovery boosts energy and health
          bEnergy = (bEnergy ?? 0) + ev;
          bHealth = (bHealth ?? 0) + ev;
        }
      }

      return {
        key: item.key,
        name: item.name,
        description: item.description,
        icon_symbol: item.icon_symbol,
        item_type: item.item_type,
        rarity: item.rarity,
        price: baseXP,
        credit_price: baseCredits > 0 ? baseCredits : null,
        store_section: listing.store_section,
        is_enabled: true,
        final_price_xp: finalXP,
        final_price_credits: finalCredits,
        effective_discount_pct: discountPct,
        bonus_strength: nullIfZero(bStrength),
        bonus_endurance: nullIfZero(bEndurance),
        bonus_energy: nullIfZero(bEnergy),
        bonus_focus: nullIfZero(bFocus),
        bonus_health: nullIfZero(bHealth),
        xp_multiplier: xpMult,
      };
    })
    .filter(Boolean)
    .sort((a: any, b: any) => {
      // Sort by store listing sort_order
      const aOrder = activeListing.find((l: any) => l.item_key === a.key)?.sort_order ?? 0;
      const bOrder = activeListing.find((l: any) => l.item_key === b.key)?.sort_order ?? 0;
      return aOrder - bOrder;
    });

  // Fetch player inventory
  const { data: inv } = await supabase
    .from("player_inventory")
    .select("item_key, quantity, is_equipped, is_active")
    .eq("cloudkit_user_id", cloudKitUserID);

  const inventory = (inv ?? []).map((row: any) => ({
    key: row.item_key,
    quantity: row.quantity,
    is_equipped: row.is_equipped ?? false,
    is_active: row.is_active ?? false,
  }));

  const playerCredits = await getPlayerCredits(supabase, cloudKitUserID);

  return jsonResponse({
    store,
    inventory,
    currency: currencyInfo(),
    sale: maxDiscount > 0
      ? { active: true, pct: maxDiscount }
      : { active: false, pct: 0 },
    player_credits: playerCredits,
  });
}

// ── purchase ───────────────────────────────────────────────────────────────────

async function handlePurchase(
  supabase: any,
  cloudKitUserID: string,
  itemKey: string,
  payWith?: string
) {
  if (!itemKey) return errorResponse(400, "Missing item_key");

  // Fetch item definition
  const { data: item, error: itemErr } = await supabase
    .from("items")
    .select("*")
    .eq("key", itemKey)
    .eq("is_active", true)
    .single();

  if (itemErr || !item) return errorResponse(404, "Item not found or disabled");

  // Fetch store listing for pricing
  const { data: listing } = await supabase
    .from("item_store")
    .select("display_price_xp, display_price_credits, discount_pct, stock_remaining")
    .eq("item_key", itemKey)
    .eq("is_active", true)
    .maybeSingle();

  // Check stock
  if (listing?.stock_remaining !== null && listing?.stock_remaining <= 0) {
    return errorResponse(400, "Out of stock");
  }

  // Check if already owned (non-consumables can only be bought once)
  const { data: existing } = await supabase
    .from("player_inventory")
    .select("quantity")
    .eq("cloudkit_user_id", cloudKitUserID)
    .eq("item_key", itemKey)
    .maybeSingle();

  if (existing && item.item_type !== "consumable") {
    return errorResponse(400, "Already owned");
  }

  // Check max_per_player limit
  if (existing && item.max_per_player && existing.quantity >= item.max_per_player) {
    return errorResponse(400, "Maximum quantity reached");
  }

  // Calculate final price
  const discountPct = listing?.discount_pct ?? 0;
  const useCredits = payWith === "credits";

  if (useCredits) {
    const baseCredits = listing?.display_price_credits ?? item.credit_cost ?? 0;
    if (baseCredits <= 0) return errorResponse(400, "Item has no GP price");
    const finalCredits = Math.max(0, Math.round(baseCredits * (1 - discountPct / 100)));

    const { data: profile } = await supabase
      .from("player_profiles")
      .select("system_credits")
      .eq("cloudkit_user_id", cloudKitUserID)
      .single();

    const currentCredits = profile?.system_credits ?? 0;
    if (currentCredits < finalCredits) return errorResponse(400, "Insufficient GP");

    // Deduct credits
    const { error: deductErr } = await supabase
      .from("player_profiles")
      .update({ system_credits: currentCredits - finalCredits })
      .eq("cloudkit_user_id", cloudKitUserID);

    if (deductErr) return errorResponse(500, "Failed to deduct credits");
  }
  // XP deduction is handled client-side

  // Add to inventory (or increment quantity for consumables)
  if (existing) {
    const { error: updateErr } = await supabase
      .from("player_inventory")
      .update({ quantity: existing.quantity + 1 })
      .eq("cloudkit_user_id", cloudKitUserID)
      .eq("item_key", itemKey);

    if (updateErr) return errorResponse(500, "Failed to update inventory");
  } else {
    const { error: insertErr } = await supabase
      .from("player_inventory")
      .insert({
        cloudkit_user_id: cloudKitUserID,
        item_key: itemKey,
        quantity: 1,
        is_equipped: false,
        is_active: false,
      });

    if (insertErr) return errorResponse(500, "Failed to add to inventory");
  }

  // Decrement stock if limited
  if (listing?.stock_remaining !== null) {
    await supabase
      .from("item_store")
      .update({ stock_remaining: listing.stock_remaining - 1 })
      .eq("item_key", itemKey);
  }

  return jsonResponse({ success: true });
}

// ── equip ──────────────────────────────────────────────────────────────────────

async function handleEquip(
  supabase: any,
  cloudKitUserID: string,
  itemKey: string,
  equip: boolean
) {
  if (!itemKey) return errorResponse(400, "Missing item_key");

  const { data: item } = await supabase
    .from("items")
    .select("item_type")
    .eq("key", itemKey)
    .single();

  if (!item) return errorResponse(404, "Item not found");

  const updateFields: Record<string, any> =
    item.item_type === "consumable"
      ? { is_active: equip }
      : { is_equipped: equip };

  const { error } = await supabase
    .from("player_inventory")
    .update(updateFields)
    .eq("cloudkit_user_id", cloudKitUserID)
    .eq("item_key", itemKey);

  if (error) return errorResponse(500, "Failed to update equip state");

  return jsonResponse({ success: true });
}

// ── Helpers ────────────────────────────────────────────────────────────────────

async function getPlayerCredits(supabase: any, cloudKitUserID: string): Promise<number> {
  const { data } = await supabase
    .from("player_profiles")
    .select("system_credits")
    .eq("cloudkit_user_id", cloudKitUserID)
    .maybeSingle();
  return data?.system_credits ?? 0;
}

function nullIfZero(val: number | null | undefined): number | null {
  if (val === null || val === undefined || val === 0) return null;
  return val;
}

function currencyInfo() {
  return {
    name: "Gold Pieces",
    symbol: "GP",
    icon: "centsign.circle.fill",
  };
}

function jsonResponse(data: any) {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
