#!/usr/bin/env python3
"""
seed_anime_plans.py — Upsert anime workout plans to Supabase.

Usage:
    # Set credentials (DB_SERVICE_ROLE_KEY is required)
    export SUPABASE_URL="https://erghbsnxtsbnmfuycnyb.supabase.co"
    export DB_SERVICE_ROLE_KEY="<your-service-role-key>"

    # Dry run (validate data only)
    python3 seed_anime_plans.py --dry-run

    # Seed / re-seed
    python3 seed_anime_plans.py

    # Force re-seed even if rows exist
    python3 seed_anime_plans.py --force
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

SUPABASE_URL    = os.environ.get("SUPABASE_URL", "https://erghbsnxtsbnmfuycnyb.supabase.co")
SUPABASE_SVC_KEY = os.environ.get("DB_SERVICE_ROLE_KEY", "")
REST_BASE       = f"{SUPABASE_URL}/rest/v1"
UPSERT_BATCH    = 10    # small batches — these payloads are large (JSONB)

# ---------------------------------------------------------------------------
# Plan data — mirrors AnimeWorkouts.swift exactly
# weekly_schedule: 7-element list (index 0 = Monday)
#   each day: { dayName, focus, isRest, exercises[], questTitle, questDetails, xpReward }
#   exercise:  { name, sets, reps, restSeconds, notes }
# ---------------------------------------------------------------------------

def ex(name: str, sets: int, reps: str, restSeconds: int, notes: str = "") -> dict:
    return {"name": name, "sets": sets, "reps": reps, "restSeconds": restSeconds, "notes": notes}

def day(dayName: str, focus: str, isRest: bool, exercises: list,
        questTitle: str, questDetails: str, xpReward: int) -> dict:
    return {
        "dayName": dayName, "focus": focus, "isRest": isRest,
        "exercises": exercises,
        "questTitle": questTitle, "questDetails": questDetails, "xpReward": xpReward,
    }

PLANS: list[dict] = [
    # -------------------------------------------------------------------------
    # Saitama — One Punch Man
    # -------------------------------------------------------------------------
    {
        "plan_key": "saitama",
        "character_name": "Saitama",
        "anime": "One Punch Man",
        "tagline": "Become so strong it stops being fun.",
        "description": "100 push-ups, 100 sit-ups, 100 squats, and a 10 km run — every single day, no days off. Simple, merciless, and the reason Saitama lost his hair. Pure bodyweight volume.",
        "difficulty": "beginner",
        "accent_color": "yellow",
        "icon_symbol": "bolt.fill",
        "target_gender": "male",
        "sort_order": 0,
        "daily_calories": 2200, "protein_grams": 140, "carb_grams": 270, "fat_grams": 60, "water_glasses": 10,
        "meal_prep_tips": [
            "Batch cook rice and chicken at the start of the week",
            "Keep boiled eggs on hand for fast protein between sessions",
            "Eat a banana + peanut butter 30 min before the run",
            "Hydrate aggressively — 10 km daily dehydrates fast",
        ],
        "avoid_list": ["Alcohol", "Fried food", "Energy drinks", "Processed snacks"],
        "weekly_schedule": [
            day("Monday",    "Full Body", False, [ex("Push-Ups", 10, "10", 30, "Chest to floor, full lockout"), ex("Sit-Ups", 10, "10", 30, "Hands behind head, full crunch"), ex("Bodyweight Squat", 10, "10", 30, "Below parallel, drive through heels"), ex("Running", 1, "10 km", 0, "Steady pace, no stopping")], "Saitama Protocol — Day 1", "100 push-ups. 100 sit-ups. 100 squats. 10 km run. No AC. No heater. No excuses.", 120),
            day("Tuesday",   "Full Body", False, [ex("Push-Ups", 10, "10", 30), ex("Sit-Ups", 10, "10", 30), ex("Bodyweight Squat", 10, "10", 30), ex("Running", 1, "10 km", 0)], "Saitama Protocol — Day 2", "Same as yesterday. Same as tomorrow. Consistency is the secret weapon.", 120),
            day("Wednesday", "Full Body", False, [ex("Push-Ups", 10, "10", 30), ex("Sit-Ups", 10, "10", 30), ex("Bodyweight Squat", 10, "10", 30), ex("Running", 1, "10 km", 0)], "Saitama Protocol — Day 3", "The hero who does it anyway. Complete the protocol.", 120),
            day("Thursday",  "Full Body", False, [ex("Push-Ups", 10, "10", 30), ex("Sit-Ups", 10, "10", 30), ex("Bodyweight Squat", 10, "10", 30), ex("Running", 1, "10 km", 0)], "Saitama Protocol — Day 4", "Day 4. Still going.", 120),
            day("Friday",    "Full Body", False, [ex("Push-Ups", 10, "10", 30), ex("Sit-Ups", 10, "10", 30), ex("Bodyweight Squat", 10, "10", 30), ex("Running", 1, "10 km", 0)], "Saitama Protocol — Day 5", "Five days straight. Weekend means nothing.", 120),
            day("Saturday",  "Full Body", False, [ex("Push-Ups", 10, "10", 30), ex("Sit-Ups", 10, "10", 30), ex("Bodyweight Squat", 10, "10", 30), ex("Running", 1, "10 km", 0)], "Saitama Protocol — Day 6", "No days off. That's the whole point.", 120),
            day("Sunday",    "Full Body", False, [ex("Push-Ups", 10, "10", 30), ex("Sit-Ups", 10, "10", 30), ex("Bodyweight Squat", 10, "10", 30), ex("Running", 1, "10 km", 0)], "Saitama Protocol — Day 7", "Seven days. One week down. Start again tomorrow.", 150),
        ],
    },
    # -------------------------------------------------------------------------
    # Goku — Dragon Ball Z
    # -------------------------------------------------------------------------
    {
        "plan_key": "goku",
        "character_name": "Goku",
        "anime": "Dragon Ball Z",
        "tagline": "Push past your limits. Every. Single. Day.",
        "description": "Goku trains under 100x gravity. We'll start lighter. Heavy compound lifts, high volume, high frequency. Massive caloric surplus to fuel muscle growth. Built for someone who refuses to stay at their current level.",
        "difficulty": "advanced",
        "accent_color": "orange",
        "icon_symbol": "flame.fill",
        "target_gender": "male",
        "sort_order": 1,
        "daily_calories": 3500, "protein_grams": 220, "carb_grams": 420, "fat_grams": 90, "water_glasses": 12,
        "meal_prep_tips": [
            "6 meals a day — never go more than 3 hours without eating",
            "Post-workout: 50 g whey + 2 bananas within 30 minutes",
            "Overnight oats with mass gainer before bed",
            "Don't fear carbs — they're your training fuel",
        ],
        "avoid_list": ["Cutting calories", "Skipping meals", "Long cardio sessions", "Alcohol"],
        "weekly_schedule": [
            day("Monday",    "Chest & Triceps", False, [ex("Barbell Bench Press", 5, "5", 120, "Touch chest, full lockout"), ex("Incline Dumbbell Press", 4, "8-10", 90), ex("Cable Fly", 3, "12", 60), ex("Close-Grip Bench Press", 4, "8", 90), ex("Tricep Pushdown", 3, "12", 60)], "Saiyan Chest Day", "Every rep is a step toward your next transformation. Push like your power level depends on it.", 130),
            day("Tuesday",   "Back & Biceps",  False, [ex("Deadlift", 5, "5", 180, "Drive through the floor"), ex("Weighted Pull-Ups", 4, "6-8", 120), ex("Barbell Row", 4, "8", 90), ex("Face Pulls", 3, "15", 60), ex("Barbell Curl", 4, "10", 60)], "Saiyan Back Day", "Your back is your power base. Build it like you're training for the Cell Games.", 140),
            day("Wednesday", "Legs",           False, [ex("Barbell Back Squat", 5, "5", 180, "Olympic depth"), ex("Romanian Deadlift", 4, "8", 120), ex("Leg Press", 4, "12", 90), ex("Walking Lunges", 3, "20", 60), ex("Calf Raise", 5, "15", 45)], "Saiyan Leg Day", "Legs win fights. Goku never skips. Neither do you.", 150),
            day("Thursday",  "Shoulders",      False, [ex("Overhead Press", 5, "5", 120), ex("Arnold Press", 4, "10", 90), ex("Lateral Raise", 4, "15", 60), ex("Rear Delt Fly", 3, "15", 60), ex("Shrugs", 3, "12", 60)], "Saiyan Shoulder Day", "Boulder shoulders built for carrying the world — or just massive gravity weights.", 130),
            day("Friday",    "Full Body Power", False, [ex("Power Clean", 5, "3", 180, "Explosive from floor"), ex("Push Press", 4, "6", 120), ex("Weighted Dips", 4, "8", 90), ex("Barbell Row", 4, "8", 90), ex("Ab Wheel Rollout", 3, "10", 60)], "Saiyan Power Day", "Explosive power. This is the session that breaks ceilings.", 140),
            day("Saturday",  "Active Recovery", True, [], "Rest Day", "Even Goku sleeps. Active recovery — light walk, stretching, mobility work.", 40),
            day("Sunday",    "Active Recovery", True, [], "Rest & Grow", "Growth happens during rest. Eat big, sleep big, come back bigger.", 40),
        ],
    },
    # -------------------------------------------------------------------------
    # Levi — Attack on Titan
    # -------------------------------------------------------------------------
    {
        "plan_key": "levi",
        "character_name": "Levi",
        "anime": "Attack on Titan",
        "tagline": "Humanity's strongest doesn't take days off.",
        "description": "Lean, fast, explosively powerful. Levi's training is functional — calisthenics, speed work, and core that could cut through titan nape. No bulk, just elite conditioning.",
        "difficulty": "intermediate",
        "accent_color": "gray",
        "icon_symbol": "wind",
        "target_gender": None,
        "sort_order": 2,
        "daily_calories": 2600, "protein_grams": 180, "carb_grams": 290, "fat_grams": 70, "water_glasses": 9,
        "meal_prep_tips": [
            "High protein, moderate carbs — maintain lean mass",
            "Pre-workout: oatmeal + coffee 45 minutes before",
            "Post-workout: chicken + rice or sweet potato within 1 hour",
            "Minimize processed sugar — you need clean fuel for explosive work",
        ],
        "avoid_list": ["Processed sugar", "Alcohol", "Heavy late-night meals", "Junk food"],
        "weekly_schedule": [
            day("Monday",    "Upper Body Strength", False, [ex("Pull-Ups", 5, "Max", 90, "Full dead hang to chin over bar"), ex("Pike Push-Ups", 4, "12", 60), ex("Archer Push-Ups", 3, "8 each", 60), ex("Hanging Leg Raise", 4, "12", 60), ex("Planche Lean", 3, "20 sec", 45)], "Vertical Supremacy", "Every rep is practice for the day you need to move faster than anyone else.", 130),
            day("Tuesday",   "Speed & Conditioning", False, [ex("Sprint Intervals", 8, "30 sec on / 30 sec off", 0, "100% effort on sprints"), ex("Box Jumps", 4, "10", 60), ex("Burpees", 3, "15", 60), ex("Jump Rope", 3, "2 min", 45)], "Speed Training", "Humanity's strongest isn't just powerful — they're faster than you can see.", 125),
            day("Wednesday", "Core & Mobility", False, [ex("Dragon Flag", 4, "6", 90, "Slow and controlled"), ex("L-Sit Hold", 4, "20 sec", 60), ex("Russian Twist", 3, "20", 45), ex("Dead Bug", 3, "10 each", 45), ex("Hollow Body Hold", 3, "30 sec", 45)], "Core Iron", "Your core is the chain linking every movement. Forge it.", 110),
            day("Thursday",  "Lower Body Power", False, [ex("Pistol Squat", 4, "6 each", 90, "Controlled descent"), ex("Nordic Curl", 3, "5", 120), ex("Jump Squat", 4, "10", 60), ex("Single-Leg Deadlift", 3, "8 each", 60), ex("Calf Raise", 4, "20", 30)], "Lower Power", "Speed comes from the legs. Build them like your survival depends on it.", 130),
            day("Friday",    "Full Body Circuit", False, [ex("Muscle-Up", 4, "5", 120, "Strict form"), ex("Handstand Push-Up", 3, "5", 90), ex("One-Arm Row", 4, "8 each", 60), ex("GHD Sit-Up", 3, "12", 60), ex("Sprint", 5, "100 m", 90)], "Elite Circuit", "This is what sets Humanity's Strongest apart. Complete it without complaint.", 150),
            day("Saturday",  "Active Recovery", True, [], "Recovery", "Light movement, stretching. Stay sharp, stay ready.", 40),
            day("Sunday",    "Rest", True, [], "Rest Day", "Rest isn't weakness. It's when adaptation happens.", 40),
        ],
    },
    # -------------------------------------------------------------------------
    # Rock Lee — Naruto
    # -------------------------------------------------------------------------
    {
        "plan_key": "rockLee",
        "character_name": "Rock Lee",
        "anime": "Naruto",
        "tagline": "Hard work will always overtake natural talent.",
        "description": "No shortcuts. Pure taijutsu — calisthenics and weighted training until your body refuses and then you do more. Rock Lee couldn't use ninjutsu, so he became a taijutsu master through sheer will.",
        "difficulty": "advanced",
        "accent_color": "green",
        "icon_symbol": "figure.martial.arts",
        "target_gender": None,
        "sort_order": 3,
        "daily_calories": 2800, "protein_grams": 175, "carb_grams": 350, "fat_grams": 70, "water_glasses": 10,
        "meal_prep_tips": [
            "Eat to support the volume — this is high-rep territory",
            "Brown rice and sweet potato are your carb staples",
            "Green tea pre-workout for focus without the crash",
            "Protein shake immediately post-session",
        ],
        "avoid_list": ["Junk food", "Alcohol", "Skipping meals", "Sitting still"],
        "weekly_schedule": [
            day("Monday",    "Leg Endurance",      False, [ex("Bodyweight Squat", 10, "100", 60, "No stopping within sets"), ex("Walking Lunges", 5, "40", 60), ex("Jump Squat", 5, "20", 60), ex("Calf Raise", 5, "100", 30), ex("Wall Sit", 3, "60 sec", 60)], "The Eight Gates — Foundation", "Lee trains with ankle weights every day. Today we build the base.", 140),
            day("Tuesday",   "Upper Endurance",    False, [ex("Push-Ups", 10, "50", 45), ex("Pull-Ups", 5, "20", 90, "Kip allowed"), ex("Dips", 5, "25", 60), ex("Handstand Hold", 4, "30 sec", 60), ex("Diamond Push-Ups", 5, "20", 45)], "Taijutsu Arms", "Your arms are your weapons. Forge them with volume.", 140),
            day("Wednesday", "Speed Drills",       False, [ex("Sprint", 10, "50 m", 30, "Explosive start"), ex("Shadow Boxing", 5, "2 min", 45), ex("Jump Rope", 5, "3 min", 60), ex("Agility Ladder", 4, "60 sec", 45)], "Speed Work", "You can't hit what you can't catch. Train to become uncatchable.", 130),
            day("Thursday",  "Weighted Strength",  False, [ex("Weighted Pull-Up", 5, "10", 90, "Start light, focus form"), ex("Weighted Dip", 5, "10", 90), ex("Barbell Squat", 5, "10", 120), ex("Farmer's Carry", 4, "50 m", 60), ex("Turkish Get-Up", 3, "5 each", 90)], "Iron Will", "Add weight to build strength. Lee trained with weights so heavy Gai-sensei worried.", 150),
            day("Friday",    "Endurance Circuit",  False, [ex("Burpees", 5, "20", 60), ex("Mountain Climbers", 5, "40", 45), ex("Bear Crawl", 4, "30 m", 60), ex("Plank", 4, "60 sec", 45), ex("V-Ups", 4, "20", 45)], "Circuit of Youth", "Youth! The circuit doesn't end until you've given everything.", 145),
            day("Saturday",  "Technique & Form",   False, [ex("Handstand Practice", 4, "60 sec attempt", 90), ex("Pistol Squat", 4, "10 each", 60), ex("Single-Leg Calf Raise", 4, "30 each", 45), ex("L-Sit", 3, "20 sec", 60)], "The Beautiful Green Beast", "Perfect technique. Every rep deliberate.", 110),
            day("Sunday",    "Active Recovery",    True, [], "Rest Day", "Even Lee rests — but he does his pushups first.", 50),
        ],
    },
    # -------------------------------------------------------------------------
    # Endeavor — My Hero Academia
    # -------------------------------------------------------------------------
    {
        "plan_key": "endeavor",
        "character_name": "Endeavor",
        "anime": "My Hero Academia",
        "tagline": "Number one means no excuses.",
        "description": "The top-ranked Pro Hero's regimen is about building maximum power. Heavy compound lifts, brutal intensity, minimal rest. Endeavor didn't climb to the top by being comfortable.",
        "difficulty": "elite",
        "accent_color": "red",
        "icon_symbol": "flame.circle.fill",
        "target_gender": "male",
        "sort_order": 4,
        "daily_calories": 4000, "protein_grams": 260, "carb_grams": 450, "fat_grams": 110, "water_glasses": 12,
        "meal_prep_tips": [
            "Eat 5-6 meals — you need the calories for this volume",
            "Pre-workout: large carb meal 2 hours before",
            "Intra-workout: BCAAs or electrolyte drink",
            "Post-workout window: 60 g fast carbs + 40 g protein immediately",
        ],
        "avoid_list": ["Skipping meals", "Low-calorie diets", "Alcohol", "Weak excuses"],
        "weekly_schedule": [
            day("Monday",    "Chest Max",   False, [ex("Barbell Bench Press", 6, "5", 120, "Controlled negative, explosive positive"), ex("Weighted Dip", 5, "8", 90), ex("Incline Press", 4, "8", 90), ex("Cable Crossover", 4, "12", 60), ex("Push-Up Burnout", 1, "Max", 0)], "Flame Chest", "The top hero trains with the top intensity. No warmup excuses — get to work.", 160),
            day("Tuesday",   "Back Max",    False, [ex("Deadlift", 6, "3", 180, "Max weight you can hold form"), ex("Weighted Pull-Up", 5, "6", 120), ex("T-Bar Row", 4, "8", 90), ex("Seated Cable Row", 4, "10", 75), ex("Straight-Arm Pulldown", 3, "12", 60)], "Number One Back", "A hero's back must be strong enough to bear every burden.", 160),
            day("Wednesday", "Legs Max",    False, [ex("Barbell Squat", 6, "5", 180, "Olympic depth, no quarter"), ex("Leg Press", 5, "10", 90), ex("Romanian Deadlift", 4, "8", 120), ex("Hack Squat", 4, "10", 90), ex("Standing Calf Raise", 5, "15", 45)], "Pillar Legs", "The top hero stands on legs that never give out.", 165),
            day("Thursday",  "Shoulders",   False, [ex("Overhead Press", 6, "5", 120), ex("Push Press", 4, "6", 120), ex("Lateral Raise", 5, "15", 45), ex("Face Pull", 4, "20", 45), ex("Upright Row", 4, "10", 75)], "Iron Shoulders", "Wide, powerful, dominant. Shoulders built for authority.", 150),
            day("Friday",    "Full Power",  False, [ex("Clean and Jerk", 5, "3", 180, "Explosive full body"), ex("Farmer's Walk", 4, "50 m", 90), ex("Weighted Carry", 3, "40 m", 90), ex("Battle Rope", 3, "30 sec", 60), ex("Heavy Ab Work", 4, "15", 60)], "Total Dominance", "Friday means full power output. This is what number one looks like.", 170),
            day("Saturday",  "Active Recovery", True, [], "Recovery", "Light movement, foam rolling, mobility. The elite recover as hard as they train.", 50),
            day("Sunday",    "Rest",        True, [], "Rest Day", "Even Endeavor needs rest. Growth requires recovery.", 40),
        ],
    },
    # -------------------------------------------------------------------------
    # Asta — Black Clover
    # -------------------------------------------------------------------------
    {
        "plan_key": "asta",
        "character_name": "Asta",
        "anime": "Black Clover",
        "tagline": "No magic? No problem. Outwork everyone.",
        "description": "Asta has no magic in a world built on it. His answer? Become the most physically developed person alive. Pure grind, anti-magic sword training, and the kind of persistence that makes mages nervous.",
        "difficulty": "intermediate",
        "accent_color": "purple",
        "icon_symbol": "dumbbell.fill",
        "target_gender": None,
        "sort_order": 5,
        "daily_calories": 2900, "protein_grams": 185, "carb_grams": 360, "fat_grams": 75, "water_glasses": 10,
        "meal_prep_tips": [
            "Volume eating — you train twice as hard so you eat twice as much",
            "Sweet potatoes and brown rice for sustained energy",
            "Pre-workout meal 1.5 hours before training",
            "Casein protein before bed for overnight recovery",
        ],
        "avoid_list": ["Making excuses", "Skipping training", "Alcohol", "Giving up"],
        "weekly_schedule": [
            day("Monday",    "Full Body Strength", False, [ex("Barbell Squat", 4, "8", 90), ex("Bench Press", 4, "8", 90), ex("Barbell Row", 4, "8", 90), ex("Overhead Press", 3, "10", 75), ex("Pull-Ups", 3, "Max", 75)], "Anti-Magic Training Day 1", "No shortcuts. You have no magic — you have work. Do the work.", 130),
            day("Tuesday",   "Conditioning",       False, [ex("Tire Flip", 4, "10", 90, "Or heavy medicine ball slam"), ex("Sled Push", 4, "30 m", 90), ex("Battle Rope", 4, "30 sec", 60), ex("Box Jump", 4, "10", 60), ex("Sprint", 6, "100 m", 60)], "Peasant Power", "You didn't grow up with advantages. You grew up with work ethic.", 135),
            day("Wednesday", "Skill & Core",       False, [ex("Single-Arm Dumbbell Row", 4, "12 each", 60), ex("Pallof Press", 4, "12 each", 60), ex("Cable Woodchop", 3, "12 each", 60), ex("Hanging Knee Raise", 4, "15", 60), ex("Plank Circuit", 3, "45 sec each side", 45)], "Core Discipline", "The body follows the will. Train your core and your will together.", 115),
            day("Thursday",  "Lower Body",         False, [ex("Deadlift", 4, "6", 120), ex("Bulgarian Split Squat", 4, "10 each", 75), ex("Glute Bridge", 4, "15", 45), ex("Step-Up", 3, "12 each", 60), ex("Jump Rope", 3, "3 min", 60)], "Foundation Day", "Powerful legs close the gap between you and your opponent.", 130),
            day("Friday",    "Upper Hypertrophy",  False, [ex("Incline Press", 4, "10", 75), ex("Cable Fly", 4, "12", 60), ex("Lat Pulldown", 4, "12", 60), ex("Face Pull", 3, "20", 45), ex("Hammer Curl", 3, "12", 45), ex("Tricep Extension", 3, "15", 45)], "Forging the Body", "Where magic fails, muscle prevails. Build the armour.", 130),
            day("Saturday",  "Active Recovery",    True, [], "Recovery Day", "Rest, stretch, and visualize tomorrow's training.", 40),
            day("Sunday",    "Rest",               True, [], "Rest Day", "Tomorrow you train again. Rest is not weakness — it's preparation.", 40),
        ],
    },
    # -------------------------------------------------------------------------
    # Rudeus — Mushoku Tensei
    # -------------------------------------------------------------------------
    {
        "plan_key": "rudeus",
        "character_name": "Rudeus Greyrat",
        "anime": "Mushoku Tensei",
        "tagline": "A second chance — don't waste it.",
        "description": "Reincarnated into a world of magic and swords, Rudeus rebuilds himself from the ground up. Balanced training — strength, flexibility, and endurance. For those starting over and doing it right this time.",
        "difficulty": "beginner",
        "accent_color": "blue",
        "icon_symbol": "arrow.clockwise.circle.fill",
        "target_gender": "male",
        "sort_order": 6,
        "daily_calories": 2400, "protein_grams": 155, "carb_grams": 300, "fat_grams": 65, "water_glasses": 8,
        "meal_prep_tips": [
            "Consistent meal times — structure matters for building habits",
            "Lean proteins at every meal: chicken, fish, eggs",
            "Don't skip breakfast — it sets the energy for the day",
            "Meal prep Sunday to remove daily decision fatigue",
        ],
        "avoid_list": ["Isolation", "Skipping meals", "Procrastination", "Junk food"],
        "weekly_schedule": [
            day("Monday",    "Foundation Strength", False, [ex("Goblet Squat", 3, "12", 60, "Learn the pattern before loading"), ex("Push-Up", 3, "15", 60), ex("Dumbbell Row", 3, "12 each", 60), ex("Romanian Deadlift", 3, "12", 60), ex("Plank", 3, "30 sec", 45)], "Building the Foundation", "In your first life you wasted time. Not this time. Every rep counts.", 110),
            day("Tuesday",   "Cardio & Flexibility", False, [ex("Brisk Walk/Light Jog", 1, "30 min", 0, "Conversational pace"), ex("Dynamic Stretching", 3, "10 each movement", 30), ex("Hip Flexor Stretch", 3, "45 sec each", 30), ex("Thoracic Rotation", 3, "10 each", 30)], "Movement Day", "The body that moves well performs well. Invest in mobility now.", 100),
            day("Wednesday", "Push Strength",        False, [ex("Bench Press", 3, "10", 75), ex("Overhead Press", 3, "10", 75), ex("Lateral Raise", 3, "15", 45), ex("Tricep Dip", 3, "10", 60), ex("Diamond Push-Up", 3, "12", 45)], "Pushing Forward", "Like learning new spells — each session compounds your power.", 110),
            day("Thursday",  "Pull & Core",          False, [ex("Lat Pulldown", 3, "12", 60), ex("Cable Row", 3, "12", 60), ex("Bicep Curl", 3, "12", 45), ex("Ab Rollout", 3, "8", 60), ex("Dead Bug", 3, "10 each", 45)], "Pull Day", "Pull your own weight first. Then more.", 110),
            day("Friday",    "Lower Body",           False, [ex("Barbell Squat", 3, "10", 90, "Add weight from Monday"), ex("Leg Press", 3, "12", 75), ex("Leg Curl", 3, "12", 60), ex("Calf Raise", 3, "20", 30), ex("Glute Bridge", 3, "15", 45)], "Leg Day", "Solid legs carry you through any world. Build them.", 115),
            day("Saturday",  "Active Recovery",      True, [], "Recovery", "Light walk or easy swim. Keep moving but let the muscles grow.", 40),
            day("Sunday",    "Rest",                 True, [], "Rest Day", "Rest is part of the program, not a break from it.", 40),
        ],
    },
    # -------------------------------------------------------------------------
    # Deku — My Hero Academia
    # -------------------------------------------------------------------------
    {
        "plan_key": "deku",
        "character_name": "Izuku Midoriya",
        "anime": "My Hero Academia",
        "tagline": "A hero's body is built before the power.",
        "description": "Before All Might gave Deku One For All, he spent months transforming a weak body into one worthy of receiving the power. This is that program — building the base so you're ready for whatever power comes next.",
        "difficulty": "beginner",
        "accent_color": "green",
        "icon_symbol": "star.fill",
        "target_gender": "male",
        "sort_order": 7,
        "daily_calories": 2500, "protein_grams": 160, "carb_grams": 310, "fat_grams": 68, "water_glasses": 9,
        "meal_prep_tips": [
            "Track your nutrition for the first 2 weeks — awareness matters",
            "High-protein breakfast to start each training day right",
            "Pack your lunch — you can't rely on convenience food",
            "Eat your last meal 2-3 hours before training",
        ],
        "avoid_list": ["Processed food", "Sugary drinks", "Skipping sleep", "Comparing yourself to others"],
        "weekly_schedule": [
            day("Monday",    "Full Body A",  False, [ex("Squat", 3, "10", 90, "Bodyweight or light barbell to start"), ex("Push-Up", 3, "10", 60), ex("Bent-Over Row", 3, "10", 75), ex("Overhead Press", 3, "10", 75), ex("Plank", 3, "20 sec", 45)], "Plus Ultra Day 1", "This is where heroes start — not at the top, but at the beginning. Show up.", 110),
            day("Tuesday",   "Beach Run",    False, [ex("Jog", 1, "2 km", 0, "Don't stop, don't walk"), ex("Bodyweight Squat", 2, "20", 45), ex("Burpee", 2, "10", 60), ex("Mountain Climber", 2, "20", 45)], "Conditioning Run", "All Might ran the beach. You run your route. Distance doesn't matter — consistency does.", 100),
            day("Wednesday", "Full Body B",  False, [ex("Deadlift", 3, "8", 90, "Light — focus form"), ex("Incline Push-Up", 3, "12", 60), ex("Lat Pulldown", 3, "12", 60), ex("Dumbbell Curl", 3, "12", 45), ex("Side Plank", 3, "20 sec each", 45)], "Plus Ultra Day 2", "Every hero has a day they wanted to quit. Today isn't that day.", 110),
            day("Thursday",  "Rest/Light",   True, [], "Active Rest", "Light stretching, walking, journaling your progress. Heroes reflect.", 40),
            day("Friday",    "Full Body C",  False, [ex("Squat", 3, "12", 90), ex("Dumbbell Bench Press", 3, "10", 75), ex("Cable Row", 3, "12", 60), ex("Arnold Press", 3, "10", 75), ex("Ab Crunch", 3, "20", 45)], "Plus Ultra Day 3", "Three sessions in. The body is adapting. Keep going.", 115),
            day("Saturday",  "Long Run",     False, [ex("Distance Run", 1, "3-4 km", 0, "Comfortable conversational pace"), ex("Cool-down Walk", 1, "10 min", 0)], "Endurance Build", "All Might cleaned that beach one load at a time. You run one kilometre at a time.", 105),
            day("Sunday",    "Rest",         True, [], "Rest Day", "Rest. Sleep. Grow. Show up Monday ready to be better.", 40),
        ],
    },
    # -------------------------------------------------------------------------
    # Maki — Jujutsu Kaisen
    # -------------------------------------------------------------------------
    {
        "plan_key": "maki",
        "character_name": "Maki Zenin",
        "anime": "Jujutsu Kaisen",
        "tagline": "No cursed energy. Pure strength. Pure will.",
        "description": "Maki was born into a sorcerer clan with no cursed energy. She compensated by becoming physically elite. Weapon training, explosive power, and endurance that makes cursed spirits hesitate.",
        "difficulty": "advanced",
        "accent_color": "green",
        "icon_symbol": "figure.fencing",
        "target_gender": "female",
        "sort_order": 8,
        "daily_calories": 2600, "protein_grams": 170, "carb_grams": 300, "fat_grams": 72, "water_glasses": 10,
        "meal_prep_tips": [
            "Lean and functional — don't bulk, fuel performance",
            "Collagen peptides in morning coffee for joint health",
            "Focus on anti-inflammatory foods: salmon, leafy greens, berries",
            "Protein within 30 minutes post-training, every session",
        ],
        "avoid_list": ["Processed food", "Sugary drinks", "Skipping sleep", "Underestimating rest"],
        "weekly_schedule": [
            day("Monday",    "Upper Power",     False, [ex("Pull-Up", 5, "Max", 90, "Dead hang — no kipping"), ex("Dumbbell Push Press", 4, "8", 90), ex("Single-Arm Cable Row", 4, "10 each", 75), ex("Pike Push-Up", 3, "12", 60), ex("Rear Delt Fly", 3, "15", 45)], "Zenin Strength — Upper", "They said you were worthless without cursed energy. Prove them wrong today.", 135),
            day("Tuesday",   "Lower Explosive", False, [ex("Trap Bar Deadlift", 5, "5", 120, "Or barbell sumo"), ex("Box Jump", 5, "5", 90, "Stick the landing"), ex("Bulgarian Split Squat", 4, "8 each", 75), ex("Nordic Hamstring Curl", 3, "5", 120), ex("Broad Jump", 4, "5", 90)], "Zenin Legs", "Explosive lower body — move faster than anyone expects.", 140),
            day("Wednesday", "Weapon Training", False, [ex("Rotational Med Ball Slam", 4, "10 each", 60), ex("Pallof Press", 4, "12 each", 60), ex("Landmine Twist", 4, "10 each", 60), ex("Turkish Get-Up", 3, "5 each", 90, "Controlled through every position"), ex("Single-Leg Romanian DL", 3, "10 each", 60)], "Weapon Drills", "A weapon is only as powerful as the person wielding it. Train the wielder.", 130),
            day("Thursday",  "Conditioning",    False, [ex("Prowler Push", 4, "30 m", 90, "Or heavy sled"), ex("Battle Rope", 4, "30 sec", 60), ex("Sandbag Carry", 4, "30 m", 60), ex("Sprint", 6, "50 m", 60), ex("Plank Variations", 3, "45 sec", 45)], "Hunter Conditioning", "A sorcerer who outran their prey. Be uncatchable.", 135),
            day("Friday",    "Full Body Skill", False, [ex("Clean", 4, "4", 120, "Learn the pattern or use dumbbell hang clean"), ex("Strict Press", 4, "6", 90), ex("Weighted Pull-Up", 4, "6", 90), ex("Pistol Squat", 3, "6 each", 75), ex("L-Sit", 3, "15 sec", 60)], "Total Skill", "Technique and strength combined. This is what elite looks like.", 145),
            day("Saturday",  "Mobility & Recovery", True, [], "Recovery", "Yoga, foam rolling, light walk. Maki's body is her weapon — maintain it.", 40),
            day("Sunday",    "Rest",            True, [], "Rest Day", "Even the best need rest. Growth is built here.", 40),
        ],
    },
    # -------------------------------------------------------------------------
    # Stars and Stripes — My Hero Academia
    # -------------------------------------------------------------------------
    {
        "plan_key": "starsAndStripes",
        "character_name": "Cathleen Bate",
        "anime": "My Hero Academia",
        "tagline": "The world's top hero doesn't leave anything on the table.",
        "description": "Star and Stripe — the #1 hero in the world. Military-grade conditioning meets elite athletic performance. Strength, speed, endurance, and the mental toughness to match. For those who want it all.",
        "difficulty": "elite",
        "accent_color": "blue",
        "icon_symbol": "star.circle.fill",
        "target_gender": "female",
        "sort_order": 9,
        "daily_calories": 3200, "protein_grams": 210, "carb_grams": 380, "fat_grams": 85, "water_glasses": 12,
        "meal_prep_tips": [
            "Military nutrition: no processed food, lean proteins, complex carbs only",
            "Every meal has protein, carbs, and vegetables — no exceptions",
            "Hydrate before you're thirsty — you don't drink water when you need it",
            "Supplement intelligently: creatine, vitamin D, omega-3s",
        ],
        "avoid_list": ["Processed food", "Alcohol", "Skipping sleep", "Mediocrity"],
        "weekly_schedule": [
            day("Monday",    "Strength A",     False, [ex("Barbell Back Squat", 5, "5", 120, "Heavy — add weight from last week"), ex("Bench Press", 5, "5", 120), ex("Weighted Pull-Up", 5, "5", 120), ex("Romanian Deadlift", 4, "8", 90), ex("Ab Wheel", 3, "10", 60)], "Star Force — Monday", "The number one hero lifts heavy on Monday. So do you.", 160),
            day("Tuesday",   "Speed & Cardio", False, [ex("Sprint Intervals", 10, "200 m fast / 200 m walk", 0), ex("Plyometric Push-Up", 4, "10", 60), ex("Lateral Bound", 4, "8 each", 60), ex("Jump Squat", 4, "10", 60)], "Air Superiority", "Fast on the ground, faster in the air. Push your speed ceiling.", 145),
            day("Wednesday", "Strength B",     False, [ex("Deadlift", 5, "5", 150), ex("Overhead Press", 5, "5", 120), ex("Barbell Row", 5, "5", 120), ex("Weighted Dip", 4, "8", 90), ex("Farmer's Walk", 3, "50 m", 90)], "Star Force — Wednesday", "Three days of elite training done right. No wasted reps.", 160),
            day("Thursday",  "Conditioning",   False, [ex("Assault Bike", 4, "3 min max effort", 180), ex("Rope Climb", 4, "2 ascents", 120, "Or lat pulldown heavy"), ex("Sled Push", 4, "40 m", 90), ex("Burpee Broad Jump", 3, "10", 75)], "Military Conditioning", "The conditioning of a world-ranked hero. Leave nothing.", 150),
            day("Friday",    "Strength C",     False, [ex("Front Squat", 4, "6", 120), ex("Incline Press", 4, "8", 90), ex("Chest-Supported Row", 4, "8", 90), ex("Landmine Press", 3, "8 each", 75), ex("RKC Plank", 3, "20 sec", 60)], "Star Force — Friday", "Five sessions. Five days. That's what the top looks like.", 160),
            day("Saturday",  "Active Recovery", True, [], "Recovery", "Long walk, swimming, yoga, or sports. Stay active, recover hard.", 50),
            day("Sunday",    "Rest",           True, [], "Rest Day", "Rest is part of the mission. Execute it.", 40),
        ],
    },
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


def upsert_plans(plans: list[dict]) -> None:
    print(f"\n[Upload] Upserting {len(plans)} anime workout plans to Supabase …")
    headers = svc_headers({
        "Content-Type": "application/json",
        "Prefer":       "resolution=merge-duplicates,return=minimal",
    })
    endpoint = f"{REST_BASE}/anime_workout_plans?on_conflict=plan_key"

    records = []
    for p in plans:
        r = dict(p)
        r["is_active"]   = True
        r["data_source"] = "rpt"
        # Serialise weekly_schedule to JSON string (PostgREST accepts native JSON)
        r["weekly_schedule"] = r["weekly_schedule"]  # already a list — PostgREST handles it
        records.append(r)

    total = 0
    for i in range(0, len(records), UPSERT_BATCH):
        batch = records[i: i + UPSERT_BATCH]
        resp = requests.post(endpoint, headers=headers, json=batch, timeout=60)
        if resp.status_code not in (200, 201):
            print(f"  ✗ Batch {i // UPSERT_BATCH + 1} failed: {resp.status_code} {resp.text[:300]}")
            sys.exit(1)
        total += len(batch)
        print(f"  ✓ Batch {i // UPSERT_BATCH + 1}: {len(batch)} plans upserted ({total}/{len(records)})")

    print(f"\nDone. {total}/{len(records)} plans uploaded.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Seed anime workout plans to Supabase")
    parser.add_argument("--dry-run", action="store_true", help="Validate and print data without uploading")
    parser.add_argument("--force",   action="store_true", help="Re-seed even if rows exist (default behaviour — upsert is idempotent)")
    args = parser.parse_args()

    print("=" * 60)
    print("  Anime Workout Plans Seed Script")
    print(f"  {len(PLANS)} plans")
    print("=" * 60)

    if not SUPABASE_SVC_KEY:
        print("Error: DB_SERVICE_ROLE_KEY environment variable is required", file=sys.stderr)
        sys.exit(1)

    if args.dry_run:
        print("\n[Dry Run] Plans that would be upserted:")
        for p in PLANS:
            days = len(p["weekly_schedule"])
            print(f"  • {p['plan_key']:20s}  {p['character_name']:20s}  {p['difficulty']:14s}  {days} days")
        print(f"\nTotal: {len(PLANS)} plans — no data uploaded.")
        return

    upsert_plans(PLANS)


if __name__ == "__main__":
    main()
