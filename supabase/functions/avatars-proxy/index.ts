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
    const action = body.action ?? "get_catalog";
    const cloudkitUserId = body.cloudkit_user_id ?? "";
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("DB_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    // GET FULL CATALOG with unlock status for player
    if (action === "get_catalog") {
      const { data: avatars, error } = await supabase
        .from("avatars")
        .select("*")
        .eq("is_active", true)
        .order("sort_order");
      if (error) throw error;

      // Get player's inventory to check owned avatars
      let ownedKeys: string[] = [];
      let playerLevel = 1;
      let unlockedAchievements: string[] = [];
      let currentAvatarKey = "avatar_default";

      if (cloudkitUserId) {
        const { data: inv } = await supabase.from("player_inventory").select("item_key").eq("cloudkit_user_id", cloudkitUserId);
        ownedKeys = (inv ?? []).map((i: Record<string, unknown>) => i.item_key as string);
        const { data: profile } = await supabase.from("player_profiles").select("level, avatar_key").eq("cloudkit_user_id", cloudkitUserId).single();
        playerLevel = profile?.level ?? 1;
        currentAvatarKey = profile?.avatar_key ?? "avatar_default";
      }

      const mapped = (avatars ?? []).map((a: Record<string, unknown>) => {
        let isUnlocked = false;
        if (a.unlock_type === "default" || a.unlock_type === "free") isUnlocked = true;
        else if (a.unlock_type === "level" && playerLevel >= (a.unlock_level as number ?? 999)) isUnlocked = true;
        else if (a.unlock_type === "item_purchase" && ownedKeys.includes(a.key as string)) isUnlocked = true;
        else if (a.unlock_type === "achievement" && unlockedAchievements.includes(a.unlock_achievement_key as string)) isUnlocked = true;

        return {
          key: a.key,
          name: a.name,
          description: a.description,
          category: a.category,
          rarity: a.rarity,
          unlockType: a.unlock_type,
          unlockLevel: a.unlock_level,
          unlockAchievementKey: a.unlock_achievement_key,
          unlockEventKey: a.unlock_event_key,
          gpPrice: a.gp_price,
          gpCost: a.gp_cost,
          accentColor: a.accent_color,
          imageUrl: a.image_url,
          sortOrder: a.sort_order,
          isUnlocked,
          isEquipped: a.key === currentAvatarKey,
        };
      });

      return new Response(JSON.stringify({ avatars: mapped, current_avatar_key: currentAvatarKey }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // SET AVATAR
    if (action === "set_avatar") {
      const avatarKey = body.avatar_key ?? "";
      if (!cloudkitUserId || !avatarKey) return new Response(JSON.stringify({ error: "Missing params" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      const { error } = await supabase.from("player_profiles").upsert({ cloudkit_user_id: cloudkitUserId, avatar_key: avatarKey, updated_at: new Date().toISOString() }, { onConflict: "cloudkit_user_id" });
      if (error) throw error;
      // Also update leaderboard display
      await supabase.from("leaderboard").update({ avatar_key: avatarKey }).eq("cloudkit_user_id", cloudkitUserId);
      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (err) {
    console.error("avatars-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
