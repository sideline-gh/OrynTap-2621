-- =====================================================================
-- OrynTap — LOCAL POSTGRESQL ONLY (skip this file on Supabase!)
-- ---------------------------------------------------------------------
-- Supabase already provides the `auth` schema, the `anon` /
-- `authenticated` roles and the realtime publication. This shim
-- recreates the minimum of those so that 01_schema.sql and 02_seed.sql
-- run unchanged on a plain PostgreSQL 14+ (pgAdmin / psql) for an
-- offline demo at the defense.
-- Run order locally:  00_local_shim.sql -> 01_schema.sql -> 02_seed.sql
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS auth;

-- Minimal copy of Supabase's auth.users (only the columns we use)
CREATE TABLE IF NOT EXISTS auth.users (
  instance_id          uuid,
  id                   uuid PRIMARY KEY,
  aud                  varchar(255),
  role                 varchar(255),
  email                varchar(255) UNIQUE,
  encrypted_password   varchar(255),
  email_confirmed_at   timestamptz,
  raw_app_meta_data    jsonb,
  raw_user_meta_data   jsonb,
  created_at           timestamptz,
  updated_at           timestamptz,
  confirmation_token   varchar(255),
  recovery_token       varchar(255),
  email_change_token_new varchar(255),
  email_change         varchar(255)
);

CREATE TABLE IF NOT EXISTS auth.identities (
  id              uuid PRIMARY KEY,
  user_id         uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  provider_id     text,
  identity_data   jsonb,
  provider        text,
  last_sign_in_at timestamptz,
  created_at      timestamptz,
  updated_at      timestamptz
);

-- In Supabase auth.uid() reads the logged-in user's id from the JWT.
-- Locally you can impersonate a user with:
--   SET request.jwt.claim.sub = '<uuid>';  SET ROLE authenticated;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;
