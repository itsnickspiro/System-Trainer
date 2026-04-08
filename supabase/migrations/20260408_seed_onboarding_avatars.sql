-- Seed 12 onboarding avatars (6 archetypes x 2 genders).
-- All free, all unlocked from day one so the AvatarPickerStepView during
-- onboarding has real options to show. The keys below MUST exactly match
-- the imageset names in RPT/Assets.xcassets/Avatars/{Male,Female}/ —
-- the iOS client loads them via UIImage(named: avatar.key).
--
-- Idempotent: ON CONFLICT DO NOTHING means re-running the migration is
-- safe. To update an existing row, edit it in the SQL editor directly or
-- write a follow-up migration.

-- Allowed category values per check constraint avatars_category_check:
--   default, warrior, mage, rogue, tank, anime, seasonal, premium, event
-- Mapping each archetype to the closest allowed category.
INSERT INTO avatars (
    key, name, description, category, rarity,
    unlock_type, unlock_level, gp_price,
    accent_color, sort_order, is_active
) VALUES
    -- Archer (ranged) -> rogue category
    ('avatar_archer_m',    'Archer',    'A keen-eyed marksman who never misses.',          'rogue',   'common', 'free', NULL, NULL, '#00FF7F',  1, true),
    ('avatar_archer_f',    'Archer',    'A keen-eyed markswoman who never misses.',        'rogue',   'common', 'free', NULL, NULL, '#00FF7F',  2, true),
    -- Assassin -> rogue
    ('avatar_assassin_m',  'Assassin',  'Strikes from the shadows, leaves no trace.',      'rogue',   'common', 'free', NULL, NULL, '#B266FF',  3, true),
    ('avatar_assassin_f',  'Assassin',  'Strikes from the shadows, leaves no trace.',      'rogue',   'common', 'free', NULL, NULL, '#B266FF',  4, true),
    -- Rogue (suffixed _classic to avoid colliding with the pre-existing
    -- avatar_rogue_m / avatar_rogue_f rows Shadow Runner / Night Striker)
    ('avatar_rogue_classic_m', 'Rogue', 'Quick wit, quicker blade.',                       'rogue',   'common', 'free', NULL, NULL, '#A0A0A0',  5, true),
    ('avatar_rogue_classic_f', 'Rogue', 'Quick wit, quicker blade.',                       'rogue',   'common', 'free', NULL, NULL, '#A0A0A0',  6, true),
    -- Sage -> mage
    ('avatar_sage_m',      'Sage',      'Wisdom forged through endless study.',            'mage',    'common', 'free', NULL, NULL, '#00FFFF',  7, true),
    ('avatar_sage_f',      'Sage',      'Wisdom forged through endless study.',            'mage',    'common', 'free', NULL, NULL, '#00FFFF',  8, true),
    -- Sorceror / Sorceress -> mage
    ('avatar_sorceror_m',  'Sorceror',  'Bender of arcane forces.',                        'mage',    'common', 'free', NULL, NULL, '#FF66FF',  9, true),
    ('avatar_sorceress_f', 'Sorceress', 'Bender of arcane forces.',                        'mage',    'common', 'free', NULL, NULL, '#FF66FF', 10, true),
    -- Villain (no archetype-specific category) -> default
    ('avatar_villain_m',   'Villain',   'Power answers to no one but itself.',             'default', 'common', 'free', NULL, NULL, '#FF0033', 11, true),
    ('avatar_villain_f',   'Villain',   'Power answers to no one but itself.',             'default', 'common', 'free', NULL, NULL, '#FF0033', 12, true)
ON CONFLICT (key) DO NOTHING;
