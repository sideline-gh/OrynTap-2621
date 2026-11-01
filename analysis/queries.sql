-- =====================================================================
-- OrynTap · Project Stage 2 · Part C: data analysis
-- Run in Supabase -> SQL Editor (or psql). Each query is independent.
-- All FINISHED check-ins are counted (expires_at already passed, or the
-- student pressed Leave). The generated test history covers 30 days and is
-- fixed in time, so no date window is used; with real users you would add
--   AND c.started_at > now() - interval '30 days'
-- to every query to look at the last month only.
-- Times are converted to Astana time (UTC+5).
-- =====================================================================

-- Q1. At which hours of the day are study spaces busiest?
--     Check-ins started per hour of the day, per university.
SELECT u.code                                                  AS university,
       extract(hour FROM c.started_at AT TIME ZONE 'Asia/Almaty')::int AS hour_of_day,
       count(*)                                                AS check_ins
FROM public.check_ins c
JOIN public.study_spaces s ON s.id = c.space_id
JOIN public.universities u ON u.id = s.university_id
WHERE (c.left_at IS NOT NULL OR c.expires_at <= now())
GROUP BY u.code, hour_of_day
ORDER BY hour_of_day, university;

-- Q2. Which study spaces are used most for their size, and how many
--     of those students need a power outlet?
SELECT u.code                                              AS university,
       s.name                                              AS space,
       s.seat_capacity                                     AS seats,
       count(c.id)                                         AS check_ins,
       round(100.0 * count(c.id) / s.seat_capacity, 1)     AS check_ins_per_100_seats,
       round(100.0 * avg(c.uses_outlet::int), 0)           AS pct_with_outlet
FROM public.study_spaces s
JOIN public.universities u ON u.id = s.university_id
LEFT JOIN public.check_ins c
       ON c.space_id = s.id
      AND (c.left_at IS NOT NULL OR c.expires_at <= now())
GROUP BY u.code, s.id, s.name, s.seat_capacity
ORDER BY check_ins_per_100_seats DESC;

-- Q3. How long do students really stay, and how often does a check-in
--     end by itself because nobody pressed Leave?
--     "Left early" = Leave pressed before expires_at.
--     "Ended by itself" = no Leave, or Leave not before the planned end.
SELECT round(extract(epoch FROM c.expires_at - c.started_at) / 3600)::int        AS planned_hours,
       count(*)                                                                    AS check_ins,
       round(avg(extract(epoch FROM least(coalesce(c.left_at, c.expires_at), c.expires_at) - c.started_at) / 60)) AS avg_stay_min,
       round(100.0 * avg((c.left_at IS NOT NULL AND c.left_at < c.expires_at)::int), 0)  AS pct_left_early,
       round(100.0 * avg((c.left_at IS NULL OR c.left_at >= c.expires_at)::int), 0)     AS pct_ended_by_itself
FROM public.check_ins c
WHERE (c.left_at IS NOT NULL OR c.expires_at <= now())
GROUP BY planned_hours
ORDER BY planned_hours;
