# OrynTap — Find your study spot

OrynTap shows which study spaces on campus have **free seats and free power outlets right now**. Students check in when they sit down ("I'm studying here") and leave when they go. If they forget, the check-in ends on its own after 1–3 hours.

Universities included: **Astana IT University**, **Nazarbayev University**, **Maqsut Narikbayev University** and **L.N. Gumilyov Eurasian National University**. There are 18 study spaces in total.

Team (SE-2621): Khaval Nurdaulet · Omirzak Amina · Bekshoinov Dias

---

## 1. How it works

```
 Browser (phone / tablet / laptop)            GitHub Pages (static hosting, HTTPS)
 ┌────────────────────────────┐   HTTPS   ┌──────────────────────────────────┐
 │ index.html + css + js      │ ────────▶ │ serves the files only            │
 └─────────────┬──────────────┘           └──────────────────────────────────┘
               │ HTTPS (TLS) · JWT after login
               ▼
 ┌──────────────────────────────────────────────────────────────────────────┐
 │ Supabase (cloud)                                                         │
 │  Auth (bcrypt passwords, e-mail login) ─▶ PostgreSQL 15                  │
 │  REST API (parameterised queries)       ─▶ Row-Level Security on tables  │
 │  Realtime (push "seat count changed")   ◀─ triggers on check_ins         │
 └──────────────────────────────────────────────────────────────────────────┘
```

* **GitHub Pages can only host static files**, so the database cannot run there. The site connects straight to **Supabase**, which is a hosted **PostgreSQL** database (the Assignment 3 brief lists it by name).
* **Demo mode:** if `js/config.js` is empty, the site keeps its data in the browser's localStorage and simulates other students. That way it works the moment you push it. Once the Supabase keys are filled in, the same interface reads from and writes to PostgreSQL.

| Requirement (Stage 1) | Where it is |
|---|---|
| R1 University e-mail only | `handle_new_user()` trigger rejects other domains, plus a check in the client |
| R2 Check in 1/2/3 h, leave early | `check_ins` table, `before_check_in()` trigger, check-in dialog |
| R3 Filters | Home chips: outlets, quiet, group, food, open now |
| R4 / R9 Real-time seats | `space_availability` view, `space_activity` table and Supabase Realtime |
| R5 Open / Closes soon / Closed | `opening_hours` table and `statusOf()` in `js/app.js` |
| R6 Campus map | AITU: the interactive [aitumap](https://yuujiso.github.io/aitumap/) by Yuujiso (MIT licence), embedded with floors, blocks and room search, plus a "Live seats" tab with pins. Other universities: a "where to find" list and a 2GIS link |
| R7 Favourites | `favourites` linking table |
| R8 Pomodoro | Button in the "You're studying at…" banner |
| R10 Roles, no location or audio | RLS policies and column GRANTs; no GPS or audio is ever stored |
| R11 360 px, contrast, light and dark, EN / RU / KK | Responsive CSS (desktop, tablet, mobile); status is always shown as text, not only as colour |
| R12 Offline label | The last data is cached and an "Offline — updated X min ago" banner appears |

---

## 2. Run it on your laptop (1 minute)

```bash
cd oryntap
python3 -m http.server 8000      # or: npx serve .
# open http://localhost:8000
```

Opening `index.html` by double-clicking also works in Chrome. A local server is still better.

**Demo mode:** sign up with any university e-mail. Accounts registered with the three team e-mails (below) become admins; everyone else is a student.

**Languages:** English, Russian and Kazakh (switch in the top bar; the choice is remembered). Texts live in `js/i18n.js`. Place names and descriptions come from the database and stay in English.

## 3. Put it on GitHub Pages

1. Create a repository, e.g. `oryntap`, and upload **the contents of this folder** (`index.html` must be at the top level).
2. Repository → **Settings → Pages** → Source: *Deploy from a branch* → Branch `main`, folder `/ (root)` → Save.
3. After about a minute the site is live at `https://<your-username>.github.io/oryntap/`.

All paths are relative and routing uses `#/…`, so nothing else is needed. The `.nojekyll` file is already included.

## 4. Connect the PostgreSQL database (Supabase, free tier)

1. Go to <https://supabase.com> → **New project** (region: Frankfurt is closest). Save the database password.
2. **SQL Editor → New query** → paste and run, in this order:
   1. `database/01_schema.sql` (tables, constraints, triggers, RLS, grants)
   2. `database/02_seed.sql` (4 universities, 18 spaces, 116 users, about 700 check-ins, 150 favourites)
   ⚠️ Do **not** run `00_local_shim.sql` on Supabase. It is only for a plain local PostgreSQL.
3. **Authentication → URL Configuration**: set *Site URL* to your GitHub Pages URL and add the same URL under *Redirect URLs*.
4. **Authentication → Providers → Email**: set the minimum password length to 8. For a classroom demo you can turn off *Confirm email*. If you leave it on, new users must click the link in their university inbox.
5. **Authentication → Providers → Google**: keep it **disabled** (the site only uses university e-mail and password).
6. **Project Settings → API**: copy the *Project URL* and the *anon public* key into `js/config.js`, then commit and push.
7. Before a demo, run `database/03_demo_live_activity.sql` so the seat counts look alive. The seeded live check-ins expire after about an hour.

**Admins:** only `260925@astanait.edu.kz` (Omirzak Amina), `261234@astanait.edu.kz` (Khaval Nurdaulet) and `261584@astanait.edu.kz` (Bekshoinov Dias). The `handle_new_user()` trigger gives them the admin role when they register; every other account is a student. The seed contains no admin accounts.

**Check-in rule:** a student can only check in at spaces of their own university (RLS policy `check_ins_own_insert`). Other universities can still be browsed.

**Database created before 14 Oct 2026?** Run `database/05_update_2026-10-14.sql` once in the SQL Editor. It sets the admin e-mails, adds the own-university check-in rule and removes the old seeded `admin@…` accounts, without touching other data. Then run `database/06_update_multimedia.sql` once: it adds the alt-text column and points every space to our own WebP photos or illustrations (Assignment 4).

> The anon key is public by design. Everything it can do is limited by Row-Level Security. **Never** put the `service_role` key in the website.

## 5. Offline copy on plain PostgreSQL (for the defense)

```bash
createdb oryntap
psql -d oryntap -f database/00_local_shim.sql   # fake auth schema + roles (local only)
psql -d oryntap -f database/01_schema.sql
psql -d oryntap -f database/02_seed.sql
```

Or open the files in **pgAdmin** → Query Tool and run them in the same order.

---

## 6. Defense cheat sheet (Assignment 3)

```sql
-- Hashed passwords (C2 evidence)
SELECT email, encrypted_password FROM auth.users LIMIT 5;     -- $2a$10$...  bcrypt

-- Count records grouped by a column
SELECT s.name, count(*) FROM check_ins c JOIN study_spaces s ON s.id = c.space_id GROUP BY s.name ORDER BY 2 DESC;

-- Busiest hour per space
SELECT space_id, extract(hour FROM started_at AT TIME ZONE 'Asia/Almaty') AS h, count(*)
FROM check_ins GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 5;

-- Parameterised query (SQL-injection safe): the value is sent separately from the SQL text
PREPARE space_by_id(int) AS SELECT name, free_seats FROM space_availability WHERE id = $1;
EXECUTE space_by_id(1);

-- What happens on delete? (FK actions)
--   delete a study space   -> its opening_hours, check_ins, favourites are deleted (ON DELETE CASCADE)
--   delete a university with users -> refused (profiles.university_id ON DELETE RESTRICT)

-- Act as a student to show Row-Level Security (local PostgreSQL)
SET request.jwt.claim.sub = '<a profile id>';  SET ROLE authenticated;
SELECT count(*) FROM check_ins;                    -- only MY rows
UPDATE study_spaces SET seat_capacity = 1;         -- UPDATE 0 (not an admin)
UPDATE profiles SET role = 'admin';                -- permission denied
RESET ROLE;

-- Audit log of admin changes
SELECT created_at, actor, action, table_name, record_id FROM audit_log ORDER BY id DESC;
```

**SQL injection:** the website never builds SQL strings. `js/store.js` calls the Supabase client (`.eq("id", id)`, `.insert({...})`). PostgREST turns these calls into **prepared statements** with bound parameters. Typing `Robert'); DROP TABLE check_ins;--` as your name is simply stored as text. CHECK constraints in the database and validation in the forms add extra protection.

**Backup and restore**

```bash
# Supabase: Database → Backups (daily, automatic) or:
pg_dump "postgresql://postgres:<password>@db.<project>.supabase.co:5432/postgres" -n public > backup.sql
# Local
pg_dump -d oryntap -n public -n auth > database/backup/oryntap_full_backup_YYYY-MM-DD.sql
# Restore into an empty database
createdb oryntap_restore && psql -d oryntap_restore -f database/backup/oryntap_full_backup_2026-10-12.sql
```

Backups contain password hashes, so `database/backup/` is git-ignored: keep them in the team Google Drive, not on GitHub.

**Data minimisation:** the profile stores only the first name, last name, university and role. The e-mail address lives only in `auth.users`. There is no phone number, no student ID and no GPS location or audio, and check-ins keep only the space, time and whether an outlet is used.

---

## 7. Project structure

```
index.html                 single page (routes: #/home #/map #/favourites #/profile #/checkin/<id>)
css/styles.css             design tokens, light/dark, desktop → tablet → mobile
js/config.js               Supabase URL + anon key (empty = demo mode)
js/store.js                data layer: SupabaseStore (PostgreSQL) and DemoStore (localStorage)
js/app.js                  interface: cards, filters, check-in, favourites, profile, admin edit, QR, Pomodoro
js/demo-data.js            generated — same spaces as the SQL seed
assets/img/                WebP photos, AITU floor plan, SVG illustrations
database/00_local_shim.sql local PostgreSQL only
database/01_schema.sql     schema, constraints, triggers, RLS, grants, realtime
database/02_seed.sql       generated test data
database/03_demo_live_activity.sql   refresh "live" check-ins before a demo
database/generate_seed.py  one source of truth: python3 database/generate_seed.py
database/05_update_2026-10-14.sql   one-time update: admin e-mails, own-university check-in
database/06_update_multimedia.sql    one-time update: own WebP photos, alt-text column
tools/optimise_images.py   original photo -> sized WebP files
tools/make_chime.py        synthesises the Pomodoro chime
media-src/                 original photos and sound (not loaded by the site)
assets/media/              how-to video, captions, poster, chime
database/backup/           example pg_dump
designs/                   desktop / tablet / mobile screens, light and dark
docs/ERD.md                ER diagram + normalisation example
```

### About the data

**AITU (counted by our team):**

| Space | Seats | Outlets | Accuracy |
|---|---|---|---|
| Library | 250 | 270 | approximate (shown with "~") |
| Open Space | 70 | 55 | approximate |
| Coworking | 180 | 25 | approximate |
| Coffeelake | 45 | 11 | **exact** (shown without "~", `counts_exact = true`) |

AITU Library hours come from the sign on the library door: Mon–Fri 09:00–22:00, Sat 09:00–17:00, Sun 10:00–15:00. The hours for Open Space, Coworking and Coffeelake, and Coffeelake's location ("Block C1, 1st floor"), are our guesses. Fix them with the admin **Edit** button, or in `database/generate_seed.py`.

**NU, MNU, ENU:** the spaces come from the universities' official pages (NU Library 24/7 rooms and Blocks D1/D5; the MNU Public Library, Zebra, the Shaikenov Atrium, the Team Talk Room and Pesochnica; the ENU Scientific Library, the Electronic Reading Room, the American Corner/Maker Space and the Student House coworking). **Their seat and outlet counts and some opening hours are estimates.**

### Media and licences (Assignment 4)

Every file the site shows is ours, or is used under a licence we have checked. No image is loaded from another website any more.

| Asset | File | Format | Size | Source / licence |
|---|---|---|---|---|
| Logo | inline SVG in `index.html` | SVG | < 1 KB | own work |
| Favicon | `assets/img/favicon.svg` | SVG | 0.2 KB | own work |
| Interface icons (home, map, heart, user, bell, play, close, pin) | inline SVG in `js/app.js` | SVG | < 1 KB each | own work |
| Space illustrations (16) | `assets/img/cover-*.svg`, `fallback-*.svg` | SVG | 2–10 KB | own work, drawn by `database/generate_seed.py` |
| AITU Library photo | `assets/img/aitu-library-460.webp` | WebP q80 | 13.4 KB | team photo (original in `media-src/`) |
| AITU Open Space photo | `assets/img/aitu-open-space-460.webp` | WebP q80 | 20.1 KB | team photo (original in `media-src/`) |
| AITU floor plan | `assets/img/aitu-map.webp` | WebP q85 | 31.9 KB | from aitumap by Yuujiso (MIT licence), attribution kept |
| How-to video (check-in) | `assets/media/howto-checkin.mp4` | MP4, H.264, no audio, 1280×720, 30 fps | 292 KB, 14 s | own screen recording of OrynTap |
| Video captions | `assets/media/howto-checkin.{en,ru,kk}.vtt` | WebVTT | < 1 KB each | own work |
| Video poster + thumbnail | `assets/media/howto-poster.webp`, `howto-thumb.webp` | WebP | 25 KB / 5 KB | frames of our own recording |
| Pomodoro chime | `assets/media/chime.mp3` | MP3 64 kbit/s, 1.2 s | 9.8 KB | own work, synthesised by `tools/make_chime.py` |
| Font | Rubik from Google Fonts | WOFF2 | — | SIL Open Font License 1.1 |

The photos that were hot-linked from astanait.edu.kz, ifla.org and mnu.kz in Assignment 3 were removed: those sites do not give a licence to reuse them. Those cards now show our own illustrations.

**Add or replace a photo:** put the original (JPEG or PNG, at least 960 px wide) in `media-src/`, then

```bash
python3 tools/optimise_images.py          # writes assets/img/<name>-480.webp and -960.webp
```

set `image=` and `alt=` for the space in `database/generate_seed.py`, run `python3 database/generate_seed.py`, and (for Supabase) update the row's `image_url` and `image_alt`.

**Alternative text** is stored in the database next to the photo (`study_spaces.image_alt`). Illustrations have no alt text on purpose (`alt=""`): the card heading already names the place.

**Sound** is off by default. The chime plays only after the student turns sound on in the study-session banner, and every chime comes with a visible message.
