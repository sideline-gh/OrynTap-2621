-- =====================================================================
-- OrynTap — PostgreSQL schema (Supabase or local PostgreSQL 14+)
-- ---------------------------------------------------------------------
-- Entities
--   universities 1─N email_domains
--   universities 1─N profiles          (profiles 1─1 auth.users)
--   universities 1─N study_spaces
--   study_spaces 1─N opening_hours
--   profiles     1─N check_ins N─1 study_spaces
--   profiles     N─M study_spaces   via favourites (linking table)
--   study_spaces 1─1 space_activity (realtime "something changed" ping)
--   audit_log    (append-only admin action log)
--
-- Security
--   * Passwords are never stored here: Supabase Auth keeps them in
--     auth.users.encrypted_password as bcrypt hashes.
--   * Row-Level Security on every table + least-privilege GRANTs.
--   * Only university e-mail domains can create an account (trigger).
--   * Role can only be changed by the database owner, never by the client.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Clean re-run support -------------------------------------------------
DROP VIEW     IF EXISTS public.space_availability CASCADE;
DROP TABLE    IF EXISTS public.audit_log, public.favourites, public.check_ins,
                        public.space_activity, public.opening_hours, public.study_spaces,
                        public.profiles, public.email_domains, public.universities CASCADE;
DROP TRIGGER  IF EXISTS on_auth_user_created ON auth.users;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
CREATE TABLE public.universities (
  id             smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code           varchar(8)   NOT NULL UNIQUE CHECK (code ~ '^[A-Z]{2,8}$'),
  name           varchar(120) NOT NULL UNIQUE,
  city           varchar(60)  NOT NULL DEFAULT 'Astana',
  address        varchar(160),
  map_image_url  text,
  map_embed_url  text,                               -- interactive campus map (iframe)
  created_at     timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE public.email_domains (
  domain         varchar(100) PRIMARY KEY CHECK (domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  university_id  smallint NOT NULL REFERENCES public.universities(id) ON DELETE CASCADE
);

CREATE TABLE public.profiles (
  id             uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name     varchar(50) NOT NULL CHECK (length(trim(first_name)) > 0),
  last_name      varchar(50) NOT NULL DEFAULT '',
  university_id  smallint    NOT NULL REFERENCES public.universities(id) ON DELETE RESTRICT,
  role           varchar(10) NOT NULL DEFAULT 'student' CHECK (role IN ('student', 'admin')),
  consent_at     timestamptz,   -- when the user agreed to personal-data processing (Law RK 94-V, Art. 8)
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.study_spaces (
  id               integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  university_id    smallint     NOT NULL REFERENCES public.universities(id) ON DELETE CASCADE,
  name             varchar(80)  NOT NULL CHECK (length(trim(name)) > 0),
  kind             varchar(12)  NOT NULL CHECK (kind IN ('library','coworking','atrium','rooms','lounge','cafe')),
  building         varchar(80),
  floor            varchar(20),
  description      text,
  image_url        text,
  image_credit     varchar(80),                       -- photo source, shown on the card
  seat_capacity    integer      NOT NULL CHECK (seat_capacity BETWEEN 1 AND 2000),
  outlet_capacity  integer      NOT NULL CHECK (outlet_capacity BETWEEN 0 AND 5000),
  counts_exact     boolean      NOT NULL DEFAULT false, -- true = seats/outlets counted exactly (no "~")
  is_quiet         boolean      NOT NULL DEFAULT false,
  group_work       boolean      NOT NULL DEFAULT false,
  food_allowed     boolean      NOT NULL DEFAULT false,
  map_x            numeric(5,2) CHECK (map_x BETWEEN 0 AND 100),
  map_y            numeric(5,2) CHECK (map_y BETWEEN 0 AND 100),
  is_active        boolean      NOT NULL DEFAULT true,
  updated_at       timestamptz  NOT NULL DEFAULT now(),
  UNIQUE (university_id, name)
);

-- weekday uses ISO numbering: 1 = Monday ... 7 = Sunday.
-- A day without a row means "closed". 00:00–24:00 means "open 24 hours".
CREATE TABLE public.opening_hours (
  space_id   integer  NOT NULL REFERENCES public.study_spaces(id) ON DELETE CASCADE,
  weekday    smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),
  opens      time     NOT NULL,
  closes     time     NOT NULL,
  PRIMARY KEY (space_id, weekday),
  CHECK (closes > opens)
);

CREATE TABLE public.check_ins (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id      uuid        NOT NULL REFERENCES public.profiles(id)     ON DELETE CASCADE,
  space_id     integer     NOT NULL REFERENCES public.study_spaces(id) ON DELETE CASCADE,
  uses_outlet  boolean     NOT NULL DEFAULT false,
  started_at   timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL,
  left_at      timestamptz,
  CHECK (expires_at > started_at AND expires_at <= started_at + interval '3 hours'),
  CHECK (left_at IS NULL OR left_at >= started_at)
);
-- R2 / risk 2: at most ONE open check-in per person
CREATE UNIQUE INDEX one_open_check_in_per_user ON public.check_ins(user_id) WHERE left_at IS NULL;
CREATE INDEX check_ins_space_active_idx ON public.check_ins(space_id, expires_at) WHERE left_at IS NULL;
CREATE INDEX check_ins_started_idx      ON public.check_ins(started_at);

CREATE TABLE public.favourites (
  user_id     uuid        NOT NULL REFERENCES public.profiles(id)     ON DELETE CASCADE,
  space_id    integer     NOT NULL REFERENCES public.study_spaces(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, space_id)
);

CREATE TABLE public.space_activity (
  space_id     integer PRIMARY KEY REFERENCES public.study_spaces(id) ON DELETE CASCADE,
  last_change  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor       uuid,
  action      varchar(10) NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  table_name  varchar(40) NOT NULL,
  record_id   text,
  details     jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. Helper functions & triggers
-- ---------------------------------------------------------------------

-- Is the current user an administrator of the given university?
CREATE OR REPLACE FUNCTION public.is_admin_of(p_university smallint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles
                 WHERE id = auth.uid() AND role = 'admin' AND university_id = p_university);
$$;

CREATE OR REPLACE FUNCTION public.is_any_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin');
$$;

-- R1: when an account is created, accept only university e-mail domains
-- and create the matching profile. The admin role is given only to the
-- three team e-mails below; everybody else becomes a student. The browser
-- cannot change this (profiles.role is not updatable by users).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_domain text := lower(split_part(NEW.email, '@', 2));
  v_uni    smallint;
  v_full   text := coalesce(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', '');
BEGIN
  SELECT d.university_id INTO v_uni
  FROM public.email_domains d
  WHERE v_domain = d.domain OR v_domain LIKE '%.' || d.domain
  LIMIT 1;

  IF v_uni IS NULL THEN
    RAISE EXCEPTION 'Only university e-mail addresses can register (got "%")', v_domain
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.profiles (id, first_name, last_name, university_id, role, consent_at)
  VALUES (
    NEW.id,
    left(coalesce(nullif(NEW.raw_user_meta_data->>'first_name', ''),
                  nullif(split_part(v_full, ' ', 1), ''),
                  initcap(split_part(NEW.email, '@', 1))), 50),
    left(coalesce(nullif(NEW.raw_user_meta_data->>'last_name', ''),
                  nullif(substr(v_full, length(split_part(v_full, ' ', 1)) + 2), ''), ''), 50),
    v_uni,
    CASE WHEN lower(NEW.email) IN ('260925@astanait.edu.kz',   -- Omirzak Amina
                                   '261234@astanait.edu.kz',   -- Khaval Nurdaulet
                                   '261584@astanait.edu.kz')   -- Bekshoinov Dias
         THEN 'admin' ELSE 'student' END,
    -- sign-up form: the consent box was ticked
    CASE WHEN NEW.raw_user_meta_data->>'consent' = 'true' THEN now() END
  );
  RETURN NEW;
END $$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Before a new check-in: close the user's previous open check-in and,
-- for real users (not seed scripts), force the start time to "now"
-- so nobody can back-date or pre-book a seat from the browser.
CREATE OR REPLACE FUNCTION public.before_check_in()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_len interval;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    v_len := NEW.expires_at - NEW.started_at;
    NEW.started_at := now();
    NEW.expires_at := now() + least(greatest(v_len, interval '15 minutes'), interval '3 hours');
    NEW.left_at    := NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.study_spaces WHERE id = NEW.space_id AND is_active) THEN
    RAISE EXCEPTION 'This study space is not available';
  END IF;

  UPDATE public.check_ins
     SET left_at = least(now(), expires_at)
   WHERE user_id = NEW.user_id AND left_at IS NULL;
  RETURN NEW;
END $$;

CREATE TRIGGER check_ins_before_insert
  BEFORE INSERT ON public.check_ins
  FOR EACH ROW EXECUTE FUNCTION public.before_check_in();

-- "Leave": a user can only set left_at, and only to the current time.
CREATE OR REPLACE FUNCTION public.before_check_out()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    IF OLD.left_at IS NOT NULL THEN RAISE EXCEPTION 'Already checked out'; END IF;
    NEW.left_at := least(now(), OLD.expires_at);
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER check_ins_before_update
  BEFORE UPDATE ON public.check_ins
  FOR EACH ROW EXECUTE FUNCTION public.before_check_out();

-- Ping space_activity on every check-in / leave so other devices refresh (R4, R9)
CREATE OR REPLACE FUNCTION public.touch_space_activity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.space_activity (space_id, last_change)
  VALUES (NEW.space_id, now())
  ON CONFLICT (space_id) DO UPDATE SET last_change = excluded.last_change;
  RETURN NEW;
END $$;

CREATE TRIGGER check_ins_touch_activity
  AFTER INSERT OR UPDATE ON public.check_ins
  FOR EACH ROW EXECUTE FUNCTION public.touch_space_activity();

-- Keep study_spaces.updated_at current
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

CREATE TRIGGER study_spaces_updated_at
  BEFORE UPDATE ON public.study_spaces
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Logging: every change an administrator makes to spaces or hours
CREATE OR REPLACE FUNCTION public.write_audit_log()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.audit_log (actor, action, table_name, record_id, details)
  VALUES (
    auth.uid(), TG_OP, TG_TABLE_NAME,
    coalesce(to_jsonb(coalesce(NEW, OLD))->>'id', to_jsonb(coalesce(NEW, OLD))->>'space_id'),
    jsonb_build_object('old', CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
                       'new', CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END)
  );
  RETURN coalesce(NEW, OLD);
END $$;

CREATE TRIGGER study_spaces_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.study_spaces
  FOR EACH ROW WHEN (auth.uid() IS NOT NULL) EXECUTE FUNCTION public.write_audit_log();
CREATE TRIGGER opening_hours_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.opening_hours
  FOR EACH ROW WHEN (auth.uid() IS NOT NULL) EXECUTE FUNCTION public.write_audit_log();

-- ---------------------------------------------------------------------
-- 3. Read model for the interface (one query = all cards)
-- ---------------------------------------------------------------------
-- Exposes only aggregated counts — never who is checked in where.
CREATE VIEW public.space_availability AS
SELECT
  s.id, s.university_id, u.code AS university_code, s.name, s.kind,
  s.building, s.floor, s.description, s.image_url, s.image_credit,
  s.seat_capacity, s.outlet_capacity, s.counts_exact, s.is_quiet, s.group_work, s.food_allowed,
  s.map_x, s.map_y,
  greatest(s.seat_capacity   - count(c.id), 0)                              AS free_seats,
  greatest(s.outlet_capacity - count(c.id) FILTER (WHERE c.uses_outlet), 0) AS free_outlets,
  coalesce(a.last_change, s.updated_at)                                     AS updated_at,
  coalesce((SELECT json_agg(json_build_object('weekday', h.weekday,
                                              'opens',  to_char(h.opens,  'HH24:MI'),
                                              'closes', to_char(h.closes, 'HH24:MI'))
                            ORDER BY h.weekday)
            FROM public.opening_hours h WHERE h.space_id = s.id), '[]'::json) AS hours
FROM public.study_spaces s
JOIN public.universities u        ON u.id = s.university_id
LEFT JOIN public.space_activity a ON a.space_id = s.id
LEFT JOIN public.check_ins c      ON c.space_id = s.id
                                  AND c.left_at IS NULL
                                  AND c.expires_at > now()
WHERE s.is_active
GROUP BY s.id, u.code, a.last_change;

-- Admin insight: check-ins per space and hour of day (last 30 days).
CREATE OR REPLACE FUNCTION public.admin_usage_by_hour()
RETURNS TABLE (space_id integer, space_name varchar, hour_of_day int, check_ins bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.name,
         extract(hour FROM c.started_at AT TIME ZONE 'Asia/Almaty')::int,
         count(*)
  FROM public.check_ins c
  JOIN public.study_spaces s ON s.id = c.space_id
  WHERE public.is_admin_of(s.university_id)
    AND c.started_at > now() - interval '30 days'
  GROUP BY 1, 2, 3
  ORDER BY 1, 3;
$$;

-- ---------------------------------------------------------------------
-- 4. Row-Level Security
-- ---------------------------------------------------------------------
ALTER TABLE public.universities   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_domains  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.study_spaces   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opening_hours  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.check_ins      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favourites     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.space_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log      ENABLE ROW LEVEL SECURITY;

-- Public catalogue (anyone, even logged out, can browse)
CREATE POLICY universities_read   ON public.universities   FOR SELECT USING (true);
CREATE POLICY email_domains_read  ON public.email_domains  FOR SELECT USING (true);
CREATE POLICY spaces_read         ON public.study_spaces   FOR SELECT USING (true);
CREATE POLICY hours_read          ON public.opening_hours  FOR SELECT USING (true);
CREATE POLICY activity_read       ON public.space_activity FOR SELECT USING (true);

-- Administrators manage the spaces of THEIR OWN university only
CREATE POLICY spaces_admin_insert ON public.study_spaces FOR INSERT TO authenticated
  WITH CHECK (public.is_admin_of(university_id));
CREATE POLICY spaces_admin_update ON public.study_spaces FOR UPDATE TO authenticated
  USING (public.is_admin_of(university_id)) WITH CHECK (public.is_admin_of(university_id));
CREATE POLICY spaces_admin_delete ON public.study_spaces FOR DELETE TO authenticated
  USING (public.is_admin_of(university_id));
CREATE POLICY hours_admin_all     ON public.opening_hours FOR ALL TO authenticated
  USING      (EXISTS (SELECT 1 FROM public.study_spaces s WHERE s.id = space_id AND public.is_admin_of(s.university_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.study_spaces s WHERE s.id = space_id AND public.is_admin_of(s.university_id)));

-- Profiles: you see and edit yourself; an admin sees their university's users
CREATE POLICY profiles_read_self  ON public.profiles FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.is_admin_of(university_id));
CREATE POLICY profiles_update_self ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- Check-ins and favourites are private to their owner
CREATE POLICY check_ins_own_read   ON public.check_ins FOR SELECT TO authenticated USING (user_id = auth.uid());
-- A student can check in only for themselves and only at their own university
CREATE POLICY check_ins_own_insert ON public.check_ins FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.study_spaces s JOIN public.profiles p ON p.id = auth.uid()
    WHERE s.id = space_id AND s.university_id = p.university_id));
CREATE POLICY check_ins_own_update ON public.check_ins FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY favourites_own_read   ON public.favourites FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY favourites_own_insert ON public.favourites FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY favourites_own_delete ON public.favourites FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE POLICY audit_admin_read ON public.audit_log FOR SELECT TO authenticated USING (public.is_any_admin());

-- ---------------------------------------------------------------------
-- 5. Least-privilege GRANTs (on top of RLS)
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon, authenticated, PUBLIC;
GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT ON public.universities, public.email_domains, public.study_spaces,
                public.opening_hours, public.space_activity, public.space_availability
             TO anon, authenticated;

GRANT SELECT                         ON public.profiles TO authenticated;
GRANT UPDATE (first_name, last_name) ON public.profiles TO authenticated;   -- not role, not university

GRANT SELECT, INSERT (space_id, user_id, uses_outlet, started_at, expires_at) ON public.check_ins TO authenticated;
GRANT UPDATE (left_at)                                                         ON public.check_ins TO authenticated;

GRANT SELECT, INSERT, DELETE ON public.favourites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.study_spaces, public.opening_hours TO authenticated; -- RLS limits to admins
GRANT SELECT ON public.audit_log TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_admin_of(smallint), public.is_any_admin(),
                          public.admin_usage_by_hour() TO authenticated;

-- ---------------------------------------------------------------------
-- 6. Realtime: push "something changed" to every open browser
-- ---------------------------------------------------------------------
ALTER PUBLICATION supabase_realtime ADD TABLE public.space_activity, public.study_spaces;
