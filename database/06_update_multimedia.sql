-- =====================================================================
-- OrynTap update for Assignment 4 (multimedia), Oct 2026.
-- Run ONCE in Supabase -> SQL Editor, after 05_update_2026-10-14.sql.
-- It keeps all users, check-ins and favourites.
--
--   1. New column study_spaces.image_alt: the alternative text of a photo
--      is stored next to the photo, so whoever changes one changes both.
--      NULL means "decorative illustration" -> the site uses alt="".
--   2. Photos hot-linked from astanait.edu.kz, ifla.org and mnu.kz are
--      replaced by our own files (no licence allowed reusing them).
--   3. Our two AITU photos and the floor plan now point to WebP versions.
--
-- A fresh install does not need this file: 01_schema.sql and 02_seed.sql
-- already contain the same changes.
-- =====================================================================
BEGIN;

-- 1. Alt text column (max 200 characters, like a short sentence)
ALTER TABLE public.study_spaces ADD COLUMN IF NOT EXISTS image_alt varchar(200);

-- The read model must expose the new column. A view's columns cannot be
-- inserted in the middle with CREATE OR REPLACE, so it is re-created.
DROP VIEW IF EXISTS public.space_availability;
CREATE VIEW public.space_availability AS
SELECT
  s.id, s.university_id, u.code AS university_code, s.name, s.kind,
  s.building, s.floor, s.description, s.image_url, s.image_credit, s.image_alt,
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
GRANT SELECT ON public.space_availability TO anon, authenticated;

-- 2 + 3. Own, optimised images and their alt text
UPDATE public.study_spaces SET image_url = 'assets/img/aitu-library-460.webp', image_credit = NULL, image_alt = 'Library hall with lime-green booth sofas, long tables and tall white bookshelves'
 WHERE name = 'Library' AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');
UPDATE public.study_spaces SET image_url = 'assets/img/aitu-open-space-460.webp', image_credit = NULL, image_alt = 'Students sitting on green modular sofas in a bright atrium under a glass roof'
 WHERE name = 'Open Space' AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-03-coworking.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Coworking' AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-04-cafe.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Coffeelake' AND university_id = (SELECT id FROM public.universities WHERE code = 'AITU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-05-library.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Library · Astana Room' AND university_id = (SELECT id FROM public.universities WHERE code = 'NU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-06-library.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Library · Quiet Room' AND university_id = (SELECT id FROM public.universities WHERE code = 'NU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-07-coworking.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Library · Collaborative Space' AND university_id = (SELECT id FROM public.universities WHERE code = 'NU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-08-lounge.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Multifunctional Room' AND university_id = (SELECT id FROM public.universities WHERE code = 'NU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-09-rooms.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Study Room D5.124' AND university_id = (SELECT id FROM public.universities WHERE code = 'NU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-10-library.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Public Library' AND university_id = (SELECT id FROM public.universities WHERE code = 'MNU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-11-coworking.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Zebra Coworking' AND university_id = (SELECT id FROM public.universities WHERE code = 'MNU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-12-atrium.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Shaikenov Atrium' AND university_id = (SELECT id FROM public.universities WHERE code = 'MNU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-13-rooms.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Team Talk Room' AND university_id = (SELECT id FROM public.universities WHERE code = 'MNU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-14-lounge.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Pesochnica' AND university_id = (SELECT id FROM public.universities WHERE code = 'MNU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-15-library.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Scientific Library · Reading Hall' AND university_id = (SELECT id FROM public.universities WHERE code = 'ENU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-16-rooms.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Electronic Reading Room' AND university_id = (SELECT id FROM public.universities WHERE code = 'ENU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-17-coworking.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'American Corner & Maker Space' AND university_id = (SELECT id FROM public.universities WHERE code = 'ENU');
UPDATE public.study_spaces SET image_url = 'assets/img/cover-18-lounge.svg', image_credit = NULL, image_alt = NULL
 WHERE name = 'Student House Coworking' AND university_id = (SELECT id FROM public.universities WHERE code = 'ENU');

UPDATE public.universities SET map_image_url = 'assets/img/aitu-map.webp' WHERE code = 'AITU';

COMMIT;

-- Check: no image may come from another website any more (expect 0 rows)
-- SELECT name, image_url FROM public.study_spaces WHERE image_url LIKE 'http%';
