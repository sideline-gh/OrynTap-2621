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
3. **Authentication → URL Configuration**: set *Site URL* to your GitHub Pages URL (`https://sideline-gh.github.io/OrynTap-2621/`) and add `https://sideline-gh.github.io/OrynTap-2621/**` under *Redirect URLs* (the `**` also allows the password reset link, which ends in `?reset=1`).
4. **Authentication → Providers → Email**: set the minimum password length to 8 and keep **Confirm email ON**. New students then get a confirmation link and can log in only after opening it (database/09 also blocks check-ins, favourites and admin rights for unconfirmed accounts). The link works once and expires after *Email OTP Expiration* (default 3600 s = 1 h).
   **E-mail sending:** Supabase's built-in sender is for testing only (a few e-mails per hour). For real students set **Authentication → Emails → SMTP Settings** to a free sender, e.g. a team Gmail account with an app password (`smtp.gmail.com`, port 465, user = the Gmail address, password = the 16-character app password). The SMTP password is entered only in the Supabase dashboard, never in this repository.
   **E-mail texts in Kazakh, Russian and English:** in **Authentication → Emails → Templates**, paste `docs/email-templates/confirm-signup.html` into *Confirm signup* and `docs/email-templates/reset-password.html` into *Reset Password*; the subject line for each is written at the top of the file.
5. **Authentication → Providers → Google**: keep it **disabled** (the site only uses university e-mail and password).
6. **Project Settings → API**: copy the *Project URL* and the *anon public* key into `js/config.js`, then commit and push.
7. Before a demo, run `database/03_demo_live_activity.sql` so the seat counts look alive. The seeded live check-ins expire after about an hour.

**Admins:** only `260925@astanait.edu.kz` (Omirzak Amina), `261234@astanait.edu.kz` (Khaval Nurdaulet) and `261584@astanait.edu.kz` (Bekshoinov Dias). The `handle_new_user()` trigger gives them the admin role when they register; every other account is a student. The seed contains no admin accounts.

**Check-in rule:** a student can only check in at spaces of their own university (RLS policy `check_ins_own_insert`). Other universities can still be browsed.

**Database created before 14 Oct 2026?** Run `database/05_update_2026-10-14.sql` once in the SQL Editor. It sets the admin e-mails, adds the own-university check-in rule and removes the old seeded `admin@…` accounts, without touching other data. Then run `database/06_update_multimedia.sql` once: it adds the alt-text column and points every space to our own WebP photos or illustrations (Assignment 4). Then run `database/07_stage2.sql` and `database/08_iot_occupancy.sql` once (Project Stage 2: admin statistics and the simulated door sensor), `database/09_photos_verification.sql` (team photos, e-mail verification guard) and `database/10_improvements.sql` (4 Nov 2026: check-in ends at closing time, Extend 1 h, “usually busy” hints, “Wrong number?” reports, Mokko/Sheker location fix, new Open Space photo). Optionally run `database/11_test_history_aitu.sql` last (6 Nov 2026: generated test history for the admin statistics, see below). A fresh install runs 01, 02, 07, 08, 09 and 10, and optionally 11.

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

## 6b. Project Stage 2 (End-term)

**Statistics for administrators (Part C5).** After `07_stage2.sql`, an admin's Profile shows busiest hours, use per 100 seats and stay length for their own university. A student gets no rows; anonymous visitors cannot call the functions.

**Generated test history for AITU (6 Nov 2026).** `database/11_test_history_aitu.sql` replaces the generated history of the 7 AITU places with 2,449 finished check-ins by the 29 generated AITU test students (never real accounts), so the admin statistics also cover Mokko, Sheker and the Canteen. It is **generated test data, not measured data**: its daily pattern follows what our team sees on campus (busiest 13:00–15:00, a little less in the Library and most in the Canteen; also busy 15:00–17:00, most in the Library and Coworking; cafes quieter before noon and full 13:00–17:00; every place busy most of the day). Check-ins are placed only on days and hours when a place is open, never run past closing time, and live check-ins are not changed. Safe to run again. It is made by `tools/make_test_history.py`, which also updates `js/demo-history.js`. Real numbers come from the pilot.

**Repeat the analysis (Part C2).**
1. Supabase → SQL Editor → paste one query from `analysis/queries.sql` → Run → *Download CSV* as `q1.csv`, `q2.csv`, `q3.csv`.
2. `pip install matplotlib` (once), then `python3 analysis/make_charts.py <folder with the CSVs>`.
Only finished check-ins are counted and there is no date window, because the seed history is fixed in time. With real users add `AND c.started_at > now() - interval '30 days'`.

**IoT door counter, simulated (Part D).** No real hardware is connected: `iot/sensor_sim.py` simulates an ESP32 with two ToF sensors at the AITU Library door and sends "people inside" to Supabase every 10 s. The Home page shows it in the **Live occupancy** panel (people inside, free seats, last update), refreshed every 10 s.
1. SQL Editor: run `database/08_iot_occupancy.sql` (after 07), then the `register_sensor` SELECT at its end; copy the secret.
2. `cp iot/.env.example iot/.env` and fill it in (publishable key only, never the secret/service_role key; `iot/.env` is git-ignored).
3. `python3 iot/sensor_sim.py`. Full instructions: `iot/README.md`.

In demo mode (empty `js/config.js`) the browser simulates the sensors and the statistics itself.

## 6c. Improvements of 4 Nov 2026 (`database/10_improvements.sql`)

| Feature | Where | How it works |
|---|---|---|
| Reminder 10 min before a check-in ends | session banner | toast + system notification (if allowed) + chime (if sound is on), once per end time; the banner turns amber |
| Extend 1 h | session banner | `extend_check_in()`: +1 h, at most 3 h ahead, never past closing time |
| Automatic check-out at closing time | check-in | trigger `check_ins_until_closing` ends a new check-in at closing time at the latest; the dialog says so |
| Forgot password | login form | Supabase sends a one-time link (1 h); the site then asks for a new password |
| ★ Best right now | Home, first chip | order by free seats (50 %), free outlets (25 %) and time until closing (25 %); closed places last |
| Usually busy | card, next to the tags | `space_busy_hours()`: per hour, how many finished check-ins of the last 8 weeks covered it; only for places with ≥ 15 check-ins, so new places (Mokko, Sheker, Canteen) show it only once real check-ins exist. This also gives the Canteen "lunch rush" warning, from data instead of a guess |
| Tell me when a seat is free | full cards | watched in this browser while OrynTap is open (no push server); ends after 3 h or at closing |
| Wrong number? | cards (logged-in students) | `report_count()`: full / many free / closed, one per place per 10 min; admins see a 7-day summary on the Profile page; the numbers on cards are not changed |
| QR poster | admin → QR code → Print poster | A4 page: big QR code, short text in Kazakh, Russian and English |
| E-mail texts | `docs/email-templates/` | confirmation and reset e-mails in Kazakh, Russian and English (paste into Supabase) |

Not done: map pins for Mokko and Sheker. The floor plan (and aitumap) shows only Block C1; a plan of the C1–C2–C3 passages is needed to place them.

## 6d. Availability (R12)

`.github/workflows/uptime.yml` checks every 30 minutes that the website and the database API answer (public key only). Each run stays in the repository's **Actions → Uptime check** list: green = up, red = down. Availability for a period = green runs ÷ all runs. With the GitHub CLI: `gh run list --workflow uptime.yml --limit 1000 --json conclusion --jq 'map(.conclusion) | group_by(.) | map({(.[0]): length}) | add'`. GitHub may delay scheduled runs by a few minutes; that does not count as downtime.

## 6e. Test accounts

| Role | Account | Password |
|---|---|---|
| Student (live site) | `248481@astanait.edu.kz` (generated test student, confirmed) | `Student2026!` |
| Administrator (live site) | created by the team for the defense; given to the instructor in person | – |
| Any role (demo mode, empty `js/config.js`) | any university e-mail; the three team e-mails become admins | any, 8+ characters |

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
database/07_stage2.sql     Stage 2: admin statistics functions, sensor tables, ingest_reading()
analysis/queries.sql       Stage 2 Part C: the three analysis queries (Q1–Q3)
analysis/make_charts.py    draws the three charts from the CSV results
database/08_iot_occupancy.sql  Part D: free seats in space_sensor_now, seat-capacity check
iot/sensor_sim.py          Part D: simulated door counter, 2 ToF sensors (Python, no packages)
iot/test_sensor_sim.py     tests of the counting logic
iot/.env.example           settings template (copy to iot/.env, never commit .env)
iot/README.md              how to set up and run the simulation
js/demo-history.js         generated check-ins for the demo-mode statistics (AITU part: tools/make_test_history.py)
tools/optimise_images.py   original photo -> sized WebP files
tools/make_chime.py        synthesises the Pomodoro chime
tools/make_test_history.py generated AITU test history -> database/11_test_history_aitu.sql
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
| Mokko (coffee shop, between Blocks C2 and C3, opposite the wardrobe) | ~10 | 0 (not counted yet) | rough estimate |
| Sheker (coffee shop, between Blocks C1 and C2, opposite the wardrobe) | ~10 | 0 (not counted yet) | rough estimate |
| Canteen (Block C1.3, dining hall) | ~100 | 0 (not counted yet) | rough estimate ("at least 100") |

AITU Library hours come from the sign on the library door: Mon–Fri 09:00–22:00, Sat 09:00–17:00, Sun 10:00–15:00. The hours for Open Space, Coworking and Coffeelake, and Coffeelake's location ("Block C1, 1st floor"), are our guesses. Mokko, Sheker and Canteen: only Mon–Fri 09:00–20:00 is confirmed; Saturday/Sunday hours, outlets and exact seats are left for an admin to fill in, so on weekends they show as closed until then. Mokko and Sheker have no pin on the live floor plan, because the plan only shows Block C1 (Canteen's pin is on the C1.3 dining hall). Fix all of this with the admin **Edit** button, or in `database/generate_seed.py`.

**NU, MNU, ENU:** the spaces come from the universities' official pages (NU Library 24/7 rooms and Blocks D1/D5; the MNU Public Library, Zebra, the Shaikenov Atrium, the Team Talk Room and Pesochnica; the ENU Scientific Library, the Electronic Reading Room, the American Corner/Maker Space and the Student House coworking). **Their seat and outlet counts and some opening hours are estimates.**

### Media and licences (Assignment 4)

Every file the site shows is ours, or is used under a licence we have checked. No image is loaded from another website any more.

| Asset | File | Format | Size | Source / licence |
|---|---|---|---|---|
| Logo | inline SVG in `index.html` | SVG | < 1 KB | own work |
| Favicon | `assets/img/favicon.svg` | SVG | 0.2 KB | own work |
| Interface icons (home, map, heart, user, bell, play, close, pin) | inline SVG in `js/app.js` | SVG | < 1 KB each | own work |
| Space illustrations (16) | `assets/img/cover-*.svg`, `fallback-*.svg` | SVG | 2–10 KB | own work, drawn by `database/generate_seed.py` |
| AITU Library photo | `assets/img/aitu-library-480.webp`, `-960.webp` | WebP q80 | 18.6 / 58.2 KB | team photo, Nov 2026 (original in `media-src/`) |
| Coffeelake photo | `assets/img/aitu-coffeelake-480.webp`, `-960.webp` | WebP q80 | 23.2 / 75.6 KB | team photo, Nov 2026 (original in `media-src/`) |
| Coworking photo | `assets/img/aitu-coworking-480.webp`, `-960.webp` | WebP q80 | 14.7 / 47.0 KB | team photo, Nov 2026 (original in `media-src/`) |
| Mokko, Sheker, Canteen photos | `assets/img/aitu-{mokko,sheker,canteen}-480/960.webp` | WebP q80 | 24–26 / 67–101 KB | team photos, Nov 2026 (originals in `media-src/`) |
| AITU Open Space photo | `assets/img/aitu-open-space-480.webp`, `-960.webp` | WebP q80 | 18.9 / 70.5 KB | team photo, Nov 2026, straightened (verticals) and lightly corrected for contrast (original in `media-src/`). The old `aitu-open-space-460.webp` can be deleted after `10_improvements.sql` has run |
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
