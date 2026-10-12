--
-- PostgreSQL database dump
--

\restrict vfcdKcZWiTjUL8AviJKZblRnnoAZNqqPRexgYCAquPvZG9wlUgWoQEG0YyDj6fK

-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO postgres;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: postgres
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;


ALTER FUNCTION auth.uid() OWNER TO postgres;

--
-- Name: admin_usage_by_hour(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.admin_usage_by_hour() RETURNS TABLE(space_id integer, space_name character varying, hour_of_day integer, check_ins bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.admin_usage_by_hour() OWNER TO postgres;

--
-- Name: before_check_in(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.before_check_in() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.before_check_in() OWNER TO postgres;

--
-- Name: before_check_out(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.before_check_out() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    IF OLD.left_at IS NOT NULL THEN RAISE EXCEPTION 'Already checked out'; END IF;
    NEW.left_at := least(now(), OLD.expires_at);
  END IF;
  RETURN NEW;
END $$;


ALTER FUNCTION public.before_check_out() OWNER TO postgres;

--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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

  INSERT INTO public.profiles (id, first_name, last_name, university_id, role)
  VALUES (
    NEW.id,
    left(coalesce(nullif(NEW.raw_user_meta_data->>'first_name', ''),
                  nullif(split_part(v_full, ' ', 1), ''),
                  initcap(split_part(NEW.email, '@', 1))), 50),
    left(coalesce(nullif(NEW.raw_user_meta_data->>'last_name', ''),
                  nullif(substr(v_full, length(split_part(v_full, ' ', 1)) + 2), ''), ''), 50),
    v_uni,
    CASE WHEN NEW.raw_app_meta_data->>'role' = 'admin' THEN 'admin' ELSE 'student' END
  );
  RETURN NEW;
END $$;


ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

--
-- Name: is_admin_of(smallint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_admin_of(p_university smallint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles
                 WHERE id = auth.uid() AND role = 'admin' AND university_id = p_university);
$$;


ALTER FUNCTION public.is_admin_of(p_university smallint) OWNER TO postgres;

--
-- Name: is_any_admin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_any_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin');
$$;


ALTER FUNCTION public.is_any_admin() OWNER TO postgres;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;


ALTER FUNCTION public.set_updated_at() OWNER TO postgres;

--
-- Name: touch_space_activity(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.touch_space_activity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.space_activity (space_id, last_change)
  VALUES (NEW.space_id, now())
  ON CONFLICT (space_id) DO UPDATE SET last_change = excluded.last_change;
  RETURN NEW;
END $$;


ALTER FUNCTION public.touch_space_activity() OWNER TO postgres;

--
-- Name: write_audit_log(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.write_audit_log() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


ALTER FUNCTION public.write_audit_log() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: identities; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.identities (
    id uuid NOT NULL,
    user_id uuid,
    provider_id text,
    identity_data jsonb,
    provider text,
    last_sign_in_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


ALTER TABLE auth.identities OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    email_confirmed_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    confirmation_token character varying(255),
    recovery_token character varying(255),
    email_change_token_new character varying(255),
    email_change character varying(255)
);


ALTER TABLE auth.users OWNER TO postgres;

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    actor uuid,
    action character varying(10) NOT NULL,
    table_name character varying(40) NOT NULL,
    record_id text,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT audit_log_action_check CHECK (((action)::text = ANY ((ARRAY['INSERT'::character varying, 'UPDATE'::character varying, 'DELETE'::character varying])::text[])))
);


ALTER TABLE public.audit_log OWNER TO postgres;

--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: check_ins; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.check_ins (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    space_id integer NOT NULL,
    uses_outlet boolean DEFAULT false NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    left_at timestamp with time zone,
    CONSTRAINT check_ins_check CHECK (((expires_at > started_at) AND (expires_at <= (started_at + '03:00:00'::interval)))),
    CONSTRAINT check_ins_check1 CHECK (((left_at IS NULL) OR (left_at >= started_at)))
);


ALTER TABLE public.check_ins OWNER TO postgres;

--
-- Name: check_ins_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.check_ins ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.check_ins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: email_domains; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.email_domains (
    domain character varying(100) NOT NULL,
    university_id smallint NOT NULL,
    CONSTRAINT email_domains_domain_check CHECK (((domain)::text ~ '^[a-z0-9.-]+\.[a-z]{2,}$'::text))
);


ALTER TABLE public.email_domains OWNER TO postgres;

--
-- Name: favourites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.favourites (
    user_id uuid NOT NULL,
    space_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.favourites OWNER TO postgres;

--
-- Name: opening_hours; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.opening_hours (
    space_id integer NOT NULL,
    weekday smallint NOT NULL,
    opens time without time zone NOT NULL,
    closes time without time zone NOT NULL,
    CONSTRAINT opening_hours_check CHECK ((closes > opens)),
    CONSTRAINT opening_hours_weekday_check CHECK (((weekday >= 1) AND (weekday <= 7)))
);


ALTER TABLE public.opening_hours OWNER TO postgres;

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) DEFAULT ''::character varying NOT NULL,
    university_id smallint NOT NULL,
    role character varying(10) DEFAULT 'student'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT profiles_first_name_check CHECK ((length(TRIM(BOTH FROM first_name)) > 0)),
    CONSTRAINT profiles_role_check CHECK (((role)::text = ANY ((ARRAY['student'::character varying, 'admin'::character varying])::text[])))
);


ALTER TABLE public.profiles OWNER TO postgres;

--
-- Name: space_activity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.space_activity (
    space_id integer NOT NULL,
    last_change timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.space_activity OWNER TO postgres;

--
-- Name: space_availability; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.space_availability AS
SELECT
    NULL::integer AS id,
    NULL::smallint AS university_id,
    NULL::character varying(8) AS university_code,
    NULL::character varying(80) AS name,
    NULL::character varying(12) AS kind,
    NULL::character varying(80) AS building,
    NULL::character varying(20) AS floor,
    NULL::text AS description,
    NULL::text AS image_url,
    NULL::character varying(80) AS image_credit,
    NULL::integer AS seat_capacity,
    NULL::integer AS outlet_capacity,
    NULL::boolean AS counts_exact,
    NULL::boolean AS is_quiet,
    NULL::boolean AS group_work,
    NULL::boolean AS food_allowed,
    NULL::numeric(5,2) AS map_x,
    NULL::numeric(5,2) AS map_y,
    NULL::bigint AS free_seats,
    NULL::bigint AS free_outlets,
    NULL::timestamp with time zone AS updated_at,
    NULL::json AS hours;


ALTER VIEW public.space_availability OWNER TO postgres;

--
-- Name: study_spaces; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.study_spaces (
    id integer NOT NULL,
    university_id smallint NOT NULL,
    name character varying(80) NOT NULL,
    kind character varying(12) NOT NULL,
    building character varying(80),
    floor character varying(20),
    description text,
    image_url text,
    image_credit character varying(80),
    seat_capacity integer NOT NULL,
    outlet_capacity integer NOT NULL,
    counts_exact boolean DEFAULT false NOT NULL,
    is_quiet boolean DEFAULT false NOT NULL,
    group_work boolean DEFAULT false NOT NULL,
    food_allowed boolean DEFAULT false NOT NULL,
    map_x numeric(5,2),
    map_y numeric(5,2),
    is_active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT study_spaces_kind_check CHECK (((kind)::text = ANY ((ARRAY['library'::character varying, 'coworking'::character varying, 'atrium'::character varying, 'rooms'::character varying, 'lounge'::character varying, 'cafe'::character varying])::text[]))),
    CONSTRAINT study_spaces_map_x_check CHECK (((map_x >= (0)::numeric) AND (map_x <= (100)::numeric))),
    CONSTRAINT study_spaces_map_y_check CHECK (((map_y >= (0)::numeric) AND (map_y <= (100)::numeric))),
    CONSTRAINT study_spaces_name_check CHECK ((length(TRIM(BOTH FROM name)) > 0)),
    CONSTRAINT study_spaces_outlet_capacity_check CHECK (((outlet_capacity >= 0) AND (outlet_capacity <= 5000))),
    CONSTRAINT study_spaces_seat_capacity_check CHECK (((seat_capacity >= 1) AND (seat_capacity <= 2000)))
);


ALTER TABLE public.study_spaces OWNER TO postgres;

--
-- Name: study_spaces_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.study_spaces ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.study_spaces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: universities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.universities (
    id smallint NOT NULL,
    code character varying(8) NOT NULL,
    name character varying(120) NOT NULL,
    city character varying(60) DEFAULT 'Astana'::character varying NOT NULL,
    address character varying(160),
    map_image_url text,
    map_embed_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT universities_code_check CHECK (((code)::text ~ '^[A-Z]{2,8}$'::text))
);


ALTER TABLE public.universities OWNER TO postgres;

--
-- Name: universities_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.universities ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.universities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Data for Name: identities; Type: TABLE DATA; Schema: auth; Owner: postgres
--

COPY auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at) FROM stdin;
ce4d212d-dc26-5d4b-970b-719c3ea9fc2e	ce4d212d-dc26-5d4b-970b-719c3ea9fc2e	ce4d212d-dc26-5d4b-970b-719c3ea9fc2e	{"sub": "ce4d212d-dc26-5d4b-970b-719c3ea9fc2e", "email": "admin@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
44a51247-0f45-5096-9fca-81ed70346a12	44a51247-0f45-5096-9fca-81ed70346a12	44a51247-0f45-5096-9fca-81ed70346a12	{"sub": "44a51247-0f45-5096-9fca-81ed70346a12", "email": "246466@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
6f583e12-eb4d-5a2d-9b34-9120b6172fbf	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	{"sub": "6f583e12-eb4d-5a2d-9b34-9120b6172fbf", "email": "233363@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
d6a0339c-e841-56e2-9be8-3c789fb9a47b	d6a0339c-e841-56e2-9be8-3c789fb9a47b	d6a0339c-e841-56e2-9be8-3c789fb9a47b	{"sub": "d6a0339c-e841-56e2-9be8-3c789fb9a47b", "email": "248237@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
0631a63b-ebc2-5785-a739-9fee4b48e5bc	0631a63b-ebc2-5785-a739-9fee4b48e5bc	0631a63b-ebc2-5785-a739-9fee4b48e5bc	{"sub": "0631a63b-ebc2-5785-a739-9fee4b48e5bc", "email": "247950@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	{"sub": "79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6", "email": "244453@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
bb9f8bce-5de6-54be-a471-3c22fff845f5	bb9f8bce-5de6-54be-a471-3c22fff845f5	bb9f8bce-5de6-54be-a471-3c22fff845f5	{"sub": "bb9f8bce-5de6-54be-a471-3c22fff845f5", "email": "232645@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
ad5b5e1b-07b1-5134-ae83-b16af18abe40	ad5b5e1b-07b1-5134-ae83-b16af18abe40	ad5b5e1b-07b1-5134-ae83-b16af18abe40	{"sub": "ad5b5e1b-07b1-5134-ae83-b16af18abe40", "email": "233212@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
123a74f4-143d-5603-81d5-6331401ea569	123a74f4-143d-5603-81d5-6331401ea569	123a74f4-143d-5603-81d5-6331401ea569	{"sub": "123a74f4-143d-5603-81d5-6331401ea569", "email": "246065@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
289a1a72-f5c0-5531-a5a2-1431eae3980d	289a1a72-f5c0-5531-a5a2-1431eae3980d	289a1a72-f5c0-5531-a5a2-1431eae3980d	{"sub": "289a1a72-f5c0-5531-a5a2-1431eae3980d", "email": "243016@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
5c29fc1f-628e-5bdc-9e83-3e576df263d4	5c29fc1f-628e-5bdc-9e83-3e576df263d4	5c29fc1f-628e-5bdc-9e83-3e576df263d4	{"sub": "5c29fc1f-628e-5bdc-9e83-3e576df263d4", "email": "241686@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
594c5eb8-5eba-5db1-9527-7d409b4281ab	594c5eb8-5eba-5db1-9527-7d409b4281ab	594c5eb8-5eba-5db1-9527-7d409b4281ab	{"sub": "594c5eb8-5eba-5db1-9527-7d409b4281ab", "email": "246829@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
a6a72968-235d-553f-84a7-223f70ff71da	a6a72968-235d-553f-84a7-223f70ff71da	a6a72968-235d-553f-84a7-223f70ff71da	{"sub": "a6a72968-235d-553f-84a7-223f70ff71da", "email": "241154@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
b88dd4ac-02c8-576e-96b7-dad2fcc30210	b88dd4ac-02c8-576e-96b7-dad2fcc30210	b88dd4ac-02c8-576e-96b7-dad2fcc30210	{"sub": "b88dd4ac-02c8-576e-96b7-dad2fcc30210", "email": "247631@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
daecc825-1e7a-51cd-a171-4a41488773ae	daecc825-1e7a-51cd-a171-4a41488773ae	daecc825-1e7a-51cd-a171-4a41488773ae	{"sub": "daecc825-1e7a-51cd-a171-4a41488773ae", "email": "244989@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	{"sub": "384c5afb-bcd3-51c6-a4f0-5bd88bbb4095", "email": "248921@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
bf1b1568-063d-5529-a346-27dcbdb160fc	bf1b1568-063d-5529-a346-27dcbdb160fc	bf1b1568-063d-5529-a346-27dcbdb160fc	{"sub": "bf1b1568-063d-5529-a346-27dcbdb160fc", "email": "242086@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
bf5483dd-f9be-503e-b843-511fab7772f3	bf5483dd-f9be-503e-b843-511fab7772f3	bf5483dd-f9be-503e-b843-511fab7772f3	{"sub": "bf5483dd-f9be-503e-b843-511fab7772f3", "email": "243835@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
c39ee07c-08d3-51a9-8933-c3f20abe6a2d	c39ee07c-08d3-51a9-8933-c3f20abe6a2d	c39ee07c-08d3-51a9-8933-c3f20abe6a2d	{"sub": "c39ee07c-08d3-51a9-8933-c3f20abe6a2d", "email": "249192@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
2667ad63-20cd-5653-af95-685a96aec1cb	2667ad63-20cd-5653-af95-685a96aec1cb	2667ad63-20cd-5653-af95-685a96aec1cb	{"sub": "2667ad63-20cd-5653-af95-685a96aec1cb", "email": "233815@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
841aeb58-3431-5102-81be-941918ee4320	841aeb58-3431-5102-81be-941918ee4320	841aeb58-3431-5102-81be-941918ee4320	{"sub": "841aeb58-3431-5102-81be-941918ee4320", "email": "249666@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
bc586d94-7153-5cf0-8676-68bcb94a0d5a	bc586d94-7153-5cf0-8676-68bcb94a0d5a	bc586d94-7153-5cf0-8676-68bcb94a0d5a	{"sub": "bc586d94-7153-5cf0-8676-68bcb94a0d5a", "email": "247191@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
813640c1-13d1-52ed-b333-486966e596de	813640c1-13d1-52ed-b333-486966e596de	813640c1-13d1-52ed-b333-486966e596de	{"sub": "813640c1-13d1-52ed-b333-486966e596de", "email": "248481@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
b28f9b27-eccf-51b6-bad2-71b3eb1324e3	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	{"sub": "b28f9b27-eccf-51b6-bad2-71b3eb1324e3", "email": "246973@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
398c2e60-8a06-5f46-8fb0-e117c255ead8	398c2e60-8a06-5f46-8fb0-e117c255ead8	398c2e60-8a06-5f46-8fb0-e117c255ead8	{"sub": "398c2e60-8a06-5f46-8fb0-e117c255ead8", "email": "237357@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	{"sub": "8e1f202a-2aae-553d-a9ac-cd2861fc7f0a", "email": "247144@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
b4455c9f-c726-58c4-a73d-dc7ac20b4280	b4455c9f-c726-58c4-a73d-dc7ac20b4280	b4455c9f-c726-58c4-a73d-dc7ac20b4280	{"sub": "b4455c9f-c726-58c4-a73d-dc7ac20b4280", "email": "244070@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
22177d59-b6dd-5230-ad3a-3f20a82c77be	22177d59-b6dd-5230-ad3a-3f20a82c77be	22177d59-b6dd-5230-ad3a-3f20a82c77be	{"sub": "22177d59-b6dd-5230-ad3a-3f20a82c77be", "email": "245797@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
4375a7a0-75af-50b6-bf34-ac0b79555581	4375a7a0-75af-50b6-bf34-ac0b79555581	4375a7a0-75af-50b6-bf34-ac0b79555581	{"sub": "4375a7a0-75af-50b6-bf34-ac0b79555581", "email": "244968@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
e1f7cb84-a272-5286-8d3b-6004b94c9fea	e1f7cb84-a272-5286-8d3b-6004b94c9fea	e1f7cb84-a272-5286-8d3b-6004b94c9fea	{"sub": "e1f7cb84-a272-5286-8d3b-6004b94c9fea", "email": "247879@astanait.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
9871575d-9f8d-5ea2-aafb-4cf2d460a9ca	9871575d-9f8d-5ea2-aafb-4cf2d460a9ca	9871575d-9f8d-5ea2-aafb-4cf2d460a9ca	{"sub": "9871575d-9f8d-5ea2-aafb-4cf2d460a9ca", "email": "admin@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a	c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a	c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a	{"sub": "c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a", "email": "aisulu.ismailova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
0f4985f0-eea4-5fc5-aba1-78fba1cf698f	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	{"sub": "0f4985f0-eea4-5fc5-aba1-78fba1cf698f", "email": "ernar.rakhimov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	{"sub": "36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b", "email": "adil.ismailov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
448fc3a2-4bb5-55c5-af6c-daa5b70403fc	448fc3a2-4bb5-55c5-af6c-daa5b70403fc	448fc3a2-4bb5-55c5-af6c-daa5b70403fc	{"sub": "448fc3a2-4bb5-55c5-af6c-daa5b70403fc", "email": "diana.dosmukhamedova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	{"sub": "2e3914a7-a1d2-5d8c-967c-4fab8cf3f489", "email": "aliya.baimukhanova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
7106add8-93da-510c-a2ee-43f512e49d3c	7106add8-93da-510c-a2ee-43f512e49d3c	7106add8-93da-510c-a2ee-43f512e49d3c	{"sub": "7106add8-93da-510c-a2ee-43f512e49d3c", "email": "daniyar.bekov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
c25c9587-af2d-50a5-9cbc-1fdf3302f483	c25c9587-af2d-50a5-9cbc-1fdf3302f483	c25c9587-af2d-50a5-9cbc-1fdf3302f483	{"sub": "c25c9587-af2d-50a5-9cbc-1fdf3302f483", "email": "tomiris.akhmetova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
18e969e2-d4e6-52f4-8e81-e62265f128f5	18e969e2-d4e6-52f4-8e81-e62265f128f5	18e969e2-d4e6-52f4-8e81-e62265f128f5	{"sub": "18e969e2-d4e6-52f4-8e81-e62265f128f5", "email": "aruzhan.seitkali@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
d44f6451-0c5b-528c-a3a1-c6ec8caf288a	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	{"sub": "d44f6451-0c5b-528c-a3a1-c6ec8caf288a", "email": "temirlan.amanov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	{"sub": "1a2bd399-49fe-58b1-bc67-c6b3fd3246f1", "email": "ayaulym.kairatova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
3c16f96c-897e-5713-b4ce-ffc817887105	3c16f96c-897e-5713-b4ce-ffc817887105	3c16f96c-897e-5713-b4ce-ffc817887105	{"sub": "3c16f96c-897e-5713-b4ce-ffc817887105", "email": "timur.utepov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	{"sub": "d39a322b-1a19-5558-a9d5-3d5c1c5f80b0", "email": "alisher.bekov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
1f63d3e3-cfb5-5ff8-8750-8765e7286e09	1f63d3e3-cfb5-5ff8-8750-8765e7286e09	1f63d3e3-cfb5-5ff8-8750-8765e7286e09	{"sub": "1f63d3e3-cfb5-5ff8-8750-8765e7286e09", "email": "aisulu.dosmukhamedova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
7f082d5c-a953-51d5-a623-9d610ae577ba	7f082d5c-a953-51d5-a623-9d610ae577ba	7f082d5c-a953-51d5-a623-9d610ae577ba	{"sub": "7f082d5c-a953-51d5-a623-9d610ae577ba", "email": "nurlan.kairatov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
2614e032-72f6-5f47-b46b-2b6fa25f275a	2614e032-72f6-5f47-b46b-2b6fa25f275a	2614e032-72f6-5f47-b46b-2b6fa25f275a	{"sub": "2614e032-72f6-5f47-b46b-2b6fa25f275a", "email": "diana.utepova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
60c1d1fe-9756-50b7-aa0c-8938baaddde2	60c1d1fe-9756-50b7-aa0c-8938baaddde2	60c1d1fe-9756-50b7-aa0c-8938baaddde2	{"sub": "60c1d1fe-9756-50b7-aa0c-8938baaddde2", "email": "daniyar.ismailov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
70a6775f-7bbd-5dff-aa6d-bc15b4445aec	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	{"sub": "70a6775f-7bbd-5dff-aa6d-bc15b4445aec", "email": "dana.sadykova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
9bc90fbb-1ed4-5e71-a722-019e2cc44797	9bc90fbb-1ed4-5e71-a722-019e2cc44797	9bc90fbb-1ed4-5e71-a722-019e2cc44797	{"sub": "9bc90fbb-1ed4-5e71-a722-019e2cc44797", "email": "asel.kairatova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
cf43eb29-cfc9-5d39-ac2e-0d32e539c990	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	{"sub": "cf43eb29-cfc9-5d39-ac2e-0d32e539c990", "email": "amina.kairatova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
2c6189e6-c56d-5f5e-90e4-3ffcdef88870	2c6189e6-c56d-5f5e-90e4-3ffcdef88870	2c6189e6-c56d-5f5e-90e4-3ffcdef88870	{"sub": "2c6189e6-c56d-5f5e-90e4-3ffcdef88870", "email": "diana.akhmetova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
7cd65549-6305-538c-bfd9-ff7ee71213eb	7cd65549-6305-538c-bfd9-ff7ee71213eb	7cd65549-6305-538c-bfd9-ff7ee71213eb	{"sub": "7cd65549-6305-538c-bfd9-ff7ee71213eb", "email": "akbota.kassymova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
9738a135-fb05-52d2-9e40-e18b24491eb4	9738a135-fb05-52d2-9e40-e18b24491eb4	9738a135-fb05-52d2-9e40-e18b24491eb4	{"sub": "9738a135-fb05-52d2-9e40-e18b24491eb4", "email": "daniyar.kuanyshev@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
0550482d-49c2-5f52-a61f-1c4badd27285	0550482d-49c2-5f52-a61f-1c4badd27285	0550482d-49c2-5f52-a61f-1c4badd27285	{"sub": "0550482d-49c2-5f52-a61f-1c4badd27285", "email": "aliya.nurlanova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
49226873-bb4d-5af8-b6d7-b618b6111788	49226873-bb4d-5af8-b6d7-b618b6111788	49226873-bb4d-5af8-b6d7-b618b6111788	{"sub": "49226873-bb4d-5af8-b6d7-b618b6111788", "email": "miras.utepov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
8c6deb00-1371-546c-92a3-fa0544ab6f69	8c6deb00-1371-546c-92a3-fa0544ab6f69	8c6deb00-1371-546c-92a3-fa0544ab6f69	{"sub": "8c6deb00-1371-546c-92a3-fa0544ab6f69", "email": "alisher.zhakupov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
1625ce28-8df4-51c9-9370-e37f4726715d	1625ce28-8df4-51c9-9370-e37f4726715d	1625ce28-8df4-51c9-9370-e37f4726715d	{"sub": "1625ce28-8df4-51c9-9370-e37f4726715d", "email": "kamila.kuanysheva@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
89b01325-f844-5951-8b97-722e76d10e26	89b01325-f844-5951-8b97-722e76d10e26	89b01325-f844-5951-8b97-722e76d10e26	{"sub": "89b01325-f844-5951-8b97-722e76d10e26", "email": "moldir.omarova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	{"sub": "b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02", "email": "akbota.abenova@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	{"sub": "4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7", "email": "dias.abenov@nu.edu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
c5bf25b6-4f79-51ef-bcce-ed2d40dcc412	c5bf25b6-4f79-51ef-bcce-ed2d40dcc412	c5bf25b6-4f79-51ef-bcce-ed2d40dcc412	{"sub": "c5bf25b6-4f79-51ef-bcce-ed2d40dcc412", "email": "admin@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
ee4381b0-e713-5329-accc-f50e1a5ee4f6	ee4381b0-e713-5329-accc-f50e1a5ee4f6	ee4381b0-e713-5329-accc-f50e1a5ee4f6	{"sub": "ee4381b0-e713-5329-accc-f50e1a5ee4f6", "email": "a_tokayeva@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
32f48806-1d58-5528-ac5f-f78d0f615e62	32f48806-1d58-5528-ac5f-f78d0f615e62	32f48806-1d58-5528-ac5f-f78d0f615e62	{"sub": "32f48806-1d58-5528-ac5f-f78d0f615e62", "email": "z_nurlanova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
45667a63-75a2-5327-80b3-07277bbc3a05	45667a63-75a2-5327-80b3-07277bbc3a05	45667a63-75a2-5327-80b3-07277bbc3a05	{"sub": "45667a63-75a2-5327-80b3-07277bbc3a05", "email": "m_bekov@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
4aed59c4-076a-58ea-8df4-eee688fc3b38	4aed59c4-076a-58ea-8df4-eee688fc3b38	4aed59c4-076a-58ea-8df4-eee688fc3b38	{"sub": "4aed59c4-076a-58ea-8df4-eee688fc3b38", "email": "b_zhakupov@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
7e76cba5-592a-50a9-a6e4-fb36d39a9030	7e76cba5-592a-50a9-a6e4-fb36d39a9030	7e76cba5-592a-50a9-a6e4-fb36d39a9030	{"sub": "7e76cba5-592a-50a9-a6e4-fb36d39a9030", "email": "m_seitkali@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
b179af01-a01d-5d62-8805-310edc535f62	b179af01-a01d-5d62-8805-310edc535f62	b179af01-a01d-5d62-8805-310edc535f62	{"sub": "b179af01-a01d-5d62-8805-310edc535f62", "email": "z_akhmetova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
c595e95e-5ae4-58c8-b1f8-4b0d42c28318	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	{"sub": "c595e95e-5ae4-58c8-b1f8-4b0d42c28318", "email": "i_omarova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
edb9f7d5-f25d-5618-aed1-d3c8e12572ae	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	{"sub": "edb9f7d5-f25d-5618-aed1-d3c8e12572ae", "email": "a_iskakova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
c24a9165-fdd8-585f-b441-f68c0c7a3bfe	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	{"sub": "c24a9165-fdd8-585f-b441-f68c0c7a3bfe", "email": "o_tokayev@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
3ce15b25-c6e0-583d-a872-0dc16ae45020	3ce15b25-c6e0-583d-a872-0dc16ae45020	3ce15b25-c6e0-583d-a872-0dc16ae45020	{"sub": "3ce15b25-c6e0-583d-a872-0dc16ae45020", "email": "n_dosmukhamedov@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
cd609af0-f2d9-5556-9083-47c78c3e1318	cd609af0-f2d9-5556-9083-47c78c3e1318	cd609af0-f2d9-5556-9083-47c78c3e1318	{"sub": "cd609af0-f2d9-5556-9083-47c78c3e1318", "email": "m_ismailova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
ba12ad86-cec0-5c76-b72c-21e59427e8e5	ba12ad86-cec0-5c76-b72c-21e59427e8e5	ba12ad86-cec0-5c76-b72c-21e59427e8e5	{"sub": "ba12ad86-cec0-5c76-b72c-21e59427e8e5", "email": "d_utepova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
5a96375a-4aa6-5b7e-895c-ff70497093dd	5a96375a-4aa6-5b7e-895c-ff70497093dd	5a96375a-4aa6-5b7e-895c-ff70497093dd	{"sub": "5a96375a-4aa6-5b7e-895c-ff70497093dd", "email": "o_omarov@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	{"sub": "8276ebdf-8d22-5cc8-bb2d-d327fc7684d2", "email": "a_dosmukhamedova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
b2dc61bc-373b-5d0c-bf25-529d5200c066	b2dc61bc-373b-5d0c-bf25-529d5200c066	b2dc61bc-373b-5d0c-bf25-529d5200c066	{"sub": "b2dc61bc-373b-5d0c-bf25-529d5200c066", "email": "d_sadykova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
8557a85b-2ada-524a-9191-e5c392f2ecd0	8557a85b-2ada-524a-9191-e5c392f2ecd0	8557a85b-2ada-524a-9191-e5c392f2ecd0	{"sub": "8557a85b-2ada-524a-9191-e5c392f2ecd0", "email": "d_yesenov@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
d59eff6d-1910-5844-86ba-5c7c123704de	d59eff6d-1910-5844-86ba-5c7c123704de	d59eff6d-1910-5844-86ba-5c7c123704de	{"sub": "d59eff6d-1910-5844-86ba-5c7c123704de", "email": "z_omarova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
9630d339-6604-569b-85a5-534d3a118af7	9630d339-6604-569b-85a5-534d3a118af7	9630d339-6604-569b-85a5-534d3a118af7	{"sub": "9630d339-6604-569b-85a5-534d3a118af7", "email": "o_sadykov@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
f131d105-108d-58b0-b737-aee95985fa93	f131d105-108d-58b0-b737-aee95985fa93	f131d105-108d-58b0-b737-aee95985fa93	{"sub": "f131d105-108d-58b0-b737-aee95985fa93", "email": "d_yesenova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
d7eb4bfb-e5ec-5046-854b-2d724a29dff3	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	{"sub": "d7eb4bfb-e5ec-5046-854b-2d724a29dff3", "email": "s_omarova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
efd23983-5f8f-5e47-bba6-22cfcef33110	efd23983-5f8f-5e47-bba6-22cfcef33110	efd23983-5f8f-5e47-bba6-22cfcef33110	{"sub": "efd23983-5f8f-5e47-bba6-22cfcef33110", "email": "t_bekov@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
b322d3fb-18a5-5119-abc3-151933818abd	b322d3fb-18a5-5119-abc3-151933818abd	b322d3fb-18a5-5119-abc3-151933818abd	{"sub": "b322d3fb-18a5-5119-abc3-151933818abd", "email": "s_abenova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
75732734-f0dc-516b-ab8d-647bcd6f7210	75732734-f0dc-516b-ab8d-647bcd6f7210	75732734-f0dc-516b-ab8d-647bcd6f7210	{"sub": "75732734-f0dc-516b-ab8d-647bcd6f7210", "email": "a_baimukhanova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
7895e227-7cba-58d0-835e-69c8af3fcc63	7895e227-7cba-58d0-835e-69c8af3fcc63	7895e227-7cba-58d0-835e-69c8af3fcc63	{"sub": "7895e227-7cba-58d0-835e-69c8af3fcc63", "email": "a_seitkali@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
d723f696-83df-5e2e-9b66-1b6668a5bffb	d723f696-83df-5e2e-9b66-1b6668a5bffb	d723f696-83df-5e2e-9b66-1b6668a5bffb	{"sub": "d723f696-83df-5e2e-9b66-1b6668a5bffb", "email": "i_amanova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
511cedf2-bc02-56a1-a754-2540298f5cee	511cedf2-bc02-56a1-a754-2540298f5cee	511cedf2-bc02-56a1-a754-2540298f5cee	{"sub": "511cedf2-bc02-56a1-a754-2540298f5cee", "email": "i_abenova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
12dc5f6c-cb16-5110-abfa-a398961b181a	12dc5f6c-cb16-5110-abfa-a398961b181a	12dc5f6c-cb16-5110-abfa-a398961b181a	{"sub": "12dc5f6c-cb16-5110-abfa-a398961b181a", "email": "a_zhumabekov@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
301d506e-f995-5472-824e-7223eea34b29	301d506e-f995-5472-824e-7223eea34b29	301d506e-f995-5472-824e-7223eea34b29	{"sub": "301d506e-f995-5472-824e-7223eea34b29", "email": "a_kairatov@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
7caf10cc-bc08-579a-befd-dfa14a46a71b	7caf10cc-bc08-579a-befd-dfa14a46a71b	7caf10cc-bc08-579a-befd-dfa14a46a71b	{"sub": "7caf10cc-bc08-579a-befd-dfa14a46a71b", "email": "a_zhakupova@mnu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
55d7564d-881c-5453-8a12-ea7124e538f0	55d7564d-881c-5453-8a12-ea7124e538f0	55d7564d-881c-5453-8a12-ea7124e538f0	{"sub": "55d7564d-881c-5453-8a12-ea7124e538f0", "email": "admin@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
a1aba091-ac3f-5cfb-8f0e-025ddbe56044	a1aba091-ac3f-5cfb-8f0e-025ddbe56044	a1aba091-ac3f-5cfb-8f0e-025ddbe56044	{"sub": "a1aba091-ac3f-5cfb-8f0e-025ddbe56044", "email": "kairatov.n@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
37dd3141-05ee-5e5d-a4f2-fb04179e158b	37dd3141-05ee-5e5d-a4f2-fb04179e158b	37dd3141-05ee-5e5d-a4f2-fb04179e158b	{"sub": "37dd3141-05ee-5e5d-a4f2-fb04179e158b", "email": "serikbayeva.m@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
1686e8b7-7ab0-56f5-894c-17df38559d0b	1686e8b7-7ab0-56f5-894c-17df38559d0b	1686e8b7-7ab0-56f5-894c-17df38559d0b	{"sub": "1686e8b7-7ab0-56f5-894c-17df38559d0b", "email": "omarova.z@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	{"sub": "7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1", "email": "zhumabekov.o@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
e57e4f91-200d-5996-8f1f-c4140498ccb5	e57e4f91-200d-5996-8f1f-c4140498ccb5	e57e4f91-200d-5996-8f1f-c4140498ccb5	{"sub": "e57e4f91-200d-5996-8f1f-c4140498ccb5", "email": "yesenov.s@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
47ac5cee-f468-5dd9-bd2f-994a2e1556fe	47ac5cee-f468-5dd9-bd2f-994a2e1556fe	47ac5cee-f468-5dd9-bd2f-994a2e1556fe	{"sub": "47ac5cee-f468-5dd9-bd2f-994a2e1556fe", "email": "iskakov.m@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
333281b0-ea48-5904-bc0d-1baecafb3642	333281b0-ea48-5904-bc0d-1baecafb3642	333281b0-ea48-5904-bc0d-1baecafb3642	{"sub": "333281b0-ea48-5904-bc0d-1baecafb3642", "email": "serikbayev.y@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
0714361c-2671-547c-a5e8-7412dd5f5bb2	0714361c-2671-547c-a5e8-7412dd5f5bb2	0714361c-2671-547c-a5e8-7412dd5f5bb2	{"sub": "0714361c-2671-547c-a5e8-7412dd5f5bb2", "email": "rakhimova.d@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
91665b25-1a02-5391-be1f-630466bf5a2f	91665b25-1a02-5391-be1f-630466bf5a2f	91665b25-1a02-5391-be1f-630466bf5a2f	{"sub": "91665b25-1a02-5391-be1f-630466bf5a2f", "email": "ismailova.a@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
f036e23d-5323-5b4f-bb1c-6e87c77bff75	f036e23d-5323-5b4f-bb1c-6e87c77bff75	f036e23d-5323-5b4f-bb1c-6e87c77bff75	{"sub": "f036e23d-5323-5b4f-bb1c-6e87c77bff75", "email": "seitkali.e@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
ce4654ab-6f97-5ba5-8e75-a674b62406d8	ce4654ab-6f97-5ba5-8e75-a674b62406d8	ce4654ab-6f97-5ba5-8e75-a674b62406d8	{"sub": "ce4654ab-6f97-5ba5-8e75-a674b62406d8", "email": "amanova.k@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
5ab878f5-0da1-5a83-9dd1-f19a741d738e	5ab878f5-0da1-5a83-9dd1-f19a741d738e	5ab878f5-0da1-5a83-9dd1-f19a741d738e	{"sub": "5ab878f5-0da1-5a83-9dd1-f19a741d738e", "email": "seitkali.a@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
af37d114-6cbb-5069-9e3e-89e207493efa	af37d114-6cbb-5069-9e3e-89e207493efa	af37d114-6cbb-5069-9e3e-89e207493efa	{"sub": "af37d114-6cbb-5069-9e3e-89e207493efa", "email": "seitkali.z@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
7e59a7bf-1599-5d03-870a-b80f4a201398	7e59a7bf-1599-5d03-870a-b80f4a201398	7e59a7bf-1599-5d03-870a-b80f4a201398	{"sub": "7e59a7bf-1599-5d03-870a-b80f4a201398", "email": "amanova.a@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
e2b516de-c76c-532d-8e53-5d02edbfa4ec	e2b516de-c76c-532d-8e53-5d02edbfa4ec	e2b516de-c76c-532d-8e53-5d02edbfa4ec	{"sub": "e2b516de-c76c-532d-8e53-5d02edbfa4ec", "email": "utepova.k@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
bed83121-8bf1-5da8-b173-e725dd4e2e71	bed83121-8bf1-5da8-b173-e725dd4e2e71	bed83121-8bf1-5da8-b173-e725dd4e2e71	{"sub": "bed83121-8bf1-5da8-b173-e725dd4e2e71", "email": "omarov.a@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
d798b580-e0a7-5aa0-b42b-c9509861df97	d798b580-e0a7-5aa0-b42b-c9509861df97	d798b580-e0a7-5aa0-b42b-c9509861df97	{"sub": "d798b580-e0a7-5aa0-b42b-c9509861df97", "email": "bekov.t@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
1e821e58-daac-52d8-9ff6-668fa3f23828	1e821e58-daac-52d8-9ff6-668fa3f23828	1e821e58-daac-52d8-9ff6-668fa3f23828	{"sub": "1e821e58-daac-52d8-9ff6-668fa3f23828", "email": "omarov.t@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
c72f74fd-f7ae-5e0d-9c17-09eb9f747580	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	{"sub": "c72f74fd-f7ae-5e0d-9c17-09eb9f747580", "email": "rakhimova.z@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
ccd0071a-1fd0-5515-a5b8-937a6bb79b26	ccd0071a-1fd0-5515-a5b8-937a6bb79b26	ccd0071a-1fd0-5515-a5b8-937a6bb79b26	{"sub": "ccd0071a-1fd0-5515-a5b8-937a6bb79b26", "email": "baimukhanov.a@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
d52c4849-0424-556a-909f-dc1685c34ca7	d52c4849-0424-556a-909f-dc1685c34ca7	d52c4849-0424-556a-909f-dc1685c34ca7	{"sub": "d52c4849-0424-556a-909f-dc1685c34ca7", "email": "yesenov.m@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
fd594592-8d60-5f8c-be18-349a233ea712	fd594592-8d60-5f8c-be18-349a233ea712	fd594592-8d60-5f8c-be18-349a233ea712	{"sub": "fd594592-8d60-5f8c-be18-349a233ea712", "email": "yesenova.z@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
3cfd1e72-fe25-526e-abce-f5c282026b57	3cfd1e72-fe25-526e-abce-f5c282026b57	3cfd1e72-fe25-526e-abce-f5c282026b57	{"sub": "3cfd1e72-fe25-526e-abce-f5c282026b57", "email": "baimukhanov.d@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
cd999017-1402-5a6e-b041-fdafc8ded0f0	cd999017-1402-5a6e-b041-fdafc8ded0f0	cd999017-1402-5a6e-b041-fdafc8ded0f0	{"sub": "cd999017-1402-5a6e-b041-fdafc8ded0f0", "email": "kassymov.a@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
4b052f0a-0cb1-59a1-912b-2786fdd40f68	4b052f0a-0cb1-59a1-912b-2786fdd40f68	4b052f0a-0cb1-59a1-912b-2786fdd40f68	{"sub": "4b052f0a-0cb1-59a1-912b-2786fdd40f68", "email": "kassymova.i@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
1c41b127-85d5-5028-9e30-ef9cea4990f8	1c41b127-85d5-5028-9e30-ef9cea4990f8	1c41b127-85d5-5028-9e30-ef9cea4990f8	{"sub": "1c41b127-85d5-5028-9e30-ef9cea4990f8", "email": "kairatova.a@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	{"sub": "6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e", "email": "yesenov.n@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
a3692637-7d1e-50da-b993-3a5d101307b0	a3692637-7d1e-50da-b993-3a5d101307b0	a3692637-7d1e-50da-b993-3a5d101307b0	{"sub": "a3692637-7d1e-50da-b993-3a5d101307b0", "email": "kairatova.t@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
10cfe625-92d9-5f2d-8c28-3da5a44180d7	10cfe625-92d9-5f2d-8c28-3da5a44180d7	10cfe625-92d9-5f2d-8c28-3da5a44180d7	{"sub": "10cfe625-92d9-5f2d-8c28-3da5a44180d7", "email": "iskakov.a@enu.kz", "email_verified": true}	email	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: postgres
--

COPY auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change) FROM stdin;
00000000-0000-0000-0000-000000000000	ce4d212d-dc26-5d4b-970b-719c3ea9fc2e	authenticated	authenticated	admin@astanait.edu.kz	$2a$10$DYnQ1FnrsjAWcg/4OUzv8.eyTrYmqY5oHwf7SE/gMD54Fvu8EoNg6	2026-10-11 17:54:36.817683+00	{"role": "admin", "provider": "email", "providers": ["email"]}	{"last_name": "AITU", "first_name": "Admin"}	2026-08-19 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	44a51247-0f45-5096-9fca-81ed70346a12	authenticated	authenticated	246466@astanait.edu.kz	$2a$10$bG561MLxWF.bh/IQGo2IEeEfdV485ccrKnZxeZz/1Tmzksyz2Jb0S	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Iskakov", "first_name": "Yerlan"}	2026-08-22 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	authenticated	authenticated	233363@astanait.edu.kz	$2a$10$5gn7rihkQD8YfxFQsGrZDud13SKktJ1DDrnB/9ncBlLP7PCHVFd4u	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Amanova", "first_name": "Diana"}	2026-08-24 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	d6a0339c-e841-56e2-9be8-3c789fb9a47b	authenticated	authenticated	248237@astanait.edu.kz	$2a$10$SgECsrKVgVtXJBKPiX0ineBkFv2y48tk0s3rjrO7AOVY9KYDimja6	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Serikbayeva", "first_name": "Dariga"}	2026-09-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	0631a63b-ebc2-5785-a739-9fee4b48e5bc	authenticated	authenticated	247950@astanait.edu.kz	$2a$10$eiWf6HxjiNFtF1eFElqSUOYbPVLF6LgcLXyeGSLeTApI3VM5MDoOW	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Tokayeva", "first_name": "Moldir"}	2026-08-19 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	authenticated	authenticated	244453@astanait.edu.kz	$2a$10$4QQJJpclKhDc8/obXVi/puBM5QQncCSLzabJKyRPrOxCSF3MNd3Ym	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Tokayev", "first_name": "Nurlan"}	2026-08-19 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	bb9f8bce-5de6-54be-a471-3c22fff845f5	authenticated	authenticated	232645@astanait.edu.kz	$2a$10$vKHFkYyLmfjD7nGuyasMLuLm3rHkiZzqxCRuDkxm7gBM.F5Q3G1KC	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Abenov", "first_name": "Bekzat"}	2026-09-04 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	ad5b5e1b-07b1-5134-ae83-b16af18abe40	authenticated	authenticated	233212@astanait.edu.kz	$2a$10$vm.DOt5ECLRp7GoQWu51WOVf1UQNjH5HpwpchQCaNXmWJa6dzzQ3u	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Sadykov", "first_name": "Yerlan"}	2026-09-15 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	123a74f4-143d-5603-81d5-6331401ea569	authenticated	authenticated	246065@astanait.edu.kz	$2a$10$vHu/H9LTqzunMg6ZbAUKSuZ6T02wLQwxRE84gTxoBessQaSXDU9e.	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Abenova", "first_name": "Akbota"}	2026-09-08 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	289a1a72-f5c0-5531-a5a2-1431eae3980d	authenticated	authenticated	243016@astanait.edu.kz	$2a$10$9iSK9QtRkf8/d6NYRYdks./IGA72Q5U9UPic0Hm.r2brACiEsGwIm	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Bekova", "first_name": "Asel"}	2026-09-07 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	5c29fc1f-628e-5bdc-9e83-3e576df263d4	authenticated	authenticated	241686@astanait.edu.kz	$2a$10$mYXnJ.XALl4rP9Mn4pT3Iu08xOnIxJtZk6/F7.idlgLFbEN5lDiw2	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Mukanova", "first_name": "Aisulu"}	2026-09-21 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	594c5eb8-5eba-5db1-9527-7d409b4281ab	authenticated	authenticated	246829@astanait.edu.kz	$2a$10$MOjkopvZ9ZbVIiMeCsr63OSvfv7o2KpTAYy5cBVjXqXknRIVKPNN6	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kuanysheva", "first_name": "Saule"}	2026-09-16 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	a6a72968-235d-553f-84a7-223f70ff71da	authenticated	authenticated	241154@astanait.edu.kz	$2a$10$H40/ux4qoMVGeBanx/2yeux9eO.r3SCzJLLRK9uPKAZHSKwDDlka2	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kuanysheva", "first_name": "Aigerim"}	2026-08-23 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	b88dd4ac-02c8-576e-96b7-dad2fcc30210	authenticated	authenticated	247631@astanait.edu.kz	$2a$10$.A5lgzkF14irdmeyMWvV4ef39MNs0BTY4DcR854y3y1TGCtz/DaFa	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Ismailov", "first_name": "Dias"}	2026-08-31 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	daecc825-1e7a-51cd-a171-4a41488773ae	authenticated	authenticated	244989@astanait.edu.kz	$2a$10$6gmL7YlGnnkQzmnHhksHru97W/BQGFLuSfhZ1hCKbaU2mc64YlEGy	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Sadykova", "first_name": "Tomiris"}	2026-08-26 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	authenticated	authenticated	248921@astanait.edu.kz	$2a$10$iXni2v4UNMAfQUAkavDOF.zOQoT1R1wyg/HArRc03M2IES0K34JN.	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Amanov", "first_name": "Temirlan"}	2026-08-18 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	bf1b1568-063d-5529-a346-27dcbdb160fc	authenticated	authenticated	242086@astanait.edu.kz	$2a$10$Yk3F1tOmTzO0He4GotO7.uimBs5WsQD8dVtIDg0q9R2aImVrepFee	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Abenov", "first_name": "Adil"}	2026-09-10 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	bf5483dd-f9be-503e-b843-511fab7772f3	authenticated	authenticated	243835@astanait.edu.kz	$2a$10$PjW.W/162AW.2j22gdRdv.K7e7rc3Ah2gvYSbfJMEUVjdkuSlIkGW	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kairatov", "first_name": "Alisher"}	2026-09-20 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	c39ee07c-08d3-51a9-8933-c3f20abe6a2d	authenticated	authenticated	249192@astanait.edu.kz	$2a$10$QgW00/1IjEDU4dr.OtNS8uE6ySprSAZXzQm8v7t8eOP133aKFP1Am	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Baimukhanov", "first_name": "Dias"}	2026-08-30 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	2667ad63-20cd-5653-af95-685a96aec1cb	authenticated	authenticated	233815@astanait.edu.kz	$2a$10$tjc3Sg7wlIfQ7RiMKsmfnOR448Ve8GvVsUdx07bNqLBt4JWwOysbG	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Utepov", "first_name": "Askar"}	2026-09-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	841aeb58-3431-5102-81be-941918ee4320	authenticated	authenticated	249666@astanait.edu.kz	$2a$10$C.Fak02erhZ2tOep.4CDV.erEWWwaVUfw7RA4vizcVXpA8wR0l2Yq	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Zhumabekov", "first_name": "Daniyar"}	2026-08-30 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	bc586d94-7153-5cf0-8676-68bcb94a0d5a	authenticated	authenticated	247191@astanait.edu.kz	$2a$10$t74x3k35.eg9cgz2lGtqyeH8klQxU3Q8mZBggorvuQOMF/iGpEPEa	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Baimukhanov", "first_name": "Nurlan"}	2026-08-17 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	813640c1-13d1-52ed-b333-486966e596de	authenticated	authenticated	248481@astanait.edu.kz	$2a$10$8nUHQ3gPBHQbYo2Ttrksx.H9ALAa8vUwt15qKWbNMCwCgxsj9P7hG	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Yesenova", "first_name": "Aisulu"}	2026-08-16 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	authenticated	authenticated	246973@astanait.edu.kz	$2a$10$/Aain2mhC5i4S77kIiH5BeIVFWMkyhDQxEVR2x/yVq/8lNcHQaqWO	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Zhumabekova", "first_name": "Aliya"}	2026-08-18 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	398c2e60-8a06-5f46-8fb0-e117c255ead8	authenticated	authenticated	237357@astanait.edu.kz	$2a$10$wjk8ZcNRDGFTb5aHQq67EetDDOT/MI0wIo1ThnejYiODjueoubpm.	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Tokayev", "first_name": "Alikhan"}	2026-09-08 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	authenticated	authenticated	247144@astanait.edu.kz	$2a$10$32DEgld4MAUeXdDGJcrK1epgD61UybhHObwAQJYey95RZVBXXHVLa	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Seitkali", "first_name": "Madina"}	2026-09-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	b4455c9f-c726-58c4-a73d-dc7ac20b4280	authenticated	authenticated	244070@astanait.edu.kz	$2a$10$ENQNh4U.xi7PVnOZhkZK3eZ3WpqgdTP5u.x0Bzv5.a6voczrm.YFm	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Dosmukhamedova", "first_name": "Amina"}	2026-08-13 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	22177d59-b6dd-5230-ad3a-3f20a82c77be	authenticated	authenticated	245797@astanait.edu.kz	$2a$10$hIT/ejbd7gOvVWlVTjkjiO7Eall6H.Xwc8vstd0Etce5rW.V0KB9C	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Omarova", "first_name": "Aliya"}	2026-09-04 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	4375a7a0-75af-50b6-bf34-ac0b79555581	authenticated	authenticated	244968@astanait.edu.kz	$2a$10$Dg7fF05AryyqBAaQfHs78uh5c0vMW42Cv6FsuO6Ow.P9oiW.WtSmC	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Zhakupova", "first_name": "Dariga"}	2026-08-17 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	e1f7cb84-a272-5286-8d3b-6004b94c9fea	authenticated	authenticated	247879@astanait.edu.kz	$2a$10$OAcLGzbOHM0lExEloEbaHOwGBSIZk6mHkuv4yRZCD4rublq2SQY32	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Dosmukhamedova", "first_name": "Aliya"}	2026-08-16 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	9871575d-9f8d-5ea2-aafb-4cf2d460a9ca	authenticated	authenticated	admin@nu.edu.kz	$2a$10$dLQX4ChsUYSnFpzJJqFIfOD4v7w4hJfCs.uaxZqUWdYWeSn..9QUO	2026-10-11 17:54:36.817683+00	{"role": "admin", "provider": "email", "providers": ["email"]}	{"last_name": "NU", "first_name": "Admin"}	2026-09-08 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a	authenticated	authenticated	aisulu.ismailova@nu.edu.kz	$2a$10$n0xIVpc0l1v0measYCQaVeN94O21VOxnE6yp2izfRThw/wN8f.34i	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Ismailova", "first_name": "Aisulu"}	2026-08-16 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	authenticated	authenticated	ernar.rakhimov@nu.edu.kz	$2a$10$czF96Ggu0pjgw1CP6/6pAuLcQFewMjMDr5ckDIRXH.3y5j78VOYsu	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Rakhimov", "first_name": "Ernar"}	2026-09-03 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	authenticated	authenticated	adil.ismailov@nu.edu.kz	$2a$10$2lJ3uU9neoC1oaZC0w8jKee//ruxXEY.ol4zdBjdlTpxi5aTj0RF6	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Ismailov", "first_name": "Adil"}	2026-08-16 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	448fc3a2-4bb5-55c5-af6c-daa5b70403fc	authenticated	authenticated	diana.dosmukhamedova@nu.edu.kz	$2a$10$LdocvUFDCig6x3FjBeS7GOPt2IGBnmbESLPM8ocqSMacJk1HKNaZ6	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Dosmukhamedova", "first_name": "Diana"}	2026-09-04 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	authenticated	authenticated	aliya.baimukhanova@nu.edu.kz	$2a$10$iwxXfWdW9ecgxWbBV/OMo.k22RjwT40NkKS5Mom2JgOZ5MO7u.u8W	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Baimukhanova", "first_name": "Aliya"}	2026-08-17 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	7106add8-93da-510c-a2ee-43f512e49d3c	authenticated	authenticated	daniyar.bekov@nu.edu.kz	$2a$10$yUDCr0Yd4ydfdSAs4c2cQuRKXYjzqJWBgWNxB8JlYvjWsAeJwTw9u	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Bekov", "first_name": "Daniyar"}	2026-09-13 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	c25c9587-af2d-50a5-9cbc-1fdf3302f483	authenticated	authenticated	tomiris.akhmetova@nu.edu.kz	$2a$10$V2yZR7NiM0Ymaf7fCMq88.rPLr6nPon5wKhGw9f6lCTkOsXCoyTeO	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Akhmetova", "first_name": "Tomiris"}	2026-09-15 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	18e969e2-d4e6-52f4-8e81-e62265f128f5	authenticated	authenticated	aruzhan.seitkali@nu.edu.kz	$2a$10$vKeimGV1n/wpzcU9WdRq3OvBr5FtfT1YLRm1AT6aUEfe4cbqdxI7S	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Seitkali", "first_name": "Aruzhan"}	2026-09-05 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	authenticated	authenticated	temirlan.amanov@nu.edu.kz	$2a$10$kylYTlHsAj8W25shdzo6suFst1TRyjjSUMgBFqO5tFOhMNbnIvO2W	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Amanov", "first_name": "Temirlan"}	2026-09-15 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	authenticated	authenticated	ayaulym.kairatova@nu.edu.kz	$2a$10$6F/cjl3epndEuFBfKY/8luRon.JztRuI0RvWsZEGGmunFM1NbruYG	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kairatova", "first_name": "Ayaulym"}	2026-08-25 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	3c16f96c-897e-5713-b4ce-ffc817887105	authenticated	authenticated	timur.utepov@nu.edu.kz	$2a$10$1TOrIGU4/e9/n0bp4XP2JetuceVyxirQMxPk9jaEUChGH1JEX33T.	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Utepov", "first_name": "Timur"}	2026-09-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	authenticated	authenticated	alisher.bekov@nu.edu.kz	$2a$10$z8LZotM1zCKCRbsAcJ5L9uIxkoN2tvXQ8qM2pqMzolKS7CWMm74Ji	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Bekov", "first_name": "Alisher"}	2026-09-15 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	1f63d3e3-cfb5-5ff8-8750-8765e7286e09	authenticated	authenticated	aisulu.dosmukhamedova@nu.edu.kz	$2a$10$Qn1pUsxvHRLqYGd9B/cQ9ucHT22Hpt2bgd8iF5.5L06SHdD6mYh4G	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Dosmukhamedova", "first_name": "Aisulu"}	2026-09-18 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	7f082d5c-a953-51d5-a623-9d610ae577ba	authenticated	authenticated	nurlan.kairatov@nu.edu.kz	$2a$10$.0//H4WPztSDN/O8YJE75.XtFRZjk2Hzi.M9Vh/frP8odk3kDBp.K	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kairatov", "first_name": "Nurlan"}	2026-08-30 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	2614e032-72f6-5f47-b46b-2b6fa25f275a	authenticated	authenticated	diana.utepova@nu.edu.kz	$2a$10$4KOnW8JreFb1ZevaxXA3N.WoczDiCsZR9Jv2VxV.x55e6HV1nS06q	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Utepova", "first_name": "Diana"}	2026-09-10 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	60c1d1fe-9756-50b7-aa0c-8938baaddde2	authenticated	authenticated	daniyar.ismailov@nu.edu.kz	$2a$10$QsU/gsTXi2tIFL9l1kbdpOMrDIma4nSBaXgK3wvPe/6sRCnTUSb5e	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Ismailov", "first_name": "Daniyar"}	2026-08-12 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	authenticated	authenticated	dana.sadykova@nu.edu.kz	$2a$10$Tdlz3wabHGglbhpc.T.xWuk7To7OFjWhxeOTo9VhiVVNJeR3g6pO6	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Sadykova", "first_name": "Dana"}	2026-09-15 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	9bc90fbb-1ed4-5e71-a722-019e2cc44797	authenticated	authenticated	asel.kairatova@nu.edu.kz	$2a$10$jNBdMtzLs70ch6u6t.rvNO3Pj388krIL7zt114i4BatF2iIFba42u	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kairatova", "first_name": "Asel"}	2026-08-20 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	authenticated	authenticated	amina.kairatova@nu.edu.kz	$2a$10$izMMOopfA05QL1K.TTPqveR.wB2Nvu.Z9KTcoL2BDtPJqBVUmDlB2	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kairatova", "first_name": "Amina"}	2026-09-01 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	2c6189e6-c56d-5f5e-90e4-3ffcdef88870	authenticated	authenticated	diana.akhmetova@nu.edu.kz	$2a$10$QMksiWQmoOeOy1dCRQBOzusOlIgPMaSW8Aj08zfGmVLCr4C80r.Dy	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Akhmetova", "first_name": "Diana"}	2026-09-04 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	7cd65549-6305-538c-bfd9-ff7ee71213eb	authenticated	authenticated	akbota.kassymova@nu.edu.kz	$2a$10$.a1o0Y2QntVhq.yVhQrWeedvyOv2RyH8rOKzVuGrCVqssukkiHePe	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kassymova", "first_name": "Akbota"}	2026-08-15 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	9738a135-fb05-52d2-9e40-e18b24491eb4	authenticated	authenticated	daniyar.kuanyshev@nu.edu.kz	$2a$10$7vecTXb1RdaIX//CKR4mueqvkVqkiQEm/8/5jQTD8B4pWgXpPJP2S	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kuanyshev", "first_name": "Daniyar"}	2026-09-17 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	0550482d-49c2-5f52-a61f-1c4badd27285	authenticated	authenticated	aliya.nurlanova@nu.edu.kz	$2a$10$8iMbS2hYBXL/XLgD6ihmjen4jA8pr5wGGgUB1RTcFEQhlZi4bZrD2	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Nurlanova", "first_name": "Aliya"}	2026-09-03 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	49226873-bb4d-5af8-b6d7-b618b6111788	authenticated	authenticated	miras.utepov@nu.edu.kz	$2a$10$qJwib/7upIdAEkT6P2T.UeSlY43HY0KV1J9TveAsBRWr5UL2bp2Qi	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Utepov", "first_name": "Miras"}	2026-09-01 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	8c6deb00-1371-546c-92a3-fa0544ab6f69	authenticated	authenticated	alisher.zhakupov@nu.edu.kz	$2a$10$IaK7qDPcrHEw/.ZTE2PQLuP1BAfZTBbaAXedXObLrW0AV7p0fm2ly	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Zhakupov", "first_name": "Alisher"}	2026-09-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	1625ce28-8df4-51c9-9370-e37f4726715d	authenticated	authenticated	kamila.kuanysheva@nu.edu.kz	$2a$10$iMGIHrEdQdtqwZRR7WG7oevdK2lwGBrmiaqt7Wm7NzCbzaYD.CGI6	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kuanysheva", "first_name": "Kamila"}	2026-09-05 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	89b01325-f844-5951-8b97-722e76d10e26	authenticated	authenticated	moldir.omarova@nu.edu.kz	$2a$10$Pv0mcTsqmMDC8ZCVOojxbuXUSqiVivW6sTPnQR4ssGuq2GOhMmC1e	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Omarova", "first_name": "Moldir"}	2026-09-05 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	authenticated	authenticated	akbota.abenova@nu.edu.kz	$2a$10$jYPLBOrgQaw1zG2RvU/fc.a4xryPuW5jgN.72YXhJuHbfoj6vYlHG	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Abenova", "first_name": "Akbota"}	2026-09-17 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	authenticated	authenticated	dias.abenov@nu.edu.kz	$2a$10$WtR2XA2SkD/4pwJBNMi2i.lT7U2yib/93YdkavPDjAGGp8inqDLbm	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Abenov", "first_name": "Dias"}	2026-09-21 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	c5bf25b6-4f79-51ef-bcce-ed2d40dcc412	authenticated	authenticated	admin@mnu.kz	$2a$10$s2U7qm98UI/o//Y6SNlDUuT0f.0OMYABan6hFlj4oC6EvIY7GVtQi	2026-10-11 17:54:36.817683+00	{"role": "admin", "provider": "email", "providers": ["email"]}	{"last_name": "MNU", "first_name": "Admin"}	2026-08-26 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	ee4381b0-e713-5329-accc-f50e1a5ee4f6	authenticated	authenticated	a_tokayeva@mnu.kz	$2a$10$D4ET0N5iO2J2R2Xs4w2vw.c7lyV54DltPCGfTCxHOUaZL.sKnD2/q	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Tokayeva", "first_name": "Akbota"}	2026-09-05 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	32f48806-1d58-5528-ac5f-f78d0f615e62	authenticated	authenticated	z_nurlanova@mnu.kz	$2a$10$rmz80XFlCZWBA8VDfwD7SOILr6HrgksPl4kUsiuUOYxJUlRKZd21G	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Nurlanova", "first_name": "Zarina"}	2026-08-26 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	45667a63-75a2-5327-80b3-07277bbc3a05	authenticated	authenticated	m_bekov@mnu.kz	$2a$10$kQZXCg5OJXC6m/8WJ.YMke0ajEnz.TxNMANRQyNqcAYqQQRNyeuFm	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Bekov", "first_name": "Maksat"}	2026-09-21 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	4aed59c4-076a-58ea-8df4-eee688fc3b38	authenticated	authenticated	b_zhakupov@mnu.kz	$2a$10$wkf9W7oA6erwTBv4vp167e34Q7nPKI4NSwhhtNccSRwukm.aKhvzK	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Zhakupov", "first_name": "Bekzat"}	2026-09-18 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	7e76cba5-592a-50a9-a6e4-fb36d39a9030	authenticated	authenticated	m_seitkali@mnu.kz	$2a$10$4g3pGbcOi4lTRyWEOsgpXOo2mdutCDj7Yb4Gyd3vOgQjXEq0zQ4Fi	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Seitkali", "first_name": "Maksat"}	2026-09-15 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	b179af01-a01d-5d62-8805-310edc535f62	authenticated	authenticated	z_akhmetova@mnu.kz	$2a$10$gWhoIYFj3KtMvkVpHBPoZuAOxC8yveAMMKJb4s20jBlzpo1DJax7e	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Akhmetova", "first_name": "Zarina"}	2026-09-06 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	authenticated	authenticated	i_omarova@mnu.kz	$2a$10$zme21n.AtcvXpB4A1jRr7.l9/GrJpHe6BrWvlsX43ftJ8yXNQvdHa	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Omarova", "first_name": "Inkar"}	2026-09-20 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	authenticated	authenticated	a_iskakova@mnu.kz	$2a$10$Yd7Oa4GQXXm3NFR/RZNHsu/Y.HdNc9Wkxg1mlMsmAE8skdetjTF0S	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Iskakova", "first_name": "Aruzhan"}	2026-09-02 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	authenticated	authenticated	o_tokayev@mnu.kz	$2a$10$60QIp3kBt7nLFQxQeBxS3.Mb7LX9c6hlfFjivxCZJXBjTcyyaa9/O	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Tokayev", "first_name": "Olzhas"}	2026-09-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	3ce15b25-c6e0-583d-a872-0dc16ae45020	authenticated	authenticated	n_dosmukhamedov@mnu.kz	$2a$10$qPNCApnZofuuEIEZhAOIWu3O9bnCyCPuyRquZP3BUyrKjW1z.ix9y	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Dosmukhamedov", "first_name": "Nurlan"}	2026-09-15 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	cd609af0-f2d9-5556-9083-47c78c3e1318	authenticated	authenticated	m_ismailova@mnu.kz	$2a$10$kPtRqQoibtq34UYGwc/Np.APdk6GR482yL0f.Fis6OrNzyzpCNl5e	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Ismailova", "first_name": "Madina"}	2026-08-17 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	ba12ad86-cec0-5c76-b72c-21e59427e8e5	authenticated	authenticated	d_utepova@mnu.kz	$2a$10$IzWofOLAAJ9Y/GmZLFdmRufDhjohp6buIMVuw50SJhUDTZ.J3lgeK	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Utepova", "first_name": "Dariga"}	2026-08-16 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	5a96375a-4aa6-5b7e-895c-ff70497093dd	authenticated	authenticated	o_omarov@mnu.kz	$2a$10$KOMZ66UdUiXtH7q7dVwroOrePaYNccm3TMdGWYcarCEigWcmDcqmW	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Omarov", "first_name": "Olzhas"}	2026-08-30 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	authenticated	authenticated	a_dosmukhamedova@mnu.kz	$2a$10$ENg5ERxkHsamwNHKEnyJt.IFyLGbowhy0aXJJlspQAGW2DD.BVjfa	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Dosmukhamedova", "first_name": "Ayaulym"}	2026-09-01 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	b2dc61bc-373b-5d0c-bf25-529d5200c066	authenticated	authenticated	d_sadykova@mnu.kz	$2a$10$wAq.9U5e8tzaD/bRtbpOZ.6ajHf8NZAtcBvmBW3nMHFQjqryqnjkO	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Sadykova", "first_name": "Diana"}	2026-08-23 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	8557a85b-2ada-524a-9191-e5c392f2ecd0	authenticated	authenticated	d_yesenov@mnu.kz	$2a$10$ycPpN9.A/wFAL/bMjbFaXeeZApOeoN/CHz7YQCQECCE0PsltkeqBa	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Yesenov", "first_name": "Dias"}	2026-08-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	d59eff6d-1910-5844-86ba-5c7c123704de	authenticated	authenticated	z_omarova@mnu.kz	$2a$10$gJ8gkqZDEDf9KSd2g8EEb.rph4T5HxkFbLmm.5PwXVa1C47WiboIi	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Omarova", "first_name": "Zhanel"}	2026-08-12 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	9630d339-6604-569b-85a5-534d3a118af7	authenticated	authenticated	o_sadykov@mnu.kz	$2a$10$g2H/744y8a0vbQTmFIbQv.TbRASzAyjbic1FUuQ4UGW7avwV.L5/i	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Sadykov", "first_name": "Olzhas"}	2026-08-13 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	f131d105-108d-58b0-b737-aee95985fa93	authenticated	authenticated	d_yesenova@mnu.kz	$2a$10$KoDYYk5wqSdqp4yf1k60aOmMsFHafkVs6LQ4B6McSK59xfEGtn5Ku	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Yesenova", "first_name": "Diana"}	2026-09-19 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	authenticated	authenticated	s_omarova@mnu.kz	$2a$10$4.GOgBSAyVczgR.YvZ.9uukLnSkMFhnytreol74JGLCOKk7PdIU1W	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Omarova", "first_name": "Saule"}	2026-08-27 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	efd23983-5f8f-5e47-bba6-22cfcef33110	authenticated	authenticated	t_bekov@mnu.kz	$2a$10$ez2iGz0SojPlmfjkBnjkdO0HLIzeSzIJUQUwYvuI7.rWgpPs6vllm	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Bekov", "first_name": "Timur"}	2026-09-01 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	b322d3fb-18a5-5119-abc3-151933818abd	authenticated	authenticated	s_abenova@mnu.kz	$2a$10$QxVnuye1bPgpvnusA2SKWuW1vZCsjuvE1kgzViZBafmVIUj0edi/W	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Abenova", "first_name": "Saule"}	2026-08-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	75732734-f0dc-516b-ab8d-647bcd6f7210	authenticated	authenticated	a_baimukhanova@mnu.kz	$2a$10$SYggWfKK5xBPW3w2jvcDx.GtCjUlS/0r.FW5..ed1a/TN/eioC/i.	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Baimukhanova", "first_name": "Amina"}	2026-09-08 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	7895e227-7cba-58d0-835e-69c8af3fcc63	authenticated	authenticated	a_seitkali@mnu.kz	$2a$10$VjUW7ZJcLZ8HPmoE0Zpmb.dppLMJ5Vk6h./yUhK6hJSGoxTfJsQAm	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Seitkali", "first_name": "Aigerim"}	2026-08-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	d723f696-83df-5e2e-9b66-1b6668a5bffb	authenticated	authenticated	i_amanova@mnu.kz	$2a$10$m.iGKCWWeIf3goOaF7NwK.a.SzrAhgUacaNG0No8fwfp2tVSMc8L.	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Amanova", "first_name": "Inkar"}	2026-08-23 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	511cedf2-bc02-56a1-a754-2540298f5cee	authenticated	authenticated	i_abenova@mnu.kz	$2a$10$4vOgM3OVbdZTnlM6VYCYz.uKHugsskOvXJytBBj9J/Q15zjtcNNKC	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Abenova", "first_name": "Inkar"}	2026-08-25 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	12dc5f6c-cb16-5110-abfa-a398961b181a	authenticated	authenticated	a_zhumabekov@mnu.kz	$2a$10$Q0GDKliTeSyOW4D.WmGOtOh449QkdAdVGFkvR8VDcXoG9ioxs5OLm	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Zhumabekov", "first_name": "Alikhan"}	2026-09-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	301d506e-f995-5472-824e-7223eea34b29	authenticated	authenticated	a_kairatov@mnu.kz	$2a$10$qdFkQCuZNF7Yb7WkNPMySOPnusyQv6sp2y98azrqR5/VtNPBsKjBS	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kairatov", "first_name": "Adil"}	2026-08-29 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	7caf10cc-bc08-579a-befd-dfa14a46a71b	authenticated	authenticated	a_zhakupova@mnu.kz	$2a$10$eCzXeCSC1MGIl5p/9WnlNeBmvvqwJizEpy/ZqyZ4fNEmSR.5kJjHy	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Zhakupova", "first_name": "Asel"}	2026-08-20 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	55d7564d-881c-5453-8a12-ea7124e538f0	authenticated	authenticated	admin@enu.kz	$2a$10$jX53fl959Pw8EY0WlFsTG.MF1Ynvi8kbg.AG7.2UIvr5jZiZR4VZ6	2026-10-11 17:54:36.817683+00	{"role": "admin", "provider": "email", "providers": ["email"]}	{"last_name": "ENU", "first_name": "Admin"}	2026-09-05 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	a1aba091-ac3f-5cfb-8f0e-025ddbe56044	authenticated	authenticated	kairatov.n@enu.kz	$2a$10$V.DtdPGPSxU6ME35SpDia.BOFxOj/kSD6Fi2MznMhgw.mVXj1jZni	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kairatov", "first_name": "Nurlan"}	2026-08-28 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	37dd3141-05ee-5e5d-a4f2-fb04179e158b	authenticated	authenticated	serikbayeva.m@enu.kz	$2a$10$8xlkOzFIcF1tPrKC1IVnS.8yWwVpJ0CW5I/atP7R4NmupKVhL4Dpa	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Serikbayeva", "first_name": "Malika"}	2026-09-03 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	1686e8b7-7ab0-56f5-894c-17df38559d0b	authenticated	authenticated	omarova.z@enu.kz	$2a$10$S4wm5I.XKIWjHArBgidNjukTp6bU5vfH1A1SVORL5LTnSANhz9/7y	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Omarova", "first_name": "Zhanel"}	2026-08-30 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	authenticated	authenticated	zhumabekov.o@enu.kz	$2a$10$QHN/gV2ZYE8Bo9/kav6t3e87l4x4gBqQEKk2rrzBuT5WxW40XGTWO	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Zhumabekov", "first_name": "Olzhas"}	2026-09-18 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	e57e4f91-200d-5996-8f1f-c4140498ccb5	authenticated	authenticated	yesenov.s@enu.kz	$2a$10$0nOASV0Zll03SZOB7Tv/aOFEKi9fjxtDjdFaagaFY0QRYo9FRUl1y	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Yesenov", "first_name": "Sanzhar"}	2026-08-25 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	47ac5cee-f468-5dd9-bd2f-994a2e1556fe	authenticated	authenticated	iskakov.m@enu.kz	$2a$10$8ZVX.UlHOY8f9XKLXEOtCuykJP23mDOqmDkg91zUTOPwRwxvy05R6	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Iskakov", "first_name": "Maksat"}	2026-09-20 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	333281b0-ea48-5904-bc0d-1baecafb3642	authenticated	authenticated	serikbayev.y@enu.kz	$2a$10$IwSn57ipI36RRdSvxW0fk.Vdj0gOnE2.bzMqjCIYMOoYFgE1m.q3W	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Serikbayev", "first_name": "Yersultan"}	2026-09-03 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	0714361c-2671-547c-a5e8-7412dd5f5bb2	authenticated	authenticated	rakhimova.d@enu.kz	$2a$10$O3hmjl/ZFuPD2h.9KbRFSe/YtrOTT/INbSmArJoGDgrhUUp0cuPBa	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Rakhimova", "first_name": "Dariga"}	2026-08-31 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	91665b25-1a02-5391-be1f-630466bf5a2f	authenticated	authenticated	ismailova.a@enu.kz	$2a$10$SidYspX9iH9Sg2WlnYQn5ea9F85cs0ZvwUB1beu866.Eq0IJhkYD6	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Ismailova", "first_name": "Aigerim"}	2026-09-03 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	f036e23d-5323-5b4f-bb1c-6e87c77bff75	authenticated	authenticated	seitkali.e@enu.kz	$2a$10$F8mfgAKJpi3TAXhGxR4ISuRZG/ZeKnfJgfUBJ2pWsry/TSeh5kpZe	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Seitkali", "first_name": "Ernar"}	2026-09-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	ce4654ab-6f97-5ba5-8e75-a674b62406d8	authenticated	authenticated	amanova.k@enu.kz	$2a$10$/HOVAONLpPpqvV8J396nMennJpd/rTGj5HOObwHz/sJDYp9od8ESe	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Amanova", "first_name": "Kamila"}	2026-09-02 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	5ab878f5-0da1-5a83-9dd1-f19a741d738e	authenticated	authenticated	seitkali.a@enu.kz	$2a$10$pENEq96lYYmeYNAxVsLls.XOI9ub9dvt9mZu/NfHW.yB5P2yvFTt6	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Seitkali", "first_name": "Arman"}	2026-08-26 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	af37d114-6cbb-5069-9e3e-89e207493efa	authenticated	authenticated	seitkali.z@enu.kz	$2a$10$O5iDQUZf1S6EaLrdK4Acuuvmt2ORHfcRKJen2R3YCsWUPdh0tUJuq	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Seitkali", "first_name": "Zarina"}	2026-09-01 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	7e59a7bf-1599-5d03-870a-b80f4a201398	authenticated	authenticated	amanova.a@enu.kz	$2a$10$ZUXEiA5kMFJtDkR7HinRtOeJI0h5eomI3fFUef4BbiEuLaMQKyie2	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Amanova", "first_name": "Akbota"}	2026-08-15 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	e2b516de-c76c-532d-8e53-5d02edbfa4ec	authenticated	authenticated	utepova.k@enu.kz	$2a$10$V7uA5Is5sjXj6Nd8LIOtIuEwMhWpi9P8l3Eom0CCU4fT/yPor8K5i	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Utepova", "first_name": "Kamila"}	2026-09-20 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	bed83121-8bf1-5da8-b173-e725dd4e2e71	authenticated	authenticated	omarov.a@enu.kz	$2a$10$GVCPbO32/8rmkp.TEcjO8.TNI3HtsqCMzTAu4iaAtFUCQmv0kl.ru	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Omarov", "first_name": "Alikhan"}	2026-08-18 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	d798b580-e0a7-5aa0-b42b-c9509861df97	authenticated	authenticated	bekov.t@enu.kz	$2a$10$gBPpoIcShaJ4AwqxxJrPe.feSQc6yHh6qwapS2j4olZbmFrpyDcx2	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Bekov", "first_name": "Timur"}	2026-08-31 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	1e821e58-daac-52d8-9ff6-668fa3f23828	authenticated	authenticated	omarov.t@enu.kz	$2a$10$OWHd7C2/LrKkQsKI582jzuuEn6JpBvNiDyFIOQhAKnmOt99OgeVX2	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Omarov", "first_name": "Timur"}	2026-09-09 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	authenticated	authenticated	rakhimova.z@enu.kz	$2a$10$zMh8RaCLLV55oiTC/Su5jequuyuTDtXoGaUfFFjSAvoUc9DO7KPq.	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Rakhimova", "first_name": "Zhanel"}	2026-08-17 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	ccd0071a-1fd0-5515-a5b8-937a6bb79b26	authenticated	authenticated	baimukhanov.a@enu.kz	$2a$10$R95goqmAGYV5FN.beFFBGuI.HkXjmDfO2ylVBrmUOL9b80BlXWJMe	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Baimukhanov", "first_name": "Arman"}	2026-09-18 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	d52c4849-0424-556a-909f-dc1685c34ca7	authenticated	authenticated	yesenov.m@enu.kz	$2a$10$qKZd7CPdp60DYc/sunYC0O7cHNGnQf.2eJzjf4eYknU4x6RVuP/Qu	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Yesenov", "first_name": "Miras"}	2026-09-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	fd594592-8d60-5f8c-be18-349a233ea712	authenticated	authenticated	yesenova.z@enu.kz	$2a$10$sPJIz4X9Ox892va.ncZ58u4qEqaosj9oasGmZ/YRw.Oh7ygA0qa1y	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Yesenova", "first_name": "Zarina"}	2026-09-11 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	3cfd1e72-fe25-526e-abce-f5c282026b57	authenticated	authenticated	baimukhanov.d@enu.kz	$2a$10$X0x0zsDc68pk8ce0Mry3buSRV8SC27rxD/94HrEzYhCLkJmgu5qnC	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Baimukhanov", "first_name": "Dias"}	2026-08-13 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	cd999017-1402-5a6e-b041-fdafc8ded0f0	authenticated	authenticated	kassymov.a@enu.kz	$2a$10$596.Twzx6KkEa./WxGwlAepWYHBNlU5yPOxqD9Ji4DJnLMD6byKLK	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kassymov", "first_name": "Adil"}	2026-09-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	4b052f0a-0cb1-59a1-912b-2786fdd40f68	authenticated	authenticated	kassymova.i@enu.kz	$2a$10$8PvgXgZDrfajWe3JaJ6HCeOJ/9pRuce6WdUk1Wf49epp8kn0vuYZ.	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kassymova", "first_name": "Inkar"}	2026-09-14 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	1c41b127-85d5-5028-9e30-ef9cea4990f8	authenticated	authenticated	kairatova.a@enu.kz	$2a$10$QAL9iQGC6Or0yAdv9DBpPuMQKJKJy6YxMx38qI4uTj/vZvuzk8eXy	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kairatova", "first_name": "Aisulu"}	2026-09-19 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	authenticated	authenticated	yesenov.n@enu.kz	$2a$10$2WEoqxKvcl9BQ4Xzf370FOh21hSIs5EGUYCpk2sf2wS/jRktPc63e	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Yesenov", "first_name": "Nurlan"}	2026-09-13 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	a3692637-7d1e-50da-b993-3a5d101307b0	authenticated	authenticated	kairatova.t@enu.kz	$2a$10$NidIxhSNrJYVapu81K18auJ/8sh80aozKoEAC421TYv0jbacv/Fq2	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Kairatova", "first_name": "Tomiris"}	2026-08-19 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
00000000-0000-0000-0000-000000000000	10cfe625-92d9-5f2d-8c28-3da5a44180d7	authenticated	authenticated	iskakov.a@enu.kz	$2a$10$dzYejZsEt4RqZj44HOy8HeYwWZRvri1qCrg9EVQJD92VwIKzpGjHO	2026-10-11 17:54:36.817683+00	{"provider": "email", "providers": ["email"]}	{"last_name": "Iskakov", "first_name": "Arman"}	2026-08-30 17:54:36.817683+00	2026-10-11 17:54:36.817683+00				
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_log (id, actor, action, table_name, record_id, details, created_at) FROM stdin;
\.


--
-- Data for Name: check_ins; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.check_ins (id, user_id, space_id, uses_outlet, started_at, expires_at, left_at) FROM stdin;
1	f131d105-108d-58b0-b737-aee95985fa93	14	t	2026-09-20 07:27:00+00	2026-09-20 09:27:00+00	2026-09-20 09:27:00+00
2	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	6	f	2026-09-16 06:08:00+00	2026-09-16 08:08:00+00	2026-09-16 07:52:00+00
3	ba12ad86-cec0-5c76-b72c-21e59427e8e5	12	t	2026-09-19 13:50:00+00	2026-09-19 15:50:00+00	2026-09-19 15:50:00+00
4	ba12ad86-cec0-5c76-b72c-21e59427e8e5	11	t	2026-09-25 15:08:00+00	2026-09-25 16:08:00+00	2026-09-25 16:03:00+00
5	cd999017-1402-5a6e-b041-fdafc8ded0f0	16	f	2026-09-14 07:40:00+00	2026-09-14 09:40:00+00	2026-09-14 09:40:00+00
6	75732734-f0dc-516b-ab8d-647bcd6f7210	11	f	2026-10-03 15:43:00+00	2026-10-03 17:43:00+00	2026-10-03 16:54:00+00
7	9bc90fbb-1ed4-5e71-a722-019e2cc44797	5	t	2026-09-15 12:21:00+00	2026-09-15 14:21:00+00	2026-09-15 14:21:00+00
8	ee4381b0-e713-5329-accc-f50e1a5ee4f6	14	f	2026-09-23 13:43:00+00	2026-09-23 15:43:00+00	2026-09-23 15:43:00+00
9	841aeb58-3431-5102-81be-941918ee4320	4	t	2026-09-25 14:52:00+00	2026-09-25 17:52:00+00	2026-09-25 15:56:00+00
10	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	8	t	2026-09-23 05:47:00+00	2026-09-23 06:47:00+00	2026-09-23 06:08:00+00
11	fd594592-8d60-5f8c-be18-349a233ea712	17	f	2026-09-13 07:02:00+00	2026-09-13 10:02:00+00	2026-09-13 10:02:00+00
12	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	12	f	2026-09-15 06:32:00+00	2026-09-15 07:32:00+00	2026-09-15 07:32:00+00
13	7f082d5c-a953-51d5-a623-9d610ae577ba	5	t	2026-09-23 04:37:00+00	2026-09-23 06:37:00+00	2026-09-23 06:37:00+00
14	ba12ad86-cec0-5c76-b72c-21e59427e8e5	11	f	2026-10-01 15:12:00+00	2026-10-01 16:12:00+00	2026-10-01 16:02:00+00
15	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	8	t	2026-09-15 12:56:00+00	2026-09-15 14:56:00+00	2026-09-15 13:19:00+00
16	ba12ad86-cec0-5c76-b72c-21e59427e8e5	10	t	2026-10-06 13:32:00+00	2026-10-06 14:32:00+00	2026-10-06 13:56:00+00
17	4375a7a0-75af-50b6-bf34-ac0b79555581	1	t	2026-09-23 10:08:00+00	2026-09-23 11:08:00+00	2026-09-23 10:59:00+00
18	d52c4849-0424-556a-909f-dc1685c34ca7	15	f	2026-09-17 07:19:00+00	2026-09-17 08:19:00+00	2026-09-17 08:19:00+00
19	bf1b1568-063d-5529-a346-27dcbdb160fc	2	t	2026-09-23 12:43:00+00	2026-09-23 15:43:00+00	2026-09-23 14:31:00+00
20	af37d114-6cbb-5069-9e3e-89e207493efa	18	t	2026-10-08 12:16:00+00	2026-10-08 14:16:00+00	2026-10-08 14:16:00+00
21	8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	11	t	2026-09-30 13:42:00+00	2026-09-30 16:42:00+00	2026-09-30 16:42:00+00
22	d798b580-e0a7-5aa0-b42b-c9509861df97	15	f	2026-09-26 11:22:00+00	2026-09-26 13:22:00+00	2026-09-26 13:22:00+00
23	2c6189e6-c56d-5f5e-90e4-3ffcdef88870	5	t	2026-10-04 11:42:00+00	2026-10-04 13:42:00+00	2026-10-04 13:42:00+00
24	bf1b1568-063d-5529-a346-27dcbdb160fc	1	t	2026-09-30 13:16:00+00	2026-09-30 15:16:00+00	2026-09-30 14:10:00+00
25	2667ad63-20cd-5653-af95-685a96aec1cb	3	t	2026-09-23 07:36:00+00	2026-09-23 10:36:00+00	2026-09-23 09:38:00+00
26	e57e4f91-200d-5996-8f1f-c4140498ccb5	17	t	2026-09-30 07:43:00+00	2026-09-30 10:43:00+00	2026-09-30 10:22:00+00
27	1625ce28-8df4-51c9-9370-e37f4726715d	7	f	2026-09-29 04:25:00+00	2026-09-29 06:25:00+00	2026-09-29 06:25:00+00
28	448fc3a2-4bb5-55c5-af6c-daa5b70403fc	6	t	2026-10-06 10:26:00+00	2026-10-06 13:26:00+00	2026-10-06 12:49:00+00
29	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	1	f	2026-09-16 05:54:00+00	2026-09-16 07:54:00+00	2026-09-16 07:54:00+00
30	e2b516de-c76c-532d-8e53-5d02edbfa4ec	16	t	2026-09-26 10:23:00+00	2026-09-26 11:23:00+00	2026-09-26 10:55:00+00
31	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	1	f	2026-10-07 15:29:00+00	2026-10-07 17:29:00+00	2026-10-07 16:10:00+00
32	594c5eb8-5eba-5db1-9527-7d409b4281ab	2	t	2026-09-22 09:37:00+00	2026-09-22 11:37:00+00	2026-09-22 11:37:00+00
33	8c6deb00-1371-546c-92a3-fa0544ab6f69	5	t	2026-10-09 11:14:00+00	2026-10-09 14:14:00+00	2026-10-09 13:01:00+00
34	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	6	t	2026-09-21 09:20:00+00	2026-09-21 11:20:00+00	2026-09-21 11:20:00+00
35	d6a0339c-e841-56e2-9be8-3c789fb9a47b	3	t	2026-09-25 07:48:00+00	2026-09-25 10:48:00+00	2026-09-25 10:48:00+00
36	0550482d-49c2-5f52-a61f-1c4badd27285	5	f	2026-10-01 04:26:00+00	2026-10-01 05:26:00+00	2026-10-01 05:18:00+00
37	5ab878f5-0da1-5a83-9dd1-f19a741d738e	15	t	2026-09-13 09:05:00+00	2026-09-13 11:05:00+00	2026-09-13 10:49:00+00
38	398c2e60-8a06-5f46-8fb0-e117c255ead8	4	t	2026-10-08 13:11:00+00	2026-10-08 15:11:00+00	2026-10-08 14:38:00+00
39	7cd65549-6305-538c-bfd9-ff7ee71213eb	5	t	2026-09-20 10:13:00+00	2026-09-20 11:13:00+00	2026-09-20 10:46:00+00
40	3cfd1e72-fe25-526e-abce-f5c282026b57	15	t	2026-09-24 06:55:00+00	2026-09-24 08:55:00+00	2026-09-24 08:46:00+00
41	8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	14	t	2026-09-19 07:41:00+00	2026-09-19 10:41:00+00	2026-09-19 10:19:00+00
42	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	13	f	2026-09-23 06:09:00+00	2026-09-23 08:09:00+00	2026-09-23 07:53:00+00
43	bed83121-8bf1-5da8-b173-e725dd4e2e71	18	f	2026-09-19 07:19:00+00	2026-09-19 09:19:00+00	2026-09-19 09:19:00+00
44	37dd3141-05ee-5e5d-a4f2-fb04179e158b	15	t	2026-09-29 06:44:00+00	2026-09-29 07:44:00+00	2026-09-29 07:13:00+00
45	b322d3fb-18a5-5119-abc3-151933818abd	14	t	2026-09-25 15:19:00+00	2026-09-25 17:19:00+00	2026-09-25 16:48:00+00
46	a1aba091-ac3f-5cfb-8f0e-025ddbe56044	16	t	2026-09-17 13:09:00+00	2026-09-17 14:09:00+00	2026-09-17 13:32:00+00
47	9630d339-6604-569b-85a5-534d3a118af7	13	t	2026-09-13 12:16:00+00	2026-09-13 14:16:00+00	2026-09-13 12:56:00+00
48	4b052f0a-0cb1-59a1-912b-2786fdd40f68	15	f	2026-09-14 11:12:00+00	2026-09-14 13:12:00+00	2026-09-14 13:12:00+00
49	b179af01-a01d-5d62-8805-310edc535f62	11	f	2026-10-04 09:55:00+00	2026-10-04 12:55:00+00	2026-10-04 12:12:00+00
50	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	18	f	2026-10-04 10:28:00+00	2026-10-04 13:28:00+00	2026-10-04 13:28:00+00
51	0714361c-2671-547c-a5e8-7412dd5f5bb2	15	t	2026-10-04 05:45:00+00	2026-10-04 07:45:00+00	2026-10-04 07:45:00+00
52	89b01325-f844-5951-8b97-722e76d10e26	9	f	2026-10-04 15:27:00+00	2026-10-04 16:27:00+00	2026-10-04 15:56:00+00
53	7895e227-7cba-58d0-835e-69c8af3fcc63	10	f	2026-09-15 11:25:00+00	2026-09-15 12:25:00+00	2026-09-15 12:14:00+00
54	d52c4849-0424-556a-909f-dc1685c34ca7	16	t	2026-09-29 05:50:00+00	2026-09-29 07:50:00+00	2026-09-29 06:55:00+00
55	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	12	t	2026-09-20 14:42:00+00	2026-09-20 16:42:00+00	2026-09-20 16:29:00+00
56	32f48806-1d58-5528-ac5f-f78d0f615e62	12	t	2026-09-29 12:52:00+00	2026-09-29 13:52:00+00	2026-09-29 13:30:00+00
57	9630d339-6604-569b-85a5-534d3a118af7	10	f	2026-10-09 14:36:00+00	2026-10-09 15:36:00+00	2026-10-09 15:36:00+00
58	8557a85b-2ada-524a-9191-e5c392f2ecd0	12	t	2026-09-26 09:09:00+00	2026-09-26 11:09:00+00	2026-09-26 11:09:00+00
59	a6a72968-235d-553f-84a7-223f70ff71da	2	t	2026-10-05 07:02:00+00	2026-10-05 08:02:00+00	2026-10-05 07:55:00+00
60	3cfd1e72-fe25-526e-abce-f5c282026b57	15	f	2026-09-12 06:30:00+00	2026-09-12 08:30:00+00	2026-09-12 08:30:00+00
61	37dd3141-05ee-5e5d-a4f2-fb04179e158b	16	t	2026-10-03 09:54:00+00	2026-10-03 11:54:00+00	2026-10-03 11:54:00+00
62	f131d105-108d-58b0-b737-aee95985fa93	11	t	2026-10-05 12:37:00+00	2026-10-05 15:37:00+00	2026-10-05 15:00:00+00
63	7cd65549-6305-538c-bfd9-ff7ee71213eb	5	t	2026-09-17 09:08:00+00	2026-09-17 11:08:00+00	2026-09-17 11:08:00+00
64	7106add8-93da-510c-a2ee-43f512e49d3c	6	t	2026-09-16 11:01:00+00	2026-09-16 13:01:00+00	2026-09-16 12:27:00+00
65	3ce15b25-c6e0-583d-a872-0dc16ae45020	12	t	2026-10-07 12:37:00+00	2026-10-07 13:37:00+00	2026-10-07 13:26:00+00
66	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	1	t	2026-09-15 16:25:00+00	2026-09-15 17:25:00+00	2026-09-15 17:25:00+00
67	f036e23d-5323-5b4f-bb1c-6e87c77bff75	15	f	2026-09-15 07:23:00+00	2026-09-15 08:23:00+00	2026-09-15 08:23:00+00
68	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	3	f	2026-10-04 10:45:00+00	2026-10-04 11:45:00+00	2026-10-04 11:40:00+00
69	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	9	f	2026-09-12 11:53:00+00	2026-09-12 12:53:00+00	2026-09-12 12:25:00+00
70	4aed59c4-076a-58ea-8df4-eee688fc3b38	10	t	2026-10-09 06:04:00+00	2026-10-09 08:04:00+00	2026-10-09 08:04:00+00
71	d723f696-83df-5e2e-9b66-1b6668a5bffb	11	f	2026-10-09 07:56:00+00	2026-10-09 09:56:00+00	2026-10-09 09:22:00+00
72	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	8	t	2026-09-25 09:14:00+00	2026-09-25 12:14:00+00	2026-09-25 10:36:00+00
73	49226873-bb4d-5af8-b6d7-b618b6111788	7	t	2026-09-28 08:39:00+00	2026-09-28 10:39:00+00	2026-09-28 10:39:00+00
74	b4455c9f-c726-58c4-a73d-dc7ac20b4280	3	t	2026-09-24 08:41:00+00	2026-09-24 10:41:00+00	2026-09-24 09:03:00+00
75	91665b25-1a02-5391-be1f-630466bf5a2f	15	f	2026-09-16 14:55:00+00	2026-09-16 16:55:00+00	2026-09-16 16:15:00+00
76	841aeb58-3431-5102-81be-941918ee4320	3	f	2026-09-19 06:35:00+00	2026-09-19 07:35:00+00	2026-09-19 07:35:00+00
77	a6a72968-235d-553f-84a7-223f70ff71da	2	t	2026-09-18 08:36:00+00	2026-09-18 10:36:00+00	2026-09-18 09:41:00+00
78	a1aba091-ac3f-5cfb-8f0e-025ddbe56044	15	f	2026-09-22 07:07:00+00	2026-09-22 10:07:00+00	2026-09-22 08:44:00+00
79	8557a85b-2ada-524a-9191-e5c392f2ecd0	14	f	2026-09-19 06:47:00+00	2026-09-19 07:47:00+00	2026-09-19 07:28:00+00
80	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	2	f	2026-09-18 05:42:00+00	2026-09-18 08:42:00+00	2026-09-18 06:42:00+00
81	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	12	t	2026-09-11 05:08:00+00	2026-09-11 06:08:00+00	2026-09-11 05:47:00+00
82	448fc3a2-4bb5-55c5-af6c-daa5b70403fc	6	t	2026-10-10 07:09:00+00	2026-10-10 10:09:00+00	2026-10-10 07:30:00+00
83	bf1b1568-063d-5529-a346-27dcbdb160fc	1	t	2026-10-07 07:51:00+00	2026-10-07 08:51:00+00	2026-10-07 08:28:00+00
84	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	9	f	2026-09-17 07:28:00+00	2026-09-17 10:28:00+00	2026-09-17 09:08:00+00
85	daecc825-1e7a-51cd-a171-4a41488773ae	2	f	2026-09-21 06:44:00+00	2026-09-21 08:44:00+00	2026-09-21 08:41:00+00
86	e1f7cb84-a272-5286-8d3b-6004b94c9fea	3	t	2026-09-13 07:51:00+00	2026-09-13 08:51:00+00	2026-09-13 08:51:00+00
87	7f082d5c-a953-51d5-a623-9d610ae577ba	7	f	2026-09-20 06:35:00+00	2026-09-20 08:35:00+00	2026-09-20 08:03:00+00
88	37dd3141-05ee-5e5d-a4f2-fb04179e158b	15	f	2026-10-02 14:15:00+00	2026-10-02 16:15:00+00	2026-10-02 14:39:00+00
89	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	15	t	2026-10-04 13:42:00+00	2026-10-04 15:42:00+00	2026-10-04 15:42:00+00
90	b179af01-a01d-5d62-8805-310edc535f62	10	t	2026-09-19 07:02:00+00	2026-09-19 09:02:00+00	2026-09-19 08:14:00+00
91	37dd3141-05ee-5e5d-a4f2-fb04179e158b	18	t	2026-09-20 13:32:00+00	2026-09-20 15:32:00+00	2026-09-20 15:10:00+00
92	ccd0071a-1fd0-5515-a5b8-937a6bb79b26	18	f	2026-09-29 09:00:00+00	2026-09-29 12:00:00+00	2026-09-29 10:59:00+00
93	9bc90fbb-1ed4-5e71-a722-019e2cc44797	9	f	2026-09-13 07:37:00+00	2026-09-13 10:37:00+00	2026-09-13 10:37:00+00
94	4b052f0a-0cb1-59a1-912b-2786fdd40f68	15	t	2026-10-10 06:31:00+00	2026-10-10 09:31:00+00	2026-10-10 07:31:00+00
95	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	1	t	2026-09-29 05:06:00+00	2026-09-29 06:06:00+00	2026-09-29 06:06:00+00
96	f131d105-108d-58b0-b737-aee95985fa93	12	t	2026-09-29 16:40:00+00	2026-09-29 17:40:00+00	2026-09-29 17:40:00+00
97	a3692637-7d1e-50da-b993-3a5d101307b0	15	t	2026-10-10 04:21:00+00	2026-10-10 06:21:00+00	2026-10-10 05:33:00+00
98	daecc825-1e7a-51cd-a171-4a41488773ae	3	t	2026-09-14 13:35:00+00	2026-09-14 16:35:00+00	2026-09-14 16:35:00+00
99	a6a72968-235d-553f-84a7-223f70ff71da	1	f	2026-09-29 08:54:00+00	2026-09-29 09:54:00+00	2026-09-29 09:49:00+00
100	1625ce28-8df4-51c9-9370-e37f4726715d	9	f	2026-09-16 05:43:00+00	2026-09-16 08:43:00+00	2026-09-16 08:43:00+00
101	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	5	t	2026-09-25 09:47:00+00	2026-09-25 10:47:00+00	2026-09-25 10:33:00+00
102	7895e227-7cba-58d0-835e-69c8af3fcc63	10	f	2026-10-08 09:15:00+00	2026-10-08 12:15:00+00	2026-10-08 12:15:00+00
103	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	1	f	2026-09-13 10:19:00+00	2026-09-13 12:19:00+00	2026-09-13 11:34:00+00
104	9bc90fbb-1ed4-5e71-a722-019e2cc44797	8	t	2026-09-11 08:40:00+00	2026-09-11 09:40:00+00	2026-09-11 09:39:00+00
105	1625ce28-8df4-51c9-9370-e37f4726715d	7	t	2026-09-13 10:14:00+00	2026-09-13 12:14:00+00	2026-09-13 11:06:00+00
106	efd23983-5f8f-5e47-bba6-22cfcef33110	12	f	2026-10-02 07:47:00+00	2026-10-02 09:47:00+00	2026-10-02 09:47:00+00
107	333281b0-ea48-5904-bc0d-1baecafb3642	16	t	2026-09-22 08:33:00+00	2026-09-22 10:33:00+00	2026-09-22 09:32:00+00
108	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	10	f	2026-10-03 06:38:00+00	2026-10-03 08:38:00+00	2026-10-03 08:31:00+00
109	7895e227-7cba-58d0-835e-69c8af3fcc63	12	f	2026-10-07 08:27:00+00	2026-10-07 11:27:00+00	2026-10-07 09:14:00+00
110	89b01325-f844-5951-8b97-722e76d10e26	8	f	2026-09-16 10:36:00+00	2026-09-16 13:36:00+00	2026-09-16 13:36:00+00
111	60c1d1fe-9756-50b7-aa0c-8938baaddde2	5	t	2026-09-15 09:23:00+00	2026-09-15 12:23:00+00	2026-09-15 12:17:00+00
112	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	16	t	2026-10-01 09:03:00+00	2026-10-01 10:03:00+00	2026-10-01 09:50:00+00
113	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	8	t	2026-09-11 11:00:00+00	2026-09-11 13:00:00+00	2026-09-11 13:00:00+00
114	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	3	f	2026-10-09 14:39:00+00	2026-10-09 17:39:00+00	2026-10-09 17:39:00+00
115	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	12	f	2026-09-20 07:06:00+00	2026-09-20 10:06:00+00	2026-09-20 10:06:00+00
116	289a1a72-f5c0-5531-a5a2-1431eae3980d	1	t	2026-09-11 12:37:00+00	2026-09-11 15:37:00+00	2026-09-11 15:37:00+00
117	ccd0071a-1fd0-5515-a5b8-937a6bb79b26	17	t	2026-09-23 11:55:00+00	2026-09-23 13:55:00+00	2026-09-23 13:55:00+00
118	7caf10cc-bc08-579a-befd-dfa14a46a71b	14	t	2026-09-14 06:03:00+00	2026-09-14 09:03:00+00	2026-09-14 09:03:00+00
119	cd609af0-f2d9-5556-9083-47c78c3e1318	12	f	2026-10-05 11:04:00+00	2026-10-05 14:04:00+00	2026-10-05 13:09:00+00
120	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	7	t	2026-09-20 12:18:00+00	2026-09-20 13:18:00+00	2026-09-20 13:05:00+00
121	0714361c-2671-547c-a5e8-7412dd5f5bb2	16	t	2026-09-26 06:20:00+00	2026-09-26 08:20:00+00	2026-09-26 08:08:00+00
122	6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	15	t	2026-10-07 08:23:00+00	2026-10-07 11:23:00+00	2026-10-07 08:45:00+00
123	301d506e-f995-5472-824e-7223eea34b29	10	t	2026-10-08 06:21:00+00	2026-10-08 08:21:00+00	2026-10-08 08:21:00+00
124	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	2	t	2026-09-14 11:29:00+00	2026-09-14 13:29:00+00	2026-09-14 12:06:00+00
125	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	1	t	2026-09-23 05:16:00+00	2026-09-23 08:16:00+00	2026-09-23 08:16:00+00
126	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	2	f	2026-09-29 14:38:00+00	2026-09-29 16:38:00+00	2026-09-29 15:34:00+00
127	bed83121-8bf1-5da8-b173-e725dd4e2e71	15	f	2026-09-23 09:54:00+00	2026-09-23 11:54:00+00	2026-09-23 11:14:00+00
128	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	1	t	2026-09-11 07:25:00+00	2026-09-11 08:25:00+00	2026-09-11 08:25:00+00
129	8c6deb00-1371-546c-92a3-fa0544ab6f69	6	f	2026-10-08 07:08:00+00	2026-10-08 08:08:00+00	2026-10-08 07:46:00+00
130	a6a72968-235d-553f-84a7-223f70ff71da	1	t	2026-09-12 06:34:00+00	2026-09-12 07:34:00+00	2026-09-12 07:34:00+00
131	0631a63b-ebc2-5785-a739-9fee4b48e5bc	3	f	2026-09-20 05:31:00+00	2026-09-20 08:31:00+00	2026-09-20 08:09:00+00
132	e1f7cb84-a272-5286-8d3b-6004b94c9fea	1	f	2026-10-09 11:45:00+00	2026-10-09 14:45:00+00	2026-10-09 14:10:00+00
133	123a74f4-143d-5603-81d5-6331401ea569	3	t	2026-09-20 13:12:00+00	2026-09-20 15:12:00+00	2026-09-20 14:39:00+00
134	0550482d-49c2-5f52-a61f-1c4badd27285	8	f	2026-09-23 05:41:00+00	2026-09-23 06:41:00+00	2026-09-23 06:41:00+00
135	ad5b5e1b-07b1-5134-ae83-b16af18abe40	3	f	2026-09-20 09:55:00+00	2026-09-20 12:55:00+00	2026-09-20 12:55:00+00
136	d723f696-83df-5e2e-9b66-1b6668a5bffb	11	f	2026-09-13 05:07:00+00	2026-09-13 07:07:00+00	2026-09-13 07:07:00+00
137	c25c9587-af2d-50a5-9cbc-1fdf3302f483	6	t	2026-10-04 11:07:00+00	2026-10-04 12:07:00+00	2026-10-04 12:00:00+00
138	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	4	t	2026-09-28 14:08:00+00	2026-09-28 16:08:00+00	2026-09-28 15:06:00+00
139	f036e23d-5323-5b4f-bb1c-6e87c77bff75	15	t	2026-09-27 12:35:00+00	2026-09-27 15:35:00+00	2026-09-27 15:35:00+00
140	fd594592-8d60-5f8c-be18-349a233ea712	18	t	2026-09-29 10:47:00+00	2026-09-29 13:47:00+00	2026-09-29 13:47:00+00
141	e57e4f91-200d-5996-8f1f-c4140498ccb5	17	f	2026-10-03 12:54:00+00	2026-10-03 14:54:00+00	2026-10-03 13:38:00+00
142	ee4381b0-e713-5329-accc-f50e1a5ee4f6	10	f	2026-10-05 12:59:00+00	2026-10-05 14:59:00+00	2026-10-05 14:18:00+00
143	bb9f8bce-5de6-54be-a471-3c22fff845f5	3	t	2026-10-02 11:52:00+00	2026-10-02 13:52:00+00	2026-10-02 13:32:00+00
144	ccd0071a-1fd0-5515-a5b8-937a6bb79b26	18	t	2026-09-12 07:51:00+00	2026-09-12 08:51:00+00	2026-09-12 08:44:00+00
145	91665b25-1a02-5391-be1f-630466bf5a2f	16	t	2026-09-30 05:43:00+00	2026-09-30 07:43:00+00	2026-09-30 07:43:00+00
146	cd999017-1402-5a6e-b041-fdafc8ded0f0	15	f	2026-10-06 07:36:00+00	2026-10-06 09:36:00+00	2026-10-06 08:29:00+00
147	7106add8-93da-510c-a2ee-43f512e49d3c	8	t	2026-10-10 14:36:00+00	2026-10-10 16:36:00+00	2026-10-10 15:31:00+00
148	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	13	t	2026-09-16 11:49:00+00	2026-09-16 13:49:00+00	2026-09-16 13:49:00+00
149	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	2	f	2026-10-05 05:23:00+00	2026-10-05 08:23:00+00	2026-10-05 05:44:00+00
150	44a51247-0f45-5096-9fca-81ed70346a12	1	t	2026-10-08 03:45:00+00	2026-10-08 04:45:00+00	2026-10-08 04:45:00+00
151	ad5b5e1b-07b1-5134-ae83-b16af18abe40	1	f	2026-09-16 14:28:00+00	2026-09-16 15:28:00+00	2026-09-16 15:28:00+00
152	b4455c9f-c726-58c4-a73d-dc7ac20b4280	1	f	2026-10-03 09:12:00+00	2026-10-03 10:12:00+00	2026-10-03 10:12:00+00
153	4aed59c4-076a-58ea-8df4-eee688fc3b38	13	f	2026-09-26 11:06:00+00	2026-09-26 14:06:00+00	2026-09-26 13:08:00+00
154	a3692637-7d1e-50da-b993-3a5d101307b0	15	t	2026-10-07 06:05:00+00	2026-10-07 07:05:00+00	2026-10-07 07:05:00+00
155	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	14	f	2026-10-03 04:19:00+00	2026-10-03 05:19:00+00	2026-10-03 04:39:00+00
156	3c16f96c-897e-5713-b4ce-ffc817887105	6	f	2026-10-05 11:05:00+00	2026-10-05 14:05:00+00	2026-10-05 12:51:00+00
157	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	3	t	2026-09-14 14:05:00+00	2026-09-14 16:05:00+00	2026-09-14 16:05:00+00
158	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	18	f	2026-10-08 12:55:00+00	2026-10-08 15:55:00+00	2026-10-08 14:41:00+00
159	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	10	t	2026-09-17 11:10:00+00	2026-09-17 13:10:00+00	2026-09-17 12:35:00+00
160	1c41b127-85d5-5028-9e30-ef9cea4990f8	15	f	2026-09-12 09:53:00+00	2026-09-12 11:53:00+00	2026-09-12 11:40:00+00
161	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	10	f	2026-09-27 10:07:00+00	2026-09-27 12:07:00+00	2026-09-27 11:43:00+00
162	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	9	t	2026-09-25 11:30:00+00	2026-09-25 13:30:00+00	2026-09-25 13:30:00+00
163	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	6	t	2026-10-09 15:14:00+00	2026-10-09 17:14:00+00	2026-10-09 17:14:00+00
164	7e59a7bf-1599-5d03-870a-b80f4a201398	16	t	2026-09-14 16:52:00+00	2026-09-14 18:52:00+00	2026-09-14 17:37:00+00
165	47ac5cee-f468-5dd9-bd2f-994a2e1556fe	15	t	2026-10-08 05:57:00+00	2026-10-08 07:57:00+00	2026-10-08 07:57:00+00
166	91665b25-1a02-5391-be1f-630466bf5a2f	15	f	2026-09-27 06:51:00+00	2026-09-27 08:51:00+00	2026-09-27 08:35:00+00
167	e2b516de-c76c-532d-8e53-5d02edbfa4ec	15	t	2026-10-05 11:45:00+00	2026-10-05 13:45:00+00	2026-10-05 12:44:00+00
168	841aeb58-3431-5102-81be-941918ee4320	3	f	2026-10-10 05:10:00+00	2026-10-10 07:10:00+00	2026-10-10 06:58:00+00
169	7e59a7bf-1599-5d03-870a-b80f4a201398	17	t	2026-09-12 10:44:00+00	2026-09-12 12:44:00+00	2026-09-12 12:44:00+00
170	d723f696-83df-5e2e-9b66-1b6668a5bffb	12	t	2026-10-07 09:42:00+00	2026-10-07 12:42:00+00	2026-10-07 12:42:00+00
171	bf1b1568-063d-5529-a346-27dcbdb160fc	4	f	2026-09-26 04:06:00+00	2026-09-26 06:06:00+00	2026-09-26 06:06:00+00
172	2614e032-72f6-5f47-b46b-2b6fa25f275a	5	f	2026-09-13 10:56:00+00	2026-09-13 13:56:00+00	2026-09-13 12:05:00+00
173	45667a63-75a2-5327-80b3-07277bbc3a05	14	t	2026-09-24 12:58:00+00	2026-09-24 15:58:00+00	2026-09-24 15:58:00+00
174	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	10	t	2026-10-06 13:25:00+00	2026-10-06 14:25:00+00	2026-10-06 14:25:00+00
175	60c1d1fe-9756-50b7-aa0c-8938baaddde2	5	t	2026-09-28 04:10:00+00	2026-09-28 06:10:00+00	2026-09-28 06:10:00+00
176	ce4654ab-6f97-5ba5-8e75-a674b62406d8	16	t	2026-09-18 10:21:00+00	2026-09-18 12:21:00+00	2026-09-18 12:21:00+00
177	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	6	f	2026-09-16 07:20:00+00	2026-09-16 08:20:00+00	2026-09-16 08:20:00+00
178	91665b25-1a02-5391-be1f-630466bf5a2f	15	f	2026-09-29 11:51:00+00	2026-09-29 12:51:00+00	2026-09-29 12:51:00+00
179	47ac5cee-f468-5dd9-bd2f-994a2e1556fe	18	f	2026-09-25 11:58:00+00	2026-09-25 14:58:00+00	2026-09-25 14:58:00+00
180	813640c1-13d1-52ed-b333-486966e596de	4	t	2026-09-16 07:15:00+00	2026-09-16 09:15:00+00	2026-09-16 09:15:00+00
181	9bc90fbb-1ed4-5e71-a722-019e2cc44797	7	t	2026-10-09 09:26:00+00	2026-10-09 10:26:00+00	2026-10-09 10:06:00+00
182	daecc825-1e7a-51cd-a171-4a41488773ae	1	t	2026-09-28 06:40:00+00	2026-09-28 07:40:00+00	2026-09-28 07:40:00+00
183	bc586d94-7153-5cf0-8676-68bcb94a0d5a	1	t	2026-10-07 06:23:00+00	2026-10-07 07:23:00+00	2026-10-07 07:23:00+00
184	c39ee07c-08d3-51a9-8933-c3f20abe6a2d	3	f	2026-09-21 12:51:00+00	2026-09-21 14:51:00+00	2026-09-21 14:51:00+00
185	cd999017-1402-5a6e-b041-fdafc8ded0f0	15	f	2026-09-24 06:32:00+00	2026-09-24 09:32:00+00	2026-09-24 07:08:00+00
186	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	5	f	2026-09-15 05:46:00+00	2026-09-15 07:46:00+00	2026-09-15 07:46:00+00
187	1686e8b7-7ab0-56f5-894c-17df38559d0b	18	f	2026-09-15 13:44:00+00	2026-09-15 16:44:00+00	2026-09-15 16:44:00+00
188	e2b516de-c76c-532d-8e53-5d02edbfa4ec	16	f	2026-09-23 08:18:00+00	2026-09-23 09:18:00+00	2026-09-23 09:18:00+00
189	18e969e2-d4e6-52f4-8e81-e62265f128f5	6	f	2026-09-14 11:18:00+00	2026-09-14 13:18:00+00	2026-09-14 13:18:00+00
190	89b01325-f844-5951-8b97-722e76d10e26	8	f	2026-10-02 04:45:00+00	2026-10-02 06:45:00+00	2026-10-02 06:25:00+00
191	3c16f96c-897e-5713-b4ce-ffc817887105	8	f	2026-10-02 09:25:00+00	2026-10-02 10:25:00+00	2026-10-02 10:25:00+00
192	91665b25-1a02-5391-be1f-630466bf5a2f	15	t	2026-09-26 10:25:00+00	2026-09-26 11:25:00+00	2026-09-26 11:06:00+00
193	8557a85b-2ada-524a-9191-e5c392f2ecd0	11	t	2026-09-28 09:36:00+00	2026-09-28 12:36:00+00	2026-09-28 12:36:00+00
194	1686e8b7-7ab0-56f5-894c-17df38559d0b	15	f	2026-10-03 09:59:00+00	2026-10-03 11:59:00+00	2026-10-03 11:59:00+00
195	32f48806-1d58-5528-ac5f-f78d0f615e62	10	t	2026-10-07 11:38:00+00	2026-10-07 14:38:00+00	2026-10-07 14:38:00+00
196	ccd0071a-1fd0-5515-a5b8-937a6bb79b26	15	t	2026-09-21 12:56:00+00	2026-09-21 14:56:00+00	2026-09-21 13:19:00+00
197	ba12ad86-cec0-5c76-b72c-21e59427e8e5	14	f	2026-10-03 14:52:00+00	2026-10-03 17:52:00+00	2026-10-03 17:52:00+00
198	44a51247-0f45-5096-9fca-81ed70346a12	1	f	2026-09-25 09:24:00+00	2026-09-25 11:24:00+00	2026-09-25 11:24:00+00
199	ba12ad86-cec0-5c76-b72c-21e59427e8e5	12	f	2026-10-09 09:02:00+00	2026-10-09 11:02:00+00	2026-10-09 09:43:00+00
200	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	3	f	2026-09-22 13:26:00+00	2026-09-22 15:26:00+00	2026-09-22 15:26:00+00
201	e57e4f91-200d-5996-8f1f-c4140498ccb5	16	t	2026-09-21 05:01:00+00	2026-09-21 08:01:00+00	2026-09-21 08:01:00+00
202	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	2	f	2026-09-16 05:54:00+00	2026-09-16 06:54:00+00	2026-09-16 06:15:00+00
203	75732734-f0dc-516b-ab8d-647bcd6f7210	14	f	2026-09-11 15:09:00+00	2026-09-11 17:09:00+00	2026-09-11 17:09:00+00
204	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	10	t	2026-10-06 08:51:00+00	2026-10-06 10:51:00+00	2026-10-06 10:51:00+00
205	289a1a72-f5c0-5531-a5a2-1431eae3980d	2	t	2026-09-13 08:27:00+00	2026-09-13 11:27:00+00	2026-09-13 11:27:00+00
206	22177d59-b6dd-5230-ad3a-3f20a82c77be	2	t	2026-10-07 09:28:00+00	2026-10-07 12:28:00+00	2026-10-07 10:09:00+00
207	1686e8b7-7ab0-56f5-894c-17df38559d0b	18	f	2026-09-29 06:48:00+00	2026-09-29 08:48:00+00	2026-09-29 08:48:00+00
208	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	11	f	2026-09-19 05:22:00+00	2026-09-19 07:22:00+00	2026-09-19 07:22:00+00
209	8557a85b-2ada-524a-9191-e5c392f2ecd0	14	t	2026-10-09 06:04:00+00	2026-10-09 08:04:00+00	2026-10-09 07:54:00+00
210	8c6deb00-1371-546c-92a3-fa0544ab6f69	5	t	2026-09-22 13:29:00+00	2026-09-22 14:29:00+00	2026-09-22 14:29:00+00
211	5ab878f5-0da1-5a83-9dd1-f19a741d738e	15	f	2026-10-07 10:47:00+00	2026-10-07 13:47:00+00	2026-10-07 13:47:00+00
212	a3692637-7d1e-50da-b993-3a5d101307b0	15	t	2026-09-19 11:39:00+00	2026-09-19 13:39:00+00	2026-09-19 13:39:00+00
213	7e76cba5-592a-50a9-a6e4-fb36d39a9030	10	t	2026-10-01 08:20:00+00	2026-10-01 11:20:00+00	2026-10-01 09:28:00+00
214	7e76cba5-592a-50a9-a6e4-fb36d39a9030	11	f	2026-09-18 07:09:00+00	2026-09-18 10:09:00+00	2026-09-18 07:37:00+00
215	a3692637-7d1e-50da-b993-3a5d101307b0	15	t	2026-09-17 03:54:00+00	2026-09-17 04:54:00+00	2026-09-17 04:54:00+00
216	f036e23d-5323-5b4f-bb1c-6e87c77bff75	16	t	2026-10-01 12:36:00+00	2026-10-01 15:36:00+00	2026-10-01 15:12:00+00
217	0714361c-2671-547c-a5e8-7412dd5f5bb2	18	t	2026-09-16 04:40:00+00	2026-09-16 06:40:00+00	2026-09-16 05:41:00+00
218	18e969e2-d4e6-52f4-8e81-e62265f128f5	5	f	2026-09-23 03:13:00+00	2026-09-23 05:13:00+00	2026-09-23 05:13:00+00
219	1625ce28-8df4-51c9-9370-e37f4726715d	5	f	2026-10-09 11:35:00+00	2026-10-09 13:35:00+00	2026-10-09 13:00:00+00
220	5c29fc1f-628e-5bdc-9e83-3e576df263d4	1	f	2026-09-21 10:44:00+00	2026-09-21 13:44:00+00	2026-09-21 13:44:00+00
221	5c29fc1f-628e-5bdc-9e83-3e576df263d4	1	f	2026-10-09 11:58:00+00	2026-10-09 13:58:00+00	2026-10-09 12:54:00+00
222	3c16f96c-897e-5713-b4ce-ffc817887105	5	f	2026-09-28 05:22:00+00	2026-09-28 08:22:00+00	2026-09-28 08:22:00+00
223	b322d3fb-18a5-5119-abc3-151933818abd	12	f	2026-09-20 11:03:00+00	2026-09-20 13:03:00+00	2026-09-20 13:03:00+00
224	91665b25-1a02-5391-be1f-630466bf5a2f	18	f	2026-10-09 10:53:00+00	2026-10-09 12:53:00+00	2026-10-09 11:21:00+00
225	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	14	t	2026-09-21 11:18:00+00	2026-09-21 13:18:00+00	2026-09-21 13:18:00+00
226	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	5	f	2026-10-05 10:13:00+00	2026-10-05 13:13:00+00	2026-10-05 12:26:00+00
227	3cfd1e72-fe25-526e-abce-f5c282026b57	16	t	2026-10-07 07:18:00+00	2026-10-07 09:18:00+00	2026-10-07 09:18:00+00
228	10cfe625-92d9-5f2d-8c28-3da5a44180d7	16	t	2026-09-17 07:17:00+00	2026-09-17 08:17:00+00	2026-09-17 08:00:00+00
229	89b01325-f844-5951-8b97-722e76d10e26	8	f	2026-09-17 05:20:00+00	2026-09-17 07:20:00+00	2026-09-17 06:21:00+00
230	89b01325-f844-5951-8b97-722e76d10e26	9	f	2026-10-08 12:26:00+00	2026-10-08 14:26:00+00	2026-10-08 14:26:00+00
231	0550482d-49c2-5f52-a61f-1c4badd27285	5	f	2026-10-08 09:23:00+00	2026-10-08 10:23:00+00	2026-10-08 10:23:00+00
232	bc586d94-7153-5cf0-8676-68bcb94a0d5a	3	t	2026-09-27 10:34:00+00	2026-09-27 11:34:00+00	2026-09-27 11:07:00+00
233	32f48806-1d58-5528-ac5f-f78d0f615e62	14	t	2026-09-21 05:17:00+00	2026-09-21 07:17:00+00	2026-09-21 06:39:00+00
234	4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	6	t	2026-09-26 11:50:00+00	2026-09-26 14:50:00+00	2026-09-26 12:28:00+00
235	3c16f96c-897e-5713-b4ce-ffc817887105	8	f	2026-09-17 11:04:00+00	2026-09-17 14:04:00+00	2026-09-17 12:23:00+00
236	511cedf2-bc02-56a1-a754-2540298f5cee	10	t	2026-10-02 14:27:00+00	2026-10-02 16:27:00+00	2026-10-02 16:27:00+00
237	7106add8-93da-510c-a2ee-43f512e49d3c	8	t	2026-10-04 11:52:00+00	2026-10-04 13:52:00+00	2026-10-04 13:45:00+00
238	ce4654ab-6f97-5ba5-8e75-a674b62406d8	16	t	2026-10-07 11:59:00+00	2026-10-07 13:59:00+00	2026-10-07 13:59:00+00
239	b179af01-a01d-5d62-8805-310edc535f62	14	t	2026-10-06 07:24:00+00	2026-10-06 10:24:00+00	2026-10-06 10:24:00+00
240	2667ad63-20cd-5653-af95-685a96aec1cb	4	f	2026-09-12 06:53:00+00	2026-09-12 08:53:00+00	2026-09-12 07:29:00+00
241	7f082d5c-a953-51d5-a623-9d610ae577ba	7	f	2026-09-14 12:43:00+00	2026-09-14 14:43:00+00	2026-09-14 14:02:00+00
242	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	5	f	2026-09-23 09:33:00+00	2026-09-23 12:33:00+00	2026-09-23 12:19:00+00
243	0550482d-49c2-5f52-a61f-1c4badd27285	7	t	2026-09-16 09:29:00+00	2026-09-16 11:29:00+00	2026-09-16 11:29:00+00
244	1625ce28-8df4-51c9-9370-e37f4726715d	8	f	2026-10-10 08:48:00+00	2026-10-10 10:48:00+00	2026-10-10 09:32:00+00
245	47ac5cee-f468-5dd9-bd2f-994a2e1556fe	17	t	2026-09-12 11:45:00+00	2026-09-12 14:45:00+00	2026-09-12 14:23:00+00
246	b179af01-a01d-5d62-8805-310edc535f62	11	t	2026-09-24 04:57:00+00	2026-09-24 06:57:00+00	2026-09-24 06:57:00+00
247	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	10	t	2026-09-26 09:33:00+00	2026-09-26 11:33:00+00	2026-09-26 11:33:00+00
248	c39ee07c-08d3-51a9-8933-c3f20abe6a2d	1	f	2026-10-10 05:10:00+00	2026-10-10 07:10:00+00	2026-10-10 05:56:00+00
249	ee4381b0-e713-5329-accc-f50e1a5ee4f6	10	f	2026-09-30 09:30:00+00	2026-09-30 12:30:00+00	2026-09-30 11:16:00+00
250	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	7	t	2026-09-25 04:55:00+00	2026-09-25 07:55:00+00	2026-09-25 07:42:00+00
251	efd23983-5f8f-5e47-bba6-22cfcef33110	13	f	2026-10-04 16:12:00+00	2026-10-04 18:12:00+00	2026-10-04 18:12:00+00
252	4b052f0a-0cb1-59a1-912b-2786fdd40f68	15	f	2026-09-11 12:46:00+00	2026-09-11 14:46:00+00	2026-09-11 14:46:00+00
253	8557a85b-2ada-524a-9191-e5c392f2ecd0	12	f	2026-10-04 09:12:00+00	2026-10-04 12:12:00+00	2026-10-04 12:12:00+00
254	7e59a7bf-1599-5d03-870a-b80f4a201398	18	t	2026-09-18 09:19:00+00	2026-09-18 12:19:00+00	2026-09-18 12:19:00+00
255	7106add8-93da-510c-a2ee-43f512e49d3c	5	t	2026-09-29 16:49:00+00	2026-09-29 19:49:00+00	2026-09-29 18:06:00+00
256	4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	5	t	2026-10-02 13:00:00+00	2026-10-02 15:00:00+00	2026-10-02 15:00:00+00
257	af37d114-6cbb-5069-9e3e-89e207493efa	15	f	2026-09-27 09:19:00+00	2026-09-27 11:19:00+00	2026-09-27 10:17:00+00
258	b4455c9f-c726-58c4-a73d-dc7ac20b4280	3	f	2026-09-30 13:32:00+00	2026-09-30 15:32:00+00	2026-09-30 14:04:00+00
259	1686e8b7-7ab0-56f5-894c-17df38559d0b	18	f	2026-09-21 12:18:00+00	2026-09-21 14:18:00+00	2026-09-21 14:18:00+00
260	cd609af0-f2d9-5556-9083-47c78c3e1318	11	f	2026-09-28 13:30:00+00	2026-09-28 14:30:00+00	2026-09-28 14:13:00+00
261	d798b580-e0a7-5aa0-b42b-c9509861df97	17	f	2026-09-17 10:25:00+00	2026-09-17 12:25:00+00	2026-09-17 10:55:00+00
262	a1aba091-ac3f-5cfb-8f0e-025ddbe56044	18	f	2026-09-15 08:25:00+00	2026-09-15 10:25:00+00	2026-09-15 09:30:00+00
263	91665b25-1a02-5391-be1f-630466bf5a2f	18	f	2026-09-21 06:51:00+00	2026-09-21 07:51:00+00	2026-09-21 07:51:00+00
264	d52c4849-0424-556a-909f-dc1685c34ca7	16	t	2026-09-16 11:19:00+00	2026-09-16 14:19:00+00	2026-09-16 14:19:00+00
265	1e821e58-daac-52d8-9ff6-668fa3f23828	16	f	2026-09-20 04:54:00+00	2026-09-20 05:54:00+00	2026-09-20 05:33:00+00
266	1f63d3e3-cfb5-5ff8-8750-8765e7286e09	6	f	2026-09-13 07:49:00+00	2026-09-13 09:49:00+00	2026-09-13 08:35:00+00
267	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	12	f	2026-09-23 06:59:00+00	2026-09-23 08:59:00+00	2026-09-23 08:59:00+00
268	448fc3a2-4bb5-55c5-af6c-daa5b70403fc	8	t	2026-09-21 09:33:00+00	2026-09-21 11:33:00+00	2026-09-21 11:33:00+00
269	44a51247-0f45-5096-9fca-81ed70346a12	4	f	2026-09-15 13:37:00+00	2026-09-15 14:37:00+00	2026-09-15 14:04:00+00
270	bf5483dd-f9be-503e-b843-511fab7772f3	3	f	2026-10-06 08:14:00+00	2026-10-06 10:14:00+00	2026-10-06 10:14:00+00
271	e2b516de-c76c-532d-8e53-5d02edbfa4ec	15	f	2026-10-02 07:42:00+00	2026-10-02 09:42:00+00	2026-10-02 09:42:00+00
272	b2dc61bc-373b-5d0c-bf25-529d5200c066	14	f	2026-09-30 12:55:00+00	2026-09-30 14:55:00+00	2026-09-30 13:39:00+00
273	3cfd1e72-fe25-526e-abce-f5c282026b57	17	f	2026-10-05 14:34:00+00	2026-10-05 15:34:00+00	2026-10-05 15:06:00+00
274	a6a72968-235d-553f-84a7-223f70ff71da	1	t	2026-09-20 09:13:00+00	2026-09-20 10:13:00+00	2026-09-20 10:01:00+00
275	cd999017-1402-5a6e-b041-fdafc8ded0f0	16	f	2026-09-11 03:31:00+00	2026-09-11 06:31:00+00	2026-09-11 06:31:00+00
276	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	3	t	2026-09-19 09:49:00+00	2026-09-19 12:49:00+00	2026-09-19 12:49:00+00
277	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	8	t	2026-09-22 12:45:00+00	2026-09-22 14:45:00+00	2026-09-22 14:05:00+00
278	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	5	t	2026-09-26 11:12:00+00	2026-09-26 12:12:00+00	2026-09-26 12:08:00+00
279	7cd65549-6305-538c-bfd9-ff7ee71213eb	6	t	2026-10-05 06:26:00+00	2026-10-05 08:26:00+00	2026-10-05 07:27:00+00
280	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	6	t	2026-10-03 09:00:00+00	2026-10-03 11:00:00+00	2026-10-03 11:00:00+00
281	37dd3141-05ee-5e5d-a4f2-fb04179e158b	15	t	2026-09-18 06:05:00+00	2026-09-18 08:05:00+00	2026-09-18 06:42:00+00
282	daecc825-1e7a-51cd-a171-4a41488773ae	1	f	2026-09-30 05:41:00+00	2026-09-30 07:41:00+00	2026-09-30 06:58:00+00
283	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	9	f	2026-09-19 06:26:00+00	2026-09-19 07:26:00+00	2026-09-19 07:26:00+00
284	e57e4f91-200d-5996-8f1f-c4140498ccb5	16	f	2026-10-08 09:22:00+00	2026-10-08 11:22:00+00	2026-10-08 10:02:00+00
285	0714361c-2671-547c-a5e8-7412dd5f5bb2	18	t	2026-10-10 09:02:00+00	2026-10-10 10:02:00+00	2026-10-10 10:02:00+00
286	2614e032-72f6-5f47-b46b-2b6fa25f275a	5	f	2026-09-25 15:24:00+00	2026-09-25 16:24:00+00	2026-09-25 16:24:00+00
287	1c41b127-85d5-5028-9e30-ef9cea4990f8	18	t	2026-09-25 07:17:00+00	2026-09-25 10:17:00+00	2026-09-25 09:47:00+00
288	89b01325-f844-5951-8b97-722e76d10e26	7	f	2026-09-24 12:07:00+00	2026-09-24 15:07:00+00	2026-09-24 14:17:00+00
289	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	1	t	2026-09-11 05:24:00+00	2026-09-11 07:24:00+00	2026-09-11 06:57:00+00
290	1686e8b7-7ab0-56f5-894c-17df38559d0b	15	t	2026-09-28 08:35:00+00	2026-09-28 10:35:00+00	2026-09-28 09:37:00+00
291	ee4381b0-e713-5329-accc-f50e1a5ee4f6	10	f	2026-10-02 16:31:00+00	2026-10-02 19:31:00+00	2026-10-02 17:46:00+00
292	ee4381b0-e713-5329-accc-f50e1a5ee4f6	13	t	2026-10-01 11:27:00+00	2026-10-01 14:27:00+00	2026-10-01 12:35:00+00
293	1e821e58-daac-52d8-9ff6-668fa3f23828	15	t	2026-09-15 08:35:00+00	2026-09-15 09:35:00+00	2026-09-15 09:35:00+00
294	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	15	t	2026-10-03 09:11:00+00	2026-10-03 10:11:00+00	2026-10-03 10:11:00+00
295	91665b25-1a02-5391-be1f-630466bf5a2f	17	t	2026-09-12 10:23:00+00	2026-09-12 12:23:00+00	2026-09-12 12:23:00+00
296	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	10	f	2026-09-25 09:48:00+00	2026-09-25 11:48:00+00	2026-09-25 11:48:00+00
297	b4455c9f-c726-58c4-a73d-dc7ac20b4280	3	t	2026-09-14 05:14:00+00	2026-09-14 08:14:00+00	2026-09-14 07:03:00+00
298	398c2e60-8a06-5f46-8fb0-e117c255ead8	3	t	2026-09-12 09:10:00+00	2026-09-12 11:10:00+00	2026-09-12 11:10:00+00
299	7caf10cc-bc08-579a-befd-dfa14a46a71b	11	t	2026-09-27 08:48:00+00	2026-09-27 11:48:00+00	2026-09-27 11:48:00+00
300	bb9f8bce-5de6-54be-a471-3c22fff845f5	4	f	2026-10-09 05:42:00+00	2026-10-09 07:42:00+00	2026-10-09 07:42:00+00
301	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	6	t	2026-09-21 08:42:00+00	2026-09-21 11:42:00+00	2026-09-21 11:42:00+00
302	4aed59c4-076a-58ea-8df4-eee688fc3b38	14	t	2026-10-08 10:30:00+00	2026-10-08 12:30:00+00	2026-10-08 12:30:00+00
303	b2dc61bc-373b-5d0c-bf25-529d5200c066	10	t	2026-09-15 09:17:00+00	2026-09-15 10:17:00+00	2026-09-15 10:15:00+00
304	91665b25-1a02-5391-be1f-630466bf5a2f	18	t	2026-09-11 10:58:00+00	2026-09-11 13:58:00+00	2026-09-11 13:58:00+00
305	bc586d94-7153-5cf0-8676-68bcb94a0d5a	1	t	2026-10-06 11:39:00+00	2026-10-06 12:39:00+00	2026-10-06 12:39:00+00
306	af37d114-6cbb-5069-9e3e-89e207493efa	15	t	2026-09-23 13:59:00+00	2026-09-23 14:59:00+00	2026-09-23 14:54:00+00
307	e2b516de-c76c-532d-8e53-5d02edbfa4ec	15	f	2026-09-21 08:02:00+00	2026-09-21 10:02:00+00	2026-09-21 10:02:00+00
308	b179af01-a01d-5d62-8805-310edc535f62	14	f	2026-09-12 07:09:00+00	2026-09-12 09:09:00+00	2026-09-12 09:09:00+00
309	bb9f8bce-5de6-54be-a471-3c22fff845f5	2	t	2026-09-25 07:58:00+00	2026-09-25 10:58:00+00	2026-09-25 10:58:00+00
310	37dd3141-05ee-5e5d-a4f2-fb04179e158b	18	f	2026-09-21 07:03:00+00	2026-09-21 10:03:00+00	2026-09-21 07:45:00+00
311	4aed59c4-076a-58ea-8df4-eee688fc3b38	10	t	2026-09-30 15:38:00+00	2026-09-30 18:38:00+00	2026-09-30 18:29:00+00
312	813640c1-13d1-52ed-b333-486966e596de	1	f	2026-09-19 08:11:00+00	2026-09-19 10:11:00+00	2026-09-19 08:45:00+00
313	7e59a7bf-1599-5d03-870a-b80f4a201398	15	f	2026-09-20 09:32:00+00	2026-09-20 12:32:00+00	2026-09-20 12:32:00+00
314	d52c4849-0424-556a-909f-dc1685c34ca7	16	t	2026-10-06 11:51:00+00	2026-10-06 13:51:00+00	2026-10-06 12:27:00+00
315	d723f696-83df-5e2e-9b66-1b6668a5bffb	14	f	2026-09-30 10:14:00+00	2026-09-30 12:14:00+00	2026-09-30 12:14:00+00
316	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	8	t	2026-09-27 07:18:00+00	2026-09-27 09:18:00+00	2026-09-27 08:34:00+00
317	594c5eb8-5eba-5db1-9527-7d409b4281ab	4	f	2026-09-28 06:39:00+00	2026-09-28 08:39:00+00	2026-09-28 08:39:00+00
318	b88dd4ac-02c8-576e-96b7-dad2fcc30210	3	t	2026-09-16 08:11:00+00	2026-09-16 09:11:00+00	2026-09-16 08:47:00+00
319	123a74f4-143d-5603-81d5-6331401ea569	4	t	2026-10-03 12:18:00+00	2026-10-03 15:18:00+00	2026-10-03 14:11:00+00
320	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	1	f	2026-09-29 13:39:00+00	2026-09-29 16:39:00+00	2026-09-29 15:55:00+00
321	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	6	t	2026-09-26 09:34:00+00	2026-09-26 10:34:00+00	2026-09-26 10:34:00+00
322	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	10	t	2026-10-07 15:08:00+00	2026-10-07 16:08:00+00	2026-10-07 15:41:00+00
323	7106add8-93da-510c-a2ee-43f512e49d3c	7	f	2026-09-11 14:05:00+00	2026-09-11 16:05:00+00	2026-09-11 15:28:00+00
324	bc586d94-7153-5cf0-8676-68bcb94a0d5a	3	t	2026-09-12 09:31:00+00	2026-09-12 11:31:00+00	2026-09-12 11:31:00+00
325	3cfd1e72-fe25-526e-abce-f5c282026b57	15	f	2026-09-14 14:04:00+00	2026-09-14 17:04:00+00	2026-09-14 17:04:00+00
326	2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	8	f	2026-09-16 13:12:00+00	2026-09-16 16:12:00+00	2026-09-16 16:12:00+00
327	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	4	f	2026-10-08 05:40:00+00	2026-10-08 06:40:00+00	2026-10-08 06:24:00+00
328	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	3	t	2026-10-06 10:21:00+00	2026-10-06 12:21:00+00	2026-10-06 11:51:00+00
329	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	16	t	2026-10-10 11:03:00+00	2026-10-10 12:03:00+00	2026-10-10 12:03:00+00
330	bf5483dd-f9be-503e-b843-511fab7772f3	2	f	2026-09-12 11:16:00+00	2026-09-12 12:16:00+00	2026-09-12 12:16:00+00
331	b88dd4ac-02c8-576e-96b7-dad2fcc30210	1	t	2026-10-07 16:24:00+00	2026-10-07 18:24:00+00	2026-10-07 18:24:00+00
332	2614e032-72f6-5f47-b46b-2b6fa25f275a	7	t	2026-09-16 09:34:00+00	2026-09-16 11:34:00+00	2026-09-16 10:54:00+00
333	e2b516de-c76c-532d-8e53-5d02edbfa4ec	18	t	2026-09-17 06:37:00+00	2026-09-17 08:37:00+00	2026-09-17 07:10:00+00
334	ad5b5e1b-07b1-5134-ae83-b16af18abe40	3	f	2026-10-05 11:11:00+00	2026-10-05 13:11:00+00	2026-10-05 13:11:00+00
335	1c41b127-85d5-5028-9e30-ef9cea4990f8	15	t	2026-10-02 12:20:00+00	2026-10-02 15:20:00+00	2026-10-02 13:19:00+00
336	1e821e58-daac-52d8-9ff6-668fa3f23828	18	f	2026-10-03 12:28:00+00	2026-10-03 15:28:00+00	2026-10-03 15:28:00+00
337	1686e8b7-7ab0-56f5-894c-17df38559d0b	15	t	2026-09-30 10:21:00+00	2026-09-30 12:21:00+00	2026-09-30 12:21:00+00
338	511cedf2-bc02-56a1-a754-2540298f5cee	13	f	2026-10-07 12:26:00+00	2026-10-07 15:26:00+00	2026-10-07 15:07:00+00
339	2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	5	f	2026-10-09 07:26:00+00	2026-10-09 10:26:00+00	2026-10-09 10:26:00+00
340	5c29fc1f-628e-5bdc-9e83-3e576df263d4	1	f	2026-09-13 05:50:00+00	2026-09-13 06:50:00+00	2026-09-13 06:35:00+00
341	18e969e2-d4e6-52f4-8e81-e62265f128f5	6	t	2026-09-29 10:44:00+00	2026-09-29 12:44:00+00	2026-09-29 12:23:00+00
342	ad5b5e1b-07b1-5134-ae83-b16af18abe40	3	f	2026-09-24 07:01:00+00	2026-09-24 09:01:00+00	2026-09-24 08:36:00+00
343	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	7	f	2026-10-03 10:59:00+00	2026-10-03 11:59:00+00	2026-10-03 11:25:00+00
344	7e76cba5-592a-50a9-a6e4-fb36d39a9030	10	f	2026-10-10 07:34:00+00	2026-10-10 09:34:00+00	2026-10-10 09:08:00+00
345	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	1	t	2026-09-13 04:18:00+00	2026-09-13 05:18:00+00	2026-09-13 04:39:00+00
346	1c41b127-85d5-5028-9e30-ef9cea4990f8	15	t	2026-10-03 11:04:00+00	2026-10-03 12:04:00+00	2026-10-03 11:48:00+00
347	123a74f4-143d-5603-81d5-6331401ea569	1	f	2026-10-09 07:33:00+00	2026-10-09 09:33:00+00	2026-10-09 09:33:00+00
348	3c16f96c-897e-5713-b4ce-ffc817887105	8	f	2026-10-09 08:06:00+00	2026-10-09 10:06:00+00	2026-10-09 10:06:00+00
349	ccd0071a-1fd0-5515-a5b8-937a6bb79b26	15	f	2026-09-26 06:24:00+00	2026-09-26 08:24:00+00	2026-09-26 08:24:00+00
350	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	1	f	2026-10-07 13:20:00+00	2026-10-07 15:20:00+00	2026-10-07 15:20:00+00
351	f036e23d-5323-5b4f-bb1c-6e87c77bff75	18	t	2026-09-18 11:41:00+00	2026-09-18 12:41:00+00	2026-09-18 12:41:00+00
352	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	14	t	2026-09-13 05:06:00+00	2026-09-13 08:06:00+00	2026-09-13 08:06:00+00
353	f036e23d-5323-5b4f-bb1c-6e87c77bff75	15	t	2026-09-26 07:20:00+00	2026-09-26 09:20:00+00	2026-09-26 09:17:00+00
354	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	7	f	2026-10-06 07:05:00+00	2026-10-06 09:05:00+00	2026-10-06 09:05:00+00
355	0631a63b-ebc2-5785-a739-9fee4b48e5bc	3	f	2026-10-10 11:27:00+00	2026-10-10 13:27:00+00	2026-10-10 11:51:00+00
356	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	2	t	2026-09-24 07:13:00+00	2026-09-24 10:13:00+00	2026-09-24 10:13:00+00
357	9738a135-fb05-52d2-9e40-e18b24491eb4	9	t	2026-09-16 06:53:00+00	2026-09-16 08:53:00+00	2026-09-16 08:53:00+00
358	1686e8b7-7ab0-56f5-894c-17df38559d0b	16	f	2026-09-14 11:31:00+00	2026-09-14 13:31:00+00	2026-09-14 12:49:00+00
359	1625ce28-8df4-51c9-9370-e37f4726715d	5	f	2026-10-01 05:46:00+00	2026-10-01 06:46:00+00	2026-10-01 06:35:00+00
360	bf5483dd-f9be-503e-b843-511fab7772f3	3	f	2026-09-18 12:20:00+00	2026-09-18 14:20:00+00	2026-09-18 12:45:00+00
361	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	3	t	2026-09-14 07:59:00+00	2026-09-14 09:59:00+00	2026-09-14 09:59:00+00
362	e1f7cb84-a272-5286-8d3b-6004b94c9fea	1	t	2026-09-30 13:28:00+00	2026-09-30 15:28:00+00	2026-09-30 15:28:00+00
363	b4455c9f-c726-58c4-a73d-dc7ac20b4280	1	t	2026-09-22 12:23:00+00	2026-09-22 13:23:00+00	2026-09-22 13:23:00+00
364	7106add8-93da-510c-a2ee-43f512e49d3c	8	t	2026-09-18 04:46:00+00	2026-09-18 06:46:00+00	2026-09-18 05:10:00+00
365	b88dd4ac-02c8-576e-96b7-dad2fcc30210	1	f	2026-10-05 13:41:00+00	2026-10-05 14:41:00+00	2026-10-05 14:22:00+00
366	89b01325-f844-5951-8b97-722e76d10e26	8	f	2026-09-20 13:15:00+00	2026-09-20 16:15:00+00	2026-09-20 14:48:00+00
367	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	8	f	2026-09-27 11:32:00+00	2026-09-27 13:32:00+00	2026-09-27 13:16:00+00
368	bf5483dd-f9be-503e-b843-511fab7772f3	1	t	2026-10-07 08:27:00+00	2026-10-07 09:27:00+00	2026-10-07 09:27:00+00
369	2614e032-72f6-5f47-b46b-2b6fa25f275a	6	t	2026-10-10 05:21:00+00	2026-10-10 06:21:00+00	2026-10-10 05:44:00+00
370	511cedf2-bc02-56a1-a754-2540298f5cee	11	t	2026-09-20 11:41:00+00	2026-09-20 14:41:00+00	2026-09-20 14:41:00+00
371	3c16f96c-897e-5713-b4ce-ffc817887105	5	f	2026-09-23 09:27:00+00	2026-09-23 11:27:00+00	2026-09-23 11:21:00+00
372	18e969e2-d4e6-52f4-8e81-e62265f128f5	5	f	2026-09-13 09:50:00+00	2026-09-13 11:50:00+00	2026-09-13 11:50:00+00
373	22177d59-b6dd-5230-ad3a-3f20a82c77be	3	t	2026-09-16 10:55:00+00	2026-09-16 11:55:00+00	2026-09-16 11:25:00+00
374	1c41b127-85d5-5028-9e30-ef9cea4990f8	17	t	2026-10-06 11:24:00+00	2026-10-06 12:24:00+00	2026-10-06 12:24:00+00
375	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	6	f	2026-09-20 13:56:00+00	2026-09-20 15:56:00+00	2026-09-20 15:56:00+00
376	ba12ad86-cec0-5c76-b72c-21e59427e8e5	10	f	2026-09-24 09:21:00+00	2026-09-24 11:21:00+00	2026-09-24 11:16:00+00
377	c39ee07c-08d3-51a9-8933-c3f20abe6a2d	2	f	2026-09-16 14:38:00+00	2026-09-16 16:38:00+00	2026-09-16 16:03:00+00
378	b4455c9f-c726-58c4-a73d-dc7ac20b4280	3	f	2026-09-11 05:24:00+00	2026-09-11 07:24:00+00	2026-09-11 07:24:00+00
379	b88dd4ac-02c8-576e-96b7-dad2fcc30210	1	f	2026-09-19 10:00:00+00	2026-09-19 12:00:00+00	2026-09-19 11:04:00+00
380	2667ad63-20cd-5653-af95-685a96aec1cb	4	t	2026-10-08 16:05:00+00	2026-10-08 18:05:00+00	2026-10-08 17:57:00+00
381	c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a	8	t	2026-10-02 06:51:00+00	2026-10-02 08:51:00+00	2026-10-02 07:59:00+00
382	448fc3a2-4bb5-55c5-af6c-daa5b70403fc	7	t	2026-09-16 06:02:00+00	2026-09-16 08:02:00+00	2026-09-16 08:02:00+00
383	9630d339-6604-569b-85a5-534d3a118af7	14	f	2026-09-30 09:17:00+00	2026-09-30 11:17:00+00	2026-09-30 11:17:00+00
384	8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	10	f	2026-09-28 11:11:00+00	2026-09-28 13:11:00+00	2026-09-28 12:19:00+00
385	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	7	t	2026-09-17 07:00:00+00	2026-09-17 10:00:00+00	2026-09-17 07:39:00+00
386	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	9	t	2026-09-17 10:15:00+00	2026-09-17 13:15:00+00	2026-09-17 12:18:00+00
387	91665b25-1a02-5391-be1f-630466bf5a2f	16	t	2026-09-17 13:55:00+00	2026-09-17 14:55:00+00	2026-09-17 14:55:00+00
388	32f48806-1d58-5528-ac5f-f78d0f615e62	12	t	2026-10-03 08:27:00+00	2026-10-03 10:27:00+00	2026-10-03 09:05:00+00
389	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	15	f	2026-09-24 09:46:00+00	2026-09-24 10:46:00+00	2026-09-24 10:46:00+00
390	12dc5f6c-cb16-5110-abfa-a398961b181a	10	t	2026-10-02 09:49:00+00	2026-10-02 10:49:00+00	2026-10-02 10:49:00+00
391	1e821e58-daac-52d8-9ff6-668fa3f23828	16	f	2026-10-02 04:20:00+00	2026-10-02 05:20:00+00	2026-10-02 05:20:00+00
392	f131d105-108d-58b0-b737-aee95985fa93	10	f	2026-10-03 10:57:00+00	2026-10-03 12:57:00+00	2026-10-03 12:57:00+00
393	1f63d3e3-cfb5-5ff8-8750-8765e7286e09	8	f	2026-09-25 07:59:00+00	2026-09-25 10:59:00+00	2026-09-25 10:59:00+00
394	7cd65549-6305-538c-bfd9-ff7ee71213eb	6	f	2026-10-02 12:32:00+00	2026-10-02 14:32:00+00	2026-10-02 14:32:00+00
395	9bc90fbb-1ed4-5e71-a722-019e2cc44797	8	f	2026-10-03 11:06:00+00	2026-10-03 13:06:00+00	2026-10-03 13:06:00+00
396	841aeb58-3431-5102-81be-941918ee4320	1	f	2026-09-30 05:11:00+00	2026-09-30 06:11:00+00	2026-09-30 06:01:00+00
397	18e969e2-d4e6-52f4-8e81-e62265f128f5	6	t	2026-10-10 07:34:00+00	2026-10-10 09:34:00+00	2026-10-10 08:30:00+00
398	8c6deb00-1371-546c-92a3-fa0544ab6f69	6	t	2026-09-23 10:00:00+00	2026-09-23 11:00:00+00	2026-09-23 10:28:00+00
399	a1aba091-ac3f-5cfb-8f0e-025ddbe56044	15	f	2026-09-14 15:34:00+00	2026-09-14 18:34:00+00	2026-09-14 18:21:00+00
400	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	13	f	2026-09-28 04:51:00+00	2026-09-28 07:51:00+00	2026-09-28 07:33:00+00
401	10cfe625-92d9-5f2d-8c28-3da5a44180d7	18	f	2026-09-27 07:05:00+00	2026-09-27 10:05:00+00	2026-09-27 09:00:00+00
402	d59eff6d-1910-5844-86ba-5c7c123704de	13	t	2026-09-17 06:29:00+00	2026-09-17 08:29:00+00	2026-09-17 08:07:00+00
403	7e76cba5-592a-50a9-a6e4-fb36d39a9030	11	t	2026-09-22 04:46:00+00	2026-09-22 06:46:00+00	2026-09-22 06:46:00+00
404	6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	18	t	2026-09-23 14:34:00+00	2026-09-23 16:34:00+00	2026-09-23 16:22:00+00
405	b2dc61bc-373b-5d0c-bf25-529d5200c066	12	t	2026-09-29 12:33:00+00	2026-09-29 13:33:00+00	2026-09-29 13:33:00+00
406	1f63d3e3-cfb5-5ff8-8750-8765e7286e09	7	t	2026-10-04 12:39:00+00	2026-10-04 15:39:00+00	2026-10-04 14:08:00+00
407	511cedf2-bc02-56a1-a754-2540298f5cee	12	f	2026-09-21 03:03:00+00	2026-09-21 04:03:00+00	2026-09-21 03:39:00+00
408	91665b25-1a02-5391-be1f-630466bf5a2f	18	f	2026-10-08 06:48:00+00	2026-10-08 07:48:00+00	2026-10-08 07:48:00+00
409	7106add8-93da-510c-a2ee-43f512e49d3c	8	f	2026-10-03 15:45:00+00	2026-10-03 16:45:00+00	2026-10-03 16:45:00+00
410	b179af01-a01d-5d62-8805-310edc535f62	11	f	2026-10-09 09:17:00+00	2026-10-09 10:17:00+00	2026-10-09 09:52:00+00
411	d52c4849-0424-556a-909f-dc1685c34ca7	16	f	2026-10-05 05:09:00+00	2026-10-05 08:09:00+00	2026-10-05 08:09:00+00
412	7e59a7bf-1599-5d03-870a-b80f4a201398	18	t	2026-10-03 06:39:00+00	2026-10-03 09:39:00+00	2026-10-03 09:39:00+00
413	45667a63-75a2-5327-80b3-07277bbc3a05	10	t	2026-10-09 12:16:00+00	2026-10-09 14:16:00+00	2026-10-09 12:40:00+00
414	3cfd1e72-fe25-526e-abce-f5c282026b57	15	t	2026-09-30 03:05:00+00	2026-09-30 05:05:00+00	2026-09-30 04:28:00+00
415	ce4654ab-6f97-5ba5-8e75-a674b62406d8	16	f	2026-10-05 14:14:00+00	2026-10-05 15:14:00+00	2026-10-05 15:14:00+00
416	b179af01-a01d-5d62-8805-310edc535f62	10	f	2026-09-14 14:03:00+00	2026-09-14 16:03:00+00	2026-09-14 14:56:00+00
417	7e76cba5-592a-50a9-a6e4-fb36d39a9030	10	f	2026-09-13 08:26:00+00	2026-09-13 10:26:00+00	2026-09-13 10:26:00+00
418	1686e8b7-7ab0-56f5-894c-17df38559d0b	15	t	2026-09-23 10:53:00+00	2026-09-23 12:53:00+00	2026-09-23 12:53:00+00
419	4375a7a0-75af-50b6-bf34-ac0b79555581	1	t	2026-10-10 13:19:00+00	2026-10-10 14:19:00+00	2026-10-10 13:53:00+00
420	813640c1-13d1-52ed-b333-486966e596de	4	f	2026-09-23 07:13:00+00	2026-09-23 08:13:00+00	2026-09-23 08:13:00+00
421	4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	8	t	2026-09-19 10:27:00+00	2026-09-19 12:27:00+00	2026-09-19 10:58:00+00
422	45667a63-75a2-5327-80b3-07277bbc3a05	13	t	2026-09-18 15:17:00+00	2026-09-18 17:17:00+00	2026-09-18 17:17:00+00
423	813640c1-13d1-52ed-b333-486966e596de	1	t	2026-09-18 06:46:00+00	2026-09-18 09:46:00+00	2026-09-18 09:20:00+00
424	e1f7cb84-a272-5286-8d3b-6004b94c9fea	2	f	2026-09-14 05:16:00+00	2026-09-14 06:16:00+00	2026-09-14 05:57:00+00
425	1f63d3e3-cfb5-5ff8-8750-8765e7286e09	7	f	2026-10-02 11:01:00+00	2026-10-02 12:01:00+00	2026-10-02 11:30:00+00
426	7e59a7bf-1599-5d03-870a-b80f4a201398	18	t	2026-09-17 06:11:00+00	2026-09-17 08:11:00+00	2026-09-17 08:11:00+00
427	44a51247-0f45-5096-9fca-81ed70346a12	1	t	2026-09-30 11:19:00+00	2026-09-30 13:19:00+00	2026-09-30 13:19:00+00
428	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	1	t	2026-10-10 16:19:00+00	2026-10-10 17:19:00+00	2026-10-10 17:19:00+00
429	bc586d94-7153-5cf0-8676-68bcb94a0d5a	1	f	2026-09-18 07:20:00+00	2026-09-18 10:20:00+00	2026-09-18 10:20:00+00
430	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	2	t	2026-09-18 05:40:00+00	2026-09-18 07:40:00+00	2026-09-18 06:28:00+00
431	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	9	t	2026-09-15 08:53:00+00	2026-09-15 09:53:00+00	2026-09-15 09:53:00+00
432	c39ee07c-08d3-51a9-8933-c3f20abe6a2d	3	t	2026-10-05 07:35:00+00	2026-10-05 08:35:00+00	2026-10-05 08:08:00+00
433	1c41b127-85d5-5028-9e30-ef9cea4990f8	18	f	2026-09-27 07:14:00+00	2026-09-27 08:14:00+00	2026-09-27 07:55:00+00
434	ce4654ab-6f97-5ba5-8e75-a674b62406d8	15	t	2026-09-23 11:28:00+00	2026-09-23 12:28:00+00	2026-09-23 12:07:00+00
435	36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	7	t	2026-10-04 06:37:00+00	2026-10-04 07:37:00+00	2026-10-04 07:16:00+00
436	89b01325-f844-5951-8b97-722e76d10e26	9	t	2026-10-01 15:19:00+00	2026-10-01 16:19:00+00	2026-10-01 15:50:00+00
437	7895e227-7cba-58d0-835e-69c8af3fcc63	11	t	2026-10-03 08:18:00+00	2026-10-03 11:18:00+00	2026-10-03 09:01:00+00
438	5a96375a-4aa6-5b7e-895c-ff70497093dd	10	t	2026-10-02 16:57:00+00	2026-10-02 17:57:00+00	2026-10-02 17:35:00+00
439	49226873-bb4d-5af8-b6d7-b618b6111788	5	t	2026-09-29 08:05:00+00	2026-09-29 11:05:00+00	2026-09-29 11:05:00+00
440	7e59a7bf-1599-5d03-870a-b80f4a201398	18	f	2026-09-28 11:57:00+00	2026-09-28 13:57:00+00	2026-09-28 12:32:00+00
441	bed83121-8bf1-5da8-b173-e725dd4e2e71	15	t	2026-09-30 12:01:00+00	2026-09-30 14:01:00+00	2026-09-30 14:01:00+00
442	b88dd4ac-02c8-576e-96b7-dad2fcc30210	1	f	2026-10-08 07:16:00+00	2026-10-08 09:16:00+00	2026-10-08 09:08:00+00
443	f131d105-108d-58b0-b737-aee95985fa93	12	t	2026-09-19 09:27:00+00	2026-09-19 11:27:00+00	2026-09-19 11:27:00+00
444	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	2	f	2026-09-15 10:16:00+00	2026-09-15 12:16:00+00	2026-09-15 12:16:00+00
445	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	5	t	2026-10-02 07:15:00+00	2026-10-02 10:15:00+00	2026-10-02 10:15:00+00
446	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	15	f	2026-09-13 13:00:00+00	2026-09-13 14:00:00+00	2026-09-13 14:00:00+00
447	daecc825-1e7a-51cd-a171-4a41488773ae	1	f	2026-10-01 12:09:00+00	2026-10-01 14:09:00+00	2026-10-01 12:38:00+00
448	a3692637-7d1e-50da-b993-3a5d101307b0	18	f	2026-09-25 06:09:00+00	2026-09-25 09:09:00+00	2026-09-25 07:32:00+00
449	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	17	f	2026-09-15 10:29:00+00	2026-09-15 13:29:00+00	2026-09-15 13:07:00+00
450	d52c4849-0424-556a-909f-dc1685c34ca7	16	t	2026-10-09 08:57:00+00	2026-10-09 09:57:00+00	2026-10-09 09:57:00+00
451	3cfd1e72-fe25-526e-abce-f5c282026b57	18	t	2026-09-26 16:36:00+00	2026-09-26 18:36:00+00	2026-09-26 18:36:00+00
452	bf5483dd-f9be-503e-b843-511fab7772f3	1	t	2026-09-24 07:25:00+00	2026-09-24 10:25:00+00	2026-09-24 09:37:00+00
453	2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	7	t	2026-09-24 04:47:00+00	2026-09-24 06:47:00+00	2026-09-24 05:35:00+00
454	301d506e-f995-5472-824e-7223eea34b29	10	t	2026-09-17 09:59:00+00	2026-09-17 12:59:00+00	2026-09-17 12:59:00+00
455	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	6	t	2026-10-01 07:12:00+00	2026-10-01 09:12:00+00	2026-10-01 08:46:00+00
456	e1f7cb84-a272-5286-8d3b-6004b94c9fea	1	t	2026-09-17 04:37:00+00	2026-09-17 06:37:00+00	2026-09-17 06:35:00+00
457	7e76cba5-592a-50a9-a6e4-fb36d39a9030	12	t	2026-09-14 06:59:00+00	2026-09-14 09:59:00+00	2026-09-14 09:59:00+00
458	4375a7a0-75af-50b6-bf34-ac0b79555581	4	f	2026-09-28 06:00:00+00	2026-09-28 08:00:00+00	2026-09-28 07:49:00+00
459	2c6189e6-c56d-5f5e-90e4-3ffcdef88870	9	t	2026-09-16 05:48:00+00	2026-09-16 08:48:00+00	2026-09-16 08:48:00+00
460	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	8	t	2026-09-29 12:48:00+00	2026-09-29 14:48:00+00	2026-09-29 14:45:00+00
461	1c41b127-85d5-5028-9e30-ef9cea4990f8	18	t	2026-09-14 07:37:00+00	2026-09-14 09:37:00+00	2026-09-14 09:37:00+00
462	cd609af0-f2d9-5556-9083-47c78c3e1318	11	f	2026-09-11 13:42:00+00	2026-09-11 15:42:00+00	2026-09-11 15:02:00+00
463	333281b0-ea48-5904-bc0d-1baecafb3642	18	f	2026-10-07 05:31:00+00	2026-10-07 07:31:00+00	2026-10-07 07:31:00+00
464	2667ad63-20cd-5653-af95-685a96aec1cb	1	f	2026-10-07 13:49:00+00	2026-10-07 15:49:00+00	2026-10-07 15:17:00+00
465	3ce15b25-c6e0-583d-a872-0dc16ae45020	14	f	2026-09-22 05:33:00+00	2026-09-22 07:33:00+00	2026-09-22 06:12:00+00
466	7e59a7bf-1599-5d03-870a-b80f4a201398	18	t	2026-09-22 13:43:00+00	2026-09-22 15:43:00+00	2026-09-22 15:41:00+00
467	8557a85b-2ada-524a-9191-e5c392f2ecd0	11	t	2026-10-07 11:09:00+00	2026-10-07 13:09:00+00	2026-10-07 11:54:00+00
468	af37d114-6cbb-5069-9e3e-89e207493efa	18	f	2026-10-03 06:35:00+00	2026-10-03 08:35:00+00	2026-10-03 07:55:00+00
469	511cedf2-bc02-56a1-a754-2540298f5cee	12	t	2026-09-19 07:17:00+00	2026-09-19 08:17:00+00	2026-09-19 08:17:00+00
470	c24a9165-fdd8-585f-b441-f68c0c7a3bfe	10	t	2026-09-18 10:39:00+00	2026-09-18 11:39:00+00	2026-09-18 11:24:00+00
471	7e76cba5-592a-50a9-a6e4-fb36d39a9030	12	t	2026-09-19 05:08:00+00	2026-09-19 07:08:00+00	2026-09-19 07:08:00+00
472	448fc3a2-4bb5-55c5-af6c-daa5b70403fc	7	f	2026-09-11 06:16:00+00	2026-09-11 08:16:00+00	2026-09-11 08:16:00+00
473	398c2e60-8a06-5f46-8fb0-e117c255ead8	3	t	2026-10-10 14:59:00+00	2026-10-10 16:59:00+00	2026-10-10 15:44:00+00
474	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	7	f	2026-09-14 14:03:00+00	2026-09-14 16:03:00+00	2026-09-14 14:51:00+00
475	2614e032-72f6-5f47-b46b-2b6fa25f275a	5	f	2026-09-23 13:07:00+00	2026-09-23 15:07:00+00	2026-09-23 15:07:00+00
476	511cedf2-bc02-56a1-a754-2540298f5cee	12	f	2026-10-06 07:24:00+00	2026-10-06 09:24:00+00	2026-10-06 08:05:00+00
477	5a96375a-4aa6-5b7e-895c-ff70497093dd	14	t	2026-09-22 06:57:00+00	2026-09-22 09:57:00+00	2026-09-22 09:57:00+00
478	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	2	f	2026-09-27 13:55:00+00	2026-09-27 14:55:00+00	2026-09-27 14:24:00+00
479	333281b0-ea48-5904-bc0d-1baecafb3642	15	t	2026-10-09 06:39:00+00	2026-10-09 09:39:00+00	2026-10-09 07:19:00+00
480	4aed59c4-076a-58ea-8df4-eee688fc3b38	11	t	2026-09-24 11:10:00+00	2026-09-24 12:10:00+00	2026-09-24 11:42:00+00
481	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	12	t	2026-09-29 09:37:00+00	2026-09-29 11:37:00+00	2026-09-29 10:56:00+00
482	0631a63b-ebc2-5785-a739-9fee4b48e5bc	4	f	2026-09-15 13:42:00+00	2026-09-15 14:42:00+00	2026-09-15 14:09:00+00
483	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	8	f	2026-09-19 12:33:00+00	2026-09-19 14:33:00+00	2026-09-19 14:17:00+00
484	bb9f8bce-5de6-54be-a471-3c22fff845f5	1	t	2026-10-01 08:33:00+00	2026-10-01 11:33:00+00	2026-10-01 11:33:00+00
485	0631a63b-ebc2-5785-a739-9fee4b48e5bc	3	t	2026-09-27 08:46:00+00	2026-09-27 09:46:00+00	2026-09-27 09:46:00+00
486	ba12ad86-cec0-5c76-b72c-21e59427e8e5	11	t	2026-10-02 09:00:00+00	2026-10-02 11:00:00+00	2026-10-02 10:59:00+00
487	18e969e2-d4e6-52f4-8e81-e62265f128f5	6	f	2026-10-08 07:04:00+00	2026-10-08 09:04:00+00	2026-10-08 09:04:00+00
488	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	8	t	2026-09-21 06:31:00+00	2026-09-21 09:31:00+00	2026-09-21 07:39:00+00
489	91665b25-1a02-5391-be1f-630466bf5a2f	15	t	2026-09-14 08:56:00+00	2026-09-14 10:56:00+00	2026-09-14 10:56:00+00
490	9bc90fbb-1ed4-5e71-a722-019e2cc44797	7	t	2026-09-14 13:30:00+00	2026-09-14 14:30:00+00	2026-09-14 14:30:00+00
491	7895e227-7cba-58d0-835e-69c8af3fcc63	10	f	2026-10-06 05:09:00+00	2026-10-06 07:09:00+00	2026-10-06 06:07:00+00
492	75732734-f0dc-516b-ab8d-647bcd6f7210	12	t	2026-09-26 06:59:00+00	2026-09-26 08:59:00+00	2026-09-26 08:59:00+00
493	7106add8-93da-510c-a2ee-43f512e49d3c	7	t	2026-09-27 06:32:00+00	2026-09-27 08:32:00+00	2026-09-27 08:32:00+00
494	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	6	t	2026-10-03 09:59:00+00	2026-10-03 11:59:00+00	2026-10-03 11:59:00+00
495	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	8	f	2026-10-09 14:49:00+00	2026-10-09 16:49:00+00	2026-10-09 15:16:00+00
496	7895e227-7cba-58d0-835e-69c8af3fcc63	10	t	2026-09-25 05:37:00+00	2026-09-25 08:37:00+00	2026-09-25 06:14:00+00
497	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	5	t	2026-09-12 09:04:00+00	2026-09-12 11:04:00+00	2026-09-12 11:04:00+00
498	7f082d5c-a953-51d5-a623-9d610ae577ba	7	f	2026-09-18 12:02:00+00	2026-09-18 13:02:00+00	2026-09-18 13:02:00+00
499	813640c1-13d1-52ed-b333-486966e596de	1	t	2026-09-30 11:42:00+00	2026-09-30 14:42:00+00	2026-09-30 13:08:00+00
500	ba12ad86-cec0-5c76-b72c-21e59427e8e5	13	t	2026-10-04 04:47:00+00	2026-10-04 06:47:00+00	2026-10-04 06:02:00+00
501	75732734-f0dc-516b-ab8d-647bcd6f7210	13	f	2026-09-14 14:57:00+00	2026-09-14 16:57:00+00	2026-09-14 16:46:00+00
502	bed83121-8bf1-5da8-b173-e725dd4e2e71	18	f	2026-09-26 10:37:00+00	2026-09-26 12:37:00+00	2026-09-26 11:34:00+00
503	bed83121-8bf1-5da8-b173-e725dd4e2e71	17	t	2026-09-25 12:50:00+00	2026-09-25 15:50:00+00	2026-09-25 15:50:00+00
504	bf5483dd-f9be-503e-b843-511fab7772f3	1	t	2026-10-02 05:23:00+00	2026-10-02 08:23:00+00	2026-10-02 05:58:00+00
505	333281b0-ea48-5904-bc0d-1baecafb3642	15	t	2026-09-21 13:11:00+00	2026-09-21 16:11:00+00	2026-09-21 14:59:00+00
506	5c29fc1f-628e-5bdc-9e83-3e576df263d4	3	t	2026-09-22 09:17:00+00	2026-09-22 12:17:00+00	2026-09-22 11:37:00+00
507	60c1d1fe-9756-50b7-aa0c-8938baaddde2	8	f	2026-09-19 10:14:00+00	2026-09-19 12:14:00+00	2026-09-19 12:14:00+00
508	f131d105-108d-58b0-b737-aee95985fa93	11	t	2026-09-12 11:34:00+00	2026-09-12 13:34:00+00	2026-09-12 13:34:00+00
509	45667a63-75a2-5327-80b3-07277bbc3a05	14	f	2026-09-15 14:32:00+00	2026-09-15 17:32:00+00	2026-09-15 17:32:00+00
510	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	3	t	2026-09-14 08:56:00+00	2026-09-14 10:56:00+00	2026-09-14 10:56:00+00
511	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	8	f	2026-09-30 10:02:00+00	2026-09-30 12:02:00+00	2026-09-30 10:38:00+00
512	b179af01-a01d-5d62-8805-310edc535f62	13	f	2026-09-25 09:28:00+00	2026-09-25 12:28:00+00	2026-09-25 12:28:00+00
513	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	6	t	2026-09-18 09:10:00+00	2026-09-18 11:10:00+00	2026-09-18 10:15:00+00
514	ee4381b0-e713-5329-accc-f50e1a5ee4f6	10	f	2026-10-06 09:41:00+00	2026-10-06 12:41:00+00	2026-10-06 10:18:00+00
515	7e59a7bf-1599-5d03-870a-b80f4a201398	18	t	2026-10-09 13:37:00+00	2026-10-09 15:37:00+00	2026-10-09 15:29:00+00
516	1c41b127-85d5-5028-9e30-ef9cea4990f8	15	f	2026-09-30 09:34:00+00	2026-09-30 12:34:00+00	2026-09-30 12:34:00+00
517	7cd65549-6305-538c-bfd9-ff7ee71213eb	8	f	2026-09-30 11:03:00+00	2026-09-30 12:03:00+00	2026-09-30 11:35:00+00
518	2c6189e6-c56d-5f5e-90e4-3ffcdef88870	8	f	2026-09-21 10:46:00+00	2026-09-21 11:46:00+00	2026-09-21 11:46:00+00
519	1686e8b7-7ab0-56f5-894c-17df38559d0b	16	f	2026-10-05 10:05:00+00	2026-10-05 12:05:00+00	2026-10-05 12:05:00+00
520	4375a7a0-75af-50b6-bf34-ac0b79555581	1	f	2026-10-09 09:30:00+00	2026-10-09 12:30:00+00	2026-10-09 12:30:00+00
521	9738a135-fb05-52d2-9e40-e18b24491eb4	5	t	2026-10-07 15:27:00+00	2026-10-07 17:27:00+00	2026-10-07 16:12:00+00
522	18e969e2-d4e6-52f4-8e81-e62265f128f5	6	t	2026-09-30 12:43:00+00	2026-09-30 15:43:00+00	2026-09-30 13:14:00+00
523	6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	15	f	2026-10-06 07:30:00+00	2026-10-06 08:30:00+00	2026-10-06 08:18:00+00
524	e57e4f91-200d-5996-8f1f-c4140498ccb5	15	t	2026-09-25 05:35:00+00	2026-09-25 07:35:00+00	2026-09-25 06:13:00+00
525	7e76cba5-592a-50a9-a6e4-fb36d39a9030	10	t	2026-10-04 06:38:00+00	2026-10-04 09:38:00+00	2026-10-04 07:17:00+00
526	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	4	t	2026-10-01 08:25:00+00	2026-10-01 10:25:00+00	2026-10-01 10:25:00+00
527	9bc90fbb-1ed4-5e71-a722-019e2cc44797	8	t	2026-10-02 04:24:00+00	2026-10-02 07:24:00+00	2026-10-02 07:24:00+00
528	ee4381b0-e713-5329-accc-f50e1a5ee4f6	13	t	2026-09-28 07:34:00+00	2026-09-28 08:34:00+00	2026-09-28 08:06:00+00
529	1e821e58-daac-52d8-9ff6-668fa3f23828	16	f	2026-09-22 08:43:00+00	2026-09-22 10:43:00+00	2026-09-22 09:56:00+00
530	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	1	t	2026-09-11 09:20:00+00	2026-09-11 10:20:00+00	2026-09-11 10:00:00+00
531	bf1b1568-063d-5529-a346-27dcbdb160fc	3	t	2026-09-28 13:12:00+00	2026-09-28 16:12:00+00	2026-09-28 15:14:00+00
532	7f082d5c-a953-51d5-a623-9d610ae577ba	6	t	2026-10-04 11:27:00+00	2026-10-04 14:27:00+00	2026-10-04 14:27:00+00
533	3c16f96c-897e-5713-b4ce-ffc817887105	5	f	2026-09-25 04:31:00+00	2026-09-25 07:31:00+00	2026-09-25 05:45:00+00
534	ce4654ab-6f97-5ba5-8e75-a674b62406d8	17	f	2026-09-21 09:16:00+00	2026-09-21 12:16:00+00	2026-09-21 12:16:00+00
535	45667a63-75a2-5327-80b3-07277bbc3a05	11	t	2026-10-03 15:40:00+00	2026-10-03 17:40:00+00	2026-10-03 17:40:00+00
536	813640c1-13d1-52ed-b333-486966e596de	2	t	2026-09-25 04:40:00+00	2026-09-25 06:40:00+00	2026-09-25 06:40:00+00
537	7106add8-93da-510c-a2ee-43f512e49d3c	8	t	2026-10-07 06:21:00+00	2026-10-07 07:21:00+00	2026-10-07 06:44:00+00
538	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	6	t	2026-09-29 06:48:00+00	2026-09-29 08:48:00+00	2026-09-29 08:48:00+00
539	594c5eb8-5eba-5db1-9527-7d409b4281ab	4	f	2026-09-18 05:56:00+00	2026-09-18 06:56:00+00	2026-09-18 06:43:00+00
540	36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	5	t	2026-09-19 10:34:00+00	2026-09-19 11:34:00+00	2026-09-19 11:18:00+00
541	9bc90fbb-1ed4-5e71-a722-019e2cc44797	9	f	2026-10-06 14:51:00+00	2026-10-06 16:51:00+00	2026-10-06 16:45:00+00
542	daecc825-1e7a-51cd-a171-4a41488773ae	2	t	2026-09-16 08:59:00+00	2026-09-16 10:59:00+00	2026-09-16 10:19:00+00
543	c25c9587-af2d-50a5-9cbc-1fdf3302f483	5	t	2026-10-06 05:26:00+00	2026-10-06 08:26:00+00	2026-10-06 07:21:00+00
544	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	5	t	2026-09-22 05:42:00+00	2026-09-22 08:42:00+00	2026-09-22 08:42:00+00
545	af37d114-6cbb-5069-9e3e-89e207493efa	16	f	2026-09-30 12:55:00+00	2026-09-30 14:55:00+00	2026-09-30 13:27:00+00
546	7e59a7bf-1599-5d03-870a-b80f4a201398	15	f	2026-09-29 05:54:00+00	2026-09-29 08:54:00+00	2026-09-29 08:54:00+00
547	2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	6	f	2026-09-27 06:34:00+00	2026-09-27 09:34:00+00	2026-09-27 09:28:00+00
548	8557a85b-2ada-524a-9191-e5c392f2ecd0	10	f	2026-09-14 14:28:00+00	2026-09-14 17:28:00+00	2026-09-14 15:20:00+00
549	123a74f4-143d-5603-81d5-6331401ea569	1	t	2026-09-28 07:16:00+00	2026-09-28 09:16:00+00	2026-09-28 08:34:00+00
550	5c29fc1f-628e-5bdc-9e83-3e576df263d4	3	t	2026-10-07 06:46:00+00	2026-10-07 09:46:00+00	2026-10-07 09:46:00+00
551	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	5	t	2026-09-18 12:19:00+00	2026-09-18 14:19:00+00	2026-09-18 14:19:00+00
552	bb9f8bce-5de6-54be-a471-3c22fff845f5	3	t	2026-09-18 06:48:00+00	2026-09-18 08:48:00+00	2026-09-18 07:37:00+00
553	5ab878f5-0da1-5a83-9dd1-f19a741d738e	18	f	2026-09-28 04:41:00+00	2026-09-28 06:41:00+00	2026-09-28 05:34:00+00
554	b88dd4ac-02c8-576e-96b7-dad2fcc30210	2	t	2026-09-23 15:37:00+00	2026-09-23 18:37:00+00	2026-09-23 18:37:00+00
555	12dc5f6c-cb16-5110-abfa-a398961b181a	10	f	2026-09-15 03:39:00+00	2026-09-15 05:39:00+00	2026-09-15 05:35:00+00
556	1686e8b7-7ab0-56f5-894c-17df38559d0b	15	t	2026-09-11 09:39:00+00	2026-09-11 12:39:00+00	2026-09-11 11:50:00+00
557	c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a	5	t	2026-10-01 04:48:00+00	2026-10-01 05:48:00+00	2026-10-01 05:48:00+00
558	32f48806-1d58-5528-ac5f-f78d0f615e62	13	t	2026-09-19 05:57:00+00	2026-09-19 08:57:00+00	2026-09-19 06:29:00+00
559	2667ad63-20cd-5653-af95-685a96aec1cb	2	t	2026-09-30 09:32:00+00	2026-09-30 11:32:00+00	2026-09-30 11:32:00+00
560	91665b25-1a02-5391-be1f-630466bf5a2f	18	f	2026-10-01 05:56:00+00	2026-10-01 07:56:00+00	2026-10-01 07:56:00+00
561	2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	9	t	2026-10-08 14:55:00+00	2026-10-08 16:55:00+00	2026-10-08 15:19:00+00
562	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	5	t	2026-10-05 09:52:00+00	2026-10-05 10:52:00+00	2026-10-05 10:39:00+00
563	7895e227-7cba-58d0-835e-69c8af3fcc63	11	t	2026-10-02 08:01:00+00	2026-10-02 10:01:00+00	2026-10-02 09:55:00+00
564	d6a0339c-e841-56e2-9be8-3c789fb9a47b	4	f	2026-09-23 07:41:00+00	2026-09-23 08:41:00+00	2026-09-23 08:37:00+00
565	bf5483dd-f9be-503e-b843-511fab7772f3	3	f	2026-09-30 09:31:00+00	2026-09-30 11:31:00+00	2026-09-30 10:02:00+00
566	448fc3a2-4bb5-55c5-af6c-daa5b70403fc	8	t	2026-09-25 09:57:00+00	2026-09-25 11:57:00+00	2026-09-25 11:57:00+00
567	511cedf2-bc02-56a1-a754-2540298f5cee	11	f	2026-09-28 08:36:00+00	2026-09-28 10:36:00+00	2026-09-28 10:22:00+00
568	bb9f8bce-5de6-54be-a471-3c22fff845f5	3	f	2026-09-17 08:04:00+00	2026-09-17 11:04:00+00	2026-09-17 08:50:00+00
569	47ac5cee-f468-5dd9-bd2f-994a2e1556fe	18	t	2026-09-20 14:37:00+00	2026-09-20 16:37:00+00	2026-09-20 16:00:00+00
570	7f082d5c-a953-51d5-a623-9d610ae577ba	6	t	2026-09-24 08:22:00+00	2026-09-24 10:22:00+00	2026-09-24 09:28:00+00
571	7895e227-7cba-58d0-835e-69c8af3fcc63	10	f	2026-10-09 11:02:00+00	2026-10-09 13:02:00+00	2026-10-09 13:02:00+00
572	12dc5f6c-cb16-5110-abfa-a398961b181a	14	f	2026-09-17 07:38:00+00	2026-09-17 09:38:00+00	2026-09-17 09:38:00+00
573	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	7	t	2026-09-18 03:21:00+00	2026-09-18 05:21:00+00	2026-09-18 04:08:00+00
574	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	3	t	2026-10-10 10:42:00+00	2026-10-10 12:42:00+00	2026-10-10 11:28:00+00
575	47ac5cee-f468-5dd9-bd2f-994a2e1556fe	16	f	2026-09-19 10:59:00+00	2026-09-19 12:59:00+00	2026-09-19 12:22:00+00
576	ee4381b0-e713-5329-accc-f50e1a5ee4f6	13	t	2026-09-21 05:13:00+00	2026-09-21 07:13:00+00	2026-09-21 07:13:00+00
577	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	15	f	2026-09-27 08:16:00+00	2026-09-27 10:16:00+00	2026-09-27 09:08:00+00
578	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	14	t	2026-09-12 10:20:00+00	2026-09-12 12:20:00+00	2026-09-12 11:23:00+00
579	5a96375a-4aa6-5b7e-895c-ff70497093dd	13	t	2026-10-05 05:17:00+00	2026-10-05 08:17:00+00	2026-10-05 08:17:00+00
580	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	14	t	2026-10-09 05:03:00+00	2026-10-09 07:03:00+00	2026-10-09 05:37:00+00
581	511cedf2-bc02-56a1-a754-2540298f5cee	11	f	2026-10-09 12:15:00+00	2026-10-09 15:15:00+00	2026-10-09 15:15:00+00
582	9738a135-fb05-52d2-9e40-e18b24491eb4	6	t	2026-09-18 12:58:00+00	2026-09-18 15:58:00+00	2026-09-18 13:38:00+00
583	398c2e60-8a06-5f46-8fb0-e117c255ead8	3	t	2026-10-03 09:18:00+00	2026-10-03 12:18:00+00	2026-10-03 12:18:00+00
584	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	11	f	2026-09-12 04:37:00+00	2026-09-12 06:37:00+00	2026-09-12 06:37:00+00
585	f131d105-108d-58b0-b737-aee95985fa93	11	f	2026-09-17 05:56:00+00	2026-09-17 07:56:00+00	2026-09-17 07:56:00+00
586	5c29fc1f-628e-5bdc-9e83-3e576df263d4	1	t	2026-09-29 09:06:00+00	2026-09-29 12:06:00+00	2026-09-29 12:06:00+00
587	d59eff6d-1910-5844-86ba-5c7c123704de	14	t	2026-09-27 08:03:00+00	2026-09-27 11:03:00+00	2026-09-27 10:52:00+00
588	d798b580-e0a7-5aa0-b42b-c9509861df97	17	t	2026-09-15 12:47:00+00	2026-09-15 14:47:00+00	2026-09-15 14:30:00+00
589	5a96375a-4aa6-5b7e-895c-ff70497093dd	14	t	2026-09-21 04:02:00+00	2026-09-21 05:02:00+00	2026-09-21 04:43:00+00
590	36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	7	f	2026-10-01 07:43:00+00	2026-10-01 08:43:00+00	2026-10-01 08:24:00+00
591	bc586d94-7153-5cf0-8676-68bcb94a0d5a	3	f	2026-09-21 10:50:00+00	2026-09-21 11:50:00+00	2026-09-21 11:21:00+00
592	289a1a72-f5c0-5531-a5a2-1431eae3980d	2	f	2026-09-22 10:17:00+00	2026-09-22 13:17:00+00	2026-09-22 11:36:00+00
593	cf43eb29-cfc9-5d39-ac2e-0d32e539c990	6	f	2026-09-28 07:24:00+00	2026-09-28 09:24:00+00	2026-09-28 08:07:00+00
594	7f082d5c-a953-51d5-a623-9d610ae577ba	5	t	2026-09-30 13:26:00+00	2026-09-30 15:26:00+00	2026-09-30 14:04:00+00
595	b179af01-a01d-5d62-8805-310edc535f62	10	t	2026-10-03 07:31:00+00	2026-10-03 09:31:00+00	2026-10-03 08:35:00+00
596	cd609af0-f2d9-5556-9083-47c78c3e1318	12	t	2026-09-12 11:37:00+00	2026-09-12 14:37:00+00	2026-09-12 14:37:00+00
597	1c41b127-85d5-5028-9e30-ef9cea4990f8	17	f	2026-10-04 05:58:00+00	2026-10-04 08:58:00+00	2026-10-04 08:58:00+00
598	d723f696-83df-5e2e-9b66-1b6668a5bffb	12	t	2026-09-22 14:44:00+00	2026-09-22 15:44:00+00	2026-09-22 15:44:00+00
599	a1aba091-ac3f-5cfb-8f0e-025ddbe56044	18	f	2026-10-02 06:18:00+00	2026-10-02 07:18:00+00	2026-10-02 07:04:00+00
600	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	6	f	2026-10-10 05:04:00+00	2026-10-10 08:04:00+00	2026-10-10 07:49:00+00
601	0f4985f0-eea4-5fc5-aba1-78fba1cf698f	5	t	2026-09-30 12:44:00+00	2026-09-30 14:44:00+00	2026-09-30 14:44:00+00
602	91665b25-1a02-5391-be1f-630466bf5a2f	15	t	2026-10-06 12:41:00+00	2026-10-06 14:41:00+00	2026-10-06 14:41:00+00
603	1f63d3e3-cfb5-5ff8-8750-8765e7286e09	5	t	2026-09-30 11:49:00+00	2026-09-30 13:49:00+00	2026-09-30 13:49:00+00
604	5a96375a-4aa6-5b7e-895c-ff70497093dd	14	t	2026-09-12 11:20:00+00	2026-09-12 12:20:00+00	2026-09-12 11:42:00+00
605	d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	6	t	2026-09-30 06:47:00+00	2026-09-30 08:47:00+00	2026-09-30 07:23:00+00
606	45667a63-75a2-5327-80b3-07277bbc3a05	14	f	2026-10-07 07:09:00+00	2026-10-07 08:09:00+00	2026-10-07 07:51:00+00
607	7e76cba5-592a-50a9-a6e4-fb36d39a9030	11	f	2026-10-07 14:13:00+00	2026-10-07 16:13:00+00	2026-10-07 14:46:00+00
608	60c1d1fe-9756-50b7-aa0c-8938baaddde2	6	f	2026-09-25 08:58:00+00	2026-09-25 09:58:00+00	2026-09-25 09:32:00+00
609	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	17	t	2026-10-09 11:07:00+00	2026-10-09 14:07:00+00	2026-10-09 14:07:00+00
610	7cd65549-6305-538c-bfd9-ff7ee71213eb	6	t	2026-10-10 09:03:00+00	2026-10-10 11:03:00+00	2026-10-10 11:03:00+00
611	bf1b1568-063d-5529-a346-27dcbdb160fc	3	t	2026-10-01 07:40:00+00	2026-10-01 09:40:00+00	2026-10-01 09:40:00+00
612	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	3	f	2026-09-26 07:51:00+00	2026-09-26 09:51:00+00	2026-09-26 08:38:00+00
613	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	12	f	2026-09-22 14:09:00+00	2026-09-22 17:09:00+00	2026-09-22 17:08:00+00
614	d52c4849-0424-556a-909f-dc1685c34ca7	15	f	2026-09-14 11:10:00+00	2026-09-14 12:10:00+00	2026-09-14 12:10:00+00
615	d723f696-83df-5e2e-9b66-1b6668a5bffb	12	f	2026-09-20 10:47:00+00	2026-09-20 13:47:00+00	2026-09-20 13:45:00+00
616	3ce15b25-c6e0-583d-a872-0dc16ae45020	11	t	2026-10-10 07:57:00+00	2026-10-10 09:57:00+00	2026-10-10 08:17:00+00
617	4aed59c4-076a-58ea-8df4-eee688fc3b38	13	f	2026-09-11 12:02:00+00	2026-09-11 15:02:00+00	2026-09-11 15:02:00+00
618	ce4654ab-6f97-5ba5-8e75-a674b62406d8	18	t	2026-09-19 12:40:00+00	2026-09-19 13:40:00+00	2026-09-19 13:15:00+00
619	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	5	f	2026-10-03 06:36:00+00	2026-10-03 08:36:00+00	2026-10-03 08:36:00+00
620	45667a63-75a2-5327-80b3-07277bbc3a05	10	t	2026-09-30 04:52:00+00	2026-09-30 05:52:00+00	2026-09-30 05:47:00+00
621	4b052f0a-0cb1-59a1-912b-2786fdd40f68	18	f	2026-10-07 11:01:00+00	2026-10-07 12:01:00+00	2026-10-07 12:01:00+00
622	fd594592-8d60-5f8c-be18-349a233ea712	15	f	2026-09-26 08:54:00+00	2026-09-26 10:54:00+00	2026-09-26 10:54:00+00
623	bb9f8bce-5de6-54be-a471-3c22fff845f5	1	t	2026-09-23 12:57:00+00	2026-09-23 13:57:00+00	2026-09-23 13:48:00+00
624	2667ad63-20cd-5653-af95-685a96aec1cb	2	f	2026-10-06 07:42:00+00	2026-10-06 09:42:00+00	2026-10-06 08:10:00+00
625	a1aba091-ac3f-5cfb-8f0e-025ddbe56044	16	f	2026-09-12 06:27:00+00	2026-09-12 08:27:00+00	2026-09-12 08:27:00+00
626	8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	1	t	2026-09-28 10:47:00+00	2026-09-28 11:47:00+00	2026-09-28 11:47:00+00
627	daecc825-1e7a-51cd-a171-4a41488773ae	1	t	2026-09-19 03:54:00+00	2026-09-19 06:54:00+00	2026-09-19 05:58:00+00
628	37dd3141-05ee-5e5d-a4f2-fb04179e158b	15	t	2026-09-25 11:07:00+00	2026-09-25 14:07:00+00	2026-09-25 14:07:00+00
629	b179af01-a01d-5d62-8805-310edc535f62	10	f	2026-09-23 08:37:00+00	2026-09-23 10:37:00+00	2026-09-23 10:04:00+00
630	ad5b5e1b-07b1-5134-ae83-b16af18abe40	1	t	2026-09-26 07:06:00+00	2026-09-26 09:06:00+00	2026-09-26 08:43:00+00
631	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	2	f	2026-09-11 07:08:00+00	2026-09-11 09:08:00+00	2026-09-11 09:08:00+00
632	7cd65549-6305-538c-bfd9-ff7ee71213eb	6	f	2026-09-13 08:22:00+00	2026-09-13 10:22:00+00	2026-09-13 10:22:00+00
633	4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	5	f	2026-10-08 11:44:00+00	2026-10-08 13:44:00+00	2026-10-08 13:21:00+00
634	1e821e58-daac-52d8-9ff6-668fa3f23828	15	f	2026-09-18 05:21:00+00	2026-09-18 06:21:00+00	2026-09-18 05:44:00+00
635	cd999017-1402-5a6e-b041-fdafc8ded0f0	16	f	2026-09-29 10:03:00+00	2026-09-29 12:03:00+00	2026-09-29 12:03:00+00
636	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	15	f	2026-10-03 09:48:00+00	2026-10-03 11:48:00+00	2026-10-03 11:48:00+00
637	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	18	f	2026-10-05 10:25:00+00	2026-10-05 12:25:00+00	2026-10-05 11:19:00+00
638	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	5	f	2026-09-16 09:27:00+00	2026-09-16 12:27:00+00	2026-09-16 10:56:00+00
639	813640c1-13d1-52ed-b333-486966e596de	1	f	2026-10-01 09:58:00+00	2026-10-01 12:58:00+00	2026-10-01 10:40:00+00
640	d6a0339c-e841-56e2-9be8-3c789fb9a47b	1	f	2026-09-15 09:41:00+00	2026-09-15 11:41:00+00	2026-09-15 11:41:00+00
641	44a51247-0f45-5096-9fca-81ed70346a12	3	f	2026-10-11 17:04:36.817683+00	2026-10-11 19:14:36.817683+00	\N
642	6f583e12-eb4d-5a2d-9b34-9120b6172fbf	1	t	2026-10-11 16:54:36.817683+00	2026-10-11 18:35:36.817683+00	\N
643	d6a0339c-e841-56e2-9be8-3c789fb9a47b	1	t	2026-10-11 16:38:36.817683+00	2026-10-11 18:20:36.817683+00	\N
644	79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	4	f	2026-10-11 17:01:36.817683+00	2026-10-11 18:15:36.817683+00	\N
645	bb9f8bce-5de6-54be-a471-3c22fff845f5	3	f	2026-10-11 16:41:36.817683+00	2026-10-11 19:11:36.817683+00	\N
646	ad5b5e1b-07b1-5134-ae83-b16af18abe40	1	f	2026-10-11 17:46:36.817683+00	2026-10-11 18:59:36.817683+00	\N
647	123a74f4-143d-5603-81d5-6331401ea569	3	t	2026-10-11 17:19:36.817683+00	2026-10-11 18:17:36.817683+00	\N
648	5c29fc1f-628e-5bdc-9e83-3e576df263d4	4	f	2026-10-11 17:53:36.817683+00	2026-10-11 18:57:36.817683+00	\N
649	594c5eb8-5eba-5db1-9527-7d409b4281ab	3	t	2026-10-11 17:26:36.817683+00	2026-10-11 18:22:36.817683+00	\N
650	a6a72968-235d-553f-84a7-223f70ff71da	2	f	2026-10-11 17:20:36.817683+00	2026-10-11 18:22:36.817683+00	\N
651	b88dd4ac-02c8-576e-96b7-dad2fcc30210	3	f	2026-10-11 17:20:36.817683+00	2026-10-11 19:03:36.817683+00	\N
652	384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	3	t	2026-10-11 17:45:36.817683+00	2026-10-11 18:54:36.817683+00	\N
653	bf1b1568-063d-5529-a346-27dcbdb160fc	4	f	2026-10-11 17:32:36.817683+00	2026-10-11 18:28:36.817683+00	\N
654	bf5483dd-f9be-503e-b843-511fab7772f3	3	t	2026-10-11 17:48:36.817683+00	2026-10-11 18:38:36.817683+00	\N
655	2667ad63-20cd-5653-af95-685a96aec1cb	1	t	2026-10-11 16:42:36.817683+00	2026-10-11 18:54:36.817683+00	\N
656	841aeb58-3431-5102-81be-941918ee4320	4	t	2026-10-11 17:26:36.817683+00	2026-10-11 19:04:36.817683+00	\N
657	b28f9b27-eccf-51b6-bad2-71b3eb1324e3	4	t	2026-10-11 16:58:36.817683+00	2026-10-11 18:23:36.817683+00	\N
658	398c2e60-8a06-5f46-8fb0-e117c255ead8	3	f	2026-10-11 17:45:36.817683+00	2026-10-11 18:55:36.817683+00	\N
659	b4455c9f-c726-58c4-a73d-dc7ac20b4280	3	f	2026-10-11 17:05:36.817683+00	2026-10-11 18:44:36.817683+00	\N
660	22177d59-b6dd-5230-ad3a-3f20a82c77be	1	f	2026-10-11 16:48:36.817683+00	2026-10-11 19:01:36.817683+00	\N
661	4375a7a0-75af-50b6-bf34-ac0b79555581	1	f	2026-10-11 17:49:36.817683+00	2026-10-11 18:16:36.817683+00	\N
662	e1f7cb84-a272-5286-8d3b-6004b94c9fea	1	t	2026-10-11 17:00:36.817683+00	2026-10-11 18:28:36.817683+00	\N
663	c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a	7	t	2026-10-11 17:21:36.817683+00	2026-10-11 19:02:36.817683+00	\N
664	36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	9	t	2026-10-11 17:49:36.817683+00	2026-10-11 18:46:36.817683+00	\N
665	2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	6	t	2026-10-11 16:35:36.817683+00	2026-10-11 18:49:36.817683+00	\N
666	c25c9587-af2d-50a5-9cbc-1fdf3302f483	6	f	2026-10-11 16:51:36.817683+00	2026-10-11 18:19:36.817683+00	\N
667	18e969e2-d4e6-52f4-8e81-e62265f128f5	5	f	2026-10-11 16:21:36.817683+00	2026-10-11 18:40:36.817683+00	\N
668	d44f6451-0c5b-528c-a3a1-c6ec8caf288a	7	t	2026-10-11 16:27:36.817683+00	2026-10-11 18:43:36.817683+00	\N
669	1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	5	t	2026-10-11 17:27:36.817683+00	2026-10-11 19:10:36.817683+00	\N
670	3c16f96c-897e-5713-b4ce-ffc817887105	5	t	2026-10-11 17:14:36.817683+00	2026-10-11 18:43:36.817683+00	\N
671	1f63d3e3-cfb5-5ff8-8750-8765e7286e09	9	t	2026-10-11 16:24:36.817683+00	2026-10-11 18:56:36.817683+00	\N
672	7f082d5c-a953-51d5-a623-9d610ae577ba	7	f	2026-10-11 17:35:36.817683+00	2026-10-11 18:57:36.817683+00	\N
673	70a6775f-7bbd-5dff-aa6d-bc15b4445aec	8	t	2026-10-11 16:29:36.817683+00	2026-10-11 18:42:36.817683+00	\N
674	9bc90fbb-1ed4-5e71-a722-019e2cc44797	8	f	2026-10-11 17:49:36.817683+00	2026-10-11 18:16:36.817683+00	\N
675	2c6189e6-c56d-5f5e-90e4-3ffcdef88870	8	t	2026-10-11 17:10:36.817683+00	2026-10-11 18:57:36.817683+00	\N
676	0550482d-49c2-5f52-a61f-1c4badd27285	7	t	2026-10-11 16:42:36.817683+00	2026-10-11 18:15:36.817683+00	\N
677	49226873-bb4d-5af8-b6d7-b618b6111788	9	f	2026-10-11 17:51:36.817683+00	2026-10-11 18:59:36.817683+00	\N
678	8c6deb00-1371-546c-92a3-fa0544ab6f69	8	t	2026-10-11 17:24:36.817683+00	2026-10-11 18:47:36.817683+00	\N
679	1625ce28-8df4-51c9-9370-e37f4726715d	8	t	2026-10-11 17:24:36.817683+00	2026-10-11 18:48:36.817683+00	\N
680	b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	8	t	2026-10-11 17:28:36.817683+00	2026-10-11 18:38:36.817683+00	\N
681	ee4381b0-e713-5329-accc-f50e1a5ee4f6	10	f	2026-10-11 17:22:36.817683+00	2026-10-11 18:26:36.817683+00	\N
682	4aed59c4-076a-58ea-8df4-eee688fc3b38	12	t	2026-10-11 16:36:36.817683+00	2026-10-11 18:39:36.817683+00	\N
683	c595e95e-5ae4-58c8-b1f8-4b0d42c28318	12	t	2026-10-11 17:13:36.817683+00	2026-10-11 19:03:36.817683+00	\N
684	edb9f7d5-f25d-5618-aed1-d3c8e12572ae	11	t	2026-10-11 17:51:36.817683+00	2026-10-11 19:01:36.817683+00	\N
685	3ce15b25-c6e0-583d-a872-0dc16ae45020	10	t	2026-10-11 16:31:36.817683+00	2026-10-11 19:01:36.817683+00	\N
686	ba12ad86-cec0-5c76-b72c-21e59427e8e5	14	t	2026-10-11 16:30:36.817683+00	2026-10-11 19:00:36.817683+00	\N
687	5a96375a-4aa6-5b7e-895c-ff70497093dd	11	t	2026-10-11 17:42:36.817683+00	2026-10-11 18:43:36.817683+00	\N
688	8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	14	f	2026-10-11 16:34:36.817683+00	2026-10-11 18:49:36.817683+00	\N
689	b2dc61bc-373b-5d0c-bf25-529d5200c066	12	f	2026-10-11 17:27:36.817683+00	2026-10-11 18:37:36.817683+00	\N
690	8557a85b-2ada-524a-9191-e5c392f2ecd0	11	t	2026-10-11 17:36:36.817683+00	2026-10-11 18:56:36.817683+00	\N
691	d59eff6d-1910-5844-86ba-5c7c123704de	10	t	2026-10-11 17:48:36.817683+00	2026-10-11 18:37:36.817683+00	\N
692	f131d105-108d-58b0-b737-aee95985fa93	10	t	2026-10-11 16:26:36.817683+00	2026-10-11 18:14:36.817683+00	\N
693	d7eb4bfb-e5ec-5046-854b-2d724a29dff3	10	t	2026-10-11 17:53:36.817683+00	2026-10-11 18:47:36.817683+00	\N
694	efd23983-5f8f-5e47-bba6-22cfcef33110	10	f	2026-10-11 16:47:36.817683+00	2026-10-11 18:40:36.817683+00	\N
695	b322d3fb-18a5-5119-abc3-151933818abd	14	t	2026-10-11 16:14:36.817683+00	2026-10-11 18:57:36.817683+00	\N
696	7895e227-7cba-58d0-835e-69c8af3fcc63	10	t	2026-10-11 16:32:36.817683+00	2026-10-11 19:00:36.817683+00	\N
697	d723f696-83df-5e2e-9b66-1b6668a5bffb	11	t	2026-10-11 16:20:36.817683+00	2026-10-11 18:19:36.817683+00	\N
698	511cedf2-bc02-56a1-a754-2540298f5cee	13	f	2026-10-11 16:45:36.817683+00	2026-10-11 18:31:36.817683+00	\N
699	12dc5f6c-cb16-5110-abfa-a398961b181a	10	t	2026-10-11 16:58:36.817683+00	2026-10-11 18:32:36.817683+00	\N
700	301d506e-f995-5472-824e-7223eea34b29	10	t	2026-10-11 16:47:36.817683+00	2026-10-11 18:51:36.817683+00	\N
701	7caf10cc-bc08-579a-befd-dfa14a46a71b	13	t	2026-10-11 17:17:36.817683+00	2026-10-11 18:33:36.817683+00	\N
702	37dd3141-05ee-5e5d-a4f2-fb04179e158b	18	f	2026-10-11 16:50:36.817683+00	2026-10-11 18:36:36.817683+00	\N
703	7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	16	t	2026-10-11 17:42:36.817683+00	2026-10-11 19:08:36.817683+00	\N
704	333281b0-ea48-5904-bc0d-1baecafb3642	16	f	2026-10-11 17:33:36.817683+00	2026-10-11 19:09:36.817683+00	\N
705	0714361c-2671-547c-a5e8-7412dd5f5bb2	18	f	2026-10-11 16:25:36.817683+00	2026-10-11 19:08:36.817683+00	\N
706	ce4654ab-6f97-5ba5-8e75-a674b62406d8	15	f	2026-10-11 16:21:36.817683+00	2026-10-11 19:00:36.817683+00	\N
707	7e59a7bf-1599-5d03-870a-b80f4a201398	18	f	2026-10-11 17:52:36.817683+00	2026-10-11 18:28:36.817683+00	\N
708	e2b516de-c76c-532d-8e53-5d02edbfa4ec	15	t	2026-10-11 16:42:36.817683+00	2026-10-11 19:06:36.817683+00	\N
709	bed83121-8bf1-5da8-b173-e725dd4e2e71	15	t	2026-10-11 17:32:36.817683+00	2026-10-11 18:33:36.817683+00	\N
710	d798b580-e0a7-5aa0-b42b-c9509861df97	16	t	2026-10-11 16:22:36.817683+00	2026-10-11 19:00:36.817683+00	\N
711	1e821e58-daac-52d8-9ff6-668fa3f23828	15	t	2026-10-11 17:36:36.817683+00	2026-10-11 18:57:36.817683+00	\N
712	c72f74fd-f7ae-5e0d-9c17-09eb9f747580	15	t	2026-10-11 17:21:36.817683+00	2026-10-11 18:34:36.817683+00	\N
713	ccd0071a-1fd0-5515-a5b8-937a6bb79b26	15	t	2026-10-11 17:48:36.817683+00	2026-10-11 18:49:36.817683+00	\N
714	d52c4849-0424-556a-909f-dc1685c34ca7	15	t	2026-10-11 17:12:36.817683+00	2026-10-11 18:35:36.817683+00	\N
715	fd594592-8d60-5f8c-be18-349a233ea712	15	t	2026-10-11 16:18:36.817683+00	2026-10-11 18:46:36.817683+00	\N
716	3cfd1e72-fe25-526e-abce-f5c282026b57	15	f	2026-10-11 17:46:36.817683+00	2026-10-11 18:54:36.817683+00	\N
717	cd999017-1402-5a6e-b041-fdafc8ded0f0	18	f	2026-10-11 16:14:36.817683+00	2026-10-11 18:33:36.817683+00	\N
718	4b052f0a-0cb1-59a1-912b-2786fdd40f68	17	f	2026-10-11 17:47:36.817683+00	2026-10-11 19:03:36.817683+00	\N
719	1c41b127-85d5-5028-9e30-ef9cea4990f8	17	t	2026-10-11 16:16:36.817683+00	2026-10-11 18:18:36.817683+00	\N
720	6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	16	t	2026-10-11 16:24:36.817683+00	2026-10-11 18:18:36.817683+00	\N
721	a3692637-7d1e-50da-b993-3a5d101307b0	18	t	2026-10-11 17:13:36.817683+00	2026-10-11 18:30:36.817683+00	\N
722	10cfe625-92d9-5f2d-8c28-3da5a44180d7	18	t	2026-10-11 16:17:36.817683+00	2026-10-11 19:12:36.817683+00	\N
\.


--
-- Data for Name: email_domains; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.email_domains (domain, university_id) FROM stdin;
astanait.edu.kz	1
nu.edu.kz	2
mnu.kz	3
kazguu.kz	3
enu.kz	4
\.


--
-- Data for Name: favourites; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.favourites (user_id, space_id, created_at) FROM stdin;
0550482d-49c2-5f52-a61f-1c4badd27285	5	2026-10-11 17:54:36.817683+00
0631a63b-ebc2-5785-a739-9fee4b48e5bc	3	2026-10-11 17:54:36.817683+00
0631a63b-ebc2-5785-a739-9fee4b48e5bc	2	2026-10-11 17:54:36.817683+00
0f4985f0-eea4-5fc5-aba1-78fba1cf698f	5	2026-10-11 17:54:36.817683+00
0f4985f0-eea4-5fc5-aba1-78fba1cf698f	7	2026-10-11 17:54:36.817683+00
10cfe625-92d9-5f2d-8c28-3da5a44180d7	17	2026-10-11 17:54:36.817683+00
10cfe625-92d9-5f2d-8c28-3da5a44180d7	16	2026-10-11 17:54:36.817683+00
123a74f4-143d-5603-81d5-6331401ea569	3	2026-10-11 17:54:36.817683+00
123a74f4-143d-5603-81d5-6331401ea569	2	2026-10-11 17:54:36.817683+00
12dc5f6c-cb16-5110-abfa-a398961b181a	10	2026-10-11 17:54:36.817683+00
12dc5f6c-cb16-5110-abfa-a398961b181a	13	2026-10-11 17:54:36.817683+00
1625ce28-8df4-51c9-9370-e37f4726715d	5	2026-10-11 17:54:36.817683+00
1625ce28-8df4-51c9-9370-e37f4726715d	7	2026-10-11 17:54:36.817683+00
1686e8b7-7ab0-56f5-894c-17df38559d0b	15	2026-10-11 17:54:36.817683+00
18e969e2-d4e6-52f4-8e81-e62265f128f5	7	2026-10-11 17:54:36.817683+00
18e969e2-d4e6-52f4-8e81-e62265f128f5	6	2026-10-11 17:54:36.817683+00
1c41b127-85d5-5028-9e30-ef9cea4990f8	15	2026-10-11 17:54:36.817683+00
1e821e58-daac-52d8-9ff6-668fa3f23828	15	2026-10-11 17:54:36.817683+00
1f63d3e3-cfb5-5ff8-8750-8765e7286e09	6	2026-10-11 17:54:36.817683+00
1f63d3e3-cfb5-5ff8-8750-8765e7286e09	8	2026-10-11 17:54:36.817683+00
2667ad63-20cd-5653-af95-685a96aec1cb	4	2026-10-11 17:54:36.817683+00
2667ad63-20cd-5653-af95-685a96aec1cb	3	2026-10-11 17:54:36.817683+00
289a1a72-f5c0-5531-a5a2-1431eae3980d	3	2026-10-11 17:54:36.817683+00
289a1a72-f5c0-5531-a5a2-1431eae3980d	1	2026-10-11 17:54:36.817683+00
289a1a72-f5c0-5531-a5a2-1431eae3980d	2	2026-10-11 17:54:36.817683+00
2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	8	2026-10-11 17:54:36.817683+00
32f48806-1d58-5528-ac5f-f78d0f615e62	10	2026-10-11 17:54:36.817683+00
32f48806-1d58-5528-ac5f-f78d0f615e62	12	2026-10-11 17:54:36.817683+00
32f48806-1d58-5528-ac5f-f78d0f615e62	11	2026-10-11 17:54:36.817683+00
333281b0-ea48-5904-bc0d-1baecafb3642	17	2026-10-11 17:54:36.817683+00
36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	9	2026-10-11 17:54:36.817683+00
37dd3141-05ee-5e5d-a4f2-fb04179e158b	16	2026-10-11 17:54:36.817683+00
384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	4	2026-10-11 17:54:36.817683+00
398c2e60-8a06-5f46-8fb0-e117c255ead8	1	2026-10-11 17:54:36.817683+00
3c16f96c-897e-5713-b4ce-ffc817887105	5	2026-10-11 17:54:36.817683+00
3c16f96c-897e-5713-b4ce-ffc817887105	6	2026-10-11 17:54:36.817683+00
3ce15b25-c6e0-583d-a872-0dc16ae45020	13	2026-10-11 17:54:36.817683+00
3ce15b25-c6e0-583d-a872-0dc16ae45020	11	2026-10-11 17:54:36.817683+00
3cfd1e72-fe25-526e-abce-f5c282026b57	16	2026-10-11 17:54:36.817683+00
3cfd1e72-fe25-526e-abce-f5c282026b57	15	2026-10-11 17:54:36.817683+00
4375a7a0-75af-50b6-bf34-ac0b79555581	4	2026-10-11 17:54:36.817683+00
448fc3a2-4bb5-55c5-af6c-daa5b70403fc	8	2026-10-11 17:54:36.817683+00
448fc3a2-4bb5-55c5-af6c-daa5b70403fc	9	2026-10-11 17:54:36.817683+00
44a51247-0f45-5096-9fca-81ed70346a12	4	2026-10-11 17:54:36.817683+00
45667a63-75a2-5327-80b3-07277bbc3a05	10	2026-10-11 17:54:36.817683+00
47ac5cee-f468-5dd9-bd2f-994a2e1556fe	16	2026-10-11 17:54:36.817683+00
49226873-bb4d-5af8-b6d7-b618b6111788	5	2026-10-11 17:54:36.817683+00
4aed59c4-076a-58ea-8df4-eee688fc3b38	10	2026-10-11 17:54:36.817683+00
4b052f0a-0cb1-59a1-912b-2786fdd40f68	16	2026-10-11 17:54:36.817683+00
4b052f0a-0cb1-59a1-912b-2786fdd40f68	15	2026-10-11 17:54:36.817683+00
4b052f0a-0cb1-59a1-912b-2786fdd40f68	18	2026-10-11 17:54:36.817683+00
4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	7	2026-10-11 17:54:36.817683+00
511cedf2-bc02-56a1-a754-2540298f5cee	14	2026-10-11 17:54:36.817683+00
594c5eb8-5eba-5db1-9527-7d409b4281ab	2	2026-10-11 17:54:36.817683+00
5ab878f5-0da1-5a83-9dd1-f19a741d738e	17	2026-10-11 17:54:36.817683+00
5ab878f5-0da1-5a83-9dd1-f19a741d738e	18	2026-10-11 17:54:36.817683+00
60c1d1fe-9756-50b7-aa0c-8938baaddde2	6	2026-10-11 17:54:36.817683+00
60c1d1fe-9756-50b7-aa0c-8938baaddde2	8	2026-10-11 17:54:36.817683+00
6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	17	2026-10-11 17:54:36.817683+00
6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	16	2026-10-11 17:54:36.817683+00
7106add8-93da-510c-a2ee-43f512e49d3c	5	2026-10-11 17:54:36.817683+00
7106add8-93da-510c-a2ee-43f512e49d3c	9	2026-10-11 17:54:36.817683+00
75732734-f0dc-516b-ab8d-647bcd6f7210	10	2026-10-11 17:54:36.817683+00
79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	4	2026-10-11 17:54:36.817683+00
7cd65549-6305-538c-bfd9-ff7ee71213eb	7	2026-10-11 17:54:36.817683+00
7cd65549-6305-538c-bfd9-ff7ee71213eb	6	2026-10-11 17:54:36.817683+00
7cd65549-6305-538c-bfd9-ff7ee71213eb	8	2026-10-11 17:54:36.817683+00
7e59a7bf-1599-5d03-870a-b80f4a201398	15	2026-10-11 17:54:36.817683+00
7e76cba5-592a-50a9-a6e4-fb36d39a9030	14	2026-10-11 17:54:36.817683+00
7f082d5c-a953-51d5-a623-9d610ae577ba	6	2026-10-11 17:54:36.817683+00
813640c1-13d1-52ed-b333-486966e596de	1	2026-10-11 17:54:36.817683+00
8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	10	2026-10-11 17:54:36.817683+00
841aeb58-3431-5102-81be-941918ee4320	1	2026-10-11 17:54:36.817683+00
8557a85b-2ada-524a-9191-e5c392f2ecd0	14	2026-10-11 17:54:36.817683+00
8557a85b-2ada-524a-9191-e5c392f2ecd0	10	2026-10-11 17:54:36.817683+00
8c6deb00-1371-546c-92a3-fa0544ab6f69	6	2026-10-11 17:54:36.817683+00
8c6deb00-1371-546c-92a3-fa0544ab6f69	8	2026-10-11 17:54:36.817683+00
91665b25-1a02-5391-be1f-630466bf5a2f	17	2026-10-11 17:54:36.817683+00
91665b25-1a02-5391-be1f-630466bf5a2f	16	2026-10-11 17:54:36.817683+00
9738a135-fb05-52d2-9e40-e18b24491eb4	5	2026-10-11 17:54:36.817683+00
9bc90fbb-1ed4-5e71-a722-019e2cc44797	5	2026-10-11 17:54:36.817683+00
9bc90fbb-1ed4-5e71-a722-019e2cc44797	8	2026-10-11 17:54:36.817683+00
a1aba091-ac3f-5cfb-8f0e-025ddbe56044	16	2026-10-11 17:54:36.817683+00
a3692637-7d1e-50da-b993-3a5d101307b0	15	2026-10-11 17:54:36.817683+00
a3692637-7d1e-50da-b993-3a5d101307b0	18	2026-10-11 17:54:36.817683+00
a6a72968-235d-553f-84a7-223f70ff71da	2	2026-10-11 17:54:36.817683+00
ad5b5e1b-07b1-5134-ae83-b16af18abe40	1	2026-10-11 17:54:36.817683+00
af37d114-6cbb-5069-9e3e-89e207493efa	17	2026-10-11 17:54:36.817683+00
b179af01-a01d-5d62-8805-310edc535f62	10	2026-10-11 17:54:36.817683+00
b179af01-a01d-5d62-8805-310edc535f62	12	2026-10-11 17:54:36.817683+00
b179af01-a01d-5d62-8805-310edc535f62	13	2026-10-11 17:54:36.817683+00
b28f9b27-eccf-51b6-bad2-71b3eb1324e3	1	2026-10-11 17:54:36.817683+00
b2dc61bc-373b-5d0c-bf25-529d5200c066	12	2026-10-11 17:54:36.817683+00
b2dc61bc-373b-5d0c-bf25-529d5200c066	11	2026-10-11 17:54:36.817683+00
b322d3fb-18a5-5119-abc3-151933818abd	14	2026-10-11 17:54:36.817683+00
b322d3fb-18a5-5119-abc3-151933818abd	11	2026-10-11 17:54:36.817683+00
b4455c9f-c726-58c4-a73d-dc7ac20b4280	4	2026-10-11 17:54:36.817683+00
b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	7	2026-10-11 17:54:36.817683+00
b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	6	2026-10-11 17:54:36.817683+00
ba12ad86-cec0-5c76-b72c-21e59427e8e5	14	2026-10-11 17:54:36.817683+00
ba12ad86-cec0-5c76-b72c-21e59427e8e5	13	2026-10-11 17:54:36.817683+00
bb9f8bce-5de6-54be-a471-3c22fff845f5	4	2026-10-11 17:54:36.817683+00
bc586d94-7153-5cf0-8676-68bcb94a0d5a	3	2026-10-11 17:54:36.817683+00
bf1b1568-063d-5529-a346-27dcbdb160fc	3	2026-10-11 17:54:36.817683+00
bf1b1568-063d-5529-a346-27dcbdb160fc	2	2026-10-11 17:54:36.817683+00
bf5483dd-f9be-503e-b843-511fab7772f3	4	2026-10-11 17:54:36.817683+00
bf5483dd-f9be-503e-b843-511fab7772f3	1	2026-10-11 17:54:36.817683+00
bf5483dd-f9be-503e-b843-511fab7772f3	2	2026-10-11 17:54:36.817683+00
c24a9165-fdd8-585f-b441-f68c0c7a3bfe	12	2026-10-11 17:54:36.817683+00
c25c9587-af2d-50a5-9cbc-1fdf3302f483	5	2026-10-11 17:54:36.817683+00
c39ee07c-08d3-51a9-8933-c3f20abe6a2d	3	2026-10-11 17:54:36.817683+00
c39ee07c-08d3-51a9-8933-c3f20abe6a2d	2	2026-10-11 17:54:36.817683+00
c72f74fd-f7ae-5e0d-9c17-09eb9f747580	17	2026-10-11 17:54:36.817683+00
c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a	8	2026-10-11 17:54:36.817683+00
ccd0071a-1fd0-5515-a5b8-937a6bb79b26	17	2026-10-11 17:54:36.817683+00
ccd0071a-1fd0-5515-a5b8-937a6bb79b26	16	2026-10-11 17:54:36.817683+00
ccd0071a-1fd0-5515-a5b8-937a6bb79b26	15	2026-10-11 17:54:36.817683+00
cd999017-1402-5a6e-b041-fdafc8ded0f0	17	2026-10-11 17:54:36.817683+00
cd999017-1402-5a6e-b041-fdafc8ded0f0	15	2026-10-11 17:54:36.817683+00
cd999017-1402-5a6e-b041-fdafc8ded0f0	18	2026-10-11 17:54:36.817683+00
ce4654ab-6f97-5ba5-8e75-a674b62406d8	16	2026-10-11 17:54:36.817683+00
cf43eb29-cfc9-5d39-ac2e-0d32e539c990	5	2026-10-11 17:54:36.817683+00
d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	5	2026-10-11 17:54:36.817683+00
d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	7	2026-10-11 17:54:36.817683+00
d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	6	2026-10-11 17:54:36.817683+00
d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	8	2026-10-11 17:54:36.817683+00
d44f6451-0c5b-528c-a3a1-c6ec8caf288a	8	2026-10-11 17:54:36.817683+00
d44f6451-0c5b-528c-a3a1-c6ec8caf288a	9	2026-10-11 17:54:36.817683+00
d52c4849-0424-556a-909f-dc1685c34ca7	16	2026-10-11 17:54:36.817683+00
d59eff6d-1910-5844-86ba-5c7c123704de	14	2026-10-11 17:54:36.817683+00
d59eff6d-1910-5844-86ba-5c7c123704de	11	2026-10-11 17:54:36.817683+00
d6a0339c-e841-56e2-9be8-3c789fb9a47b	1	2026-10-11 17:54:36.817683+00
d6a0339c-e841-56e2-9be8-3c789fb9a47b	2	2026-10-11 17:54:36.817683+00
d798b580-e0a7-5aa0-b42b-c9509861df97	16	2026-10-11 17:54:36.817683+00
d798b580-e0a7-5aa0-b42b-c9509861df97	15	2026-10-11 17:54:36.817683+00
d7eb4bfb-e5ec-5046-854b-2d724a29dff3	12	2026-10-11 17:54:36.817683+00
d7eb4bfb-e5ec-5046-854b-2d724a29dff3	11	2026-10-11 17:54:36.817683+00
e1f7cb84-a272-5286-8d3b-6004b94c9fea	4	2026-10-11 17:54:36.817683+00
e1f7cb84-a272-5286-8d3b-6004b94c9fea	1	2026-10-11 17:54:36.817683+00
e1f7cb84-a272-5286-8d3b-6004b94c9fea	2	2026-10-11 17:54:36.817683+00
e2b516de-c76c-532d-8e53-5d02edbfa4ec	15	2026-10-11 17:54:36.817683+00
e2b516de-c76c-532d-8e53-5d02edbfa4ec	18	2026-10-11 17:54:36.817683+00
e57e4f91-200d-5996-8f1f-c4140498ccb5	18	2026-10-11 17:54:36.817683+00
edb9f7d5-f25d-5618-aed1-d3c8e12572ae	10	2026-10-11 17:54:36.817683+00
edb9f7d5-f25d-5618-aed1-d3c8e12572ae	13	2026-10-11 17:54:36.817683+00
ee4381b0-e713-5329-accc-f50e1a5ee4f6	11	2026-10-11 17:54:36.817683+00
f036e23d-5323-5b4f-bb1c-6e87c77bff75	15	2026-10-11 17:54:36.817683+00
f131d105-108d-58b0-b737-aee95985fa93	12	2026-10-11 17:54:36.817683+00
f131d105-108d-58b0-b737-aee95985fa93	11	2026-10-11 17:54:36.817683+00
fd594592-8d60-5f8c-be18-349a233ea712	15	2026-10-11 17:54:36.817683+00
\.


--
-- Data for Name: opening_hours; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.opening_hours (space_id, weekday, opens, closes) FROM stdin;
1	1	09:00:00	22:00:00
1	2	09:00:00	22:00:00
1	3	09:00:00	22:00:00
1	4	09:00:00	22:00:00
1	5	09:00:00	22:00:00
1	6	09:00:00	17:00:00
1	7	10:00:00	15:00:00
2	1	08:00:00	23:00:00
2	2	08:00:00	23:00:00
2	3	08:00:00	23:00:00
2	4	08:00:00	23:00:00
2	5	08:00:00	23:00:00
2	6	08:00:00	23:00:00
2	7	08:00:00	23:00:00
3	1	08:00:00	22:00:00
3	2	08:00:00	22:00:00
3	3	08:00:00	22:00:00
3	4	08:00:00	22:00:00
3	5	08:00:00	22:00:00
3	6	09:00:00	20:00:00
4	1	08:00:00	20:00:00
4	2	08:00:00	20:00:00
4	3	08:00:00	20:00:00
4	4	08:00:00	20:00:00
4	5	08:00:00	20:00:00
4	6	09:00:00	18:00:00
5	1	00:00:00	24:00:00
5	2	00:00:00	24:00:00
5	3	00:00:00	24:00:00
5	4	00:00:00	24:00:00
5	5	00:00:00	24:00:00
5	6	00:00:00	24:00:00
5	7	00:00:00	24:00:00
6	1	00:00:00	24:00:00
6	2	00:00:00	24:00:00
6	3	00:00:00	24:00:00
6	4	00:00:00	24:00:00
6	5	00:00:00	24:00:00
6	6	00:00:00	24:00:00
6	7	00:00:00	24:00:00
7	1	00:00:00	24:00:00
7	2	00:00:00	24:00:00
7	3	00:00:00	24:00:00
7	4	00:00:00	24:00:00
7	5	00:00:00	24:00:00
7	6	00:00:00	24:00:00
7	7	00:00:00	24:00:00
8	1	00:00:00	24:00:00
8	2	00:00:00	24:00:00
8	3	00:00:00	24:00:00
8	4	00:00:00	24:00:00
8	5	00:00:00	24:00:00
8	6	00:00:00	24:00:00
8	7	00:00:00	24:00:00
9	1	00:00:00	24:00:00
9	2	00:00:00	24:00:00
9	3	00:00:00	24:00:00
9	4	00:00:00	24:00:00
9	5	00:00:00	24:00:00
9	6	00:00:00	24:00:00
9	7	00:00:00	24:00:00
10	1	09:00:00	22:00:00
10	2	09:00:00	22:00:00
10	3	09:00:00	22:00:00
10	4	09:00:00	22:00:00
10	5	09:00:00	22:00:00
10	6	09:00:00	17:00:00
11	1	08:00:00	22:00:00
11	2	08:00:00	22:00:00
11	3	08:00:00	22:00:00
11	4	08:00:00	22:00:00
11	5	08:00:00	22:00:00
11	6	09:00:00	18:00:00
12	1	08:00:00	21:00:00
12	2	08:00:00	21:00:00
12	3	08:00:00	21:00:00
12	4	08:00:00	21:00:00
12	5	08:00:00	21:00:00
12	6	09:00:00	18:00:00
13	1	09:00:00	21:00:00
13	2	09:00:00	21:00:00
13	3	09:00:00	21:00:00
13	4	09:00:00	21:00:00
13	5	09:00:00	21:00:00
13	6	09:00:00	17:00:00
14	1	09:00:00	21:00:00
14	2	09:00:00	21:00:00
14	3	09:00:00	21:00:00
14	4	09:00:00	21:00:00
14	5	09:00:00	21:00:00
14	6	10:00:00	18:00:00
15	1	09:00:00	20:00:00
15	2	09:00:00	20:00:00
15	3	09:00:00	20:00:00
15	4	09:00:00	20:00:00
15	5	09:00:00	20:00:00
15	6	09:00:00	17:00:00
16	1	09:00:00	18:00:00
16	2	09:00:00	18:00:00
16	3	09:00:00	18:00:00
16	4	09:00:00	18:00:00
16	5	09:00:00	18:00:00
17	1	10:00:00	18:00:00
17	2	10:00:00	18:00:00
17	3	10:00:00	18:00:00
17	4	10:00:00	18:00:00
17	5	10:00:00	18:00:00
17	6	10:00:00	16:00:00
18	1	08:00:00	23:00:00
18	2	08:00:00	23:00:00
18	3	08:00:00	23:00:00
18	4	08:00:00	23:00:00
18	5	08:00:00	23:00:00
18	6	08:00:00	23:00:00
18	7	08:00:00	23:00:00
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.profiles (id, first_name, last_name, university_id, role, created_at) FROM stdin;
ce4d212d-dc26-5d4b-970b-719c3ea9fc2e	Admin	AITU	1	admin	2026-10-11 17:54:36.817683+00
44a51247-0f45-5096-9fca-81ed70346a12	Yerlan	Iskakov	1	student	2026-10-11 17:54:36.817683+00
6f583e12-eb4d-5a2d-9b34-9120b6172fbf	Diana	Amanova	1	student	2026-10-11 17:54:36.817683+00
d6a0339c-e841-56e2-9be8-3c789fb9a47b	Dariga	Serikbayeva	1	student	2026-10-11 17:54:36.817683+00
0631a63b-ebc2-5785-a739-9fee4b48e5bc	Moldir	Tokayeva	1	student	2026-10-11 17:54:36.817683+00
79cab285-6b22-5b1b-b7d0-7fd6f84f6cc6	Nurlan	Tokayev	1	student	2026-10-11 17:54:36.817683+00
bb9f8bce-5de6-54be-a471-3c22fff845f5	Bekzat	Abenov	1	student	2026-10-11 17:54:36.817683+00
ad5b5e1b-07b1-5134-ae83-b16af18abe40	Yerlan	Sadykov	1	student	2026-10-11 17:54:36.817683+00
123a74f4-143d-5603-81d5-6331401ea569	Akbota	Abenova	1	student	2026-10-11 17:54:36.817683+00
289a1a72-f5c0-5531-a5a2-1431eae3980d	Asel	Bekova	1	student	2026-10-11 17:54:36.817683+00
5c29fc1f-628e-5bdc-9e83-3e576df263d4	Aisulu	Mukanova	1	student	2026-10-11 17:54:36.817683+00
594c5eb8-5eba-5db1-9527-7d409b4281ab	Saule	Kuanysheva	1	student	2026-10-11 17:54:36.817683+00
a6a72968-235d-553f-84a7-223f70ff71da	Aigerim	Kuanysheva	1	student	2026-10-11 17:54:36.817683+00
b88dd4ac-02c8-576e-96b7-dad2fcc30210	Dias	Ismailov	1	student	2026-10-11 17:54:36.817683+00
daecc825-1e7a-51cd-a171-4a41488773ae	Tomiris	Sadykova	1	student	2026-10-11 17:54:36.817683+00
384c5afb-bcd3-51c6-a4f0-5bd88bbb4095	Temirlan	Amanov	1	student	2026-10-11 17:54:36.817683+00
bf1b1568-063d-5529-a346-27dcbdb160fc	Adil	Abenov	1	student	2026-10-11 17:54:36.817683+00
bf5483dd-f9be-503e-b843-511fab7772f3	Alisher	Kairatov	1	student	2026-10-11 17:54:36.817683+00
c39ee07c-08d3-51a9-8933-c3f20abe6a2d	Dias	Baimukhanov	1	student	2026-10-11 17:54:36.817683+00
2667ad63-20cd-5653-af95-685a96aec1cb	Askar	Utepov	1	student	2026-10-11 17:54:36.817683+00
841aeb58-3431-5102-81be-941918ee4320	Daniyar	Zhumabekov	1	student	2026-10-11 17:54:36.817683+00
bc586d94-7153-5cf0-8676-68bcb94a0d5a	Nurlan	Baimukhanov	1	student	2026-10-11 17:54:36.817683+00
813640c1-13d1-52ed-b333-486966e596de	Aisulu	Yesenova	1	student	2026-10-11 17:54:36.817683+00
b28f9b27-eccf-51b6-bad2-71b3eb1324e3	Aliya	Zhumabekova	1	student	2026-10-11 17:54:36.817683+00
398c2e60-8a06-5f46-8fb0-e117c255ead8	Alikhan	Tokayev	1	student	2026-10-11 17:54:36.817683+00
8e1f202a-2aae-553d-a9ac-cd2861fc7f0a	Madina	Seitkali	1	student	2026-10-11 17:54:36.817683+00
b4455c9f-c726-58c4-a73d-dc7ac20b4280	Amina	Dosmukhamedova	1	student	2026-10-11 17:54:36.817683+00
22177d59-b6dd-5230-ad3a-3f20a82c77be	Aliya	Omarova	1	student	2026-10-11 17:54:36.817683+00
4375a7a0-75af-50b6-bf34-ac0b79555581	Dariga	Zhakupova	1	student	2026-10-11 17:54:36.817683+00
e1f7cb84-a272-5286-8d3b-6004b94c9fea	Aliya	Dosmukhamedova	1	student	2026-10-11 17:54:36.817683+00
9871575d-9f8d-5ea2-aafb-4cf2d460a9ca	Admin	NU	2	admin	2026-10-11 17:54:36.817683+00
c8bc6f1c-4ede-5ad0-8ec4-f68d5397b37a	Aisulu	Ismailova	2	student	2026-10-11 17:54:36.817683+00
0f4985f0-eea4-5fc5-aba1-78fba1cf698f	Ernar	Rakhimov	2	student	2026-10-11 17:54:36.817683+00
36ac0367-d7e9-532e-9ea6-d2b79a5b9c3b	Adil	Ismailov	2	student	2026-10-11 17:54:36.817683+00
448fc3a2-4bb5-55c5-af6c-daa5b70403fc	Diana	Dosmukhamedova	2	student	2026-10-11 17:54:36.817683+00
2e3914a7-a1d2-5d8c-967c-4fab8cf3f489	Aliya	Baimukhanova	2	student	2026-10-11 17:54:36.817683+00
7106add8-93da-510c-a2ee-43f512e49d3c	Daniyar	Bekov	2	student	2026-10-11 17:54:36.817683+00
c25c9587-af2d-50a5-9cbc-1fdf3302f483	Tomiris	Akhmetova	2	student	2026-10-11 17:54:36.817683+00
18e969e2-d4e6-52f4-8e81-e62265f128f5	Aruzhan	Seitkali	2	student	2026-10-11 17:54:36.817683+00
d44f6451-0c5b-528c-a3a1-c6ec8caf288a	Temirlan	Amanov	2	student	2026-10-11 17:54:36.817683+00
1a2bd399-49fe-58b1-bc67-c6b3fd3246f1	Ayaulym	Kairatova	2	student	2026-10-11 17:54:36.817683+00
3c16f96c-897e-5713-b4ce-ffc817887105	Timur	Utepov	2	student	2026-10-11 17:54:36.817683+00
d39a322b-1a19-5558-a9d5-3d5c1c5f80b0	Alisher	Bekov	2	student	2026-10-11 17:54:36.817683+00
1f63d3e3-cfb5-5ff8-8750-8765e7286e09	Aisulu	Dosmukhamedova	2	student	2026-10-11 17:54:36.817683+00
7f082d5c-a953-51d5-a623-9d610ae577ba	Nurlan	Kairatov	2	student	2026-10-11 17:54:36.817683+00
2614e032-72f6-5f47-b46b-2b6fa25f275a	Diana	Utepova	2	student	2026-10-11 17:54:36.817683+00
60c1d1fe-9756-50b7-aa0c-8938baaddde2	Daniyar	Ismailov	2	student	2026-10-11 17:54:36.817683+00
70a6775f-7bbd-5dff-aa6d-bc15b4445aec	Dana	Sadykova	2	student	2026-10-11 17:54:36.817683+00
9bc90fbb-1ed4-5e71-a722-019e2cc44797	Asel	Kairatova	2	student	2026-10-11 17:54:36.817683+00
cf43eb29-cfc9-5d39-ac2e-0d32e539c990	Amina	Kairatova	2	student	2026-10-11 17:54:36.817683+00
2c6189e6-c56d-5f5e-90e4-3ffcdef88870	Diana	Akhmetova	2	student	2026-10-11 17:54:36.817683+00
7cd65549-6305-538c-bfd9-ff7ee71213eb	Akbota	Kassymova	2	student	2026-10-11 17:54:36.817683+00
9738a135-fb05-52d2-9e40-e18b24491eb4	Daniyar	Kuanyshev	2	student	2026-10-11 17:54:36.817683+00
0550482d-49c2-5f52-a61f-1c4badd27285	Aliya	Nurlanova	2	student	2026-10-11 17:54:36.817683+00
49226873-bb4d-5af8-b6d7-b618b6111788	Miras	Utepov	2	student	2026-10-11 17:54:36.817683+00
8c6deb00-1371-546c-92a3-fa0544ab6f69	Alisher	Zhakupov	2	student	2026-10-11 17:54:36.817683+00
1625ce28-8df4-51c9-9370-e37f4726715d	Kamila	Kuanysheva	2	student	2026-10-11 17:54:36.817683+00
89b01325-f844-5951-8b97-722e76d10e26	Moldir	Omarova	2	student	2026-10-11 17:54:36.817683+00
b7d3ca21-ac8f-59eb-9a27-fefdb02f7c02	Akbota	Abenova	2	student	2026-10-11 17:54:36.817683+00
4b0dd2af-2dab-53ce-87c9-9d33aaeb98e7	Dias	Abenov	2	student	2026-10-11 17:54:36.817683+00
c5bf25b6-4f79-51ef-bcce-ed2d40dcc412	Admin	MNU	3	admin	2026-10-11 17:54:36.817683+00
ee4381b0-e713-5329-accc-f50e1a5ee4f6	Akbota	Tokayeva	3	student	2026-10-11 17:54:36.817683+00
32f48806-1d58-5528-ac5f-f78d0f615e62	Zarina	Nurlanova	3	student	2026-10-11 17:54:36.817683+00
45667a63-75a2-5327-80b3-07277bbc3a05	Maksat	Bekov	3	student	2026-10-11 17:54:36.817683+00
4aed59c4-076a-58ea-8df4-eee688fc3b38	Bekzat	Zhakupov	3	student	2026-10-11 17:54:36.817683+00
7e76cba5-592a-50a9-a6e4-fb36d39a9030	Maksat	Seitkali	3	student	2026-10-11 17:54:36.817683+00
b179af01-a01d-5d62-8805-310edc535f62	Zarina	Akhmetova	3	student	2026-10-11 17:54:36.817683+00
c595e95e-5ae4-58c8-b1f8-4b0d42c28318	Inkar	Omarova	3	student	2026-10-11 17:54:36.817683+00
edb9f7d5-f25d-5618-aed1-d3c8e12572ae	Aruzhan	Iskakova	3	student	2026-10-11 17:54:36.817683+00
c24a9165-fdd8-585f-b441-f68c0c7a3bfe	Olzhas	Tokayev	3	student	2026-10-11 17:54:36.817683+00
3ce15b25-c6e0-583d-a872-0dc16ae45020	Nurlan	Dosmukhamedov	3	student	2026-10-11 17:54:36.817683+00
cd609af0-f2d9-5556-9083-47c78c3e1318	Madina	Ismailova	3	student	2026-10-11 17:54:36.817683+00
ba12ad86-cec0-5c76-b72c-21e59427e8e5	Dariga	Utepova	3	student	2026-10-11 17:54:36.817683+00
5a96375a-4aa6-5b7e-895c-ff70497093dd	Olzhas	Omarov	3	student	2026-10-11 17:54:36.817683+00
8276ebdf-8d22-5cc8-bb2d-d327fc7684d2	Ayaulym	Dosmukhamedova	3	student	2026-10-11 17:54:36.817683+00
b2dc61bc-373b-5d0c-bf25-529d5200c066	Diana	Sadykova	3	student	2026-10-11 17:54:36.817683+00
8557a85b-2ada-524a-9191-e5c392f2ecd0	Dias	Yesenov	3	student	2026-10-11 17:54:36.817683+00
d59eff6d-1910-5844-86ba-5c7c123704de	Zhanel	Omarova	3	student	2026-10-11 17:54:36.817683+00
9630d339-6604-569b-85a5-534d3a118af7	Olzhas	Sadykov	3	student	2026-10-11 17:54:36.817683+00
f131d105-108d-58b0-b737-aee95985fa93	Diana	Yesenova	3	student	2026-10-11 17:54:36.817683+00
d7eb4bfb-e5ec-5046-854b-2d724a29dff3	Saule	Omarova	3	student	2026-10-11 17:54:36.817683+00
efd23983-5f8f-5e47-bba6-22cfcef33110	Timur	Bekov	3	student	2026-10-11 17:54:36.817683+00
b322d3fb-18a5-5119-abc3-151933818abd	Saule	Abenova	3	student	2026-10-11 17:54:36.817683+00
75732734-f0dc-516b-ab8d-647bcd6f7210	Amina	Baimukhanova	3	student	2026-10-11 17:54:36.817683+00
7895e227-7cba-58d0-835e-69c8af3fcc63	Aigerim	Seitkali	3	student	2026-10-11 17:54:36.817683+00
d723f696-83df-5e2e-9b66-1b6668a5bffb	Inkar	Amanova	3	student	2026-10-11 17:54:36.817683+00
511cedf2-bc02-56a1-a754-2540298f5cee	Inkar	Abenova	3	student	2026-10-11 17:54:36.817683+00
12dc5f6c-cb16-5110-abfa-a398961b181a	Alikhan	Zhumabekov	3	student	2026-10-11 17:54:36.817683+00
301d506e-f995-5472-824e-7223eea34b29	Adil	Kairatov	3	student	2026-10-11 17:54:36.817683+00
7caf10cc-bc08-579a-befd-dfa14a46a71b	Asel	Zhakupova	3	student	2026-10-11 17:54:36.817683+00
55d7564d-881c-5453-8a12-ea7124e538f0	Admin	ENU	4	admin	2026-10-11 17:54:36.817683+00
a1aba091-ac3f-5cfb-8f0e-025ddbe56044	Nurlan	Kairatov	4	student	2026-10-11 17:54:36.817683+00
37dd3141-05ee-5e5d-a4f2-fb04179e158b	Malika	Serikbayeva	4	student	2026-10-11 17:54:36.817683+00
1686e8b7-7ab0-56f5-894c-17df38559d0b	Zhanel	Omarova	4	student	2026-10-11 17:54:36.817683+00
7a38a9cf-69bd-5806-a3b3-75c4e3d7cdd1	Olzhas	Zhumabekov	4	student	2026-10-11 17:54:36.817683+00
e57e4f91-200d-5996-8f1f-c4140498ccb5	Sanzhar	Yesenov	4	student	2026-10-11 17:54:36.817683+00
47ac5cee-f468-5dd9-bd2f-994a2e1556fe	Maksat	Iskakov	4	student	2026-10-11 17:54:36.817683+00
333281b0-ea48-5904-bc0d-1baecafb3642	Yersultan	Serikbayev	4	student	2026-10-11 17:54:36.817683+00
0714361c-2671-547c-a5e8-7412dd5f5bb2	Dariga	Rakhimova	4	student	2026-10-11 17:54:36.817683+00
91665b25-1a02-5391-be1f-630466bf5a2f	Aigerim	Ismailova	4	student	2026-10-11 17:54:36.817683+00
f036e23d-5323-5b4f-bb1c-6e87c77bff75	Ernar	Seitkali	4	student	2026-10-11 17:54:36.817683+00
ce4654ab-6f97-5ba5-8e75-a674b62406d8	Kamila	Amanova	4	student	2026-10-11 17:54:36.817683+00
5ab878f5-0da1-5a83-9dd1-f19a741d738e	Arman	Seitkali	4	student	2026-10-11 17:54:36.817683+00
af37d114-6cbb-5069-9e3e-89e207493efa	Zarina	Seitkali	4	student	2026-10-11 17:54:36.817683+00
7e59a7bf-1599-5d03-870a-b80f4a201398	Akbota	Amanova	4	student	2026-10-11 17:54:36.817683+00
e2b516de-c76c-532d-8e53-5d02edbfa4ec	Kamila	Utepova	4	student	2026-10-11 17:54:36.817683+00
bed83121-8bf1-5da8-b173-e725dd4e2e71	Alikhan	Omarov	4	student	2026-10-11 17:54:36.817683+00
d798b580-e0a7-5aa0-b42b-c9509861df97	Timur	Bekov	4	student	2026-10-11 17:54:36.817683+00
1e821e58-daac-52d8-9ff6-668fa3f23828	Timur	Omarov	4	student	2026-10-11 17:54:36.817683+00
c72f74fd-f7ae-5e0d-9c17-09eb9f747580	Zhanel	Rakhimova	4	student	2026-10-11 17:54:36.817683+00
ccd0071a-1fd0-5515-a5b8-937a6bb79b26	Arman	Baimukhanov	4	student	2026-10-11 17:54:36.817683+00
d52c4849-0424-556a-909f-dc1685c34ca7	Miras	Yesenov	4	student	2026-10-11 17:54:36.817683+00
fd594592-8d60-5f8c-be18-349a233ea712	Zarina	Yesenova	4	student	2026-10-11 17:54:36.817683+00
3cfd1e72-fe25-526e-abce-f5c282026b57	Dias	Baimukhanov	4	student	2026-10-11 17:54:36.817683+00
cd999017-1402-5a6e-b041-fdafc8ded0f0	Adil	Kassymov	4	student	2026-10-11 17:54:36.817683+00
4b052f0a-0cb1-59a1-912b-2786fdd40f68	Inkar	Kassymova	4	student	2026-10-11 17:54:36.817683+00
1c41b127-85d5-5028-9e30-ef9cea4990f8	Aisulu	Kairatova	4	student	2026-10-11 17:54:36.817683+00
6b622cf6-d1b3-5243-9b62-bb5d1bc7d70e	Nurlan	Yesenov	4	student	2026-10-11 17:54:36.817683+00
a3692637-7d1e-50da-b993-3a5d101307b0	Tomiris	Kairatova	4	student	2026-10-11 17:54:36.817683+00
10cfe625-92d9-5f2d-8c28-3da5a44180d7	Arman	Iskakov	4	student	2026-10-11 17:54:36.817683+00
\.


--
-- Data for Name: space_activity; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.space_activity (space_id, last_change) FROM stdin;
2	2026-10-11 17:54:36.817683+00
4	2026-10-11 17:54:36.817683+00
3	2026-10-11 17:54:36.817683+00
1	2026-10-11 17:54:36.817683+00
6	2026-10-11 17:54:36.817683+00
5	2026-10-11 17:54:36.817683+00
7	2026-10-11 17:54:36.817683+00
9	2026-10-11 17:54:36.817683+00
8	2026-10-11 17:54:36.817683+00
12	2026-10-11 17:54:36.817683+00
14	2026-10-11 17:54:36.817683+00
11	2026-10-11 17:54:36.817683+00
10	2026-10-11 17:54:36.817683+00
13	2026-10-11 17:54:36.817683+00
15	2026-10-11 17:54:36.817683+00
17	2026-10-11 17:54:36.817683+00
16	2026-10-11 17:54:36.817683+00
18	2026-10-11 17:54:36.817683+00
\.


--
-- Data for Name: study_spaces; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.study_spaces (id, university_id, name, kind, building, floor, description, image_url, image_credit, seat_capacity, outlet_capacity, counts_exact, is_quiet, group_work, food_allowed, map_x, map_y, is_active, updated_at) FROM stdin;
1	1	Library	library	Block C1.1	1st floor	Main university library with soft booths, long tables and bookshelves. Silence zone. library@astanait.edu.kz	assets/img/aitu-library.jpg	\N	250	270	f	t	f	f	11.00	68.00	t	2026-10-11 17:54:36.817683+00
2	1	Open Space	atrium	Block C1.2 · Atrium	1st floor	Bright atrium under the glass roof with modular sofas. Good for group work between classes.	assets/img/aitu-open-space.jpg	\N	70	55	f	f	t	t	50.00	61.00	t	2026-10-11 17:54:36.817683+00
3	1	Coworking	coworking	Block C1.2	1st floor	Large coworking zone with shared desks, sofas and whiteboards next to the atrium.	https://astanait.edu.kz/media/766ad632___________astana_it_university__1_.jpg	astanait.edu.kz	180	25	f	f	t	f	50.00	23.00	t	2026-10-11 17:54:36.817683+00
4	1	Coffeelake	cafe	Block C1	1st floor	Campus coffee shop. Seat and outlet numbers were counted exactly by our team.	assets/img/cover-04-cafe.svg	\N	45	11	t	f	t	t	\N	\N	t	2026-10-11 17:54:36.817683+00
5	2	Library · Astana Room	library	NU Library	\N	The most popular reading room, with the largest number of computers. Open 24/7.	https://2025.ifla.org/wp-content/uploads/2025/03/Nazarbayev-University-Library-8.jpeg	IFLA WLIC 2025	120	140	f	t	f	f	\N	\N	t	2026-10-11 17:54:36.817683+00
6	2	Library · Quiet Room	library	NU Library	\N	Silent room for individual study. No talking, no calls. Open 24/7.	https://2025.ifla.org/wp-content/uploads/2025/03/Nazarbayev-University-Library-7.jpeg	IFLA WLIC 2025	60	60	f	t	f	f	\N	\N	t	2026-10-11 17:54:36.817683+00
7	2	Library · Collaborative Space	coworking	NU Library	\N	Media Room and Collaborative Space for teamwork, trainings and student club meetings.	https://2025.ifla.org/wp-content/uploads/2025/03/Nazarbayev-University-Library-2.jpeg	IFLA WLIC 2025	50	50	f	f	t	f	\N	\N	t	2026-10-11 17:54:36.817683+00
8	2	Multifunctional Room	lounge	Block D1	\N	Student multifunctional room, open around the clock.	assets/img/cover-08-lounge.svg	\N	60	40	f	f	t	t	\N	\N	t	2026-10-11 17:54:36.817683+00
9	2	Study Room D5.124	rooms	Block D5	Room D5.124	Study room in the residential blocks, open 24/7.	assets/img/cover-09-rooms.svg	\N	30	30	f	t	f	f	\N	\N	t	2026-10-11 17:54:36.817683+00
10	3	Public Library	library	Main building	2nd floor	1,051 m² library with ~13,000 books, a mezzanine and a winter garden. Workstations have lights and outlets. Water only.	https://2025.ifla.org/wp-content/uploads/2025/03/Maqsut-Narikbayev-University-Library-2-768x512.jpg	IFLA WLIC 2025	150	120	f	t	f	f	\N	\N	t	2026-10-11 17:54:36.817683+00
11	3	Zebra Coworking	coworking	Main building	2nd floor	Coworking for individual and group work: ergonomic furniture, lit workstations with outlets, discussion areas.	https://mnu.kz/wp-content/uploads/2025/01/by_kana-51-1024x683.webp	mnu.kz	60	60	f	f	t	f	\N	\N	t	2026-10-11 17:54:36.817683+00
12	3	Shaikenov Atrium	atrium	Main building	3rd floor	Open study areas for individual and small-group work, with sound-absorbing design.	assets/img/cover-12-atrium.svg	\N	70	40	f	f	t	f	\N	\N	t	2026-10-11 17:54:36.817683+00
13	3	Team Talk Room	rooms	Main building	1st floor	Six separate rooms for teamwork and project discussions, opposite the library. Multimedia equipment.	https://mnu.kz/wp-content/uploads/2025/01/by_kana-30-683x1024.webp	mnu.kz	36	24	f	f	t	f	\N	\N	t	2026-10-11 17:54:36.817683+00
14	3	Pesochnica	lounge	Main building	Ground floor	Student hub for meetings and events with a multifunctional work area. Hall for up to 80 people.	https://mnu.kz/wp-content/uploads/2025/01/by_kana-9-1024x683.webp	mnu.kz	80	30	f	f	t	t	\N	\N	t	2026-10-11 17:54:36.817683+00
15	4	Scientific Library · Reading Hall	library	Educational building	\N	Open-access reading hall with educational, reference and scientific literature.	https://2025.ifla.org/wp-content/uploads/2025/03/L.N.Gumilyov-Eurasian-National-University-Library-8-768x1024.jpeg	IFLA WLIC 2025	200	80	f	t	f	f	\N	\N	t	2026-10-11 17:54:36.817683+00
16	4	Electronic Reading Room	rooms	Scientific Library	\N	Computers with access to EBSCO and other scientific databases.	https://2025.ifla.org/wp-content/uploads/2025/03/L.N.Gumilyov-Eurasian-National-University-Library-7-768x1024.jpeg	IFLA WLIC 2025	60	70	f	t	f	f	\N	\N	t	2026-10-11 17:54:36.817683+00
17	4	American Corner & Maker Space	coworking	Information Resource Center	\N	Space for group projects, workshops and maker activities.	assets/img/cover-17-coworking.svg	\N	40	40	f	f	t	f	\N	\N	t	2026-10-11 17:54:36.817683+00
18	4	Student House Coworking	lounge	Student House	\N	Coworking zones of the new 2,656-place Student House, made for team-based work.	assets/img/cover-18-lounge.svg	\N	100	80	f	f	t	t	\N	\N	t	2026-10-11 17:54:36.817683+00
\.


--
-- Data for Name: universities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.universities (id, code, name, city, address, map_image_url, map_embed_url, created_at) FROM stdin;
1	AITU	Astana IT University	Astana	Mangilik El Ave 55/11, EXPO Business Center, Block C1	assets/img/aitu-map.jpg	https://yuujiso.github.io/aitumap/	2026-10-11 17:54:36.817683+00
2	NU	Nazarbayev University	Astana	Kabanbay Batyr Ave 53	\N	\N	2026-10-11 17:54:36.817683+00
3	MNU	Maqsut Narikbayev University	Astana	Korgalzhyn Hwy 8	\N	\N	2026-10-11 17:54:36.817683+00
4	ENU	L.N. Gumilyov Eurasian National University	Astana	Satbayev St 2	\N	\N	2026-10-11 17:54:36.817683+00
\.


--
-- Name: audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_log_id_seq', 1, false);


--
-- Name: check_ins_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.check_ins_id_seq', 722, true);


--
-- Name: study_spaces_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.study_spaces_id_seq', 18, true);


--
-- Name: universities_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.universities_id_seq', 4, true);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: check_ins check_ins_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT check_ins_pkey PRIMARY KEY (id);


--
-- Name: email_domains email_domains_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.email_domains
    ADD CONSTRAINT email_domains_pkey PRIMARY KEY (domain);


--
-- Name: favourites favourites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.favourites
    ADD CONSTRAINT favourites_pkey PRIMARY KEY (user_id, space_id);


--
-- Name: opening_hours opening_hours_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.opening_hours
    ADD CONSTRAINT opening_hours_pkey PRIMARY KEY (space_id, weekday);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: space_activity space_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.space_activity
    ADD CONSTRAINT space_activity_pkey PRIMARY KEY (space_id);


--
-- Name: study_spaces study_spaces_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.study_spaces
    ADD CONSTRAINT study_spaces_pkey PRIMARY KEY (id);


--
-- Name: study_spaces study_spaces_university_id_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.study_spaces
    ADD CONSTRAINT study_spaces_university_id_name_key UNIQUE (university_id, name);


--
-- Name: universities universities_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.universities
    ADD CONSTRAINT universities_code_key UNIQUE (code);


--
-- Name: universities universities_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.universities
    ADD CONSTRAINT universities_name_key UNIQUE (name);


--
-- Name: universities universities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.universities
    ADD CONSTRAINT universities_pkey PRIMARY KEY (id);


--
-- Name: check_ins_space_active_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX check_ins_space_active_idx ON public.check_ins USING btree (space_id, expires_at) WHERE (left_at IS NULL);


--
-- Name: check_ins_started_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX check_ins_started_idx ON public.check_ins USING btree (started_at);


--
-- Name: one_open_check_in_per_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX one_open_check_in_per_user ON public.check_ins USING btree (user_id) WHERE (left_at IS NULL);


--
-- Name: space_availability _RETURN; Type: RULE; Schema: public; Owner: postgres
--

CREATE OR REPLACE VIEW public.space_availability AS
 SELECT s.id,
    s.university_id,
    u.code AS university_code,
    s.name,
    s.kind,
    s.building,
    s.floor,
    s.description,
    s.image_url,
    s.image_credit,
    s.seat_capacity,
    s.outlet_capacity,
    s.counts_exact,
    s.is_quiet,
    s.group_work,
    s.food_allowed,
    s.map_x,
    s.map_y,
    GREATEST((s.seat_capacity - count(c.id)), (0)::bigint) AS free_seats,
    GREATEST((s.outlet_capacity - count(c.id) FILTER (WHERE c.uses_outlet)), (0)::bigint) AS free_outlets,
    COALESCE(a.last_change, s.updated_at) AS updated_at,
    COALESCE(( SELECT json_agg(json_build_object('weekday', h.weekday, 'opens', to_char((h.opens)::interval, 'HH24:MI'::text), 'closes', to_char((h.closes)::interval, 'HH24:MI'::text)) ORDER BY h.weekday) AS json_agg
           FROM public.opening_hours h
          WHERE (h.space_id = s.id)), '[]'::json) AS hours
   FROM (((public.study_spaces s
     JOIN public.universities u ON ((u.id = s.university_id)))
     LEFT JOIN public.space_activity a ON ((a.space_id = s.id)))
     LEFT JOIN public.check_ins c ON (((c.space_id = s.id) AND (c.left_at IS NULL) AND (c.expires_at > now()))))
  WHERE s.is_active
  GROUP BY s.id, u.code, a.last_change;


--
-- Name: users on_auth_user_created; Type: TRIGGER; Schema: auth; Owner: postgres
--

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


--
-- Name: check_ins check_ins_before_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER check_ins_before_insert BEFORE INSERT ON public.check_ins FOR EACH ROW EXECUTE FUNCTION public.before_check_in();


--
-- Name: check_ins check_ins_before_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER check_ins_before_update BEFORE UPDATE ON public.check_ins FOR EACH ROW EXECUTE FUNCTION public.before_check_out();


--
-- Name: check_ins check_ins_touch_activity; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER check_ins_touch_activity AFTER INSERT OR UPDATE ON public.check_ins FOR EACH ROW EXECUTE FUNCTION public.touch_space_activity();


--
-- Name: opening_hours opening_hours_audit; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER opening_hours_audit AFTER INSERT OR DELETE OR UPDATE ON public.opening_hours FOR EACH ROW WHEN ((auth.uid() IS NOT NULL)) EXECUTE FUNCTION public.write_audit_log();


--
-- Name: study_spaces study_spaces_audit; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER study_spaces_audit AFTER INSERT OR DELETE OR UPDATE ON public.study_spaces FOR EACH ROW WHEN ((auth.uid() IS NOT NULL)) EXECUTE FUNCTION public.write_audit_log();


--
-- Name: study_spaces study_spaces_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER study_spaces_updated_at BEFORE UPDATE ON public.study_spaces FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: identities identities_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: check_ins check_ins_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT check_ins_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.study_spaces(id) ON DELETE CASCADE;


--
-- Name: check_ins check_ins_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT check_ins_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: email_domains email_domains_university_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.email_domains
    ADD CONSTRAINT email_domains_university_id_fkey FOREIGN KEY (university_id) REFERENCES public.universities(id) ON DELETE CASCADE;


--
-- Name: favourites favourites_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.favourites
    ADD CONSTRAINT favourites_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.study_spaces(id) ON DELETE CASCADE;


--
-- Name: favourites favourites_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.favourites
    ADD CONSTRAINT favourites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: opening_hours opening_hours_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.opening_hours
    ADD CONSTRAINT opening_hours_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.study_spaces(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_university_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_university_id_fkey FOREIGN KEY (university_id) REFERENCES public.universities(id) ON DELETE RESTRICT;


--
-- Name: space_activity space_activity_space_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.space_activity
    ADD CONSTRAINT space_activity_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.study_spaces(id) ON DELETE CASCADE;


--
-- Name: study_spaces study_spaces_university_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.study_spaces
    ADD CONSTRAINT study_spaces_university_id_fkey FOREIGN KEY (university_id) REFERENCES public.universities(id) ON DELETE CASCADE;


--
-- Name: space_activity activity_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY activity_read ON public.space_activity FOR SELECT USING (true);


--
-- Name: audit_log audit_admin_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY audit_admin_read ON public.audit_log FOR SELECT TO authenticated USING (public.is_any_admin());


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: check_ins; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.check_ins ENABLE ROW LEVEL SECURITY;

--
-- Name: check_ins check_ins_own_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY check_ins_own_insert ON public.check_ins FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: check_ins check_ins_own_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY check_ins_own_read ON public.check_ins FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: check_ins check_ins_own_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY check_ins_own_update ON public.check_ins FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: email_domains; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.email_domains ENABLE ROW LEVEL SECURITY;

--
-- Name: email_domains email_domains_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY email_domains_read ON public.email_domains FOR SELECT USING (true);


--
-- Name: favourites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.favourites ENABLE ROW LEVEL SECURITY;

--
-- Name: favourites favourites_own_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY favourites_own_delete ON public.favourites FOR DELETE TO authenticated USING ((user_id = auth.uid()));


--
-- Name: favourites favourites_own_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY favourites_own_insert ON public.favourites FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: favourites favourites_own_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY favourites_own_read ON public.favourites FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: opening_hours hours_admin_all; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY hours_admin_all ON public.opening_hours TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.study_spaces s
  WHERE ((s.id = opening_hours.space_id) AND public.is_admin_of(s.university_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.study_spaces s
  WHERE ((s.id = opening_hours.space_id) AND public.is_admin_of(s.university_id)))));


--
-- Name: opening_hours hours_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY hours_read ON public.opening_hours FOR SELECT USING (true);


--
-- Name: opening_hours; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.opening_hours ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_read_self; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY profiles_read_self ON public.profiles FOR SELECT TO authenticated USING (((id = auth.uid()) OR public.is_admin_of(university_id)));


--
-- Name: profiles profiles_update_self; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY profiles_update_self ON public.profiles FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));


--
-- Name: space_activity; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.space_activity ENABLE ROW LEVEL SECURITY;

--
-- Name: study_spaces spaces_admin_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY spaces_admin_delete ON public.study_spaces FOR DELETE TO authenticated USING (public.is_admin_of(university_id));


--
-- Name: study_spaces spaces_admin_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY spaces_admin_insert ON public.study_spaces FOR INSERT TO authenticated WITH CHECK (public.is_admin_of(university_id));


--
-- Name: study_spaces spaces_admin_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY spaces_admin_update ON public.study_spaces FOR UPDATE TO authenticated USING (public.is_admin_of(university_id)) WITH CHECK (public.is_admin_of(university_id));


--
-- Name: study_spaces spaces_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY spaces_read ON public.study_spaces FOR SELECT USING (true);


--
-- Name: study_spaces; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.study_spaces ENABLE ROW LEVEL SECURITY;

--
-- Name: universities; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.universities ENABLE ROW LEVEL SECURITY;

--
-- Name: universities universities_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY universities_read ON public.universities FOR SELECT USING (true);


--
-- Name: SCHEMA auth; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA auth TO anon;
GRANT USAGE ON SCHEMA auth TO authenticated;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;


--
-- Name: FUNCTION uid(); Type: ACL; Schema: auth; Owner: postgres
--

GRANT ALL ON FUNCTION auth.uid() TO anon;
GRANT ALL ON FUNCTION auth.uid() TO authenticated;


--
-- Name: FUNCTION admin_usage_by_hour(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.admin_usage_by_hour() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_usage_by_hour() TO authenticated;


--
-- Name: FUNCTION before_check_in(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.before_check_in() FROM PUBLIC;


--
-- Name: FUNCTION before_check_out(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.before_check_out() FROM PUBLIC;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;


--
-- Name: FUNCTION is_admin_of(p_university smallint); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_admin_of(p_university smallint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_admin_of(p_university smallint) TO authenticated;


--
-- Name: FUNCTION is_any_admin(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_any_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_any_admin() TO authenticated;


--
-- Name: FUNCTION set_updated_at(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC;


--
-- Name: FUNCTION touch_space_activity(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.touch_space_activity() FROM PUBLIC;


--
-- Name: FUNCTION write_audit_log(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.write_audit_log() FROM PUBLIC;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.audit_log TO authenticated;


--
-- Name: TABLE check_ins; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.check_ins TO authenticated;


--
-- Name: COLUMN check_ins.user_id; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT(user_id) ON TABLE public.check_ins TO authenticated;


--
-- Name: COLUMN check_ins.space_id; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT(space_id) ON TABLE public.check_ins TO authenticated;


--
-- Name: COLUMN check_ins.uses_outlet; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT(uses_outlet) ON TABLE public.check_ins TO authenticated;


--
-- Name: COLUMN check_ins.started_at; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT(started_at) ON TABLE public.check_ins TO authenticated;


--
-- Name: COLUMN check_ins.expires_at; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT(expires_at) ON TABLE public.check_ins TO authenticated;


--
-- Name: COLUMN check_ins.left_at; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(left_at) ON TABLE public.check_ins TO authenticated;


--
-- Name: TABLE email_domains; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.email_domains TO anon;
GRANT SELECT ON TABLE public.email_domains TO authenticated;


--
-- Name: TABLE favourites; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE ON TABLE public.favourites TO authenticated;


--
-- Name: TABLE opening_hours; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.opening_hours TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.opening_hours TO authenticated;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.profiles TO authenticated;


--
-- Name: COLUMN profiles.first_name; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(first_name) ON TABLE public.profiles TO authenticated;


--
-- Name: COLUMN profiles.last_name; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(last_name) ON TABLE public.profiles TO authenticated;


--
-- Name: TABLE space_activity; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.space_activity TO anon;
GRANT SELECT ON TABLE public.space_activity TO authenticated;


--
-- Name: TABLE space_availability; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.space_availability TO anon;
GRANT SELECT ON TABLE public.space_availability TO authenticated;


--
-- Name: TABLE study_spaces; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.study_spaces TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.study_spaces TO authenticated;


--
-- Name: TABLE universities; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.universities TO anon;
GRANT SELECT ON TABLE public.universities TO authenticated;


--
-- PostgreSQL database dump complete
--

\unrestrict vfcdKcZWiTjUL8AviJKZblRnnoAZNqqPRexgYCAquPvZG9wlUgWoQEG0YyDj6fK

