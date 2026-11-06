-- =====================================================================
-- OrynTap · update of 4 Nov 2026: improvements approved by the team
-- Run ONCE in Supabase -> SQL Editor AFTER 09_photos_verification.sql. Safe to run again.
--
--   1. Data fixes: Sheker is between Blocks C1 and C2, Mokko between C2 and C3;
--      new Open Space photo (480/960 px WebP)
--   2. A check-in ends at the place's closing time at the latest (automatic check-out)
--   3. "Extend 1 h": extend_check_in()  (never more than 3 h ahead, never past closing)
--   4. "Usually busy": space_busy_hours()  (counts per hour only, nobody can be identified)
--   5. "Wrong number?" reports from students: count_reports, report_count(),
--      admin_count_reports()
-- Nothing here changes first come, first served or QR check-in / check-out.
-- =====================================================================
BEGIN;

-- 1. Data fixes ---------------------------------------------------------
UPDATE public.study_spaces SET building = 'Between Blocks C1 and C2, opposite the wardrobe'
 WHERE name = 'Sheker' AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');
UPDATE public.study_spaces SET building = 'Between Blocks C2 and C3, opposite the wardrobe'
 WHERE name = 'Mokko'  AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');
UPDATE public.study_spaces SET image_url = 'assets/img/aitu-open-space-480.webp', image_credit = NULL,
       image_alt = 'Wide open atrium with a grey carpet, glass walls and green sofas along the far side'
 WHERE name = 'Open Space' AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');

-- 2. Closing time --------------------------------------------------------
-- Closing time of a space on the day of p_at (Astana time, UTC+5), if p_at is within that
-- day's opening hours; NULL if the place is closed then or closes at midnight (24 h places).
CREATE OR REPLACE FUNCTION public.closing_time(p_space integer, p_at timestamptz)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT ((x.lt::date + h.closes) - interval '5 hours') AT TIME ZONE 'UTC'
  FROM (SELECT (p_at AT TIME ZONE 'UTC') + interval '5 hours' AS lt) x
  JOIN public.opening_hours h ON h.space_id = p_space AND h.weekday = extract(isodow FROM x.lt)::int
  WHERE h.closes < time '24:00'
    AND x.lt >= x.lt::date + h.opens AND x.lt < x.lt::date + h.closes;
$$;
REVOKE ALL ON FUNCTION public.closing_time(integer, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.closing_time(integer, timestamptz) TO anon, authenticated;

-- A new check-in never lasts past closing time: the seat is free again when the place closes.
CREATE OR REPLACE FUNCTION public.check_in_until_closing()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_close timestamptz := public.closing_time(NEW.space_id, NEW.started_at);
BEGIN
  IF v_close IS NOT NULL AND NEW.expires_at > v_close THEN NEW.expires_at := v_close; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS check_ins_until_closing ON public.check_ins;
CREATE TRIGGER check_ins_until_closing BEFORE INSERT ON public.check_ins
  FOR EACH ROW EXECUTE FUNCTION public.check_in_until_closing();

-- 3. Extend 1 h ------------------------------------------------------------
-- The 3-hour limit now means "at most 3 hours ahead": at check-in (as before) and when
-- extending (function below). The table rule allows a day of extensions (12 h in total).
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
           WHERE conrelid = 'public.check_ins'::regclass AND contype = 'c'
             AND pg_get_constraintdef(oid) LIKE '%03:00:00%' LOOP
    EXECUTE format('ALTER TABLE public.check_ins DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE public.check_ins DROP CONSTRAINT IF EXISTS check_ins_length;
ALTER TABLE public.check_ins ADD CONSTRAINT check_ins_length
  CHECK (expires_at > started_at AND expires_at <= started_at + interval '12 hours');

-- (A new check-in is still limited to 3 hours by before_check_in() in 01_schema.sql.)
-- "Leave" stays as before: an UPDATE by a student only sets left_at to now. The one exception is
-- extend_check_in() below, which marks its own transaction; students cannot change expires_at
-- themselves (they may only UPDATE the column left_at, 01_schema.sql).
CREATE OR REPLACE FUNCTION public.before_check_out()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    IF OLD.left_at IS NOT NULL THEN RAISE EXCEPTION 'Already checked out'; END IF;
    IF current_setting('oryntap.extending', true) = 'on' THEN
      NEW.left_at := NULL; NEW.started_at := OLD.started_at;   -- extension: only expires_at changes
    ELSE
      NEW.left_at := least(now(), OLD.expires_at);
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.extend_check_in(p_id bigint)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c public.check_ins; v_new timestamptz; v_close timestamptz;
BEGIN
  IF NOT public.email_verified() THEN RAISE EXCEPTION 'not_verified' USING ERRCODE = '42501'; END IF;
  SELECT * INTO c FROM public.check_ins
   WHERE id = p_id AND user_id = auth.uid() AND left_at IS NULL AND expires_at > now() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'no_active_check_in' USING ERRCODE = 'P0002'; END IF;
  v_new := least(c.expires_at + interval '1 hour', now() + interval '3 hours');
  v_close := public.closing_time(c.space_id, now());
  IF v_close IS NOT NULL THEN v_new := least(v_new, v_close); END IF;
  IF v_new < c.expires_at + interval '1 minute' THEN RAISE EXCEPTION 'cannot_extend' USING ERRCODE = 'P0001'; END IF;
  PERFORM set_config('oryntap.extending', 'on', true);
  UPDATE public.check_ins SET expires_at = v_new WHERE id = c.id;
  PERFORM set_config('oryntap.extending', 'off', true);
  RETURN v_new;
END $$;
REVOKE ALL ON FUNCTION public.extend_check_in(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.extend_check_in(bigint) TO authenticated;

-- 4. Usually busy -----------------------------------------------------------
-- For each space: how many finished check-ins of the last 8 weeks covered each hour of the
-- day (Astana time). Only aggregate counts, and only for spaces with at least 15 check-ins,
-- so no single visit can be seen. Readable by everyone, like the free-seat counts.
CREATE OR REPLACE FUNCTION public.space_busy_hours(p_university smallint)
RETURNS TABLE (space_id integer, hour_of_day int, presence bigint, check_ins bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH c AS (
    SELECT c.space_id,
           (c.started_at AT TIME ZONE 'UTC') + interval '5 hours' AS s,
           (least(coalesce(c.left_at, c.expires_at), c.expires_at) AT TIME ZONE 'UTC') + interval '5 hours' AS e
    FROM public.check_ins c JOIN public.study_spaces sp ON sp.id = c.space_id
    WHERE sp.university_id = p_university AND sp.is_active
      AND c.started_at > now() - interval '56 days'
      AND (c.left_at IS NOT NULL OR c.expires_at <= now())
  ), n AS (SELECT c.space_id, count(*) AS n FROM c GROUP BY 1 HAVING count(*) >= 15)
  SELECT c.space_id, extract(hour FROM h)::int, count(*), n.n
  FROM c JOIN n ON n.space_id = c.space_id
  CROSS JOIN LATERAL generate_series(date_trunc('hour', c.s), c.e - interval '1 second', interval '1 hour') AS h
  GROUP BY 1, 2, n.n
  ORDER BY 1, 2;
$$;
REVOKE ALL ON FUNCTION public.space_busy_hours(smallint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.space_busy_hours(smallint) TO anon, authenticated;

-- 5. "Wrong number?" reports ----------------------------------------------------
-- A student says what they see at a place: full, many free seats, or closed. Only admins of
-- that university read the reports; the free-seat numbers are NOT changed by them.
CREATE TABLE IF NOT EXISTS public.count_reports (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  space_id    integer NOT NULL REFERENCES public.study_spaces(id) ON DELETE CASCADE,
  user_id     uuid    NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind        varchar(8) NOT NULL CHECK (kind IN ('full', 'empty', 'closed')),
  shown_free  integer CHECK (shown_free >= 0),      -- free seats the app showed at that moment
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS count_reports_space_idx ON public.count_reports(space_id, created_at);
ALTER TABLE public.count_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.count_reports FROM anon, authenticated;   -- only through the functions below

CREATE OR REPLACE FUNCTION public.report_count(p_space integer, p_kind text, p_shown_free integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.email_verified() THEN RAISE EXCEPTION 'not_verified' USING ERRCODE = '42501'; END IF;
  IF p_kind NOT IN ('full', 'empty', 'closed') THEN RAISE EXCEPTION 'bad_kind' USING ERRCODE = '22023'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.study_spaces s JOIN public.profiles p ON p.id = auth.uid()
                 WHERE s.id = p_space AND s.university_id = p.university_id) THEN
    RAISE EXCEPTION 'own_university_only' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM public.count_reports
             WHERE user_id = auth.uid() AND space_id = p_space AND created_at > now() - interval '10 minutes') THEN
    RAISE EXCEPTION 'too_soon' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO public.count_reports (space_id, user_id, kind, shown_free)
  VALUES (p_space, auth.uid(), p_kind, greatest(p_shown_free, 0));
END $$;
REVOKE ALL ON FUNCTION public.report_count(integer, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_count(integer, text, integer) TO authenticated;

-- Admin: reports of the last 7 days per space of their university (no names, only counts)
CREATE OR REPLACE FUNCTION public.admin_count_reports()
RETURNS TABLE (space_id integer, space_name varchar, full_n bigint, empty_n bigint, closed_n bigint, last_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.name,
         count(*) FILTER (WHERE r.kind = 'full'), count(*) FILTER (WHERE r.kind = 'empty'),
         count(*) FILTER (WHERE r.kind = 'closed'), max(r.created_at)
  FROM public.count_reports r JOIN public.study_spaces s ON s.id = r.space_id
  WHERE public.is_admin_of(s.university_id) AND r.created_at > now() - interval '7 days'
  GROUP BY s.id, s.name
  ORDER BY max(r.created_at) DESC;
$$;
REVOKE ALL ON FUNCTION public.admin_count_reports() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_count_reports() TO authenticated;

COMMIT;
