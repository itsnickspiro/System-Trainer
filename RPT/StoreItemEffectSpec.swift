import Foundation

// MARK: - StoreItemEffectSpec
//
// Source of truth for what every store item is SUPPOSED to do. Built in
// response to the pre-F7 store audit that found:
//
//   - `Discipline Crown` (+4 discipline) did nothing — server store-proxy
//     never emitted bonus_discipline; client decoder never read it;
//     Components.swift discipline stat accessor never summed it in.
//   - 14 equipment items with effect_type=stat_bonus had all bonus_*
//     columns zero — the server's stat_bonus handler was gated on
//     item_type='consumable' only.
//   - 2 consumables (Mystery Chest, Stat Reset Crystal) used effect_type
//     values (random_reward, stat_reset) that had no handler on server
//     OR client.
//   - Equipment bonus_xp_multiplier (System Armor 1.1x) was read by the
//     server but discarded by the client because recomputeBonuses()'s
//     xpMultiplier aggregation was in the consumable branch only.
//
// All four bugs shipped to TestFlight and went undetected because there
// was no verification that a purchased/equipped item actually did
// anything. This file exists so that if a future item gets added with
// a similar gap, `StoreItemEffectAudit.verifyCatalog()` fails loudly
// instead of shipping a broken purchase flow.
//
// Usage:
//   StoreItemEffectAudit.verifyCatalog() // call after StoreService.refresh()
//
// New items must be added to `knownSpecs` or the audit will flag them
// as "unspecified." Adding a new item to Supabase is fine — it just
// won't silently ship with broken effect state.

enum StoreItemEffectAudit {

    // MARK: - Effect types

    /// What an item is EXPECTED to do. Matched against the catalog row
    /// returned by StoreService after refresh.
    enum ExpectedEffect {
        /// Numeric stat bonus equipment. `stats` is the specific set of
        /// non-zero bonus fields the catalog row must report. Missing or
        /// zero fields of those named is a FAIL.
        case equipmentStatBonus(stats: [Stat: Int])

        /// XP multiplier equipment. Any non-1.0 xpMultiplier from server
        /// satisfies this — magnitude isn't asserted because the server
        /// may apply sale adjustments.
        case equipmentXPMultiplier

        /// Consumable that boosts all 5 stats when active.
        case consumableAllStatsBoost

        /// Consumable that applies a stat bonus when active (server
        /// handler implementation: +effect_value to all 5 stats).
        case consumableStatBonus

        /// Consumable that boosts health/energy when active.
        case consumableRecoveryBoost

        /// Consumable that multiplies XP while active.
        case consumableXPMultiplier

        /// Pure cosmetic — avatar frame, title, or visual. No numeric
        /// effect expected. Presence in catalog is the entire success
        /// criterion.
        case cosmeticOnly

        /// Client-dispatch-only effect — the item has a gameplay effect
        /// but that effect lives entirely in Swift code, not in numeric
        /// bonus columns. Example: Quest Reroll Token, Streak Shield
        /// (Hermit's Miracle Seed). These items are not numerically
        /// verifiable from the catalog row; the spec records intent so
        /// future audits don't flag them as "unspecified."
        case clientDispatchOnly(reason: String)

        /// Explicitly deactivated at the DB level pending a proper
        /// dispatch system. Not expected to appear in the catalog.
        case deactivatedPendingDispatch(reason: String)
    }

    enum Stat: String {
        case strength, endurance, discipline, focus, health, energy
    }

    // MARK: - Known specs
    //
    // Every row in `item_store WHERE is_active = true` must have an
    // entry here. Missing entries cause `verifyCatalog()` to flag
    // them as UNSPECIFIED — which is the signal that someone added
    // an item to Supabase without adding a verification row to
    // this file.

    static let knownSpecs: [String: ExpectedEffect] = [
        // ── equipment (22) ────────────────────────────────────────────
        "iron_bracers":        .equipmentStatBonus(stats: [.strength: 2]),
        "steel_gauntlets":     .equipmentStatBonus(stats: [.strength: 3]),
        "endurance_belt":      .equipmentStatBonus(stats: [.endurance: 3]),
        "discipline_crown":    .equipmentStatBonus(stats: [.discipline: 4]),
        "focus_lens":          .equipmentStatBonus(stats: [.focus: 3]),
        "vitality_charm":      .equipmentStatBonus(stats: [.health: 3]),
        "warriors_mantle":     .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "awakened_eye_patch":  .equipmentStatBonus(stats: [
                                    .strength: 3, .endurance: 3, .discipline: 3,
                                    .focus: 3, .health: 3
                                ]),
        "celestial_robe":      .equipmentStatBonus(stats: [
                                    .strength: 3, .endurance: 3, .discipline: 3,
                                    .focus: 3, .health: 3
                                ]),
        "endurance_talisman":  .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "flame_vambraces":     .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "focus_talisman":      .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "iron_will_headband":  .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "lone_wolf_armor":     .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "phantom_greaves":     .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "shadow_cloak":        .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "sovereign_pauldrons": .equipmentStatBonus(stats: [
                                    .strength: 3, .endurance: 3, .discipline: 3,
                                    .focus: 3, .health: 3
                                ]),
        "spirit_band":         .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "system_armor":        .equipmentStatBonus(stats: [
                                    .strength: 5, .endurance: 5, .discipline: 5,
                                    .focus: 5, .health: 5
                                ]),
        "thunder_wraps":       .equipmentStatBonus(stats: [
                                    .strength: 2, .endurance: 2, .discipline: 2,
                                    .focus: 2, .health: 2
                                ]),
        "void_gauntlets":      .equipmentStatBonus(stats: [
                                    .strength: 3, .endurance: 3, .discipline: 3,
                                    .focus: 3, .health: 3
                                ]),
        "zero_point_belt":     .equipmentStatBonus(stats: [
                                    .strength: 3, .endurance: 3, .discipline: 3,
                                    .focus: 3, .health: 3
                                ]),

        // ── consumable (15) ───────────────────────────────────────────
        "alchemy_elixir":       .consumableAllStatsBoost,
        "spirit_stone":         .consumableAllStatsBoost,
        "shadow_extraction":    .consumableAllStatsBoost,
        "discipline_token":     .consumableStatBonus,
        "gate_opener":          .consumableStatBonus,
        "phantom_step_scroll":  .consumableStatBonus,
        "senzu_surge":          .consumableRecoveryBoost,
        "last_stand_pill":      .consumableXPMultiplier,
        "training_weight_seal": .consumableXPMultiplier,
        "xp_boost_2x":          .consumableXPMultiplier,
        "xp_boost_3x":          .consumableXPMultiplier,
        "quest_reroll_token":   .clientDispatchOnly(reason: "re-rolls today's quest set — handled by QuestTemplateService, no stat effect"),
        "streak_shield":        .clientDispatchOnly(reason: "Hermit's Miracle Seed — exempts the player from streak reset on a missed day; Profile.exemptionPassCount tracks inventory"),
        "mystery_chest":        .deactivatedPendingDispatch(reason: "effect_type=random_reward has no server dispatch; deactivated in item_store by the pre-F7 audit"),
        "stat_reset_token":     .deactivatedPendingDispatch(reason: "effect_type=stat_reset has no server dispatch; deactivated in item_store by the pre-F7 audit"),

        // ── boost (1) ─────────────────────────────────────────────────
        "double_xp_weekend":    .consumableXPMultiplier,

        // ── avatar_frame (10) ─────────────────────────────────────────
        "frame_anime":      .cosmeticOnly,
        "frame_awakened":   .cosmeticOnly,
        "frame_celestial":  .cosmeticOnly,
        "frame_elite":      .cosmeticOnly,
        "frame_flame":      .cosmeticOnly,
        "frame_gold":       .cosmeticOnly,
        "frame_ronin":      .cosmeticOnly,
        "frame_shadow":     .cosmeticOnly,
        "frame_thunder":    .cosmeticOnly,
        "frame_void":       .cosmeticOnly,

        // ── title (14) ────────────────────────────────────────────────
        "title_arc_master":       .cosmeticOnly,
        "title_awakened":         .cosmeticOnly,
        "title_beast_mode":       .cosmeticOnly,
        "title_flame_pillar":     .cosmeticOnly,
        "title_gate_breaker":     .cosmeticOnly,
        "title_iron_will":        .cosmeticOnly,
        "title_lone_hunter":      .cosmeticOnly,
        "title_no_days_off":      .cosmeticOnly,
        "title_phantom_blade":    .cosmeticOnly,
        "title_shadow_monarch":   .cosmeticOnly,
        "title_system_sovereign": .cosmeticOnly,
        "title_void_walker":      .cosmeticOnly,
        "title_zero_to_hero":     .cosmeticOnly,

        // ── cosmetic (5) — avatar reskins ─────────────────────────────
        "avatar_anime_hero":      .cosmeticOnly,
        "avatar_anime_villain":   .cosmeticOnly,
        "avatar_cyber_warrior":   .cosmeticOnly,
        "avatar_golden_champion": .cosmeticOnly,
        "avatar_shadow_elite":    .cosmeticOnly,
    ]

    // MARK: - Audit

    struct AuditIssue {
        let itemKey: String
        let severity: Severity
        let reason: String

        enum Severity: String {
            case unspecified     // no entry in knownSpecs — someone added an item without updating this file
            case effectMismatch  // catalog row disagrees with spec
            case missingBonus    // spec says stat=X, catalog has zero or nil
            case unexpectedDispatch // deactivatedPendingDispatch item showed up in catalog
        }
    }

    /// Audits the currently-loaded StoreService catalog against `knownSpecs`.
    /// Returns the list of issues. Safe to call from any thread.
    ///
    /// This is the **canonical verification** requested in the F7-precursor
    /// store audit: for every item in the catalog (now and future), confirm
    /// it has a known intended effect AND that the catalog row matches that
    /// intent. New items added to Supabase that aren't also added to
    /// `knownSpecs` surface as `.unspecified` — that's the signal to
    /// update this file.
    @MainActor
    static func verifyCatalog() -> [AuditIssue] {
        var issues: [AuditIssue] = []
        let catalog = StoreService.shared.storeItems
        let catalogKeys = Set(catalog.map(\.key))
        let specKeys = Set(knownSpecs.keys)

        // 1. Items in the catalog without a spec
        for item in catalog {
            guard let spec = knownSpecs[item.key] else {
                issues.append(AuditIssue(
                    itemKey: item.key,
                    severity: .unspecified,
                    reason: "Item in catalog has no entry in StoreItemEffectAudit.knownSpecs — add one"
                ))
                continue
            }

            switch spec {
            case .equipmentStatBonus(let expected):
                guard item.itemType == "equipment" else {
                    issues.append(AuditIssue(
                        itemKey: item.key,
                        severity: .effectMismatch,
                        reason: "Spec says equipment but catalog reports item_type=\(item.itemType)"
                    ))
                    continue
                }
                for (stat, expectedValue) in expected {
                    let actual = Self.bonusValue(from: item, stat: stat)
                    if actual == nil || Int(actual!) == 0 {
                        issues.append(AuditIssue(
                            itemKey: item.key,
                            severity: .missingBonus,
                            reason: "Spec expects bonus \(stat.rawValue)=\(expectedValue), catalog reports \(actual.map { String(Int($0)) } ?? "nil")"
                        ))
                    } else if Int(actual!) != expectedValue {
                        issues.append(AuditIssue(
                            itemKey: item.key,
                            severity: .effectMismatch,
                            reason: "Spec expects \(stat.rawValue)=\(expectedValue), catalog reports \(Int(actual!))"
                        ))
                    }
                }
            case .equipmentXPMultiplier:
                if item.xpMultiplier == nil || (item.xpMultiplier ?? 1) <= 1 {
                    issues.append(AuditIssue(
                        itemKey: item.key,
                        severity: .missingBonus,
                        reason: "Spec expects xp_multiplier > 1 for equipment, catalog reports \(item.xpMultiplier.map(String.init) ?? "nil")"
                    ))
                }
            case .consumableAllStatsBoost, .consumableStatBonus:
                // The server coalesces effect_value onto bonus_* for these
                // consumables. We can't easily assert the exact value, but we
                // can assert that AT LEAST ONE bonus_* field is non-zero.
                if !Self.hasAnyStatBonus(item) {
                    issues.append(AuditIssue(
                        itemKey: item.key,
                        severity: .missingBonus,
                        reason: "Spec expects consumable stat boost, catalog has all bonus_* zero/nil"
                    ))
                }
            case .consumableRecoveryBoost:
                if (item.bonusHealth ?? 0) <= 0 && (item.bonusEnergy ?? 0) <= 0 {
                    issues.append(AuditIssue(
                        itemKey: item.key,
                        severity: .missingBonus,
                        reason: "Spec expects recovery_boost → bonus_health/energy, catalog has both zero/nil"
                    ))
                }
            case .consumableXPMultiplier:
                if item.xpMultiplier == nil || (item.xpMultiplier ?? 1) <= 1 {
                    issues.append(AuditIssue(
                        itemKey: item.key,
                        severity: .missingBonus,
                        reason: "Spec expects consumable xp_multiplier > 1, catalog reports \(item.xpMultiplier.map(String.init) ?? "nil")"
                    ))
                }
            case .cosmeticOnly:
                // Nothing to assert — cosmetic presence is the entire contract.
                break
            case .clientDispatchOnly:
                // Item exists for its own reasons — effect lives in Swift,
                // not in catalog numerics. Nothing to assert here.
                break
            case .deactivatedPendingDispatch(let reason):
                issues.append(AuditIssue(
                    itemKey: item.key,
                    severity: .unexpectedDispatch,
                    reason: "\(item.key) should be deactivated in item_store but appears in catalog. \(reason)"
                ))
            }
        }

        // 2. Specs for items not in the catalog — informational, not an error.
        //    (`deactivatedPendingDispatch` items SHOULD NOT be in the catalog.)
        let orphanedSpecs = specKeys.subtracting(catalogKeys)
        for key in orphanedSpecs {
            if case .deactivatedPendingDispatch = knownSpecs[key] {
                continue  // expected to be absent
            }
            // Not emitted as an issue — a spec can exist for an item that's
            // seasonally disabled. Logged only, and only in DEBUG.
            #if DEBUG
            print("[StoreItemEffectAudit] spec entry '\(key)' has no matching catalog item (this is OK if the store rotates)")
            #endif
        }

        return issues
    }

    /// Convenience wrapper that logs results. Call from StoreService after
    /// refresh, or from a debug menu.
    @MainActor
    static func auditAndLog() {
        let issues = verifyCatalog()
        if issues.isEmpty {
            print("[StoreItemEffectAudit] ✓ \(StoreService.shared.storeItems.count) items pass verification")
            return
        }
        print("[StoreItemEffectAudit] ⚠ \(issues.count) issue(s) found:")
        for issue in issues {
            print("  - [\(issue.severity.rawValue)] \(issue.itemKey): \(issue.reason)")
        }
    }

    // MARK: - Private helpers

    private static func bonusValue(from item: StoreItem, stat: Stat) -> Double? {
        switch stat {
        case .strength:   return item.bonusStrength
        case .endurance:  return item.bonusEndurance
        case .discipline: return item.bonusDiscipline
        case .focus:      return item.bonusFocus
        case .health:     return item.bonusHealth
        case .energy:     return item.bonusEnergy
        }
    }

    private static func hasAnyStatBonus(_ item: StoreItem) -> Bool {
        (item.bonusStrength ?? 0) > 0
            || (item.bonusEndurance ?? 0) > 0
            || (item.bonusDiscipline ?? 0) > 0
            || (item.bonusFocus ?? 0) > 0
            || (item.bonusHealth ?? 0) > 0
            || (item.bonusEnergy ?? 0) > 0
    }
}
