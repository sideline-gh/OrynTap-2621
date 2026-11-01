-- =====================================================================
-- OrynTap · Project Stage 2, Part D: IoT occupancy (simulated door sensor)
-- Run ONCE in Supabase -> SQL Editor, AFTER 07_stage2.sql. Safe to run again.
--
-- 07_stage2.sql already created everything the sensor needs:
--   sensors          one row per door counter (secret stored only as SHA-256)
--   sensor_readings  people_inside + measured_at, admin-only (RLS)
--   ingest_reading() the only way a device can write (public key + own secret)
--   space_sensor_now the latest reading per space, readable by everyone
-- This file only:
--   1. adds space name, seats and FREE SEATS to the view (for the website panel)
--   2. makes ingest_reading() refuse a count above the room's seat capacity
-- Row-Level Security and the grants from 07 are NOT changed.
-- =====================================================================
DO $$
BEGIN
  IF to_regclass('public.sensor_readings') IS NULL THEN
    RAISE EXCEPTION 'Run database/07_stage2.sql first (sensor tables are missing)';
  END IF;
END $$;

BEGIN;
SET LOCAL search_path = public, extensions;

-- 1. Latest reading per space, now with seats and free seats.
--    New columns are added at the END, so the existing website code keeps working.
--    Privacy rule from 07 stays: fewer than 3 people -> people_inside is NULL and few = true.
CREATE OR REPLACE VIEW public.space_sensor_now AS
SELECT DISTINCT ON (r.space_id)
       r.space_id,
       CASE WHEN r.people_inside < 3 THEN NULL ELSE r.people_inside END AS people_inside,
       (r.people_inside < 3)                                            AS few,
       r.measured_at,
       sp.name                                                          AS space_name,
       sp.seat_capacity,
       CASE WHEN r.people_inside < 3 THEN NULL
            ELSE greatest(sp.seat_capacity - r.people_inside, 0) END    AS free_seats
FROM public.sensor_readings r
JOIN public.sensors s       ON s.id = r.sensor_id AND s.active
JOIN public.study_spaces sp ON sp.id = r.space_id
WHERE r.measured_at > now() - interval '15 minutes'
ORDER BY r.space_id, r.measured_at DESC;
REVOKE ALL ON public.space_sensor_now FROM anon, authenticated;
GRANT SELECT ON public.space_sensor_now TO anon, authenticated;

-- 2. Same function as in 07, plus one check: never more people than seats.
CREATE OR REPLACE FUNCTION public.ingest_reading(p_token text, p_people integer)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_sensor public.sensors%ROWTYPE;
  v_seats  integer;
BEGIN
  SELECT * INTO v_sensor FROM public.sensors
   WHERE token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown or disabled sensor' USING ERRCODE = '28000';
  END IF;
  SELECT seat_capacity INTO v_seats FROM public.study_spaces WHERE id = v_sensor.space_id;
  IF p_people IS NULL OR p_people < 0 OR p_people > v_seats THEN
    RAISE EXCEPTION 'people_inside must be between 0 and % (seats)', v_seats USING ERRCODE = '22003';
  END IF;
  -- Flood protection: at most one reading per sensor every 5 seconds
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
REVOKE ALL ON FUNCTION public.ingest_reading(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ingest_reading(text, integer) TO anon, authenticated;

COMMIT;

-- ---------------------------------------------------------------------
-- After running: register ONE sensor for the AITU Library door and copy
-- the secret into iot/.env as SENSOR_TOKEN (it is shown only once):
--
-- SELECT s.id AS space_id, s.name, s.seat_capacity,
--        public.register_sensor(s.id, 'Library door: ESP32 + 2 ToF (simulated)') AS secret
-- FROM public.study_spaces s JOIN public.universities u ON u.id = s.university_id
-- WHERE u.code = 'AITU' AND s.name = 'Library';
--
-- Optional: switch off sensors registered earlier for the old 4-space simulation
-- UPDATE public.sensors SET active = false WHERE label NOT LIKE 'Library door%';
--
-- Check that readings arrive (SQL Editor runs as the owner, so RLS does not hide them):
-- SELECT * FROM public.sensor_readings ORDER BY measured_at DESC LIMIT 10;
-- SELECT * FROM public.space_sensor_now;
-- ---------------------------------------------------------------------
