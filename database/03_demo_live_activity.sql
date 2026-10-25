-- OrynTap — refresh live check-ins before a demo (closes old ones automatically)
UPDATE public.check_ins SET left_at = least(now(), expires_at) WHERE left_at IS NULL;

-- Live activity: about 70 % of seeded students are "studying right now".
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
