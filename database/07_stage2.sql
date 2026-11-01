-- =====================================================================
-- OrynTap · Project Stage 2 (End-term), Oct 2026
-- Run ONCE in Supabase -> SQL Editor after 06_update_multimedia.sql
-- (a fresh install runs 01, 02 and then this file). Safe to run again.
--
--   Part C5  admin statistics shown inside the app:
--            admin_space_stats()  use of each space for its size + outlet share
--            admin_stay_stats()   real stay length, left early vs ended by itself
--   Part D3  smart extension (simulated door sensors):
--            sensors, sensor_readings, register_sensor(), ingest_reading(),
--            view space_sensor_now, purge_sensor_readings()
-- =====================================================================
BEGIN;
SET LOCAL search_path = public, extensions;

-- ---------------------------------------------------------------------
-- C5. Statistics for the administrator screen (same logic as analysis/queries.sql)
--     Only finished check-ins, only the admin's university. No date window,
--     because the generated test history is fixed in time (see analysis/queries.sql);
--     with real users add: AND c.started_at > now() - interval '30 days'.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_space_stats()
RETURNS TABLE (space_id integer, space_name varchar, seats integer, check_ins bigint,
               per_100_seats numeric, pct_with_outlet numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.name, s.seat_capacity,
         count(c.id),
         round(100.0 * count(c.id) / s.seat_capacity, 1),
         round(100.0 * avg(c.uses_outlet::int), 0)
  FROM public.study_spaces s
  LEFT JOIN public.check_ins c
         ON c.space_id = s.id
        AND (c.left_at IS NOT NULL OR c.expires_at <= now())
  WHERE public.is_admin_of(s.university_id)
  GROUP BY s.id, s.name, s.seat_capacity
  ORDER BY 5 DESC;
$$;

CREATE OR REPLACE FUNCTION public.admin_stay_stats()
RETURNS TABLE (planned_hours integer, check_ins bigint, avg_stay_min numeric,
               pct_left_early numeric, pct_ended_by_itself numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT round(extract(epoch FROM c.expires_at - c.started_at) / 3600)::int,
         count(*),
         round(avg(extract(epoch FROM least(coalesce(c.left_at, c.expires_at), c.expires_at) - c.started_at) / 60)),
         round(100.0 * avg((c.left_at IS NOT NULL AND c.left_at < c.expires_at)::int), 0),
         round(100.0 * avg((c.left_at IS NULL OR c.left_at >= c.expires_at)::int), 0)
  FROM public.check_ins c
  JOIN public.study_spaces s ON s.id = c.space_id
  WHERE public.is_admin_of(s.university_id)
    AND (c.left_at IS NOT NULL OR c.expires_at <= now())
  GROUP BY 1
  ORDER BY 1;
$$;

-- The Assignment 3 chart (busiest hours) uses the same rule from now on.
CREATE OR REPLACE FUNCTION public.admin_usage_by_hour()
RETURNS TABLE (space_id integer, space_name varchar, hour_of_day int, check_ins bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.name,
         extract(hour FROM c.started_at AT TIME ZONE 'Asia/Almaty')::int,
         count(*)
  FROM public.check_ins c
  JOIN public.study_spaces s ON s.id = c.space_id
  WHERE public.is_admin_of(s.university_id)
    AND (c.left_at IS NOT NULL OR c.expires_at <= now())
  GROUP BY 1, 2, 3
  ORDER BY 1, 3;
$$;

REVOKE ALL ON FUNCTION public.admin_space_stats(), public.admin_stay_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_space_stats(), public.admin_stay_stats() TO authenticated;

-- ---------------------------------------------------------------------
-- D3. Door sensors (simulated). A sensor counts people going in and out
--     of a study space and reports "people inside now" once a minute.
--     No camera, no phone/MAC address, no student ID: only a number.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sensors (
  id          smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  space_id    integer NOT NULL REFERENCES public.study_spaces(id) ON DELETE CASCADE,
  label       varchar(60) NOT NULL,
  token_hash  text NOT NULL UNIQUE,              -- SHA-256 of the device secret, never the secret
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sensor_readings (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sensor_id      smallint NOT NULL REFERENCES public.sensors(id) ON DELETE CASCADE,
  space_id       integer  NOT NULL REFERENCES public.study_spaces(id) ON DELETE CASCADE,
  measured_at    timestamptz NOT NULL DEFAULT now(),
  people_inside  integer NOT NULL CHECK (people_inside BETWEEN 0 AND 5000)
);
CREATE INDEX IF NOT EXISTS sensor_readings_space_time ON public.sensor_readings (space_id, measured_at DESC);

-- Only administrators of the university can see sensors and raw readings.
ALTER TABLE public.sensors         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sensor_readings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sensors_admin_read  ON public.sensors;
DROP POLICY IF EXISTS readings_admin_read ON public.sensor_readings;
CREATE POLICY sensors_admin_read ON public.sensors FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.study_spaces s WHERE s.id = space_id AND public.is_admin_of(s.university_id)));
CREATE POLICY readings_admin_read ON public.sensor_readings FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.study_spaces s WHERE s.id = space_id AND public.is_admin_of(s.university_id)));

-- Supabase gives new tables broad default privileges: take them away first.
REVOKE ALL ON public.sensors, public.sensor_readings FROM anon, authenticated;
GRANT SELECT ON public.sensors, public.sensor_readings TO authenticated;   -- RLS above = admins only

-- An administrator registers a sensor for one of their spaces and gets its
-- secret ONCE. Only the SHA-256 hash is stored.
CREATE OR REPLACE FUNCTION public.register_sensor(p_space_id integer, p_label text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uni   smallint;
  v_token text := encode(gen_random_bytes(24), 'hex');
BEGIN
  SELECT university_id INTO v_uni FROM public.study_spaces WHERE id = p_space_id;
  IF v_uni IS NULL THEN RAISE EXCEPTION 'Unknown space %', p_space_id; END IF;
  -- In the SQL Editor auth.uid() is NULL (the project owner); in the app only an admin may do this.
  IF auth.uid() IS NOT NULL AND NOT public.is_admin_of(v_uni) THEN
    RAISE EXCEPTION 'Only an administrator of this university can register sensors' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.sensors (space_id, label, token_hash)
  VALUES (p_space_id, left(coalesce(nullif(trim(p_label), ''), 'Door sensor'), 60),
          encode(digest(v_token, 'sha256'), 'hex'));
  RETURN v_token;
END $$;

-- The device (or the simulator) calls this with its own secret. It needs
-- only the public anon key, never the service_role key.
CREATE OR REPLACE FUNCTION public.ingest_reading(p_token text, p_people integer)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_sensor public.sensors%ROWTYPE;
BEGIN
  SELECT * INTO v_sensor FROM public.sensors
   WHERE token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown or disabled sensor' USING ERRCODE = '28000';
  END IF;
  IF p_people IS NULL OR p_people < 0 OR p_people > 5000 THEN
    RAISE EXCEPTION 'people_inside out of range' USING ERRCODE = '22003';
  END IF;
  -- Simple flood protection: at most one reading per sensor every 5 seconds
  IF EXISTS (SELECT 1 FROM public.sensor_readings
              WHERE sensor_id = v_sensor.id AND measured_at > now() - interval '5 seconds') THEN
    RETURN 'skipped (too frequent)';
  END IF;
  INSERT INTO public.sensor_readings (sensor_id, space_id, people_inside)
  VALUES (v_sensor.id, v_sensor.space_id, p_people);
  -- Same "something changed" ping as a check-in, so open screens refresh (Realtime)
  INSERT INTO public.space_activity (space_id, last_change) VALUES (v_sensor.space_id, now())
  ON CONFLICT (space_id) DO UPDATE SET last_change = excluded.last_change;
  RETURN 'ok';
END $$;

REVOKE ALL ON FUNCTION public.register_sensor(integer, text), public.ingest_reading(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_sensor(integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_reading(text, integer) TO anon, authenticated;

-- What everybody may read: the latest count per space from the last 15 minutes.
-- Privacy rule: fewer than 3 people is shown as "few", never the exact number,
-- so a single student alone in a small room cannot be singled out.
CREATE OR REPLACE VIEW public.space_sensor_now AS
SELECT DISTINCT ON (r.space_id)
       r.space_id,
       CASE WHEN r.people_inside < 3 THEN NULL ELSE r.people_inside END AS people_inside,
       (r.people_inside < 3)                                            AS few,
       r.measured_at
FROM public.sensor_readings r
JOIN public.sensors s ON s.id = r.sensor_id AND s.active
WHERE r.measured_at > now() - interval '15 minutes'
ORDER BY r.space_id, r.measured_at DESC;
REVOKE ALL ON public.space_sensor_now FROM anon, authenticated;
GRANT SELECT ON public.space_sensor_now TO anon, authenticated;

-- Data minimisation: raw readings are kept 30 days. Call this daily
-- (Supabase -> Database -> Cron, or by hand before a demo).
CREATE OR REPLACE FUNCTION public.purge_sensor_readings()
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH d AS (DELETE FROM public.sensor_readings WHERE measured_at < now() - interval '30 days' RETURNING 1)
  SELECT count(*)::int FROM d;
$$;
REVOKE ALL ON FUNCTION public.purge_sensor_readings() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ---------------------------------------------------------------------
-- After running: register one sensor per AITU space and copy the four
-- secrets into iot/sensors.local.json (never commit that file):
--
-- SELECT s.name, public.register_sensor(s.id, s.name || ' entrance') AS secret
-- FROM public.study_spaces s JOIN public.universities u ON u.id = s.university_id
-- WHERE u.code = 'AITU' ORDER BY s.id;
-- ---------------------------------------------------------------------
