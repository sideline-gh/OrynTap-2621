-- =====================================================================
-- OrynTap · update of 3 Nov 2026: team photos + e-mail verification guard
-- Run ONCE in Supabase -> SQL Editor (after 01–08). Safe to run again.
--
--   1. Library, Coffeelake and Coworking show the team's own photos (WebP, 480/960 px);
--      three new AITU places: Mokko, Sheker and Canteen
--   2. Only accounts with a CONFIRMED e-mail can check in, save favourites
--      or use admin rights. Supabase already refuses to log in an unconfirmed
--      account when "Confirm email" is on; this makes the database refuse it
--      too, so the rule holds even if that setting is switched off by mistake.
-- Accounts created while "Confirm email" was off were confirmed automatically
-- (Supabase sets email_confirmed_at), so nobody who can log in today is locked out.
-- =====================================================================
BEGIN;

-- 1. Photos ------------------------------------------------------------
UPDATE public.study_spaces SET image_url = 'assets/img/aitu-library-480.webp', image_credit = NULL,
       image_alt = 'Library reading area with rows of grey desk booths, green carpet and a slatted wooden ceiling'
 WHERE name = 'Library' AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');
UPDATE public.study_spaces SET image_url = 'assets/img/aitu-coffeelake-480.webp', image_credit = NULL,
       image_alt = 'Coffeelake counter with pastries, and white chairs at tables beside a green plant wall'
 WHERE name = 'Coffeelake' AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');

UPDATE public.study_spaces SET image_url = 'assets/img/aitu-coworking-480.webp', image_credit = NULL,
       image_alt = 'Coworking area with a long table and grey chairs, sofas and swing seats by the windows'
 WHERE name = 'Coworking' AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');

-- New places (added only if not there yet). Seats are rough counts and outlets are 0 until an admin
-- counts them; only Mon–Fri 09:00–20:00 is confirmed: admins add the weekend hours with Edit.
INSERT INTO public.study_spaces (university_id, name, kind, building, floor, description, image_url, image_alt,
                                 seat_capacity, outlet_capacity, counts_exact, is_quiet, group_work, food_allowed, map_x, map_y)
SELECT u.id, v.name, 'cafe', v.building, v.floor, v.descr, v.img, v.alt, v.seats, 0, false, false, true, true, v.mx, v.my
FROM public.universities u
CROSS JOIN (VALUES
  ('Mokko',   'Between Blocks C2 and C3, opposite the wardrobe', NULL,
   'University coffee shop. Seat count is approximate; outlets and weekend hours are not confirmed yet.',
   'assets/img/aitu-mokko-480.webp', 'Mokko coffee kiosk in a glass-walled passage, with round tables and wooden armchairs', 10, NULL::numeric, NULL::numeric),
  ('Sheker',  'Between Blocks C1 and C2, opposite the wardrobe', NULL,
   'Coffee shop. Seat count is approximate; outlets and weekend hours are not confirmed yet.',
   'assets/img/aitu-sheker-480.webp', 'Sheker coffee kiosk with square tables and grey chairs under string lights', 10, NULL, NULL),
  ('Canteen', 'Block C1.3', 'Dining hall',
   'University dining hall. At least 100 seats (approximate); outlets and weekend hours are not confirmed yet.',
   'assets/img/aitu-canteen-480.webp', 'Large canteen hall with long tables, yellow benches and round ceiling lamps by tall windows', 100, 84, 74)
) AS v(name, building, floor, descr, img, alt, seats, mx, my)
WHERE u.code = 'AITU'
  AND NOT EXISTS (SELECT 1 FROM public.study_spaces s WHERE s.university_id = u.id AND s.name = v.name);

INSERT INTO public.opening_hours (space_id, weekday, opens, closes)
SELECT s.id, d, '09:00', '20:00'
FROM public.study_spaces s JOIN public.universities u ON u.id = s.university_id
CROSS JOIN generate_series(1, 5) AS d
WHERE u.code = 'AITU' AND s.name IN ('Mokko', 'Sheker', 'Canteen')
  AND NOT EXISTS (SELECT 1 FROM public.opening_hours h WHERE h.space_id = s.id);

-- 2. E-mail verification guard -----------------------------------------
CREATE OR REPLACE FUNCTION public.email_verified()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT email_confirmed_at IS NOT NULL FROM auth.users WHERE id = auth.uid()), false);
$$;
REVOKE ALL ON FUNCTION public.email_verified() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.email_verified() TO authenticated;

-- Check-in: only for yourself, only at your own university (05), and only with a confirmed e-mail
DROP POLICY IF EXISTS check_ins_own_insert ON public.check_ins;
CREATE POLICY check_ins_own_insert ON public.check_ins FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.email_verified() AND EXISTS (
    SELECT 1 FROM public.study_spaces s JOIN public.profiles p ON p.id = auth.uid()
    WHERE s.id = space_id AND s.university_id = p.university_id));

DROP POLICY IF EXISTS favourites_own_insert ON public.favourites;
CREATE POLICY favourites_own_insert ON public.favourites FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.email_verified());

-- Admin rights (edit spaces and hours, statistics, sensors) also need a confirmed e-mail
CREATE OR REPLACE FUNCTION public.is_admin_of(p_university smallint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.email_verified() AND EXISTS (SELECT 1 FROM public.profiles
                 WHERE id = auth.uid() AND role = 'admin' AND university_id = p_university);
$$;
CREATE OR REPLACE FUNCTION public.is_any_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.email_verified() AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin');
$$;

COMMIT;

-- Check (SQL Editor): accounts that still wait for confirmation
-- SELECT email, created_at FROM auth.users WHERE email_confirmed_at IS NULL ORDER BY created_at DESC;
