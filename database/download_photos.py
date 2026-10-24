#!/usr/bin/env python3
"""
OrynTap — save the real photos of NU / MNU / ENU / AITU spaces INTO the repo.

The seed links to photos on the universities' and IFLA's websites. That works,
but if one of those sites is slow or blocks hot-linking the card falls back to
an illustration. Run this once on your laptop (it needs internet):

    python3 database/download_photos.py

It downloads every remote photo to assets/img/photos/space-XX.<ext>, then
re-runs generate_seed.py so js/demo-data.js and database/02_seed.sql point to
the local copies. Commit the new files and push. If you already loaded the seed
into Supabase, run the UPDATE statements it prints in the SQL editor.
"""
import re, subprocess, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "database"))
src = (ROOT / "database" / "generate_seed.py").read_text()

# read SPACES without running the whole generator
ns = {"__file__": str(ROOT / "database" / "generate_seed.py")}
exec(src.split("FIRST = [")[0], ns)
spaces = ns["SPACES"]

out_dir = ROOT / "assets" / "img" / "photos"
out_dir.mkdir(parents=True, exist_ok=True)
updates = []
for i, s in enumerate(spaces, 1):
    url = s.get("image") or ""
    if not url.startswith("http"):
        continue
    ext = re.search(r"\.(jpe?g|png|webp)(?:$|\?)", url, re.I)
    ext = (ext.group(1).lower() if ext else "jpg").replace("jpeg", "jpg")
    dest = out_dir / f"space-{i:02d}.{ext}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (OrynTap student project)"})
        with urllib.request.urlopen(req, timeout=30) as r:
            dest.write_bytes(r.read())
        print(f"ok   {s['name']:<36} -> {dest.relative_to(ROOT)}")
        updates.append((s, f"assets/img/photos/space-{i:02d}.{ext}"))
    except Exception as e:
        print(f"FAIL {s['name']:<36} {e}")

subprocess.run([sys.executable, str(ROOT / "database" / "generate_seed.py")], check=True)

if updates:
    print("\n-- If the seed is already in Supabase, run this in the SQL editor:")
    for s, path in updates:
        name = s["name"].replace("'", "''")
        print(f"UPDATE public.study_spaces SET image_url = '{path}' WHERE name = '{name}' "
              f"AND university_id = (SELECT id FROM public.universities WHERE code = '{s['uni']}');")
