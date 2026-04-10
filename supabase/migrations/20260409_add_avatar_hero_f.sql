-- Add Hero (Female) avatar — warrior category, free unlock.
INSERT INTO avatars (
    key, name, description, category, rarity,
    unlock_type, unlock_level, gp_price,
    accent_color, sort_order, is_active
) VALUES (
    'avatar_hero_f', 'Hero', 'A champion who rises when others fall.',
    'warrior', 'common', 'free', NULL, NULL,
    '#FFD700', 13, true
) ON CONFLICT (key) DO NOTHING;
