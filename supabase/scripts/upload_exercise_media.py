#!/usr/bin/env python3
"""
Exercise Media Upload Script
============================
Downloads exercise images and GIFs from GitHub, uploads them to the
Supabase Storage 'exercise-media' bucket, then updates the URLs in the
exercises table to point to the Supabase CDN.

Run AFTER build_exercise_db.py has populated the table.

Requirements
------------
    pip install requests supabase

Usage
-----
    export SUPABASE_URL="https://erghbsnxtsbnmfuycnyb.supabase.co"
    export SUPABASE_SERVICE_ROLE_KEY="<your-service-role-key>"

    # Upload all media (slow first time — ~2-3 GB of images/GIFs):
    python3 upload_exercise_media.py

    # Only upload images (skip GIFs):
    python3 upload_exercise_media.py --skip-gifs

    # Only upload GIFs (skip static images):
    python3 upload_exercise_media.py --skip-images

    # Re-upload even if file already exists in Storage:
    python3 upload_exercise_media.py --force

    # Limit to N exercises (for testing):
    python3 upload_exercise_media.py --limit 10

Notes
-----
- Files already in Storage are skipped by default (checks 409 Conflict).
- If a download fails the exercise row keeps the original GitHub URL.
- Updates are batched: image_urls and gif_url columns updated in place.
- Supabase Storage public URL format:
    <SUPABASE_URL>/storage/v1/object/public/exercise-media/<path>
"""

import argparse
import os
import sys
import time
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import requests

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SUPABASE_URL      = os.environ.get("SUPABASE_URL", "https://erghbsnxtsbnmfuycnyb.supabase.co")
SUPABASE_SVC_KEY  = os.environ.get("DB_SERVICE_ROLE_KEY", "")
BUCKET            = "exercise-media"
STORAGE_BASE      = f"{SUPABASE_URL}/storage/v1"
REST_BASE         = f"{SUPABASE_URL}/rest/v1"

# Pause between uploads to avoid hitting rate limits
UPLOAD_DELAY_S    = 0.3
# Max retries per file download
MAX_RETRIES       = 5


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


def storage_public_url(path: str) -> str:
    return f"{STORAGE_BASE}/object/public/{BUCKET}/{path}"


def upload_file(path_in_bucket: str, content: bytes, mime: str, force: bool = False) -> Optional[str]:
    """
    Upload bytes to Supabase Storage.
    Returns the public URL, or None on failure.
    """
    url = f"{STORAGE_BASE}/object/{BUCKET}/{path_in_bucket}"
    headers = svc_headers({
        "Content-Type":  mime,
        "x-upsert":      "true" if force else "false",
    })
    r = requests.post(url, headers=headers, data=content, timeout=60)
    if r.status_code in (200, 201):
        return storage_public_url(path_in_bucket)
    if r.status_code == 409 and not force:
        # Already exists — return the existing public URL
        return storage_public_url(path_in_bucket)
    print(f"    ✗ Upload failed [{r.status_code}]: {path_in_bucket}: {r.text[:120]}")
    return None


def download_bytes(url: str) -> Optional[bytes]:
    for attempt in range(MAX_RETRIES):
        try:
            r = requests.get(url, timeout=30, headers={"User-Agent": "RPT-Exercise-Uploader/1.0"})
            if r.status_code == 200:
                return r.content
            if r.status_code == 404:
                return None  # File doesn't exist upstream
            if r.status_code == 429:
                # Rate limited — wait longer before retrying
                wait = 5 * (attempt + 1)
                print(f"    ⏳ Rate limited, waiting {wait}s...")
                time.sleep(wait)
                continue
        except requests.RequestException:
            pass
        if attempt < MAX_RETRIES - 1:
            time.sleep(2 * (attempt + 1))
    return None


def guess_mime(url: str) -> str:
    lower = url.lower()
    if lower.endswith(".gif"):
        return "image/gif"
    if lower.endswith(".png"):
        return "image/png"
    if lower.endswith(".webp"):
        return "image/webp"
    return "image/jpeg"


def path_from_url(url: str) -> str:
    """
    Derive a bucket storage path from a source URL.
    E.g. 'https://raw.githubusercontent.com/.../Bench-Press/0.jpg'
         → 'exercises/Bench-Press/0.jpg'
    """
    parsed = urlparse(url)
    parts = parsed.path.split("/")
    # Keep the last two path components (folder/filename)
    if len(parts) >= 2:
        folder = parts[-2]
        filename = parts[-1]
        return f"exercises/{folder}/{filename}"
    return f"exercises/{parts[-1]}"


# ---------------------------------------------------------------------------
# Fetch all exercises from Supabase
# ---------------------------------------------------------------------------

def fetch_all_exercises(limit: int = 0) -> list[dict]:
    print("Fetching exercises from Supabase …")
    headers = svc_headers({"Content-Type": "application/json"})
    all_exercises = []
    page_size = 1000
    offset = 0

    while True:
        params = {
            "select": "id,slug,image_urls,gif_url",
            "limit":  str(page_size),
            "offset": str(offset),
            "order":  "slug.asc",
        }
        r = requests.get(f"{REST_BASE}/exercises", headers=headers, params=params, timeout=30)
        if r.status_code != 200:
            print(f"  ✗ Failed to fetch exercises: {r.status_code} {r.text[:200]}")
            break
        page = r.json()
        if not page:
            break
        all_exercises.extend(page)
        offset += len(page)
        if len(page) < page_size:
            break

    if limit > 0:
        all_exercises = all_exercises[:limit]

    print(f"  → {len(all_exercises)} exercises to process")
    return all_exercises


# ---------------------------------------------------------------------------
# Update exercise row in Supabase
# ---------------------------------------------------------------------------

def update_exercise_urls(exercise_id: str, image_urls: list[str], gif_url: Optional[str]) -> bool:
    headers = svc_headers({
        "Content-Type": "application/json",
        "Prefer":       "return=minimal",
    })
    payload: dict = {"image_urls": image_urls}
    if gif_url is not None:
        payload["gif_url"] = gif_url
    r = requests.patch(
        f"{REST_BASE}/exercises",
        headers=headers,
        params={"id": f"eq.{exercise_id}"},
        json=payload,
        timeout=30,
    )
    return r.status_code in (200, 204)


# ---------------------------------------------------------------------------
# Main processing loop
# ---------------------------------------------------------------------------

def process_exercises(
    exercises: list[dict],
    skip_images: bool,
    skip_gifs: bool,
    force: bool,
) -> None:
    total = len(exercises)
    updated = 0
    skipped = 0
    errors = 0

    for idx, ex in enumerate(exercises):
        ex_id   = ex["id"]
        slug    = ex.get("slug", ex_id)
        new_image_urls: list[str] = list(ex.get("image_urls") or [])
        new_gif_url: Optional[str] = ex.get("gif_url")
        changed = False

        print(f"[{idx+1}/{total}] {slug}")

        # --- Static images ---
        if not skip_images:
            uploaded_images: list[str] = []
            for raw_url in (ex.get("image_urls") or []):
                if not raw_url or SUPABASE_URL in raw_url:
                    # Already a Supabase URL
                    uploaded_images.append(raw_url)
                    continue

                storage_path = path_from_url(raw_url)
                print(f"  ↓ image {storage_path}")
                data = download_bytes(raw_url)
                if data is None:
                    print(f"    ⚠ Download failed, keeping original URL")
                    uploaded_images.append(raw_url)
                    continue
                supabase_url = upload_file(storage_path, data, guess_mime(raw_url), force)
                if supabase_url:
                    uploaded_images.append(supabase_url)
                    changed = True
                else:
                    uploaded_images.append(raw_url)
                time.sleep(UPLOAD_DELAY_S)

            new_image_urls = uploaded_images

        # --- GIF ---
        if not skip_gifs and ex.get("gif_url"):
            raw_gif = ex["gif_url"]
            if raw_gif and SUPABASE_URL not in raw_gif:
                storage_path = path_from_url(raw_gif)
                print(f"  ↓ gif  {storage_path}")
                data = download_bytes(raw_gif)
                if data is None:
                    print(f"    ⚠ GIF download failed, keeping original URL")
                else:
                    supabase_url = upload_file(storage_path, data, "image/gif", force)
                    if supabase_url:
                        new_gif_url = supabase_url
                        changed = True
                time.sleep(UPLOAD_DELAY_S)

        # Update row in Supabase only if something changed
        if changed:
            ok = update_exercise_urls(ex_id, new_image_urls, new_gif_url)
            if ok:
                updated += 1
            else:
                print(f"    ✗ Row update failed for {slug}")
                errors += 1
        else:
            skipped += 1

    print(f"\n{'='*50}")
    print(f"Media upload complete:")
    print(f"  Updated: {updated}")
    print(f"  Skipped (already Supabase URLs): {skipped}")
    print(f"  Errors:  {errors}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Upload exercise media to Supabase Storage")
    parser.add_argument("--skip-images",  action="store_true", help="Skip static images")
    parser.add_argument("--skip-gifs",    action="store_true", help="Skip GIF animations")
    parser.add_argument("--force",        action="store_true", help="Re-upload even if file exists")
    parser.add_argument("--limit",        type=int, default=0, help="Only process N exercises (0 = all)")
    args = parser.parse_args()

    if not SUPABASE_SVC_KEY:
        print("Error: SUPABASE_SERVICE_ROLE_KEY environment variable is required")
        sys.exit(1)

    exercises = fetch_all_exercises(limit=args.limit)
    if not exercises:
        print("No exercises found. Run build_exercise_db.py first.")
        sys.exit(1)

    process_exercises(
        exercises,
        skip_images=args.skip_images,
        skip_gifs=args.skip_gifs,
        force=args.force,
    )


if __name__ == "__main__":
    main()
