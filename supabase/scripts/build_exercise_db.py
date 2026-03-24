#!/usr/bin/env python3
"""
Exercise Database Pipeline
==========================
Fetches exercises from three public-domain sources, merges and deduplicates
them, then upserts into Supabase. Run this once to populate the table, then
again whenever you want to refresh.

Sources
-------
1. yuhonas/free-exercise-db  — 870+ exercises with static images (public domain)
   https://github.com/yuhonas/free-exercise-db
2. wrkout/exercises.json     — structured exercises with instructions (Unlicense)
   https://github.com/wrkout/exercises.json
3. ExerciseDB/exercisedb-api — 1,300+ exercises with GIFs (MIT/open data)
   https://github.com/yuhonas/free-exercise-db (same data, different GIF field)
   GIFs: https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/<id>.gif

Requirements
------------
    pip install requests supabase python-slugify

Usage
-----
    export SUPABASE_URL="https://erghbsnxtsbnmfuycnyb.supabase.co"
    export SUPABASE_SERVICE_ROLE_KEY="<your-service-role-key>"
    python3 build_exercise_db.py

    # Dry-run (print merged exercises, no upload):
    python3 build_exercise_db.py --dry-run

    # Skip specific sources:
    python3 build_exercise_db.py --skip-wrkout --skip-exercisedb
"""

import argparse
import json
import os
import re
import sys
import unicodedata
from pathlib import Path
from typing import Optional

import requests

# ---------------------------------------------------------------------------
# Optional: use supabase-py if installed, else fall back to raw REST
# ---------------------------------------------------------------------------
try:
    from supabase import create_client, Client as SupabaseClient
    HAS_SUPABASE_PY = True
except ImportError:
    HAS_SUPABASE_PY = False

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://erghbsnxtsbnmfuycnyb.supabase.co")
SUPABASE_SERVICE_KEY = os.environ.get("DB_SERVICE_ROLE_KEY", "")

# GitHub raw content base URLs
FREE_EXERCISE_DB_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main"
FREE_EXERCISE_DB_INDEX = f"{FREE_EXERCISE_DB_BASE}/dist/exercises.json"
FREE_EXERCISE_DB_IMAGE_BASE = f"{FREE_EXERCISE_DB_BASE}/exercises"

WRKOUT_INDEX = "https://raw.githubusercontent.com/wrkout/exercises.json/master/exercises"
WRKOUT_MANIFEST = f"{WRKOUT_INDEX}/_index.json"

# Batch size for Supabase upsert
UPSERT_BATCH = 100


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def slugify(text: str) -> str:
    """Create a URL-safe slug from a name."""
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii")
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9\s-]", "", text)
    text = re.sub(r"[\s_-]+", "-", text)
    text = re.sub(r"^-+|-+$", "", text)
    return text


def normalise_muscle(name: Optional[str]) -> str:
    """Map varied muscle-group names to a consistent vocabulary."""
    if not name:
        return ""
    n = name.lower().strip()
    mapping = {
        "lats": "lats",
        "latissimus dorsi": "lats",
        "traps": "traps",
        "trapezius": "traps",
        "quads": "quadriceps",
        "quadriceps": "quadriceps",
        "hamstrings": "hamstrings",
        "glutes": "glutes",
        "glute": "glutes",
        "gluteus maximus": "glutes",
        "calves": "calves",
        "calf": "calves",
        "gastrocnemius": "calves",
        "chest": "chest",
        "pecs": "chest",
        "pectorals": "chest",
        "pectoralis major": "chest",
        "shoulders": "shoulders",
        "deltoids": "shoulders",
        "deltoid": "shoulders",
        "anterior deltoid": "shoulders",
        "biceps": "biceps",
        "bicep": "biceps",
        "triceps": "triceps",
        "tricep": "triceps",
        "forearms": "forearms",
        "forearm": "forearms",
        "abs": "abdominals",
        "abdominals": "abdominals",
        "abdominal": "abdominals",
        "core": "abdominals",
        "lower back": "lower back",
        "erector spinae": "lower back",
        "middle back": "middle back",
        "rhomboids": "middle back",
        "neck": "neck",
        "hip flexors": "hip flexors",
        "adductors": "adductors",
        "abductors": "abductors",
    }
    return mapping.get(n, n)


def normalise_category(cat: Optional[str]) -> str:
    if not cat:
        return "strength"
    c = cat.lower().strip()
    mapping = {
        "strength": "strength",
        "cardio": "cardio",
        "stretching": "stretching",
        "plyometrics": "plyometrics",
        "plyometric": "plyometrics",
        "olympic weightlifting": "olympic weightlifting",
        "powerlifting": "powerlifting",
        "strongman": "strength",
        "flexibility": "stretching",
    }
    return mapping.get(c, "strength")


def normalise_level(lvl: Optional[str]) -> str:
    if not lvl:
        return "intermediate"
    l = lvl.lower().strip()
    if l in ("beginner", "easy", "novice"):
        return "beginner"
    if l in ("expert", "advanced", "hard"):
        return "expert"
    return "intermediate"


def fetch_json(url: str) -> object:
    print(f"  Fetching: {url}")
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    return r.json()


# ---------------------------------------------------------------------------
# Source 1: yuhonas/free-exercise-db
# ---------------------------------------------------------------------------

def fetch_free_exercise_db() -> list[dict]:
    """
    Returns exercises in the unified schema from free-exercise-db.

    free-exercise-db schema (relevant fields):
        id, name, force, level, mechanic, equipment, primaryMuscles,
        secondaryMuscles, instructions (array), category, images (array of filenames)
    """
    print("\n[1/3] Fetching yuhonas/free-exercise-db …")
    data = fetch_json(FREE_EXERCISE_DB_INDEX)
    results = []

    for ex in data:
        ex_id = ex.get("id", "")
        name = ex.get("name", "").strip()
        if not name:
            continue

        # Build absolute image URLs
        raw_images = ex.get("images", [])
        image_urls = [
            f"{FREE_EXERCISE_DB_IMAGE_BASE}/{ex_id}/{img}"
            for img in raw_images
            if img
        ]

        primary   = [normalise_muscle(m) for m in ex.get("primaryMuscles", []) if m]
        secondary = [normalise_muscle(m) for m in ex.get("secondaryMuscles", []) if m]
        instructions = [s.strip() for s in ex.get("instructions", []) if s.strip()]

        results.append({
            "name":              name,
            "slug":              slugify(name),
            "primary_muscles":   primary,
            "secondary_muscles": secondary,
            "force":             ex.get("force"),
            "level":             normalise_level(ex.get("level")),
            "mechanic":          ex.get("mechanic"),
            "equipment":         (ex.get("equipment") or "").lower().strip() or None,
            "category":          normalise_category(ex.get("category")),
            "instructions":      instructions,
            "tips":              None,
            "image_urls":        image_urls,
            "gif_url":           None,
            "source_flags":      1,
        })

    print(f"  → {len(results)} exercises loaded from free-exercise-db")
    return results


# ---------------------------------------------------------------------------
# Source 2: wrkout/exercises.json
# ---------------------------------------------------------------------------

def fetch_wrkout() -> list[dict]:
    """
    wrkout exercises are stored as individual JSON files indexed by _index.json.

    Each exercise file schema:
        name, aliases, primaryMuscles, secondaryMuscles, force, level,
        mechanic, equipment, category, instructions (array), tips (array or str)
    """
    print("\n[2/3] Fetching wrkout/exercises.json …")
    try:
        index = fetch_json(WRKOUT_MANIFEST)
    except Exception as e:
        print(f"  ⚠ Could not fetch wrkout manifest: {e}")
        return []

    results = []
    for entry in index:
        slug_name = entry.get("name") or entry.get("id", "")
        if not slug_name:
            continue
        url = f"{WRKOUT_INDEX}/{slug_name}.json"
        try:
            ex = fetch_json(url)
        except Exception:
            continue

        name = ex.get("name", slug_name).strip()
        if not name:
            continue

        primary   = [normalise_muscle(m) for m in ex.get("primaryMuscles", []) if m]
        secondary = [normalise_muscle(m) for m in ex.get("secondaryMuscles", []) if m]
        instructions = [s.strip() for s in ex.get("instructions", []) if s.strip()]

        # Tips may be an array or a single string
        raw_tips = ex.get("tips", [])
        if isinstance(raw_tips, list):
            tips = " ".join(t.strip() for t in raw_tips if t.strip()) or None
        else:
            tips = str(raw_tips).strip() or None

        results.append({
            "name":              name,
            "slug":              slugify(name),
            "primary_muscles":   primary,
            "secondary_muscles": secondary,
            "force":             ex.get("force"),
            "level":             normalise_level(ex.get("level")),
            "mechanic":          ex.get("mechanic"),
            "equipment":         (ex.get("equipment") or "").lower().strip() or None,
            "category":          normalise_category(ex.get("category")),
            "instructions":      instructions,
            "tips":              tips,
            "image_urls":        [],
            "gif_url":           None,
            "source_flags":      2,
        })

    print(f"  → {len(results)} exercises loaded from wrkout")
    return results


# ---------------------------------------------------------------------------
# Source 3: ExerciseDB (GIFs from free-exercise-db repo)
# ---------------------------------------------------------------------------

def fetch_exercisedb() -> list[dict]:
    """
    ExerciseDB API data is also mirrored in the yuhonas/free-exercise-db repo
    under the 'exercises' directory with GIF animations named '<id>.gif'.

    We already fetched the exercise list in source 1; here we just build a
    mapping of slug → gif_url so the merge step can annotate entries.
    """
    print("\n[3/3] Building ExerciseDB GIF URL map from free-exercise-db …")
    try:
        data = fetch_json(FREE_EXERCISE_DB_INDEX)
    except Exception as e:
        print(f"  ⚠ Could not build GIF map: {e}")
        return []

    results = []
    for ex in data:
        ex_id = ex.get("id", "")
        name = ex.get("name", "").strip()
        if not name or not ex_id:
            continue
        gif_url = f"{FREE_EXERCISE_DB_IMAGE_BASE}/{ex_id}/{ex_id}.gif"
        results.append({
            "slug":    slugify(name),
            "gif_url": gif_url,
        })

    print(f"  → {len(results)} GIF URLs mapped")
    return results


# ---------------------------------------------------------------------------
# Merge & Deduplicate
# ---------------------------------------------------------------------------

def merge_sources(
    free_exercises: list[dict],
    wrkout_exercises: list[dict],
    gif_map: list[dict],
) -> list[dict]:
    """
    Deduplication strategy: slug is the canonical key.
    - free-exercise-db is authoritative for muscle groups, category, images
    - wrkout enriches tips and mechanic fields when free-exercise-db is missing them
    - GIF URLs annotated from ExerciseDB map
    """
    print("\n[Merge] Merging and deduplicating …")

    # Index by slug
    merged: dict[str, dict] = {}

    # Pass 1: free-exercise-db (primary source)
    for ex in free_exercises:
        s = ex["slug"]
        merged[s] = dict(ex)

    # Pass 2: wrkout enriches missing fields
    for ex in wrkout_exercises:
        s = ex["slug"]
        if s in merged:
            existing = merged[s]
            # Add tips if missing
            if not existing.get("tips") and ex.get("tips"):
                existing["tips"] = ex["tips"]
            # Add mechanic if missing
            if not existing.get("mechanic") and ex.get("mechanic"):
                existing["mechanic"] = ex["mechanic"]
            # Better instructions (wrkout often has more steps)
            if len(ex["instructions"]) > len(existing["instructions"]):
                existing["instructions"] = ex["instructions"]
            # Merge secondary muscles
            extra_secondary = [m for m in ex["secondary_muscles"] if m not in existing["secondary_muscles"]]
            existing["secondary_muscles"].extend(extra_secondary)
            existing["source_flags"] |= 2
        else:
            merged[s] = dict(ex)

    # Pass 3: annotate GIF URLs
    gif_lookup = {g["slug"]: g["gif_url"] for g in gif_map}
    for s, ex in merged.items():
        if s in gif_lookup:
            ex["gif_url"] = gif_lookup[s]
            ex["source_flags"] |= 4

    results = list(merged.values())

    # Sort alphabetically for deterministic ordering
    results.sort(key=lambda x: x["name"].lower())

    # Remove empty strings from array fields
    for ex in results:
        ex["primary_muscles"]   = [m for m in ex["primary_muscles"]   if m]
        ex["secondary_muscles"] = [m for m in ex["secondary_muscles"] if m]
        ex["instructions"]      = [i for i in ex["instructions"]      if i]
        ex["image_urls"]        = [u for u in ex["image_urls"]        if u]

    print(f"  → {len(results)} unique exercises after merge")
    return results


# ---------------------------------------------------------------------------
# Supabase Upsert
# ---------------------------------------------------------------------------

def upsert_to_supabase(exercises: list[dict]) -> None:
    if not SUPABASE_SERVICE_KEY:
        print("\n⚠ SUPABASE_SERVICE_ROLE_KEY not set — skipping upload.")
        print("  Set the env var and re-run to upload.")
        return

    print(f"\n[Upload] Upserting {len(exercises)} exercises to Supabase …")

    headers = {
        "apikey":        SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type":  "application/json",
        "Prefer":        "resolution=merge-duplicates,return=minimal",
    }
    endpoint = f"{SUPABASE_URL}/rest/v1/exercises"

    total = 0
    for i in range(0, len(exercises), UPSERT_BATCH):
        batch = exercises[i : i + UPSERT_BATCH]
        r = requests.post(endpoint, headers=headers, json=batch, timeout=60)
        if r.status_code not in (200, 201):
            print(f"  ✗ Batch {i//UPSERT_BATCH + 1} failed: {r.status_code} {r.text[:200]}")
        else:
            total += len(batch)
            print(f"  ✓ Batch {i//UPSERT_BATCH + 1}: {len(batch)} exercises upserted ({total}/{len(exercises)})")

    print(f"\nDone. {total}/{len(exercises)} exercises uploaded.")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Build and upload exercise database to Supabase")
    parser.add_argument("--dry-run",       action="store_true", help="Print merged data without uploading")
    parser.add_argument("--skip-wrkout",   action="store_true", help="Skip wrkout/exercises.json source")
    parser.add_argument("--skip-exercisedb", action="store_true", help="Skip ExerciseDB GIF annotations")
    parser.add_argument("--output",        type=str, default=None, help="Save merged JSON to this file")
    args = parser.parse_args()

    print("=" * 60)
    print("  Exercise Database Pipeline")
    print("=" * 60)

    free_exercises = fetch_free_exercise_db()

    wrkout_exercises: list[dict] = []
    if not args.skip_wrkout:
        wrkout_exercises = fetch_wrkout()
    else:
        print("\n[2/3] Skipping wrkout source")

    gif_map: list[dict] = []
    if not args.skip_exercisedb:
        gif_map = fetch_exercisedb()
    else:
        print("\n[3/3] Skipping ExerciseDB GIF map")

    merged = merge_sources(free_exercises, wrkout_exercises, gif_map)

    if args.output:
        out_path = Path(args.output)
        out_path.write_text(json.dumps(merged, indent=2, ensure_ascii=False))
        print(f"\nMerged data saved to: {out_path}")

    if args.dry_run:
        print("\n[Dry run] First 3 exercises:")
        for ex in merged[:3]:
            print(json.dumps(ex, indent=2))
        print(f"\nTotal: {len(merged)} exercises (not uploaded)")
        return

    upsert_to_supabase(merged)


if __name__ == "__main__":
    main()
