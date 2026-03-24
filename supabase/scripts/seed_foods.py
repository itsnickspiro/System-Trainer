#!/usr/bin/env python3
"""
Foods Database Seed Script
==========================
Seeds the Supabase `foods` table from the curated list originally in
SampleFoodData.swift (~200 items). Run once after running the migration.

Requirements
------------
    pip install requests

Usage
-----
    export SUPABASE_URL="https://erghbsnxtsbnmfuycnyb.supabase.co"
    export DB_SERVICE_ROLE_KEY="<your-service-role-key>"

    # Dry-run (print JSON, no upload):
    python3 seed_foods.py --dry-run

    # Seed (upsert on name conflict):
    python3 seed_foods.py

    # Re-seed even if rows already exist:
    python3 seed_foods.py --force
"""

import argparse
import json
import os
import sys
from typing import Optional

import requests

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SUPABASE_URL     = os.environ.get("SUPABASE_URL", "https://erghbsnxtsbnmfuycnyb.supabase.co")
SUPABASE_SVC_KEY = os.environ.get("DB_SERVICE_ROLE_KEY", "")
REST_BASE        = f"{SUPABASE_URL}/rest/v1"
UPSERT_BATCH     = 100


# ---------------------------------------------------------------------------
# Food data — mirrors SampleFoodData.swift exactly
# Fields: name, brand, barcode, calories_per_100g, serving_size_g,
#         carbohydrates, protein, fat, fiber, sugar, sodium_mg, category
# ---------------------------------------------------------------------------

FOODS: list[dict] = [

    # ── Proteins: Meats & Fish ───────────────────────────────────────────────
    dict(name="Chicken Breast, Grilled",     brand=None,              barcode=None,           calories_per_100g=165, serving_size_g=150, carbohydrates=0,    protein=31.0, fat=3.6,  fiber=0,    sugar=0,    sodium_mg=74,   category="proteins"),
    dict(name="Chicken Thigh, Skinless",     brand=None,              barcode=None,           calories_per_100g=177, serving_size_g=140, carbohydrates=0,    protein=24.0, fat=9.0,  fiber=0,    sugar=0,    sodium_mg=90,   category="proteins"),
    dict(name="Ground Turkey 93% Lean",      brand=None,              barcode=None,           calories_per_100g=148, serving_size_g=112, carbohydrates=0,    protein=22.0, fat=6.5,  fiber=0,    sugar=0,    sodium_mg=79,   category="proteins"),
    dict(name="Atlantic Salmon, Baked",      brand=None,              barcode=None,           calories_per_100g=206, serving_size_g=140, carbohydrates=0,    protein=22.1, fat=12.4, fiber=0,    sugar=0,    sodium_mg=59,   category="proteins"),
    dict(name="Tuna, Canned in Water",       brand="StarKist",        barcode=None,           calories_per_100g=116, serving_size_g=85,  carbohydrates=0,    protein=25.5, fat=1.0,  fiber=0,    sugar=0,    sodium_mg=320,  category="proteins"),
    dict(name="Tilapia Fillet, Baked",       brand=None,              barcode=None,           calories_per_100g=96,  serving_size_g=140, carbohydrates=0,    protein=20.1, fat=2.0,  fiber=0,    sugar=0,    sodium_mg=52,   category="proteins"),
    dict(name="Shrimp, Cooked",              brand=None,              barcode=None,           calories_per_100g=99,  serving_size_g=85,  carbohydrates=0,    protein=21.0, fat=1.1,  fiber=0,    sugar=0,    sodium_mg=190,  category="proteins"),
    dict(name="Lean Ground Beef 95%",        brand=None,              barcode=None,           calories_per_100g=152, serving_size_g=112, carbohydrates=0,    protein=22.0, fat=7.0,  fiber=0,    sugar=0,    sodium_mg=72,   category="proteins"),
    dict(name="Sirloin Steak, Grilled",      brand=None,              barcode=None,           calories_per_100g=207, serving_size_g=170, carbohydrates=0,    protein=26.0, fat=11.0, fiber=0,    sugar=0,    sodium_mg=65,   category="proteins"),
    dict(name="Turkey Breast, Deli Sliced",  brand="Boar's Head",     barcode=None,           calories_per_100g=109, serving_size_g=56,  carbohydrates=2.0,  protein=18.0, fat=2.5,  fiber=0,    sugar=1.0,  sodium_mg=450,  category="proteins"),
    dict(name="Cod Fillet, Baked",           brand=None,              barcode=None,           calories_per_100g=82,  serving_size_g=140, carbohydrates=0,    protein=17.5, fat=0.7,  fiber=0,    sugar=0,    sodium_mg=65,   category="proteins"),
    dict(name="Sardines in Olive Oil",       brand="Season",          barcode=None,           calories_per_100g=208, serving_size_g=85,  carbohydrates=0,    protein=22.0, fat=13.0, fiber=0,    sugar=0,    sodium_mg=400,  category="proteins"),

    # ── Proteins: Eggs & Dairy Protein ──────────────────────────────────────
    dict(name="Whole Egg, Large",            brand=None,              barcode=None,           calories_per_100g=143, serving_size_g=50,  carbohydrates=0.7,  protein=12.6, fat=9.5,  fiber=0,    sugar=0.2,  sodium_mg=142,  category="proteins"),
    dict(name="Egg Whites, Liquid",          brand=None,              barcode=None,           calories_per_100g=52,  serving_size_g=61,  carbohydrates=0.7,  protein=10.9, fat=0.2,  fiber=0,    sugar=0.7,  sodium_mg=169,  category="proteins"),
    dict(name="Cottage Cheese 2%",           brand="Daisy",           barcode=None,           calories_per_100g=90,  serving_size_g=113, carbohydrates=4.5,  protein=13.5, fat=2.5,  fiber=0,    sugar=4.5,  sodium_mg=310,  category="dairy"),
    dict(name="Greek Yogurt, Plain 0%",      brand="Fage",            barcode=None,           calories_per_100g=57,  serving_size_g=170, carbohydrates=4.0,  protein=10.0, fat=0.4,  fiber=0,    sugar=4.0,  sodium_mg=36,   category="dairy"),
    dict(name="Greek Yogurt, Plain 2%",      brand="Chobani",         barcode=None,           calories_per_100g=80,  serving_size_g=170, carbohydrates=5.0,  protein=14.0, fat=2.0,  fiber=0,    sugar=5.0,  sodium_mg=70,   category="dairy"),
    dict(name="Whey Protein Isolate",        brand="Optimum Nutrition",barcode=None,          calories_per_100g=370, serving_size_g=31,  carbohydrates=4.0,  protein=25.0, fat=1.0,  fiber=0,    sugar=1.0,  sodium_mg=90,   category="proteins"),
    dict(name="Casein Protein Powder",       brand="Dymatize",        barcode=None,           calories_per_100g=370, serving_size_g=34,  carbohydrates=5.0,  protein=25.0, fat=1.5,  fiber=1.0,  sugar=1.0,  sodium_mg=230,  category="proteins"),

    # ── Legumes & Plant Proteins ─────────────────────────────────────────────
    dict(name="Black Beans, Cooked",         brand=None,              barcode=None,           calories_per_100g=132, serving_size_g=130, carbohydrates=24.0, protein=8.9,  fat=0.5,  fiber=8.7,  sugar=0.3,  sodium_mg=2,    category="proteins"),
    dict(name="Chickpeas, Cooked",           brand=None,              barcode=None,           calories_per_100g=164, serving_size_g=164, carbohydrates=27.0, protein=8.9,  fat=2.6,  fiber=7.6,  sugar=4.8,  sodium_mg=7,    category="proteins"),
    dict(name="Lentils, Cooked",             brand=None,              barcode=None,           calories_per_100g=116, serving_size_g=198, carbohydrates=20.0, protein=9.0,  fat=0.4,  fiber=7.9,  sugar=1.8,  sodium_mg=4,    category="proteins"),
    dict(name="Edamame, Shelled",            brand=None,              barcode=None,           calories_per_100g=122, serving_size_g=155, carbohydrates=9.9,  protein=11.9, fat=5.2,  fiber=5.2,  sugar=2.2,  sodium_mg=9,    category="proteins"),
    dict(name="Tofu, Extra Firm",            brand="Nasoya",          barcode=None,           calories_per_100g=76,  serving_size_g=140, carbohydrates=2.0,  protein=9.4,  fat=4.2,  fiber=0.3,  sugar=0.5,  sodium_mg=10,   category="proteins"),
    dict(name="Tempeh",                      brand=None,              barcode=None,           calories_per_100g=193, serving_size_g=85,  carbohydrates=9.4,  protein=19.0, fat=11.0, fiber=0,    sugar=0,    sodium_mg=9,    category="proteins"),
    dict(name="Kidney Beans, Cooked",        brand=None,              barcode=None,           calories_per_100g=127, serving_size_g=177, carbohydrates=23.0, protein=8.7,  fat=0.5,  fiber=6.4,  sugar=0.3,  sodium_mg=2,    category="proteins"),

    # ── Grains & Carbohydrates ───────────────────────────────────────────────
    dict(name="Steel Cut Oats",              brand="Quaker",          barcode=None,           calories_per_100g=379, serving_size_g=40,  carbohydrates=67.7, protein=13.2, fat=6.5,  fiber=10.1, sugar=1.1,  sodium_mg=2,    category="grains"),
    dict(name="Rolled Oats",                 brand="Bob's Red Mill",  barcode=None,           calories_per_100g=389, serving_size_g=40,  carbohydrates=66.0, protein=14.0, fat=7.0,  fiber=10.0, sugar=1.0,  sodium_mg=5,    category="grains"),
    dict(name="Brown Rice, Cooked",          brand=None,              barcode=None,           calories_per_100g=111, serving_size_g=200, carbohydrates=23.0, protein=2.6,  fat=0.9,  fiber=1.8,  sugar=0.4,  sodium_mg=5,    category="grains"),
    dict(name="White Rice, Cooked",          brand=None,              barcode=None,           calories_per_100g=130, serving_size_g=186, carbohydrates=28.0, protein=2.7,  fat=0.3,  fiber=0.4,  sugar=0,    sodium_mg=2,    category="grains"),
    dict(name="Quinoa, Cooked",              brand=None,              barcode=None,           calories_per_100g=120, serving_size_g=185, carbohydrates=21.3, protein=4.4,  fat=1.9,  fiber=2.8,  sugar=0.9,  sodium_mg=7,    category="grains"),
    dict(name="Whole Wheat Bread",           brand="Dave's Killer Bread", barcode=None,       calories_per_100g=247, serving_size_g=45,  carbohydrates=43.3, protein=13.4, fat=4.2,  fiber=7.0,  sugar=5.6,  sodium_mg=491,  category="grains"),
    dict(name="White Bread",                 brand="Wonder",          barcode=None,           calories_per_100g=266, serving_size_g=25,  carbohydrates=50.0, protein=8.0,  fat=3.5,  fiber=2.0,  sugar=4.0,  sodium_mg=506,  category="grains"),
    dict(name="Whole Wheat Pasta, Dry",      brand="Barilla",         barcode=None,           calories_per_100g=348, serving_size_g=56,  carbohydrates=68.0, protein=14.0, fat=2.5,  fiber=7.0,  sugar=3.0,  sodium_mg=7,    category="grains"),
    dict(name="Pasta (White), Cooked",       brand=None,              barcode=None,           calories_per_100g=131, serving_size_g=140, carbohydrates=25.0, protein=5.0,  fat=1.1,  fiber=1.0,  sugar=0.6,  sodium_mg=3,    category="grains"),
    dict(name="Sweet Potato, Baked",         brand=None,              barcode=None,           calories_per_100g=86,  serving_size_g=130, carbohydrates=20.1, protein=1.6,  fat=0.1,  fiber=3.0,  sugar=4.2,  sodium_mg=4,    category="vegetables"),
    dict(name="White Potato, Baked",         brand=None,              barcode=None,           calories_per_100g=93,  serving_size_g=173, carbohydrates=21.1, protein=2.5,  fat=0.1,  fiber=2.1,  sugar=0.9,  sodium_mg=10,   category="vegetables"),
    dict(name="Corn Tortilla",               brand="Mission",         barcode=None,           calories_per_100g=218, serving_size_g=28,  carbohydrates=44.0, protein=5.7,  fat=3.0,  fiber=5.3,  sugar=0.7,  sodium_mg=376,  category="grains"),
    dict(name="Basmati Rice, Cooked",        brand=None,              barcode=None,           calories_per_100g=121, serving_size_g=186, carbohydrates=25.2, protein=3.5,  fat=0.4,  fiber=0.4,  sugar=0,    sodium_mg=1,    category="grains"),
    dict(name="Ezekiel Bread",               brand="Food for Life",   barcode=None,           calories_per_100g=253, serving_size_g=34,  carbohydrates=41.3, protein=10.0, fat=1.0,  fiber=6.7,  sugar=0,    sodium_mg=173,  category="grains"),
    dict(name="Buckwheat Groats, Cooked",    brand=None,              barcode=None,           calories_per_100g=92,  serving_size_g=168, carbohydrates=19.9, protein=3.4,  fat=0.6,  fiber=2.7,  sugar=0.9,  sodium_mg=4,    category="grains"),

    # ── Vegetables ───────────────────────────────────────────────────────────
    dict(name="Broccoli, Steamed",           brand=None,              barcode=None,           calories_per_100g=35,  serving_size_g=150, carbohydrates=7.0,  protein=2.8,  fat=0.4,  fiber=2.6,  sugar=1.5,  sodium_mg=33,   category="vegetables"),
    dict(name="Spinach, Fresh",              brand=None,              barcode=None,           calories_per_100g=23,  serving_size_g=30,  carbohydrates=3.6,  protein=2.9,  fat=0.4,  fiber=2.2,  sugar=0.4,  sodium_mg=79,   category="vegetables"),
    dict(name="Kale, Raw",                   brand=None,              barcode=None,           calories_per_100g=49,  serving_size_g=67,  carbohydrates=8.8,  protein=4.3,  fat=0.9,  fiber=3.6,  sugar=1.0,  sodium_mg=38,   category="vegetables"),
    dict(name="Mixed Salad Greens",          brand=None,              barcode=None,           calories_per_100g=20,  serving_size_g=85,  carbohydrates=3.5,  protein=2.0,  fat=0.3,  fiber=1.5,  sugar=1.8,  sodium_mg=45,   category="vegetables"),
    dict(name="Romaine Lettuce",             brand=None,              barcode=None,           calories_per_100g=17,  serving_size_g=85,  carbohydrates=3.3,  protein=1.2,  fat=0.3,  fiber=2.1,  sugar=1.1,  sodium_mg=8,    category="vegetables"),
    dict(name="Cucumber, Sliced",            brand=None,              barcode=None,           calories_per_100g=16,  serving_size_g=119, carbohydrates=3.6,  protein=0.7,  fat=0.1,  fiber=0.5,  sugar=1.7,  sodium_mg=2,    category="vegetables"),
    dict(name="Cherry Tomatoes",             brand=None,              barcode=None,           calories_per_100g=18,  serving_size_g=149, carbohydrates=3.9,  protein=0.9,  fat=0.2,  fiber=1.2,  sugar=2.6,  sodium_mg=5,    category="vegetables"),
    dict(name="Bell Pepper, Red",            brand=None,              barcode=None,           calories_per_100g=31,  serving_size_g=149, carbohydrates=7.2,  protein=1.0,  fat=0.3,  fiber=2.1,  sugar=4.7,  sodium_mg=2,    category="vegetables"),
    dict(name="Zucchini, Cooked",            brand=None,              barcode=None,           calories_per_100g=17,  serving_size_g=180, carbohydrates=3.5,  protein=1.3,  fat=0.3,  fiber=1.2,  sugar=2.1,  sodium_mg=3,    category="vegetables"),
    dict(name="Asparagus, Steamed",          brand=None,              barcode=None,           calories_per_100g=20,  serving_size_g=134, carbohydrates=3.9,  protein=2.2,  fat=0.2,  fiber=2.1,  sugar=1.9,  sodium_mg=2,    category="vegetables"),
    dict(name="Green Beans, Cooked",         brand=None,              barcode=None,           calories_per_100g=35,  serving_size_g=125, carbohydrates=7.9,  protein=1.9,  fat=0.1,  fiber=3.4,  sugar=3.4,  sodium_mg=1,    category="vegetables"),
    dict(name="Cauliflower, Steamed",        brand=None,              barcode=None,           calories_per_100g=25,  serving_size_g=107, carbohydrates=5.3,  protein=1.9,  fat=0.3,  fiber=2.1,  sugar=2.4,  sodium_mg=30,   category="vegetables"),
    dict(name="Mushrooms, Sauteed",          brand=None,              barcode=None,           calories_per_100g=38,  serving_size_g=156, carbohydrates=5.9,  protein=3.8,  fat=0.5,  fiber=1.1,  sugar=2.9,  sodium_mg=14,   category="vegetables"),
    dict(name="Onion, Yellow",               brand=None,              barcode=None,           calories_per_100g=40,  serving_size_g=148, carbohydrates=9.3,  protein=1.1,  fat=0.1,  fiber=1.7,  sugar=4.2,  sodium_mg=4,    category="vegetables"),
    dict(name="Carrot, Raw",                 brand=None,              barcode=None,           calories_per_100g=41,  serving_size_g=61,  carbohydrates=9.6,  protein=0.9,  fat=0.2,  fiber=2.8,  sugar=4.7,  sodium_mg=69,   category="vegetables"),
    dict(name="Celery, Raw",                 brand=None,              barcode=None,           calories_per_100g=16,  serving_size_g=101, carbohydrates=3.5,  protein=0.7,  fat=0.2,  fiber=1.6,  sugar=1.8,  sodium_mg=80,   category="vegetables"),
    dict(name="Brussels Sprouts, Roasted",   brand=None,              barcode=None,           calories_per_100g=43,  serving_size_g=88,  carbohydrates=9.0,  protein=3.4,  fat=0.3,  fiber=3.8,  sugar=2.2,  sodium_mg=25,   category="vegetables"),

    # ── Fruits ───────────────────────────────────────────────────────────────
    dict(name="Banana, Medium",              brand=None,              barcode=None,           calories_per_100g=89,  serving_size_g=118, carbohydrates=22.8, protein=1.1,  fat=0.3,  fiber=2.6,  sugar=12.2, sodium_mg=1,    category="fruits"),
    dict(name="Apple, Medium",               brand=None,              barcode=None,           calories_per_100g=52,  serving_size_g=182, carbohydrates=13.8, protein=0.3,  fat=0.2,  fiber=2.4,  sugar=10.4, sodium_mg=1,    category="fruits"),
    dict(name="Blueberries, Fresh",          brand=None,              barcode=None,           calories_per_100g=57,  serving_size_g=148, carbohydrates=14.5, protein=0.7,  fat=0.3,  fiber=2.4,  sugar=10.0, sodium_mg=1,    category="fruits"),
    dict(name="Strawberries, Fresh",         brand=None,              barcode=None,           calories_per_100g=32,  serving_size_g=152, carbohydrates=7.7,  protein=0.7,  fat=0.3,  fiber=2.0,  sugar=4.9,  sodium_mg=1,    category="fruits"),
    dict(name="Orange, Navel",               brand=None,              barcode=None,           calories_per_100g=47,  serving_size_g=154, carbohydrates=11.8, protein=0.9,  fat=0.1,  fiber=2.4,  sugar=9.4,  sodium_mg=0,    category="fruits"),
    dict(name="Mango, Diced",                brand=None,              barcode=None,           calories_per_100g=60,  serving_size_g=165, carbohydrates=15.0, protein=0.8,  fat=0.4,  fiber=1.6,  sugar=13.7, sodium_mg=2,    category="fruits"),
    dict(name="Pineapple, Fresh Chunks",     brand=None,              barcode=None,           calories_per_100g=50,  serving_size_g=165, carbohydrates=13.1, protein=0.5,  fat=0.1,  fiber=1.4,  sugar=9.9,  sodium_mg=1,    category="fruits"),
    dict(name="Grapes, Red",                 brand=None,              barcode=None,           calories_per_100g=69,  serving_size_g=151, carbohydrates=18.1, protein=0.6,  fat=0.2,  fiber=0.9,  sugar=15.5, sodium_mg=2,    category="fruits"),
    dict(name="Watermelon, Cubed",           brand=None,              barcode=None,           calories_per_100g=30,  serving_size_g=286, carbohydrates=7.6,  protein=0.6,  fat=0.2,  fiber=0.4,  sugar=6.2,  sodium_mg=2,    category="fruits"),
    dict(name="Avocado, Hass",               brand=None,              barcode=None,           calories_per_100g=160, serving_size_g=201, carbohydrates=8.5,  protein=2.0,  fat=14.7, fiber=6.7,  sugar=0.7,  sodium_mg=7,    category="fats"),
    dict(name="Raspberries, Fresh",          brand=None,              barcode=None,           calories_per_100g=52,  serving_size_g=123, carbohydrates=11.9, protein=1.2,  fat=0.7,  fiber=6.5,  sugar=4.4,  sodium_mg=1,    category="fruits"),
    dict(name="Kiwi, Green",                 brand=None,              barcode=None,           calories_per_100g=61,  serving_size_g=76,  carbohydrates=15.0, protein=1.1,  fat=0.5,  fiber=3.0,  sugar=9.0,  sodium_mg=3,    category="fruits"),

    # ── Dairy ────────────────────────────────────────────────────────────────
    dict(name="Whole Milk",                  brand=None,              barcode=None,           calories_per_100g=61,  serving_size_g=244, carbohydrates=4.8,  protein=3.2,  fat=3.3,  fiber=0,    sugar=4.8,  sodium_mg=43,   category="dairy"),
    dict(name="Skim Milk",                   brand=None,              barcode=None,           calories_per_100g=34,  serving_size_g=244, carbohydrates=5.0,  protein=3.4,  fat=0.2,  fiber=0,    sugar=5.0,  sodium_mg=44,   category="dairy"),
    dict(name="Almond Milk, Unsweetened",    brand="Califia",         barcode=None,           calories_per_100g=15,  serving_size_g=240, carbohydrates=1.3,  protein=0.4,  fat=1.2,  fiber=0.3,  sugar=0,    sodium_mg=160,  category="dairy"),
    dict(name="Oat Milk",                    brand="Oatly",           barcode=None,           calories_per_100g=47,  serving_size_g=240, carbohydrates=8.3,  protein=1.3,  fat=1.7,  fiber=0.8,  sugar=4.2,  sodium_mg=100,  category="dairy"),
    dict(name="Cheddar Cheese",              brand="Tillamook",       barcode=None,           calories_per_100g=403, serving_size_g=28,  carbohydrates=1.3,  protein=23.0, fat=33.0, fiber=0,    sugar=0.5,  sodium_mg=621,  category="dairy"),
    dict(name="Mozzarella, Part Skim",       brand=None,              barcode=None,           calories_per_100g=254, serving_size_g=28,  carbohydrates=2.2,  protein=16.0, fat=17.0, fiber=0,    sugar=0.7,  sodium_mg=406,  category="dairy"),
    dict(name="Parmesan, Grated",            brand="Kraft",           barcode=None,           calories_per_100g=431, serving_size_g=5,   carbohydrates=3.8,  protein=38.0, fat=29.0, fiber=0,    sugar=0.9,  sodium_mg=1529, category="dairy"),
    dict(name="Butter, Unsalted",            brand="Land O'Lakes",    barcode=None,           calories_per_100g=717, serving_size_g=14,  carbohydrates=0.1,  protein=0.1,  fat=81.1, fiber=0,    sugar=0.1,  sodium_mg=11,   category="fats"),

    # ── Nuts & Seeds ─────────────────────────────────────────────────────────
    dict(name="Almonds, Raw",                brand=None,              barcode=None,           calories_per_100g=579, serving_size_g=28,  carbohydrates=21.6, protein=21.2, fat=49.9, fiber=12.5, sugar=4.4,  sodium_mg=1,    category="nuts_seeds"),
    dict(name="Walnuts, Raw",                brand=None,              barcode=None,           calories_per_100g=654, serving_size_g=28,  carbohydrates=13.7, protein=15.2, fat=65.2, fiber=6.7,  sugar=2.6,  sodium_mg=2,    category="nuts_seeds"),
    dict(name="Cashews, Roasted",            brand=None,              barcode=None,           calories_per_100g=553, serving_size_g=28,  carbohydrates=32.7, protein=14.8, fat=43.9, fiber=3.3,  sugar=5.9,  sodium_mg=181,  category="nuts_seeds"),
    dict(name="Peanut Butter, Natural",      brand="Justin's",        barcode=None,           calories_per_100g=588, serving_size_g=32,  carbohydrates=20.0, protein=25.8, fat=50.0, fiber=6.0,  sugar=9.2,  sodium_mg=17,   category="nuts_seeds"),
    dict(name="Almond Butter",               brand="Barney Butter",   barcode=None,           calories_per_100g=614, serving_size_g=32,  carbohydrates=18.8, protein=21.2, fat=55.5, fiber=12.5, sugar=3.7,  sodium_mg=2,    category="nuts_seeds"),
    dict(name="Chia Seeds",                  brand=None,              barcode=None,           calories_per_100g=486, serving_size_g=28,  carbohydrates=42.1, protein=16.5, fat=30.7, fiber=34.4, sugar=0,    sodium_mg=16,   category="nuts_seeds"),
    dict(name="Flaxseed, Ground",            brand=None,              barcode=None,           calories_per_100g=534, serving_size_g=10,  carbohydrates=28.9, protein=18.3, fat=42.2, fiber=27.3, sugar=1.6,  sodium_mg=30,   category="nuts_seeds"),
    dict(name="Hemp Seeds",                  brand="Manitoba Harvest", barcode=None,          calories_per_100g=553, serving_size_g=30,  carbohydrates=8.7,  protein=31.6, fat=48.8, fiber=4.0,  sugar=1.5,  sodium_mg=5,    category="nuts_seeds"),
    dict(name="Pistachios, Shelled",         brand=None,              barcode=None,           calories_per_100g=562, serving_size_g=28,  carbohydrates=27.7, protein=20.2, fat=45.3, fiber=10.3, sugar=7.7,  sodium_mg=1,    category="nuts_seeds"),
    dict(name="Pumpkin Seeds",               brand=None,              barcode=None,           calories_per_100g=559, serving_size_g=28,  carbohydrates=17.8, protein=24.5, fat=45.9, fiber=6.0,  sugar=1.4,  sodium_mg=5,    category="nuts_seeds"),

    # ── Oils & Condiments ────────────────────────────────────────────────────
    dict(name="Olive Oil, Extra Virgin",     brand="California Olive Ranch", barcode=None,   calories_per_100g=884, serving_size_g=14,  carbohydrates=0,    protein=0,    fat=100.0,fiber=0,    sugar=0,    sodium_mg=0,    category="oils"),
    dict(name="Coconut Oil",                 brand="Nutiva",          barcode=None,           calories_per_100g=862, serving_size_g=14,  carbohydrates=0,    protein=0,    fat=100.0,fiber=0,    sugar=0,    sodium_mg=0,    category="oils"),
    dict(name="Hummus, Classic",             brand="Sabra",           barcode=None,           calories_per_100g=166, serving_size_g=56,  carbohydrates=14.3, protein=4.9,  fat=9.6,  fiber=3.9,  sugar=1.4,  sodium_mg=286,  category="fats"),
    dict(name="Salsa, Mild",                 brand="Newman's Own",    barcode=None,           calories_per_100g=25,  serving_size_g=30,  carbohydrates=5.0,  protein=1.0,  fat=0,    fiber=1.0,  sugar=3.0,  sodium_mg=190,  category="condiments"),
    dict(name="Soy Sauce, Low Sodium",       brand="Kikkoman",        barcode=None,           calories_per_100g=60,  serving_size_g=15,  carbohydrates=5.6,  protein=5.8,  fat=0.1,  fiber=0.1,  sugar=0.8,  sodium_mg=575,  category="condiments"),
    dict(name="Hot Sauce, Tabasco",          brand="McIlhenny",       barcode=None,           calories_per_100g=12,  serving_size_g=5,   carbohydrates=0.3,  protein=0.1,  fat=0.1,  fiber=0,    sugar=0.1,  sodium_mg=196,  category="condiments"),

    # ── Beverages ────────────────────────────────────────────────────────────
    dict(name="Coffee, Black",               brand=None,              barcode=None,           calories_per_100g=1,   serving_size_g=240, carbohydrates=0,    protein=0.1,  fat=0,    fiber=0,    sugar=0,    sodium_mg=5,    category="beverages"),
    dict(name="Green Tea",                   brand=None,              barcode=None,           calories_per_100g=1,   serving_size_g=240, carbohydrates=0,    protein=0,    fat=0,    fiber=0,    sugar=0,    sodium_mg=1,    category="beverages"),
    dict(name="Protein Shake, Chocolate",    brand="Premier Protein", barcode=None,           calories_per_100g=104, serving_size_g=325, carbohydrates=4.9,  protein=30.0, fat=3.1,  fiber=1.5,  sugar=1.2,  sodium_mg=400,  category="proteins"),
    dict(name="Coca-Cola Classic",           brand="Coca-Cola",       barcode="049000028913", calories_per_100g=42,  serving_size_g=355, carbohydrates=10.6, protein=0,    fat=0,    fiber=0,    sugar=10.6, sodium_mg=9,    category="beverages"),
    dict(name="Orange Juice, No Pulp",       brand="Tropicana",       barcode=None,           calories_per_100g=45,  serving_size_g=240, carbohydrates=10.5, protein=0.7,  fat=0.2,  fiber=0.2,  sugar=8.4,  sodium_mg=2,    category="beverages"),
    dict(name="Sports Drink, Lemon-Lime",    brand="Gatorade",        barcode=None,           calories_per_100g=26,  serving_size_g=591, carbohydrates=6.3,  protein=0,    fat=0,    fiber=0,    sugar=5.3,  sodium_mg=110,  category="beverages"),
    dict(name="Sparkling Water",             brand="LaCroix",         barcode=None,           calories_per_100g=0,   serving_size_g=355, carbohydrates=0,    protein=0,    fat=0,    fiber=0,    sugar=0,    sodium_mg=0,    category="beverages"),
    dict(name="Coconut Water",               brand="Vita Coco",       barcode=None,           calories_per_100g=19,  serving_size_g=330, carbohydrates=4.3,  protein=0.2,  fat=0.2,  fiber=0,    sugar=3.7,  sodium_mg=22,   category="beverages"),

    # ── Snacks & Packaged Foods ───────────────────────────────────────────────
    dict(name="Cheerios Original",           brand="General Mills",   barcode="016000275263", calories_per_100g=367, serving_size_g=28,  carbohydrates=73.3, protein=10.0, fat=6.7,  fiber=10.0, sugar=3.3,  sodium_mg=500,  category="grains"),
    dict(name="KIND Bar, Dark Chocolate Nuts",brand="KIND",           barcode="602652171215", calories_per_100g=500, serving_size_g=40,  carbohydrates=35.0, protein=15.0, fat=35.0, fiber=7.5,  sugar=12.5, sodium_mg=375,  category="snacks"),
    dict(name="Clif Bar, Chocolate Chip",    brand="Clif",            barcode=None,           calories_per_100g=388, serving_size_g=68,  carbohydrates=68.0, protein=11.8, fat=5.9,  fiber=5.9,  sugar=22.1, sodium_mg=147,  category="snacks"),
    dict(name="Rice Cakes, Plain",           brand="Lundberg",        barcode=None,           calories_per_100g=392, serving_size_g=9,   carbohydrates=83.3, protein=8.3,  fat=2.5,  fiber=1.7,  sugar=0,    sodium_mg=17,   category="snacks"),
    dict(name="Pretzels, Thin Twist",        brand="Snyder's",        barcode=None,           calories_per_100g=381, serving_size_g=28,  carbohydrates=78.6, protein=9.5,  fat=4.8,  fiber=3.3,  sugar=2.4,  sodium_mg=786,  category="snacks"),
    dict(name="Popcorn, Air Popped",         brand=None,              barcode=None,           calories_per_100g=387, serving_size_g=8,   carbohydrates=77.9, protein=12.0, fat=4.3,  fiber=14.5, sugar=0.9,  sodium_mg=8,    category="snacks"),
    dict(name="Dark Chocolate 70%",          brand="Lindt",           barcode=None,           calories_per_100g=598, serving_size_g=28,  carbohydrates=45.9, protein=7.4,  fat=42.6, fiber=11.0, sugar=23.0, sodium_mg=9,    category="snacks"),
    dict(name="Granola, Low Sugar",          brand="Bear Naked",      barcode=None,           calories_per_100g=460, serving_size_g=47,  carbohydrates=64.0, protein=10.0, fat=18.0, fiber=5.0,  sugar=12.0, sodium_mg=90,   category="snacks"),
    dict(name="Beef Jerky, Original",        brand="Jack Link's",     barcode=None,           calories_per_100g=254, serving_size_g=28,  carbohydrates=11.3, protein=28.2, fat=7.0,  fiber=0.4,  sugar=8.5,  sodium_mg=508,  category="snacks"),

    # ── Prepared / Fast Foods ────────────────────────────────────────────────
    dict(name="Egg Burrito, Breakfast",      brand=None,              barcode=None,           calories_per_100g=165, serving_size_g=217, carbohydrates=28.0, protein=10.0, fat=5.5,  fiber=2.0,  sugar=2.5,  sodium_mg=480,  category="prepared"),
    dict(name="Chicken Burrito Bowl (no rice)", brand="Chipotle",     barcode=None,           calories_per_100g=127, serving_size_g=385, carbohydrates=19.0, protein=28.0, fat=9.0,  fiber=7.0,  sugar=3.0,  sodium_mg=985,  category="prepared"),
    dict(name="Turkey & Veggie Wrap",        brand=None,              barcode=None,           calories_per_100g=165, serving_size_g=200, carbohydrates=25.0, protein=18.0, fat=4.5,  fiber=3.5,  sugar=3.5,  sodium_mg=680,  category="prepared"),
    dict(name="Mixed Nuts, Unsalted",        brand="Planters",        barcode=None,           calories_per_100g=607, serving_size_g=30,  carbohydrates=16.5, protein=15.0, fat=54.4, fiber=5.2,  sugar=3.4,  sodium_mg=4,    category="nuts_seeds"),

    # ── Supplements ──────────────────────────────────────────────────────────
    dict(name="Creatine Monohydrate",        brand="Optimum Nutrition",barcode=None,          calories_per_100g=0,   serving_size_g=5,   carbohydrates=0,    protein=0,    fat=0,    fiber=0,    sugar=0,    sodium_mg=0,    category="supplements"),
    dict(name="BCAA Powder",                 brand="Xtend",           barcode=None,           calories_per_100g=50,  serving_size_g=14,  carbohydrates=1.0,  protein=7.0,  fat=0,    fiber=0,    sugar=0,    sodium_mg=270,  category="supplements"),
    dict(name="Pre-Workout, Fruit Punch",    brand="C4",              barcode=None,           calories_per_100g=167, serving_size_g=6,   carbohydrates=7.0,  protein=0,    fat=0,    fiber=0,    sugar=0,    sodium_mg=160,  category="supplements"),
    dict(name="Fish Oil Capsule",            brand="Nordic Naturals", barcode=None,           calories_per_100g=897, serving_size_g=4,   carbohydrates=0,    protein=0,    fat=99.0, fiber=0,    sugar=0,    sodium_mg=0,    category="fats"),
]


# ---------------------------------------------------------------------------
# Supabase helpers
# ---------------------------------------------------------------------------

def svc_headers(extra: Optional[dict] = None) -> dict:
    h = {
        "apikey":        SUPABASE_SVC_KEY,
        "Authorization": f"Bearer {SUPABASE_SVC_KEY}",
    }
    if extra:
        h.update(extra)
    return h


def upsert_foods(foods: list[dict]) -> None:
    print(f"\n[Upload] Upserting {len(foods)} foods to Supabase …")
    headers = svc_headers({
        "Content-Type": "application/json",
        "Prefer":       "resolution=merge-duplicates,return=minimal",
    })
    # on_conflict=name requires a UNIQUE constraint on the name column
    endpoint = f"{REST_BASE}/foods?on_conflict=name"

    # Add metadata fields
    records = []
    for f in foods:
        r = dict(f)
        r["is_verified"] = True
        r["data_source"] = "rpt"
        # Keep barcode key in every row (PostgREST requires uniform keys per batch)
        # None becomes JSON null, which the DB accepts fine
        if "barcode" not in r:
            r["barcode"] = None
        records.append(r)

    total = 0
    for i in range(0, len(records), UPSERT_BATCH):
        batch = records[i: i + UPSERT_BATCH]
        r = requests.post(endpoint, headers=headers, json=batch, timeout=60)
        if r.status_code not in (200, 201):
            print(f"  ✗ Batch {i // UPSERT_BATCH + 1} failed: {r.status_code} {r.text[:200]}")
        else:
            total += len(batch)
            print(f"  ✓ Batch {i // UPSERT_BATCH + 1}: {len(batch)} foods upserted ({total}/{len(records)})")

    print(f"\nDone. {total}/{len(records)} foods uploaded.")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Seed Supabase foods table from SampleFoodData.swift")
    parser.add_argument("--dry-run", action="store_true", help="Print JSON without uploading")
    args = parser.parse_args()

    print("=" * 60)
    print("  Foods Seed Script")
    print(f"  {len(FOODS)} curated foods")
    print("=" * 60)

    if args.dry_run:
        print("\n[Dry run] First 3 foods:")
        for f in FOODS[:3]:
            print(json.dumps(f, indent=2))
        print(f"\nTotal: {len(FOODS)} foods (not uploaded)")
        return

    if not SUPABASE_SVC_KEY:
        print("Error: DB_SERVICE_ROLE_KEY environment variable is required")
        sys.exit(1)

    upsert_foods(FOODS)


if __name__ == "__main__":
    main()
