import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// CORS headers — match the leaderboard-proxy pattern so the iOS client
// can call this function with the same headers it already sends.
const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-app-secret",
};

// Per-archetype single-player HP. Guild raid HP scales by member_count.
const BOSS_HP: Record<string, number> = {
  sloth_demon: 50000,
  glutton_king: 40,
  hollow_warrior: 180,
  iron_sleeper: 50,
  withering_spirit: 60,
  forsaken_dragon: 3000,
};

const BOSS_ROTATION = [
  "sloth_demon",
  "glutton_king",
  "hollow_warrior",
  "iron_sleeper",
  "withering_spirit",
  "forsaken_dragon",
];

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
type SB = any;

// Compute current week's Monday as YYYY-MM-DD (ISO week, Monday start).
// Matches date_trunc('week', current_date) in Postgres.
function currentWeekMonday(): string {
  const now = new Date();
  const day = now.getUTCDay(); // 0=Sun..6=Sat
  const diff = (day === 0 ? -6 : 1 - day);
  const monday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + diff));
  return monday.toISOString().slice(0, 10);
}

// ISO week number for boss rotation. Matches Postgres extract(week from current_date).
function isoWeekNumber(d: Date): number {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  return Math.ceil((((date.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
}

function bossKeyForCurrentWeek(): string {
  const week = isoWeekNumber(new Date());
  // (week + 3) % 6 — guilds run on a different rotation than personal raids.
  const idx = (week + 3) % 6;
  return BOSS_ROTATION[idx];
}

// Look up the active raid for a guild for the current week, spawning one
// if it doesn't yet exist. Guild raid HP = member_count × per-player HP.
async function getOrCreateRaid(supabase: SB, guild: SB): Promise<SB> {
  const weekStart = currentWeekMonday();
  const { data: existing } = await supabase
    .from("guild_raids")
    .select("*")
    .eq("guild_id", guild.id)
    .eq("week_start_date", weekStart)
    .maybeSingle();
  if (existing) return existing;

  const bossKey = bossKeyForCurrentWeek();
  const perPlayerHP = BOSS_HP[bossKey] ?? 100;
  const memberCount = Math.max(1, guild.member_count ?? 1);
  const maxHP = perPlayerHP * memberCount;

  const { data: created, error } = await supabase
    .from("guild_raids")
    .insert({
      guild_id: guild.id,
      week_start_date: weekStart,
      boss_key: bossKey,
      max_hp: maxHP,
      current_hp: maxHP,
      damage_dealt: 0,
    })
    .select("*")
    .single();
  if (error) throw error;
  return created;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // Validate shared secret. Mirrors leaderboard-proxy: env var is RPT_APP_SECRET.
  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  if (!appSecret || !incomingSecret || incomingSecret !== appSecret) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const action = body.action ?? "";

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("DB_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // ----- CREATE GUILD -----
    if (action === "create_guild") {
      const rawName = (body.name ?? "").toString();
      const name = rawName;
      const description = (body.description ?? "").toString();
      const isPublic = body.is_public !== false;
      const ownerId = (body.owner_cloudkit_user_id ?? "").toString();
      const ownerName = (body.owner_display_name ?? "").toString();

      if (!ownerId || !ownerName) return jsonResponse({ error: "Missing owner identity." }, 400);
      if (name.length < 3 || name.length > 30 || name.trim() !== name) {
        return jsonResponse({ error: "Guild name must be 3-30 characters." }, 400);
      }

      // Already in a guild?
      const { data: existingMember } = await supabase
        .from("guild_members")
        .select("guild_id")
        .eq("cloudkit_user_id", ownerId)
        .maybeSingle();
      if (existingMember) {
        return jsonResponse({ error: "You're already in a guild. Leave it first." }, 400);
      }

      // Name taken?
      const { data: nameDupe } = await supabase
        .from("guilds")
        .select("id")
        .eq("name", name)
        .maybeSingle();
      if (nameDupe) return jsonResponse({ error: "Guild name already exists." }, 400);

      const { data: guild, error: insertErr } = await supabase
        .from("guilds")
        .insert({
          name,
          description,
          owner_cloudkit_user_id: ownerId,
          is_public: isPublic,
          member_count: 1,
        })
        .select("*")
        .single();
      if (insertErr) {
        if ((insertErr.message ?? "").includes("duplicate")) {
          return jsonResponse({ error: "Guild name already exists." }, 400);
        }
        throw insertErr;
      }

      const { error: memberErr } = await supabase
        .from("guild_members")
        .insert({
          guild_id: guild.id,
          cloudkit_user_id: ownerId,
          display_name: ownerName,
          role: "owner",
        });
      if (memberErr) throw memberErr;

      return jsonResponse({ success: true, guild, message: "Guild created" });
    }

    // ----- JOIN GUILD -----
    if (action === "join_guild") {
      const guildId = (body.guild_id ?? "").toString();
      const userId = (body.cloudkit_user_id ?? "").toString();
      const displayName = (body.display_name ?? "").toString();
      if (!guildId || !userId || !displayName) return jsonResponse({ error: "Missing params" }, 400);

      const { data: existingMember } = await supabase
        .from("guild_members")
        .select("guild_id")
        .eq("cloudkit_user_id", userId)
        .maybeSingle();
      if (existingMember) {
        return jsonResponse({ error: "You're already in a guild. Leave it first." }, 400);
      }

      const { data: guild, error: gErr } = await supabase
        .from("guilds")
        .select("*")
        .eq("id", guildId)
        .maybeSingle();
      if (gErr) throw gErr;
      if (!guild || guild.is_disbanded) return jsonResponse({ error: "Guild not found." }, 404);
      if (guild.member_count >= guild.max_members) return jsonResponse({ error: "Guild is full." }, 400);

      const { error: insErr } = await supabase
        .from("guild_members")
        .insert({
          guild_id: guildId,
          cloudkit_user_id: userId,
          display_name: displayName,
          role: "member",
        });
      if (insErr) throw insErr;

      const { data: updated, error: upErr } = await supabase
        .from("guilds")
        .update({
          member_count: guild.member_count + 1,
          updated_at: new Date().toISOString(),
        })
        .eq("id", guildId)
        .select("*")
        .single();
      if (upErr) throw upErr;

      return jsonResponse({ success: true, guild: updated });
    }

    // ----- LEAVE GUILD -----
    if (action === "leave_guild") {
      const userId = (body.cloudkit_user_id ?? "").toString();
      if (!userId) return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      const { data: membership } = await supabase
        .from("guild_members")
        .select("*")
        .eq("cloudkit_user_id", userId)
        .maybeSingle();
      if (!membership) return jsonResponse({ success: true });

      const guildId = membership.guild_id;
      const { data: guild } = await supabase
        .from("guilds")
        .select("*")
        .eq("id", guildId)
        .maybeSingle();

      // Remove the user
      const { error: delErr } = await supabase
        .from("guild_members")
        .delete()
        .eq("guild_id", guildId)
        .eq("cloudkit_user_id", userId);
      if (delErr) throw delErr;

      const remainingCount = Math.max(0, (guild?.member_count ?? 1) - 1);

      if (remainingCount <= 0) {
        // Last member out — disband
        await supabase
          .from("guilds")
          .update({
            member_count: 0,
            is_disbanded: true,
            updated_at: new Date().toISOString(),
          })
          .eq("id", guildId);
        return jsonResponse({ success: true });
      }

      // Transfer ownership if the leaving user was the owner
      const updates: Record<string, unknown> = {
        member_count: remainingCount,
        updated_at: new Date().toISOString(),
      };

      if (membership.role === "owner") {
        const { data: heir } = await supabase
          .from("guild_members")
          .select("*")
          .eq("guild_id", guildId)
          .order("joined_at", { ascending: true })
          .limit(1)
          .maybeSingle();
        if (heir) {
          await supabase
            .from("guild_members")
            .update({ role: "owner" })
            .eq("guild_id", guildId)
            .eq("cloudkit_user_id", heir.cloudkit_user_id);
          updates.owner_cloudkit_user_id = heir.cloudkit_user_id;
        }
      }

      await supabase.from("guilds").update(updates).eq("id", guildId);
      return jsonResponse({ success: true });
    }

    // ----- TRANSFER LEADERSHIP -----
    if (action === "transfer_leadership") {
      const callerId = (body.cloudkit_user_id ?? "").toString();
      const newLeaderId = (body.new_leader_cloudkit_user_id ?? "").toString();
      if (!callerId || !newLeaderId) return jsonResponse({ error: "Missing params" }, 400);

      // Look up caller's membership
      const { data: callerMembership } = await supabase
        .from("guild_members")
        .select("*")
        .eq("cloudkit_user_id", callerId)
        .maybeSingle();
      if (!callerMembership) return jsonResponse({ error: "You're not in a guild." }, 400);
      if (callerMembership.role !== "owner") {
        return jsonResponse({ error: "Only the guild owner can transfer leadership" }, 403);
      }

      const guildId = callerMembership.guild_id;

      // Verify target is a member of the same guild
      const { data: targetMembership } = await supabase
        .from("guild_members")
        .select("*")
        .eq("guild_id", guildId)
        .eq("cloudkit_user_id", newLeaderId)
        .maybeSingle();
      if (!targetMembership) {
        return jsonResponse({ error: "Target player is not a member of this guild" }, 400);
      }
      if (targetMembership.role === "owner") {
        return jsonResponse({ error: "That player is already the owner" }, 400);
      }

      // Promote new leader to owner
      const { error: promoteErr } = await supabase
        .from("guild_members")
        .update({ role: "owner" })
        .eq("guild_id", guildId)
        .eq("cloudkit_user_id", newLeaderId);
      if (promoteErr) throw promoteErr;

      // Demote old leader to member
      const { error: demoteErr } = await supabase
        .from("guild_members")
        .update({ role: "member" })
        .eq("guild_id", guildId)
        .eq("cloudkit_user_id", callerId);
      if (demoteErr) throw demoteErr;

      // Update guild's owner reference
      await supabase
        .from("guilds")
        .update({
          owner_cloudkit_user_id: newLeaderId,
          updated_at: new Date().toISOString(),
        })
        .eq("id", guildId);

      return jsonResponse({ success: true, new_owner: newLeaderId });
    }

    // ----- GET MY GUILD -----
    if (action === "get_my_guild") {
      const userId = (body.cloudkit_user_id ?? "").toString();
      if (!userId) return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      const { data: membership } = await supabase
        .from("guild_members")
        .select("*")
        .eq("cloudkit_user_id", userId)
        .maybeSingle();
      if (!membership) return jsonResponse({ guild: null });

      const { data: guild } = await supabase
        .from("guilds")
        .select("*")
        .eq("id", membership.guild_id)
        .maybeSingle();
      if (!guild || guild.is_disbanded) return jsonResponse({ guild: null });

      const { data: members } = await supabase
        .from("guild_members")
        .select("*")
        .eq("guild_id", guild.id)
        .order("joined_at", { ascending: true });

      const raid = await getOrCreateRaid(supabase, guild);

      const { data: contributions } = await supabase
        .from("guild_raid_contributions")
        .select("*")
        .eq("raid_id", raid.id)
        .order("damage_contributed", { ascending: false });

      return jsonResponse({
        guild,
        role: membership.role,
        members: members ?? [],
        raid,
        contributions: contributions ?? [],
      });
    }

    // ----- LIST PUBLIC GUILDS -----
    if (action === "list_public_guilds") {
      const page = Math.max(parseInt(body.page ?? "1", 10), 1);
      const pageSize = Math.min(Math.max(parseInt(body.page_size ?? "50", 10), 1), 100);
      const offset = (page - 1) * pageSize;

      const { data, error, count } = await supabase
        .from("guilds")
        .select("*", { count: "exact" })
        .eq("is_public", true)
        .eq("is_disbanded", false)
        .order("member_count", { ascending: false })
        .order("level", { ascending: false })
        .range(offset, offset + pageSize - 1);
      if (error) throw error;
      return jsonResponse({ guilds: data ?? [], total: count ?? 0 });
    }

    // ----- SET FOCUS -----
    if (action === "set_focus") {
      const guildId = (body.guild_id ?? "").toString();
      const requesterId = (body.requested_by_cloudkit_user_id ?? "").toString();
      const focus = (body.focus ?? "").toString();
      if (!guildId || !requesterId) return jsonResponse({ error: "Missing params" }, 400);

      const { data: membership } = await supabase
        .from("guild_members")
        .select("role")
        .eq("guild_id", guildId)
        .eq("cloudkit_user_id", requesterId)
        .maybeSingle();
      if (!membership || (membership.role !== "owner" && membership.role !== "officer")) {
        return jsonResponse({ error: "Only owners or officers can set the focus." }, 403);
      }

      const { data: updated, error } = await supabase
        .from("guilds")
        .update({ weekly_focus: focus, updated_at: new Date().toISOString() })
        .eq("id", guildId)
        .select("*")
        .single();
      if (error) throw error;
      return jsonResponse({ success: true, guild: updated });
    }

    // ----- CONTRIBUTE TO RAID -----
    if (action === "contribute_to_raid") {
      const userId = (body.cloudkit_user_id ?? "").toString();
      const damage = Math.max(0, parseInt(body.damage ?? "0", 10) || 0);
      const displayName = (body.display_name ?? "").toString();
      if (!userId) return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);
      if (damage <= 0) return jsonResponse({ error: "Damage must be > 0" }, 400);

      const { data: membership } = await supabase
        .from("guild_members")
        .select("*")
        .eq("cloudkit_user_id", userId)
        .maybeSingle();
      if (!membership) return jsonResponse({ error: "You're not in a guild." }, 400);

      const { data: guild } = await supabase
        .from("guilds")
        .select("*")
        .eq("id", membership.guild_id)
        .maybeSingle();
      if (!guild || guild.is_disbanded) return jsonResponse({ error: "Guild not found." }, 404);

      const raid = await getOrCreateRaid(supabase, guild);

      // Upsert contribution row (raid_id, cloudkit_user_id)
      const { data: existingContrib } = await supabase
        .from("guild_raid_contributions")
        .select("*")
        .eq("raid_id", raid.id)
        .eq("cloudkit_user_id", userId)
        .maybeSingle();

      if (existingContrib) {
        await supabase
          .from("guild_raid_contributions")
          .update({
            damage_contributed: (existingContrib.damage_contributed ?? 0) + damage,
            last_contribution_at: new Date().toISOString(),
            display_name: displayName || existingContrib.display_name,
          })
          .eq("raid_id", raid.id)
          .eq("cloudkit_user_id", userId);
      } else {
        await supabase
          .from("guild_raid_contributions")
          .insert({
            raid_id: raid.id,
            cloudkit_user_id: userId,
            display_name: displayName || membership.display_name,
            damage_contributed: damage,
            last_contribution_at: new Date().toISOString(),
          });
      }

      // Update raid HP
      const newDamageDealt = (raid.damage_dealt ?? 0) + damage;
      const newCurrentHP = Math.max(0, (raid.max_hp ?? 0) - newDamageDealt);
      const wasDefeated = newCurrentHP === 0 && !raid.defeated_at;
      const raidUpdates: Record<string, unknown> = {
        damage_dealt: newDamageDealt,
        current_hp: newCurrentHP,
      };
      if (wasDefeated) raidUpdates.defeated_at = new Date().toISOString();

      const { data: updatedRaid, error: rErr } = await supabase
        .from("guild_raids")
        .update(raidUpdates)
        .eq("id", raid.id)
        .select("*")
        .single();
      if (rErr) throw rErr;

      // Update lifetime contribution on the member ledger
      await supabase
        .from("guild_members")
        .update({
          contribution_xp: (membership.contribution_xp ?? 0) + damage,
        })
        .eq("guild_id", guild.id)
        .eq("cloudkit_user_id", userId);

      // Guild XP + leveling — each point of raid damage earns 1 guild XP.
      // Level thresholds: level N requires N×500 total XP.
      const newGuildXP = (guild.total_xp ?? 0) + damage;
      const newGuildLevel = Math.max(1, Math.floor(newGuildXP / 500) + 1);
      await supabase.from("guilds").update({
        total_xp: newGuildXP,
        level: newGuildLevel,
        updated_at: new Date().toISOString(),
      }).eq("id", guild.id);

      return jsonResponse({ success: true, raid: updatedRaid, defeated: wasDefeated, guild_xp: newGuildXP, guild_level: newGuildLevel });
    }

    // ----- CLAIM RAID REWARD -----
    if (action === "claim_raid_reward") {
      const userId = (body.cloudkit_user_id ?? "").toString();
      if (!userId) return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      const { data: membership } = await supabase
        .from("guild_members")
        .select("*")
        .eq("cloudkit_user_id", userId)
        .maybeSingle();
      if (!membership) return jsonResponse({ error: "You're not in a guild." }, 400);

      // Most recent defeated raid for this guild
      const { data: raid } = await supabase
        .from("guild_raids")
        .select("*")
        .eq("guild_id", membership.guild_id)
        .not("defeated_at", "is", null)
        .order("defeated_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!raid) return jsonResponse({ error: "No defeated raid available." }, 400);

      const { data: contrib } = await supabase
        .from("guild_raid_contributions")
        .select("*")
        .eq("raid_id", raid.id)
        .eq("cloudkit_user_id", userId)
        .maybeSingle();
      if (!contrib) return jsonResponse({ error: "You did not participate in this raid." }, 400);
      if (contrib.reward_claimed) return jsonResponse({ error: "Reward already claimed." }, 400);

      await supabase
        .from("guild_raid_contributions")
        .update({ reward_claimed: true })
        .eq("raid_id", raid.id)
        .eq("cloudkit_user_id", userId);

      return jsonResponse({ success: true, gp_award: 200 });
    }

    // ----- DISMANTLE GUILD -----
    if (action === "dismantle_guild") {
      const userId = (body.cloudkit_user_id ?? "").toString();
      if (!userId) return jsonResponse({ error: "Missing cloudkit_user_id" }, 400);

      const { data: membership } = await supabase
        .from("guild_members")
        .select("*")
        .eq("cloudkit_user_id", userId)
        .maybeSingle();
      if (!membership) return jsonResponse({ error: "You're not in a guild." }, 400);

      const guildId = membership.guild_id;

      const { data: guild } = await supabase
        .from("guilds")
        .select("*")
        .eq("id", guildId)
        .maybeSingle();
      if (!guild || guild.is_disbanded) return jsonResponse({ error: "Guild not found." }, 404);

      // Only the owner can dismantle
      if (membership.role !== "owner") {
        return jsonResponse({ error: "Only the guild owner can dismantle the guild" }, 403);
      }

      // Remove ALL members
      const { error: delMembersErr } = await supabase
        .from("guild_members")
        .delete()
        .eq("guild_id", guildId);
      if (delMembersErr) throw delMembersErr;

      // Mark the guild as disbanded and zero out members
      const { error: disbandErr } = await supabase
        .from("guilds")
        .update({
          member_count: 0,
          is_disbanded: true,
          updated_at: new Date().toISOString(),
        })
        .eq("id", guildId);
      if (disbandErr) throw disbandErr;

      return jsonResponse({ success: true, dismantled: true });
    }

    // ----- GET GUILD LEADERBOARD -----
    if (action === "get_guild_leaderboard") {
      const page = Math.max(parseInt(body.page ?? "1", 10), 1);
      const pageSize = Math.min(Math.max(parseInt(body.page_size ?? "50", 10), 1), 100);
      const offset = (page - 1) * pageSize;

      const { data, error, count } = await supabase
        .from("guilds")
        .select("id, name, description, level, total_xp, member_count, max_members, owner_cloudkit_user_id", { count: "exact" })
        .eq("is_disbanded", false)
        .order("total_xp", { ascending: false })
        .order("level", { ascending: false })
        .range(offset, offset + pageSize - 1);
      if (error) throw error;

      // Assign ranks
      (data ?? []).forEach((g: Record<string, unknown>, i: number) => { g.rank = offset + i + 1; });

      return jsonResponse({ guilds: data ?? [], total: count ?? 0 });
    }

    // ----- PROMOTE MEMBER TO OFFICER -----
    if (action === "promote_member") {
      const callerId = (body.cloudkit_user_id ?? "").toString();
      const targetId = (body.target_cloudkit_user_id ?? "").toString();
      if (!callerId || !targetId) return jsonResponse({ error: "Missing params" }, 400);

      const { data: callerMember } = await supabase
        .from("guild_members").select("*").eq("cloudkit_user_id", callerId).maybeSingle();
      if (!callerMember || callerMember.role !== "owner") {
        return jsonResponse({ error: "Only the guild owner can promote members" }, 403);
      }

      const { data: targetMember } = await supabase
        .from("guild_members").select("*")
        .eq("guild_id", callerMember.guild_id).eq("cloudkit_user_id", targetId).maybeSingle();
      if (!targetMember) return jsonResponse({ error: "Target is not in your guild" }, 400);
      if (targetMember.role === "owner") return jsonResponse({ error: "Cannot promote the owner" }, 400);

      await supabase.from("guild_members").update({ role: "officer" })
        .eq("guild_id", callerMember.guild_id).eq("cloudkit_user_id", targetId);

      return jsonResponse({ success: true, new_role: "officer" });
    }

    // ----- DEMOTE OFFICER TO MEMBER -----
    if (action === "demote_officer") {
      const callerId = (body.cloudkit_user_id ?? "").toString();
      const targetId = (body.target_cloudkit_user_id ?? "").toString();
      if (!callerId || !targetId) return jsonResponse({ error: "Missing params" }, 400);

      const { data: callerMember } = await supabase
        .from("guild_members").select("*").eq("cloudkit_user_id", callerId).maybeSingle();
      if (!callerMember || callerMember.role !== "owner") {
        return jsonResponse({ error: "Only the guild owner can demote officers" }, 403);
      }

      await supabase.from("guild_members").update({ role: "member" })
        .eq("guild_id", callerMember.guild_id).eq("cloudkit_user_id", targetId);

      return jsonResponse({ success: true, new_role: "member" });
    }

    // ----- KICK MEMBER -----
    if (action === "kick_member") {
      const callerId = (body.cloudkit_user_id ?? "").toString();
      const targetId = (body.target_cloudkit_user_id ?? "").toString();
      if (!callerId || !targetId) return jsonResponse({ error: "Missing params" }, 400);
      if (callerId === targetId) return jsonResponse({ error: "Cannot kick yourself" }, 400);

      const { data: callerMember } = await supabase
        .from("guild_members").select("*").eq("cloudkit_user_id", callerId).maybeSingle();
      if (!callerMember || (callerMember.role !== "owner" && callerMember.role !== "officer")) {
        return jsonResponse({ error: "Only owners and officers can kick members" }, 403);
      }

      const { data: targetMember } = await supabase
        .from("guild_members").select("*")
        .eq("guild_id", callerMember.guild_id).eq("cloudkit_user_id", targetId).maybeSingle();
      if (!targetMember) return jsonResponse({ error: "Target is not in your guild" }, 400);
      if (targetMember.role === "owner") return jsonResponse({ error: "Cannot kick the owner" }, 400);
      if (targetMember.role === "officer" && callerMember.role !== "owner") {
        return jsonResponse({ error: "Only the owner can kick officers" }, 403);
      }

      await supabase.from("guild_members").delete()
        .eq("guild_id", callerMember.guild_id).eq("cloudkit_user_id", targetId);

      // Decrement member count
      const { data: guild } = await supabase.from("guilds").select("member_count")
        .eq("id", callerMember.guild_id).single();
      await supabase.from("guilds").update({
        member_count: Math.max(0, (guild?.member_count ?? 1) - 1),
        updated_at: new Date().toISOString(),
      }).eq("id", callerMember.guild_id);

      return jsonResponse({ success: true, kicked: targetId });
    }

    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (err) {
    console.error("guild-proxy error:", err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
