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

**Database created before 14 Oct 2026?** Run `database/05_update_2026-10-14.sql` once in the SQL Editor. It sets the admin e-mails, adds the own-university check-in rule and removes the old seeded `admin@…` accounts, without touching other data.

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
assets/img/                photos, AITU floor plan, illustrations
database/00_local_shim.sql local PostgreSQL only
database/01_schema.sql     schema, constraints, triggers, RLS, grants, realtime
database/02_seed.sql       generated test data
database/03_demo_live_activity.sql   refresh "live" check-ins before a demo
database/generate_seed.py  one source of truth: python3 database/generate_seed.py
database/download_photos.py  copies the remote photos into assets/img/photos/
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

### Photos

Real photos are used where an official one exists. Each card shows its source:

* **NU** Astana Room, Quiet Room and Collaborative Space, the **MNU** Public Library, and the **ENU** Reading Hall and Electronic Reading Room: official photos from the IFLA World Library and Information Congress 2025 (2025.ifla.org).
* **MNU** Zebra, Team Talk Room and Pesochnica: mnu.kz (the "Pesochnica… new community hub" news article).
* **AITU** Coworking: astanait.edu.kz. AITU Library and Open Space: our own photos.
* There is no public photo yet for **Coffeelake**, NU Multifunctional Room, NU Study Room D5.124, the MNU Shaikenov Atrium, the ENU American Corner or the ENU Student House. These show an illustration. Take a photo, put it in `assets/img/`, and set `image=` in `generate_seed.py`.

The photos are loaded from the source websites. To keep copies inside the repo, so the demo does not depend on those sites, run this once on a computer with internet:

```bash
python3 database/download_photos.py   # saves assets/img/photos/*, regenerates seed + demo data
```

If a photo ever fails to load, the card automatically shows an illustration instead. The photos are used for a non-commercial student project with attribution. Replace them with your own shots if you publish the app.
