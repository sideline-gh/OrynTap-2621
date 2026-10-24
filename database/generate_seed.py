#!/usr/bin/env python3
"""
OrynTap — one source of truth for universities and study spaces.

Generates:
  database/02_seed.sql             realistic test data for PostgreSQL / Supabase
  database/03_demo_live_activity.sql   fresh "live" check-ins (run before a demo)
  js/demo-data.js                  the same data for the browser demo mode
  assets/img/cover-*.svg           illustrations for spaces without a photo

Run:  python3 database/generate_seed.py
"""
import json, random, uuid, os, math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
rnd = random.Random(2026)

# ---------------------------------------------------------------- data
UNIVERSITIES = [
    dict(code="AITU", name="Astana IT University", short="AITU",
         address="Mangilik El Ave 55/11, EXPO Business Center, Block C1",
         domains=["astanait.edu.kz"], map="assets/img/aitu-map.jpg",
         embed="https://yuujiso.github.io/aitumap/", hue=212),
    dict(code="NU", name="Nazarbayev University", short="NU",
         address="Kabanbay Batyr Ave 53", domains=["nu.edu.kz"], map=None, hue=200),
    dict(code="MNU", name="Maqsut Narikbayev University", short="MNU",
         address="Korgalzhyn Hwy 8", domains=["mnu.kz", "kazguu.kz"], map=None, hue=350),
    dict(code="ENU", name="L.N. Gumilyov Eurasian National University", short="ENU",
         address="Satbayev St 2", domains=["enu.kz"], map=None, hue=160),
]

def daily(o, c):            return {d: (o, c) for d in range(1, 8)}
def h247():                 return daily("00:00", "24:00")
def week(o, c, sat=None, sun=None):
    h = {d: (o, c) for d in range(1, 6)}
    if sat: h[6] = sat
    if sun: h[7] = sun
    return h

IFLA = "https://2025.ifla.org/wp-content/uploads/2025/03/"
SPACES = [
    # ---- AITU — seats/outlets counted by our team (Stage 1). Only Coffeelake is exact.
    dict(uni="AITU", name="Library", kind="library", building="Block C1.1", floor="1st floor",
         desc="Main university library with soft booths, long tables and bookshelves. Silence zone. library@astanait.edu.kz",
         seats=250, outlets=270, quiet=True, group=False, food=False,
         # from the sign on the library door
         hours=week("09:00", "22:00", sat=("09:00", "17:00"), sun=("10:00", "15:00")),
         image="assets/img/aitu-library.jpg", map=(11, 68)),
    dict(uni="AITU", name="Open Space", kind="atrium", building="Block C1.2 · Atrium", floor="1st floor",
         desc="Bright atrium under the glass roof with modular sofas. Good for group work between classes.",
         seats=70, outlets=55, quiet=False, group=True, food=True,
         hours=daily("08:00", "23:00"), image="assets/img/aitu-open-space.jpg", map=(50, 61)),
    dict(uni="AITU", name="Coworking", kind="coworking", building="Block C1.2", floor="1st floor",
         desc="Large coworking zone with shared desks, sofas and whiteboards next to the atrium.",
         seats=180, outlets=25, quiet=False, group=True, food=False,
         hours=week("08:00", "22:00", sat=("09:00", "20:00")),
         image="https://astanait.edu.kz/media/766ad632___________astana_it_university__1_.jpg", credit="astanait.edu.kz", map=(50, 23)),
    dict(uni="AITU", name="Coffeelake", kind="cafe", building="Block C1", floor="1st floor",
         desc="Campus coffee shop. Seat and outlet numbers were counted exactly by our team.",
         seats=45, outlets=11, quiet=False, group=True, food=True, exact=True,
         hours=week("08:00", "20:00", sat=("09:00", "18:00")), image=None, map=None),

    # ---- Nazarbayev University (library rooms are open 24/7)
    dict(uni="NU", name="Library · Astana Room", kind="library", building="NU Library", floor=None,
         desc="The most popular reading room, with the largest number of computers. Open 24/7.",
         seats=120, outlets=140, quiet=True, group=False, food=False, hours=h247(),
         image=IFLA + "Nazarbayev-University-Library-8.jpeg", credit="IFLA WLIC 2025"),
    dict(uni="NU", name="Library · Quiet Room", kind="library", building="NU Library", floor=None,
         desc="Silent room for individual study. No talking, no calls. Open 24/7.",
         seats=60, outlets=60, quiet=True, group=False, food=False, hours=h247(),
         image=IFLA + "Nazarbayev-University-Library-7.jpeg", credit="IFLA WLIC 2025"),
    dict(uni="NU", name="Library · Collaborative Space", kind="coworking", building="NU Library", floor=None,
         desc="Media Room and Collaborative Space for teamwork, trainings and student club meetings.",
         seats=50, outlets=50, quiet=False, group=True, food=False, hours=h247(),
         image=IFLA + "Nazarbayev-University-Library-2.jpeg", credit="IFLA WLIC 2025"),
    dict(uni="NU", name="Multifunctional Room", kind="lounge", building="Block D1", floor=None,
         desc="Student multifunctional room, open around the clock.",
         seats=60, outlets=40, quiet=False, group=True, food=True, hours=h247(), image=None),
    dict(uni="NU", name="Study Room D5.124", kind="rooms", building="Block D5", floor="Room D5.124",
         desc="Study room in the residential blocks, open 24/7.",
         seats=30, outlets=30, quiet=True, group=False, food=False, hours=h247(), image=None),

    # ---- Maqsut Narikbayev University
    dict(uni="MNU", name="Public Library", kind="library", building="Main building", floor="2nd floor",
         desc="1,051 m² library with ~13,000 books, a mezzanine and a winter garden. Workstations have lights and outlets. Water only.",
         seats=150, outlets=120, quiet=True, group=False, food=False,
         hours=week("09:00", "22:00", sat=("09:00", "17:00")),
         image=IFLA + "Maqsut-Narikbayev-University-Library-2-768x512.jpg", credit="IFLA WLIC 2025"),
    dict(uni="MNU", name="Zebra Coworking", kind="coworking", building="Main building", floor="2nd floor",
         desc="Coworking for individual and group work: ergonomic furniture, lit workstations with outlets, discussion areas.",
         seats=60, outlets=60, quiet=False, group=True, food=False,
         hours=week("08:00", "22:00", sat=("09:00", "18:00")),
         image="https://mnu.kz/wp-content/uploads/2025/01/by_kana-51-1024x683.webp", credit="mnu.kz"),
    dict(uni="MNU", name="Shaikenov Atrium", kind="atrium", building="Main building", floor="3rd floor",
         desc="Open study areas for individual and small-group work, with sound-absorbing design.",
         seats=70, outlets=40, quiet=False, group=True, food=False,
         hours=week("08:00", "21:00", sat=("09:00", "18:00")), image=None),
    dict(uni="MNU", name="Team Talk Room", kind="rooms", building="Main building", floor="1st floor",
         desc="Six separate rooms for teamwork and project discussions, opposite the library. Multimedia equipment.",
         seats=36, outlets=24, quiet=False, group=True, food=False,
         hours=week("09:00", "21:00", sat=("09:00", "17:00")),
         image="https://mnu.kz/wp-content/uploads/2025/01/by_kana-30-683x1024.webp", credit="mnu.kz"),
    dict(uni="MNU", name="Pesochnica", kind="lounge", building="Main building", floor="Ground floor",
         desc="Student hub for meetings and events with a multifunctional work area. Hall for up to 80 people.",
         seats=80, outlets=30, quiet=False, group=True, food=True,
         hours=week("09:00", "21:00", sat=("10:00", "18:00")),
         image="https://mnu.kz/wp-content/uploads/2025/01/by_kana-9-1024x683.webp", credit="mnu.kz"),

    # ---- L.N. Gumilyov Eurasian National University
    dict(uni="ENU", name="Scientific Library · Reading Hall", kind="library", building="Educational building", floor=None,
         desc="Open-access reading hall with educational, reference and scientific literature.",
         seats=200, outlets=80, quiet=True, group=False, food=False,
         hours=week("09:00", "20:00", sat=("09:00", "17:00")),
         image=IFLA + "L.N.Gumilyov-Eurasian-National-University-Library-8-768x1024.jpeg", credit="IFLA WLIC 2025"),
    dict(uni="ENU", name="Electronic Reading Room", kind="rooms", building="Scientific Library", floor=None,
         desc="Computers with access to EBSCO and other scientific databases.",
         seats=60, outlets=70, quiet=True, group=False, food=False,
         hours=week("09:00", "18:00"),
         image=IFLA + "L.N.Gumilyov-Eurasian-National-University-Library-7-768x1024.jpeg", credit="IFLA WLIC 2025"),
    dict(uni="ENU", name="American Corner & Maker Space", kind="coworking", building="Information Resource Center", floor=None,
         desc="Space for group projects, workshops and maker activities.",
         seats=40, outlets=40, quiet=False, group=True, food=False,
         hours=week("10:00", "18:00", sat=("10:00", "16:00")), image=None),
    dict(uni="ENU", name="Student House Coworking", kind="lounge", building="Student House", floor=None,
         desc="Coworking zones of the new 2,656-place Student House, made for team-based work.",
         seats=100, outlets=80, quiet=False, group=True, food=True,
         hours=daily("08:00", "23:00"), image=None),
]

FIRST = ["Aruzhan", "Alikhan", "Dana", "Nursultan", "Aigerim", "Dias", "Amina", "Yerlan", "Madina", "Temirlan",
         "Zhanel", "Arman", "Kamila", "Sanzhar", "Dariga", "Bekzat", "Aisulu", "Miras", "Tomiris", "Adil",
         "Asel", "Rustem", "Inkar", "Alisher", "Saule", "Ernar", "Moldir", "Daniyar", "Akbota", "Yersultan",
         "Aliya", "Nurlan", "Diana", "Timur", "Zarina", "Askar", "Malika", "Olzhas", "Ayaulym", "Maksat"]
LAST = ["Abenov", "Seitkali", "Nurlanov", "Zhakupov", "Omarov", "Kassymov", "Bekov", "Tulegenov", "Akhmetov",
        "Sadykov", "Iskakov", "Mukanov", "Baimukhanov", "Yesenov", "Kairatov", "Utepov", "Zhumabekov",
        "Ismailov", "Tokayev", "Serikbayev", "Amanov", "Rakhimov", "Dosmukhamedov", "Kuanyshev"]

def female(first):
    return first in {"Aruzhan", "Dana", "Aigerim", "Amina", "Madina", "Zhanel", "Kamila", "Dariga", "Aisulu",
                     "Tomiris", "Asel", "Inkar", "Saule", "Moldir", "Akbota", "Aliya", "Diana", "Zarina",
                     "Malika", "Ayaulym"}

def surname(last, first):
    return last + "a" if female(first) and last.endswith(("ov", "ev")) else last

def q(s):
    return "NULL" if s is None else "'" + str(s).replace("'", "''") + "'"

# ------------------------------------------------------------ users
USERS = []  # dict(id, email, first, last, uni, role)
NS = uuid.UUID("6f1d2a40-0000-4000-8000-000000002026")
for u in UNIVERSITIES:
    dom = u["domains"][0]
    USERS.append(dict(id=str(uuid.uuid5(NS, "admin@" + dom)), email="admin@" + dom,
                      first="Admin", last=u["short"], uni=u["code"], role="admin"))
    used = set()
    while len([x for x in USERS if x["uni"] == u["code"]]) < 30:
        f = rnd.choice(FIRST); l = surname(rnd.choice(LAST), f)
        if (f, l) in used: continue
        used.add((f, l))
        if u["code"] == "AITU":
            email = f"{rnd.randint(230000, 249999)}@astanait.edu.kz"
        elif u["code"] == "NU":
            email = f"{f.lower()}.{l.lower()}@nu.edu.kz"
        elif u["code"] == "MNU":
            email = f"{f[0].lower()}_{l.lower()}@mnu.kz"
        else:
            email = f"{l.lower()}.{f[0].lower()}@enu.kz"
        if any(x["email"] == email for x in USERS): continue
        USERS.append(dict(id=str(uuid.uuid5(NS, email)), email=email, first=f, last=l,
                          uni=u["code"], role="student"))

# ------------------------------------------------------------ SQL seed
def space_ref(s):
    return (f"(SELECT s.id FROM public.study_spaces s JOIN public.universities u ON u.id = s.university_id "
            f"WHERE u.code = {q(s['uni'])} AND s.name = {q(s['name'])})")

def local_photo(i):
    """A photo downloaded by database/download_photos.py wins over the remote URL."""
    for ext in ("jpg", "jpeg", "png", "webp"):
        if (ROOT / f"assets/img/photos/space-{i:02d}.{ext}").exists():
            return f"assets/img/photos/space-{i:02d}.{ext}"
    return None

def cover_path(i, s):
    return local_photo(i) or s["image"] or f"assets/img/cover-{i:02d}-{s['kind']}.svg"

def credit(i, s):
    return s.get("credit") if (s["image"] or local_photo(i)) else None

out = []
w = out.append
w("-- =====================================================================")
w("-- OrynTap — test data (generated by database/generate_seed.py)")
w("-- Run after 01_schema.sql. Test students share one starting password (see")
w("-- the crypt() calls below); change it after loading, see README.")
w("-- Passwords are stored ONLY as bcrypt hashes: crypt(..., gen_salt('bf', 10)).")
w("-- =====================================================================\n")
w("BEGIN;\n")
w("-- Supabase keeps pgcrypto (crypt, gen_salt) in the \"extensions\" schema\nSET LOCAL search_path = public, extensions;\n")

w("-- Universities ------------------------------------------------------")
w("INSERT INTO public.universities (code, name, city, address, map_image_url, map_embed_url) VALUES")
w(",\n".join(f"  ({q(u['code'])}, {q(u['name'])}, 'Astana', {q(u['address'])}, {q(u['map'])}, {q(u.get('embed'))})" for u in UNIVERSITIES) + ";\n")

w("INSERT INTO public.email_domains (domain, university_id) VALUES")
rows = []
for u in UNIVERSITIES:
    for d in u["domains"]:
        rows.append(f"  ({q(d)}, (SELECT id FROM public.universities WHERE code = {q(u['code'])}))")
w(",\n".join(rows) + ";\n")

w("-- Study spaces ------------------------------------------------------")
w("INSERT INTO public.study_spaces (university_id, name, kind, building, floor, description, image_url, image_credit,\n"
  "  seat_capacity, outlet_capacity, counts_exact, is_quiet, group_work, food_allowed, map_x, map_y) VALUES")
rows = []
for i, s in enumerate(SPACES, 1):
    mx, my = s.get("map") or (None, None)
    rows.append(f"  ((SELECT id FROM public.universities WHERE code = {q(s['uni'])}), {q(s['name'])}, {q(s['kind'])}, "
                f"{q(s['building'])}, {q(s['floor'])}, {q(s['desc'])}, {q(cover_path(i, s))}, {q(credit(i, s))}, {s['seats']}, {s['outlets']}, {str(s.get('exact', False)).lower()}, "
                f"{str(s['quiet']).lower()}, {str(s['group']).lower()}, {str(s['food']).lower()}, "
                f"{'NULL' if mx is None else mx}, {'NULL' if my is None else my})")
w(",\n".join(rows) + ";\n")

w("-- Opening hours (ISO weekday 1 = Monday) ---------------------------")
w("INSERT INTO public.opening_hours (space_id, weekday, opens, closes) VALUES")
rows = []
for s in SPACES:
    for d, (o, c) in sorted(s["hours"].items()):
        rows.append(f"  ({space_ref(s)}, {d}, '{o}', '{c}')")
w(",\n".join(rows) + ";\n")

w("-- Users: inserted into auth.users; the on_auth_user_created trigger")
w("-- validates the e-mail domain and creates the matching profile row.")
rows, idrows = [], []
for x in USERS:
    days_ago = rnd.randint(20, 60)   # drawn for every user so the rest of the data stays identical
    # The placeholder admin@... rows are kept in USERS only for that reason and
    # are not written: the admin role now belongs to the team's three e-mails
    # (handle_new_user trigger in 01_schema.sql).
    if x["role"] == "admin":
        continue
    app_meta = json.dumps({"provider": "email", "providers": ["email"]})
    user_meta = json.dumps({"first_name": x["first"], "last_name": x["last"], "consent": "true"})
    rows.append(f"  ('00000000-0000-0000-0000-000000000000', '{x['id']}', 'authenticated', 'authenticated', {q(x['email'])}, "
                f"crypt('Student2026!', gen_salt('bf', 10)), now(), {q(app_meta)}::jsonb, {q(user_meta)}::jsonb, "
                f"now() - interval '{days_ago} days', now(), '', '', '', '')")
    idrows.append(f"  ('{x['id']}', '{x['id']}', '{x['id']}', "
                  f"{q(json.dumps({'sub': x['id'], 'email': x['email'], 'email_verified': True}))}::jsonb, 'email', now(), now(), now())")
w("INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,\n"
  "  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,\n"
  "  confirmation_token, recovery_token, email_change_token_new, email_change) VALUES")
w(",\n".join(rows) + ";\n")
w("INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at) VALUES")
w(",\n".join(idrows) + ";\n")

w("-- Helper: a timestamp N days ago at HH:MM Astana time (dropped at the end)")
w("CREATE FUNCTION pg_temp.ts(days_ago int, hhmm text) RETURNS timestamptz LANGUAGE sql AS $$\n"
  "  SELECT (date_trunc('day', now() AT TIME ZONE 'Asia/Almaty') - make_interval(days => days_ago) + hhmm::interval)\n"
  "         AT TIME ZONE 'Asia/Almaty'\n$$;\n")

# historical check-ins: ~640 rows over the last 30 days, peaks around 11:00–17:00
HOUR_W = {8: 3, 9: 6, 10: 9, 11: 12, 12: 12, 13: 13, 14: 14, 15: 13, 16: 12, 17: 10, 18: 8, 19: 6, 20: 4, 21: 2}
hrs, wts = zip(*HOUR_W.items())
spaces_by_uni = {}
for s in SPACES: spaces_by_uni.setdefault(s["uni"], []).append(s)
students = [x for x in USERS if x["role"] == "student"]
used_days = set()
hist = []
while len(hist) < 640:
    x = rnd.choice(students)
    d = rnd.randint(1, 30)
    if (x["id"], d) in used_days: continue
    used_days.add((x["id"], d))
    cand = spaces_by_uni[x["uni"]]
    s = rnd.choices(cand, weights=[c["seats"] ** 0.6 for c in cand])[0]
    h = rnd.choices(hrs, weights=wts)[0]
    wd = ((d % 7))  # rough – weekend dampening below
    m = rnd.randint(0, 59)
    planned = rnd.choice([60, 120, 120, 180])
    stayed = planned if rnd.random() < 0.45 else rnd.randint(20, planned)   # many leave early
    hist.append((x["id"], s, rnd.random() < 0.55, d, f"{h:02d}:{m:02d}", planned, stayed))
w(f"-- Check-ins history ({len(hist)} rows, main table) ----------------------------")
w("INSERT INTO public.check_ins (user_id, space_id, uses_outlet, started_at, expires_at, left_at) VALUES")
rows = []
for uid, s, outl, d, hm, planned, stayed in hist:
    st = f"pg_temp.ts({d}, '{hm}')"
    rows.append(f"  ('{uid}', {space_ref(s)}, {str(outl).lower()}, {st}, {st} + interval '{planned} minutes', {st} + interval '{stayed} minutes')")
w(",\n".join(rows) + ";\n")

# favourites
fav = set()
while len(fav) < 150:
    x = rnd.choice(students)
    s = rnd.choice(spaces_by_uni[x["uni"]])
    fav.add((x["id"], s["uni"], s["name"]))
w(f"-- Favourites ({len(fav)} rows, many-to-many linking table) -------------------")
w("INSERT INTO public.favourites (user_id, space_id) VALUES")
w(",\n".join(f"  ('{uid}', {space_ref(dict(uni=un, name=nm))})" for uid, un, nm in sorted(fav)) + ";\n")

LIVE_SQL = """-- Live activity: about 70 % of seeded students are "studying right now".
-- Re-run this block (or 03_demo_live_activity.sql) right before a demo.
INSERT INTO public.check_ins (user_id, space_id, uses_outlet, started_at, expires_at)
SELECT p.id, pick.id, random() < 0.6,
       now() - make_interval(mins => (random() * 100)::int),       -- started up to 100 min ago
       now() + make_interval(mins => 20 + (random() * 60)::int)    -- ends in 20–80 min (always <= start + 3 h)
FROM public.profiles p
CROSS JOIN LATERAL (
  SELECT s.id FROM public.study_spaces s
  WHERE s.university_id = p.university_id AND s.is_active
  ORDER BY random() / s.seat_capacity ^ 0.7 LIMIT 1
) pick
WHERE p.role = 'student' AND random() < 0.7;
"""
w(LIVE_SQL)
w("COMMIT;")
(ROOT / "database" / "02_seed.sql").write_text("\n".join(out) + "\n")
(ROOT / "database" / "03_demo_live_activity.sql").write_text(
    "-- OrynTap — refresh live check-ins before a demo (closes old ones automatically)\n"
    "UPDATE public.check_ins SET left_at = least(now(), expires_at) WHERE left_at IS NULL;\n\n" + LIVE_SQL)

# ------------------------------------------------------------ demo JS
demo = dict(
    universities=[dict(id=i, code=u["code"], name=u["name"], short=u["short"], address=u["address"],
                       domains=u["domains"], map_image_url=u["map"], map_embed_url=u.get("embed")) for i, u in enumerate(UNIVERSITIES, 1)],
    spaces=[],
)
uid_by_code = {u["code"]: i for i, u in enumerate(UNIVERSITIES, 1)}
for i, s in enumerate(SPACES, 1):
    mx, my = s.get("map") or (None, None)
    demo["spaces"].append(dict(
        id=i, university_id=uid_by_code[s["uni"]], university_code=s["uni"], name=s["name"], kind=s["kind"],
        building=s["building"], floor=s["floor"], description=s["desc"], image_url=cover_path(i, s), image_credit=credit(i, s),
        seat_capacity=s["seats"], outlet_capacity=s["outlets"], counts_exact=s.get("exact", False), is_quiet=s["quiet"], group_work=s["group"],
        food_allowed=s["food"], map_x=mx, map_y=my,
        hours=[dict(weekday=d, opens=o, closes=c) for d, (o, c) in sorted(s["hours"].items())]))
(ROOT / "js" / "demo-data.js").write_text(
    "// Generated by database/generate_seed.py — same data as database/02_seed.sql\n"
    "window.ORYNTAP_DEMO = " + json.dumps(demo, indent=1, ensure_ascii=False) + ";\n")

# ------------------------------------------------------------ cover art
def cover_svg(kind, hue, seed):
    r = random.Random(seed)
    H = hue
    def c(l, s=45, a=1, hh=None): return f"hsla({H if hh is None else hh},{s}%,{l}%,{a})"
    g = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 270" preserveAspectRatio="xMidYMid slice">',
         f'<defs><linearGradient id="w" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{c(96,30)}"/><stop offset="1" stop-color="{c(88,25)}"/></linearGradient>'
         f'<linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{c(70,20)}"/><stop offset="1" stop-color="{c(58,22)}"/></linearGradient></defs>',
         '<rect width="480" height="270" fill="url(#w)"/>',
         '<polygon points="0,190 480,190 480,270 0,270" fill="url(#f)"/>']
    acc = c(52, 70, hh=(H + 140) % 360)     # furniture accent
    acc2 = c(60, 75, hh=(H + 40) % 360)
    if kind == "library":
        for x0 in (20, 260):
            g.append(f'<rect x="{x0}" y="40" width="200" height="150" fill="{c(99,10)}" stroke="{c(80,15)}"/>')
            for row in range(4):
                y = 48 + row * 36
                g.append(f'<rect x="{x0}" y="{y+28}" width="200" height="4" fill="{c(80,15)}"/>')
                x = x0 + 6
                while x < x0 + 190:
                    bw = r.randint(6, 12); bh = r.randint(18, 26)
                    if r.random() < 0.8:
                        g.append(f'<rect x="{x}" y="{y+28-bh}" width="{bw}" height="{bh}" fill="hsl({r.choice([H, H+150, H+30, 20, 45])},{r.randint(35,60)}%,{r.randint(40,65)}%)"/>')
                    x += bw + 2
        g.append(f'<rect x="150" y="205" width="180" height="10" rx="3" fill="{c(35,15)}"/>'
                 f'<rect x="160" y="215" width="6" height="40" fill="{c(30,10)}"/><rect x="314" y="215" width="6" height="40" fill="{c(30,10)}"/>'
                 f'<rect x="60" y="200" width="70" height="55" rx="10" fill="{acc}"/><rect x="350" y="200" width="70" height="55" rx="10" fill="{acc}"/>')
    elif kind == "coworking":
        for i in range(6):
            g.append(f'<rect x="{20+i*76}" y="30" width="64" height="120" fill="{c(85,40)}" stroke="{c(75,20)}"/>')
        for tx in (40, 260):
            g.append(f'<rect x="{tx}" y="185" width="180" height="12" rx="3" fill="{c(97,5)}" stroke="{c(70,10)}"/>')
            for k in range(3):
                g.append(f'<rect x="{tx+15+k*55}" y="168" width="30" height="18" rx="2" fill="{c(25,10)}"/>'
                         f'<rect x="{tx+12+k*55}" y="210" width="36" height="34" rx="8" fill="{acc if k%2 else acc2}"/>')
        g.append(f'<circle cx="455" cy="170" r="22" fill="hsl(120,35%,38%)"/><rect x="445" y="185" width="20" height="25" fill="{c(40,15)}"/>')
    elif kind == "atrium":
        for i in range(13):
            g.append(f'<line x1="{i*40}" y1="0" x2="{240+(i*40-240)*0.6}" y2="70" stroke="{c(75,15)}" stroke-width="2"/>')
        g.append(f'<rect x="0" y="70" width="480" height="4" fill="{c(75,15)}"/>')
        for i in range(8):
            g.append(f'<rect x="{30+i*60}" y="74" width="6" height="116" fill="{c(97,5)}" stroke="{c(80,10)}"/>')
        for i in range(5):
            x = 25 + i * 92 + r.randint(-8, 8)
            g.append(f'<rect x="{x}" y="{200+r.randint(-6,10)}" width="62" height="34" rx="6" fill="{acc}"/>'
                     f'<rect x="{x}" y="{226+r.randint(-4,4)}" width="62" height="16" rx="4" fill="{c(25,10)}"/>')
    elif kind == "rooms":
        for i in range(4):
            x = 15 + i * 118
            g.append(f'<rect x="{x}" y="45" width="108" height="145" fill="{c(88,35,0.55)}" stroke="{c(55,20)}" stroke-width="3"/>'
                     f'<rect x="{x+20}" y="140" width="68" height="10" rx="2" fill="{c(97,5)}"/>'
                     f'<rect x="{x+24}" y="150" width="4" height="40" fill="{c(40,10)}"/><rect x="{x+80}" y="150" width="4" height="40" fill="{c(40,10)}"/>'
                     f'<circle cx="{x+54}" cy="90" r="18" fill="{acc2 if i%2 else acc}" opacity=".85"/>')
    elif kind == "cafe":
        g.append(f'<rect x="250" y="120" width="210" height="75" rx="6" fill="{c(35,25)}"/><rect x="250" y="112" width="210" height="10" rx="3" fill="{c(92,10)}"/>'
                 f'<rect x="280" y="60" width="150" height="40" rx="6" fill="{c(25,15)}"/><rect x="292" y="70" width="60" height="5" fill="{c(90,10)}"/><rect x="292" y="82" width="90" height="5" fill="{c(90,10)}"/>')
        for k in range(4):
            g.append(f'<rect x="{270+k*45}" y="96" width="16" height="16" rx="3" fill="{c(97,5)}" stroke="{c(60,10)}"/>')
        for x in (60, 170):
            g.append(f'<ellipse cx="{x}" cy="205" rx="40" ry="10" fill="{c(97,5)}" stroke="{c(70,10)}"/><rect x="{x-3}" y="205" width="6" height="45" fill="{c(35,10)}"/>'
                     f'<rect x="{x-58}" y="215" width="22" height="34" rx="6" fill="{acc}"/><rect x="{x+36}" y="215" width="22" height="34" rx="6" fill="{acc2}"/>')
    else:  # lounge
        g.append(f'<rect x="0" y="30" width="480" height="8" fill="{c(80,15)}"/>')
        for i in range(3):
            x = 30 + i * 150
            g.append(f'<rect x="{x}" y="160" width="110" height="45" rx="14" fill="{acc if i!=1 else acc2}"/>'
                     f'<rect x="{x-6}" y="195" width="122" height="28" rx="10" fill="{c(30,15)}"/>'
                     f'<ellipse cx="{x+55}" cy="245" rx="30" ry="8" fill="{c(97,5)}" stroke="{c(70,10)}"/>')
        for x in (15, 465):
            g.append(f'<circle cx="{x}" cy="140" r="26" fill="hsl(130,35%,38%)"/><rect x="{x-10}" y="160" width="20" height="30" fill="{c(40,15)}"/>')
        for i in range(5):
            g.append(f'<circle cx="{60+i*90}" cy="60" r="10" fill="{c(99,60)}" stroke="{c(80,20)}"/>')
    g.append("</svg>")
    return "".join(g)

hue_by = {u["code"]: u["hue"] for u in UNIVERSITIES}
for old in (ROOT / "assets/img").glob("cover-*.svg"):
    old.unlink()
for i, s in enumerate(SPACES, 1):
    if not s["image"] and not local_photo(i):
        (ROOT / cover_path(i, s)).write_text(cover_svg(s["kind"], hue_by[s["uni"]], i))
# Fallback pictures used by the site if a remote photo cannot load
for k in ("library", "coworking", "atrium", "rooms", "lounge", "cafe"):
    (ROOT / f"assets/img/fallback-{k}.svg").write_text(cover_svg(k, 215, 7))

print(f"universities={len(UNIVERSITIES)} spaces={len(SPACES)} users={len([x for x in USERS if x['role'] == 'student'])} "
      f"check_ins={len(hist)}+live favourites={len(fav)}")
