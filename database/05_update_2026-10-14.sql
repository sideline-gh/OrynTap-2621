-- =====================================================================
-- OrynTap update, 14 Oct 2026. Run ONCE in Supabase -> SQL Editor on the
-- existing database (it does not delete tables or test data).
--   1. Admin role only for the team's three e-mails
--   2. Students can check in only at their own university
--   3. Remove the old seeded admin@... accounts (their password is public)
-- A fresh install does not need this file: 01_schema.sql and 02_seed.sql
-- already contain the same rules.
-- =====================================================================
BEGIN;

-- 1a. New accounts: the role is decided by the e-mail address.
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
    CASE WHEN NEW.raw_user_meta_data->>'consent' = 'true' THEN now() END
  );
  RETURN NEW;
END $$;

-- 1b. Existing accounts: everybody is a student except the three team e-mails.
UPDATE public.profiles p
   SET role = CASE WHEN lower(u.email) IN ('260925@astanait.edu.kz', '261234@astanait.edu.kz', '261584@astanait.edu.kz')
                   THEN 'admin' ELSE 'student' END
  FROM auth.users u
 WHERE u.id = p.id;

-- 2. Check-ins only at the student's own university (Row-Level Security).
DROP POLICY IF EXISTS check_ins_own_insert ON public.check_ins;
CREATE POLICY check_ins_own_insert ON public.check_ins FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.study_spaces s JOIN public.profiles p ON p.id = auth.uid()
    WHERE s.id = space_id AND s.university_id = p.university_id));

-- 3. The four seeded admin accounts are no longer needed.
DELETE FROM auth.users
 WHERE email IN ('admin@astanait.edu.kz', 'admin@nu.edu.kz', 'admin@mnu.kz', 'admin@enu.kz');

COMMIT;

-- Check: who is admin now? (empty until the three of you have registered)
-- SELECT u.email, p.role FROM public.profiles p JOIN auth.users u ON u.id = p.id WHERE p.role = 'admin';
