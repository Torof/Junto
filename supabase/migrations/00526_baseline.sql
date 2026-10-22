-- 00526 baseline — the whole database as migrated (MIGRATION_PLAN v7).
-- Earlier migrations live in supabase/migrations_archive/ (history only, never replayed).

-- ===== 05_target_guard.sql =====
DO $$ BEGIN
  IF to_regnamespace('private') IS NOT NULL THEN RAISE EXCEPTION 'schema private already exists: not a fresh project'; END IF;
  IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r', 'v', 'm'))
  THEN RAISE EXCEPTION 'schema public is not empty: not a fresh project'; END IF;
  IF NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user)
  THEN RAISE EXCEPTION 'the build role cannot bypass RLS (reference data load would fail)'; END IF;
END $$;

-- ===== 10_extensions.sql =====
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron;
DROP EXTENSION IF EXISTS pg_graphql;
DO $$ BEGIN
  IF (SELECT n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'postgis') <> 'extensions'
  THEN RAISE EXCEPTION 'PostGIS is not in the extensions schema'; END IF;
END $$;

-- ===== 20_default_privileges_pristine.sql =====
ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL ON TABLES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;
DO $$ BEGIN
  -- Pristine = no entry for postgres (global or public) grants anything to anyone but postgres.
  IF EXISTS (SELECT 1 FROM pg_default_acl d CROSS JOIN LATERAL aclexplode(d.defaclacl) a
             WHERE d.defaclrole = 'postgres'::regrole
               AND (d.defaclnamespace = 0 OR d.defaclnamespace = 'public'::regnamespace)
               AND a.grantee <> 'postgres'::regrole
               AND NOT (d.defaclnamespace = 0 AND d.defaclobjtype = 'f' AND a.grantee = 0))
  THEN RAISE EXCEPTION 'default privileges are not pristine'; END IF;
END $$;

-- ===== 30_schema.sql =====
--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: private; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA private;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: assert_approved_pro(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.assert_approved_pro(p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM users u
    JOIN pro_profiles pp ON pp.user_id = u.id
    WHERE u.id = p_user_id
      AND u.tier = 'pro'
      AND u.suspended_at IS NULL
      AND pp.status = 'approved'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;


--
-- Name: assert_can_send(uuid, uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.assert_can_send(p_conversation_id uuid, p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_conv RECORD;
  v_other UUID;
BEGIN
  SELECT id, type, status, user_1, user_2, activity_id INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: a group taken down by moderation is read-only.
  IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conv.id AND moderated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT private.is_conversation_member(p_conversation_id, p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_conv.type = 'dm' THEN
    IF v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_other := CASE WHEN v_conv.user_1 = p_user_id THEN v_conv.user_2 ELSE v_conv.user_1 END;
    IF EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = p_user_id AND blocked_id = v_other)
         OR (blocker_id = v_other AND blocked_id = p_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  ELSIF v_conv.type = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = v_conv.activity_id AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  ELSIF v_conv.type = 'channel' THEN
    -- Ban is authoritative on the send path (defense against a join/remove race
    -- that could leave a banned user with a stale membership row).
    IF EXISTS (
      SELECT 1 FROM channel_bans
      WHERE conversation_id = p_conversation_id AND user_id = p_user_id
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  END IF;
END;
$$;


--
-- Name: award_on_late_presence(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.award_on_late_presence() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.confirmed_present IS TRUE AND OLD.confirmed_present IS DISTINCT FROM TRUE
     AND NEW.status = 'accepted'
     AND EXISTS (SELECT 1 FROM activities a WHERE a.id = NEW.activity_id
                 AND a.status = 'completed' AND a.deleted_at IS NULL) THEN
    PERFORM award_badge_progression(NEW.user_id, false);
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: ban_email_on_suspended_delete(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.ban_email_on_suspended_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_auth_email TEXT;
BEGIN
  IF OLD.suspended_at IS NULL THEN RETURN OLD; END IF;
  SELECT email INTO v_auth_email FROM auth.users WHERE id = OLD.id;
  -- Both the profile e-mail and the current login e-mail (changed meanwhile?).
  INSERT INTO banned_email_hashes (email_hash)
  SELECT h FROM (VALUES (private.email_hash(OLD.email)), (private.email_hash(v_auth_email))) v(h)
  WHERE h IS NOT NULL
  ON CONFLICT (email_hash) DO NOTHING;
  RETURN OLD;
END;
$$;


--
-- Name: broadcast_message_update(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.broadcast_message_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity UUID;
BEGIN
  IF NEW.content IS NOT DISTINCT FROM OLD.content AND NEW.deleted_at IS NOT DISTINCT FROM OLD.deleted_at THEN
    RETURN NEW;
  END IF;
  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('table', 'messages', 'op', 'UPDATE',
                         'conversation_id', NEW.conversation_id, 'message_id', NEW.id),
      'change', 'conversation:' || NEW.conversation_id::text, true);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  SELECT activity_id INTO v_activity FROM conversations
  WHERE id = NEW.conversation_id AND type = 'activity';
  IF v_activity IS NOT NULL THEN
    BEGIN
      PERFORM realtime.send(
        jsonb_build_object('table', 'messages', 'op', 'UPDATE', 'conversation_id', NEW.conversation_id),
        'wall', 'activity:' || v_activity::text, true);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: check_avatar_url(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.check_avatar_url() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- Only the person editing their own profile (demo seeding by an admin and
  -- system writes keep their URLs). NOTE migration: project host below.
  IF auth.uid() IS DISTINCT FROM NEW.id THEN RETURN NEW; END IF;
  IF NEW.avatar_url IS NOT DISTINCT FROM OLD.avatar_url OR NEW.avatar_url IS NULL THEN RETURN NEW; END IF;
  IF private.project_url() IS NULL  -- 00524: fail-closed without a project URL
     OR NEW.avatar_url NOT LIKE private.project_url() || '/storage/v1/object/public/avatars/' || NEW.id::text || '/%'
     OR NEW.avatar_url ~* '(\.\.|%2e|%2f|%5c|\\)' THEN  -- 00503: no climbing out of the folder
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: check_schedule_conflict(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.check_schedule_conflict() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_range TSTZRANGE;
BEGIN
  -- 00503: a join REQUEST (pending) is checked too, for the requester
  -- only — otherwise the organiser who accepts later learns of another outing.
  IF NEW.status NOT IN ('accepted', 'pending') THEN RETURN NEW; END IF;
  IF NEW.status = 'pending' AND auth.uid() IS DISTINCT FROM NEW.user_id THEN RETURN NEW; END IF;
  -- System writes (scheduled jobs, demo seeding) have no end user.
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'accepted' THEN RETURN NEW; END IF;

  SELECT tstzrange(a.starts_at, a.starts_at + a.duration) INTO v_range
  FROM activities a
  WHERE a.id = NEW.activity_id AND NOT a.is_demo AND a.deleted_at IS NULL;
  IF v_range IS NULL THEN RETURN NEW; END IF;

  -- Serialise this person's acceptances (two joins at once).
  PERFORM pg_advisory_xact_lock(hashtext('schedule:' || NEW.user_id::text));

  IF EXISTS (
    SELECT 1 FROM participations p
    JOIN activities a ON a.id = p.activity_id
    WHERE p.user_id = NEW.user_id
      AND p.status = 'accepted'
      AND p.activity_id <> NEW.activity_id
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
      AND NOT a.is_demo
      AND tstzrange(a.starts_at, a.starts_at + a.duration) && v_range
  ) THEN
    IF auth.uid() IS NOT DISTINCT FROM NEW.user_id THEN
      RAISE EXCEPTION 'junto.schedule_conflict';
    ELSE
      RAISE EXCEPTION 'junto.participant_schedule_conflict';
    END IF;
  END IF;
  -- 00520 (C6): once accepted somewhere, the person's overlapping pending
  -- requests are withdrawn — no organiser can probe their schedule later.
  IF NEW.status = 'accepted' THEN
    UPDATE participations p SET status = 'withdrawn'
    FROM activities a
    WHERE p.user_id = NEW.user_id AND p.status = 'pending' AND p.activity_id <> NEW.activity_id
      AND a.id = p.activity_id AND a.deleted_at IS NULL AND NOT a.is_demo
      AND tstzrange(a.starts_at, a.starts_at + a.duration) && v_range;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: check_shared_outing_block(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.check_shared_outing_block() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.status NOT IN ('accepted', 'pending') THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN RETURN NEW; END IF;
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;  -- system writes (demo seeding)
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = NEW.activity_id AND a.is_demo) THEN RETURN NEW; END IF;
  -- Someone already in the outing (organiser included) who BLOCKED the newcomer:
  -- generic refusal (never tell who blocks whom).
  IF EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE b.blocked_id = NEW.user_id
      AND (b.blocker_id IN (SELECT p.user_id FROM participations p
                            WHERE p.activity_id = NEW.activity_id AND p.status = 'accepted' AND p.user_id <> NEW.user_id)
           OR b.blocker_id = (SELECT a.creator_id FROM activities a WHERE a.id = NEW.activity_id))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- The newcomer blocked someone already in it: they know it, say it.
  IF EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE b.blocker_id = NEW.user_id
      AND b.blocked_id IN (SELECT p.user_id FROM participations p
                           WHERE p.activity_id = NEW.activity_id AND p.status = 'accepted' AND p.user_id <> NEW.user_id)
  ) THEN
    -- 00522 (F1): the coded message only to the person joining (it is about
    -- their own block) — an organiser accepting them gets the generic one.
    IF auth.uid() = NEW.user_id THEN RAISE EXCEPTION 'junto.blocked_member_present'; END IF;
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: clear_stale_join_request(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.clear_stale_join_request() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF OLD.status = 'pending' AND NEW.status IN ('withdrawn', 'expired', 'refused') THEN
    DELETE FROM notifications n
    USING activities a
    WHERE a.id = NEW.activity_id
      AND n.user_id = a.creator_id
      AND n.type = 'join_request'
      AND n.read_at IS NULL
      AND n.data->>'activity_id' = NEW.activity_id::text
      AND n.data->>'requester_id' = NEW.user_id::text;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: email_hash(text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.email_hash(p_email text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
  SELECT CASE WHEN p_email IS NULL OR position('@' in p_email) = 0 THEN NULL ELSE
    encode(extensions.hmac(
      -- 00513: Gmail ignores dots in the local part, and googlemail.com = gmail.com.
      CASE WHEN split_part(lower(trim(p_email)), '@', 2) IN ('gmail.com', 'googlemail.com')
        THEN replace(regexp_replace(split_part(lower(trim(p_email)), '@', 1), '\+.*$', ''), '.', '') || '@gmail.com'
        ELSE regexp_replace(split_part(lower(trim(p_email)), '@', 1), '\+.*$', '') || '@' || split_part(lower(trim(p_email)), '@', 2) END,
      (SELECT value FROM app_config WHERE name = 'email_ban_pepper'), 'sha256'), 'hex') END;
$_$;


--
-- Name: email_is_banned(text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.email_is_banned(p_email text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM banned_email_hashes WHERE email_hash = private.email_hash(p_email));
$$;


--
-- Name: insert_rich_message(uuid, uuid, text, jsonb); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.insert_rich_message(p_conversation_id uuid, p_sender_id uuid, p_content text, p_metadata jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO messages (conversation_id, sender_id, content, metadata)
  VALUES (p_conversation_id, p_sender_id, p_content, p_metadata)
  RETURNING id INTO v_id;
  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id AND hidden_at IS NOT NULL;
  RETURN v_id;
END;
$$;


--
-- Name: is_conversation_member(uuid, uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.is_conversation_member(p_conversation_id uuid, p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM conversation_members
    WHERE conversation_id = p_conversation_id AND user_id = p_user_id
  )
  -- 00514: a suspended account reads no conversation any more.
  AND NOT private.user_is_suspended(p_user_id);
$$;


--
-- Name: is_messaging_eligible(uuid, uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.is_messaging_eligible(p_caller uuid, p_target uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.type = 'dm'
        AND c.user_1 = LEAST(p_caller, p_target)
        AND c.user_2 = GREATEST(p_caller, p_target)
    ) THEN COALESCE((
      SELECT c.status = 'active' FROM conversations c
      WHERE c.type = 'dm'
        AND c.user_1 = LEAST(p_caller, p_target)
        AND c.user_2 = GREATEST(p_caller, p_target)
    ), false)
    ELSE EXISTS (
      SELECT 1
      FROM participations pc
      JOIN participations pt ON pt.activity_id = pc.activity_id
      JOIN activities a ON a.id = pc.activity_id
      WHERE pc.user_id = p_caller AND pc.status = 'accepted' AND pc.confirmed_present = true
        AND pt.user_id = p_target AND pt.status = 'accepted'
        AND a.deleted_at IS NULL
        AND a.status NOT IN ('cancelled', 'expired')
        AND a.starts_at <= now()
        AND a.starts_at > now() - INTERVAL '180 days'
    )
  END;
$$;


--
-- Name: level_tier(text, text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.level_tier(p_sport_key text, p_level text) RETURNS smallint
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  SELECT CASE
    WHEN p_level IS NULL THEN NULL
    WHEN lower(p_level) IN ('débutant', 'beginner') THEN 0
    WHEN lower(p_level) IN ('intermédiaire', 'intermediate') THEN 1
    WHEN lower(p_level) IN ('avancé', 'advanced') THEN 2
    WHEN lower(p_level) = 'expert' THEN 3
    ELSE (
      SELECT v.tier::smallint FROM (VALUES
        ('fr','5a',0),('fr','5b',0),('fr','5c',0),('fr','6a',1),('fr','6b',1),('fr','6c',1),
        ('fr','7a',2),('fr','7b',2),('fr','7c',2),('fr','8a',3),('fr','8b',3),('fr','8c',3),
        ('font','5',0),('font','6a',1),('font','6b',1),('font','6c',1),('font','7a',2),('font','7b',2),('font','7c',2),('font','8a',3),
        ('alpine','f',0),('alpine','pd',1),('alpine','ad',1),('alpine','d',2),('alpine','td',2),('alpine','ed',3),
        ('ice','wi3',1),('ice','wi4',2),('ice','wi5',2),('ice','wi6',3),
        ('dry','m5',1),('dry','m6',1),('dry','m7',2),('dry','m8',2),('dry','m9',3),
        ('vf','pd',0),('vf','ad',1),('vf','d',2),('vf','td',2),('vf','ed',3),
        ('canyon','v2',0),('canyon','v3',1),('canyon','v4',1),('canyon','v5',2),('canyon','v6',2),('canyon','v7',3),
        ('ww','classe ii',0),('ww','classe iii',1),('ww','classe iv',2),('ww','classe v',3),
        ('ski','s1',0),('ski','s2',1),('ski','s3',2),('ski','s4',2),('ski','s5',3),
        ('piste','vert',0),('piste','bleu',1),('piste','rouge',2),('piste','noir',3),
        ('fly','découverte',0),('fly','brevet en cours',0),('fly','pilote autonome',1),('fly','confirmé',2),
        ('dive','n1',0),('dive','n2',1),('dive','n3',2),('dive','n4',3),
        ('apnea','découverte',0),('apnea','10-20 m',1),('apnea','20-30 m',2),('apnea','30 m+',3)
      ) AS v(scale, label, tier)
      WHERE v.label = lower(p_level)
        AND v.scale = CASE p_sport_key
          WHEN 'climbing-sport' THEN 'fr' WHEN 'climbing-multipitch' THEN 'fr'
          WHEN 'bouldering' THEN 'font' WHEN 'mountaineering' THEN 'alpine'
          WHEN 'ice-climbing' THEN 'ice' WHEN 'dry-tooling' THEN 'dry'
          WHEN 'via-ferrata' THEN 'vf' WHEN 'canyoning' THEN 'canyon'
          WHEN 'kayaking' THEN 'ww' WHEN 'canoe' THEN 'ww' WHEN 'rafting' THEN 'ww'
          WHEN 'ski-touring' THEN 'ski' WHEN 'ski-freeride' THEN 'ski' WHEN 'splitboard' THEN 'ski'
          WHEN 'skiing' THEN 'piste' WHEN 'snowboarding' THEN 'piste'
          WHEN 'mtb-xc' THEN 'piste' WHEN 'mtb-enduro' THEN 'piste' WHEN 'mtb-downhill' THEN 'piste'
          WHEN 'paragliding' THEN 'fly' WHEN 'speed-riding' THEN 'fly' WHEN 'hang-gliding' THEN 'fly'
          WHEN 'diving' THEN 'dive' WHEN 'freediving' THEN 'apnea'
          ELSE NULL END
    )
  END;
$$;


--
-- Name: message_author_visible(uuid, uuid, uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.message_author_visible(p_conversation_id uuid, p_sender_id uuid, p_viewer_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT
    p_sender_id IS NULL  -- system message (deleted author): always visible
    OR (
      -- ACTIVITY, GROUP, CHANNEL (00485, MS-1): hide authors the viewer blocked,
      -- or suspended authors (wall parity 00324).
      NOT (
        EXISTS (SELECT 1 FROM conversations c WHERE c.id = p_conversation_id AND c.type IN ('activity', 'group', 'channel'))
        AND (
          EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_viewer_id AND blocked_id = p_sender_id)
          OR private.user_is_suspended(p_sender_id)
        )
      )
      -- DM: hide the whole thread if a block exists between the two parties,
      -- either direction (restores 00031 private_messages_select behaviour).
      AND NOT EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = p_conversation_id AND c.type = 'dm'
          AND EXISTS (
            SELECT 1 FROM blocked_users b
            WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
               OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
          )
      )
    );
$$;


--
-- Name: notify_pro_renamed(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.notify_pro_renamed() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_admin UUID;
BEGIN
  IF NEW.status <> 'approved' OR NEW.display_name IS NOT DISTINCT FROM OLD.display_name THEN RETURN NULL; END IF;
  FOR v_admin IN SELECT id FROM users WHERE is_admin AND suspended_at IS NULL LOOP
    -- 00522 (F6): one notice per pro and admin a day (rename loops).
    CONTINUE WHEN EXISTS (SELECT 1 FROM notifications n WHERE n.user_id = v_admin AND n.type = 'pro_renamed'
                          AND n.data->>'pro_id' = NEW.user_id::text AND n.created_at > now() - INTERVAL '1 day');
    PERFORM create_notification(v_admin, 'pro_renamed', 'Vitrine pro renommée',
      sanitize_notif_text(coalesce(OLD.display_name, '?')) || ' → ' || sanitize_notif_text(coalesce(NEW.display_name, '?')),
      jsonb_build_object('pro_id', NEW.user_id,
        'params', jsonb_build_object('old', sanitize_notif_text(coalesce(OLD.display_name, '?')), 'new', sanitize_notif_text(coalesce(NEW.display_name, '?')))));
  END LOOP;
  RETURN NULL;
END;
$$;


--
-- Name: offering_duration_ok(text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.offering_duration_ok(p text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public'
    AS $$
BEGIN
  RETURN p::interval BETWEEN INTERVAL '15 minutes' AND INTERVAL '30 days';
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;


--
-- Name: private_activity_access(uuid, uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.private_activity_access(p_activity_id uuid, p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT
    -- 00489: never for someone the organiser removed or blocked.
    NOT EXISTS (SELECT 1 FROM participations p
                WHERE p.activity_id = p_activity_id AND p.user_id = p_user_id AND p.status = 'removed')
    AND NOT EXISTS (SELECT 1 FROM activities a JOIN blocked_users b
                      ON b.blocker_id = a.creator_id AND b.blocked_id = p_user_id
                    WHERE a.id = p_activity_id)
    AND (
      EXISTS (
        SELECT 1 FROM invite_grants g
        WHERE g.activity_id = p_activity_id AND g.user_id = p_user_id
          AND g.at > now() - INTERVAL '30 days')
      -- 00489: someone who had joined and withdrew can come back from history.
      OR EXISTS (SELECT 1 FROM participations p
                 WHERE p.activity_id = p_activity_id AND p.user_id = p_user_id AND p.status = 'withdrawn')
      OR EXISTS (
        -- Shared by the organiser in a DIRECT conversation with this account
        -- (00489: not groups / channels, whose membership changes later).
        SELECT 1 FROM activities a
        JOIN messages m ON m.sender_id = a.creator_id
        JOIN conversations c ON c.id = m.conversation_id AND c.type = 'dm'
        JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = p_user_id
        WHERE a.id = p_activity_id
          AND m.deleted_at IS NULL
          AND m.metadata->>'type' = 'shared_activity'
          AND m.metadata->>'activity_id' = p_activity_id::text)
    );
$$;


--
-- Name: pro_photo_url_ok(text, uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.pro_photo_url_ok(p_url text, p_uid uuid) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  SELECT p_url IS NOT NULL
     AND char_length(p_url) BETWEEN 1 AND 500
     -- 00524: host from app_config; NULL (missing URL) counts as refused.
     AND coalesce(p_url LIKE private.project_url() || '/storage/v1/object/public/pro-photos/' || p_uid::text || '/%', false)
     -- 00501 (PO-8): no path climbing out of the own folder (« .. », encoded or not).
     AND p_url !~* '(\.\.|%2e|%2f|%5c|\\)';
$$;


--
-- Name: project_url(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.project_url() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
  SELECT value FROM app_config
  WHERE name = 'project_url' AND value ~ '^https://[a-z0-9-]+(\.[a-z0-9-]+)+$';
$_$;


--
-- Name: rate_hit(text, integer, interval); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.rate_hit(p_kind text, p_limit integer, p_window interval) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user UUID := auth.uid();
  v_count INTEGER;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_rate_' || p_kind));
  SELECT count(*) INTO v_count FROM rate_events
  WHERE user_id = v_user AND kind = p_kind AND at > now() - p_window;
  IF v_count >= p_limit THEN RAISE EXCEPTION 'junto.too_many_actions'; END IF;
  INSERT INTO rate_events (user_id, kind) VALUES (v_user, p_kind);
END;
$$;


--
-- Name: refuse_banned_email_change(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.refuse_banned_email_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.email IS DISTINCT FROM OLD.email AND private.email_is_banned(NEW.email) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: require_onboarded_actor(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.require_onboarded_actor() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_actor UUID := auth.uid();
BEGIN
  -- Scheduled jobs and service tasks have no end user: nothing to check.
  IF v_actor IS NULL THEN RETURN NEW; END IF;
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.id = v_actor
                 AND u.age_confirmed_at IS NOT NULL AND u.accepted_tos_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: seat_cleanup_on_participation_loss(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.seat_cleanup_on_participation_loss() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_act RECORD;
  v_req RECORD;
  v_name TEXT;
BEGIN
  IF NOT (OLD.status = 'accepted' AND NEW.status IS DISTINCT FROM 'accepted') THEN
    RETURN NEW;
  END IF;
  SELECT id, title, status, deleted_at INTO v_act FROM activities WHERE id = NEW.activity_id;
  SELECT display_name INTO v_name FROM public_profiles WHERE id = NEW.user_id;

  -- As a passenger: pending requests withdrawn; the accepted seat freed
  -- (seat given back by trg_seat_requests_release) and its driver told.
  FOR v_req IN
    SELECT id, driver_id, status FROM seat_requests
    WHERE activity_id = NEW.activity_id AND requester_id = NEW.user_id
      AND status IN ('pending', 'accepted')
    FOR UPDATE
  LOOP
    UPDATE seat_requests SET status = 'cancelled' WHERE id = v_req.id;
    IF v_req.status = 'accepted' AND v_act.status IN ('published', 'in_progress') AND v_act.deleted_at IS NULL THEN
      PERFORM create_notification(
        v_req.driver_id,
        'seat_passenger_left',
        'Place libérée',
        coalesce(v_name, 'Ton passager') || ' ne participe plus à « ' || v_act.title || ' » — sa place dans ta voiture est libérée',
        jsonb_build_object('activity_id', NEW.activity_id,
          'params', jsonb_build_object('name', coalesce(v_name, 'Ton passager'), 'title', v_act.title))
      );
    END IF;
  END LOOP;

  -- As a driver: every passenger (pending or seated) is released and told.
  FOR v_req IN
    SELECT id, requester_id FROM seat_requests
    WHERE activity_id = NEW.activity_id AND driver_id = NEW.user_id
      AND status IN ('pending', 'accepted')
    FOR UPDATE
  LOOP
    UPDATE seat_requests SET status = 'cancelled' WHERE id = v_req.id;
    IF v_act.status IN ('published', 'in_progress') AND v_act.deleted_at IS NULL THEN
      PERFORM create_notification(
        v_req.requester_id,
        'driver_left',
        'Place annulée',
        coalesce(v_name, 'Le conducteur') || ' a quitté « ' || v_act.title || ' » — trouve une autre place',
        jsonb_build_object('activity_id', NEW.activity_id, 'driver_id', NEW.user_id,
          'params', jsonb_build_object('name', coalesce(v_name, 'Le conducteur'), 'title', v_act.title))
      );
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;


--
-- Name: seat_release_on_end(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.seat_release_on_end() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF OLD.status = 'accepted' AND NEW.status IN ('cancelled', 'expired') THEN
    UPDATE participations
    SET transport_seats = LEAST(COALESCE(transport_seats, 0) + 1, 8)
    WHERE activity_id = NEW.activity_id AND user_id = NEW.driver_id
      AND status = 'accepted' AND transport_type = 'car';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: stamp_accepted_at(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.stamp_accepted_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.status = 'accepted' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'accepted') THEN
    NEW.accepted_at := now();
    NEW.accepted_via := CASE
      WHEN TG_OP = 'UPDATE' AND OLD.status = 'pending' THEN 'organiser'
      WHEN TG_OP = 'UPDATE' AND OLD.status = 'invited' THEN 'invitation'
      ELSE 'self' END;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.accepted_at := CASE WHEN NEW.status = 'accepted' THEN OLD.accepted_at END;
    NEW.accepted_via := CASE WHEN NEW.status = 'accepted' THEN OLD.accepted_via END;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: storage_object_quota(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.storage_object_quota() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_folder TEXT := (storage.foldername(NEW.name))[1];
  -- 00522 (F4): uploads per DAY, not files kept — replaced photos stay as
  -- orphans in storage, so a lifetime count would lock active pros out.
  v_cap INTEGER := CASE NEW.bucket_id WHEN 'avatars' THEN 20 WHEN 'pro-photos' THEN 100 WHEN 'channel-photos' THEN 30 ELSE NULL END;
BEGIN
  IF v_cap IS NULL OR auth.uid() IS NULL THEN RETURN NEW; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('storage:' || NEW.bucket_id || ':' || coalesce(v_folder, '')));
  IF (SELECT count(*) FROM storage.objects o
      WHERE o.bucket_id = NEW.bucket_id AND (storage.foldername(o.name))[1] = v_folder
        AND o.created_at > now() - INTERVAL '1 day') >= v_cap THEN
    RAISE EXCEPTION 'junto.storage_quota';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: today_paris(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.today_paris() RETURNS date
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  SELECT (now() AT TIME ZONE 'Europe/Paris')::date;
$$;


--
-- Name: user_is_suspended(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.user_is_suspended(p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM users WHERE id = p_user_id AND suspended_at IS NOT NULL
  );
$$;


--
-- Name: accept_activity_invitation(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_activity_invitation(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_row RECORD;
  v_count INTEGER;
  v_updated INTEGER;
  v_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, deleted_at, max_participants, title INTO v_activity
  FROM activities WHERE id = p_activity_id
  FOR UPDATE;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00516: once the presence check window of a started outing has passed,
  -- nobody joins any more (they could no longer validate, and could tip a
  -- 2-person outing into the 3+ rule).
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.requires_presence
             AND now() > a.starts_at + INTERVAL '15 minutes') THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  -- 00496 (AC-11 / BR-4): not a suspended or blocking organiser's outing,
  -- and only from an onboarded account (accepting is an action).
  IF private.user_is_suspended(v_activity.creator_id)
     OR EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id)
     OR NOT EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.age_confirmed_at IS NOT NULL AND u.accepted_tos_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id INTO v_row FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'invited';
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT count(*) INTO v_count FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
  WHERE id = v_row.id AND status = 'invited';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  -- Row vanished between the SELECT and the UPDATE (concurrent decline / block
  -- cascade, which don't take the activity lock) → no phantom success/push.
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT display_name INTO v_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_activity.creator_id, 'invitation_accepted',
    coalesce(v_name, 'Quelqu''un') || ' a accepté ton invitation',
    '« ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g') || ' »',
    jsonb_build_object('activity_id', p_activity_id,
      'params', jsonb_build_object('name', coalesce(v_name, 'Quelqu''un'), 'title', regexp_replace(v_activity.title, '<[^>]*>', '', 'g')))
  );
END;
$$;


--
-- Name: accept_booking(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_booking(p_booking_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_pro_name TEXT;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_updated INTEGER;
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00418 : le verbe ACCEPT exige un pro encore approuvé (un pro révoqué garde
  -- cancel, perd accept) — inclut le check suspension.
  PERFORM private.assert_approved_pro(v_user_id);

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.status != 'pending' OR v_bk.client_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.pro_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_bk.day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_bk.client_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_bk.client_id)
       OR (blocker_id = v_bk.client_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'accepted' WHERE id = p_booking_id AND status = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;
  v_period_label := CASE v_bk.period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;

  IF v_bk.client_id < v_user_id THEN v_u1 := v_bk.client_id; v_u2 := v_user_id;
  ELSE v_u1 := v_user_id; v_u2 := v_bk.client_id; END IF;

  SELECT id INTO v_conversation_id FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF v_conversation_id IS NULL THEN
    BEGIN
      INSERT INTO conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES ('dm', v_u1, v_u2, v_user_id, 'active', 'booking', now(), now())
      RETURNING id INTO v_conversation_id;
    EXCEPTION WHEN unique_violation THEN
      -- Course avec un autre créateur de DM : récupérer la ligne fraîche.
      SELECT id INTO v_conversation_id FROM conversations
      WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
    END;
  END IF;

  -- 00418 H2 : la réactivation d'une ligne existante RETAGUE en logistique.
  -- Une demande sociale pending/declined ne devient JAMAIS un contact via le
  -- booking : initiated_from='booking' + purge des champs de requête. Le
  -- double consentement frais (demande client + accept pro) ne couvre que
  -- l'ouverture du fil, pas la classification sociale (invariant 00372).
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE conversations
  SET status = 'active',
      initiated_from = CASE
        WHEN status != 'active' THEN 'booking'
        ELSE initiated_from
      END,
      request_sender_id = CASE WHEN status != 'active' THEN NULL ELSE request_sender_id END,
      request_message   = CASE WHEN status != 'active' THEN NULL ELSE request_message END,
      pending_activity_id = CASE WHEN status != 'active' THEN NULL ELSE pending_activity_id END,
      request_expires_at = NULL,
      last_message_at = now()
  WHERE id = v_conversation_id;
  -- Ré-afficher le fil chez les deux parties (un fil masqué doit resurgir
  -- avec la confirmation).
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  INSERT INTO messages (conversation_id, sender_id, content, metadata)
  VALUES (
    v_conversation_id, v_user_id,
    '📆 Réservation confirmée — « ' || coalesce(v_off_title, 'Sortie') || ' », le '
      || to_char(v_bk.day, 'DD/MM') || ' ' || v_period_label
      || ' (' || v_bk.party_size || ' pers.). Paiement sur place.',
    jsonb_build_object('type', 'booking_accepted', 'booking_id', v_bk.id,
                       'offering_id', v_bk.offering_id)
  );
  UPDATE conversations SET last_message_at = now() WHERE id = v_conversation_id;

  PERFORM create_notification(
    v_bk.client_id,
    'booking_accepted',
    'Réservation confirmée !',
    coalesce(v_pro_name, 'Le professionnel') || ' a confirmé « '
      || coalesce(v_off_title, 'ta sortie') || ' » le ' || to_char(v_bk.day, 'DD/MM')
      || ', ' || v_period_label || '. Paiement sur place.',
    jsonb_build_object('booking_id', v_bk.id, 'conversation_id', v_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'), 'title', coalesce(v_off_title, 'ta sortie'),
                                   'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
  );

  RETURN v_conversation_id;
END;
$$;


--
-- Name: accept_contact_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_contact_request(p_conversation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_name TEXT;
  v_act RECORD;
  v_existing RECORD;
  v_sender_name TEXT;
  v_rows INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00496 (BR-4): accepting a contact is an action — onboarded accounts only.
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.age_confirmed_at IS NOT NULL AND u.accepted_tos_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- FOR UPDATE : sérialise accept ⨯ accept (double message d'amorce) et
  -- accept ⨯ decline (un refus ne peut plus être ressuscité en actif).
  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id FOR UPDATE;
  IF v_conv.id IS NULL OR v_conv.type != 'dm' OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id = v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Une demande expirée ne s'accepte plus (elle a déjà disparu des Demandes ;
  -- seul un conversation_id rejoué pouvait encore la flipper).
  IF v_conv.request_expires_at IS NOT NULL AND v_conv.request_expires_at < NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Don't connect to a sender who was suspended after sending the request.
  IF EXISTS (SELECT 1 FROM users WHERE id = v_conv.request_sender_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Defense-in-depth: a block that appeared meanwhile forbids the acceptance.
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_conv.request_sender_id)
       OR (blocker_id = v_conv.request_sender_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE conversations
  SET status = 'active', request_expires_at = NULL, last_message_at = now()
  WHERE id = p_conversation_id AND status = 'pending_request';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- The request message becomes the first message of the thread.
  IF v_conv.request_message IS NOT NULL AND char_length(trim(v_conv.request_message)) > 0 THEN
    INSERT INTO messages (conversation_id, sender_id, content, created_at)
    VALUES (p_conversation_id, v_conv.request_sender_id, v_conv.request_message, now());
  END IF;

  SELECT display_name INTO v_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_conv.request_sender_id,
    'contact_request_accepted',
    coalesce(v_name, 'Quelqu''un') || ' a accepté ta demande de contact',
    '',
    jsonb_build_object('conversation_id', p_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_name, 'Quelqu''un')))
  );

  -- Discovery invite: the request was framed around one of the sender's
  -- activities. The pair is connected now, so the anti-cold gate holds —
  -- materialise the invitation as an 'invited' participation (the accepter
  -- still confirms the outing via the activity screen; capacity is checked
  -- there). Consume the link regardless of outcome.
  IF v_conv.pending_activity_id IS NOT NULL THEN
    SELECT a.id, a.title, a.creator_id, a.status, a.deleted_at, a.is_demo
    INTO v_act FROM activities a WHERE a.id = v_conv.pending_activity_id;

    IF v_act.id IS NOT NULL AND v_act.deleted_at IS NULL AND NOT v_act.is_demo
       AND v_act.creator_id = v_conv.request_sender_id
       AND v_act.status IN ('published', 'in_progress')
       -- 00503 (MS-3): not an outing this person already declined.
       AND NOT EXISTS (SELECT 1 FROM invitation_declines d WHERE d.activity_id = v_act.id AND d.user_id = v_user_id) THEN

      SELECT id, status INTO v_existing FROM participations
      WHERE activity_id = v_act.id AND user_id = v_user_id;

      PERFORM set_config('junto.bypass_lock', 'true', true);
      IF v_existing.id IS NULL THEN
        INSERT INTO participations (activity_id, user_id, status, invited_by, invite_message, created_at)
        VALUES (v_act.id, v_user_id, 'invited', v_conv.request_sender_id, NULL, now());
      ELSIF v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
        UPDATE participations
        SET status = 'invited', invited_by = v_conv.request_sender_id,
            invite_message = NULL, created_at = now(), refused_at = NULL, left_at = NULL
        WHERE id = v_existing.id;
      END IF;
      PERFORM set_config('junto.bypass_lock', 'false', true);

      IF v_existing.id IS NULL OR v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
        SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_conv.request_sender_id;
        PERFORM create_notification(
          v_user_id,
          'activity_invitation',
          coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
          '« ' || regexp_replace(v_act.title, '<[^>]*>', '', 'g') || ' »',
          jsonb_build_object('activity_id', v_act.id, 'type', 'activity_invitation',
            'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', regexp_replace(v_act.title, '<[^>]*>', '', 'g')))
        );
      END IF;
    ELSE
      -- La sortie liée n'existe plus (annulée/supprimée/terminée) : au lieu
      -- d'un silence total, dire à l'accepteur pourquoi rien n'apparaît dans
      -- ses Invitations. Le fil, lui, reste connecté (voulu).
      PERFORM create_notification(
        v_user_id,
        'invite_activity_gone',
        'Cette sortie n''est plus disponible',
        coalesce('« ' || regexp_replace(v_act.title, '<[^>]*>', '', 'g') || ' »', ''),
        jsonb_build_object('conversation_id', p_conversation_id,
          'params', jsonb_build_object('title', coalesce(regexp_replace(v_act.title, '<[^>]*>', '', 'g'), '')))
      );
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE conversations SET pending_activity_id = NULL WHERE id = p_conversation_id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END IF;
END;
$$;


--
-- Name: accept_participation(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_participation(p_participation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_max_participants INTEGER;
  v_activity_status TEXT;
  v_current_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00522 (F10): take the person's schedule lock BEFORE the row lock — the
  -- schedule trigger takes it too, and withdraws overlapping rows: same order
  -- everywhere, no deadlock between two organisers accepting at once.
  PERFORM pg_advisory_xact_lock(hashtext('schedule:' || coalesce((SELECT user_id::text FROM participations WHERE id = p_participation_id), '')));

  SELECT p.id, p.activity_id, p.user_id, p.status, a.creator_id, a.status AS activity_status, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00516: not on an outing removed by moderation, nor once the presence
  -- check window of a started outing has passed.
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = v_participation.activity_id
             AND (a.deleted_at IS NOT NULL OR (a.requires_presence AND now() > a.starts_at + INTERVAL '15 minutes'))) THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_participation.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00520: not a requester suspended in the meantime.
  IF private.user_is_suspended(v_participation.user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Lock the activity row and re-read cap AND status under the lock:
  -- serializes concurrent accepts with each other, with join_activity
  -- (same lock), with update_activity lowering the cap, and with
  -- cancel_activity flipping the status (00311 re-read the cap only —
  -- an accept racing a cancel could accept into a cancelled activity).
  SELECT max_participants, status INTO v_max_participants, v_activity_status
  FROM activities WHERE id = v_participation.activity_id
  FOR UPDATE;

  IF v_activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = v_participation.activity_id AND status = 'accepted';

  -- Open activities (max_participants IS NULL) honor a hidden 50-soft-cap, same as join_activity
  IF v_current_count >= COALESCE(v_max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'accepted' WHERE id = p_participation_id;

  PERFORM create_notification(
    v_participation.user_id,
    'request_accepted',
    'Tu es dans la sortie !',
    '« ' || v_participation.title || ' »',
    jsonb_build_object('activity_id', v_participation.activity_id,
      'params', jsonb_build_object('title', v_participation.title))
  );
END;
$$;


--
-- Name: accept_seat_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_seat_request(p_request_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_part RECORD;
  v_requester_name TEXT;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_driver_from TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
  v_updated_count INTEGER;
  v_skip_seed BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_req.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  SELECT id, transport_seats, transport_from_name INTO v_driver_part
  FROM participations
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted'
  FOR UPDATE;

  IF v_driver_part IS NULL OR coalesce(v_driver_part.transport_seats, 0) <= 0 THEN
    RAISE EXCEPTION 'junto.seats_exhausted';
  END IF;

  -- 00494 (BR-3): a passenger already seated with another driver of this
  -- outing does not take a second seat (two drivers accepting at once are
  -- serialised on the passenger).
  PERFORM pg_advisory_xact_lock(hashtext('seat_passenger:' || v_req.activity_id::text || ':' || v_req.requester_id::text));
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND requester_id = v_req.requester_id
               AND status = 'accepted' AND id <> p_request_id) THEN
    RAISE EXCEPTION 'junto.passenger_already_seated';
  END IF;
  -- 00496 (BR-3): a passenger who carries passengers does not ride elsewhere,
  -- and a driver who is seated in someone else's car takes nobody.
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND driver_id = v_req.requester_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.driver_has_passengers';
  END IF;
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND requester_id = v_req.driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;

  UPDATE seat_requests SET status = 'accepted'
  WHERE id = p_request_id AND status = 'pending';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00496 (B-4): the passenger's other pending requests on this outing are
  -- withdrawn (other drivers no longer see a request they cannot accept).
  UPDATE seat_requests SET status = 'cancelled'
  WHERE activity_id = v_req.activity_id AND requester_id = v_req.requester_id
    AND status = 'pending' AND id <> p_request_id;

  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE id = v_driver_part.id;

  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL,
      transport_from_lat = NULL, transport_from_lng = NULL, transport_from_locality = NULL, transport_departs_at = NULL  -- 00522 (F11)
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_driver_from := v_driver_part.transport_from_name;
  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  SELECT EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_req.driver_id AND blocked_id = v_req.requester_id)
       OR (blocker_id = v_req.requester_id AND blocked_id = v_req.driver_id)
  ) OR EXISTS (
    SELECT 1 FROM users u WHERE u.id = v_req.requester_id AND u.suspended_at IS NOT NULL
  ) INTO v_skip_seed;

  IF v_req.requester_id < v_req.driver_id THEN
    v_u1 := v_req.requester_id; v_u2 := v_req.driver_id;
  ELSE
    v_u1 := v_req.driver_id; v_u2 := v_req.requester_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (retag 'transport' à la
  -- réactivation, purge des champs de requête). Plus d'unique_violation brute.
  SELECT id, status INTO v_conversation_id, v_conv_status
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF NOT v_skip_seed THEN
    IF v_conversation_id IS NULL THEN
      BEGIN
        INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
        VALUES (v_u1, v_u2, v_req.driver_id, 'active', 'transport', NOW(), NOW())
        RETURNING id INTO v_conversation_id;
      EXCEPTION WHEN unique_violation THEN
        SELECT id INTO v_conversation_id FROM conversations
        WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
      END;
    ELSIF v_conv_status != 'active' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE conversations
      SET status = 'active', initiated_from = 'transport',
          request_sender_id = NULL, request_message = NULL,
          pending_activity_id = NULL, request_expires_at = NULL,
          last_message_at = NOW()
      WHERE id = v_conversation_id;
      UPDATE conversation_members SET hidden_at = NULL
      WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
      PERFORM set_config('junto.bypass_lock', 'false', true);
    END IF;

    v_message := '🚗 Place réservée pour « ' || v_activity_title || ' »'
      || CASE WHEN v_req.pickup_from IS NOT NULL THEN ' — pickup depuis ' || v_req.pickup_from ELSE '' END
      || CASE WHEN v_driver_from IS NOT NULL THEN ' (départ ' || v_driver_from || ')' ELSE '' END;

    -- 00508: unified store directly; this writer notifies on its own.
    PERFORM set_config('junto.skip_message_push', 'true', true);
    INSERT INTO messages (conversation_id, sender_id, content, metadata, created_at)
    VALUES (
      v_conversation_id, v_req.driver_id, v_message,
      jsonb_build_object('type', 'seat_accepted', 'activity_id', v_req.activity_id),
      NOW()
    );

    UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
    UPDATE conversation_members SET hidden_at = NULL  -- 00523
    WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
  ELSIF v_conv_status IS DISTINCT FROM 'active' THEN
    -- Seed sauté (blocage/suspension) : ne pas pointer la notif vers un fil
    -- non actif.
    v_conversation_id := NULL;
  END IF;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_accepted',
    'Place confirmée !',
    coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_driver_name, 'Le conducteur'), 'title', v_activity_title)
    )
  );

  RETURN v_conversation_id;
END;
$$;


--
-- Name: accept_tos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_tos() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('accept_tos:' || auth.uid()::text));

  -- Idempotent: already accepted -> no-op, preserving the original
  -- acceptance timestamp (the legally meaningful one). Was RAISE, which
  -- blocked the onboarding submit for pre-existing accounts re-shown the
  -- onboarding after the age-attestation migration (Scott 2026-07-12).
  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND accepted_tos_at IS NOT NULL) THEN
    RETURN;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET accepted_tos_at = now(), accepted_privacy_at = now() WHERE id = auth.uid();
END;
$$;


--
-- Name: activate_dispo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.activate_dispo() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM discovery_availabilities WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';  -- compose first
  END IF;
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE discovery_availabilities SET is_active = true WHERE user_id = v_user_id;
END;
$$;


--
-- Name: add_favorite(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_favorite(p_kind text, p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Cap only NEW favorites — re-favoriting an existing target stays an
  -- idempotent no-op even at the boundary.
  IF (SELECT count(*) FROM favorites WHERE owner_id = v_user_id) >= 500
     AND NOT EXISTS (
       SELECT 1 FROM favorites
       WHERE owner_id = v_user_id
         AND ( (p_kind = 'activity' AND activity_id = p_id)
            OR (p_kind = 'offering' AND offering_id = p_id)
            OR (p_kind = 'pro'      AND pro_id = p_id) )
     ) THEN
    RAISE EXCEPTION 'junto.favorite_cap';
  END IF;

  IF p_kind = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = p_id
        AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
        AND (a.is_demo = false OR demo_content_visible())
        AND (
          a.visibility IN ('public', 'approval')
          OR (
            a.visibility IN ('private_link', 'private_link_approval')
            AND (
              a.creator_id = v_user_id
              OR EXISTS (SELECT 1 FROM participations p WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted')
            )
          )
        )
        AND NOT EXISTS (SELECT 1 FROM users cu WHERE cu.id = a.creator_id AND cu.suspended_at IS NOT NULL)
        AND a.creator_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, activity_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'offering' THEN
    -- Mirror pro_offerings_with_coords: gate on suspension + demo only (NOT the
    -- parent pro's approved status — the view shows the offering regardless).
    IF NOT EXISTS (
      SELECT 1 FROM pro_offerings o
      JOIN users u ON u.id = o.pro_id
      WHERE o.id = p_id AND u.suspended_at IS NULL
        AND (o.is_demo = false OR demo_content_visible())
        -- 00505 (B8): the view now hides unapproved pros' offerings too.
        AND EXISTS (SELECT 1 FROM pro_profiles pp WHERE pp.user_id = o.pro_id AND pp.status = 'approved')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, offering_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'pro' THEN
    IF NOT EXISTS (
      SELECT 1 FROM pro_profiles p
      JOIN users u ON u.id = p.user_id
      WHERE p.user_id = p_id AND p.status = 'approved' AND u.suspended_at IS NULL
        AND (p.is_demo = false OR demo_content_visible())
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, pro_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;


--
-- Name: add_group_member(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_group_member(p_conversation_id uuid, p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_member_count INTEGER;
  v_added_today INTEGER;
  v_caller_name TEXT;
  v_group_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT name INTO v_group_name FROM conversations
  WHERE id = p_conversation_id AND type = 'group';
  IF v_group_name IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_user_id IS NULL OR p_user_id = v_user_id
     OR NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF private.is_conversation_member(p_conversation_id, p_user_id) THEN RETURN; END IF;

  -- Caller lock (30/24h add-rate) + CONVERSATION lock (cap-20 + membership race).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_group'));
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_group_members'));

  SELECT count(*) INTO v_member_count FROM conversation_members
  WHERE conversation_id = p_conversation_id;
  IF v_member_count >= 20 THEN RAISE EXCEPTION 'junto.group_cap'; END IF;

  SELECT count(*) INTO v_added_today FROM conversation_members
  WHERE added_by = v_user_id AND joined_at > now() - INTERVAL '24 hours';
  IF v_added_today >= 30 THEN RAISE EXCEPTION 'junto.group_add_rate_limit'; END IF;

  IF NOT private.is_messaging_eligible(v_user_id, p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users bu
    JOIN conversation_members cm ON cm.conversation_id = p_conversation_id
    WHERE (bu.blocker_id = p_user_id AND bu.blocked_id = cm.user_id)
       OR (bu.blocker_id = cm.user_id AND bu.blocked_id = p_user_id)
  ) THEN
    -- 00499 (MS-2): skipped silently — an error would tell the adder that
    -- someone in the group blocks (or is blocked by) this person.
    RETURN;
  END IF;
  -- 00499 (AB-12): someone who left this group is not put back by others
  -- for 30 days.
  -- 00519: also a group of the adder's that this person left (not only
  -- this one), so a copy of the group cannot pull them back.
  IF EXISTS (SELECT 1 FROM conversation_departures d
             WHERE d.conversation_id = p_conversation_id AND d.user_id = p_user_id
               AND d.at > now() - INTERVAL '30 days')
     OR EXISTS (
      SELECT 1 FROM conversation_departures d
      JOIN conversation_members cm ON cm.conversation_id = d.conversation_id AND cm.user_id = v_user_id
      WHERE d.user_id = p_user_id AND d.at > now() - INTERVAL '30 days') THEN
    RAISE EXCEPTION 'junto.member_left_recently';
  END IF;

  -- 00519: a group taken down by moderation is read-only.
  IF EXISTS (SELECT 1 FROM conversations WHERE id = p_conversation_id AND moderated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (p_conversation_id, p_user_id, v_user_id, now())
  ON CONFLICT DO NOTHING;

  SELECT display_name INTO v_caller_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    p_user_id, 'group_added',
    coalesce(v_caller_name, 'Quelqu''un') || ' t''ajoute au groupe',
    v_group_name, jsonb_build_object('conversation_id', p_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_caller_name, 'Quelqu''un'), 'group', v_group_name))
  );
END;
$$;


--
-- Name: add_missing_gear(uuid, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_missing_gear(p_activity_id uuid, p_name text, p_quantity integer DEFAULT 1) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
  v_qty INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('gear_missing', 30, INTERVAL '1 minute');
  PERFORM private.rate_hit('gear_missing_h', 300, INTERVAL '1 hour');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) AND NOT EXISTS (
    SELECT 1 FROM activities WHERE id = p_activity_id AND creator_id = v_user_id
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Same HTML-strip as set_activity_gear (00238 H5c).
  v_name := regexp_replace(trim(coalesce(p_name, '')), '<[^>]*>', '', 'g');
  IF char_length(v_name) < 1 OR char_length(v_name) > 60 THEN
    RAISE EXCEPTION 'junto.gear_invalid';
  END IF;
  v_qty := GREATEST(1, LEAST(coalesce(p_quantity, 1), 99));

  -- Anti-noise cap.
  IF (SELECT count(*) FROM activity_gear_missing WHERE activity_id = p_activity_id) >= 20 THEN
    RAISE EXCEPTION 'junto.gear_missing_limit';
  END IF;

  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by)
  VALUES (p_activity_id, v_name, v_qty, v_user_id)
  ON CONFLICT (activity_id, lower(name))
  DO UPDATE SET quantity = EXCLUDED.quantity;
END;
$$;


--
-- Name: add_pro_community_photo(uuid, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid DEFAULT NULL::uuid, p_offering_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_photo_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF private.user_is_suspended(p_pro_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;  -- 00520
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_pro_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00418 H4 : cible = pro APPROUVÉ (ferme l'oracle de candidature — même
  -- erreur générique qu'une cible inexistante).
  -- 00443 B5 : et NON démo — un compte démo ne reçoit jamais d'écriture réelle (00426).
  IF NOT EXISTS (
    SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND status = 'approved' AND is_demo = false
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00418 H4 : URL ancrée hôte + dossier du CONTRIBUTEUR (fin du wildcard).
  IF NOT private.pro_photo_url_ok(p_photo_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_review_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_reviews
    WHERE id = p_review_id AND reviewer_id = v_user_id AND pro_id = p_pro_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_offering_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_offerings
    WHERE id = p_offering_id AND pro_id = p_pro_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_community_photo:' || v_user_id::text || ':' || p_pro_id::text));

  SELECT count(*) INTO v_count
  FROM pro_community_photos
  WHERE pro_id = p_pro_id AND contributor_id = v_user_id;

  IF v_count >= 5 THEN
    RAISE EXCEPTION 'junto.photo_limit';
  END IF;

  INSERT INTO pro_community_photos (pro_id, contributor_id, photo_url, review_id, offering_id)
  VALUES (p_pro_id, v_user_id, p_photo_url, p_review_id, p_offering_id)
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$$;


--
-- Name: add_pro_offering_photo(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_pro_offering_photo(p_offering_id uuid, p_photo_url text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_count INTEGER;
  v_next_index INTEGER;
  v_photo_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT private.pro_photo_url_ok(p_photo_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_pro_offering_photo:' || p_offering_id::text));
  SELECT count(*) INTO v_count FROM pro_offering_photos WHERE offering_id = p_offering_id;
  IF v_count >= 25 THEN RAISE EXCEPTION 'junto.photo_cap'; END IF;
  SELECT COALESCE(MAX(order_index), -1) + 1 INTO v_next_index
  FROM pro_offering_photos WHERE offering_id = p_offering_id;
  INSERT INTO pro_offering_photos (offering_id, photo_url, order_index)
  VALUES (p_offering_id, p_photo_url, v_next_index)
  RETURNING id INTO v_photo_id;
  RETURN v_photo_id;
END;
$$;


--
-- Name: add_pro_photo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_pro_photo(p_photo_url text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_count INTEGER;
  v_next_index INTEGER;
  v_photo_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT private.pro_photo_url_ok(p_photo_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_pro_photo:' || v_user_id::text));
  SELECT count(*) INTO v_count FROM pro_profile_photos WHERE pro_id = v_user_id;
  IF v_count >= 25 THEN RAISE EXCEPTION 'junto.photo_cap'; END IF;
  SELECT COALESCE(MAX(order_index), -1) + 1 INTO v_next_index
  FROM pro_profile_photos WHERE pro_id = v_user_id;
  INSERT INTO pro_profile_photos (pro_id, photo_url, order_index)
  VALUES (v_user_id, p_photo_url, v_next_index)
  RETURNING id INTO v_photo_id;
  RETURN v_photo_id;
END;
$$;


--
-- Name: admin_get_pending_pro_applications(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_get_pending_pro_applications() RETURNS TABLE(user_id uuid, display_name text, company_name text, real_name text, email text, phone text, website text, primary_location_name text, created_at timestamp with time zone, prior_review_count integer, last_review_action text, last_review_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00420 D2 (contre-mesure blanchiment M5) : un pro qui a déjà été
  -- approuvé/refusé puis s'est désinscrit (CASCADE avis/photos) réapparaît
  -- ici avec son passif visible — l'admin re-valide en connaissance de cause.
  RETURN QUERY
  SELECT pp.user_id, pp.display_name, pp.company_name, pp.real_name,
         pp.email, pp.phone, pp.website, pp.primary_location_name, pp.created_at,
         coalesce(h.cnt, 0)::INTEGER, h.last_action, h.last_at
  FROM pro_profiles pp
  LEFT JOIN LATERAL (
    SELECT count(*)::INTEGER AS cnt,
           (ARRAY_AGG(a.action ORDER BY a.created_at DESC))[1] AS last_action,
           max(a.created_at) AS last_at
    FROM admin_actions a
    WHERE a.target_id = pp.user_id
      AND a.action IN ('approve_pro', 'reject_pro')
  ) h ON true
  WHERE pp.status = 'pending'
  ORDER BY pp.created_at ASC;
END;
$$;


--
-- Name: admin_pro_owner(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_pro_owner(p_pro_id uuid) RETURNS TABLE(pro_id uuid, pro_name text, status text, owner_display_name text, owner_email text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles pp WHERE pp.user_id = p_pro_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM log_admin_action(v_admin, 'pro_owner', 'pro_profile', p_pro_id, NULL, NULL);

  RETURN QUERY
    SELECT pp.user_id, pp.display_name, pp.status, u.display_name, u.email
    FROM pro_profiles pp JOIN users u ON u.id = pp.user_id
    WHERE pp.user_id = p_pro_id;
END;
$$;


--
-- Name: admin_remove_content(text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_remove_content(p_target_type text, p_target_id uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_admin UUID;
  v_reason TEXT;
  v_found BOOLEAN := false;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := trim(coalesce(p_reason, ''));
  IF char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'junto.admin_reason_required';
  END IF;

  IF p_target_type NOT IN ('activity', 'message', 'group', 'channel', 'pro_review', 'offering_review') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  IF p_target_type = 'activity' THEN
    UPDATE activities SET deleted_at = now(), updated_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'message' THEN
    -- Unified store: reads come from `messages`. 'wall_message' kept for
    -- migrated ids (id is shared), 'message' for post-rebuild content.
    UPDATE messages SET deleted_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'group' THEN
    UPDATE conversations SET name = '[Groupe retiré]', icon = NULL, moderated_at = now()
    WHERE id = p_target_id AND type = 'group';
    v_found := FOUND;
  ELSIF p_target_type = 'channel' THEN
    -- 00507: a reported channel is closed (read-only, out of search).
    UPDATE channels SET closed_at = now()
    WHERE conversation_id = p_target_id AND closed_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'pro_review' THEN
    DELETE FROM pro_reviews WHERE id = p_target_id;
    v_found := FOUND;
  ELSIF p_target_type = 'offering_review' THEN
    DELETE FROM offering_reviews WHERE id = p_target_id;
    v_found := FOUND;
  END IF;

  IF NOT v_found THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM log_admin_action(v_admin, 'remove_content', p_target_type, p_target_id, v_reason, NULL);
END;
$$;


--
-- Name: admin_resolve_user(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_resolve_user(p_user_id uuid) RETURNS TABLE(id uuid, display_name text, email text, tier text, is_admin boolean, suspended_at timestamp with time zone, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_admin AND u0.is_admin = true AND u0.suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM log_admin_action(v_admin, 'resolve_user', 'user', p_user_id, NULL, NULL);

  RETURN QUERY
    SELECT u.id, u.display_name, u.email, u.tier, u.is_admin, u.suspended_at, u.created_at
    FROM users u WHERE u.id = p_user_id;
END;
$$;


--
-- Name: admin_set_demo_mode(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_set_demo_mode(p_on boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_admin uuid;
  v_base GEOGRAPHY;
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
  v_sports TEXT[];
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE app_config SET value = CASE WHEN p_on THEN 'true' ELSE 'false' END
  WHERE name = 'demo_mode';

  IF p_on THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);

    -- Showcase demo activities only → future dates. The completed HISTORY
    -- (c0000000-…, feeds the rich profiles) is excluded by UUID range so it can
    -- never be dragged into the re-date pool (a status-only guard traps it).
    WITH ordered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM activities
      WHERE is_demo = true AND deleted_at IS NULL AND id::text NOT LIKE 'c0000000-%'
    ),
    target AS (
      SELECT a.id, a.starts_at AS old_start,
             date_trunc('day', now())
               + make_interval(
                   days  => (1 + ((o.rn - 1) / 2))::int, -- 00457 : deux sorties par jour (50 sorties → 25 jours)
                   hours => (ARRAY[9,14,8,16,10,17,11,15])[((o.rn - 1) % 8) + 1],
                   mins  => (ARRAY[0,30,15,0,45,30,0,30])[((o.rn - 1) % 8) + 1]
                 ) AS new_start
      FROM activities a JOIN ordered o ON o.id = a.id
    ),
    -- Carpool departures and pickups follow their outing (same snapshot).
    shifted_transport AS (
      UPDATE participations p
      SET transport_departs_at = p.transport_departs_at + (t.new_start - t.old_start)
      FROM target t
      WHERE p.activity_id = t.id AND p.transport_departs_at IS NOT NULL
      RETURNING p.id
    ),
    shifted_pickups AS (
      UPDATE seat_requests s
      SET requested_pickup_at = s.requested_pickup_at + (t.new_start - t.old_start)
      FROM target t
      WHERE s.activity_id = t.id AND s.requested_pickup_at IS NOT NULL
      RETURNING s.id
    )
    UPDATE activities a
    SET starts_at = t.new_start, status = 'published'
    FROM target t
    WHERE a.id = t.id;

    -- Demo dispos: each partner keeps ONE of the admin's sports (rotation →
    -- every card matches) + up to 2 of its own flavor sports, on a varied
    -- sub-window of the admin's window, with varied radius/offset per partner.
    SELECT d.base, d.window_start, d.window_end, d.sport_keys
      INTO v_base, v_ws, v_we, v_sports
    FROM discovery_availabilities d
    WHERE d.user_id = v_admin AND d.is_active AND d.is_demo = false;

    IF v_base IS NOT NULL THEN
      WITH ordered AS (
        SELECT id, user_id, row_number() OVER (ORDER BY user_id) AS rn
        FROM discovery_availabilities WHERE is_demo = true
      ),
      flavors(user_id, extras) AS (VALUES
        ('d0000000-0000-4000-a000-000000000002'::uuid, ARRAY['trail-running','hiking']),
        ('d0000000-0000-4000-a000-000000000003'::uuid, ARRAY['climbing-sport','bouldering']),
        ('d0000000-0000-4000-a000-000000000004'::uuid, ARRAY['climbing-multipitch','mountaineering']),
        ('d0000000-0000-4000-a000-000000000005'::uuid, ARRAY['paragliding','hiking']),
        ('d0000000-0000-4000-a000-000000000006'::uuid, ARRAY['via-ferrata','canyoning']),
        ('d0000000-0000-4000-a000-000000000007'::uuid, ARRAY['mtb-enduro','gravel']),
        ('d0000000-0000-4000-a000-000000000008'::uuid, ARRAY['trail-running','running']),
        ('d0000000-0000-4000-a000-000000000009'::uuid, ARRAY['windsurfing','swimming'])
      )
      UPDATE discovery_availabilities dd
      SET sport_keys = (
            ARRAY[v_sports[((o.rn - 1) % cardinality(v_sports)) + 1]]
            || array_remove(COALESCE(f.extras, '{}'::text[]),
                            v_sports[((o.rn - 1) % cardinality(v_sports)) + 1])
          )[1:3],
          window_start = v_ws + (v_we - v_ws)
            * ((ARRAY[0,2,1,3,0,2,1,3])[((o.rn - 1) % 8) + 1] / 10.0),
          window_end   = v_we - (v_we - v_ws)
            * ((ARRAY[0,1,2,0,3,1,0,2])[((o.rn - 1) % 8) + 1] / 10.0),
          radius_km    = (ARRAY[30,50,15,NULL,50,10,30,15])[((o.rn - 1) % 8) + 1],
          base = ST_SetSRID(ST_MakePoint(
                   ST_X(v_base::geometry) + (ARRAY[0.06,0.13,-0.08,0.10,-0.12,0.15,0.04,-0.05])[((o.rn - 1) % 8) + 1],
                   ST_Y(v_base::geometry) + (ARRAY[0.00,0.03,-0.02,0.05,0.02,0.01,-0.04,0.04])[((o.rn - 1) % 8) + 1]),
                 4326)::geography,
          is_active = true
      FROM ordered o
      LEFT JOIN flavors f ON f.user_id = o.user_id
      WHERE dd.id = o.id;
    END IF;
  END IF;

  PERFORM log_admin_action(
    v_admin,
    CASE WHEN p_on THEN 'demo_mode_on' ELSE 'demo_mode_off' END,
    'app_config', NULL, NULL, NULL
  );
END;
$$;


--
-- Name: admin_suspend_user(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_suspend_user(p_user_id uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_admin UUID;
  v_reason TEXT;
  v_bk RECORD;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := trim(coalesce(p_reason, ''));
  IF char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'junto.admin_reason_required';
  END IF;

  IF p_user_id = v_admin THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- An admin cannot suspend another admin — admin status is managed at SQL level.
  IF EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET suspended_at = now() WHERE id = p_user_id AND suspended_at IS NULL;

  -- 00420 D1 : les réservations futures du suspendu s'annulent (2 sens) et les
  -- contreparties sont prévenues — copy neutre, la suspension n'est pas
  -- révélée. Miroir du bloc delete_own_account (00419 M1) : pro suspendu →
  -- tout client est prévenu ; client suspendu → le pro seulement pour du
  -- confirmé (un pending qui disparaît reste silencieux).
  FOR v_bk IN
    SELECT b.id AS b_id, b.pro_id AS b_pro, b.client_id AS b_client,
           b.status AS b_status, b.day AS b_day, po.title AS b_title
    FROM bookings b
    LEFT JOIN pro_offerings po ON po.id = b.offering_id
    WHERE (b.pro_id = p_user_id OR b.client_id = p_user_id)
      AND b.status IN ('pending', 'accepted')
      AND b.day >= private.today_paris()
    FOR UPDATE OF b
  LOOP
    UPDATE bookings
    SET status = CASE WHEN v_bk.b_pro = p_user_id THEN 'cancelled_pro' ELSE 'cancelled' END
    WHERE id = v_bk.b_id;

    IF v_bk.b_pro = p_user_id THEN
      IF v_bk.b_client IS NOT NULL THEN
        PERFORM create_notification(
          v_bk.b_client,
          'booking_cancelled',
          'Sortie annulée',
          '« ' || coalesce(v_bk.b_title, 'Ta sortie') || ' » du '
            || to_char(v_bk.b_day, 'DD/MM') || ' a été annulée.',
          jsonb_build_object('booking_id', v_bk.b_id, 'by', 'pro',
            'params', jsonb_build_object('title', coalesce(v_bk.b_title, 'Ta sortie'), 'date', to_char(v_bk.b_day, 'YYYY-MM-DD')))
        );
      END IF;
    ELSIF v_bk.b_status = 'accepted' THEN
      PERFORM create_notification(
        v_bk.b_pro,
        'booking_cancelled',
        'Réservation annulée',
        'La réservation de « ' || coalesce(v_bk.b_title, 'une sortie') || ' » du '
          || to_char(v_bk.b_day, 'DD/MM') || ' a été annulée.',
        jsonb_build_object('booking_id', v_bk.b_id, 'by', 'client', 'variant', 'client_gone',
          'params', jsonb_build_object('title', coalesce(v_bk.b_title, 'une sortie'), 'date', to_char(v_bk.b_day, 'YYYY-MM-DD')))
      );
    END IF;
  END LOOP;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM log_admin_action(v_admin, 'suspend_user', 'user', p_user_id, v_reason, NULL);
END;
$$;


--
-- Name: admin_unsuspend_user(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_unsuspend_user(p_user_id uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_admin UUID;
  v_reason TEXT;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := trim(coalesce(p_reason, ''));
  IF char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'junto.admin_reason_required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET suspended_at = NULL WHERE id = p_user_id;

  PERFORM log_admin_action(v_admin, 'unsuspend_user', 'user', p_user_id, v_reason, NULL);
END;
$$;


--
-- Name: approve_pro(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.approve_pro(p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_user_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles
    SET status = 'approved', rejection_reason = NULL, reviewed_at = now(), reviewed_by = v_admin
    WHERE user_id = p_user_id;
  -- 00419 : si unregister_as_pro a supprimé la ligne entre le check et ici,
  -- ne surtout pas poser tier='pro' sans profil.
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE users SET tier = 'pro' WHERE id = p_user_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (p_user_id, 'pro_approved', 'Page pro validée',
          'Ta page pro est en ligne. Tu peux maintenant publier tes sorties.',
          jsonb_build_object('pro_id', p_user_id, 'params', '{}'::jsonb));

  PERFORM log_admin_action(v_admin, 'approve_pro', 'pro_profile', p_user_id, NULL, NULL);
END;
$$;


--
-- Name: award_badge_progression(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.award_badge_progression(p_user_id uuid, p_silent boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_count INTEGER;
  v_tier TEXT;
  v_inserted UUID;
  v_label TEXT;
BEGIN
  -- Joined activities (where the user wasn't the creator)
  SELECT count(*) INTO v_count
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND par.confirmed_present = true /* 00521: validated presence only */  -- 00495 (PR-7)
    AND a.status = 'completed'
    AND a.creator_id != p_user_id
    AND a.deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'joined', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('joined', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'joined', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
  v_inserted := NULL;

  -- Created activities
  SELECT count(*) INTO v_count
  FROM activities
  WHERE creator_id = p_user_id
    AND status = 'completed'
    AND deleted_at IS NULL
    -- 00522 (F8): same rule as the trophies — the organiser's presence validated.
    AND EXISTS (SELECT 1 FROM participations cp WHERE cp.activity_id = activities.id
                AND cp.user_id = p_user_id AND cp.confirmed_present = true);
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'created', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('created', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'created', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
END;
$$;


--
-- Name: badge_label_fr(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.badge_label_fr(p_category text, p_tier text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  SELECT CASE p_category || '_' || p_tier
    WHEN 'joined_bronze'  THEN 'Membre'
    WHEN 'joined_silver'  THEN 'Régulier'
    WHEN 'joined_gold'    THEN 'Pilier'
    WHEN 'created_bronze' THEN 'Initiateur'
    WHEN 'created_silver' THEN 'Animateur'
    WHEN 'created_gold'   THEN 'Bâtisseur'
    ELSE NULL
  END;
$$;


--
-- Name: badge_tier_for(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.badge_tier_for(p_count integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  SELECT CASE
    WHEN p_count >= 50 THEN 'gold'
    WHEN p_count >= 20 THEN 'silver'
    WHEN p_count >= 5  THEN 'bronze'
    ELSE NULL
  END;
$$;


--
-- Name: bookings_clear_participant_info(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bookings_clear_participant_info() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'accepted' THEN
    NEW.participant_info := NULL;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: bookings_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bookings_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.offering_id := OLD.offering_id;
  NEW.pro_id := OLD.pro_id;
  NEW.client_id := OLD.client_id;
  NEW.manual_name := OLD.manual_name;
  NEW.manual_phone := OLD.manual_phone;
  NEW.day := OLD.day;
  NEW.period := OLD.period;
  NEW.created_at := OLD.created_at;
  NEW.submitted_count := OLD.submitted_count;
  NEW.last_submitted_at := OLD.last_submitted_at;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: broadcast_activity_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.broadcast_activity_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  v_activity_id := COALESCE(
    (CASE WHEN TG_OP <> 'DELETE' THEN NEW.activity_id END),
    (CASE WHEN TG_OP <> 'INSERT' THEN OLD.activity_id END)
  );
  IF v_activity_id IS NULL THEN
    RETURN NULL;
  END IF;

  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP),
      'change',
      'activity:' || v_activity_id::text,
      true
    );
  EXCEPTION WHEN OTHERS THEN
    -- Realtime broker hiccup: better to lose the ping than to fail
    -- the user's write. Subscribers refetch on stale times anyway.
    NULL;
  END;

  RETURN NULL;
END;
$$;


--
-- Name: broadcast_activity_change_stmt(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.broadcast_activity_change_stmt() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity UUID;
BEGIN
  -- 00481: set_activity_gear sends its own single ping.
  IF current_setting('junto.gear_quiet', true) = 'true' THEN RETURN NULL; END IF;
  -- Transition tables only exist for the events that define them: branch on
  -- TG_OP so an INSERT trigger never references old_rows (and vice versa).
  FOR v_activity IN EXECUTE CASE TG_OP
      WHEN 'INSERT' THEN 'SELECT DISTINCT activity_id FROM new_rows WHERE activity_id IS NOT NULL'
      WHEN 'DELETE' THEN 'SELECT DISTINCT activity_id FROM old_rows WHERE activity_id IS NOT NULL'
      ELSE 'SELECT activity_id FROM new_rows WHERE activity_id IS NOT NULL UNION SELECT activity_id FROM old_rows WHERE activity_id IS NOT NULL'
    END
  LOOP
    BEGIN
      PERFORM realtime.send(jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP), 'change', 'activity:' || v_activity::text, true);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  RETURN NULL;
END;
$$;


--
-- Name: broadcast_and_push_message(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.broadcast_and_push_message() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_conv RECORD;
  v_sender_name TEXT;
  v_secret TEXT;
  v_recipients UUID[];
  v_uid UUID;
  v_title TEXT;
BEGIN
  SELECT type, name, activity_id INTO v_conv
  FROM conversations WHERE id = NEW.conversation_id;

  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('table', 'messages', 'op', 'INSERT',
                         'conversation_id', NEW.conversation_id, 'message_id', NEW.id),
      'change', 'conversation:' || NEW.conversation_id::text, true);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  IF v_conv.type = 'activity' AND v_conv.activity_id IS NOT NULL THEN
    BEGIN
      PERFORM realtime.send(
        jsonb_build_object('table', 'messages', 'op', 'INSERT',
                           'conversation_id', NEW.conversation_id),
        'wall', 'activity:' || v_conv.activity_id::text, true);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  SELECT array_agg(cm.user_id) INTO v_recipients
  FROM conversation_members cm
  WHERE cm.conversation_id = NEW.conversation_id
    AND cm.user_id IS DISTINCT FROM NEW.sender_id
    -- 00472 (audit L12): a suspended member gets no message push or live event
    -- (create_notification already skipped them; the two paths now agree).
    AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = cm.user_id AND u.suspended_at IS NOT NULL)
    AND (NEW.sender_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE b.blocker_id = cm.user_id AND b.blocked_id = NEW.sender_id
    ));
  IF v_recipients IS NULL OR array_length(v_recipients, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  FOREACH v_uid IN ARRAY v_recipients LOOP
    BEGIN
      PERFORM realtime.send(
        jsonb_build_object('conversation_id', NEW.conversation_id),
        'inbox', 'user:' || v_uid::text, true);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;

  -- Push leg — skipped for rows mirrored from a legacy writer (already pushed).
  IF current_setting('junto.skip_message_push', true) IS DISTINCT FROM 'true' THEN
    IF NEW.sender_id IS NOT NULL THEN
      SELECT display_name INTO v_sender_name FROM users WHERE id = NEW.sender_id;
    END IF;
    v_title := coalesce(v_sender_name, 'Junto');
    IF v_conv.type = 'group' AND v_conv.name IS NOT NULL THEN
      v_title := v_title || ' · ' || v_conv.name;
    ELSIF v_conv.type = 'activity' THEN
      SELECT v_title || ' · ' || regexp_replace(a.title, '<[^>]*>', '', 'g')
      INTO v_title FROM activities a WHERE a.id = v_conv.activity_id;
    END IF;

    v_title := regexp_replace(v_title, '[[:cntrl:]]', ' ', 'g');  -- 00503 (MS-5)

    SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
    IF v_secret IS NOT NULL AND private.project_url() IS NOT NULL THEN  -- 00524
      BEGIN
        PERFORM net.http_post(
          url := private.project_url() || '/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json',
                                        'x-junto-push-secret', v_secret),
          body := jsonb_build_object(
            'user_ids', to_jsonb(v_recipients),
            'title', v_title,
            'body', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140),
            -- 00437 : pour un fil d'ACTIVITÉ, on ajoute activity_id. Sans lui, le
            -- routeur push ouvrait /conversation/{id} — l'écran DM/groupe, qui ne
            -- sait pas afficher un fil d'activité (le mur vit dans l'onglet chat de
            -- l'écran d'activité). Les DM et groupes gardent le payload d'origine.
            'data', CASE
              WHEN v_conv.type = 'activity' AND v_conv.activity_id IS NOT NULL THEN
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message',
                                   'activity_id', v_conv.activity_id,
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'Junto'),
                                     'context', (SELECT regexp_replace(a.title, '<[^>]*>', '', 'g') FROM activities a WHERE a.id = v_conv.activity_id),
                                     'preview', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140)))
              WHEN v_conv.name IS NOT NULL THEN
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message',
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'Junto'),
                                     'context', v_conv.name, 'preview', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140)))
              ELSE
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message', 'variant', 'dm',
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'Junto'),
                                     'preview', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140)))
            END,
            'collapseId', 'message-' || NEW.conversation_id::text
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: broadcast_map_activity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.broadcast_map_activity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.visibility IN ('public', 'approval') AND NOT OLD.is_demo THEN PERFORM map_ping(OLD.id); END IF;
    RETURN NULL;
  END IF;
  -- A public outing switched to demo must disappear from maps: ping on the flip.
  IF TG_OP = 'UPDATE' AND NEW.is_demo IS DISTINCT FROM OLD.is_demo THEN PERFORM map_ping(NEW.id); RETURN NULL; END IF;
  IF NEW.is_demo THEN RETURN NULL; END IF;
  IF NOT (NEW.visibility IN ('public', 'approval')
          OR (TG_OP = 'UPDATE' AND OLD.visibility IN ('public', 'approval'))) THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'UPDATE' AND NOT (
       NEW.status IS DISTINCT FROM OLD.status
    OR NEW.starts_at IS DISTINCT FROM OLD.starts_at
    OR NEW.duration IS DISTINCT FROM OLD.duration
    OR NEW.location_meeting IS DISTINCT FROM OLD.location_meeting
    OR NEW.location_objective IS DISTINCT FROM OLD.location_objective
    OR NEW.title IS DISTINCT FROM OLD.title
    OR NEW.max_participants IS DISTINCT FROM OLD.max_participants
    OR NEW.visibility IS DISTINCT FROM OLD.visibility
    OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
    OR NEW.level IS DISTINCT FROM OLD.level
    OR NEW.level_max IS DISTINCT FROM OLD.level_max
    OR NEW.sport_id IS DISTINCT FROM OLD.sport_id
    -- 00480: every column the map payload shows (getNearby / activities_with_coords).
    OR NEW.location_end IS DISTINCT FROM OLD.location_end
    OR NEW.meeting_name IS DISTINCT FROM OLD.meeting_name
    OR NEW.meeting_locality IS DISTINCT FROM OLD.meeting_locality
    OR NEW.objective_name IS DISTINCT FROM OLD.objective_name
    OR NEW.distance_km IS DISTINCT FROM OLD.distance_km
    OR NEW.elevation_gain_m IS DISTINCT FROM OLD.elevation_gain_m
    OR (NEW.trace_geojson IS NULL) IS DISTINCT FROM (OLD.trace_geojson IS NULL)
    OR NEW.requires_presence IS DISTINCT FROM OLD.requires_presence
  ) THEN
    RETURN NULL;
  END IF;
  PERFORM map_ping(NEW.id);
  RETURN NULL;
END;
$$;


--
-- Name: broadcast_map_creator(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.broadcast_map_creator() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE creator_id = NEW.id
      AND visibility IN ('public', 'approval')
      AND NOT is_demo
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RETURN NULL; END IF;
  -- Hourly budget without raising (a profile save must never fail for a ping).
  PERFORM pg_advisory_xact_lock(hashtext(NEW.id::text || '_rate_creator_map'));
  IF (SELECT count(*) FROM rate_events
      WHERE user_id = NEW.id AND kind = 'creator_map' AND at > now() - INTERVAL '1 hour') >= 30 THEN
    RETURN NULL;
  END IF;
  INSERT INTO rate_events (user_id, kind) VALUES (NEW.id, 'creator_map');
  -- The creator id is the throttle key (map_broadcasts has no FK): one
  -- content-less ping per creator change, ≤ 1 per 15 s.
  PERFORM map_ping(NEW.id);
  RETURN NULL;
END;
$$;


--
-- Name: broadcast_map_participation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.broadcast_map_participation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity UUID;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NULL; END IF;
  v_activity := CASE WHEN TG_OP = 'DELETE' THEN OLD.activity_id ELSE NEW.activity_id END;
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = v_activity
             AND a.visibility IN ('public', 'approval') AND NOT a.is_demo) THEN
    PERFORM map_ping(v_activity);
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: cancel_accepted_seat(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_accepted_seat(p_request_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_request RECORD;
  v_updated_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, requester_id, driver_id, activity_id, status
  INTO v_request
  FROM seat_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_request IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.requester_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_request.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  UPDATE seat_requests SET status = 'cancelled'
  WHERE id = p_request_id AND status = 'accepted';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00523: the seat is given back by trg_seat_requests_release.
END;
$$;


--
-- Name: cancel_activity(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_activity(p_activity_id uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
  v_clean_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00472/00474 (audit L11, F9): bounded to 300 — copied into every participant's
  -- notification, twice in the push payload (body + params), under Expo's 4 KB.
  v_clean_reason := left(NULLIF(trim(coalesce(p_reason, '')), ''), 300);
  IF v_clean_reason IS NULL OR char_length(v_clean_reason) < 3 THEN
    RAISE EXCEPTION 'junto.cancel_reason_invalid';
  END IF;

  SELECT id, creator_id, status, title
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_user_id != v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';  -- 00516: moderated outing frozen
  END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE activities
  SET status = 'cancelled',
      cancelled_reason = v_clean_reason,
      updated_at = now()
  WHERE id = p_activity_id;

  -- Notify all accepted participants except creator
  FOR v_participant IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id
      AND status IN ('accepted', 'pending')
      AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_cancelled',
      'Sortie annulée',
      CASE WHEN coalesce(v_clean_reason, '') = '' THEN '« ' || v_activity.title || ' »'
           ELSE '« ' || v_activity.title || ' » — ' || v_clean_reason END,
      jsonb_build_object('activity_id', p_activity_id,
        'variant', CASE WHEN coalesce(v_clean_reason, '') = '' THEN 'no_reason' ELSE NULL END,
        'params', jsonb_build_object('title', v_activity.title, 'reason', coalesce(v_clean_reason, '')))
    );
  END LOOP;
END;
$$;


--
-- Name: cancel_booking(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_booking(p_booking_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_client_name TEXT;
  v_updated INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00420 D1 : un suspendu n'annule plus lui-même — ses réservations ont été
  -- auto-annulées à la suspension (admin_suspend_user).
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  -- 00443 B2 : IS DISTINCT FROM — sur une résa MANUELLE (client_id NULL),
  -- `!=` valait NULL et le IF ne levait pas : n'importe quel compte connaissant
  -- l'id pouvait l'annuler. Une manuelle n'a pas de client côté app : refus.
  IF v_bk IS NULL OR v_bk.client_id IS DISTINCT FROM v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'cancelled'
  WHERE id = p_booking_id AND status IN ('pending', 'accepted');
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Le pro n'est prévenu que si c'était CONFIRMÉ (un pending annulé disparaît).
  IF v_bk.status = 'accepted' THEN
    SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
    SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;
    PERFORM create_notification(
      v_bk.pro_id,
      'booking_cancelled',
      'Réservation annulée',
      coalesce(v_client_name, 'Un client') || ' a annulé « '
        || coalesce(v_off_title, 'une sortie') || ' » du ' || to_char(v_bk.day, 'DD/MM') || '.',
      jsonb_build_object('booking_id', v_bk.id, 'by', 'client', 'variant', 'by_client',
        'params', jsonb_build_object('name', coalesce(v_client_name, 'Un client'), 'title', coalesce(v_off_title, 'une sortie'),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD')))
    );
  END IF;
END;
$$;


--
-- Name: cancel_booking_pro(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_booking_pro(p_booking_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_pro_name TEXT;
  v_updated INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00420 D1 : idem côté pro.
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.pro_id != v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'cancelled_pro'
  WHERE id = p_booking_id AND status IN ('pending', 'accepted');
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_bk.client_id IS NOT NULL AND v_bk.status = 'accepted' THEN
    SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
    SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;
    PERFORM create_notification(
      v_bk.client_id,
      'booking_cancelled',
      'Sortie annulée',
      coalesce(v_pro_name, 'Le professionnel') || ' a annulé « '
        || coalesce(v_off_title, 'ta sortie') || ' » du ' || to_char(v_bk.day, 'DD/MM')
        || '. Contacte-le pour reprogrammer.',
      jsonb_build_object('booking_id', v_bk.id, 'by', 'pro', 'variant', 'by_pro',
        'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'), 'title', coalesce(v_off_title, 'ta sortie'),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD')))
    );
  END IF;
END;
$$;


--
-- Name: cancel_pending_seat_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_pending_seat_request(p_request_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_request RECORD;
  v_updated_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, requester_id, driver_id, activity_id, status
  INTO v_request
  FROM seat_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_request IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.requester_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_request.activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE seat_requests SET status = 'cancelled'
  WHERE id = p_request_id AND status = 'pending';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
END;
$$;


--
-- Name: cascade_block_cleanup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cascade_block_cleanup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_row RECORD;
  v_name TEXT;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 00522 (F2): a pending request of someone who is now in a block relation
  -- with an accepted member of that outing is withdrawn (it could never be
  -- accepted any more — the shared-outing rule would refuse it).
  -- 00523 (Scott, F2): the organiser is told that a block withdrew it — never
  -- who. Not when the organiser is a party (the refusal below covers it).
  FOR v_row IN
    UPDATE participations p
    SET status = 'withdrawn'
    FROM activities a
    WHERE a.id = p.activity_id
      AND p.status = 'pending'
      AND a.creator_id NOT IN (NEW.blocker_id, NEW.blocked_id)
      AND ((p.user_id = NEW.blocked_id AND EXISTS (SELECT 1 FROM participations q
              WHERE q.activity_id = p.activity_id AND q.user_id = NEW.blocker_id AND q.status = 'accepted'))
        OR (p.user_id = NEW.blocker_id AND EXISTS (SELECT 1 FROM participations q
              WHERE q.activity_id = p.activity_id AND q.user_id = NEW.blocked_id AND q.status = 'accepted')))
    RETURNING p.activity_id, p.user_id, a.creator_id, a.title
  LOOP
    SELECT display_name INTO v_name FROM public_profiles WHERE id = v_row.user_id;
    PERFORM create_notification(
      v_row.creator_id,
      'join_request_blocked',
      'Demande retirée',
      'La demande de ' || coalesce(v_name, 'quelqu''un') || ' pour « ' || v_row.title || ' » a été retirée : un blocage l''oppose à un participant.',
      jsonb_build_object('activity_id', v_row.activity_id,
        'params', jsonb_build_object('name', coalesce(v_name, 'Quelqu''un'), 'title', v_row.title))
    );
  END LOOP;

  -- Refuse pending join requests where blocker is creator and blocked is requester (or vice-versa)
  UPDATE participations p
  SET status = 'refused', refused_at = now()
  FROM activities a
  WHERE p.activity_id = a.id
    AND p.status = 'pending'
    AND ((a.creator_id = NEW.blocker_id AND p.user_id = NEW.blocked_id)
      OR (a.creator_id = NEW.blocked_id AND p.user_id = NEW.blocker_id));

  -- Cancel pending/accepted seat requests in both directions
  UPDATE seat_requests
  SET status = 'cancelled'
  WHERE status IN ('pending', 'accepted')
    AND ((requester_id = NEW.blocker_id AND driver_id = NEW.blocked_id)
      OR (requester_id = NEW.blocked_id AND driver_id = NEW.blocker_id));

  RETURN NEW;
END;
$$;


--
-- Name: cascade_block_invited(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cascade_block_invited() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  DELETE FROM participations p
  USING activities a
  WHERE p.activity_id = a.id
    AND p.status = 'invited'
    AND (
      (p.user_id = NEW.blocked_id AND a.creator_id = NEW.blocker_id)
      OR (p.user_id = NEW.blocker_id AND a.creator_id = NEW.blocked_id)
    );
  RETURN NEW;
END;
$$;


--
-- Name: cascade_block_to_requests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cascade_block_to_requests() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_u1 UUID;
  v_u2 UUID;
BEGIN
  IF NEW.blocker_id < NEW.blocked_id THEN
    v_u1 := NEW.blocker_id; v_u2 := NEW.blocked_id;
  ELSE
    v_u1 := NEW.blocked_id; v_u2 := NEW.blocker_id;
  END IF;

  UPDATE conversations
  SET status = 'declined'
  WHERE user_1 = v_u1 AND user_2 = v_u2
    AND status = 'pending_request';

  RETURN NEW;
END;
$$;


--
-- Name: channels_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.channels_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.conversation_id := OLD.conversation_id;
  NEW.sport_key := OLD.sport_key;
  NEW.base := OLD.base;
  NEW.base_label := OLD.base_label;
  NEW.radius_km := OLD.radius_km;
  NEW.photo_url := OLD.photo_url;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;


--
-- Name: check_activity_transitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_activity_transitions() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('activity_transitions')) THEN
    RETURN;
  END IF;

  -- 00495: each step isolated — a failure in one must not roll back the
  -- others (presence finalisation, notifications, expirations).
  BEGIN PERFORM transition_statuses_only();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'transition_statuses_only: %', SQLERRM; END;
  BEGIN PERFORM expire_stale_contact_requests();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'expire_stale_contact_requests: %', SQLERRM; END;
  BEGIN PERFORM expire_idle_seat_requests();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'expire_idle_seat_requests: %', SQLERRM; END;
END;
$$;


--
-- Name: check_alerts_for_activity(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_alerts_for_activity(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_activity RECORD;
  v_sport_key TEXT;
  v_activity_date DATE;
  v_alert RECORD;
  v_today_count INTEGER;
BEGIN
  SELECT a.id, a.creator_id, a.title, a.location_meeting,
         a.starts_at, a.level, a.status, a.deleted_at, s.key AS sport_key
  INTO v_activity
  FROM activities a JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'published' OR v_activity.deleted_at IS NOT NULL THEN
    RETURN;
  END IF;

  v_sport_key := v_activity.sport_key;
  v_activity_date := (v_activity.starts_at AT TIME ZONE 'Europe/Paris')::date;  -- 00523

  FOR v_alert IN
    SELECT a.id, a.user_id
    FROM activity_alerts a
    WHERE a.user_id != v_activity.creator_id
      AND (a.sport_key IS NULL OR a.sport_key = v_sport_key)
      AND (a.levels IS NULL OR v_activity.level = ANY(a.levels))
      AND (a.starts_on IS NULL OR v_activity_date >= a.starts_on)
      AND (a.ends_on IS NULL OR v_activity_date <= a.ends_on)
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_activity.creator_id AND b.blocked_id = a.user_id)
           OR (b.blocker_id = a.user_id AND b.blocked_id = v_activity.creator_id)
      )
      AND ST_DWithin(a.location, v_activity.location_meeting, a.radius_km * 1000)
  LOOP
    -- Per-user advisory lock so the count+insert is atomic vs. concurrent
    -- alert checks for the same user (multiple activities published in parallel).
    PERFORM pg_advisory_xact_lock(hashtext('alert_match_' || v_alert.user_id::text));

    SELECT count(*) INTO v_today_count
    FROM notifications
    WHERE user_id = v_alert.user_id
      AND type = 'alert_match'
      AND created_at >= (private.today_paris()::timestamp AT TIME ZONE 'Europe/Paris');  -- 00523: Paris day

    IF v_today_count >= 3 THEN CONTINUE; END IF;

    PERFORM create_notification(
      v_alert.user_id,
      'alert_match',
      'Nouvelle sortie pour ton alerte',
      '« ' || v_activity.title || ' »',
      jsonb_build_object('activity_id', p_activity_id,
        'params', jsonb_build_object('title', v_activity.title))
    );
  END LOOP;
END;
$$;


--
-- Name: cleanup_notifications_on_conversation_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_notifications_on_conversation_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  DELETE FROM notifications WHERE data->>'conversation_id' = OLD.id::text;
  RETURN OLD;
END;
$$;


--
-- Name: clear_missing_on_shared_gear(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clear_missing_on_shared_gear() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  DELETE FROM activity_gear_missing
  WHERE activity_id = NEW.activity_id
    AND lower(name) = lower(NEW.gear_name);
  RETURN NEW;
END;
$$;


--
-- Name: clear_push_token_on_suspension(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clear_push_token_on_suspension() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE id = NEW.id AND push_token IS NOT NULL;
  DELETE FROM push_tokens WHERE user_id = NEW.id;
  RETURN NEW;
END;
$$;


--
-- Name: close_channel(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_channel(p_conversation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF v_creator IS NULL OR v_creator != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE channels SET closed_at = now() WHERE conversation_id = p_conversation_id AND closed_at IS NULL;
END;
$$;


--
-- Name: close_due_presence_windows(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_due_presence_windows() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  FOR v_activity_id IN
    SELECT a.id
    FROM activities a
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.starts_at + a.duration + INTERVAL '24 hours' < now()
      AND a.starts_at + a.duration + INTERVAL '48 hours' > now()  -- 00495
      AND a.deleted_at IS NULL
      -- 00432 : ne JAMAIS finaliser une sortie dont le créateur est suspendu.
      -- Les 4 boucles de notification l'excluent déjà (00427) — sans cette
      -- garde, l'asymétrie était la pire des deux : les participants ne
      -- recevaient plus AUCUN signal, n'avaient aucun QR possible
      -- (create_presence_token refuse), et prenaient quand même tous une
      -- absence + pénalité de fiabilité à fin+24h sans avoir rien pu faire.
      AND NOT EXISTS (
        SELECT 1 FROM users c
        WHERE c.id = a.creator_id AND c.suspended_at IS NOT NULL
      )
      AND EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id
          AND p.status = 'accepted'
          AND p.confirmed_present IS NULL
      )
  LOOP
    PERFORM close_presence_window_for(v_activity_id);
  END LOOP;

  -- 00491 (PR-2 / BR-2): votes left uncounted — an outing where everybody
  -- was already validated (the loop above skips it) or one without presence
  -- check. Bounded to outings ended in the last 14 days.
  FOR v_activity_id IN
    SELECT a.id
    FROM activities a
    WHERE a.status = 'completed'
      AND a.deleted_at IS NULL
      AND a.starts_at + a.duration + INTERVAL '24 hours' < now()
      AND a.starts_at + a.duration + INTERVAL '48 hours' > now()  -- 00495
      AND a.requires_presence = TRUE  -- 00495
      AND NOT EXISTS (SELECT 1 FROM users c WHERE c.id = a.creator_id AND c.suspended_at IS NOT NULL)
      AND EXISTS (SELECT 1 FROM reputation_votes rv WHERE rv.activity_id = a.id AND rv.counted_at IS NULL)
  LOOP
    PERFORM close_presence_window_for(v_activity_id);
  END LOOP;
END;
$$;


--
-- Name: close_presence_window_for(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_presence_window_for(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_accepted_count INTEGER;
BEGIN
  SELECT id, status, starts_at, duration, requires_presence, creator_id, deleted_at
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  -- 00429 : ne JAMAIS finaliser (donc ne jamais poser d'absence ni de pénalité)
  -- sur une sortie retirée par la modération. Le balayage cron filtre déjà
  -- deleted_at (00107) ; le chemin lazy, non → un participant qui ouvrait une
  -- vieille notification déclenchait les absences que le cron refusait de poser.
  IF v_activity.deleted_at IS NOT NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF now() <= v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;
  -- 00491 (PR-1): never finalise the outing of a suspended organiser — its
  -- participants received no reminder and could get no QR. Whoever calls.
  IF EXISTS (SELECT 1 FROM users c WHERE c.id = v_activity.creator_id AND c.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00495: outings WITHOUT presence check never count votes (00491's BR-2
  -- counting let two accounts farm or smear a reputation with a fake
  -- outing — pending Scott's decision on soliciting votes there at all).
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  -- 00495: finalise only in the normal window (end + 24 h … + 48 h). Later
  -- means the outing was frozen (organiser suspended, then reinstated):
  -- nobody gets an absence after the fact.
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '48 hours' THEN RETURN; END IF;

  -- Deferred evaluations: commit (make count) every reputation vote whose BOTH
  -- parties ended up confirmed present. Runs before the presence branching
  -- below — the confirmed-present set is already fixed (finalisation only flips
  -- NULLs to FALSE / neutralises, never adds a TRUE). requires_presence = false
  -- returned earlier, so a no-presence activity never commits any vote, and if
  -- nobody was confirmed present there is simply no anchored pair to commit.
  UPDATE reputation_votes rv
  SET counted_at = now()
  WHERE rv.activity_id = p_activity_id
    AND rv.counted_at IS NULL
    AND rv.voter_id <> rv.voted_id  -- defensive: a self-vote would break the CHECK re-validation
    AND EXISTS (
      SELECT 1 FROM participations pv
      WHERE pv.activity_id = p_activity_id
        AND pv.user_id = rv.voter_id
        AND pv.status = 'accepted'
        AND pv.confirmed_present = TRUE
    )
    AND EXISTS (
      SELECT 1 FROM participations pt
      WHERE pt.activity_id = p_activity_id
        AND pt.user_id = rv.voted_id
        AND pt.status = 'accepted'
        AND pt.confirmed_present = TRUE
    );

  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  -- Solo (creator alone): "absent" is undefined. Leave NULL untouched.
  IF v_accepted_count < 2 THEN RETURN; END IF;

  -- Rule C — exactly 2: presence only via QR/geo (peer testimony is circular).
  -- A non-creator confirmation auto-validates both (rule A), so its ABSENCE
  -- means the meetup wasn't verifiable -> re-expire, wipe any lone self-
  -- validation so nothing counts, and never penalise.
  IF v_accepted_count = 2 THEN
    IF NOT EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted'
        AND user_id != v_activity.creator_id AND confirmed_present = TRUE
    ) THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE activities SET status = 'expired', updated_at = now()
      WHERE id = p_activity_id AND status = 'completed';
      FOR v_target IN
        SELECT user_id FROM participations
        WHERE activity_id = p_activity_id AND status = 'accepted'
          AND confirmed_present IS NOT NULL
      LOOP
        UPDATE participations SET confirmed_present = NULL
        WHERE activity_id = p_activity_id AND user_id = v_target.user_id AND status = 'accepted';
        PERFORM recalculate_reliability_score(v_target.user_id);
      END LOOP;
    END IF;
    RETURN;
  END IF;

  -- 3+ : the review happened iff at least one participant is confirmed present.
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- Nobody confirmed -> the review never ran. Can't tell absent from forgotten:
  -- stay neutral for everyone (expire, no penalty), like the 2-person case.
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND status = 'accepted' AND confirmed_present = TRUE
  ) THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'completed';
    RETURN;
  END IF;

  -- At least one presence established -> the unconfirmed are genuine no-shows.
  FOR v_target IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id
      AND status = 'accepted'
      AND confirmed_present IS NULL
  LOOP
    UPDATE participations
    SET confirmed_present = FALSE
    WHERE activity_id = p_activity_id
      AND user_id = v_target.user_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;

    PERFORM recalculate_reliability_score(v_target.user_id);
  END LOOP;
END;
$$;


--
-- Name: compute_trace_stats(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_trace_stats(p_geojson jsonb) RETURNS TABLE(distance_km numeric, elevation_gain_m integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_geom geometry;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('trace_stats', 600, INTERVAL '1 hour');

  -- 00482: everything after the counter runs in a sub-block that swallows
  -- its own failures, so an invalid trace still COUNTS (a raise would roll
  -- the counter back and make the expensive failing path free). An invalid
  -- trace now yields no stats, which the client already treats as "none".
  BEGIN
  -- 00470 (audit L7): cheap shape/size gate before the PostGIS parse.
  IF p_geojson IS NULL OR NOT trace_geojson_ok(p_geojson) THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  BEGIN
    v_geom := ST_GeomFromGeoJSON(p_geojson::text);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END;
  IF ST_GeometryType(v_geom) <> 'ST_LineString'
     OR ST_NPoints(v_geom) < 2
     OR ST_NPoints(v_geom) > 10000 THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  RETURN QUERY SELECT trace_distance_km(p_geojson), trace_elevation_gain_m(p_geojson);
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT NULL::numeric, NULL::integer;
  END;
END;
$$;


--
-- Name: confirm_age_adult(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_age_adult() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Idempotent: already confirmed → no-op (re-confirming is harmless).
  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND age_confirmed_at IS NOT NULL) THEN
    RETURN;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET age_confirmed_at = now() WHERE id = auth.uid();
END;
$$;


--
-- Name: confirm_presence_via_geo(uuid, double precision, double precision, timestamp with time zone, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_presence_via_geo(p_activity_id uuid, p_lng double precision, p_lat double precision, p_captured_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_skip_push boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_user_point GEOGRAPHY;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_d_trace FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_window_anchor TIMESTAMPTZ;
  v_creator_id UUID;
  v_creator_flipped INTEGER;
  v_requires_presence BOOLEAN;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration, status, deleted_at, creator_id, requires_presence, is_demo
  INTO v_starts_at, v_duration, v_status, v_deleted_at, v_creator_id, v_requires_presence, v_is_demo
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00429 : une sortie qui ne demande PAS de validation de présence n'a aucun
  -- chemin de confirmation (le finaliseur sort tôt, donc aucun risque de FALSE)
  -- → confirmer y gonflait le score de fiabilité sans risque de baisse.
  IF v_requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  -- 00429 : rideau démo côté ÉCRITURE, garde ABSOLUE (admin en mode démo
  -- compris) — même règle que join_activity et que les envois de 00426.
  IF v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- RESTAURÉ (00292) — Invariant : la présence du créateur n'est JAMAIS
  -- auto-attestée. No-op silencieux (pas une erreur : le client ne propose
  -- pas le bouton, un appel direct ne doit simplement rien faire).
  IF v_user_id = v_creator_id THEN RETURN; END IF;

  -- Reject cancelled / expired activities, and soft-deleted ones. The
  -- time-window check below catches future-dated activities, but a
  -- creator cancelling within the validation window would otherwise
  -- still allow validations.
  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;

  IF p_captured_at IS NULL THEN
    v_window_anchor := now();
  ELSE
    -- 00419 : un événement « capturé dans le futur » est forcément forgé
    -- (2 min de tolérance d'horloge pour les replays offline légitimes).
    IF p_captured_at > now() + INTERVAL '2 minutes' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 00429 : la borne d'ARRIVÉE du rejeu passe de fin+3h à fin+24h (alignée
    -- sur la fenêtre de témoignage et sur l'auto-absence). Scénario outdoor
    -- normal : fin 17h, réseau retrouvé à 18h30, app ouverte à 21h → la preuve
    -- était valide et mesurée sur place, elle était jetée. L'anti-fraude réel
    -- reste l'heure de CAPTURE (fenêtre T±15min, vérifiée juste en dessous),
    -- la distance, le refus du futur et l'idempotence — pas l'heure d'arrivée.
    IF now() > v_starts_at + v_duration + INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.presence_window_closed';
    END IF;
    v_window_anchor := p_captured_at;
  END IF;

  IF v_window_anchor < v_starts_at - INTERVAL '15 minutes'
     OR v_window_anchor > v_starts_at + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.presence_window_closed';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RETURN; END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  -- CORRIGÉ (00428) : location_start a été SUPPRIMÉE en 00306 (fusionnée dans
  -- location_meeting). 00419 la référençait encore → la fonction levait
  -- « column location_start does not exist » à CHAQUE appel. Les trois points
  -- valides sont meeting / end / trace.
  SELECT
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END,
    CASE WHEN trace_geojson IS NOT NULL
         THEN ST_Distance(ST_GeomFromGeoJSON(trace_geojson::text)::geography, v_user_point)
         ELSE NULL END
  INTO v_d_meeting, v_d_end, v_d_trace
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end,     999999),
    coalesce(v_d_trace,   999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'junto.presence_too_far';
  END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id, p_skip_push);

  -- RESTAURÉ (00292) — Règle A : un non-créateur qui confirme PROUVE que la
  -- sortie a eu lieu → la présence du créateur est validée automatiquement.
  -- C'est le SEUL chemin de validation du créateur côté géo (il n'est jamais
  -- relancé par les notifications, précisément parce que cette règle existe).
  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, p_activity_id, p_skip_push);
    END IF;
  END IF;
END;
$$;


--
-- Name: confirm_presence_via_token(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_presence_via_token(p_token text, p_skip_push boolean DEFAULT true) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_token_record RECORD;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_activity_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_creator_id UUID;
  v_creator_flipped INTEGER;
  v_requires_presence BOOLEAN;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT activity_id, expires_at INTO v_token_record
  FROM presence_tokens WHERE token = p_token;
  IF v_token_record IS NULL OR v_token_record.expires_at < now() THEN
    RAISE EXCEPTION 'junto.presence_token_invalid';
  END IF;

  v_activity_id := v_token_record.activity_id;

  SELECT starts_at, duration, status, deleted_at, creator_id, requires_presence, is_demo
  INTO v_starts_at, v_duration, v_status, v_deleted_at, v_creator_id, v_requires_presence, v_is_demo
  FROM activities WHERE id = v_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00429 : une sortie qui ne demande PAS de validation de présence n'a aucun
  -- chemin de confirmation (le finaliseur sort tôt, donc aucun risque de FALSE)
  -- → confirmer y gonflait le score de fiabilité sans risque de baisse.
  IF v_requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  -- 00429 : rideau démo côté ÉCRITURE, garde ABSOLUE (admin en mode démo
  -- compris) — même règle que join_activity et que les envois de 00426.
  IF v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;

  -- Invariant: the creator never self-confirms (via their own QR either).
  IF v_user_id = v_creator_id THEN RETURN v_activity_id; END IF;

  IF now() < v_starts_at - INTERVAL '15 minutes' OR now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
    RAISE EXCEPTION 'junto.presence_window_closed';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = v_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RETURN v_activity_id; END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, v_activity_id, p_skip_push);

  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = v_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, v_activity_id, p_skip_push);
    END IF;
  END IF;

  RETURN v_activity_id;
END;
$$;


--
-- Name: connect_via_qr_token(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.connect_via_qr_token(p_token text, p_expected_owner uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_owner UUID;
  v_user_1 UUID;
  v_user_2 UUID;
  v_conv RECORD;
  v_conversation_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- L5: a suspended or demo account never scans.
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND (suspended_at IS NOT NULL OR is_demo)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Scan quota first. From here on, every failure RETURNs NULL instead of
  -- raising, so the quota row is kept and failed attempts count too (L1).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_qr_scan'));
  DELETE FROM contact_qr_scans WHERE user_id = v_user_id AND scanned_at < now() - INTERVAL '1 hour';
  SELECT count(*) INTO v_count FROM contact_qr_scans WHERE user_id = v_user_id;
  IF v_count >= 30 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO contact_qr_scans (user_id) VALUES (v_user_id);

  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN NULL; END IF;

  -- Opportunistic sweep of long-dead tokens (anyone's).
  DELETE FROM contact_qr_tokens WHERE created_at < now() - INTERVAL '1 day';

  SELECT user_id INTO v_owner FROM contact_qr_tokens
  WHERE token = p_token AND expires_at > now();
  IF v_owner IS NULL OR v_owner = v_user_id THEN RETURN NULL; END IF;
  -- L2: the id printed in the QR must be the token's owner.
  IF p_expected_owner IS NOT NULL AND p_expected_owner <> v_owner THEN RETURN NULL; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_owner AND suspended_at IS NULL AND is_demo = false
  ) THEN
    RETURN NULL;
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_owner)
       OR (blocker_id = v_owner AND blocked_id = v_user_id)
  ) THEN
    RETURN NULL;
  END IF;

  IF v_user_id < v_owner THEN
    v_user_1 := v_user_id; v_user_2 := v_owner;
  ELSE
    v_user_1 := v_owner; v_user_2 := v_user_id;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_user_1::text || '_' || v_user_2::text || '_dm'));

  SELECT * INTO v_conv FROM conversations
  WHERE type = 'dm' AND user_1 = v_user_1 AND user_2 = v_user_2
  FOR UPDATE;

  IF v_conv.id IS NOT NULL THEN
    IF v_conv.status = 'active' THEN RETURN v_conv.id; END IF;
    UPDATE conversations
    SET status = 'active', request_expires_at = NULL, last_message_at = now()
    WHERE id = v_conv.id;
    -- M3: only a request that was still pending carries a message worth
    -- opening the thread with; a declined one stays unpublished.
    IF v_conv.status = 'pending_request'
       AND v_conv.request_sender_id IS NOT NULL
       AND v_conv.request_message IS NOT NULL
       AND char_length(trim(v_conv.request_message)) > 0 THEN
      INSERT INTO messages (conversation_id, sender_id, content, created_at)
      VALUES (v_conv.id, v_conv.request_sender_id, v_conv.request_message, now());
    END IF;
    -- M3: a pending outing-invite link is consumed (it was never meant to
    -- ride on a QR connection).
    IF v_conv.pending_activity_id IS NOT NULL THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE conversations SET pending_activity_id = NULL WHERE id = v_conv.id;
      PERFORM set_config('junto.bypass_lock', 'false', true);
    END IF;
    RETURN v_conv.id;
  END IF;

  INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, created_at, last_message_at)
  VALUES (v_user_1, v_user_2, v_user_id, 'active', 'profile', NULL, now(), now())
  RETURNING id INTO v_conversation_id;

  RETURN v_conversation_id;
END;
$_$;


--
-- Name: consume_snap_trail_quota(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consume_snap_trail_quota() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user UUID;
  v_count INTEGER;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_snap_trail'));
  -- 00522 (F3): rows are kept a day (purged by the daily job) so the global
  -- daily ceiling really counts the day; the per-user limit counts the hour.
  SELECT count(*) INTO v_count FROM snap_trail_calls WHERE user_id = v_user AND called_at > now() - INTERVAL '1 hour';
  IF v_count >= 200 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  -- 00520 (AB-7): a global daily ceiling protects the shared routing quota.
  IF (SELECT count(*) FROM snap_trail_calls WHERE called_at > now() - INTERVAL '1 day') >= 1500 THEN
    RAISE EXCEPTION 'junto.rate_limited';
  END IF;
  INSERT INTO snap_trail_calls (user_id) VALUES (v_user);
END;
$$;


--
-- Name: consume_trace_elevation_points(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consume_trace_elevation_points(p_points integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user UUID;
  v_sum BIGINT;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_points IS NULL OR p_points < 1 OR p_points > 10000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_trace_elevation'));
  SELECT coalesce(sum(points), 0) INTO v_sum FROM trace_elevation_calls
  WHERE user_id = v_user AND called_at > now() - INTERVAL '1 hour';
  IF v_sum + p_points > 50000 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO trace_elevation_calls (user_id, points) VALUES (v_user, p_points);
END;
$$;


--
-- Name: consume_trace_elevation_quota(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.consume_trace_elevation_quota() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user UUID;
  v_count INTEGER;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_trace_elevation'));
  DELETE FROM trace_elevation_calls WHERE user_id = v_user AND called_at < now() - INTERVAL '1 hour';
  -- 00474 (counter-audit F1): only CALL rows (points = 0) count here; the
  -- points rows added by 00471 halved the call quota.
  SELECT count(*) INTO v_count FROM trace_elevation_calls WHERE user_id = v_user AND points = 0;
  IF v_count >= 150 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO trace_elevation_calls (user_id) VALUES (v_user);
END;
$$;


--
-- Name: conversation_members_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.conversation_members_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.conversation_id := OLD.conversation_id;
  NEW.user_id := OLD.user_id;
  NEW.added_by := OLD.added_by;
  NEW.joined_at := OLD.joined_at;
  RETURN NEW;
END;
$$;


--
-- Name: conversations_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.conversations_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.user_1 := OLD.user_1;
  NEW.user_2 := OLD.user_2;
  NEW.type := OLD.type;
  NEW.activity_id := OLD.activity_id;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  NEW.initiated_by := OLD.initiated_by;
  NEW.initiated_from := OLD.initiated_from;
  NEW.request_sender_id := OLD.request_sender_id;
  NEW.pending_activity_id := OLD.pending_activity_id;
  RETURN NEW;
END;
$$;


--
-- Name: create_activity(uuid, text, text, text, integer, double precision, double precision, double precision, double precision, timestamp with time zone, text, text, boolean, double precision, double precision, text, numeric, integer, text, jsonb, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_activity(p_sport_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_end_lng double precision DEFAULT NULL::double precision, p_end_lat double precision DEFAULT NULL::double precision, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_duration text DEFAULT '2 hours'::text, p_visibility text DEFAULT 'public'::text, p_requires_presence boolean DEFAULT true, p_objective_lng double precision DEFAULT NULL::double precision, p_objective_lat double precision DEFAULT NULL::double precision, p_objective_name text DEFAULT NULL::text, p_distance_km numeric DEFAULT NULL::numeric, p_elevation_gain_m integer DEFAULT NULL::integer, p_meeting_name text DEFAULT NULL::text, p_trace_geojson jsonb DEFAULT NULL::jsonb, p_level_max text DEFAULT NULL::text, p_meeting_locality text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_is_admin BOOLEAN;
  v_daily_count INTEGER;
  v_monthly_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
  v_level_max TEXT;
  v_distance_km NUMERIC;
  v_elevation_gain_m INTEGER;
BEGIN
  -- Sensitive: generic.
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00516: coordinates must be real places (NaN and out-of-range refused).
  IF NOT ((p_meeting_lng IS NULL AND p_meeting_lat IS NULL) OR (p_meeting_lng BETWEEN -180 AND 180 AND p_meeting_lat BETWEEN -90 AND 90)) OR p_meeting_lng IS NULL
     OR NOT ((p_end_lng IS NULL AND p_end_lat IS NULL) OR (p_end_lng BETWEEN -180 AND 180 AND p_end_lat BETWEEN -90 AND 90))
     OR NOT ((p_objective_lng IS NULL AND p_objective_lat IS NULL) OR (p_objective_lng BETWEEN -180 AND 180 AND p_objective_lat BETWEEN -90 AND 90)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- User-actionable: coded.
  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;

  -- Normalise the range high end: empty → NULL; equal to the low end → NULL
  -- (single level). Scale membership/ordering enforced client-side.
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'junto.date_in_past';
  END IF;

  IF p_starts_at > NOW() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.date_too_far';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'junto.participants_range';
  END IF;

  -- Tamper guard (UI only sends valid values): generic.
  IF p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00470 (audit M6): the trace is validated before anything else touches it.
  IF p_trace_geojson IS NOT NULL AND NOT trace_geojson_ok(p_trace_geojson) THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT tier, coalesce(is_admin, FALSE) INTO v_tier, v_is_admin
  FROM users WHERE id = v_user_id;

  -- Private-link visibilities are open to everyone (Scott 2026-07-10):
  -- all tiers are free at launch. Premium gate removed.

  IF NOT v_is_admin THEN
    SELECT count(*) INTO v_daily_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

    IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.limit_daily'; END IF;

    SELECT count(*) INTO v_monthly_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '30 days';

    IF v_monthly_count >= 30 THEN RAISE EXCEPTION 'junto.limit_monthly'; END IF;
  END IF;

  -- Trace-derived prefill (00452), after the rate limits (00470, audit L7):
  -- the typed value always wins; a derived figure outside the column's range
  -- (flat or descending trace → 0 m, degenerate or absurd distance) stays
  -- NULL instead of failing the insert (00470, audit M5).
  v_distance_km := p_distance_km;
  v_elevation_gain_m := p_elevation_gain_m;
  IF p_trace_geojson IS NOT NULL THEN
    IF v_distance_km IS NULL THEN
      v_distance_km := trace_distance_km(p_trace_geojson);
      IF round(v_distance_km, 1) <= 0 OR v_distance_km > 9999 THEN v_distance_km := NULL; END IF;
    END IF;
    IF v_elevation_gain_m IS NULL THEN
      v_elevation_gain_m := NULLIF(trace_elevation_gain_m(p_trace_geojson), 0);
      IF v_elevation_gain_m > 99999 THEN v_elevation_gain_m := NULL; END IF;
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level, level_max,
    max_participants, location_meeting, location_end,
    location_objective, objective_name, meeting_name, meeting_locality,
    distance_km, elevation_gain_m,
    starts_at, duration, visibility, requires_presence,
    trace_geojson,
    status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_title, trim(p_description), p_level, v_level_max,
    p_max_participants,
    ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography,
    CASE WHEN p_end_lng IS NOT NULL AND p_end_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_end_lng, p_end_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_lng IS NOT NULL AND p_objective_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_objective_lng, p_objective_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_name IS NOT NULL AND char_length(trim(p_objective_name)) > 0
      THEN trim(p_objective_name) ELSE NULL END,
    CASE WHEN p_meeting_name IS NOT NULL AND char_length(trim(p_meeting_name)) > 0
      THEN trim(p_meeting_name) ELSE NULL END,
    CASE WHEN p_meeting_locality IS NOT NULL AND char_length(trim(p_meeting_locality)) > 0
      THEN left(trim(p_meeting_locality), 80) ELSE NULL END,
    v_distance_km,
    v_elevation_gain_m,
    p_starts_at, p_duration::interval, p_visibility, coalesce(p_requires_presence, TRUE),
    p_trace_geojson,
    'published', now(), now()
  ) RETURNING id INTO v_activity_id;

  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_user_id, 'accepted', now());

  IF p_visibility IN ('public', 'approval') THEN
    PERFORM check_alerts_for_activity(v_activity_id);
  END IF;

  RETURN v_activity_id;
END;
$$;


--
-- Name: create_activity_conversation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_activity_conversation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO conversations (type, activity_id, status, created_at)
  VALUES ('activity', NEW.id, 'active', now())
  ON CONFLICT (activity_id) WHERE activity_id IS NOT NULL DO NOTHING;
  RETURN NEW;
END;
$$;


--
-- Name: create_alert(double precision, double precision, integer, text, text[], date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_alert(p_lng double precision, p_lat double precision, p_radius_km integer, p_sport_key text DEFAULT NULL::text, p_levels text[] DEFAULT NULL::text[], p_starts_on date DEFAULT NULL::date, p_ends_on date DEFAULT NULL::date) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_alert_count INTEGER;
  v_alert_id UUID;
  v_allowed_levels TEXT[] := ARRAY['débutant', 'intermédiaire', 'avancé', 'expert'];
  v_level TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00499 (DC-6): validated inputs.
  IF p_lng IS NULL OR p_lat IS NULL OR p_lng NOT BETWEEN -180 AND 180 OR p_lat NOT BETWEEN -90 AND 90
     OR p_radius_km IS NULL OR p_radius_km NOT BETWEEN 5 AND 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_sport_key IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = p_sport_key AND s.is_active) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Serialise the cap.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_alerts'));

  SELECT count(*) INTO v_alert_count FROM activity_alerts WHERE user_id = v_user_id;
  IF v_alert_count >= 10 THEN
    RAISE EXCEPTION 'junto.alert_limit_reached';
  END IF;

  IF p_levels IS NOT NULL THEN
    IF array_length(p_levels, 1) IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    FOREACH v_level IN ARRAY p_levels LOOP
      IF NOT (v_level = ANY(v_allowed_levels)) THEN
        RAISE EXCEPTION 'Operation not permitted';
      END IF;
    END LOOP;
  END IF;

  IF p_starts_on IS NOT NULL AND p_ends_on IS NOT NULL AND p_ends_on < p_starts_on THEN
    RAISE EXCEPTION 'junto.alert_date_invalid';
  END IF;
  IF p_ends_on IS NOT NULL AND p_ends_on < private.today_paris() THEN
    RAISE EXCEPTION 'junto.alert_date_invalid';
  END IF;

  INSERT INTO activity_alerts (user_id, sport_key, location, radius_km, levels, starts_on, ends_on, created_at)
  VALUES (
    v_user_id,
    p_sport_key,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_radius_km,
    p_levels,
    p_starts_on,
    p_ends_on,
    now()
  )
  RETURNING id INTO v_alert_id;

  RETURN v_alert_id;
END;
$$;


--
-- Name: create_booking(uuid, date, text, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_off RECORD;
  v_msg TEXT;
  v_existing RECORD;
  v_booking_id UUID;
  v_client_name TEXT;
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT po.id, po.pro_id, po.title, po.max_participants, pp.is_demo
    INTO v_off
  FROM pro_offerings po
  JOIN pro_profiles pp ON pp.user_id = po.pro_id
  JOIN users u ON u.id = po.pro_id
  WHERE po.id = p_offering_id
    AND pp.status = 'approved'
    AND u.suspended_at IS NULL
    AND u.tier = 'pro'
  -- 00518 (L4): the offering cannot be deleted while this booking is created.
  FOR SHARE OF po;
  IF v_off IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_off.pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_off.is_demo = true AND NOT demo_content_visible() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_off.pro_id)
       OR (blocker_id = v_off.pro_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_day IS NULL OR p_day < private.today_paris() OR p_day > private.today_paris() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pro_availabilities
    WHERE pro_id = v_off.pro_id AND day = p_day AND period = p_period
  ) THEN
    RAISE EXCEPTION 'junto.booking_slot_unavailable';
  END IF;

  IF p_party_size IS NULL
     OR p_party_size < 1
     OR p_party_size > LEAST(coalesce(v_off.max_participants, 50), 50) THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;

  v_msg := nullif(regexp_replace(trim(coalesce(p_message, '')), '<[^>]*>', '', 'g'), '');
  IF v_msg IS NOT NULL AND char_length(v_msg) > 500 THEN
    RAISE EXCEPTION 'junto.booking_message';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_booking'));
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND status = 'pending'
        AND day >= private.today_paris()) >= 5 THEN  -- 00523: past days never block
    RAISE EXCEPTION 'junto.booking_pending_cap';
  END IF;
  -- Cap quotidien inchangé : le trou H1 (cycles annuler/recréer sur la même
  -- ligne) est fermé par le cooldown 1 h + le plafond 5 soumissions/ligne
  -- ci-dessous — sans surcompter les soumissions anciennes d'une ligne réactivée.
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND created_at > now() - INTERVAL '24 hours') >= 10 THEN
    RAISE EXCEPTION 'junto.booking_daily_cap';
  END IF;

  SELECT * INTO v_existing FROM bookings
  WHERE offering_id = p_offering_id AND client_id = v_user_id
    AND day = p_day AND period = p_period
  FOR UPDATE;

  IF v_existing.id IS NOT NULL THEN  -- 00477: a RECORD with any NULL field is never « IS NOT NULL »
    IF v_existing.status IN ('pending', 'accepted') THEN
      RAISE EXCEPTION 'junto.booking_already';
    END IF;
    -- Anti-spam (00418 H1) : cooldown 1 h entre soumissions du même créneau,
    -- plafond 5 soumissions par créneau à vie.
    IF v_existing.last_submitted_at > now() - INTERVAL '1 hour' THEN
      RAISE EXCEPTION 'junto.booking_cooldown';
    END IF;
    IF v_existing.submitted_count >= 5 THEN
      RAISE EXCEPTION 'junto.booking_cooldown';
    END IF;
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = 'pending', party_size = p_party_size, message = v_msg,
        created_at = now(),
        -- 00505: a re-submitted request takes the current price.
        price_eur = (SELECT o.price_eur FROM pro_offerings o WHERE o.id = p_offering_id),
        price_unit = (SELECT o.price_unit::text FROM pro_offerings o WHERE o.id = p_offering_id),
        submitted_count = v_existing.submitted_count + 1,
        last_submitted_at = now()
    WHERE id = v_existing.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_booking_id := v_existing.id;
  ELSE
    BEGIN
      -- 00501 (PO-5): the price the client asked at is kept with the booking.
      INSERT INTO bookings (offering_id, pro_id, client_id, day, period, party_size, message, price_eur, price_unit)
      VALUES (p_offering_id, v_off.pro_id, v_user_id, p_day, p_period, p_party_size, v_msg,
              (SELECT o.price_eur FROM pro_offerings o WHERE o.id = p_offering_id),
              (SELECT o.price_unit::text FROM pro_offerings o WHERE o.id = p_offering_id))
      RETURNING id INTO v_booking_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'junto.booking_already';
    END;
  END IF;

  SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;
  v_period_label := CASE p_period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;

  PERFORM create_notification(
    v_off.pro_id,
    'booking_request',
    'Nouvelle demande de réservation',
    coalesce(v_client_name, 'Un membre') || ' · « ' || v_off.title || ' » · '
      || to_char(p_day, 'DD/MM') || ', ' || v_period_label
      || ' · ' || p_party_size || ' pers.',
    jsonb_build_object('booking_id', v_booking_id, 'offering_id', p_offering_id,
      'params', jsonb_build_object('name', coalesce(v_client_name, 'Un membre'), 'title', v_off.title,
                                   'date', to_char(p_day, 'YYYY-MM-DD'), 'period', p_period, 'count', p_party_size))
  );

  RETURN v_booking_id;
END;
$$;


--
-- Name: create_channel(text, double precision, double precision, text, integer, text, text, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_channel(p_name text, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_sport_key text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_photo_url text DEFAULT NULL::text, p_force boolean DEFAULT false) RETURNS TABLE(conversation_id uuid, duplicate boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_clean_desc TEXT;
  v_label TEXT;
  v_base GEOGRAPHY;
  v_sport TEXT;
  v_photo TEXT;
  v_open_count INTEGER;
  v_daily INTEGER;
  v_existing UUID;
  v_conv_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_name IS NULL OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.channel_name';
  END IF;

  v_clean_desc := NULLIF(trim(regexp_replace(COALESCE(p_description, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_desc IS NOT NULL AND char_length(v_clean_desc) > 500 THEN
    RAISE EXCEPTION 'junto.channel_desc';
  END IF;

  IF p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_base_lng NOT BETWEEN -180 AND 180 OR p_base_lat NOT BETWEEN -90 AND 90 THEN
    RAISE EXCEPTION 'junto.channel_place';
  END IF;
  v_label := NULLIF(trim(regexp_replace(COALESCE(p_base_label, ''), '<[^>]*>', '', 'g')), '');
  IF v_label IS NULL OR char_length(v_label) > 120 THEN
    RAISE EXCEPTION 'junto.channel_place';
  END IF;
  v_base := ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography;

  IF p_radius_km IS NULL OR p_radius_km NOT IN (35, 60, 100) THEN
    RAISE EXCEPTION 'junto.channel_radius';
  END IF;

  v_sport := NULLIF(trim(p_sport_key), '');
  IF v_sport IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = v_sport AND s.is_active) THEN
    RAISE EXCEPTION 'junto.channel_sport';
  END IF;

  -- Photo OPTIONAL: must be a public URL at the PROJECT storage origin, in the
  -- channel-photos bucket, under the caller's own {uid} folder. Host-anchored
  -- (no leading wildcard) so an external look-alike host cannot pass.
  v_photo := NULLIF(trim(p_photo_url), '');
  IF v_photo IS NOT NULL AND (
       char_length(v_photo) > 500
       OR private.project_url() IS NULL  -- 00524: fail-closed without a project URL
       OR v_photo NOT LIKE private.project_url() || '/storage/v1/object/public/channel-photos/' || v_user_id::text || '/%'
       OR v_photo ~* '(\.\.|%2e|%2f|%5c|\\)'  -- 00503
     ) THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_channel'));
  SELECT count(*) INTO v_open_count FROM channels
  WHERE created_by = v_user_id AND closed_at IS NULL;
  IF v_open_count >= 5 THEN RAISE EXCEPTION 'junto.channel_cap'; END IF;
  SELECT count(*) INTO v_daily FROM channels
  WHERE created_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.channel_rate_limit'; END IF;

  IF NOT p_force THEN
    SELECT c.conversation_id INTO v_existing
    FROM channels c
    WHERE c.closed_at IS NULL
      AND ST_DWithin(c.base, v_base, c.radius_km * 1000.0)
    ORDER BY ST_Distance(c.base, v_base) ASC
    LIMIT 1;
    IF v_existing IS NOT NULL THEN
      RETURN QUERY SELECT v_existing, true;
      RETURN;
    END IF;
  END IF;

  INSERT INTO conversations (type, status, name, created_by, created_at, last_message_at)
  VALUES ('channel', 'active', v_clean_name, v_user_id, now(), now())
  RETURNING id INTO v_conv_id;

  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, photo_url, created_by, created_at)
  VALUES (v_conv_id, v_sport, v_base, v_label, p_radius_km, v_clean_desc, v_photo, v_user_id, now());

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());

  RETURN QUERY SELECT v_conv_id, false;
END;
$$;


--
-- Name: create_contact_qr_token(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_contact_qr_token() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_token TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND (suspended_at IS NOT NULL OR is_demo)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_qr_token'));
  -- Keep revoked/expired rows for an hour so they still count in the quota.
  DELETE FROM contact_qr_tokens WHERE user_id = v_user_id AND created_at < now() - INTERVAL '1 hour';
  SELECT count(*) INTO v_count FROM contact_qr_tokens
  WHERE user_id = v_user_id AND created_at > now() - INTERVAL '1 hour';
  IF v_count >= 120 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;

  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  INSERT INTO contact_qr_tokens (token, user_id, expires_at)
  VALUES (v_token, v_user_id, now() + INTERVAL '2 minutes');
  RETURN v_token;
END;
$$;


--
-- Name: create_dm_member_rows(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_dm_member_rows() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.type = 'dm' THEN
    INSERT INTO conversation_members (conversation_id, user_id, joined_at)
    VALUES (NEW.id, NEW.user_1, now()), (NEW.id, NEW.user_2, now())
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: gpx_traces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gpx_traces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    geojson jsonb NOT NULL,
    distance_km numeric(7,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    elevation_gain_m integer,
    CONSTRAINT gpx_traces_distance_km_check CHECK ((distance_km >= (0)::numeric)),
    CONSTRAINT gpx_traces_elevation_gain_m_check CHECK (((elevation_gain_m IS NULL) OR (elevation_gain_m >= 0))),
    CONSTRAINT gpx_traces_name_check CHECK (((char_length(TRIM(BOTH FROM name)) >= 1) AND (char_length(TRIM(BOTH FROM name)) <= 80)))
);

ALTER TABLE ONLY public.gpx_traces FORCE ROW LEVEL SECURITY;


--
-- Name: create_gpx_trace(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_gpx_trace(p_name text, p_geojson jsonb) RETURNS public.gpx_traces
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
  v_geom geometry;
  v_distance_km NUMERIC(7,2);
  v_elevation_gain_m INTEGER;
  v_count INTEGER;
  v_row gpx_traces;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_name := trim(p_name);
  IF char_length(v_name) < 1 OR char_length(v_name) > 80 THEN
    RAISE EXCEPTION 'junto.trace_name_invalid';
  END IF;

  -- 00474 (counter-audit F8): same shape/size gate as the activity paths.
  IF p_geojson IS NULL OR NOT trace_geojson_ok(p_geojson) THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  BEGIN
    v_geom := ST_GeomFromGeoJSON(p_geojson::text);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END;
  IF ST_GeometryType(v_geom) <> 'ST_LineString'
     OR ST_NPoints(v_geom) < 2
     OR ST_NPoints(v_geom) > 10000 THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_gpx_trace'));
  SELECT count(*) INTO v_count FROM gpx_traces WHERE user_id = v_user_id;
  IF v_count >= 50 THEN
    RAISE EXCEPTION 'junto.trace_quota_reached';
  END IF;

  v_distance_km := round((ST_Length(v_geom::geography) / 1000)::numeric, 2);
  v_elevation_gain_m := trace_elevation_gain_m(p_geojson);

  INSERT INTO gpx_traces (user_id, name, geojson, distance_km, elevation_gain_m, created_at, updated_at)
  VALUES (v_user_id, v_name, p_geojson, v_distance_km, v_elevation_gain_m, now(), now())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


--
-- Name: create_group(text, text, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_group(p_name text, p_icon text, p_member_ids uuid[]) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_n INTEGER;
  v_daily INTEGER;
  v_target UUID;
  v_retained UUID[] := '{}';
  v_conv_id UUID;
  v_caller_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := regexp_replace(trim(COALESCE(p_name, '')), '<[^>]*>', '', 'g');
  IF char_length(v_clean_name) < 1 OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;
  IF p_icon IS NOT NULL AND (char_length(p_icon) < 1 OR char_length(p_icon) > 8 OR p_icon ~ '[[:cntrl:]]') THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;

  v_n := array_length(p_member_ids, 1);
  IF p_member_ids IS NULL OR v_n IS NULL OR v_n < 2 THEN
    RAISE EXCEPTION 'junto.group_min_members';  -- min 3 total (creator + 2)
  END IF;
  IF v_n > 19 THEN RAISE EXCEPTION 'junto.group_cap'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_group'));
  SELECT count(*) INTO v_daily FROM conversations
  WHERE type = 'group' AND created_by = v_user_id
    AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.group_rate_limit'; END IF;

  FOR v_target IN SELECT DISTINCT unnest(p_member_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL);
    CONTINUE WHEN NOT private.is_messaging_eligible(v_user_id, v_target);
    -- 00514 (AB-12): someone who left a group of this creator in the last 30
    -- days is not put into a fresh copy of it.
    -- 00519: …from any group the creator belongs to, not only their own.
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM conversation_departures d
      JOIN conversation_members cm ON cm.conversation_id = d.conversation_id AND cm.user_id = v_user_id
      WHERE d.user_id = v_target AND d.at > now() - INTERVAL '30 days');
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users bu
      JOIN unnest(v_retained) AS r(id) ON TRUE
      WHERE (bu.blocker_id = v_target AND bu.blocked_id = r.id)
         OR (bu.blocker_id = r.id AND bu.blocked_id = v_target)
    );
    v_retained := array_append(v_retained, v_target);
  END LOOP;

  -- ≥2 retained → group of ≥3 with the creator. A 1-retained result would be a
  -- DM-equivalent 2-person group; refuse (count only — no cause leaked).
  IF array_length(v_retained, 1) IS NULL OR array_length(v_retained, 1) < 2 THEN
    RAISE EXCEPTION 'junto.group_min_members';
  END IF;

  INSERT INTO conversations (type, status, name, icon, created_by, created_at, last_message_at)
  VALUES ('group', 'active', v_clean_name, p_icon, v_user_id, now(), now())
  RETURNING id INTO v_conv_id;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  SELECT v_conv_id, r.id, v_user_id, now() FROM unnest(v_retained) AS r(id);

  SELECT display_name INTO v_caller_name FROM public_profiles WHERE id = v_user_id;
  FOR v_target IN SELECT unnest(v_retained) LOOP
    PERFORM create_notification(
      v_target, 'group_added',
      coalesce(v_caller_name, 'Quelqu''un') || ' t''ajoute au groupe',
      v_clean_name, jsonb_build_object('conversation_id', v_conv_id,
        'params', jsonb_build_object('name', coalesce(v_caller_name, 'Quelqu''un'), 'group', v_clean_name))
    );
  END LOOP;

  RETURN v_conv_id;
END;
$$;


--
-- Name: create_manual_booking(uuid, date, text, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_manual_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_name text, p_phone text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_off RECORD;
  v_name TEXT;
  v_phone TEXT;
  v_booking_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  SELECT po.id, po.max_participants INTO v_off
  FROM pro_offerings po WHERE po.id = p_offering_id AND po.pro_id = v_user_id;
  IF v_off IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Le pro peut saisir sur n'importe quel jour futur (même non marqué dispo) :
  -- c'est SON agenda, source de vérité y compris pour l'hors-app.
  IF p_day IS NULL OR p_day < private.today_paris() OR p_day > private.today_paris() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;
  IF p_party_size IS NULL OR p_party_size < 1
     OR p_party_size > LEAST(coalesce(v_off.max_participants, 50), 50) THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;

  v_name := nullif(regexp_replace(trim(coalesce(p_name, '')), '<[^>]*>', '', 'g'), '');
  IF v_name IS NULL OR char_length(v_name) > 80 THEN
    RAISE EXCEPTION 'junto.booking_manual_name';
  END IF;
  v_phone := nullif(regexp_replace(trim(coalesce(p_phone, '')), '<[^>]*>', '', 'g'), '');
  IF v_phone IS NOT NULL AND char_length(v_phone) NOT BETWEEN 3 AND 30 THEN
    RAISE EXCEPTION 'junto.booking_manual_name';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_manual_booking'));
  IF (SELECT count(*) FROM bookings
      WHERE pro_id = v_user_id AND client_id IS NULL
        AND created_at > now() - INTERVAL '24 hours') >= 30 THEN
    RAISE EXCEPTION 'junto.booking_daily_cap';
  END IF;

  INSERT INTO bookings (offering_id, pro_id, client_id, manual_name, manual_phone,
                        day, period, party_size, status)
  VALUES (p_offering_id, v_user_id, NULL, v_name, v_phone, p_day, p_period, p_party_size, 'accepted')
  RETURNING id INTO v_booking_id;

  RETURN v_booking_id;
END;
$$;


--
-- Name: create_notification(uuid, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_notification(p_user_id uuid, p_type text, p_title text, p_body text, p_data jsonb DEFAULT NULL::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_notification_id UUID;
  v_prefs JSONB;
  v_pref_value TEXT;
  v_suspended TIMESTAMPTZ;
BEGIN
  SELECT suspended_at, notification_preferences
  INTO v_suspended, v_prefs
  FROM users WHERE id = p_user_id;

  IF v_suspended IS NOT NULL THEN
    RETURN NULL;
  END IF;

  IF v_prefs IS NOT NULL AND v_prefs ? p_type THEN
    v_pref_value := v_prefs ->> p_type;
    IF v_pref_value IS NOT NULL AND v_pref_value NOT IN ('true', '1') THEN
      RETURN NULL;
    END IF;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    p_user_id, p_type,
    sanitize_notif_text(p_title),
    sanitize_notif_text(p_body),
    p_data, now()
  )
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;


--
-- Name: create_offering_review(uuid, smallint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_offering_review(p_offering_id uuid, p_rating smallint, p_body text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_pro_id UUID;
  v_body TEXT;
  v_daily_count INTEGER;
  v_review_id UUID;
  v_reviewer_name TEXT;
  v_offering_title TEXT;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT o.pro_id, o.title, o.is_demo INTO v_pro_id, v_offering_title, v_is_demo FROM pro_offerings o
  WHERE o.id = p_offering_id
    -- 00505 (B8): an approved pro's offering only.
    AND EXISTS (SELECT 1 FROM pro_profiles pp WHERE pp.user_id = o.pro_id AND pp.status = 'approved');
  -- 00443 B5 : offre démo refusée (même erreur générique qu'inexistante).
  IF v_pro_id IS NULL OR v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_pro_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reviews'));

  IF EXISTS (
    SELECT 1 FROM offering_reviews WHERE offering_id = p_offering_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'junto.review_duplicate';
  END IF;

  SELECT (
    (SELECT count(*) FROM pro_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
    +
    (SELECT count(*) FROM offering_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
  ) INTO v_daily_count;

  IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.review_rate_limit'; END IF;

  BEGIN
    INSERT INTO offering_reviews (offering_id, reviewer_id, rating, body, created_at, updated_at)
    VALUES (p_offering_id, v_user_id, p_rating, v_body, now(), now())
    RETURNING id INTO v_review_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Operation not permitted';
  END;

  SELECT display_name INTO v_reviewer_name FROM users WHERE id = v_user_id;
  PERFORM notify_review_received(
    v_pro_id,
    v_reviewer_name,
    p_rating,
    v_offering_title,
    jsonb_build_object('offering_id', p_offering_id, 'review_id', v_review_id, 'reviewer_id', v_user_id)
  );

  RETURN v_review_id;
END;
$$;


--
-- Name: create_presence_token(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_presence_token(p_activity_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_creator_id UUID;
  v_token TEXT;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_requires_presence BOOLEAN;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT creator_id, starts_at, duration, status, deleted_at, requires_presence, is_demo
  INTO v_creator_id, v_starts_at, v_duration, v_status, v_deleted_at, v_requires_presence, v_is_demo
  FROM activities WHERE id = p_activity_id;
  IF v_creator_id IS NULL OR v_creator_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00429 : ne pas frapper un token sur une sortie supprimée / annulée /
  -- expirée, ni sans validation de présence, ni sur une sortie démo.
  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  IF v_requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  IF v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '15 minutes' OR now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
    RAISE EXCEPTION 'junto.presence_token_window_closed';
  END IF;

  SELECT token INTO v_token FROM presence_tokens
  -- 00436 : on ne réutilise un token que s'il lui reste plus de 5 MINUTES.
  -- Avant, la condition était « expires_at > now() » : un client qui demandait
  -- un renouvellement récupérait donc le token mourant au lieu d'un neuf, et
  -- comme il n'a aucun moyen de connaître la vraie échéance, il affichait
  -- « valide 30 min de plus » sur un code qui allait mourir — un QR mort à
  -- l'écran, pendant que l'app affirmait le contraire. Cette borne garantit
  -- qu'une demande proche de l'expiration rend un token réellement frais.
  WHERE activity_id = p_activity_id AND expires_at > now() + INTERVAL '5 minutes'
  LIMIT 1;

  IF v_token IS NULL THEN
    v_token := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
    INSERT INTO presence_tokens (token, activity_id, expires_at)
    VALUES (v_token, p_activity_id, now() + INTERVAL '30 minutes');
  END IF;

  RETURN v_token;
END;
$$;


--
-- Name: create_pro_offering(uuid, text, text, text, double precision, double precision, text, text, integer, text, numeric, integer, numeric, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_pro_offering(p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text DEFAULT NULL::text, p_max_participants integer DEFAULT NULL::integer, p_schedule_text text DEFAULT NULL::text, p_distance_km numeric DEFAULT NULL::numeric, p_elevation_gain_m integer DEFAULT NULL::integer, p_price_eur numeric DEFAULT NULL::numeric, p_price_unit text DEFAULT NULL::text, p_min_participants integer DEFAULT NULL::integer) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_count INTEGER;
  v_offering_id UUID;
  v_clean_title TEXT;
  v_clean_location_name TEXT;
  v_clean_schedule TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00519: duration between 15 min and 30 days, readable error.
  IF p_duration IS NOT NULL AND NOT private.offering_duration_ok(p_duration) THEN RAISE EXCEPTION 'junto.offering_duration'; END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_title := trim(p_title);
  IF char_length(v_clean_title) < 3 OR char_length(v_clean_title) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_description IS NULL OR char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_level IS NULL OR char_length(trim(p_level)) < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_location_name := trim(p_location_name);
  IF char_length(v_clean_location_name) < 1 OR char_length(v_clean_location_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_location_lng IS NULL OR p_location_lat IS NULL
     OR p_location_lng < -180 OR p_location_lng > 180
     OR p_location_lat < -90 OR p_location_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 1 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_min_participants IS NOT NULL AND (p_min_participants < 1 OR p_min_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_min_participants IS NOT NULL AND p_max_participants IS NOT NULL
     AND p_min_participants > p_max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_schedule_text IS NOT NULL THEN
    v_clean_schedule := trim(p_schedule_text);
    IF char_length(v_clean_schedule) > 100 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF char_length(v_clean_schedule) = 0 THEN
      v_clean_schedule := NULL;
    END IF;
  END IF;

  IF p_distance_km IS NOT NULL AND (p_distance_km <= 0 OR p_distance_km > 9999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_elevation_gain_m IS NOT NULL AND (p_elevation_gain_m <= 0 OR p_elevation_gain_m > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_eur IS NOT NULL AND (p_price_eur <= 0 OR p_price_eur > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_unit IS NOT NULL AND p_price_unit NOT IN ('person', 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF (p_price_eur IS NULL) <> (p_price_unit IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('create_offering:' || v_user_id::text));

  SELECT count(*) INTO v_count
  FROM pro_offerings
  WHERE pro_id = v_user_id;

  -- 12: covers the typical catalogue, forces curation, and keeps the
  -- permanent-pin density on the map under control (RA pins accumulate,
  -- UA pins expire). Raise later if real pros ask — never lower.
  IF v_count >= 12 THEN RAISE EXCEPTION 'junto.offering_cap'; END IF;

  INSERT INTO pro_offerings (
    pro_id, sport_id, title, description, level,
    location, location_name,
    duration, max_participants, schedule_text,
    distance_km, elevation_gain_m,
    price_eur, price_unit, min_participants,
    created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_clean_title, p_description, p_level,
    ST_SetSRID(ST_MakePoint(p_location_lng, p_location_lat), 4326)::geography,
    v_clean_location_name,
    CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE NULL END,
    p_max_participants,
    v_clean_schedule,
    p_distance_km,
    p_elevation_gain_m,
    p_price_eur,
    p_price_unit,
    p_min_participants,
    now(), now()
  ) RETURNING id INTO v_offering_id;

  RETURN v_offering_id;
END;
$$;


--
-- Name: create_pro_review(uuid, smallint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_pro_review(p_pro_id uuid, p_rating smallint, p_body text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_body TEXT;
  v_daily_count INTEGER;
  v_review_id UUID;
  v_reviewer_name TEXT;
  v_pro_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_pro_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00443 B5 : cible démo refusée (même erreur générique qu'inexistante).
  -- 00505 (B8): only an approved pro can be reviewed (same generic error).
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND is_demo = false AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = p_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reviews'));

  IF EXISTS (
    SELECT 1 FROM pro_reviews WHERE pro_id = p_pro_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'junto.review_duplicate';
  END IF;

  SELECT (
    (SELECT count(*) FROM pro_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
    +
    (SELECT count(*) FROM offering_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
  ) INTO v_daily_count;

  IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.review_rate_limit'; END IF;

  BEGIN
    INSERT INTO pro_reviews (pro_id, reviewer_id, rating, body, created_at, updated_at)
    VALUES (p_pro_id, v_user_id, p_rating, v_body, now(), now())
    RETURNING id INTO v_review_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Operation not permitted';
  END;

  SELECT display_name INTO v_reviewer_name FROM users WHERE id = v_user_id;
  SELECT display_name INTO v_pro_name FROM pro_profiles WHERE user_id = p_pro_id;
  PERFORM notify_review_received(
    p_pro_id,
    v_reviewer_name,
    p_rating,
    v_pro_name,
    jsonb_build_object('pro_id', p_pro_id, 'review_id', v_review_id, 'reviewer_id', v_user_id)
  );

  RETURN v_review_id;
END;
$$;


--
-- Name: create_report(text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_report(p_target_type text, p_target_id uuid, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_report_id UUID;
  v_hourly_count INTEGER;
  v_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type NOT IN ('user', 'activity',
                           'pro_review', 'offering_review', 'message', 'group', 'channel') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := regexp_replace(trim(p_reason), '<[^>]*>', '', 'g');
  IF char_length(v_reason) < 10 THEN RAISE EXCEPTION 'junto.report_reason_too_short'; END IF;

  IF p_target_type = 'user' AND p_target_id = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Existence checks. 'message' / 'group' hit the unified store; the reporter
  -- must be a member of the conversation the content lives in (no probing).
  IF p_target_type = 'user' AND NOT EXISTS (SELECT 1 FROM users WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'activity' AND NOT EXISTS (SELECT 1 FROM activities WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'message' AND NOT EXISTS (
    -- 00499 (MS-8): a message deleted by its author stays reportable by a
    -- member (deleting abuse right after sending it must not dodge a report).
    SELECT 1 FROM messages m
    WHERE m.id = p_target_id
      AND private.is_conversation_member(m.conversation_id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'group' AND NOT EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id = p_target_id AND c.type = 'group'
      AND private.is_conversation_member(c.id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'channel' AND NOT EXISTS (
    SELECT 1 FROM conversations c WHERE c.id = p_target_id AND c.type = 'channel'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'pro_review' AND NOT EXISTS (SELECT 1 FROM pro_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'offering_review' AND NOT EXISTS (SELECT 1 FROM offering_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00520: serialised per reporter (and a unique index backs it).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_report'));
  IF EXISTS (
    SELECT 1 FROM reports
    WHERE reporter_id = v_user_id AND target_type = p_target_type AND target_id = p_target_id
  ) THEN RAISE EXCEPTION 'junto.report_already_filed'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reports'));
  SELECT count(*) INTO v_hourly_count FROM reports
  WHERE reporter_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.report_rate_limit'; END IF;

  INSERT INTO reports (reporter_id, target_type, target_id, reason, status, created_at)
  VALUES (v_user_id, p_target_type, p_target_id, v_reason, 'pending', now())
  RETURNING id INTO v_report_id;
  RETURN v_report_id;
END;
$$;


--
-- Name: deactivate_dispo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deactivate_dispo() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE discovery_availabilities SET is_active = false WHERE user_id = v_user_id;
END;
$$;


--
-- Name: decline_activity_invitation(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decline_activity_invitation(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- No refused_at (no cooldown inflicted), no notification (silent), row
  -- deleted so a later re-invite is a clean INSERT. Not invited → no-op.
  PERFORM set_config('junto.bypass_lock', 'true', true);
  DELETE FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'invited';
  -- 00499 (MS-3): remembered, so the invitation is not sent again.
  IF FOUND THEN
    INSERT INTO invitation_declines (activity_id, user_id, at) VALUES (p_activity_id, v_user_id, now())
    ON CONFLICT (activity_id, user_id) DO UPDATE SET at = now();
  END IF;
END;
$$;


--
-- Name: decline_booking(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decline_booking(p_booking_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_pro_name TEXT;
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_updated INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.status != 'pending' OR v_bk.pro_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'declined' WHERE id = p_booking_id AND status = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_bk.client_id IS NOT NULL THEN
    SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
    SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;
    PERFORM create_notification(
      v_bk.client_id,
      'booking_declined',
      'Créneau indisponible',
      coalesce(v_pro_name, 'Le professionnel') || ' n''est pas disponible pour « '
        || coalesce(v_off_title, 'cette sortie') || ' » le ' || to_char(v_bk.day, 'DD/MM')
        || '. Essaie un autre créneau.',
      jsonb_build_object('booking_id', v_bk.id, 'offering_id', v_bk.offering_id,
        'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'), 'title', coalesce(v_off_title, 'cette sortie'),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD')))
    );
  END IF;
END;
$$;


--
-- Name: decline_contact_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decline_contact_request(p_conversation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id FOR UPDATE;
  IF v_conv.id IS NULL OR v_conv.type != 'dm' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id = v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_conv.status = 'pending_request' THEN
    UPDATE conversations SET status = 'declined' WHERE id = p_conversation_id;
  ELSIF v_conv.status = 'declined' THEN
    NULL; -- double-tap safe, indistinguishable
  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;


--
-- Name: decline_seat_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decline_seat_request(p_request_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_name TEXT;
  v_activity_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_req.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE seat_requests SET status = 'declined' WHERE id = p_request_id;

  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_declined',
    'Pas de place',
    coalesce(v_driver_name, 'Le conducteur') || ' a refusé ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'seat_request_id', v_req.id,
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'params', jsonb_build_object('name', coalesce(v_driver_name, 'Le conducteur'), 'title', v_activity_title)
    )
  );
END;
$$;


--
-- Name: delete_account_as(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_account_as(p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- Called only by the delete-account edge function (service role), after it
  -- verified the caller's JWT. Runs the deletion as that user.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
  PERFORM delete_own_account();
END;
$$;


--
-- Name: delete_gpx_trace(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_gpx_trace(p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM gpx_traces WHERE id = p_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM gpx_traces WHERE id = p_id AND user_id = v_user_id;
END;
$$;


--
-- Name: delete_message(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_message(p_message_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_conv UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE messages SET deleted_at = now()
  WHERE id = p_message_id AND sender_id = v_user_id AND deleted_at IS NULL;
  IF FOUND THEN RETURN; END IF;

  SELECT conversation_id INTO v_conv FROM messages WHERE id = p_message_id AND deleted_at IS NULL;
  IF v_conv IS NOT NULL AND EXISTS (
    SELECT 1 FROM channels ch WHERE ch.conversation_id = v_conv AND ch.created_by = v_user_id
  ) THEN
    UPDATE messages SET deleted_at = now() WHERE id = p_message_id AND deleted_at IS NULL;
    RETURN;
  END IF;

  RAISE EXCEPTION 'Operation not permitted';
END;
$$;


--
-- Name: delete_offering_review(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_offering_review(p_review_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM offering_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM offering_reviews WHERE id = p_review_id;
END;
$$;


--
-- Name: delete_own_account(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_own_account() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
  v_channel RECORD;
  v_new_owner UUID;
  v_booking RECORD;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 2. Cancel all active activities created by user + notify participants
  FOR v_activity IN
    SELECT id, title FROM activities
    WHERE creator_id = v_user_id AND status IN ('published', 'in_progress')
  LOOP
    UPDATE activities SET status = 'cancelled', updated_at = now() WHERE id = v_activity.id;

    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = v_activity.id AND status = 'accepted' AND user_id != v_user_id
    LOOP
      PERFORM create_notification(
        v_participant.user_id,
        'activity_cancelled',
        'Sortie annulée',
        '« ' || v_activity.title || ' » — l''organisateur a quitté Junto',
        jsonb_build_object('activity_id', v_activity.id, 'variant', 'creator_gone',
          'params', jsonb_build_object('title', v_activity.title))
      );
    END LOOP;
  END LOOP;

  -- 2b. Channels created by the user: hand the hub to the earliest remaining
  -- member so it keeps a moderator; if none remain, close it. Before the user
  -- delete so the created_by FK no longer references these rows.
  FOR v_channel IN
    SELECT conversation_id FROM channels WHERE created_by = v_user_id
  LOOP
    SELECT user_id INTO v_new_owner
    FROM conversation_members
    WHERE conversation_id = v_channel.conversation_id AND user_id != v_user_id
    ORDER BY joined_at ASC
    LIMIT 1;

    IF v_new_owner IS NOT NULL THEN
      UPDATE channels SET created_by = v_new_owner WHERE conversation_id = v_channel.conversation_id;
      UPDATE conversations SET created_by = v_new_owner WHERE id = v_channel.conversation_id;
    ELSE
      UPDATE channels SET closed_at = now()
      WHERE conversation_id = v_channel.conversation_id AND closed_at IS NULL;
    END IF;
  END LOOP;

  -- 2c. Réservations futures (00419 M1) : le CASCADE va les effacer sans un
  -- mot — prévenir la contrepartie AVANT. Miroir du bloc activités : pro
  -- supprimé → tout client (pending ou accepté) est prévenu ; client supprimé
  -- → le pro n'est prévenu que pour du confirmé (un pending qui disparaît
  -- reste silencieux, pattern cancel_booking).
  FOR v_booking IN
    SELECT b.id, b.day, b.pro_id, b.client_id, b.status, po.title
    FROM bookings b
    LEFT JOIN pro_offerings po ON po.id = b.offering_id
    WHERE (b.pro_id = v_user_id OR b.client_id = v_user_id)
      AND b.status IN ('pending', 'accepted')
      AND b.day >= private.today_paris()
  LOOP
    IF v_booking.pro_id = v_user_id THEN
      IF v_booking.client_id IS NOT NULL THEN
        PERFORM create_notification(
          v_booking.client_id,
          'booking_cancelled',
          'Sortie annulée',
          '« ' || coalesce(v_booking.title, 'Ta sortie') || ' » du '
            || to_char(v_booking.day, 'DD/MM') || ' est annulée — le professionnel n''est plus sur Junto.',
          jsonb_build_object('booking_id', v_booking.id, 'by', 'pro', 'variant', 'pro_gone',
            'params', jsonb_build_object('title', coalesce(v_booking.title, 'Ta sortie'), 'date', to_char(v_booking.day, 'YYYY-MM-DD')))
        );
      END IF;
    ELSIF v_booking.status = 'accepted' THEN
      PERFORM create_notification(
        v_booking.pro_id,
        'booking_cancelled',
        'Réservation annulée',
        'La réservation de « ' || coalesce(v_booking.title, 'une sortie') || ' » du '
          || to_char(v_booking.day, 'DD/MM') || ' a été annulée (compte supprimé).',
        jsonb_build_object('booking_id', v_booking.id, 'by', 'client', 'variant', 'client_gone',
          'params', jsonb_build_object('title', coalesce(v_booking.title, 'une sortie'), 'date', to_char(v_booking.day, 'YYYY-MM-DD')))
      );
    END IF;
  END LOOP;

  -- 3. Wall messages: anonymize (SET NULL handled by FK ON DELETE SET NULL)
  -- 4. Private messages: deleted by FK ON DELETE CASCADE
  -- 5. Conversations: deleted by FK ON DELETE CASCADE
  -- 6. Participations: deleted by FK ON DELETE CASCADE
  -- 7. Notifications: deleted by FK ON DELETE CASCADE
  -- 8. Blocked users: deleted by FK ON DELETE CASCADE
  -- 9. Reputation votes: deleted by FK ON DELETE CASCADE
  -- 10. Reports: reporter anonymisé (reporter_id → SET NULL depuis 00418 ;
  --     l'historique de modération survit sans identité)

  -- 11. Delete the user row — FKs handle cascading
  DELETE FROM users WHERE id = v_user_id;
END;
$$;


--
-- Name: delete_pro_offering(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_pro_offering(p_offering_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00518 (L4): lock the offering first — no booking can slip in between the
  -- check below and the delete.
  PERFORM 1 FROM pro_offerings WHERE id = p_offering_id FOR UPDATE;

  -- 00416 : refuser tant que des réservations futures vivantes existent.
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE offering_id = p_offering_id
      AND status IN ('pending', 'accepted')
      AND day >= private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  DELETE FROM pro_offerings WHERE id = p_offering_id;
END;
$$;


--
-- Name: delete_pro_review(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_pro_review(p_review_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_reviews WHERE id = p_review_id;
END;
$$;


--
-- Name: demo_content_visible(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.demo_content_visible() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT
    coalesce((SELECT value = 'true' FROM app_config WHERE name = 'demo_mode'), false)
    AND EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid() AND is_admin = true AND suspended_at IS NULL
    );
$$;


--
-- Name: discovery_availabilities_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.discovery_availabilities_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.user_id := OLD.user_id;
  NEW.is_active := OLD.is_active;
  NEW.is_demo := OLD.is_demo;
  NEW.created_at := OLD.created_at;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: edit_message(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.edit_message(p_message_id uuid, p_content text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_conv_id UUID;
  v_type TEXT;
  v_activity_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT c.id, c.type, c.activity_id INTO v_conv_id, v_type, v_activity_id
  FROM messages m JOIN conversations c ON c.id = m.conversation_id
  WHERE m.id = p_message_id AND m.sender_id = v_user_id
    AND m.deleted_at IS NULL AND m.metadata IS NULL; -- rich cards not editable
  IF v_conv_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: a group taken down by moderation is read-only.
  -- 00520: restores 00514 (lost by 00519) — no rewriting in a closed discussion,
  -- and the same thread rules as sending (DM status, blocks, bans).
  IF v_type = 'channel' AND EXISTS (SELECT 1 FROM channels WHERE conversation_id = v_conv_id AND closed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM private.assert_can_send(v_conv_id, v_user_id);
  IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conv_id AND moderated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Must still be a member; for activity messages the activity must be alive
  -- (wall edit parity 00177).
  IF NOT private.is_conversation_member(v_conv_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_type = 'activity' AND NOT EXISTS (
    SELECT 1 FROM activities a WHERE a.id = v_activity_id
      AND a.deleted_at IS NULL AND a.status IN ('published', 'in_progress')
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00474 (counter-audit F5): keep the first version for moderation (internal
  -- table, no client grant) — an edit can no longer launder a thread.
  INSERT INTO message_original_content (message_id, content)
  SELECT id, content FROM messages WHERE id = p_message_id
  ON CONFLICT (message_id) DO NOTHING;

  UPDATE messages SET content = trim(p_content), edited_at = now()
  WHERE id = p_message_id;
END;
$$;


--
-- Name: ensure_user_row(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_user_row() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_email TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM public.users WHERE id = v_user_id) THEN
    RETURN;
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = v_user_id;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00513: an account deleted while suspended cannot come back through its
  -- surviving login (the profile row is recreated here, not in
  -- handle_new_user — the ID-2 bypass found by the re-secure audit).
  IF private.email_is_banned(v_email) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO public.users (id, email, display_name, tier, created_at, updated_at)
  VALUES (v_user_id, v_email, generate_random_name(), 'premium', now(), now())
  ON CONFLICT (id) DO NOTHING;
END;
$$;


--
-- Name: expire_idle_seat_requests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.expire_idle_seat_requests() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_request RECORD;
  v_activity_title TEXT;
BEGIN
  FOR v_request IN
    SELECT sr.id, sr.requester_id, sr.activity_id
    FROM seat_requests sr
    JOIN activities a ON a.id = sr.activity_id
    WHERE sr.status = 'pending'
      AND sr.created_at < NOW() - INTERVAL '48 hours'
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
    FOR UPDATE OF sr
  LOOP
    UPDATE seat_requests SET status = 'expired'
    WHERE id = v_request.id AND status = 'pending';

    SELECT title INTO v_activity_title FROM activities WHERE id = v_request.activity_id;

    PERFORM create_notification(
      v_request.requester_id,
      'seat_request_expired',
      'Demande sans réponse',
      'Ta demande de covoiturage pour « ' || coalesce(v_activity_title, '?') || ' » a expiré sans réponse du conducteur.',
      jsonb_build_object('activity_id', v_request.activity_id, 'seat_request_id', v_request.id,
        'params', jsonb_build_object('title', coalesce(v_activity_title, '?')))
    );
  END LOOP;
END;
$$;


--
-- Name: expire_invited_on_activity_end(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.expire_invited_on_activity_end() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.status IN ('completed', 'cancelled', 'expired')
     AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE participations
    SET status = 'expired'
    WHERE activity_id = NEW.id AND status = 'invited';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: expire_stale_contact_requests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.expire_stale_contact_requests() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  DELETE FROM conversations
  WHERE type = 'dm'
    AND status IN ('pending_request', 'declined')
    AND created_at < NOW() - INTERVAL '30 days';
END;
$$;


--
-- Name: generate_random_name(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_random_name() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  adjectives TEXT[] := ARRAY[
    'Brave', 'Swift', 'Bold', 'Calm', 'Keen',
    'Wild', 'Free', 'Sharp', 'Cool', 'Warm',
    'Bright', 'Quick', 'Steady', 'Light', 'Strong'
  ];
  animals TEXT[] := ARRAY[
    'Falcon', 'Wolf', 'Eagle', 'Bear', 'Fox',
    'Hawk', 'Lynx', 'Otter', 'Deer', 'Heron',
    'Marmot', 'Ibex', 'Chamois', 'Viper', 'Trout'
  ];
  adj TEXT;
  animal TEXT;
  digits TEXT;
BEGIN
  adj := adjectives[1 + floor(random() * array_length(adjectives, 1))::int];
  animal := animals[1 + floor(random() * array_length(animals, 1))::int];
  digits := lpad(floor(random() * 10000)::text, 4, '0');
  RETURN adj || animal || digits;
END;
$$;


--
-- Name: get_active_negative_count(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_active_negative_count(p_voted_id uuid, p_badge_key text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_active INTEGER := 0;
  v_last_at TIMESTAMPTZ;
  v_vote RECORD;
  v_months_elapsed INTEGER;
BEGIN
  FOR v_vote IN
    -- 00496 (PR-11): one vote per person (their latest) — one hostile
    -- co-participant over five outings is not five people.
    SELECT x.created_at FROM (
      SELECT DISTINCT ON (voter_id) created_at FROM reputation_votes
      WHERE voted_id = p_voted_id AND badge_key = p_badge_key
        AND counted_at IS NOT NULL
      ORDER BY voter_id, created_at DESC
    ) x
    ORDER BY x.created_at ASC
  LOOP
    IF v_last_at IS NOT NULL THEN
      v_months_elapsed := FLOOR(
        EXTRACT(EPOCH FROM (v_vote.created_at - v_last_at)) / (30.0 * 24 * 3600)
      )::INTEGER;
      v_active := GREATEST(0, v_active - v_months_elapsed);
    END IF;
    v_active := v_active + 1;
    v_last_at := v_vote.created_at;
  END LOOP;

  IF v_last_at IS NOT NULL THEN
    v_months_elapsed := FLOOR(
      EXTRACT(EPOCH FROM (NOW() - v_last_at)) / (30.0 * 24 * 3600)
    )::INTEGER;
    v_active := GREATEST(0, v_active - v_months_elapsed);
  END IF;

  RETURN v_active;
END;
$$;


--
-- Name: get_activity_by_invite_token(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_activity_by_invite_token(p_token uuid) RETURNS TABLE(id uuid, creator_id uuid, sport_id uuid, title text, description text, level text, level_max text, max_participants integer, starts_at timestamp with time zone, duration interval, visibility text, status text, lng double precision, lat double precision, creator_name text, creator_avatar text, sport_key text, sport_icon text, sport_category text, participant_count integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00486 (IX-1): remember that this account opened the link; join_activity
  -- requires it for a private outing (the app calls this before joining).
  INSERT INTO invite_grants (user_id, activity_id, at)
  SELECT v_user_id, a.id, now() FROM activities a
  WHERE a.invite_token = p_token AND a.status IN ('published', 'in_progress') AND a.deleted_at IS NULL
    -- 00520: never for someone the organiser removed or blocked, nor for a
    -- suspended organiser's outing (same rules as private_activity_access).
    AND NOT private.user_is_suspended(a.creator_id)
    AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = a.creator_id AND b.blocked_id = v_user_id)
    AND NOT EXISTS (SELECT 1 FROM participations rp WHERE rp.activity_id = a.id AND rp.user_id = v_user_id AND rp.status = 'removed')
    AND (a.is_demo = false OR demo_content_visible())
  ON CONFLICT (user_id, activity_id) DO UPDATE SET at = now();

  RETURN QUERY
  SELECT
    a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.level_max,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.status,
    ST_X(a.location_meeting::geometry)::FLOAT AS lng,
    ST_Y(a.location_meeting::geometry)::FLOAT AS lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    (SELECT count(*)::int FROM participations p
     WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count
  FROM activities a
  JOIN public_profiles pp ON a.creator_id = pp.id
  JOIN sports s ON a.sport_id = s.id
  WHERE a.invite_token = p_token
    AND a.status IN ('published', 'in_progress')
    AND a.deleted_at IS NULL
    -- 00520: never for someone the organiser removed or blocked, nor for a
    -- suspended organiser's outing (same rules as private_activity_access).
    AND NOT private.user_is_suspended(a.creator_id)
    AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = a.creator_id AND b.blocked_id = v_user_id)
    AND NOT EXISTS (SELECT 1 FROM participations rp WHERE rp.activity_id = a.id AND rp.user_id = v_user_id AND rp.status = 'removed')
    AND (a.is_demo = false OR demo_content_visible());
END;
$$;


--
-- Name: reliability_tier(double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reliability_tier(p_score double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  SELECT CASE
    WHEN p_score IS NULL THEN 'new'
    WHEN p_score >= 90 THEN 'excellent'
    WHEN p_score >= 75 THEN 'good'
    WHEN p_score >= 50 THEN 'fair'
    ELSE 'poor'
  END;
$$;


--
-- Name: activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    creator_id uuid NOT NULL,
    sport_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    level text NOT NULL,
    max_participants integer,
    location_meeting extensions.geography(Point,4326) NOT NULL,
    route extensions.geography(LineString,4326),
    starts_at timestamp with time zone NOT NULL,
    duration interval NOT NULL,
    visibility text DEFAULT 'public'::text NOT NULL,
    invite_token uuid DEFAULT gen_random_uuid() NOT NULL,
    status text DEFAULT 'published'::text NOT NULL,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    location_end extensions.geography(Point,4326),
    cancelled_reason text,
    requires_presence boolean DEFAULT true NOT NULL,
    location_objective extensions.geography(Point,4326),
    objective_name text,
    distance_km numeric(6,1),
    elevation_gain_m integer,
    meeting_name text,
    trace_geojson jsonb,
    level_max text,
    is_demo boolean DEFAULT false NOT NULL,
    meeting_locality text,
    CONSTRAINT activities_description_check CHECK ((char_length(description) <= 2000)),
    CONSTRAINT activities_distance_km_check CHECK (((distance_km IS NULL) OR ((distance_km > (0)::numeric) AND (distance_km <= (9999)::numeric)))),
    CONSTRAINT activities_duration_check CHECK (((duration >= '00:15:00'::interval) AND (duration <= '7 days'::interval))),
    CONSTRAINT activities_elevation_gain_m_check CHECK (((elevation_gain_m IS NULL) OR ((elevation_gain_m > 0) AND (elevation_gain_m <= 99999)))),
    CONSTRAINT activities_level_len CHECK ((char_length(level) <= 60)),
    CONSTRAINT activities_level_max_len CHECK (((level_max IS NULL) OR (char_length(level_max) <= 60))),
    CONSTRAINT activities_max_participants_check CHECK (((max_participants >= 2) AND (max_participants <= 50))),
    CONSTRAINT activities_meeting_locality_check CHECK (((meeting_locality IS NULL) OR ((char_length(meeting_locality) >= 1) AND (char_length(meeting_locality) <= 80)))),
    CONSTRAINT activities_objective_name_check CHECK (((objective_name IS NULL) OR ((char_length(objective_name) >= 1) AND (char_length(objective_name) <= 100)))),
    CONSTRAINT activities_start_name_check CHECK (((meeting_name IS NULL) OR ((char_length(meeting_name) >= 1) AND (char_length(meeting_name) <= 100)))),
    CONSTRAINT activities_status_check CHECK ((status = ANY (ARRAY['published'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text, 'expired'::text]))),
    CONSTRAINT activities_title_check CHECK (((char_length(title) >= 3) AND (char_length(title) <= 100))),
    CONSTRAINT activities_trace_geojson_check CHECK (((trace_geojson IS NULL) OR (((trace_geojson ->> 'type'::text) = 'LineString'::text) AND (jsonb_typeof((trace_geojson -> 'coordinates'::text)) = 'array'::text) AND ((jsonb_array_length((trace_geojson -> 'coordinates'::text)) >= 2) AND (jsonb_array_length((trace_geojson -> 'coordinates'::text)) <= 10000))))),
    CONSTRAINT activities_visibility_check CHECK ((visibility = ANY (ARRAY['public'::text, 'approval'::text, 'private_link'::text, 'private_link_approval'::text])))
);

ALTER TABLE ONLY public.activities FORCE ROW LEVEL SECURITY;


--
-- Name: blocked_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blocked_users (
    blocker_id uuid NOT NULL,
    blocked_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT blocked_users_check CHECK ((blocker_id <> blocked_id))
);

ALTER TABLE ONLY public.blocked_users FORCE ROW LEVEL SECURITY;


--
-- Name: participations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.participations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    activity_id uuid NOT NULL,
    user_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    left_at timestamp with time zone,
    confirmed_present boolean,
    left_reason text,
    penalty_waived boolean DEFAULT false NOT NULL,
    transport_type text,
    transport_seats smallint,
    transport_from_name text,
    transport_departs_at timestamp with time zone,
    refused_at timestamp with time zone,
    invited_by uuid,
    invite_message text,
    transport_from_lat double precision,
    transport_from_lng double precision,
    accepted_at timestamp with time zone,
    accepted_via text,
    transport_from_locality text,
    CONSTRAINT participations_accepted_via_check CHECK (((accepted_via IS NULL) OR (accepted_via = ANY (ARRAY['self'::text, 'organiser'::text, 'invitation'::text])))),
    CONSTRAINT participations_invite_msg_len_check CHECK (((invite_message IS NULL) OR (char_length(invite_message) <= 500))),
    CONSTRAINT participations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'refused'::text, 'removed'::text, 'withdrawn'::text, 'expired'::text, 'invited'::text]))),
    CONSTRAINT participations_transport_from_locality_check CHECK (((transport_from_locality IS NULL) OR (char_length(transport_from_locality) <= 80))),
    CONSTRAINT participations_transport_from_name_check CHECK (((transport_from_name IS NULL) OR ((char_length(transport_from_name) >= 1) AND (char_length(transport_from_name) <= 100)))),
    CONSTRAINT participations_transport_seats_check CHECK (((transport_seats IS NULL) OR ((transport_seats >= 0) AND (transport_seats <= 8)))),
    CONSTRAINT participations_transport_type_check CHECK (((transport_type IS NULL) OR (transport_type = ANY (ARRAY['car'::text, 'public_transport'::text, 'bike'::text, 'on_foot'::text, 'other'::text]))))
);

ALTER TABLE ONLY public.participations FORCE ROW LEVEL SECURITY;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    email text NOT NULL,
    display_name text NOT NULL,
    avatar_url text,
    bio text,
    sports jsonb DEFAULT '[]'::jsonb,
    levels_per_sport jsonb DEFAULT '{}'::jsonb,
    tier text DEFAULT 'free'::text NOT NULL,
    is_admin boolean DEFAULT false NOT NULL,
    suspended_at timestamp with time zone,
    accepted_tos_at timestamp with time zone,
    accepted_privacy_at timestamp with time zone,
    push_token text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    notification_preferences jsonb DEFAULT '{"alert_match": true, "driver_left": true, "join_request": true, "review_reply": true, "seat_request": true, "badge_unlocked": true, "booking_expired": true, "booking_request": true, "contact_request": true, "request_refused": true, "review_received": true, "activity_updated": true, "booking_accepted": true, "booking_declined": true, "participant_left": false, "request_accepted": true, "booking_cancelled": true, "rate_participants": true, "activity_cancelled": true, "participant_joined": false, "presence_confirmed": true, "qr_create_reminder": true, "participant_removed": true, "peer_review_closing": true, "presence_pre_warning": true, "seat_request_expired": true, "participant_left_late": true, "seat_request_accepted": true, "seat_request_declined": true, "contact_request_accepted": true, "presence_validate_overdue": true, "presence_validate_warning": true, "presence_pre_warning_10min": true}'::jsonb NOT NULL,
    reliability_score double precision,
    tutorial_seen_at timestamp with time zone,
    age_confirmed_at timestamp with time zone,
    is_demo boolean DEFAULT false NOT NULL,
    language text DEFAULT 'fr'::text NOT NULL,
    CONSTRAINT users_bio_check CHECK ((char_length(bio) <= 500)),
    CONSTRAINT users_display_name_check CHECK (((char_length(display_name) >= 2) AND (char_length(display_name) <= 30))),
    CONSTRAINT users_language_check CHECK ((language = ANY (ARRAY['fr'::text, 'en'::text, 'it'::text, 'es'::text, 'de'::text]))),
    CONSTRAINT users_notification_preferences_size CHECK (((notification_preferences IS NULL) OR ((jsonb_typeof(notification_preferences) = 'object'::text) AND (pg_column_size(notification_preferences) < 4096)))),
    CONSTRAINT users_sports_shape CHECK (((sports IS NULL) OR ((jsonb_typeof(sports) = 'array'::text) AND (jsonb_array_length(sports) <= 40) AND (pg_column_size(sports) < 2048)))),
    CONSTRAINT users_tier_check CHECK ((tier = ANY (ARRAY['free'::text, 'premium'::text, 'pro'::text])))
);

ALTER TABLE ONLY public.users FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN users.language; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.language IS 'Langue effective affichée par l''app (écrite par le client). Servira à composer les notifications dans la langue du destinataire.';


--
-- Name: public_profiles; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.public_profiles AS
 SELECT id,
    display_name,
    avatar_url,
    bio,
    sports,
    levels_per_sport,
    created_at,
    NULL::double precision AS reliability_score,
    public.reliability_tier(reliability_score) AS reliability_tier,
    is_demo
   FROM public.users
  WHERE ((suspended_at IS NULL) AND ((is_demo = false) OR public.demo_content_visible()));


--
-- Name: sports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sports (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    icon text NOT NULL,
    category text NOT NULL,
    display_order integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL
);

ALTER TABLE ONLY public.sports FORCE ROW LEVEL SECURITY;


--
-- Name: activities_with_coords; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.activities_with_coords AS
 SELECT a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.distance_km,
    a.elevation_gain_m,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.requires_presence,
    a.status,
    a.deleted_at,
    a.created_at,
    a.updated_at,
    a.objective_name,
    a.meeting_name,
    a.trace_geojson,
    extensions.st_x((COALESCE(a.location_objective, a.location_meeting))::extensions.geometry) AS lng,
    extensions.st_y((COALESCE(a.location_objective, a.location_meeting))::extensions.geometry) AS lat,
    extensions.st_x((a.location_meeting)::extensions.geometry) AS meeting_lng,
    extensions.st_y((a.location_meeting)::extensions.geometry) AS meeting_lat,
    extensions.st_x((a.location_end)::extensions.geometry) AS end_lng,
    extensions.st_y((a.location_end)::extensions.geometry) AS end_lat,
    extensions.st_x((a.location_objective)::extensions.geometry) AS objective_lng,
    extensions.st_y((a.location_objective)::extensions.geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    ( SELECT (count(*))::integer AS count
           FROM public.participations p
          WHERE ((p.activity_id = a.id) AND (p.status = 'accepted'::text))) AS participant_count,
    a.level_max,
    a.meeting_locality
   FROM ((public.activities a
     JOIN public.public_profiles pp ON ((a.creator_id = pp.id)))
     JOIN public.sports s ON ((a.sport_id = s.id)))
  WHERE ((a.deleted_at IS NULL) AND (a.status = ANY (ARRAY['published'::text, 'in_progress'::text])) AND ((a.is_demo = false) OR public.demo_content_visible()) AND ((a.visibility = ANY (ARRAY['public'::text, 'approval'::text])) OR ((a.visibility = ANY (ARRAY['private_link'::text, 'private_link_approval'::text])) AND ((a.creator_id = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.participations p2
          WHERE ((p2.activity_id = a.id) AND (p2.user_id = auth.uid()) AND (p2.status = 'accepted'::text))))))) AND (NOT private.user_is_suspended(a.creator_id)) AND (NOT (a.creator_id IN ( SELECT blocked_users.blocked_id
           FROM public.blocked_users
          WHERE (blocked_users.blocker_id = auth.uid())))));


--
-- Name: get_activity_detail(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_activity_detail(p_activity_id uuid) RETURNS SETOF public.activities_with_coords
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT
    a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
    a.distance_km, a.elevation_gain_m,
    a.max_participants, a.starts_at, a.duration, a.visibility,
    a.requires_presence,
    a.status, a.deleted_at, a.created_at, a.updated_at,
    a.objective_name, a.meeting_name,
    a.trace_geojson,
    ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
    ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
    ST_X(a.location_meeting::geometry) AS meeting_lng,
    ST_Y(a.location_meeting::geometry) AS meeting_lat,
    ST_X(a.location_end::geometry) AS end_lng,
    ST_Y(a.location_end::geometry) AS end_lat,
    ST_X(a.location_objective::geometry) AS objective_lng,
    ST_Y(a.location_objective::geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    (SELECT count(*)::int FROM participations p
     WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
    a.level_max,
    a.meeting_locality
  FROM activities a
  JOIN public_profiles pp ON a.creator_id = pp.id
  JOIN sports s ON a.sport_id = s.id
  WHERE a.id = p_activity_id
    AND a.deleted_at IS NULL
    AND (a.is_demo = false OR demo_content_visible())
    AND NOT private.user_is_suspended(a.creator_id)
    AND a.creator_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
    AND (
      a.creator_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id AND p.user_id = v_user_id
          AND p.status IN ('accepted', 'pending')
      )
      OR a.visibility IN ('public', 'approval')
      -- 00486: opened through its link, or shared by its organiser.
      OR (a.visibility IN ('private_link', 'private_link_approval') AND private.private_activity_access(a.id, v_user_id))
    );
END;
$$;


--
-- Name: get_activity_participants(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_activity_participants(p_activity_id uuid) RETURNS TABLE(participation_id uuid, activity_id uuid, user_id uuid, status text, created_at timestamp with time zone, left_at timestamp with time zone, confirmed_present boolean, transport_type text, transport_seats smallint, transport_from_name text, transport_departs_at timestamp with time zone, transport_from_lat double precision, transport_from_lng double precision, display_name text, avatar_url text, transport_from_locality text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_is_creator BOOLEAN;
  v_is_member BOOLEAN;
  v_live BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      -- 00472 (audit L3): the demo curtain, like every other read surface.
      AND (a.is_demo = false OR demo_content_visible())
      AND a.deleted_at IS NULL  -- 00516
      AND (
        a.visibility IN ('public', 'approval')
        OR a.creator_id = v_user_id
        -- 00485 (AC-2): only an ACCEPTED participant, not a removed / left one.
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ) THEN
    RETURN;
  END IF;

  SELECT a.creator_id = v_user_id, a.status IN ('published', 'in_progress')
    INTO v_is_creator, v_live
  FROM activities a WHERE a.id = p_activity_id;
  v_is_member := v_is_creator OR EXISTS (
    SELECT 1 FROM participations p
    WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id AND p.status = 'accepted');

  RETURN QUERY
  SELECT
    p.id AS participation_id,
    p.activity_id,
    p.user_id,
    p.status,
    p.created_at,
    p.left_at,
    -- 00485 (DX-1): an absence is shown only to the organiser and to the
    -- person concerned; everyone else sees « present » or nothing.
    CASE WHEN p.user_id = v_user_id OR v_is_creator THEN p.confirmed_present
         -- 00488: only fellow members see « present » (once an outing is
         -- finalised, a missing tick would otherwise read as an absence).
         WHEN v_is_member AND p.confirmed_present THEN true ELSE NULL END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_type END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_seats END,
    -- 00485 (AC-2): a driver's starting point (often home) is shown only to
    -- the outing's accepted members, while it is upcoming / under way, and
    -- never across a block.
    -- 00521: the exact start point (often home) only for the driver's own
    -- accepted passengers; other members see the village (last column).
    CASE WHEN (p.user_id = v_user_id OR (v_live AND EXISTS (
      SELECT 1 FROM seat_requests sr WHERE sr.activity_id = p_activity_id
        AND sr.driver_id = p.user_id AND sr.requester_id = v_user_id AND sr.status = 'accepted')
      AND NOT EXISTS (SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
           OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_name END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_departs_at END,
    CASE WHEN (p.user_id = v_user_id OR (v_live AND EXISTS (
      SELECT 1 FROM seat_requests sr WHERE sr.activity_id = p_activity_id
        AND sr.driver_id = p.user_id AND sr.requester_id = v_user_id AND sr.status = 'accepted')
      AND NOT EXISTS (SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
           OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lat END,
    CASE WHEN (p.user_id = v_user_id OR (v_live AND EXISTS (
      SELECT 1 FROM seat_requests sr WHERE sr.activity_id = p_activity_id
        AND sr.driver_id = p.user_id AND sr.requester_id = v_user_id AND sr.status = 'accepted')
      AND NOT EXISTS (SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
           OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lng END,
    pp.display_name,
    pp.avatar_url,
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_locality END
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
  ORDER BY p.created_at;
END;
$$;


--
-- Name: get_activity_peer_review_state(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_activity_peer_review_state(p_activity_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_result jsonb;
  v_sport_key TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00520 (COV-1): suspended caller or moderated outing → nothing.
  IF private.user_is_suspended(v_user_id)
     OR EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.key INTO v_sport_key
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id',                p.user_id,
      'display_name',           pp.display_name,
      'avatar_url',             pp.avatar_url,
      -- 00488 (DX-1): never echo an absence to co-participants.
      'confirmed_present',      CASE WHEN p.confirmed_present THEN true END,
      -- 00508: peer presence testimony removed (disabled since 00434).
      'peer_validation_count',  0,
      'i_voted_presence',       false,
      'my_badge_votes',         coalesce(my_votes.keys, ARRAY[]::TEXT[]),
      'declared_level',         NULLIF(pp.levels_per_sport ->> v_sport_key, '')
    )
  ) INTO v_result
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  LEFT JOIN (
    SELECT voted_id, array_agg(badge_key) AS keys
    FROM reputation_votes
    WHERE activity_id = p_activity_id AND voter_id = v_user_id
    GROUP BY voted_id
  ) my_votes ON my_votes.voted_id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id != v_user_id;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$$;


--
-- Name: get_activity_seat_assignments(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_activity_seat_assignments(p_activity_id uuid) RETURNS TABLE(id uuid, driver_id uuid, requester_id uuid, display_name text, avatar_url text, pickup_from text, requested_pickup_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
  v_live BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.user_id = v_user_id
      AND p.status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.creator_id, a.status IN ('published', 'in_progress') INTO v_creator, v_live
  FROM activities a WHERE a.id = p_activity_id;

  RETURN QUERY
    SELECT
      sr.id,
      sr.driver_id,
      sr.requester_id,
      pp.display_name,
      pp.avatar_url,
      -- 00488: a pickup point (often home) goes to the driver, the passenger
      -- and the organiser; other members see it only while the outing is live.
      -- 00521: a pickup point goes to the driver, the passenger and the organiser only.
      CASE WHEN v_user_id IN (sr.driver_id, sr.requester_id, v_creator) THEN sr.pickup_from END,
      CASE WHEN v_user_id IN (sr.driver_id, sr.requester_id, v_creator) THEN sr.requested_pickup_at END
    FROM seat_requests sr
    JOIN public_profiles pp ON pp.id = sr.requester_id
    WHERE sr.activity_id = p_activity_id
      AND sr.status = 'accepted'
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id IN (sr.driver_id, sr.requester_id))
           OR (b.blocked_id = v_user_id AND b.blocker_id IN (sr.driver_id, sr.requester_id))
      );
END;
$$;


--
-- Name: get_channel(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_channel(p_conversation_id uuid) RETURNS TABLE(conversation_id uuid, name text, sport_key text, base_lng double precision, base_lat double precision, base_label text, radius_km integer, description text, photo_url text, member_count integer, is_member boolean, is_creator boolean, is_closed boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.conversation_id, conv.name, c.sport_key,
         ST_X(c.base::geometry), ST_Y(c.base::geometry), c.base_label, c.radius_km,
         c.description, c.photo_url,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id),
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id),
         (c.created_by = v_user_id),
         (c.closed_at IS NOT NULL)
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.conversation_id = p_conversation_id
    AND NOT EXISTS (
      SELECT 1 FROM channel_bans b
      WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id
    );
END;
$$;


--
-- Name: get_channel_members(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_channel_members(p_conversation_id uuid) RETURNS TABLE(user_id uuid, display_name text, avatar_url text, reliability_tier text, is_creator boolean, joined_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  -- Channel must exist; caller must be a member to see the roster.
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM conversation_members m
    WHERE m.conversation_id = p_conversation_id AND m.user_id = v_user_id
  ) THEN RETURN; END IF;

  RETURN QUERY
  SELECT m.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         (m.user_id = v_creator) AS is_creator, m.joined_at
  FROM conversation_members m
  JOIN public_profiles pp ON pp.id = m.user_id
  WHERE m.conversation_id = p_conversation_id
  ORDER BY (m.user_id = v_creator) DESC, m.joined_at ASC;
END;
$$;


--
-- Name: get_contacts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_contacts() RETURNS TABLE(id uuid, display_name text, avatar_url text, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT pp.id, pp.display_name, pp.avatar_url, c.created_at
  FROM conversations c
  JOIN public_profiles pp
    ON pp.id = CASE WHEN c.user_1 = v_user_id THEN c.user_2 ELSE c.user_1 END
  WHERE c.type = 'dm'
    AND c.status = 'active'
    AND c.initiated_from IN ('profile', 'discovery', 'invite')
    AND (c.user_1 = v_user_id OR c.user_2 = v_user_id)
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
         OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
    )
  ORDER BY c.created_at DESC;
END;
$$;


--
-- Name: get_conversation_peer(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_conversation_peer(p_conversation_id uuid) RETURNS TABLE(other_id uuid, display_name text, avatar_url text, initiated_from text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END AS other_id,
         pp.display_name, pp.avatar_url,
         CASE WHEN c.type = 'dm' THEN c.initiated_from END AS initiated_from
  FROM conversations c
  LEFT JOIN public_profiles pp
    ON pp.id = CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END
  WHERE auth.uid() IS NOT NULL
    AND c.id = p_conversation_id
    AND (c.user_1 = auth.uid() OR c.user_2 = auth.uid())
$$;


--
-- Name: get_conversation_state_with(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_conversation_state_with(p_other_user_id uuid) RETURNS TABLE(id uuid, state text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT c.id,
         CASE
           WHEN c.status = 'active' THEN 'active'
           WHEN c.request_sender_id = auth.uid() THEN 'pending'
           ELSE 'pending_received'
         END AS state
  FROM conversations c
  WHERE auth.uid() IS NOT NULL
    AND p_other_user_id IS NOT NULL
    AND c.user_1 = LEAST(auth.uid(), p_other_user_id)
    AND c.user_2 = GREATEST(auth.uid(), p_other_user_id)
    AND (
      c.status = 'active'
      OR c.request_sender_id = auth.uid()
      OR (c.status = 'pending_request' AND c.request_expires_at > NOW())
    )
$$;


--
-- Name: get_discovery_cards(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_discovery_cards() RETURNS TABLE(user_id uuid, display_name text, avatar_url text, reliability_tier text, sport_keys text[], levels jsonb, transport_modes text[], radius_km integer, window_start timestamp with time zone, window_end timestamp with time zone, intent text[], distance_km double precision, sorties_count integer, about text, contact_state text, conversation_id uuid, is_demo boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_radius INTEGER;
  v_sports TEXT[];
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  SELECT d.base, d.radius_km, d.sport_keys, d.window_start, d.window_end
    INTO v_base, v_radius, v_sports, v_ws, v_we
  FROM discovery_availabilities d WHERE d.user_id = v_user_id AND d.is_active;
  IF v_base IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT d.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         d.sport_keys, d.levels, d.transport_modes, d.radius_km,
         d.window_start, d.window_end, d.intent,
         -- 00485 (DC-1): whole kilometres, never below 1.
         greatest(1, round(ST_Distance(d.base, v_base) / 1000.0))::float8 AS distance_km,
         -- 00435 (trouvé par Scott) : ce compteur n'exigeait QUE status =
         -- 'accepted' — donc s'inscrire à 200 sorties futures affichait
         -- « 200 sorties » immédiatement, sans qu'aucune ait eu lieu. Et c'est
         -- le chiffre qu'un inconnu lit avant de décider de te contacter. On
         -- applique le même prédicat que get_user_public_stats : sortie
         -- réellement terminée, et présence non démentie.
         (SELECT count(*)::int FROM participations p
          JOIN activities pa ON pa.id = p.activity_id
          WHERE p.user_id = d.user_id
            AND p.status = 'accepted'
            AND p.confirmed_present = true /* 00521: validated presence only */
            AND pa.status = 'completed'
            AND pa.deleted_at IS NULL) AS sorties_count,
         d.about,
         coalesce((
           SELECT CASE
             WHEN c.status = 'active' THEN 'connected'
             WHEN c.request_sender_id = v_user_id THEN 'pending'
             WHEN c.status = 'pending_request' AND c.request_expires_at > NOW() THEN 'pending_received'
             ELSE 'none'
           END
           FROM conversations c
           WHERE c.type = 'dm'
             AND c.user_1 = LEAST(v_user_id, d.user_id)
             AND c.user_2 = GREATEST(v_user_id, d.user_id)
         ), 'none') AS contact_state,
         (
           SELECT c.id FROM conversations c
           WHERE c.type = 'dm' AND c.status = 'active'
             AND c.user_1 = LEAST(v_user_id, d.user_id)
             AND c.user_2 = GREATEST(v_user_id, d.user_id)
         ) AS conversation_id,
         u.is_demo
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  JOIN public_profiles pp ON pp.id = d.user_id
  WHERE d.is_active
    -- 00494 (BR-5): a dispo whose window is over is no longer offered.
    AND d.window_end > now()
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && v_sports
    AND tstzrange(d.window_start, d.window_end) && tstzrange(v_ws, v_we)
    AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         ST_DWithin(d.base, v_base, (CASE WHEN v_radius IS NULL AND d.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(v_radius, 0) + coalesce(d.radius_km, 0) END) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id))
  -- 00435 : le tri portait sur pp.reliability_score, que la vue public_profiles
  -- force à NULL depuis 00347 (elle ne publie que le palier) → clé de tri
  -- constamment vide, classement dégénéré en distance seule, et ce depuis six
  -- réécritures de cette fonction. On trie sur la table users, déjà jointe
  -- ligne « JOIN users u ». Ce n'est qu'un ORDER BY : aucune colonne
  -- supplémentaire n'est retournée, donc le score brut reste non publié.
  ORDER BY u.reliability_score DESC NULLS LAST, distance_km ASC;
END;
$$;


--
-- Name: get_discovery_count(text[], double precision, double precision, integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_discovery_count(p_sport_keys text[], p_base_lng double precision, p_base_lat double precision, p_radius_km integer, p_window_start timestamp with time zone, p_window_end timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN 0; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN 0; END IF;
  IF p_sport_keys IS NULL OR array_length(p_sport_keys, 1) IS NULL
     OR p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_window_start IS NULL OR p_window_end IS NULL THEN
    RETURN 0;
  END IF;
  -- 00485 (DC-2): radius from the app's list only (NULL = « anywhere », which
  -- constrains no position), probe rounded like stored bases, and a budget.
  IF p_radius_km IS NOT NULL AND p_radius_km NOT IN (5, 10, 15, 30, 50) THEN
    RAISE EXCEPTION 'junto.dispo_radius';
  END IF;
  PERFORM private.rate_hit('dispo_count', 300, INTERVAL '1 hour');
  v_base := ST_SetSRID(ST_MakePoint(round(p_base_lng::numeric, 2)::float8, round(p_base_lat::numeric, 2)::float8), 4326)::geography;

  SELECT count(*) INTO v_count
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  WHERE d.is_active
    -- 00494 (BR-5): a dispo whose window is over is no longer offered.
    AND d.window_end > now()
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && p_sport_keys
    AND tstzrange(d.window_start, d.window_end) && tstzrange(p_window_start, p_window_end)
    AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         ST_DWithin(d.base, v_base, (CASE WHEN p_radius_km IS NULL AND d.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(p_radius_km, 0) + coalesce(d.radius_km, 0) END) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id));

  IF v_count > 0 AND v_count <= 2 THEN RETURN -1; END IF;  -- -1 = "quelques"
  RETURN v_count;
END;
$$;


--
-- Name: get_dispo_zone(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_dispo_zone(p_user_id uuid) RETURNS TABLE(base_lng double precision, base_lat double precision, radius_km integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_radius INTEGER;
  v_sports TEXT[];
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;
  IF v_user_id = p_user_id THEN RETURN; END IF;  -- own zone comes from get_my_dispo

  SELECT d.base, d.radius_km, d.sport_keys, d.window_start, d.window_end
    INTO v_base, v_radius, v_sports, v_ws, v_we
  FROM discovery_availabilities d WHERE d.user_id = v_user_id AND d.is_active;
  IF v_base IS NULL THEN RETURN; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE (b.blocker_id = v_user_id AND b.blocked_id = p_user_id)
       OR (b.blocker_id = p_user_id AND b.blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  RETURN QUERY
  SELECT ST_X(t.base::geometry), ST_Y(t.base::geometry), t.radius_km
  FROM discovery_availabilities t
  JOIN users u ON u.id = t.user_id AND u.suspended_at IS NULL
  WHERE t.user_id = p_user_id
    AND t.is_active
    -- 00494 (BR-5): a dispo whose window is over is no longer offered.
    AND t.window_end > now()
    AND (t.is_demo = false OR demo_content_visible())
    AND t.sport_keys && v_sports
    AND tstzrange(t.window_start, t.window_end) && tstzrange(v_ws, v_we)
    AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         ST_DWithin(t.base, v_base, (CASE WHEN v_radius IS NULL AND t.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(v_radius, 0) + coalesce(t.radius_km, 0) END) * 1000.0));
END;
$$;


--
-- Name: get_favorites(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_favorites() RETURNS TABLE(kind text, ref_id uuid, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    CASE
      WHEN f.activity_id IS NOT NULL THEN 'activity'
      WHEN f.offering_id IS NOT NULL THEN 'offering'
      ELSE 'pro'
    END AS kind,
    coalesce(f.activity_id, f.offering_id, f.pro_id) AS ref_id,
    f.created_at
  FROM favorites f
  WHERE f.owner_id = v_user_id
  ORDER BY f.created_at DESC;
END;
$$;


--
-- Name: get_group_info(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_group_info(p_conversation_id uuid) RETURNS TABLE(group_name text, group_icon text, created_by uuid, member_id uuid, member_name text, member_avatar text, member_joined_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT c.name, c.icon, c.created_by,
         cm.user_id, COALESCE(pp.display_name, '?'), pp.avatar_url, cm.joined_at
  FROM conversations c
  JOIN conversation_members cm ON cm.conversation_id = c.id
  LEFT JOIN public_profiles pp ON pp.id = cm.user_id
  WHERE c.id = p_conversation_id
    AND c.type = 'group'
    AND auth.uid() IS NOT NULL
    AND private.is_conversation_member(c.id, auth.uid())
  ORDER BY cm.joined_at ASC
$$;


--
-- Name: get_invitable_activities_for_dispo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_invitable_activities_for_dispo(p_target_user_id uuid) RETURNS TABLE(id uuid, title text, sport_key text, starts_at timestamp with time zone, max_participants integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_dispo RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_user_id AND u0.suspended_at IS NOT NULL) THEN RETURN; END IF;
  IF v_user_id = p_target_user_id THEN RETURN; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  -- Reciprocity: the target must be one of MY discovery matches. Silent empty
  -- otherwise (no availability oracle for a non-match / demo dispo).
  IF NOT EXISTS (
    SELECT 1
    FROM discovery_availabilities me
    JOIN discovery_availabilities tgt
      ON tgt.user_id = p_target_user_id AND tgt.is_active AND tgt.window_end > now()  -- 00496 (BR-5)
         AND (tgt.is_demo = false OR demo_content_visible())
    WHERE me.user_id = v_user_id AND me.is_active AND me.window_end > now()
      AND me.sport_keys && tgt.sport_keys
      AND tstzrange(me.window_start, me.window_end) && tstzrange(tgt.window_start, tgt.window_end)
      AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         ST_DWithin(me.base, tgt.base, (CASE WHEN me.radius_km IS NULL AND tgt.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(me.radius_km, 0) + coalesce(tgt.radius_km, 0) END) * 1000.0))
  ) THEN RETURN; END IF;

  SELECT d.sport_keys, d.window_start, d.window_end INTO v_dispo
  FROM discovery_availabilities d
  WHERE d.user_id = p_target_user_id AND d.is_active AND d.window_end > now()
    AND (d.is_demo = false OR demo_content_visible());
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT a.id, a.title, s.key, a.starts_at, a.max_participants
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.creator_id = v_user_id
    AND a.deleted_at IS NULL
    AND NOT a.is_demo
    AND a.status IN ('published', 'in_progress')
    AND s.key = ANY(v_dispo.sport_keys)
    AND a.starts_at BETWEEN v_dispo.window_start AND v_dispo.window_end
  ORDER BY a.starts_at ASC;
END;
$$;


--
-- Name: get_late_leavers(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_late_leavers(p_activity_id uuid) RETURNS TABLE(participation_id uuid, user_id uuid, display_name text, avatar_url text, left_at timestamp with time zone, left_reason text, penalty_waived boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_user_id AND u0.suspended_at IS NOT NULL) THEN RETURN; END IF;
  -- Creator only (00478, audit PR-6: the client read participations directly,
  -- which RLS limits to the caller's own row, so the list was always empty).
  IF NOT EXISTS (SELECT 1 FROM activities a0 WHERE a0.id = p_activity_id AND a0.creator_id = v_user_id) THEN RETURN; END IF;

  RETURN QUERY
    SELECT p.id, lc.user_id, pp.display_name, pp.avatar_url, lc.at, p.left_reason, lc.waived
    FROM late_cancels lc
    JOIN participations p ON p.activity_id = lc.activity_id AND p.user_id = lc.user_id
    JOIN public_profiles pp ON pp.id = lc.user_id
    WHERE lc.activity_id = p_activity_id
    ORDER BY lc.at;
END;
$$;


--
-- Name: get_my_active_presence_activities(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_active_presence_activities() RETURNS TABLE(activity_id uuid, title text, starts_at timestamp with time zone, duration interval, meeting_lng double precision, meeting_lat double precision, end_lng double precision, end_lat double precision)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    a.id AS activity_id,
    a.title,
    a.starts_at,
    a.duration,
    ST_X(a.location_meeting::geometry)::float AS meeting_lng,
    ST_Y(a.location_meeting::geometry)::float AS meeting_lat,
    ST_X(a.location_end::geometry)::float AS end_lng,
    ST_Y(a.location_end::geometry)::float AS end_lat
  FROM activities a
  JOIN participations p ON p.activity_id = a.id
  WHERE p.user_id = v_user_id
    AND p.status = 'accepted'
    AND p.confirmed_present IS NULL
    AND a.creator_id != v_user_id          -- creator never self-confirms
    AND a.requires_presence = TRUE
    AND a.deleted_at IS NULL
    AND a.status IN ('published', 'in_progress')
    -- 00431 : fenêtre d'ARMEMENT élargie de 2 h à 24 h. Elle ne décide PAS
    -- quand une présence est valide (ça reste T±15min, vérifié par la tâche de
    -- geofencing ET par confirm_presence_via_geo) : elle décide seulement quand
    -- l'OS reçoit la zone à surveiller. À 2 h, il fallait ouvrir l'app dans un
    -- créneau de 2 h 15 pour que la détection en arrière-plan existe — sinon la
    -- validation « automatique, app fermée » n'avait jamais lieu. À 24 h,
    -- n'importe quelle ouverture de l'app la veille arme le système.
    AND now() >= a.starts_at - INTERVAL '24 hours'
    AND now() <= a.starts_at + INTERVAL '15 minutes'
  -- Les plus proches d'abord : le client plafonne à 20 zones (limite iOS) et
  -- coupait jusqu'ici une liste non triée, donc au hasard.
  ORDER BY a.starts_at ASC;
END;
$$;


--
-- Name: get_my_bookings(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_bookings() RETURNS TABLE(id uuid, offering_id uuid, offering_title text, pro_id uuid, pro_name text, day date, period text, party_size integer, status text, conversation_id uuid, created_at timestamp with time zone, location_name text, price_eur numeric, price_unit text, sport_key text, sport_category text, equipment_required jsonb, participant_fields jsonb, participant_info jsonb)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  -- 00501 (PO-6): a suspended account reads nothing (like the table).
  IF private.user_is_suspended(v_user_id) THEN RETURN; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'expired'
  WHERE bookings.client_id = v_user_id AND bookings.status = 'pending' AND bookings.day < private.today_paris();
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN QUERY
  SELECT b.id, b.offering_id, po.title, b.pro_id, pp.display_name,
         b.day, b.period, b.party_size, b.status,
         (SELECT c.id FROM conversations c
          WHERE c.type = 'dm' AND c.status = 'active'
            AND c.user_1 = LEAST(v_user_id, b.pro_id)
            AND c.user_2 = GREATEST(v_user_id, b.pro_id)),
         b.created_at,
         po.location_name, coalesce(b.price_eur, po.price_eur), coalesce(b.price_unit, po.price_unit::TEXT),  -- 00501 (PO-5)
         s.key::TEXT, s.category::TEXT,
         po.equipment_required, po.participant_fields, b.participant_info
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.pro_id
  WHERE b.client_id = v_user_id
  ORDER BY b.day DESC, b.created_at DESC;
END;
$$;


--
-- Name: get_my_conversations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_conversations() RETURNS TABLE(id uuid, type text, status text, last_message_at timestamp with time zone, created_at timestamp with time zone, last_message_content text, last_message_sender_id uuid, last_message_metadata jsonb, is_unread boolean, user_1 uuid, user_2 uuid, other_user_id uuid, other_user_name text, other_user_avatar text, other_user_reliability_tier text, name text, icon text, member_count integer, activity_id uuid, activity_title text, sport_id uuid, photo_url text, initiated_from text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT
    c.id, c.type, c.status, c.last_message_at, c.created_at,
    lm.content, lm.sender_id, lm.metadata,
    EXISTS (
      SELECT 1 FROM messages m
      WHERE m.conversation_id = c.id
        AND m.deleted_at IS NULL
        AND m.sender_id IS DISTINCT FROM auth.uid()
        AND private.message_author_visible(c.id, m.sender_id, auth.uid())
        AND (me.last_read_at IS NULL OR m.created_at > me.last_read_at)
    ) AS is_unread,
    c.user_1, c.user_2,
    CASE WHEN c.type = 'dm' THEN (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END) END,
    CASE WHEN c.type = 'dm' THEN COALESCE(pp.display_name, '?') END,
    CASE WHEN c.type = 'dm' THEN pp.avatar_url END,
    CASE WHEN c.type = 'dm' THEN pp.reliability_tier END,
    CASE WHEN c.type IN ('group', 'channel') THEN c.name END,
    CASE WHEN c.type = 'group' THEN c.icon END,
    CASE WHEN c.type IN ('group', 'channel') THEN (SELECT count(*)::int FROM conversation_members gm WHERE gm.conversation_id = c.id) END,
    CASE WHEN c.type = 'activity' THEN c.activity_id END,
    CASE WHEN c.type = 'activity' THEN act.title END,
    CASE WHEN c.type = 'activity' THEN act.sport_id WHEN c.type = 'channel' THEN cs.id END,
    CASE WHEN c.type = 'channel' THEN ch.photo_url END,
    CASE WHEN c.type = 'dm' THEN c.initiated_from END
  FROM conversations c
  JOIN conversation_members me
    ON me.conversation_id = c.id AND me.user_id = auth.uid() AND me.hidden_at IS NULL
  LEFT JOIN public_profiles pp
    ON c.type = 'dm' AND pp.id = (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END)
  LEFT JOIN activities act
    ON c.type = 'activity' AND act.id = c.activity_id
  LEFT JOIN channels ch
    ON c.type = 'channel' AND ch.conversation_id = c.id
  LEFT JOIN sports cs
    ON ch.sport_key IS NOT NULL AND cs.key = ch.sport_key
  LEFT JOIN LATERAL (
    SELECT m.content, m.sender_id, m.metadata
    FROM messages m
    WHERE m.conversation_id = c.id AND m.deleted_at IS NULL
      AND private.message_author_visible(m.conversation_id, m.sender_id, auth.uid())
    ORDER BY m.created_at DESC LIMIT 1
  ) lm ON TRUE
  WHERE auth.uid() IS NOT NULL
    AND NOT private.user_is_suspended(auth.uid())  -- 00515: suspended → nothing
    AND (
      (c.type = 'dm' AND c.status = 'active'
        AND NOT EXISTS (
          SELECT 1 FROM blocked_users b
          WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
             OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
        ))
      OR c.type = 'group'
      OR c.type = 'channel'
      OR (c.type = 'activity'
          AND act.id IS NOT NULL
          AND act.deleted_at IS NULL
          AND act.is_demo = (SELECT u.is_demo FROM users u WHERE u.id = auth.uid())
          AND (act.status IN ('published', 'in_progress')
               OR act.starts_at > now() - INTERVAL '30 days'))
    )
  ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
$$;


--
-- Name: get_my_dispo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_dispo() RETURNS TABLE(id uuid, sport_keys text[], levels jsonb, intent text[], base_lng double precision, base_lat double precision, base_label text, radius_km integer, transport_modes text[], window_start timestamp with time zone, window_end timestamp with time zone, is_active boolean, about text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
  SELECT id, sport_keys, levels, intent,
         ST_X(base::geometry), ST_Y(base::geometry), base_label,
         radius_km, transport_modes, window_start, window_end, is_active, about
  FROM discovery_availabilities
  WHERE user_id = auth.uid()
  LIMIT 1;
$$;


--
-- Name: get_my_invitations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_invitations() RETURNS TABLE(activity_id uuid, activity_title text, sport_id uuid, starts_at timestamp with time zone, invited_by uuid, inviter_name text, inviter_avatar text, invite_message text, invited_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT a.id, a.title, a.sport_id, a.starts_at,
         p.invited_by, pp.display_name, pp.avatar_url,
         p.invite_message, p.created_at
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  LEFT JOIN public_profiles pp ON pp.id = p.invited_by
  WHERE auth.uid() IS NOT NULL
    AND p.user_id = auth.uid()
    AND p.status = 'invited'
    AND a.deleted_at IS NULL
    AND a.status IN ('published', 'in_progress')
  ORDER BY p.created_at DESC
$$;


--
-- Name: get_my_pro_application(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_pro_application() RETURNS TABLE(user_id uuid, display_name text, company_name text, real_name text, tagline text, description text, website text, email text, phone text, instagram text, facebook text, primary_lng double precision, primary_lat double precision, primary_location_name text, pin_image_url text, pin_icon text, status text, rejection_reason text, last_location_change_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT pp.user_id, pp.display_name, pp.company_name, pp.real_name,
         pp.tagline, pp.description, pp.website, pp.email, pp.phone,
         pp.instagram, pp.facebook,
         pp.primary_lng, pp.primary_lat, pp.primary_location_name,
         pp.pin_image_url, pp.pin_icon,
         pp.status, pp.rejection_reason,
         pp.last_location_change_at, pp.created_at, pp.updated_at
  FROM pro_profiles pp
  WHERE pp.user_id = v_user_id;
END;
$$;


--
-- Name: get_own_invite_token(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_own_invite_token(p_activity_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_token UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only the creator can get the invite token
  SELECT invite_token INTO v_token
  FROM activities
  WHERE id = p_activity_id AND creator_id = v_user_id AND deleted_at IS NULL;

  IF v_token IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN v_token;
END;
$$;


--
-- Name: get_pending_contact_requests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_pending_contact_requests() RETURNS TABLE(id uuid, user_1 uuid, user_2 uuid, request_sender_id uuid, initiated_from text, request_message text, created_at timestamp with time zone, sender_name text, sender_avatar text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT c.id, c.user_1, c.user_2, c.request_sender_id, c.initiated_from,
         c.request_message, c.created_at,
         COALESCE(pp.display_name, '?') AS sender_name,
         pp.avatar_url AS sender_avatar
  FROM conversations c
  LEFT JOIN public_profiles pp ON pp.id = c.request_sender_id
  WHERE auth.uid() IS NOT NULL
    AND c.status = 'pending_request'
    AND (c.user_1 = auth.uid() OR c.user_2 = auth.uid())
    AND c.request_sender_id IS DISTINCT FROM auth.uid()
    AND NOT private.user_is_suspended(c.request_sender_id)  -- 00514
    AND (c.request_expires_at IS NULL OR c.request_expires_at > NOW())
  ORDER BY c.created_at DESC
$$;


--
-- Name: get_pro_agenda(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_pro_agenda(p_from date, p_to date) RETURNS TABLE(kind text, id uuid, day date, period text, status text, offering_id uuid, offering_title text, party_size integer, client_id uuid, client_name text, manual_phone text, message text, is_manual boolean, sport_key text, sport_category text, participant_fields jsonb, participant_info jsonb)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_flip RECORD;
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from
     OR p_to > p_from + INTERVAL '12 months' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Expiration paresseuse + notif client (00420 D3).
  PERFORM set_config('junto.bypass_lock', 'true', true);
  FOR v_flip IN
    WITH flipped AS (
      UPDATE bookings SET status = 'expired'
      WHERE bookings.pro_id = v_user_id AND bookings.status = 'pending'
        AND bookings.day < private.today_paris()
      RETURNING bookings.id AS b_id, bookings.client_id AS b_client,
                bookings.offering_id AS b_off, bookings.day AS b_day,
                bookings.period AS b_period
    )
    SELECT f.b_id, f.b_client, f.b_off, f.b_day, f.b_period, po.title AS b_title
    FROM flipped f
    LEFT JOIN pro_offerings po ON po.id = f.b_off
    WHERE f.b_client IS NOT NULL
  LOOP
    v_period_label := CASE v_flip.b_period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;
    PERFORM create_notification(
      v_flip.b_client,
      'booking_expired',
      'Demande expirée',
      'Ta demande pour « ' || coalesce(v_flip.b_title, 'une sortie') || ' » du '
        || to_char(v_flip.b_day, 'DD/MM') || ', ' || v_period_label
        || ' a expiré sans réponse. Tu peux demander un autre créneau.',
      jsonb_build_object('booking_id', v_flip.b_id, 'offering_id', v_flip.b_off,
        'params', jsonb_build_object('title', coalesce(v_flip.b_title, 'une sortie'),
                                     'date', to_char(v_flip.b_day, 'YYYY-MM-DD'), 'period', v_flip.b_period))
    );
  END LOOP;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN QUERY
  SELECT 'availability'::TEXT, a.id, a.day, a.period, NULL::TEXT,
         NULL::UUID, NULL::TEXT, NULL::INTEGER, NULL::UUID, NULL::TEXT, NULL::TEXT,
         NULL::TEXT, NULL::BOOLEAN, NULL::TEXT, NULL::TEXT, NULL::JSONB, NULL::JSONB
  FROM pro_availabilities a
  WHERE a.pro_id = v_user_id AND a.day BETWEEN p_from AND p_to
  UNION ALL
  SELECT 'booking'::TEXT, b.id, b.day, b.period, b.status,
         b.offering_id, po.title, b.party_size, b.client_id,
         coalesce(pp.display_name, b.manual_name),
         b.manual_phone, b.message, (b.client_id IS NULL),
         s.key::TEXT, s.category::TEXT,
         po.participant_fields, b.participant_info
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.client_id
  WHERE b.pro_id = v_user_id
    AND b.day BETWEEN p_from AND p_to
    AND b.status IN ('pending', 'accepted')
  ORDER BY 3, 4;
END;
$$;


--
-- Name: get_pro_availability(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_pro_availability(p_pro_id uuid) RETURNS TABLE(day date, period text, taken integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  -- Cible : pro approuvé + tier pro (00419), non suspendu, gate démo, pas de blocage.
  IF NOT EXISTS (
    SELECT 1 FROM pro_profiles pp
    JOIN users u ON u.id = pp.user_id
    WHERE pp.user_id = p_pro_id
      AND pp.status = 'approved'
      AND u.tier = 'pro'
      AND u.suspended_at IS NULL
      AND (pp.is_demo = false OR demo_content_visible())
  ) THEN RETURN; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_pro_id)
       OR (blocker_id = p_pro_id AND blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  -- `taken` = somme des groupes ACCEPTÉS du pro sur le créneau, toutes offres
  -- confondues (un pro = une sortie par demi-journée). Agrégat anonyme :
  -- aucun nom, aucune composition de groupe ne fuite.
  RETURN QUERY
  SELECT a.day, a.period,
         coalesce((
           SELECT sum(b.party_size)::INTEGER FROM bookings b
           WHERE b.pro_id = p_pro_id AND b.day = a.day AND b.period = a.period
             AND b.status = 'accepted'
         ), 0) AS taken
  FROM pro_availabilities a
  WHERE a.pro_id = p_pro_id AND a.day >= private.today_paris()
  ORDER BY a.day, a.period;
END;
$$;


--
-- Name: get_recent_partners(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_recent_partners() RETURNS TABLE(id uuid, display_name text, avatar_url text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_user_id AND u0.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH my_activities AS (
    SELECT a.id, a.starts_at, a.creator_id
    FROM activities a
    WHERE a.deleted_at IS NULL
      AND a.starts_at <= now()
      AND a.starts_at > now() - INTERVAL '180 days'
      AND (
        a.creator_id = v_user_id
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ),
  partners AS (
    SELECT ma.creator_id AS uid, ma.starts_at AS at
    FROM my_activities ma
    WHERE ma.creator_id <> v_user_id
    UNION ALL
    SELECT p.user_id AS uid, ma.starts_at AS at
    FROM my_activities ma
    JOIN participations p
      ON p.activity_id = ma.id AND p.status = 'accepted' AND p.user_id <> v_user_id
  ),
  ranked AS (
    SELECT uid, max(at) AS last_at
    FROM partners
    GROUP BY uid
  )
  SELECT pp.id, pp.display_name, pp.avatar_url
  FROM ranked r
  JOIN public_profiles pp ON pp.id = r.uid
  WHERE NOT EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.type = 'dm' AND c.status = 'active'
        AND ((c.user_1 = v_user_id AND c.user_2 = r.uid)
          OR (c.user_1 = r.uid AND c.user_2 = v_user_id))
    )
    AND r.uid NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id)
    AND r.uid NOT IN (SELECT blocker_id FROM blocked_users WHERE blocked_id = v_user_id)
  ORDER BY r.last_at DESC
  LIMIT 20;
END;
$$;


--
-- Name: get_transport_summary(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_transport_summary(p_activity_id uuid) RETURNS TABLE(transport_type text, count integer, total_seats integer, cities text[])
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
      AND (a.is_demo = false OR demo_content_visible())
      AND (
        a.visibility IN ('public', 'approval')
        OR a.creator_id = v_user_id
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_is_member := EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.creator_id = v_user_id)
    OR EXISTS (SELECT 1 FROM participations p WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id AND p.status = 'accepted');

  RETURN QUERY
  SELECT
    p.transport_type,
    count(*)::int AS count,
    COALESCE(sum(p.transport_seats)::int, 0) AS total_seats,
    -- 00490 (Scott): where the cars leave from is what makes someone join
    -- (« a car leaves from my town »), so every viewer of the outing sees the
    -- places — never WHO leaves from where (per-person transport is masked
    -- for non-members in get_activity_participants). Never across a block.
    -- 00521: villages only (never the typed text, often an address).
    array_agg(DISTINCT p.transport_from_locality) FILTER (
      WHERE p.transport_from_locality IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM blocked_users b
          WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
             OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id))) AS cities
  FROM participations p
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.transport_type IS NOT NULL
  GROUP BY p.transport_type
  ORDER BY count DESC;
END;
$$;


--
-- Name: get_user_award_aggregates(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_award_aggregates(p_user_id uuid) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  WITH completed AS (
    SELECT
      a.id,
      a.creator_id,
      a.duration,
      s.key AS sport_key,
      s.category
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND p.confirmed_present = true /* 00521: validated presence only */  -- 00520 (PR-7)
      AND a.status = 'completed'
      AND a.deleted_at IS NULL  -- 00520 (PR-10)
      AND auth.uid() IS NOT NULL AND NOT private.user_is_suspended(auth.uid())  -- 00520 (ID-9)
      AND NOT private.user_is_suspended(p_user_id)  -- 00503 (DX-3)
      -- 00419 M3 : rideau démo.
      AND NOT (
        EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
        AND NOT demo_content_visible()
      )
  ),
  per_category AS (
    SELECT
      category,
      count(*)::int AS outings,
      count(DISTINCT sport_key)::int AS distinct_sports
    FROM completed
    GROUP BY category
  )
  SELECT jsonb_build_object(
    'joined', (SELECT count(*)::int FROM completed WHERE creator_id IS DISTINCT FROM p_user_id),
    'created', (SELECT count(*)::int FROM completed WHERE creator_id = p_user_id),
    'distinct_sports', (SELECT count(DISTINCT sport_key)::int FROM completed),
    'multi_day_count', (SELECT count(*)::int FROM completed WHERE duration > INTERVAL '1 day'),
    'by_category', COALESCE((
      SELECT jsonb_object_agg(category, jsonb_build_object(
        'outings', outings,
        'distinct_sports', distinct_sports
      )) FROM per_category
    ), '{}'::jsonb)
  );
$$;


--
-- Name: get_user_public_stats(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_public_stats(p_user_id uuid) RETURNS TABLE(total_activities integer, completed_activities integer, created_activities integer, joined_activities integer, sports_count integer, reliability_score double precision, reliability_tier text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- 00419 M3 : rideau démo.
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;

  -- 00499 (DX-3): a suspended account reveals nothing (like public_profiles).
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
  -- 00520 (ID-9): a signed-in, non-suspended caller only.
  IF auth.uid() IS NULL OR private.user_is_suspended(auth.uid()) THEN RETURN; END IF;

  RETURN QUERY
  WITH real_outings AS (
    SELECT a.id, a.creator_id
    FROM participations par
    JOIN activities a ON a.id = par.activity_id
    WHERE par.user_id = p_user_id
      AND par.status = 'accepted'
      AND par.confirmed_present = true /* 00521: validated presence only */
      AND a.status = 'completed'
      AND a.deleted_at IS NULL
  )
  SELECT
    (SELECT count(*)::int FROM real_outings) AS total_activities,
    (SELECT count(*)::int FROM real_outings) AS completed_activities,
    (SELECT count(*)::int FROM real_outings WHERE creator_id = p_user_id) AS created_activities,
    (SELECT count(*)::int FROM real_outings WHERE creator_id != p_user_id) AS joined_activities,
    (SELECT count(DISTINCT jsonb_array_elements_text)::int
     FROM users, jsonb_array_elements_text(sports)
     WHERE users.id = p_user_id) AS sports_count,
    -- 00488: the raw score is not public (public_profiles hides it since
    -- 00347); only the tier below is.
    NULL::double precision AS reliability_score,
    (SELECT public.reliability_tier(u.reliability_score)
     FROM users u WHERE u.id = p_user_id) AS reliability_tier;
END;
$$;


--
-- Name: get_user_reputation(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_reputation(p_user_id uuid) RETURNS TABLE(badge_key text, vote_count integer, last_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_caller UUID;
  v_negative_keys TEXT[] := ARRAY[
    'unprepared', 'aggressive', 'reckless',
    'late_canceller', 'level_overestimated', 'unreliable_field', 'difficult_attitude'
  ];
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_caller AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00419 M3 : rideau démo.
  -- 00516 (DX-3): a suspended account reveals nothing.
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH grouped AS (
    SELECT
      rv.badge_key,
      count(DISTINCT rv.voter_id)::int AS total_count,  -- 00496 (PR-11): people, not votes
      date_trunc('month', max(rv.created_at)) AS max_at  -- 00496 (PR-3): no exact vote time
    FROM reputation_votes rv
    WHERE rv.voted_id = p_user_id
      AND rv.counted_at IS NOT NULL
      AND rv.badge_key NOT IN ('level_over', 'level_right', 'level_under')
    GROUP BY rv.badge_key
  )
  SELECT
    g.badge_key,
    CASE
      WHEN g.badge_key = ANY(v_negative_keys)
        THEN get_active_negative_count(p_user_id, g.badge_key)
      ELSE g.total_count
    END AS vote_count,
    g.max_at AS last_at
  FROM grouped g
  WHERE
    -- 00496 (PR-3): a negative trait is returned only from the warning
    -- threshold the app shows (5) — below it, even its target cannot tell
    -- who voted by elimination.
    NOT (
      g.badge_key = ANY(v_negative_keys)
      AND get_active_negative_count(p_user_id, g.badge_key) < 5
    );
END;
$$;


--
-- Name: get_user_sport_level_votes(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_sport_level_votes(p_user_id uuid) RETURNS TABLE(sport_key text, level_over integer, level_right integer)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT
    s.key AS sport_key,
    count(*) FILTER (WHERE rv.badge_key = 'level_over')::int AS level_over,
    count(*) FILTER (WHERE rv.badge_key = 'level_right')::int AS level_right
  FROM reputation_votes rv
  JOIN activities a ON a.id = rv.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE rv.voted_id = p_user_id
    AND rv.badge_key IN ('level_over', 'level_right')
    AND rv.counted_at IS NOT NULL
    AND NOT private.user_is_suspended(p_user_id)  -- 00503 (DX-3)
    AND auth.uid() IS NOT NULL AND NOT private.user_is_suspended(auth.uid())  -- 00520 (ID-9)
    AND rv.created_at >= now() - INTERVAL '12 months'   -- sliding freshness window
    -- 00493 (IX-3): demo curtain.
    AND (NOT EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo) OR demo_content_visible())
  GROUP BY s.key
  HAVING count(*) > 0;
$$;


--
-- Name: get_user_sport_levels(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_sport_levels(p_user_id uuid) RETURNS TABLE(sport_key text, dots smallint, last_at timestamp with time zone, first_at timestamp with time zone)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  WITH completed AS (
    SELECT s.key AS sport_key, private.level_tier(s.key, a.level) AS tier, a.starts_at AS at
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND p.confirmed_present = true /* 00521: validated presence only */  -- 00495 (PR-7)
      AND a.status = 'completed'
      AND a.deleted_at IS NULL  -- 00495
      AND NOT private.user_is_suspended(p_user_id)  -- 00503 (DX-3)
      AND auth.uid() IS NOT NULL AND NOT private.user_is_suspended(auth.uid())  -- 00520 (ID-9)
      -- 00419 M3 : rideau démo.
      AND NOT (
        EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
        AND NOT demo_content_visible()
      )
  ),
  agg AS (
    SELECT
      completed.sport_key,
      count(*) AS total,
      count(*) FILTER (
        WHERE completed.tier >= 1  -- 00525: app values (« Intermédiaire », « 6b »…)
      ) AS at_intermediate,
      count(*) FILTER (
        WHERE completed.tier >= 2
      ) AS at_advanced,
      count(*) FILTER (WHERE completed.tier = 3) AS at_expert,
      max(completed.at) AS last_at,
      min(completed.at) AS first_at
    FROM completed
    GROUP BY completed.sport_key
  )
  SELECT
    agg.sport_key,
    (CASE
      WHEN agg.at_expert >= 3 THEN 4
      WHEN agg.at_advanced >= 5 THEN 3
      WHEN agg.at_intermediate >= 3 THEN 2
      WHEN agg.total >= 1 THEN 1
      ELSE 0
    END)::SMALLINT AS dots,
    -- 00499 (DX-4): month only — an exact time could date a private outing.
    date_trunc('month', agg.last_at),
    date_trunc('month', agg.first_at)
  FROM agg
  WHERE agg.total > 0;
$$;


--
-- Name: get_user_trophies(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_trophies(p_user_id uuid) RETURNS TABLE(category text, sport_key text, count integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_caller UUID;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_caller AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00419 M3 : rideau démo.
  -- 00516 (DX-3): a suspended account reveals nothing.
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 'joined'::text, NULL::text,
    (SELECT count(*)::int
     FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id
       AND par.status = 'accepted'
       AND par.confirmed_present = true /* 00521: validated presence only */  -- 00491 (PR-7): an absence is not an outing
       AND a.status = 'completed'
       AND a.creator_id != p_user_id
       AND a.deleted_at IS NULL)
  UNION ALL
  SELECT 'created'::text, NULL::text,
    (SELECT count(*)::int
     FROM activities
     WHERE creator_id = p_user_id
       AND status = 'completed'
       AND deleted_at IS NULL
       -- 00521: only an outing whose organiser's presence was validated.
       AND EXISTS (SELECT 1 FROM participations cp
                   WHERE cp.activity_id = activities.id AND cp.user_id = p_user_id
                     AND cp.confirmed_present = true))
  UNION ALL
  SELECT 'sport'::text, s.key::text, count(*)::int
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND par.confirmed_present = true /* 00521: validated presence only */  -- 00491 (PR-7)
    AND a.status = 'completed'
    AND a.deleted_at IS NULL
  GROUP BY s.key
  HAVING count(*) > 0;
END;
$$;


--
-- Name: get_voters_for_badge(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_voters_for_badge(p_user_id uuid, p_badge_key text) RETURNS TABLE(voter_id uuid, display_name text, avatar_url text, voted_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00493 (IX-3): demo curtain, like get_user_reputation.
  -- 00516 (DX-3): a suspended account reveals nothing.
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;
  -- 00493 (PR-3): voters are shown only for a POSITIVE trait, and only once
  -- at least 5 different people gave it (the app shows the trait from 5 on).
  -- A negative vote never reveals its author (no retaliation).
  IF p_badge_key NOT IN ('punctual', 'prepared', 'conciliant', 'prudent') THEN RETURN; END IF;
  IF (SELECT count(DISTINCT rv.voter_id) FROM reputation_votes rv
      WHERE rv.voted_id = p_user_id AND rv.badge_key = p_badge_key AND rv.counted_at IS NOT NULL) < 5 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT *
  FROM (
    SELECT DISTINCT ON (rv.voter_id)
      pp.id           AS voter_id,
      pp.display_name AS display_name,
      pp.avatar_url   AS avatar_url,
      date_trunc('month', rv.created_at) AS voted_at  -- 00516 (PR-3)
    FROM reputation_votes rv
    JOIN public_profiles pp ON pp.id = rv.voter_id
    WHERE rv.voted_id  = p_user_id
      AND rv.badge_key = p_badge_key
      AND rv.counted_at IS NOT NULL
    ORDER BY rv.voter_id, rv.created_at DESC
  ) deduped
  ORDER BY deduped.voted_at DESC;
END;
$$;


--
-- Name: get_wall_messages(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_wall_messages(p_activity_id uuid) RETURNS TABLE(id uuid, conversation_id uuid, user_id uuid, content text, metadata jsonb, reply_to_message_id uuid, edited_at timestamp with time zone, created_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  -- Latest 200 (server-side cap), returned oldest-first for the UI.
  SELECT * FROM (
    SELECT m.id, m.conversation_id, m.sender_id, m.content, m.metadata,
           m.reply_to_message_id, m.edited_at, m.created_at
    FROM messages m
    JOIN conversations c ON c.id = m.conversation_id
    WHERE auth.uid() IS NOT NULL
      AND c.activity_id = p_activity_id
      AND m.deleted_at IS NULL
      AND private.is_conversation_member(c.id, auth.uid())
      AND private.message_author_visible(c.id, m.sender_id, auth.uid())
    ORDER BY m.created_at DESC
    LIMIT 200
  ) sub
  ORDER BY created_at ASC
$$;


--
-- Name: give_reputation_badge(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.give_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_recent_count INTEGER;
  v_valid_keys TEXT[] := ARRAY[
    'punctual', 'prepared', 'conciliant', 'prudent',
    'unprepared', 'aggressive', 'reckless',
    'level_over', 'level_right'
  ];
  v_level_keys TEXT[] := ARRAY['level_over', 'level_right'];
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_voted_id)
       OR (blocker_id = p_voted_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('reputation_vote:' || v_user_id::text));

  SELECT count(*) INTO v_recent_count
  FROM reputation_votes
  WHERE voter_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_recent_count >= 20 THEN RAISE EXCEPTION 'junto.badge_rate_limit'; END IF;

  IF NOT (p_badge_key = ANY(v_valid_keys)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, duration, sport_id, requires_presence INTO v_activity
  FROM activities WHERE id = p_activity_id
    AND deleted_at IS NULL;  -- 00496 (BR-8): no votes on a moderated outing

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00497 (Scott): votes only where presence was verified — an outing without
  -- it proves nobody was there, so it cannot build or smear a reputation.
  IF v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.votes_need_presence';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.badge_window_not_open';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'junto.badge_window_closed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_voted_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- A level vote judges the accuracy of a DECLARED level. With no declaration,
  -- there is no reference point — reject. The client hides the level section for
  -- such targets, so this path is a backstop (stale client / tamper): generic.
  IF p_badge_key = ANY(v_level_keys) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM users u
      JOIN sports s ON s.id = v_activity.sport_id
      WHERE u.id = p_voted_id
        AND COALESCE(u.levels_per_sport ->> s.key, '') <> ''
    ) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  IF p_badge_key = ANY(v_level_keys) THEN
    DELETE FROM reputation_votes
    WHERE voter_id = v_user_id
      AND voted_id = p_voted_id
      AND activity_id = p_activity_id
      AND badge_key = ANY(v_level_keys);
  END IF;

  -- 00493 (PR-12): voting twice for the same trait is a no-op, not a raw
  -- unique-violation error.
  INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, p_badge_key, now())
  ON CONFLICT DO NOTHING;
END;
$$;


--
-- Name: handle_activity_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_activity_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  NEW.creator_id := OLD.creator_id;
  NEW.status := OLD.status;
  NEW.invite_token := OLD.invite_token;
  NEW.created_at := OLD.created_at;
  NEW.deleted_at := OLD.deleted_at;
  NEW.cancelled_reason := OLD.cancelled_reason;
  NEW.distance_km := OLD.distance_km;
  NEW.elevation_gain_m := OLD.elevation_gain_m;
  NEW.meeting_name := OLD.meeting_name;
  NEW.trace_geojson := OLD.trace_geojson;
  NEW.route := OLD.route;
  NEW.is_demo := OLD.is_demo;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_meeting := OLD.location_meeting;
    NEW.location_end := OLD.location_end;
    NEW.location_objective := OLD.location_objective;
    NEW.objective_name := OLD.objective_name;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.level_max := OLD.level_max;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
    NEW.requires_presence := OLD.requires_presence;
    -- 00516: nor its length (participants' schedules and the conflict rule
    -- depend on it).
    NEW.duration := OLD.duration;
  END IF;

  -- 00467 (audit M1): once the outing has started, its end is fixed — the
  -- presence QR window and the absence finalizer both hang off it.
  IF now() >= OLD.starts_at THEN
    NEW.duration := OLD.duration;
  END IF;

  -- 00441: the locality follows the meeting pin and nothing else — it may
  -- only change in the same UPDATE that moves location_meeting (which the
  -- participant lock above already freezes once someone has joined).
  IF NEW.location_meeting IS NOT DISTINCT FROM OLD.location_meeting THEN
    NEW.meeting_locality := OLD.meeting_locality;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- 00506 (ID-2): an e-mail whose account was deleted while suspended cannot
  -- sign up again (re-registration goes through support).
  IF private.email_is_banned(NEW.email) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  INSERT INTO public.users (id, email, display_name, tier, created_at, updated_at)
  VALUES (NEW.id, NEW.email, generate_random_name(), 'premium', now(), now());
  RETURN NEW;
END;
$$;


--
-- Name: handle_notification_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_notification_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- read_at is the only client-writable column. Everything else
  -- pins to OLD.
  NEW.id := OLD.id;
  NEW.user_id := OLD.user_id;
  NEW.type := OLD.type;
  NEW.title := OLD.title;
  NEW.body := OLD.body;
  NEW.data := OLD.data;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;


--
-- Name: handle_user_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_user_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  -- 00510: WHITELIST, not a pin list — a client may change only its profile
  -- fields; every other column (including any column added later) keeps its
  -- old value unless a SECURITY DEFINER function sets junto.bypass_lock.
  NEW := jsonb_populate_record(OLD, jsonb_build_object(
    'display_name', NEW.display_name,
    'avatar_url', NEW.avatar_url,
    'bio', NEW.bio,
    'sports', NEW.sports,
    'notification_preferences', NEW.notification_preferences,
    'language', NEW.language));
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: join_activity(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_activity(p_activity_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_current_count INTEGER;
  v_hourly_count INTEGER;
  v_result_status TEXT;
  v_existing RECORD;
  v_user_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, visibility, max_participants, title, is_demo, deleted_at
  INTO v_activity
  FROM activities WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00516: once the presence check window of a started outing has passed,
  -- nobody joins any more (they could no longer validate, and could tip a
  -- 2-person outing into the 3+ rule).
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.requires_presence
             AND now() > a.starts_at + INTERVAL '15 minutes') THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;

  -- Demo activities are joinable only by an admin currently in demo mode.
  IF v_activity.is_demo AND NOT demo_content_visible() THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id = v_activity.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00494 (AC-11): the outing of a suspended organiser is hidden everywhere;
  -- it cannot be joined by id either.
  IF private.user_is_suspended(v_activity.creator_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00486 (IX-1): a private outing is joined only through its link (opened
  -- by this account) or an invitation from its organiser — never by id alone.
  IF v_activity.visibility IN ('private_link', 'private_link_approval')
     AND NOT private.private_activity_access(p_activity_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour'
    AND status <> 'invited';  -- 00523: invitations received are not the invitee's joins
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.join_rate_limit'; END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  SELECT id, status, refused_at, left_at INTO v_existing
  FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id;

  -- 00477 (DB-PR-1): test the id, not the record — a RECORD with any NULL field
  -- (refused_at, left_at) is never « IS NOT NULL », which sent every rejoin to
  -- the INSERT branch and a raw unique violation.
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.status = 'removed' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

    IF v_existing.status = 'invited' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE participations
      SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
      WHERE id = v_existing.id;
      SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;
      PERFORM create_notification(
        v_activity.creator_id, 'invitation_accepted',
        coalesce(v_user_name, 'Quelqu''un') || ' a accepté ton invitation',
        '« ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g') || ' »',
        jsonb_build_object('activity_id', p_activity_id,
          'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', regexp_replace(v_activity.title, '<[^>]*>', '', 'g')))
      );
      RETURN 'accepted';
    END IF;

    IF v_existing.status IN ('accepted', 'pending') THEN RAISE EXCEPTION 'junto.already_joined'; END IF;
    -- 00477 (AB-1): a join/leave loop pushed the organiser without limit — the
    -- hourly cap counts rows and a rejoin reuses the same row. 15 min after a
    -- withdrawal before rejoining the same outing.
    IF v_existing.status = 'withdrawn'
       AND v_existing.left_at IS NOT NULL
       AND v_existing.left_at > NOW() - INTERVAL '15 minutes' THEN
      RAISE EXCEPTION 'junto.rejoin_cooldown';
    END IF;
    IF v_existing.status = 'refused'
       AND v_existing.refused_at IS NOT NULL
       AND v_existing.refused_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.refuse_cooldown';
    END IF;

    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET status = v_result_status, left_at = NULL, created_at = now(), refused_at = NULL
    WHERE id = v_existing.id;
  ELSE
    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    INSERT INTO participations (activity_id, user_id, status, created_at)
    VALUES (p_activity_id, v_user_id, v_result_status, now());
  END IF;

  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;

  IF v_result_status = 'pending' THEN
    PERFORM create_notification(
      v_activity.creator_id, 'join_request',
      coalesce(v_user_name, 'Quelqu''un') || ' veut rejoindre ta sortie',
      '« ' || v_activity.title || ' »',
      jsonb_build_object('activity_id', p_activity_id, 'requester_id', v_user_id,  -- 00523
        'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', v_activity.title))
    );
  ELSE
    PERFORM notify_participant_joined(v_activity.creator_id, p_activity_id, v_user_name, v_activity.title);
  END IF;

  RETURN v_result_status;
END;
$$;


--
-- Name: join_channel(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.join_channel(p_conversation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_ch RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Serialize against remove_channel_member so a ban-check + INSERT can't
  -- interleave with a DELETE + ban INSERT (no member+banned state).
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_channel_members'));

  SELECT c.conversation_id, c.closed_at INTO v_ch
  FROM channels c WHERE c.conversation_id = p_conversation_id;
  IF v_ch.conversation_id IS NULL OR v_ch.closed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM channel_bans WHERE conversation_id = p_conversation_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00514 (MS-6): bounded discussions (each message fans out to every member).
  IF (SELECT count(*) FROM conversation_members WHERE conversation_id = p_conversation_id) >= 500 THEN
    RAISE EXCEPTION 'junto.channel_full';
  END IF;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (p_conversation_id, v_user_id, NULL, now())
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$$;


--
-- Name: leave_activity(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.leave_activity(p_activity_id uuid, p_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity RECORD;
  v_user_name TEXT;
  v_is_late BOOLEAN;
  v_reason TEXT;
  v_was_driver BOOLEAN;
  v_passenger RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := NULLIF(left(trim(coalesce(p_reason, '')), 200), '');

  SELECT p.id, p.status, p.transport_type, p.transport_seats, p.accepted_at, p.accepted_via
  INTO v_participation
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id
  FOR UPDATE;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_participation.status NOT IN ('accepted', 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, creator_id, title, requires_presence INTO v_activity
  FROM activities WHERE id = p_activity_id;

  -- Block creator from leaving their own activity (would orphan the activity)
  IF v_user_id = v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00477 (PR-5): only leaving an ACCEPTED place late is a late cancel;
  -- withdrawing a request nobody answered is not.
  v_is_late := v_participation.status = 'accepted'
               AND v_activity.requires_presence
               AND (v_activity.starts_at - INTERVAL '12 hours' < now())
               -- 00517: a REQUEST the organiser accepted inside the 12-hour line
               -- is not a late cancel when left (the trap) — a place one took
               -- oneself, at any time, still is.
               AND NOT (v_participation.accepted_via = 'organiser'
                        AND v_participation.accepted_at >= v_activity.starts_at - INTERVAL '12 hours')
               -- 00516: nobody is penalised for leaving a suspended organiser's outing.
               AND NOT private.user_is_suspended(v_activity.creator_id);


  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn',
      left_at = now(),
      left_reason = v_reason,
      transport_type = NULL,
      transport_seats = NULL,
      transport_from_name = NULL,
      transport_departs_at = NULL,
      transport_from_lat = NULL, transport_from_lng = NULL, transport_from_locality = NULL  -- 00522 (F11)
  WHERE id = v_participation.id;

  -- 00478 (PR-4): the late cancel goes to its own ledger, which no rejoin,
  -- re-invitation, declined invitation or block cascade can erase. A new late
  -- cancel on the same outing re-arms a previous waiver.
  IF v_is_late THEN
    INSERT INTO late_cancels (user_id, activity_id, at, waived)
    VALUES (v_user_id, p_activity_id, now(), false)
    ON CONFLICT (user_id, activity_id) DO UPDATE SET at = now(), waived = false;
  END IF;

  PERFORM recalculate_reliability_score(v_user_id);

  SELECT display_name INTO v_user_name FROM users WHERE id = v_user_id;
  -- 00477/00478 (AB-1): at most one notification of EACH type per participant
  -- and outing per 24 h — an early leave never hides a later late one.
  IF NOT EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_activity.creator_id
      AND type = CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END
      AND data->>'participation_id' = v_participation.id::text
      AND created_at > now() - INTERVAL '24 hours'
  ) THEN
  PERFORM create_notification(
    v_activity.creator_id,
    CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END,
    coalesce(v_user_name, 'Quelqu''un') || ' a quitté « ' || v_activity.title || ' »',
    CASE
      WHEN v_is_late THEN 'Départ tardif — pénalité de fiabilité appliquée, tu peux la lever depuis la sortie.'
      ELSE coalesce(v_reason, '')
    END,
    jsonb_build_object('activity_id', p_activity_id, 'participation_id', v_participation.id, 'late', v_is_late,
      'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', v_activity.title, 'reason', coalesce(v_reason, '')))
  );
  END IF;

  -- 00523: carpool links (as driver or passenger) are released by
  -- trg_participations_seat_cleanup on the status change above.
END;
$$;


--
-- Name: leave_channel(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.leave_channel(p_conversation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM channels WHERE conversation_id = p_conversation_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = v_user_id;
END;
$$;


--
-- Name: leave_group(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.leave_group(p_conversation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_left INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conversation_id AND type = 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Serialize with adds/other leavers so the empty-cleanup can't race.
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_group_members'));

  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = v_user_id;
  -- 00499 (AB-12): remember the departure (others cannot re-add for 30 days).
  INSERT INTO conversation_departures (conversation_id, user_id, at)
  VALUES (p_conversation_id, v_user_id, now())
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET at = now();

  SELECT count(*) INTO v_left FROM conversation_members
  WHERE conversation_id = p_conversation_id;
  IF v_left = 0 THEN
    DELETE FROM conversations WHERE id = p_conversation_id;
  END IF;
END;
$$;


--
-- Name: log_admin_action(uuid, text, text, uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_admin_action(p_admin uuid, p_action text, p_target_type text, p_target_id uuid, p_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT NULL::jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO admin_actions (admin_id, action, target_type, target_id, reason, metadata)
  VALUES (p_admin, p_action, p_target_type, p_target_id, p_reason, p_metadata);
END;
$$;


--
-- Name: map_ping(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.map_ping(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_sent INT;
BEGIN
  -- Throttle: at most one signal per outing every 15 s. UPDATE first so the
  -- row is locked only when the window has elapsed (00480 — the previous
  -- INSERT … ON CONFLICT … WHERE locked it on every write, a new deadlock
  -- coupling between unrelated transactions).
  UPDATE map_broadcasts SET at = now()
  WHERE activity_id = p_activity_id AND at < now() - INTERVAL '15 seconds';
  GET DIAGNOSTICS v_sent = ROW_COUNT;
  IF v_sent = 0 THEN
    INSERT INTO map_broadcasts (activity_id, at) VALUES (p_activity_id, now())
    ON CONFLICT (activity_id) DO NOTHING;
    GET DIAGNOSTICS v_sent = ROW_COUNT;
  END IF;
  IF v_sent = 0 THEN RETURN; END IF;
  BEGIN
    PERFORM realtime.send('{}'::jsonb, 'map', 'map', true);
  EXCEPTION WHEN OTHERS THEN NULL; -- never fail the user's write for a ping
  END;
END;
$$;


--
-- Name: mark_conversation_read(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_conversation_read(p_conversation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE conversation_members
  SET last_read_at = GREATEST(COALESCE(last_read_at, 'epoch'::timestamptz), now())
  WHERE conversation_id = p_conversation_id AND user_id = auth.uid();
  -- Not a member → zero rows → silent no-op (own state only, no oracle).
END;
$$;


--
-- Name: mark_tutorial_seen(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_tutorial_seen() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tutorial_seen_at = now() WHERE id = v_user_id;
END;
$$;


--
-- Name: messages_block_closed_channel(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.messages_block_closed_channel() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM channels WHERE conversation_id = NEW.conversation_id AND closed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: messages_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.messages_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.conversation_id := OLD.conversation_id;
  NEW.sender_id := OLD.sender_id;
  NEW.reply_to_message_id := OLD.reply_to_message_id;
  NEW.created_at := OLD.created_at;
  NEW.metadata := OLD.metadata;
  RETURN NEW;
END;
$$;


--
-- Name: moderate_report(uuid, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.moderate_report(p_report_id uuid, p_action text, p_admin_note text DEFAULT NULL::text, p_suspend_user_id uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_report RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_action NOT IN ('dismissed', 'actioned') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status, target_type, target_id INTO v_report FROM reports WHERE id = p_report_id;
  IF v_report IS NULL OR v_report.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE reports
  SET status = p_action, admin_note = p_admin_note, resolved_at = now()
  WHERE id = p_report_id;

  IF p_suspend_user_id IS NOT NULL AND p_action = 'actioned' THEN
    -- 00513 (ID-4): only the person the report is about can be suspended
    -- from it, through the full suspension path (reason, booking
    -- cancellations, notifications, log).
    IF p_suspend_user_id IS DISTINCT FROM (
      SELECT CASE v_report.target_type
        WHEN 'user' THEN v_report.target_id
        WHEN 'message' THEN (SELECT m.sender_id FROM messages m WHERE m.id = v_report.target_id)
        WHEN 'activity' THEN (SELECT a.creator_id FROM activities a WHERE a.id = v_report.target_id)
        WHEN 'pro_review' THEN (SELECT r.reviewer_id FROM pro_reviews r WHERE r.id = v_report.target_id)
        WHEN 'offering_review' THEN (SELECT r.reviewer_id FROM offering_reviews r WHERE r.id = v_report.target_id)
        WHEN 'group' THEN (SELECT c.created_by FROM conversations c WHERE c.id = v_report.target_id)
        WHEN 'channel' THEN (SELECT ch.created_by FROM channels ch WHERE ch.conversation_id = v_report.target_id)
      END) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    PERFORM admin_suspend_user(p_suspend_user_id, coalesce(nullif(trim(p_admin_note), ''), 'Signalement n° ' || p_report_id::text));
  END IF;

  PERFORM log_admin_action(
    v_user_id, 'moderate_report', 'report', p_report_id, p_admin_note,
    jsonb_build_object('action', p_action, 'suspended_user_id', p_suspend_user_id)
  );
END;
$$;


--
-- Name: notify_creator_qr_reminder(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_creator_qr_reminder(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity RECORD;
BEGIN
  SELECT id, creator_id, title, status, starts_at, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN RETURN; END IF;

  IF now() < v_activity.starts_at - INTERVAL '10 minutes' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_activity.creator_id
      AND type = 'qr_create_reminder'
      AND (data->>'activity_id')::uuid = p_activity_id
  ) THEN RETURN; END IF;

  BEGIN
    PERFORM create_notification(
      v_activity.creator_id,
      'qr_create_reminder',
      v_activity.title,
      'Génère le QR de présence pour tes participants',
      jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
    );
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;
END;
$$;


--
-- Name: notify_participant_joined(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_participant_joined(p_creator_id uuid, p_activity_id uuid, p_joiner_name text, p_activity_title text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $_$
DECLARE
  v_existing RECORD;
  v_count INTEGER;
  v_recent_names JSONB;
  v_clean_name TEXT;
  v_clean_title TEXT;
  v_body TEXT;
  v_secret TEXT;
  v_names_arr TEXT[];
BEGIN
  v_clean_name := sanitize_notif_text(coalesce(p_joiner_name, 'Quelqu''un'));
  v_clean_title := sanitize_notif_text(coalesce(p_activity_title, ''));

  SELECT id, data INTO v_existing
  FROM notifications
  WHERE user_id = p_creator_id
    AND type = 'participant_joined'
    AND (data->>'activity_id')::uuid = p_activity_id
    AND read_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_existing IS NULL THEN
    PERFORM create_notification(
      p_creator_id,
      'participant_joined',
      'Nouveau participant',
      v_clean_name || ' a rejoint « ' || v_clean_title || ' »',
      jsonb_build_object(
        'activity_id', p_activity_id,
        'count', 1,
        'recent_names', jsonb_build_array(v_clean_name),
        'params', jsonb_build_object('name', v_clean_name, 'title', v_clean_title)
      )
    );
    RETURN;
  END IF;

  v_count := COALESCE((v_existing.data->>'count')::int, 1) + 1;
  v_recent_names := COALESCE(v_existing.data->'recent_names', '[]'::jsonb)
                    || jsonb_build_array(v_clean_name);
  -- Keep at most last 3 names
  IF jsonb_array_length(v_recent_names) > 3 THEN
    v_recent_names := jsonb_path_query_array(v_recent_names, '$[1 to last]');
  END IF;

  SELECT array_agg(value) INTO v_names_arr
  FROM jsonb_array_elements_text(v_recent_names) WITH ORDINALITY;

  IF v_count = 2 THEN
    v_body := v_names_arr[1] || ' et ' || v_names_arr[2] || ' ont rejoint ' || v_clean_title;
  ELSE
    v_body := v_names_arr[array_upper(v_names_arr, 1)]
              || ' et ' || (v_count - 1)::text || ' autres ont rejoint ' || v_clean_title;
  END IF;

  UPDATE notifications
  SET body = v_body,
      data = jsonb_set(
        jsonb_set(v_existing.data, '{count}', to_jsonb(v_count)),
        '{recent_names}', v_recent_names
      ),
      created_at = now(),
      read_at = NULL
  WHERE id = v_existing.id;

  -- AFTER INSERT trigger doesn't fire on UPDATE, so push manually with collapseId
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL AND private.project_url() IS NOT NULL THEN  -- 00524
    PERFORM net.http_post(
      url := private.project_url() || '/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-junto-push-secret', v_secret
      ),
      body := jsonb_build_object(
        'user_id', p_creator_id,
        'title', 'Nouveau participant',
        'body', v_body,
        'data', jsonb_build_object(
          'activity_id', p_activity_id,
          'count', v_count,
          'type', 'participant_joined'
        ),
        'collapseId', 'joined-' || p_activity_id::text
      )
    );
  END IF;
END;
$_$;


--
-- Name: notify_presence_confirmed(uuid, uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_presence_confirmed(p_user_id uuid, p_activity_id uuid, p_skip_push boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_title TEXT;
  v_data JSONB;
BEGIN
  SELECT title INTO v_title FROM activities WHERE id = p_activity_id;
  IF v_title IS NULL THEN RETURN; END IF;

  v_data := jsonb_build_object('activity_id', p_activity_id);
  IF p_skip_push THEN
    v_data := v_data || jsonb_build_object('skip_push', TRUE);
  END IF;

  BEGIN
    PERFORM create_notification(
      p_user_id,
      'presence_confirmed',
      'Présence confirmée',
      'Ta présence est validée pour « ' || v_title || ' »',
      coalesce(v_data, '{}'::jsonb) || jsonb_build_object('params', jsonb_build_object('title', v_title))
    );
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END;
$$;


--
-- Name: notify_presence_pre_warning(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_presence_pre_warning(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, requires_presence, creator_id
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'published' THEN RETURN; END IF;
  IF now() < v_activity.starts_at - INTERVAL '2 hours' OR now() >= v_activity.starts_at THEN
    RETURN;
  END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      -- 00432 : le créateur n'a AUCUN chemin d'auto-validation (invariant
      -- 00292). Lui dire « prépare-toi à valider ta présence » était une
      -- consigne inexécutable, et la fiche d'activité ne mentionnait même pas
      -- la présence pour lui à ce moment-là. Son action à lui, c'est
      -- qr_create_reminder à T-10min.
      AND p.user_id != v_activity.creator_id
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning',
        v_activity.title,
        'Démarre dans 2 h — prépare-toi à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;


--
-- Name: notify_presence_pre_warning_10min(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_presence_pre_warning_10min(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN RETURN; END IF;

  IF now() < v_activity.starts_at - INTERVAL '10 minutes' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      -- 00432 : le créateur n'a AUCUN chemin d'auto-validation (invariant
      -- 00292). Lui dire « prépare-toi à valider ta présence » était une
      -- consigne inexécutable, et la fiche d'activité ne mentionnait même pas
      -- la présence pour lui à ce moment-là. Son action à lui, c'est
      -- qr_create_reminder à T-10min.
      AND p.user_id != v_activity.creator_id
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning_10min'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning_10min',
        v_activity.title,
        'Démarre dans 10 min — pense à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;


--
-- Name: notify_presence_validate_overdue(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_presence_validate_overdue(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_accepted_count INTEGER;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '1 hour' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '1 hour 30 minutes' THEN RETURN; END IF;

  -- 00432 : le seuil passe de 3 à 2. À 2 participants, le QR est le SEUL
  -- recours (le témoignage entre pairs exige 3) — c'était donc la
  -- configuration qui avait le plus besoin d'être relancée, et la seule qui ne
  -- recevait RIEN entre T+15min et fin+3h. La copy est choisie selon le
  -- nombre : à 2, elle ne parle que du QR et ne menace d'aucune absence
  -- (close_presence_window_for remet à NULL sans pénalité à 2).
  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_accepted_count < 2 THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND p.user_id != v_activity.creator_id   -- Rule B: creator not nagged
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_overdue'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_overdue',
        'Présence non validée',
        -- 00450 : ≤ 120 caractères (audit 2026-10-15). À deux, pas d'absence
        -- possible : la sortie n'est simplement pas comptée (00327/00434).
        CASE WHEN v_accepted_count >= 3 THEN
          'Scanne le QR de l''organisateur avant 3 h après la fin de « ' || v_activity.title || ' », sinon ce sera une absence.'
        ELSE
          'Scanne le QR de l''organisateur avant 3 h après la fin de « ' || v_activity.title || ' », sinon la sortie ne sera pas comptée.'
        END,
        jsonb_build_object('activity_id', p_activity_id,
          'variant', CASE WHEN v_accepted_count >= 3 THEN NULL ELSE 'duo' END,
          'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;


--
-- Name: notify_presence_validate_warning(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_presence_validate_warning(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_accepted_count INTEGER;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  IF now() < v_activity.starts_at + (v_activity.duration / 2) THEN RETURN; END IF;
  IF now() >= v_activity.starts_at + v_activity.duration THEN RETURN; END IF;

  -- Peer testimony (and thus the self-validate nag) only applies from 3.
  -- 00432 : le seuil passe de 3 à 2. À 2 participants, le QR est le SEUL
  -- recours (le témoignage entre pairs exige 3) — c'était donc la
  -- configuration qui avait le plus besoin d'être relancée, et la seule qui ne
  -- recevait RIEN entre T+15min et fin+3h. La copy est choisie selon le
  -- nombre : à 2, elle ne parle que du QR et ne menace d'aucune absence
  -- (close_presence_window_for remet à NULL sans pénalité à 2).
  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_accepted_count < 2 THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND p.user_id != v_activity.creator_id   -- Rule B: creator not nagged
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_warning',
        'Valide ta présence',
        -- 00450 : une seule phrase, ≤ 120 caractères (audit 2026-10-15) — la
        -- distinction 3+/2 ne changeait que des détails que la push tronquait.
        'Scanne le QR de l''organisateur — valable jusqu''à 3 h après la fin de « ' || v_activity.title || ' ».',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;


--
-- Name: notify_rate_participants(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_rate_participants(p_activity_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, deleted_at, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.deleted_at IS NOT NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  -- 00497 (Scott): no vote request on an outing without presence check.
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  -- La fenêtre de vote réelle : fin+15 min → fin+24 h. Avant : silence
  -- (le prochain balayage émettra) ; après : plus de sens, on n'émet jamais.
  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  -- Gate solo (00265) : personne à évaluer en dessous de 2 acceptés.
  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'rate_participants'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'rate_participants',
        'Évalue tes co-participants',
        '« ' || v_activity.title || ' » — dis-nous comment ça s''est passé.',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;


--
-- Name: notify_review_received(uuid, text, smallint, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_review_received(p_pro_id uuid, p_reviewer_name text, p_rating smallint, p_target_label text, p_data jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_clean_name TEXT;
  v_clean_label TEXT;
BEGIN
  -- 00501 (PO-1 / PO-11): no repeat — one « new review » per reviewer and
  -- pro a day (publish / delete loops), one « review updated » per review a day.
  IF p_data ? 'reviewer_id' AND EXISTS (
    SELECT 1 FROM notifications n
    WHERE n.user_id = p_pro_id AND n.type = 'review_received'
      AND n.data->>'reviewer_id' = p_data->>'reviewer_id'
      AND coalesce(n.data->>'variant', '') = coalesce(p_data->>'variant', '')
      AND (p_data->>'variant' IS NULL OR n.data->>'review_id' = p_data->>'review_id')
      -- 00505: per target — a review of the pro page and one of an offering
      -- are two different notifications.
      AND coalesce(n.data->>'offering_id', '') = coalesce(p_data->>'offering_id', '')
      AND n.created_at > now() - INTERVAL '24 hours'
  ) THEN RETURN; END IF;

  v_clean_name := sanitize_notif_text(coalesce(p_reviewer_name, 'Quelqu''un'));
  v_clean_label := sanitize_notif_text(coalesce(p_target_label, ''));
  PERFORM create_notification(
    p_pro_id,
    'review_received',
    CASE WHEN p_data->>'variant' = 'updated' THEN 'Avis modifié' ELSE 'Nouvel avis' END,
    CASE WHEN p_data->>'variant' = 'updated'
      THEN v_clean_name || ' a modifié son avis (' || p_rating || '★) sur ' || v_clean_label
      ELSE v_clean_name || ' a laissé un avis (' || p_rating || '★) sur ' || v_clean_label END,
    coalesce(p_data, '{}'::jsonb) || jsonb_build_object('params', jsonb_build_object('name', v_clean_name, 'rating', p_rating, 'label', v_clean_label))
  );
END;
$$;


--
-- Name: notify_review_reply(uuid, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_review_reply(p_reviewer_id uuid, p_pro_name text, p_target_label text, p_data jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_clean_name TEXT;
  v_clean_label TEXT;
BEGIN
  -- 00501 (PO-2): one « reply » notification per review (erase / rewrite
  -- loops do not ping the author again).
  IF EXISTS (SELECT 1 FROM notifications n
             WHERE n.user_id = p_reviewer_id AND n.type = 'review_reply'
               AND n.data->>'review_id' = p_data->>'review_id') THEN
    RETURN;
  END IF;

  v_clean_name := sanitize_notif_text(coalesce(p_pro_name, 'Le pro'));
  v_clean_label := sanitize_notif_text(coalesce(p_target_label, ''));
  PERFORM create_notification(
    p_reviewer_id,
    'review_reply',
    'Réponse à ton avis',
    v_clean_name || ' a répondu à ton avis sur ' || v_clean_label,
    coalesce(p_data, '{}'::jsonb) || jsonb_build_object('params', jsonb_build_object('name', v_clean_name, 'label', v_clean_label))
  );
END;
$$;


--
-- Name: offering_reviews_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.offering_reviews_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.offering_id := OLD.offering_id;
  NEW.reviewer_id := OLD.reviewer_id;
  NEW.pro_reply := OLD.pro_reply;
  NEW.pro_reply_at := OLD.pro_reply_at;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;


--
-- Name: on_activity_completed_award_badges(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.on_activity_completed_award_badges() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_participant RECORD;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted'
    LOOP
      -- Badge progression always (a solo creator still created an outing)
      PERFORM award_badge_progression(v_participant.user_id, FALSE);
    END LOOP;
    -- rate_participants n'est PLUS émis ici (00427) : la fenêtre de vote
    -- n'ouvre qu'à fin+15 min — l'émission vit dans notify_rate_participants,
    -- appelée par les balayages une fois la fenêtre réellement ouverte.
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: on_activity_finished_expire_seat_requests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.on_activity_finished_expire_seat_requests() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_request RECORD;
BEGIN
  IF NEW.status NOT IN ('completed', 'cancelled', 'expired') THEN
    RETURN NEW;
  END IF;
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Cleanup only — flip pending requests to expired so the UI no longer
  -- shows them as pending. No notification emission (00157 decision);
  -- the activity-status transition reaches the user through other
  -- channels.
  FOR v_request IN
    SELECT id
    FROM seat_requests
    WHERE activity_id = NEW.id AND status = 'pending'
    FOR UPDATE
  LOOP
    UPDATE seat_requests SET status = 'expired' WHERE id = v_request.id;
  END LOOP;

  -- Same treatment for participation requests (mig 00263 — they were
  -- the forgotten sibling and ghosted the "En attente" tab forever).
  UPDATE participations
  SET status = 'expired'
  WHERE activity_id = NEW.id AND status = 'pending';

  RETURN NEW;
END;
$$;


--
-- Name: pro_availabilities_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_availabilities_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN RETURN NEW; END IF;
  NEW.id := OLD.id;
  NEW.pro_id := OLD.pro_id;
  NEW.day := OLD.day;
  NEW.period := OLD.period;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;


--
-- Name: pro_community_photos_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_community_photos_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.pro_id := OLD.pro_id;
  NEW.contributor_id := OLD.contributor_id;
  NEW.photo_url := OLD.photo_url;
  NEW.review_id := OLD.review_id;
  NEW.offering_id := OLD.offering_id;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;


--
-- Name: pro_offering_photos_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_offering_photos_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.offering_id := OLD.offering_id;
  NEW.photo_url := OLD.photo_url;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;


--
-- Name: pro_offerings_require_approved(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_offerings_require_approved() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = NEW.pro_id AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: pro_offerings_touch_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_offerings_touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: pro_offerings_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_offerings_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.pro_id := OLD.pro_id;
  NEW.created_at := OLD.created_at;
  NEW.is_demo := OLD.is_demo;
  RETURN NEW;
END;
$$;


--
-- Name: pro_profile_photos_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_profile_photos_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.pro_id := OLD.pro_id;
  NEW.photo_url := OLD.photo_url;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;


--
-- Name: pro_profiles_touch_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_profiles_touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: pro_profiles_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_profiles_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.user_id := OLD.user_id;
  NEW.created_at := OLD.created_at;
  NEW.last_location_change_at := OLD.last_location_change_at;
  NEW.status := OLD.status;
  NEW.company_name := OLD.company_name;
  NEW.real_name := OLD.real_name;
  NEW.rejection_reason := OLD.rejection_reason;
  NEW.reviewed_at := OLD.reviewed_at;
  NEW.reviewed_by := OLD.reviewed_by;
  NEW.is_demo := OLD.is_demo;
  RETURN NEW;
END;
$$;


--
-- Name: pro_reviews_require_approved(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_reviews_require_approved() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = NEW.pro_id AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: pro_reviews_whitelist_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_reviews_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.pro_id := OLD.pro_id;
  NEW.reviewer_id := OLD.reviewer_id;
  NEW.pro_reply := OLD.pro_reply;
  NEW.pro_reply_at := OLD.pro_reply_at;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;


--
-- Name: purge_booking_participant_info(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purge_booking_participant_info() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET participant_info = NULL
  WHERE participant_info IS NOT NULL AND day < private.today_paris() - 30;
  -- 00518 (L5): third-party contact typed by the pro, and the client's free
  -- text, are not kept forever either.
  UPDATE bookings SET manual_phone = NULL, message = NULL
  WHERE (manual_phone IS NOT NULL OR message IS NOT NULL) AND day < private.today_paris() - 30;
END;
$$;


--
-- Name: purge_contact_removal_archive(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purge_contact_removal_archive() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  DELETE FROM contact_removal_archive WHERE removed_at < now() - INTERVAL '90 days';
$$;


--
-- Name: purge_old_notifications(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purge_old_notifications() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  DELETE FROM notifications
  WHERE created_at < now() - INTERVAL '7 days'
    AND (
      read_at IS NOT NULL
      OR type NOT IN (
        'join_request',
        'seat_request',
        'contact_request',
        'peer_review_closing'
      )
    );
$$;


--
-- Name: purge_throttle_tables(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purge_throttle_tables() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  DELETE FROM map_broadcasts WHERE at < now() - INTERVAL '1 day';
  DELETE FROM rate_events WHERE at < now() - INTERVAL '2 days';
  DELETE FROM snap_trail_calls WHERE called_at < now() - INTERVAL '1 day';  -- 00522
$$;


--
-- Name: push_notification_to_device(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.push_notification_to_device() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_should_push BOOLEAN := TRUE;
  v_collapse_id TEXT;
  v_activity_starts TIMESTAMPTZ;
  v_changes JSONB;
  v_secret TEXT;
  v_activity_id TEXT;
  v_presence_count INT;
  v_title TEXT := NEW.title;
  v_forwarded_data JSONB;
  v_allowed_keys TEXT[] := ARRAY[
    'activity_id',
    'conversation_id',
    'seat_request_id',
    'driver_id',
    'requester_id',
    'from_user_id',
    -- 00472 (audit M7): send-push composes the text in the recipient's
    -- language from these (lots A-F, 00447-00450). Display names, titles,
    -- dates only — the same facts the French body already carries.
    'params',
    'variant',
    -- 00523: routing keys for bookings, reviews and pro pages (ids only).
    'by',
    'pro_id',
    'offering_id',
    'booking_id'
  ];
BEGIN
  IF (NEW.data ? 'skip_push') AND ((NEW.data->>'skip_push')::boolean IS TRUE) THEN
    RETURN NEW;
  END IF;

  CASE NEW.type
    WHEN 'rate_participants', 'request_refused' THEN
      v_should_push := FALSE;

    WHEN 'participant_joined' THEN
      v_collapse_id := 'joined-' || (NEW.data->>'activity_id');

    WHEN 'badge_unlocked' THEN
      v_collapse_id := 'badge-' || NEW.user_id::text
                       || '-' || to_char(NEW.created_at, 'YYYY-MM-DD');

    WHEN 'presence_pre_warning', 'presence_validate_now', 'presence_validate_warning' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
        SELECT count(*) INTO v_presence_count
        FROM notifications
        WHERE user_id = NEW.user_id
          AND type IN ('presence_pre_warning', 'presence_validate_now', 'presence_validate_warning')
          AND (data->>'activity_id') = v_activity_id
          AND created_at > NOW() - INTERVAL '24 hours';
        IF v_presence_count > 1 THEN
          v_title := v_title || ' (×' || v_presence_count || ')';
        END IF;
      END IF;

    WHEN 'presence_confirmed' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
      END IF;

    WHEN 'activity_cancelled' THEN
      SELECT starts_at INTO v_activity_starts
      FROM activities WHERE id = (NEW.data->>'activity_id')::uuid;
      v_should_push := v_activity_starts IS NULL
                       OR (v_activity_starts - now() < INTERVAL '48 hours');

    WHEN 'activity_updated' THEN
      v_changes := NEW.data->'changes';
      v_should_push := v_changes IS NOT NULL AND (
        v_changes ? 'starts_at' OR v_changes ? 'duration'
        OR v_changes ? 'location_meeting'
        OR v_changes ? 'max_participants' OR v_changes ? 'level'
        OR v_changes ? 'trace'  -- 00475: route changed after sign-up
      );

    ELSE
      v_should_push := TRUE;
  END CASE;

  IF NOT v_should_push THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL OR private.project_url() IS NULL THEN RETURN NEW; END IF;  -- 00524

  -- Strict allow-list — anything not in v_allowed_keys is dropped
  -- before the payload leaves the DB. `type` is always added (the
  -- client routes on it).
  SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb)
    INTO v_forwarded_data
  FROM jsonb_each(COALESCE(NEW.data, '{}'::jsonb))
  WHERE key = ANY(v_allowed_keys);

  v_forwarded_data := v_forwarded_data || jsonb_build_object('type', NEW.type);

  PERFORM net.http_post(
    url := private.project_url() || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-junto-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', v_title,
      'body', NEW.body,
      'data', v_forwarded_data,
      'collapseId', v_collapse_id
    )
  );

  RETURN NEW;
END;
$$;


--
-- Name: recalc_creator_on_participant_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalc_creator_on_participant_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_creator_id UUID;
  v_other_count INTEGER;
BEGIN
  SELECT creator_id INTO v_creator_id
  FROM activities WHERE id = COALESCE(NEW.activity_id, OLD.activity_id);
  IF v_creator_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  -- If the creator hasn't recorded a presence on this activity, nothing to do.
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = COALESCE(NEW.activity_id, OLD.activity_id)
      AND user_id = v_creator_id
      AND confirmed_present IS NOT NULL
  ) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Recalc the creator's score so the recorded validation flips to counted
  -- (or back to ignored) based on the new participant pool.
  PERFORM recalculate_reliability_score(v_creator_id);
  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: recalculate_reliability_score(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalculate_reliability_score(p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  -- 00435 : constante bayésienne 3 → 1. Avec 3, les scores étaient écrasés
  -- vers le haut au point que le signal ne discriminait plus : quelqu'un qui
  -- s'inscrit à une seule sortie et n'y va pas affichait (3+0)/(3+1) = 75 %,
  -- soit « Bonne » — le MÊME palier qu'un habitué irréprochable — et il fallait
  -- quatre défections consécutives pour tomber en « Faible ».
  -- Avec 1 : 1 absence sur 1 → 50 % (« Correcte »), 2 sur 2 → 33 % (« Faible »),
  -- et un historique sain protège toujours (10 présences + 1 absence → 92 %,
  -- « Excellente »). Un nouveau compte reste à NULL (palier « nouveau ») jusqu'à
  -- sa première sortie terminée, donc on n'affiche jamais 100 % à quelqu'un qui
  -- n'a rien fait.
  v_prior CONSTANT INTEGER := 1;
  v_total INTEGER;
  v_present INTEGER;
  v_late_cancels INTEGER;
  v_score FLOAT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('reliability_' || p_user_id::text));

  -- Validations on activities where the user is the creator AND no other
  -- accepted participant exists are recorded but don't count toward
  -- reliability — solo activities can't be peer-witnessed. The next recalc
  -- after a participant joins picks them up automatically.
  SELECT count(*) INTO v_total
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present IS NOT NULL
    AND a.deleted_at IS NULL AND a.status <> 'cancelled'  -- 00495 (PR-10)
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  SELECT count(*) INTO v_present
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present = true
    AND a.deleted_at IS NULL AND a.status <> 'cancelled'  -- 00495 (PR-10)
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  -- 00478 (PR-4): late cancels come from the late_cancels ledger. One per
  -- outing; not counted once the person has a presence verdict on that outing
  -- (no double count after a rejoin), nor on outings cancelled or removed.
  SELECT count(*) INTO v_late_cancels
  FROM late_cancels lc
  JOIN activities a ON a.id = lc.activity_id
  WHERE lc.user_id = p_user_id
    AND lc.waived = FALSE
    AND a.requires_presence = TRUE
    AND a.status <> 'cancelled'
    AND a.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM participations p
      WHERE p.activity_id = lc.activity_id AND p.user_id = lc.user_id
        AND p.confirmed_present IS NOT NULL
    );

  v_score := ROUND(
    (((v_prior + v_present)::float / (v_prior + v_total + v_late_cancels)::float) * 100)::numeric,
    1
  )::float;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$$;


--
-- Name: refuse_participation(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refuse_participation(p_participation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.activity_id, a.creator_id, a.status AS activity_status, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = v_participation.activity_id AND a.deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';  -- 00516: moderated outing frozen
  END IF;
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_participation.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'refused', refused_at = now()
  WHERE id = p_participation_id;

  PERFORM create_notification(
    v_participation.user_id,
    'request_refused',
    'Demande refusée',
    '« ' || v_participation.title || ' »',
    jsonb_build_object('activity_id', v_participation.activity_id,
      'params', jsonb_build_object('title', v_participation.title))
  );
END;
$$;


--
-- Name: register_as_pro(text, text, text, text, text, text, text, text, text, text, double precision, double precision, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_as_pro(p_display_name text, p_company_name text, p_real_name text, p_tagline text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_instagram text DEFAULT NULL::text, p_facebook text DEFAULT NULL::text, p_primary_lng double precision DEFAULT NULL::double precision, p_primary_lat double precision DEFAULT NULL::double precision, p_primary_location_name text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $_$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_clean_tagline TEXT;
  v_clean_description TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Required-field validation
  IF p_display_name IS NULL OR char_length(trim(p_display_name)) < 1 OR char_length(p_display_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_company_name IS NULL OR char_length(trim(p_company_name)) < 2 OR char_length(p_company_name) > 120 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NULL OR char_length(trim(p_real_name)) < 2 OR char_length(p_real_name) > 120 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_primary_lng IS NULL OR p_primary_lat IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_primary_location_name IS NULL OR char_length(trim(p_primary_location_name)) < 1 OR char_length(p_primary_location_name) > 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: same link rules as the table checks, with a readable error.
  IF p_website IS NOT NULL AND p_website !~* '^https?://[^[:space:]]+$' THEN RAISE EXCEPTION 'junto.pro_website_invalid'; END IF;
  IF (p_facebook IS NOT NULL AND p_facebook ~* '^[a-z][a-z0-9+.-]*:' AND p_facebook !~* '^https?://')
     OR (p_instagram IS NOT NULL AND p_instagram ~* '^[a-z][a-z0-9+.-]*:' AND p_instagram !~* '^https?://') THEN
    RAISE EXCEPTION 'junto.pro_website_invalid';
  END IF;

  v_clean_name := regexp_replace(trim(p_display_name), '<[^>]*>', '', 'g');
  v_clean_tagline := CASE WHEN p_tagline IS NOT NULL AND char_length(trim(p_tagline)) > 0
                          THEN regexp_replace(trim(p_tagline), '<[^>]*>', '', 'g') ELSE NULL END;
  v_clean_description := CASE WHEN p_description IS NOT NULL AND char_length(trim(p_description)) > 0
                              THEN regexp_replace(trim(p_description), '<[^>]*>', '', 'g') ELSE NULL END;

  INSERT INTO pro_profiles (
    user_id, display_name, company_name, real_name, status, tagline, description,
    website, email, phone, instagram, facebook,
    primary_lng, primary_lat, primary_location, primary_location_name
  )
  VALUES (
    v_user_id, v_clean_name,
    regexp_replace(trim(p_company_name), '<[^>]*>', '', 'g'),
    regexp_replace(trim(p_real_name), '<[^>]*>', '', 'g'),
    'pending', v_clean_tagline, v_clean_description,
    p_website, p_email, p_phone, p_instagram, p_facebook,
    p_primary_lng, p_primary_lat,
    ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography,
    trim(p_primary_location_name)
  );
  -- NB: tier stays 'free' — approve_pro flips it to 'pro'.
END;
$_$;


--
-- Name: register_push_token(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_push_token(p_token text, p_device_id text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_token IS NULL OR char_length(p_token) < 20 OR char_length(p_token) > 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_token !~ '^Exp(o|onent)PushToken\[.+\]$' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM push_tokens WHERE token = p_token AND user_id != v_user_id;

  IF p_device_id IS NOT NULL THEN
    DELETE FROM push_tokens
      WHERE user_id = v_user_id
        AND device_id = p_device_id
        AND token != p_token;
    INSERT INTO push_tokens (user_id, token, device_id)
      VALUES (v_user_id, p_token, p_device_id)
      ON CONFLICT (user_id, token)
      DO UPDATE SET device_id = EXCLUDED.device_id, created_at = now();  -- 00519: last use
  ELSE
    INSERT INTO push_tokens (user_id, token)
      VALUES (v_user_id, p_token)
      ON CONFLICT (user_id, token) DO UPDATE SET created_at = now();  -- 00519: last use
  END IF;

  -- 00514 (AB-11): at most 10 devices per account (oldest dropped).
  DELETE FROM push_tokens WHERE user_id = v_user_id AND token NOT IN (
    SELECT token FROM push_tokens WHERE user_id = v_user_id ORDER BY created_at DESC LIMIT 10);

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE push_token = p_token AND id != v_user_id;
  UPDATE users SET push_token = p_token WHERE id = v_user_id;
END;
$_$;


--
-- Name: reject_pro(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_pro(p_user_id uuid, p_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_user_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_reason IS NOT NULL AND char_length(p_reason) > 500 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles
    SET status = 'rejected', rejection_reason = NULLIF(trim(coalesce(p_reason, '')), ''),
        reviewed_at = now(), reviewed_by = v_admin
    WHERE user_id = p_user_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (p_user_id, 'pro_rejected', 'Demande pro refusée',
          coalesce(NULLIF(trim(coalesce(p_reason, '')), ''), 'Ta demande de page pro n''a pas été validée. Corrige tes informations et renvoie-la.'),
          jsonb_build_object('pro_id', p_user_id,
            'variant', CASE WHEN NULLIF(trim(coalesce(p_reason, '')), '') IS NULL THEN NULL ELSE 'reason' END,
            'params', jsonb_build_object('reason', coalesce(NULLIF(trim(coalesce(p_reason, '')), ''), ''))));

  PERFORM log_admin_action(v_admin, 'reject_pro', 'pro_profile', p_user_id, NULLIF(trim(coalesce(p_reason, '')), ''), NULL);
END;
$$;


--
-- Name: remove_channel_member(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_channel_member(p_conversation_id uuid, p_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF v_creator IS NULL OR v_creator != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_user_id IS NULL OR p_user_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Serialize against join_channel (see above).
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_channel_members'));

  -- Ban FIRST, then remove membership: with the shared lock this order also
  -- means a concurrent join blocks until the ban row is visible.
  INSERT INTO channel_bans (conversation_id, user_id, banned_by)
  VALUES (p_conversation_id, p_user_id, v_user_id)
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = p_user_id;
END;
$$;


--
-- Name: remove_connection(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_connection(p_other_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only a genuine social connection can be removed here — never a transport /
  -- request_reply logistics thread.
  SELECT id, user_1, user_2 INTO v_conv
  FROM conversations
  WHERE type = 'dm'
    AND status = 'active'
    AND initiated_from IN ('profile', 'discovery', 'invite')
    AND ((user_1 = v_user_id AND user_2 = p_other_user_id)
      OR (user_1 = p_other_user_id AND user_2 = v_user_id));
  IF v_conv.id IS NULL THEN RETURN; END IF;

  -- A live carpool between the pair would be stranded (accepted seat + reservation)
  -- if we deleted the shared thread. Ask the user to settle it first.
  IF EXISTS (
    SELECT 1 FROM seat_requests s
    WHERE s.status IN ('pending', 'accepted')
      AND ((s.driver_id = v_user_id AND s.requester_id = p_other_user_id)
        OR (s.driver_id = p_other_user_id AND s.requester_id = v_user_id))
  ) THEN
    RAISE EXCEPTION 'junto.carpool_active';
  END IF;

  -- 00469 (audit M4): keep the thread for moderation before it disappears.
  INSERT INTO contact_removal_archive (conversation_id, user_1, user_2, removed_by, messages)
  SELECT v_conv.id, v_conv.user_1, v_conv.user_2, v_user_id,
         COALESCE(jsonb_agg(jsonb_build_object(
           'id', m.id, 'sender_id', m.sender_id, 'content', m.content, 'created_at', m.created_at,
           'edited_at', m.edited_at, 'original_content', o.content
         ) ORDER BY m.created_at), '[]'::jsonb)
  FROM messages m LEFT JOIN message_original_content o ON o.message_id = m.id
  WHERE m.conversation_id = v_conv.id;

  DELETE FROM conversations WHERE id = v_conv.id;
END;
$$;


--
-- Name: remove_favorite(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_favorite(p_kind text, p_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_kind = 'activity' THEN
    DELETE FROM favorites WHERE owner_id = v_user_id AND activity_id = p_id;
  ELSIF p_kind = 'offering' THEN
    DELETE FROM favorites WHERE owner_id = v_user_id AND offering_id = p_id;
  ELSIF p_kind = 'pro' THEN
    DELETE FROM favorites WHERE owner_id = v_user_id AND pro_id = p_id;
  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;


--
-- Name: remove_missing_gear(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_missing_gear(p_activity_id uuid, p_name text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('gear_missing', 30, INTERVAL '1 minute');
  PERFORM private.rate_hit('gear_missing_h', 300, INTERVAL '1 hour');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) AND NOT EXISTS (
    SELECT 1 FROM activities WHERE id = p_activity_id AND creator_id = v_user_id
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  DELETE FROM activity_gear_missing
  WHERE activity_id = p_activity_id
    AND lower(name) = lower(trim(coalesce(p_name, '')));
END;
$$;


--
-- Name: remove_participant(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_participant(p_participation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.activity_id, p.confirmed_present,
         a.creator_id, a.title, a.status AS activity_status, a.deleted_at
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.user_id = v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00430 : retirer quelqu'un est une action de LOGISTIQUE (avant / pendant),
  -- pas une édition d'historique. Après la fin, la liste des participants est
  -- un fait acquis. Code parlant : le créateur voit que la sortie est passée,
  -- rien de sensible n'est révélé.
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'junto.activity_ended_no_remove';
  END IF;

  -- 00430 : on ne « dés-invite » pas quelqu'un dont la présence est VÉRIFIÉE
  -- (QR, géo ou témoignage de deux pairs). Avant, cette présence était effacée
  -- (`confirmed_present = NULL`) : la victime perdait son crédit de fiabilité
  -- et sa sortie réelle, et à 3+ retirer le seul confirmé neutralisait tout le
  -- monde. On refuse plutôt que d'effacer le fait.
  IF v_participation.confirmed_present IS NOT NULL THEN
    RAISE EXCEPTION 'junto.participant_present_no_remove';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'removed',
      confirmed_present = NULL   -- déjà NULL (gardé par ceinture)
  WHERE id = p_participation_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM create_notification(
    v_participation.user_id,
    'participant_removed',
    'Tu ne fais plus partie de la sortie',
    '« ' || v_participation.title || ' »',
    jsonb_build_object('activity_id', v_participation.activity_id,
      'params', jsonb_build_object('title', v_participation.title))
  );
END;
$$;


--
-- Name: remove_pro_community_photo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_pro_community_photo(p_photo_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- allowed if the caller uploaded it, or owns the pro page (pro_id = owner uid)
  IF NOT EXISTS (
    SELECT 1 FROM pro_community_photos
    WHERE id = p_photo_id AND (contributor_id = v_user_id OR pro_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_community_photos WHERE id = p_photo_id;
END;
$$;


--
-- Name: remove_pro_offering_photo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_pro_offering_photo(p_photo_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pro_offering_photos p
    JOIN pro_offerings o ON o.id = p.offering_id
    WHERE p.id = p_photo_id AND o.pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_offering_photos WHERE id = p_photo_id;
END;
$$;


--
-- Name: remove_pro_photo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_pro_photo(p_photo_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_profile_photos WHERE id = p_photo_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_profile_photos WHERE id = p_photo_id;
END;
$$;


--
-- Name: rename_channel(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rename_channel(p_conversation_id uuid, p_name text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_clean TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00514: a closed discussion (by its creator or by moderation) is frozen.
  IF NOT EXISTS (SELECT 1 FROM channels WHERE conversation_id = p_conversation_id AND created_by = v_user_id AND closed_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  v_clean := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean IS NULL OR char_length(v_clean) > 60 THEN RAISE EXCEPTION 'junto.channel_name'; END IF;
  UPDATE conversations SET name = v_clean WHERE id = p_conversation_id;
END;
$$;


--
-- Name: rename_gpx_trace(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rename_gpx_trace(p_id uuid, p_name text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Ownership: exists AND mine. Generic error either way (don't reveal the id).
  IF NOT EXISTS (SELECT 1 FROM gpx_traces WHERE id = p_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_name := trim(p_name);
  IF char_length(v_name) < 1 OR char_length(v_name) > 80 THEN
    RAISE EXCEPTION 'junto.trace_name_invalid';
  END IF;

  UPDATE gpx_traces SET name = v_name, updated_at = now()
  WHERE id = p_id AND user_id = v_user_id;
END;
$$;


--
-- Name: rename_group(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rename_group(p_conversation_id uuid, p_name text, p_icon text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Creator only (MVP), and the creator must still be a member.
  IF NOT EXISTS (
    SELECT 1 FROM conversations
    WHERE id = p_conversation_id AND type = 'group' AND created_by = v_user_id
      AND moderated_at IS NULL  -- 00514: a group renamed by moderation stays so
  ) OR NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := regexp_replace(trim(COALESCE(p_name, '')), '<[^>]*>', '', 'g');
  IF char_length(v_clean_name) < 1 OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;
  IF p_icon IS NOT NULL AND (char_length(p_icon) < 1 OR char_length(p_icon) > 8 OR p_icon ~ '[[:cntrl:]]') THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;

  UPDATE conversations SET name = v_clean_name, icon = p_icon
  WHERE id = p_conversation_id;
END;
$$;


--
-- Name: reorder_pro_offering_photos(uuid, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reorder_pro_offering_photos(p_offering_id uuid, p_photo_ids uuid[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_owned_count INTEGER;
  v_target_count INTEGER;
  i INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_photo_ids IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_target_count := array_length(p_photo_ids, 1);
  IF v_target_count IS NULL OR v_target_count = 0 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_count FROM pro_offering_photos WHERE offering_id = p_offering_id;
  IF v_count <> v_target_count THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT count(*) INTO v_owned_count
  FROM pro_offering_photos
  WHERE offering_id = p_offering_id AND id = ANY(p_photo_ids);
  IF v_owned_count <> v_target_count THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE pro_offering_photos
  SET order_index = order_index + 1000
  WHERE offering_id = p_offering_id;

  FOR i IN 1..v_target_count LOOP
    UPDATE pro_offering_photos
    SET order_index = i - 1
    WHERE id = p_photo_ids[i] AND offering_id = p_offering_id;
  END LOOP;
END;
$$;


--
-- Name: reorder_pro_photos(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reorder_pro_photos(p_photo_ids uuid[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_owned_count INTEGER;
  v_target_count INTEGER;
  i INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_photo_ids IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_target_count := array_length(p_photo_ids, 1);
  IF v_target_count IS NULL OR v_target_count = 0 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_count FROM pro_profile_photos WHERE pro_id = v_user_id;
  IF v_count <> v_target_count THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT count(*) INTO v_owned_count
  FROM pro_profile_photos
  WHERE pro_id = v_user_id AND id = ANY(p_photo_ids);
  IF v_owned_count <> v_target_count THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Pass 1: shift everyone out of the [0, 25) window to free the targets.
  UPDATE pro_profile_photos
  SET order_index = order_index + 1000
  WHERE pro_id = v_user_id;

  -- Pass 2: assign each id its array position.
  FOR i IN 1..v_target_count LOOP
    UPDATE pro_profile_photos
    SET order_index = i - 1
    WHERE id = p_photo_ids[i] AND pro_id = v_user_id;
  END LOOP;
END;
$$;


--
-- Name: reply_to_offering_review(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reply_to_offering_review(p_review_id uuid, p_reply text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_reply TEXT;
  v_reviewer_id UUID;
  v_had_reply BOOLEAN;
  v_offering_id UUID;
  v_offering_title TEXT;
  v_pro_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT r.reviewer_id, r.pro_reply IS NOT NULL, o.id, o.title
  INTO v_reviewer_id, v_had_reply, v_offering_id, v_offering_title
  FROM offering_reviews r
  JOIN pro_offerings o ON o.id = r.offering_id
  WHERE r.id = p_review_id AND o.pro_id = v_user_id;

  IF v_reviewer_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_reply IS NOT NULL THEN
    v_reply := trim(regexp_replace(p_reply, '<[^>]*>', '', 'g'));
    IF char_length(v_reply) = 0 THEN v_reply := NULL; END IF;
    IF v_reply IS NOT NULL AND char_length(v_reply) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE offering_reviews
  SET pro_reply = v_reply,
      pro_reply_at = CASE WHEN v_reply IS NULL THEN NULL ELSE now() END
  WHERE id = p_review_id;

  IF v_reply IS NOT NULL AND NOT v_had_reply THEN
    SELECT display_name INTO v_pro_name FROM pro_profiles WHERE user_id = v_user_id;
    PERFORM notify_review_reply(
      v_reviewer_id,
      v_pro_name,
      v_offering_title,
      jsonb_build_object('offering_id', v_offering_id, 'review_id', p_review_id)
    );
  END IF;
END;
$$;


--
-- Name: reply_to_pro_review(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reply_to_pro_review(p_review_id uuid, p_reply text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_reply TEXT;
  v_reviewer_id UUID;
  v_had_reply BOOLEAN;
  v_pro_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT reviewer_id, pro_reply IS NOT NULL
  INTO v_reviewer_id, v_had_reply
  FROM pro_reviews
  WHERE id = p_review_id AND pro_id = v_user_id;

  IF v_reviewer_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_reply IS NOT NULL THEN
    v_reply := trim(regexp_replace(p_reply, '<[^>]*>', '', 'g'));
    IF char_length(v_reply) = 0 THEN v_reply := NULL; END IF;
    IF v_reply IS NOT NULL AND char_length(v_reply) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE pro_reviews
  SET pro_reply = v_reply,
      pro_reply_at = CASE WHEN v_reply IS NULL THEN NULL ELSE now() END
  WHERE id = p_review_id;

  IF v_reply IS NOT NULL AND NOT v_had_reply THEN
    SELECT display_name INTO v_pro_name FROM pro_profiles WHERE user_id = v_user_id;
    PERFORM notify_review_reply(
      v_reviewer_id,
      v_pro_name,
      v_pro_name,
      jsonb_build_object('pro_id', v_user_id, 'review_id', p_review_id)
    );
  END IF;
END;
$$;


--
-- Name: request_seat(uuid, uuid, text, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.request_seat(p_activity_id uuid, p_driver_id uuid, p_pickup_from text DEFAULT NULL::text, p_message text DEFAULT NULL::text, p_requested_pickup_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_request_id UUID;
  v_requester_name TEXT;
  v_activity_title TEXT;
  v_starts_at TIMESTAMPTZ;
  v_existing RECORD;
  v_pickup TEXT;
  v_message TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_conv_sender UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_seed_message TEXT;
  v_recent_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_driver_id)
       OR (blocker_id = p_driver_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('request_seat:' || v_user_id::text));

  SELECT count(*) INTO v_recent_count
  FROM seat_requests
  WHERE requester_id = v_user_id
    AND created_at > NOW() - INTERVAL '5 minutes';
  IF v_recent_count >= 5 THEN RAISE EXCEPTION 'junto.seat_rate_limit'; END IF;

  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.starts_at, a.title INTO v_starts_at, v_activity_title
  FROM activities a
  WHERE a.id = p_activity_id
    AND a.status IN ('published', 'in_progress')
    AND a.starts_at > NOW() - INTERVAL '15 seconds'
    AND a.deleted_at IS NULL;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_driver_id
      AND transport_type IN ('car', 'carpool') AND transport_seats > 0
  ) THEN RAISE EXCEPTION 'junto.no_seats_available'; END IF;

  IF p_requested_pickup_at IS NOT NULL THEN
    IF p_requested_pickup_at < v_starts_at - INTERVAL '12 hours'
       OR p_requested_pickup_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'junto.pickup_out_of_window';
    END IF;
  END IF;

  -- Strip HTML/script tags from pickup_from too (message already does).
  v_pickup := CASE
    WHEN p_pickup_from IS NOT NULL AND char_length(trim(p_pickup_from)) > 0
    THEN regexp_replace(trim(p_pickup_from), '<[^>]*>', '', 'g')
    ELSE NULL
  END;
  v_message := CASE WHEN p_message IS NOT NULL AND char_length(trim(p_message)) > 0
                    THEN regexp_replace(trim(p_message), '<[^>]*>', '', 'g') ELSE NULL END;

  -- 00494 (BR-3): one seat per passenger and outing; a driver who carries
  -- passengers does not ride with someone else.
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = p_activity_id AND requester_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = p_activity_id AND driver_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.driver_has_passengers';  -- 00496 (B-5): actionable, coded
  END IF;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  -- 00477 (DB-AC-2): test the id — the record has NULL columns, so the
  -- re-request branch was dead code and every re-request was refused.
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    -- 00477 (AC-4 / AB-4): no request/cancel loop toward the same driver —
    -- 24 h after a refusal, 1 h after a cancellation or expiry.
    IF v_existing.status = 'declined' AND v_existing.created_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.seat_request_cooldown';
    END IF;
    IF v_existing.status IN ('cancelled', 'expired') AND v_existing.created_at > NOW() - INTERVAL '1 hour' THEN
      RAISE EXCEPTION 'junto.seat_request_cooldown';
    END IF;
    UPDATE seat_requests
    SET status = 'pending', created_at = NOW(),
        pickup_from = v_pickup, message = v_message,
        requested_pickup_at = p_requested_pickup_at
    WHERE id = v_existing.id;
    v_request_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO seat_requests (activity_id, requester_id, driver_id, pickup_from, message, requested_pickup_at)
      VALUES (p_activity_id, v_user_id, p_driver_id, v_pickup, v_message, p_requested_pickup_at)
      RETURNING id INTO v_request_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Operation not permitted';
    END;
  END IF;

  IF v_user_id < p_driver_id THEN
    v_u1 := v_user_id; v_u2 := p_driver_id;
  ELSE
    v_u1 := p_driver_id; v_u2 := v_user_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (pas seulement active).
  -- Une ligne pending/declined est réactivée en logistique (retag 'transport'
  -- + purge des champs de requête — invariant 00372 : un refus social ne
  -- devient pas un contact par le covoit). Plus d'unique_violation brute.
  SELECT id, status, request_sender_id INTO v_conversation_id, v_conv_status, v_conv_sender
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  -- 00486 (IX-2 / BR-1): if the requester's own contact request to the driver
  -- was refused (or is still unanswered), the seat request must not turn into
  -- a conversation the driver never accepted. The driver gets the request by
  -- notification and decides; accepting it is the driver's consent.
  IF v_conversation_id IS NOT NULL AND v_conv_status IN ('declined', 'pending_request')
     AND v_conv_sender = v_user_id THEN
    v_conversation_id := NULL;
  END IF;

  -- 00514: a seat REQUEST never creates nor reactivates a conversation — only
  -- the driver's acceptance does (accept_seat_request). The seed message goes
  -- into an already active DM; otherwise the driver is notified only.
  IF v_conv_status IS DISTINCT FROM 'active' THEN
    v_conversation_id := NULL;
  END IF;

  IF v_conversation_id IS NOT NULL THEN
  v_seed_message := '🚗 Demande de place pour « ' || v_activity_title || ' »'
    || CASE WHEN v_pickup IS NOT NULL THEN E'\nDepuis : ' || v_pickup ELSE '' END
    || CASE WHEN v_message IS NOT NULL THEN E'\n\n' || v_message ELSE '' END;

  -- 00508: straight into the unified store (the legacy table and its mirror
  -- are gone). This writer notifies on its own: no generic message push.
  PERFORM set_config('junto.skip_message_push', 'true', true);
  INSERT INTO messages (conversation_id, sender_id, content, metadata, created_at)
  VALUES (
    v_conversation_id, v_user_id, v_seed_message,
    jsonb_build_object(
      'type', 'seat_request_pending',
      'activity_id', p_activity_id,
      'seat_request_id', v_request_id
    ),
    NOW()
  );

  UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL  -- 00523
  WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
  END IF;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_driver_id,
    'seat_request',
    'Demande de covoiturage',
    coalesce(v_requester_name, 'Quelqu''un') || ' demande une place pour « ' || v_activity_title || ' »'
      || CASE WHEN v_pickup IS NOT NULL THEN ' depuis ' || v_pickup ELSE '' END,
    jsonb_build_object(
      'seat_request_id', v_request_id,
      'activity_id', p_activity_id,
      'from_user_id', v_user_id,
      'conversation_id', v_conversation_id,
      'variant', CASE WHEN v_pickup IS NOT NULL THEN 'pickup' ELSE NULL END,
      'params', jsonb_build_object('name', coalesce(v_requester_name, 'Quelqu''un'), 'title', v_activity_title, 'pickup', coalesce(v_pickup, ''))
    )
  );

  RETURN v_conversation_id;
END;
$$;


--
-- Name: resubmit_pro_application(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resubmit_pro_application() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'rejected') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles SET status = 'pending', rejection_reason = NULL, reviewed_at = NULL, reviewed_by = NULL
    WHERE user_id = v_user_id;
END;
$$;


--
-- Name: reviews_touch_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reviews_touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: revoke_contact_qr_tokens(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revoke_contact_qr_tokens(p_token text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- Own tokens only. With p_token: just that one (the screen passes the token
  -- it was showing, so a late revoke never kills a fresher token minted by a
  -- quick reopen — counter-audit F6a). Without: every live one.
  UPDATE contact_qr_tokens SET expires_at = now()
  WHERE user_id = v_user_id AND expires_at > now()
    AND (p_token IS NULL OR token = p_token);
END;
$$;


--
-- Name: revoke_push_token_for_device(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revoke_push_token_for_device(p_device_id text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_revoked_token TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_device_id IS NULL OR char_length(p_device_id) < 1 OR char_length(p_device_id) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Capture whatever token is currently registered for this device so
  -- we can also clear the legacy users.push_token mirror below.
  SELECT token INTO v_revoked_token
  FROM push_tokens
  WHERE user_id = v_user_id AND device_id = p_device_id;

  DELETE FROM push_tokens
  WHERE user_id = v_user_id AND device_id = p_device_id;

  IF v_revoked_token IS NOT NULL THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE users SET push_token = NULL
    WHERE id = v_user_id AND push_token = v_revoked_token;
  END IF;
END;
$$;


--
-- Name: revoke_reputation_badge(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revoke_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.badge_window_not_open';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'junto.badge_window_closed';
  END IF;

  DELETE FROM reputation_votes
  WHERE voter_id = v_user_id
    AND voted_id = p_voted_id
    AND activity_id = p_activity_id
    AND badge_key = p_badge_key;
END;
$$;


--
-- Name: sanitize_notif_text(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sanitize_notif_text(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  SELECT substring(
    regexp_replace(
      regexp_replace(coalesce(p, ''), '<[^>]*>', '', 'g'),
      '[\x00-\x1F\x7F]', '', 'g'
    )
    FROM 1 FOR 200
  );
$$;


--
-- Name: search_channels(text, text, double precision, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.search_channels(p_query text DEFAULT NULL::text, p_sport_key text DEFAULT NULL::text, p_near_lng double precision DEFAULT NULL::double precision, p_near_lat double precision DEFAULT NULL::double precision) RETURNS TABLE(conversation_id uuid, name text, sport_key text, base_label text, radius_km integer, description text, photo_url text, distance_km double precision, member_count integer, is_member boolean, is_creator boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_near GEOGRAPHY;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  -- 00499 (AB-14): bounded query.
  IF p_query IS NOT NULL AND char_length(p_query) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_near := CASE WHEN p_near_lng IS NOT NULL AND p_near_lat IS NOT NULL
                 THEN ST_SetSRID(ST_MakePoint(p_near_lng, p_near_lat), 4326)::geography END;

  RETURN QUERY
  SELECT c.conversation_id, conv.name, c.sport_key, c.base_label, c.radius_km, c.description, c.photo_url,
         CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) / 1000.0 END AS distance_km,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id) AS member_count,
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id) AS is_member,
         (c.created_by = v_user_id) AS is_creator
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.closed_at IS NULL
    AND (p_sport_key IS NULL OR p_sport_key = c.sport_key)
    AND (p_query IS NULL
         OR conv.name ILIKE '%' || p_query || '%'
         OR c.base_label ILIKE '%' || p_query || '%'
         OR c.sport_key ILIKE '%' || p_query || '%'
         OR coalesce(c.description, '') ILIKE '%' || p_query || '%')
    AND (v_near IS NULL OR ST_DWithin(c.base, v_near, c.radius_km * 1000.0))
    AND NOT EXISTS (SELECT 1 FROM channel_bans b WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id)
  ORDER BY
    CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) END ASC NULLS LAST,
    (SELECT count(*) FROM conversation_members m WHERE m.conversation_id = c.conversation_id) DESC,
    c.created_at DESC
  LIMIT 60;
END;
$$;


--
-- Name: send_activity_invitations(uuid, uuid[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_activity_invitations(p_activity_id uuid, p_user_ids uuid[], p_message text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_n INTEGER;
  v_daily INTEGER;
  v_written INTEGER := 0;
  v_target UUID;
  v_existing RECORD;
  v_clean_msg TEXT;
  v_sender_name TEXT;
  v_clean_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_n := array_length(p_user_ids, 1);
  IF p_user_ids IS NULL OR v_n IS NULL OR v_n < 1 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_n > 20 THEN RAISE EXCEPTION 'junto.invite_cap'; END IF;

  IF p_message IS NOT NULL AND char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'junto.message_too_long';
  END IF;
  v_clean_msg := NULLIF(regexp_replace(trim(COALESCE(p_message, '')), '<[^>]*>', '', 'g'), '');

  SELECT id, title, creator_id, status, deleted_at, is_demo INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL OR v_activity.is_demo
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_activity.creator_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00523: same lock as join/accept — an invitation nobody could accept is not sent.
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.requires_presence
             AND now() > a.starts_at + INTERVAL '15 minutes') THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_invite'));
  SELECT count(*) INTO v_daily FROM participations
  WHERE invited_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 30 THEN RAISE EXCEPTION 'junto.invite_daily_cap'; END IF;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
  v_clean_title := regexp_replace(v_activity.title, '<[^>]*>', '', 'g');
  PERFORM set_config('junto.bypass_lock', 'true', true);

  FOR v_target IN SELECT DISTINCT unnest(p_user_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL AND is_demo = false);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );
    CONTINUE WHEN NOT private.is_messaging_eligible(v_user_id, v_target);
    -- 00522 (F14): not someone in a block relation with an accepted member
    -- (the invitation could never be accepted).
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users b JOIN participations q ON q.activity_id = p_activity_id AND q.status = 'accepted'
      WHERE (b.blocker_id = q.user_id AND b.blocked_id = v_target) OR (b.blocker_id = v_target AND b.blocked_id = q.user_id));
    -- 00499 (MS-3): someone who declined this outing's invitation is not
    -- invited to it again.
    CONTINUE WHEN EXISTS (SELECT 1 FROM invitation_declines d
                          WHERE d.activity_id = p_activity_id AND d.user_id = v_target);

    SELECT id, status INTO v_existing FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_target;

    IF v_existing.id IS NULL THEN
      EXIT WHEN v_daily + v_written >= 30;  -- in-loop cap (no single-batch overshoot)
      INSERT INTO participations (activity_id, user_id, status, invited_by, invite_message, created_at)
      VALUES (p_activity_id, v_target, 'invited', v_user_id, v_clean_msg, now());
      v_written := v_written + 1;
    ELSIF v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
      EXIT WHEN v_daily + v_written >= 30;
      UPDATE participations
      SET status = 'invited', invited_by = v_user_id, invite_message = v_clean_msg,
          created_at = now(), refused_at = NULL, left_at = NULL
      WHERE id = v_existing.id;
      v_written := v_written + 1;
    ELSE
      CONTINUE;
    END IF;

    PERFORM create_notification(
      v_target, 'activity_invitation',
      coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
      '« ' || v_clean_title || ' »', jsonb_build_object('activity_id', p_activity_id, 'type', 'activity_invitation',
        'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', v_clean_title))
    );
  END LOOP;
END;
$$;


--
-- Name: send_contact_request(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_contact_request(p_target_user_id uuid, p_message text, p_source text DEFAULT 'profile'::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_conversation_id UUID;
  v_pending_count INTEGER;
  v_daily_count INTEGER;
  v_user_1 UUID;
  v_user_2 UUID;
  v_sender_name TEXT;
  v_clean_message TEXT;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_target_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Le client n'envoie que ces deux valeurs ; le reste de l'enum ('invite',
  -- 'request_reply', 'booking'…) est réservé aux écritures internes — un
  -- appelant ne doit pas pouvoir déguiser une demande profil en invitation.
  IF p_source IS NULL OR p_source NOT IN ('profile', 'discovery') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Rideau démo côté écriture : garde ABSOLUE (admin en mode démo compris),
  -- comme join_activity — un compte démo ne reçoit jamais de vraie demande.
  IF NOT EXISTS (
    SELECT 1 FROM users u
    WHERE u.id = p_target_user_id AND u.suspended_at IS NULL AND u.is_demo = false
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  -- Lock AVANT l'examen de la paire : le reset (DELETE) et l'INSERT restent
  -- atomiques vis-à-vis d'un double-tap du même émetteur.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  SELECT * INTO v_conv FROM conversations WHERE user_1 = v_user_1 AND user_2 = v_user_2;
  IF v_conv.id IS NOT NULL THEN
    IF v_conv.status = 'active' THEN RETURN v_conv.id; END IF;
    -- Demande morte (refusée, ou pending au-delà de ses 30 jours) : la partie
    -- qui NE l'a PAS envoyée peut rouvrir la paire avec sa propre demande.
    -- L'expéditeur d'origine reste verrouillé jusqu'au balayage à
    -- created_at+30j — même échéance qu'une pending ignorée, donc le refus
    -- silencieux reste inobservable de son côté.
    IF v_user_id IS DISTINCT FROM v_conv.request_sender_id
       AND (v_conv.status = 'declined'
            OR (v_conv.status = 'pending_request' AND v_conv.request_expires_at < NOW())) THEN
      DELETE FROM conversations WHERE id = v_conv.id;
    ELSE
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  -- Parité anti-oracle : les DEUX statuts comptent sur la même fenêtre de
  -- 30 jours (une pending non balayée ne sort plus du compte avant une
  -- declined) — le cap ne peut pas servir de sonde à refus.
  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND status IN ('pending_request', 'declined')
    AND created_at > NOW() - INTERVAL '30 days';
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'junto.contact_request_pending_cap'; END IF;

  SELECT count(*) INTO v_daily_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_daily_count >= 5 THEN RAISE EXCEPTION 'junto.contact_request_daily_cap'; END IF;

  IF p_message IS NULL OR char_length(trim(p_message)) < 1 OR char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_message := regexp_replace(trim(p_message), '<[^>]*>', '', 'g');

  INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message, request_expires_at, created_at, last_message_at)
  VALUES (v_user_1, v_user_2, v_user_id, 'pending_request', p_source, v_user_id, v_clean_message, NOW() + INTERVAL '30 days', NOW(), NOW())
  ON CONFLICT (user_1, user_2) DO NOTHING
  RETURNING id INTO v_conversation_id;
  -- Course d'envoi croisé perdue (la paire a gagné une ligne entre l'examen et
  -- l'insert) : même générique que tout chemin « paire existante ».
  IF v_conversation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_target_user_id,
    'contact_request',
    coalesce(v_sender_name, 'Quelqu''un') || ' souhaite te contacter',
    '',
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id,
      'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un')))
  );

  RETURN v_conversation_id;
END;
$$;


--
-- Name: send_discovery_invite(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_discovery_invite(p_target_user_id uuid, p_activity_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_conversation_id UUID;
  v_pending_count INTEGER;
  v_daily_count INTEGER;
  v_user_1 UUID;
  v_user_2 UUID;
  v_sender_name TEXT;
  v_activity RECORD;
  v_sport_key TEXT;
  v_dispo RECORD;
  v_clean_title TEXT;
  v_message TEXT;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id = p_target_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- Rideau démo côté écriture : garde ABSOLUE, même en mode démo admin
  -- (demo_content_visible() rend les gates de réciprocité perméables à
  -- l'admin — la cible démo doit être rejetée AVANT).
  IF NOT EXISTS (
    SELECT 1 FROM users u
    WHERE u.id = p_target_user_id AND u.suspended_at IS NULL AND u.is_demo = false
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Reciprocity + demo gate: the target must be one of MY discovery matches.
  -- Generic failure (sensitive): don't reveal whether it's no-dispo vs no-match.
  IF NOT EXISTS (
    SELECT 1
    FROM discovery_availabilities me
    JOIN discovery_availabilities tgt
      ON tgt.user_id = p_target_user_id AND tgt.is_active AND tgt.window_end > now()  -- 00496 (BR-5)
         AND (tgt.is_demo = false OR demo_content_visible())
    WHERE me.user_id = v_user_id AND me.is_active AND me.window_end > now()
      AND me.sport_keys && tgt.sport_keys
      AND tstzrange(me.window_start, me.window_end) && tstzrange(tgt.window_start, tgt.window_end)
      AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         ST_DWithin(me.base, tgt.base, (CASE WHEN me.radius_km IS NULL AND tgt.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(me.radius_km, 0) + coalesce(tgt.radius_km, 0) END) * 1000.0))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Activity must be mine, live, real.
  SELECT a.id, a.title, a.creator_id, a.status, a.deleted_at, a.is_demo, a.starts_at, a.sport_id
  INTO v_activity FROM activities a WHERE a.id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL OR v_activity.is_demo
     OR v_activity.creator_id != v_user_id
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00514 (MS-3): never re-invite someone who declined this outing.
  IF EXISTS (SELECT 1 FROM invitation_declines d WHERE d.activity_id = p_activity_id AND d.user_id = p_target_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.key INTO v_sport_key FROM sports s WHERE s.id = v_activity.sport_id;

  -- Match the chosen activity against the target's ACTIVE dispo (sport + date).
  SELECT d.sport_keys, d.window_start, d.window_end INTO v_dispo
  FROM discovery_availabilities d
  WHERE d.user_id = p_target_user_id AND d.is_active AND d.window_end > now()
    AND (d.is_demo = false OR demo_content_visible());
  IF NOT FOUND
     OR v_sport_key IS NULL
     OR NOT (v_sport_key = ANY(v_dispo.sport_keys))
     OR v_activity.starts_at < v_dispo.window_start
     OR v_activity.starts_at > v_dispo.window_end THEN
    RAISE EXCEPTION 'junto.discovery_no_match';
  END IF;

  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  SELECT * INTO v_conv FROM conversations WHERE user_1 = v_user_1 AND user_2 = v_user_2;
  IF v_conv.id IS NOT NULL THEN
    -- Même règle de réouverture que send_contact_request (00426 §3).
    IF v_user_id IS DISTINCT FROM v_conv.request_sender_id
       AND (v_conv.status = 'declined'
            OR (v_conv.status = 'pending_request' AND v_conv.request_expires_at < NOW())) THEN
      DELETE FROM conversations WHERE id = v_conv.id;
    ELSE
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND status IN ('pending_request', 'declined')
    AND created_at > NOW() - INTERVAL '30 days';
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'junto.contact_request_pending_cap'; END IF;

  SELECT count(*) INTO v_daily_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_daily_count >= 5 THEN RAISE EXCEPTION 'junto.contact_request_daily_cap'; END IF;

  v_clean_title := regexp_replace(v_activity.title, '<[^>]*>', '', 'g');
  v_message := 'Je t''invite à rejoindre « ' || v_clean_title || ' »';

  INSERT INTO conversations (
    user_1, user_2, initiated_by, status, initiated_from,
    request_sender_id, request_message, request_expires_at,
    pending_activity_id, created_at, last_message_at
  )
  VALUES (
    v_user_1, v_user_2, v_user_id, 'pending_request', 'invite',
    v_user_id, v_message, NOW() + INTERVAL '30 days',
    p_activity_id, NOW(), NOW()
  )
  ON CONFLICT (user_1, user_2) DO NOTHING
  RETURNING id INTO v_conversation_id;
  IF v_conversation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    p_target_user_id,
    'contact_request',
    coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
    '« ' || v_clean_title || ' »',
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id, 'activity_id', p_activity_id,
      'variant', 'invite', 'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', v_clean_title))
  );

  RETURN v_conversation_id;
END;
$$;


--
-- Name: send_message(uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_other UUID;
  v_count INTEGER;
  v_limit INTEGER;
  v_msg_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, type, status, user_1, user_2, activity_id INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: a group taken down by moderation is read-only.
  IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conv.id AND moderated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00520 (C8): in an open discussion, 100 messages a day per member (each
  -- one fans out to every member).
  IF v_conv.type = 'channel' THEN
    PERFORM private.rate_hit('ch:' || v_conv.id::text, 100, INTERVAL '1 day');
    -- 00522 (F15): a banned member never posts (membership is removed on ban,
    -- this is the belt-and-braces check the edit / share paths already have).
    IF EXISTS (SELECT 1 FROM channel_bans WHERE conversation_id = v_conv.id AND user_id = v_user_id) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_conv.type = 'dm' THEN
    IF v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_other := CASE WHEN v_conv.user_1 = v_user_id THEN v_conv.user_2 ELSE v_conv.user_1 END;
    -- Peer must exist and not be suspended (parity with old send_private_message).
    IF EXISTS (SELECT 1 FROM users WHERE id = v_other AND suspended_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_other)
         OR (blocker_id = v_other AND blocked_id = v_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_limit := 15;
  ELSIF v_conv.type = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = v_conv.activity_id AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_limit := 30;
  ELSE
    v_limit := 30;
  END IF;

  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM messages m
    WHERE m.id = p_reply_to_message_id
      AND m.conversation_id = p_conversation_id AND m.deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_send_message'));
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND conversation_id = p_conversation_id
    AND created_at > now() - INTERVAL '1 minute';
  IF v_count >= v_limit THEN
    IF v_conv.type = 'dm' THEN RAISE EXCEPTION 'junto.dm_rate_limit';
    ELSE RAISE EXCEPTION 'junto.wall_rate_limit'; END IF;
  END IF;
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND created_at > now() - INTERVAL '1 minute';
  IF v_count >= 60 THEN RAISE EXCEPTION 'junto.send_rate_limit'; END IF;
  -- 00479 (AB-3): daily cap — one account could otherwise fill the database
  -- in under a day (60/min × 2000 chars, no daily bound).
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_count >= 500 THEN RAISE EXCEPTION 'junto.message_daily_cap'; END IF;

  INSERT INTO messages (conversation_id, sender_id, content, reply_to_message_id)
  VALUES (p_conversation_id, v_user_id, trim(p_content), p_reply_to_message_id)
  RETURNING id INTO v_msg_id;

  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id AND hidden_at IS NOT NULL;

  RETURN v_msg_id;
END;
$$;


--
-- Name: send_private_message(uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_private_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT send_message(p_conversation_id, p_content, p_reply_to_message_id);
$$;


--
-- Name: send_wall_message(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_wall_message(p_activity_id uuid, p_content text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_conv_id UUID;
BEGIN
  SELECT id INTO v_conv_id FROM conversations WHERE activity_id = p_activity_id;
  IF v_conv_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  RETURN send_message(v_conv_id, p_content);
END;
$$;


--
-- Name: set_activity_gear(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_activity_gear(p_activity_id uuid, p_items jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_item JSONB;
  v_name TEXT;
  v_qty INTEGER;
  v_is_shared BOOLEAN;
  v_catalog_is_shared BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('gear', 20, INTERVAL '1 minute');
  PERFORM private.rate_hit('gear_h', 200, INTERVAL '1 hour');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- H7: cap the array size so a megabyte-sized payload can't blow up
  -- the loop. 50 items is generous for legit use.
  IF jsonb_array_length(p_items) > 50 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00481: the per-item loop below is one INSERT statement per item, so the
  -- statement-level ping fired once per item. Silence it for the rewrite and
  -- send a single ping at the end.
  PERFORM set_config('junto.gear_quiet', 'true', true);
  DELETE FROM activity_gear WHERE activity_id = p_activity_id AND user_id = v_user_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    -- H5c: strip HTML/script tags before storing the user-provided
    -- gear name (catalog items are stored as keys and immune).
    v_name := regexp_replace(trim(v_item->>'name'), '<[^>]*>', '', 'g');
    v_qty := COALESCE((v_item->>'quantity')::integer, 1);

    IF v_name IS NOT NULL AND char_length(v_name) > 0 AND v_qty > 0 THEN
      v_qty := LEAST(v_qty, 99);

      SELECT is_shared INTO v_catalog_is_shared
      FROM gear_catalog WHERE name_key = v_name LIMIT 1;
      v_is_shared := COALESCE(v_catalog_is_shared, (v_item->>'is_shared')::boolean, false);

      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared)
      VALUES (p_activity_id, v_user_id, v_name, v_qty, v_is_shared);
    END IF;
  END LOOP;
  PERFORM set_config('junto.gear_quiet', 'false', true);
  BEGIN
    PERFORM realtime.send(jsonb_build_object('table', 'activity_gear', 'op', 'UPDATE'), 'change', 'activity:' || p_activity_id::text, true);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
$$;


--
-- Name: set_booking_participant_info(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_booking_participant_info(p_booking_id uuid, p_info jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_fields JSONB;
  v_allowed_std JSONB;
  v_allowed_custom JSONB;
  v_entry JSONB;
  v_key TEXT;
  v_val JSONB;
  v_q TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT b.*, po.participant_fields AS fields INTO v_bk
  FROM bookings b JOIN pro_offerings po ON po.id = b.offering_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b;
  IF v_bk IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Client Junto : lui seul. Résa manuelle (sans compte) : le pro saisit.
  IF NOT (
    (v_bk.client_id IS NOT NULL AND v_bk.client_id = v_user_id)
    OR (v_bk.client_id IS NULL AND v_bk.pro_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_bk.day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  v_fields := coalesce(v_bk.fields, '{"std":[],"custom":[]}'::jsonb);
  v_allowed_std := coalesce(v_fields->'std', '[]'::jsonb);
  v_allowed_custom := coalesce(v_fields->'custom', '[]'::jsonb);
  IF jsonb_array_length(v_allowed_std) = 0 AND jsonb_array_length(v_allowed_custom) = 0 THEN
    RAISE EXCEPTION 'Operation not permitted'; -- l'offre ne demande pas de fiche
  END IF;

  -- Validation : tableau ≤ party_size ; par participant, un objet dont les
  -- clés ⊆ champs std demandés (valeurs texte ≤ 30) + 'custom' (objet
  -- question⊆demandées → réponse ≤ 120). Les valeurs sont stockées nettoyées
  -- (balises HTML et caractères de contrôle retirés, 00473 — audit L13).
  IF p_info IS NULL OR jsonb_typeof(p_info) != 'array'
     OR jsonb_array_length(p_info) < 1
     OR jsonb_array_length(p_info) > v_bk.party_size THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_info) LOOP
    IF jsonb_typeof(v_entry) != 'object' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    FOR v_key, v_val IN SELECT * FROM jsonb_each(v_entry) LOOP
      IF v_key = 'custom' THEN
        IF jsonb_typeof(v_val) != 'object' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
        FOR v_q IN SELECT jsonb_object_keys(v_val) LOOP
          IF NOT v_allowed_custom ? v_q THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
          IF jsonb_typeof(v_val->v_q) != 'string'
             OR char_length(v_val->>v_q) > 120 THEN
            RAISE EXCEPTION 'Operation not permitted';
          END IF;
        END LOOP;
      ELSE
        IF NOT v_allowed_std ? v_key THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
        IF jsonb_typeof(v_val) != 'string' OR char_length(v_entry->>v_key) > 30 THEN
          RAISE EXCEPTION 'Operation not permitted';
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET participant_info = (
    SELECT jsonb_agg(
      (SELECT coalesce(jsonb_object_agg(k,
         CASE WHEN k = 'custom' THEN
           (SELECT coalesce(jsonb_object_agg(q, to_jsonb(
              regexp_replace(regexp_replace(trim(a #>> '{}'), '<[^>]*>', '', 'g'), '[[:cntrl:]]', '', 'g'))), '{}'::jsonb)
            FROM jsonb_each(v) AS c(q, a))
         ELSE to_jsonb(regexp_replace(regexp_replace(trim(v #>> '{}'), '<[^>]*>', '', 'g'), '[[:cntrl:]]', '', 'g'))
         END), '{}'::jsonb)
       FROM jsonb_each(e) AS kv(k, v))
      ORDER BY ord)
    FROM jsonb_array_elements(p_info) WITH ORDINALITY AS x(e, ord)
  ) WHERE id = p_booking_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;


--
-- Name: set_channel_photo(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_channel_photo(p_conversation_id uuid, p_photo_url text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_photo TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM channels
    WHERE conversation_id = p_conversation_id
      AND created_by = v_user_id
      AND closed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_photo := NULLIF(trim(p_photo_url), '');
  IF v_photo IS NOT NULL AND (
       char_length(v_photo) > 500
       OR private.project_url() IS NULL  -- 00524: fail-closed without a project URL
       OR v_photo NOT LIKE private.project_url() || '/storage/v1/object/public/channel-photos/' || v_user_id::text || '/%'
       OR v_photo ~* '(\.\.|%2e|%2f|%5c|\\)'  -- 00503
     ) THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE channels SET photo_url = v_photo WHERE conversation_id = p_conversation_id;
END;
$$;


--
-- Name: set_conversation_hidden(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_conversation_hidden(p_conversation_id uuid, p_hidden boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE conversation_members
  SET hidden_at = CASE WHEN p_hidden THEN now() ELSE NULL END
  WHERE conversation_id = p_conversation_id AND user_id = auth.uid();
END;
$$;


--
-- Name: set_offering_details(uuid, text[], text[], text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_offering_details(p_offering_id uuid, p_equipment_provided text[], p_equipment_required text[], p_participant_std text[], p_participant_custom text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_provided JSONB := '[]'::jsonb;
  v_required JSONB := '[]'::jsonb;
  v_std JSONB := '[]'::jsonb;
  v_custom JSONB := '[]'::jsonb;
  v_item TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Matériel : listes libres, 15 items max, 60 car. max, HTML strippé.
  IF coalesce(array_length(p_equipment_provided, 1), 0) > 15
     OR coalesce(array_length(p_equipment_required, 1), 0) > 15 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  FOREACH v_item IN ARRAY coalesce(p_equipment_provided, '{}') LOOP
    v_item := nullif(regexp_replace(trim(v_item), '<[^>]*>', '', 'g'), '');
    IF v_item IS NULL THEN CONTINUE; END IF;
    IF char_length(v_item) > 60 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_provided := v_provided || to_jsonb(v_item);
  END LOOP;
  FOREACH v_item IN ARRAY coalesce(p_equipment_required, '{}') LOOP
    v_item := nullif(regexp_replace(trim(v_item), '<[^>]*>', '', 'g'), '');
    IF v_item IS NULL THEN CONTINUE; END IF;
    IF char_length(v_item) > 60 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_required := v_required || to_jsonb(v_item);
  END LOOP;

  -- Fiche participant : champs standard ⊆ catalogue, questions libres ≤3.
  IF coalesce(array_length(p_participant_std, 1), 0) > 5
     OR coalesce(array_length(p_participant_custom, 1), 0) > 3 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  FOREACH v_item IN ARRAY coalesce(p_participant_std, '{}') LOOP
    IF v_item NOT IN ('shoe_size', 'height', 'weight', 'age', 'level') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF NOT v_std ? v_item THEN v_std := v_std || to_jsonb(v_item); END IF;
  END LOOP;
  FOREACH v_item IN ARRAY coalesce(p_participant_custom, '{}') LOOP
    v_item := nullif(regexp_replace(trim(v_item), '<[^>]*>', '', 'g'), '');
    IF v_item IS NULL THEN CONTINUE; END IF;
    IF char_length(v_item) > 80 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_custom := v_custom || to_jsonb(v_item);
  END LOOP;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_offerings
  SET equipment_provided = v_provided,
      equipment_required = v_required,
      participant_fields = jsonb_build_object('std', v_std, 'custom', v_custom),
      updated_at = now()
  WHERE id = p_offering_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;


--
-- Name: set_participation_transport(uuid, text, smallint, text, timestamp with time zone, double precision, double precision, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_participation_transport(p_activity_id uuid, p_transport_type text, p_transport_seats smallint DEFAULT NULL::smallint, p_transport_from_name text DEFAULT NULL::text, p_transport_departs_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_transport_from_lat double precision DEFAULT NULL::double precision, p_transport_from_lng double precision DEFAULT NULL::double precision, p_transport_from_locality text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_from_name TEXT;
  v_lat DOUBLE PRECISION;
  v_lng DOUBLE PRECISION;
  v_locality TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM private.rate_hit('transport', 20, INTERVAL '1 minute');  -- 00516 (L5)

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_transport_type IS NOT NULL
     AND p_transport_type NOT IN ('car', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00496 (BR-3): someone seated in another car does not offer seats.
  IF p_transport_type = 'car' AND coalesce(p_transport_seats, 0) > 0
     AND EXISTS (SELECT 1 FROM seat_requests
                 WHERE activity_id = p_activity_id AND requester_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;

  IF (p_transport_type IS NULL OR p_transport_type != 'car')
     AND EXISTS (
       SELECT 1 FROM seat_requests
       WHERE activity_id = p_activity_id
         AND driver_id = v_user_id
         AND status = 'accepted'
     ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_transport_type != 'car' AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  IF p_transport_departs_at IS NOT NULL THEN
    SELECT starts_at INTO v_starts_at FROM activities WHERE id = p_activity_id;
    IF p_transport_departs_at < v_starts_at - INTERVAL '12 hours'
       OR p_transport_departs_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  v_from_name := CASE
    WHEN p_transport_from_name IS NOT NULL AND char_length(trim(p_transport_from_name)) > 0
    THEN regexp_replace(trim(p_transport_from_name), '<[^>]*>', '', 'g')
    ELSE NULL
  END;

  -- Coords only meaningful with a name; range-validated; cleared with the name
  -- (a free-text departure has a name but no coords).
  IF v_from_name IS NULL THEN
    v_lat := NULL; v_lng := NULL;
  ELSE
    IF p_transport_from_lat IS NOT NULL AND p_transport_from_lat NOT BETWEEN -90 AND 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_transport_from_lng IS NOT NULL AND p_transport_from_lng NOT BETWEEN -180 AND 180 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    v_lat := p_transport_from_lat; v_lng := p_transport_from_lng;
  END IF;

  -- 00521: the village / commune of the start point (reverse-geocoded by the
  -- app, like meeting_locality) — the only start information shown to members
  -- who are not this driver's passengers, and in the carpool summary.
  v_locality := CASE WHEN v_from_name IS NULL THEN NULL ELSE
    NULLIF(left(trim(regexp_replace(regexp_replace(coalesce(p_transport_from_locality, ''), '<[^>]*>', '', 'g'), '[[:cntrl:]]', ' ', 'g')), 80), '') END;

  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = v_from_name,
      transport_departs_at = p_transport_departs_at,
      transport_from_lat = v_lat,
      transport_from_lng = v_lng,
      transport_from_locality = v_locality
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$$;


--
-- Name: set_pro_availability(date, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_pro_availability(p_day date, p_period text, p_available boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_day IS NULL OR p_day < private.today_paris() THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;
  IF p_day > private.today_paris() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;

  IF p_available THEN
    INSERT INTO pro_availabilities (pro_id, day, period)
    VALUES (v_user_id, p_day, p_period)
    ON CONFLICT (pro_id, day, period) DO NOTHING;
  ELSE
    DELETE FROM pro_availabilities
    WHERE pro_id = v_user_id AND day = p_day AND period = p_period;
  END IF;
END;
$$;


--
-- Name: set_pro_availability_bulk(date[], text[], boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_pro_availability_bulk(p_days date[], p_periods text[], p_available boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_n INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  v_n := coalesce(array_length(p_days, 1), 0);
  IF v_n < 1 OR v_n > 200 OR v_n IS DISTINCT FROM coalesce(array_length(p_periods, 1), 0) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(p_periods) AS pr WHERE pr IS NULL OR pr NOT IN ('am', 'pm')
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(p_days) AS d
    WHERE d IS NULL OR d < private.today_paris() OR d > private.today_paris() + INTERVAL '6 months'
  ) THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;

  IF p_available THEN
    INSERT INTO pro_availabilities (pro_id, day, period)
    SELECT v_user_id, t.d, t.pr
    FROM unnest(p_days, p_periods) AS t(d, pr)
    ON CONFLICT (pro_id, day, period) DO NOTHING;
  ELSE
    DELETE FROM pro_availabilities a
    USING unnest(p_days, p_periods) AS t(d, pr)
    WHERE a.pro_id = v_user_id AND a.day = t.d AND a.period = t.pr;
  END IF;
END;
$$;


--
-- Name: set_pro_pin_icon(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_pro_pin_icon(p_pin_icon text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_pin_icon IS NOT NULL AND p_pin_icon NOT IN ('mountain', 'water', 'air', 'cycling', 'wellness') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_profiles SET pin_icon = p_pin_icon WHERE user_id = v_user_id;
END;
$$;


--
-- Name: set_pro_pin_image(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_pro_pin_image(p_pin_image_url text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- NULL efface ; sinon URL ancrée au dossier du caller (00418 H4 — le pin
  -- fan-out vers la carte de TOUS les utilisateurs).
  IF p_pin_image_url IS NOT NULL AND NOT private.pro_photo_url_ok(p_pin_image_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_profiles SET pin_image_url = p_pin_image_url WHERE user_id = v_user_id;
END;
$$;


--
-- Name: set_sport_level(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_sport_level(p_sport_key text, p_new_level text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_current TEXT;
  v_ord_new INT;
  v_ord_cur INT;
  v_green INT;
  v_red INT;
  v_tiers TEXT[] := ARRAY['débutant', 'intermédiaire', 'avancé', 'expert'];
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_ord_new := array_position(v_tiers, p_new_level);
  IF v_ord_new IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM sports WHERE key = p_sport_key) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('sport_level:' || v_user_id::text));

  SELECT levels_per_sport ->> p_sport_key INTO v_current FROM users WHERE id = v_user_id;

  IF v_current IS NOT NULL AND v_current <> '' THEN
    v_ord_cur := array_position(v_tiers, v_current);
    IF v_ord_cur IS NOT NULL THEN
      IF v_ord_new = v_ord_cur THEN RETURN; END IF;
      IF abs(v_ord_new - v_ord_cur) <> 1 THEN
        RAISE EXCEPTION 'Operation not permitted';
      END IF;
      IF v_ord_new > v_ord_cur THEN
        SELECT
          count(*) FILTER (WHERE rv.badge_key = 'level_right'),
          count(*) FILTER (WHERE rv.badge_key = 'level_over')
        INTO v_green, v_red
        FROM reputation_votes rv
        JOIN activities a ON a.id = rv.activity_id
        JOIN sports s ON s.id = a.sport_id
        WHERE rv.voted_id = v_user_id
          AND s.key = p_sport_key
          AND rv.badge_key IN ('level_right', 'level_over')
          AND rv.counted_at IS NOT NULL
          AND rv.created_at > now() - INTERVAL '12 months';

        IF coalesce(v_green, 0) - coalesce(v_red, 0) < 3 THEN
          RAISE EXCEPTION 'junto.level_up_locked';
        END IF;
      END IF;
    END IF;

    DELETE FROM reputation_votes rv
    USING activities a, sports s
    WHERE rv.voted_id = v_user_id
      AND rv.activity_id = a.id
      AND a.sport_id = s.id
      AND s.key = p_sport_key
      AND rv.badge_key IN ('level_right', 'level_over');
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users
  SET levels_per_sport = COALESCE(levels_per_sport, '{}'::jsonb)
                         || jsonb_build_object(p_sport_key, p_new_level),
      sports = CASE
                 WHEN COALESCE(sports, '[]'::jsonb) ? p_sport_key THEN sports
                 ELSE COALESCE(sports, '[]'::jsonb) || to_jsonb(p_sport_key)
               END
  WHERE id = v_user_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;


--
-- Name: share_activity_message(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.share_activity_message(p_conversation_id uuid, p_activity_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_can_see BOOLEAN;
  v_recent INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.assert_can_send(p_conversation_id, v_user_id);

  SELECT id, title, visibility, deleted_at, creator_id, is_demo, sport_id INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL
     OR (v_activity.is_demo AND NOT demo_content_visible()) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Share gate: public → anyone; private → creator only; approval → participant.
  v_can_see := v_activity.visibility = 'public'
    OR v_activity.creator_id = v_user_id
    OR (
      v_activity.visibility = 'approval'
      AND EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = p_activity_id AND user_id = v_user_id
          AND status IN ('accepted', 'pending')
      )
    );
  IF NOT v_can_see THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Channel sport lock: a channel WITH a sport only accepts activities of that
  -- sport. Sport-less channels (and non-channel conversations) are unrestricted.
  IF EXISTS (
    SELECT 1 FROM channels ch
    WHERE ch.conversation_id = p_conversation_id
      AND ch.sport_key IS NOT NULL
      AND ch.sport_key IS DISTINCT FROM (SELECT s.key FROM sports s WHERE s.id = v_activity.sport_id)
  ) THEN
    RAISE EXCEPTION 'junto.channel_sport_mismatch';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_activity'));
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_activity'
    AND created_at > now() - INTERVAL '1 minute';
  IF v_recent >= 1 THEN RAISE EXCEPTION 'junto.share_rate_limit'; END IF;
  -- 00479 (AB-3): daily cap.
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_activity'
    AND created_at > now() - INTERVAL '24 hours';
  IF v_recent >= 50 THEN RAISE EXCEPTION 'junto.share_daily_cap'; END IF;

  RETURN private.insert_rich_message(
    p_conversation_id, v_user_id,
    '📍 ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g'),
    jsonb_build_object('type', 'shared_activity', 'activity_id', p_activity_id)
  );
END;
$$;


--
-- Name: share_trace_message(uuid, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.share_trace_message(p_conversation_id uuid, p_trace_geojson jsonb, p_name text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_coord_count INTEGER;
  v_clean_name TEXT;
  v_recent INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.assert_can_send(p_conversation_id, v_user_id);

  IF p_trace_geojson IS NULL
     OR p_trace_geojson->>'type' != 'LineString'
     OR jsonb_typeof(p_trace_geojson->'coordinates') != 'array' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  v_coord_count := jsonb_array_length(p_trace_geojson->'coordinates');
  IF v_coord_count < 2 OR v_coord_count > 10000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00482: size and frequency gates BEFORE the per-coordinate scan, so a
  -- caller over the limits cannot make the database do the expensive work.
  IF octet_length(p_trace_geojson::text) > 1000000 THEN RAISE EXCEPTION 'junto.trace_too_large'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_trace'));
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
    AND created_at > now() - INTERVAL '1 minute';
  IF v_recent >= 1 THEN RAISE EXCEPTION 'junto.share_rate_limit'; END IF;
  -- 00479 (AB-3 / MS-7): daily cap and total size bound (≤ 1 MB, the shared
  -- trace gate used by activities) — numbers of arbitrary precision made
  -- multi-MB messages possible.
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
    AND created_at > now() - INTERVAL '24 hours';
  IF v_recent >= 20 THEN RAISE EXCEPTION 'junto.share_daily_cap'; END IF;
  -- 00480: byte budget too (20 × 1 MB a day per account was still a lot).
  -- 00482: raw bytes on both sides (pg_column_size of a stored row is the
  -- compressed size, which undercounted earlier shares).
  IF (SELECT coalesce(sum(octet_length((metadata->'trace_geojson')::text)), 0) FROM messages
      WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
        AND created_at > now() - INTERVAL '24 hours') + octet_length(p_trace_geojson::text) > 5000000 THEN
    RAISE EXCEPTION 'junto.share_daily_cap';
  END IF;

  -- Schema + NUMERIC BOUNDS (design review: 1e300 coords sailed straight into
  -- the map renderer). lon/lat ranges, plausible elevation.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_trace_geojson->'coordinates') AS coord
    WHERE jsonb_typeof(coord) != 'array'
       OR jsonb_array_length(coord) < 2
       OR jsonb_array_length(coord) > 3
       OR jsonb_typeof(coord->0) != 'number'
       OR jsonb_typeof(coord->1) != 'number'
       OR (coord->>0)::numeric < -180 OR (coord->>0)::numeric > 180
       OR (coord->>1)::numeric < -90 OR (coord->>1)::numeric > 90
       OR (jsonb_array_length(coord) = 3 AND (
            jsonb_typeof(coord->2) != 'number'
            OR (coord->>2)::numeric < -500 OR (coord->>2)::numeric > 9000
       ))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT trace_geojson_ok(p_trace_geojson) THEN RAISE EXCEPTION 'junto.trace_geojson_invalid'; END IF;

  v_clean_name := CASE
    WHEN p_name IS NOT NULL AND char_length(trim(p_name)) > 0
    THEN substring(regexp_replace(trim(p_name), '<[^>]*>', '', 'g') from 1 for 100)
    ELSE 'trace.gpx'
  END;

  RETURN private.insert_rich_message(
    p_conversation_id, v_user_id,
    '🗺️ ' || v_clean_name,
    jsonb_build_object('type', 'shared_trace', 'name', v_clean_name, 'trace_geojson', p_trace_geojson)
  );
END;
$$;


--
-- Name: strip_html_messages(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.strip_html_messages() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.content := regexp_replace(NEW.content, '<[^>]*>', '', 'g');
  RETURN NEW;
END;
$$;


--
-- Name: strip_html_reviews(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.strip_html_reviews() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.body IS NOT NULL THEN
    NEW.body := regexp_replace(NEW.body, '<[^>]*>', '', 'g');
  END IF;
  IF NEW.pro_reply IS NOT NULL THEN
    NEW.pro_reply := regexp_replace(NEW.pro_reply, '<[^>]*>', '', 'g');
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: strip_html_tags(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.strip_html_tags() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.title IS NOT NULL THEN
    NEW.title := regexp_replace(NEW.title, '<[^>]*>', '', 'g');
  END IF;
  IF NEW.description IS NOT NULL THEN
    NEW.description := regexp_replace(NEW.description, '<[^>]*>', '', 'g');
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: strip_html_users(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.strip_html_users() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.display_name IS NOT NULL THEN
    NEW.display_name := regexp_replace(NEW.display_name, '<[^>]*>', '', 'g');
  END IF;
  IF NEW.bio IS NOT NULL THEN
    NEW.bio := regexp_replace(NEW.bio, '<[^>]*>', '', 'g');
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: sync_activity_membership(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_activity_membership() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_conv_id UUID;
BEGIN
  -- Immutable keys guard (future-proof: no writer re-points a row today).
  IF TG_OP = 'UPDATE' AND (NEW.user_id IS DISTINCT FROM OLD.user_id
                        OR NEW.activity_id IS DISTINCT FROM OLD.activity_id) THEN
    RAISE EXCEPTION 'participations keys are immutable';
  END IF;

  IF TG_OP = 'DELETE' THEN
    -- Tolerant cleanup; redundant with FK cascades (order unspecified) — never fails.
    IF OLD.status = 'accepted' THEN
      DELETE FROM conversation_members cm
      USING conversations c
      WHERE c.activity_id = OLD.activity_id
        AND cm.conversation_id = c.id AND cm.user_id = OLD.user_id;
    END IF;
    RETURN OLD;
  END IF;

  -- Gain: became accepted (INSERT accepted, or UPDATE from any other status).
  IF NEW.status = 'accepted' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'accepted') THEN
    SELECT id INTO v_conv_id FROM conversations WHERE activity_id = NEW.activity_id;
    IF v_conv_id IS NOT NULL THEN
      INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
      VALUES (v_conv_id, NEW.user_id, NULL, now())
      ON CONFLICT (conversation_id, user_id) DO NOTHING;
    END IF;
  -- Loss: left accepted (remove / withdraw / expire / refuse — all UPDATEs).
  ELSIF TG_OP = 'UPDATE' AND OLD.status = 'accepted' AND NEW.status IS DISTINCT FROM 'accepted' THEN
    DELETE FROM conversation_members cm
    USING conversations c
    WHERE c.activity_id = NEW.activity_id
      AND cm.conversation_id = c.id AND cm.user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: trace_distance_km(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trace_distance_km(p_geojson jsonb) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_geom geometry;
BEGIN
  IF p_geojson IS NULL THEN RETURN NULL; END IF;
  BEGIN
    v_geom := ST_GeomFromGeoJSON(p_geojson::text);
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  IF ST_GeometryType(v_geom) <> 'ST_LineString' OR ST_NPoints(v_geom) < 2 THEN
    RETURN NULL;
  END IF;
  RETURN round((ST_Length(v_geom::geography) / 1000)::numeric, 2);
END;
$$;


--
-- Name: trace_elevation_gain_m(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trace_elevation_gain_m(p_geojson jsonb) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  c_threshold CONSTANT DOUBLE PRECISION := 5;
  v_raw DOUBLE PRECISION[];
  v_z DOUBLE PRECISION[];
  v_smooth DOUBLE PRECISION[];
  v_n INTEGER;
  v_with_z INTEGER;
  v_ref DOUBLE PRECISION;
  v_gain DOUBLE PRECISION := 0;
  i INTEGER;
BEGIN
  IF p_geojson IS NULL
     OR coalesce(p_geojson->>'type', '') <> 'LineString'
     OR jsonb_typeof(p_geojson->'coordinates') <> 'array' THEN
    RETURN NULL;
  END IF;

  -- Third coordinate of every point, NULL where absent or not a number.
  SELECT array_agg(
           CASE WHEN jsonb_typeof(c->2) = 'number' AND abs((c->>2)::numeric) < 100000
                THEN (c->>2)::double precision END
           ORDER BY ord)
    INTO v_raw
  FROM jsonb_array_elements(p_geojson->'coordinates') WITH ORDINALITY AS t(c, ord);

  v_n := coalesce(array_length(v_raw, 1), 0);
  IF v_n < 2 THEN RETURN NULL; END IF;

  SELECT count(*) INTO v_with_z FROM unnest(v_raw) AS u(z) WHERE z IS NOT NULL;
  IF v_with_z < 2 OR v_with_z < ceil(v_n * 0.9) THEN RETURN NULL; END IF;

  -- Drop the gaps (neighbours join across them, as gpxpy does).
  SELECT array_agg(z ORDER BY ord) INTO v_z
  FROM unnest(v_raw) WITH ORDINALITY AS u(z, ord)
  WHERE z IS NOT NULL;
  v_n := array_length(v_z, 1);

  -- 3-point weighted smoothing; the ends keep their raw value.
  v_smooth := v_z;
  FOR i IN 2..(v_n - 1) LOOP
    v_smooth[i] := 0.3 * v_z[i - 1] + 0.4 * v_z[i] + 0.3 * v_z[i + 1];
  END LOOP;

  -- Hysteresis: the reference only moves on a ≥ 5 m excursion.
  v_ref := v_smooth[1];
  FOR i IN 2..v_n LOOP
    IF v_smooth[i] - v_ref >= c_threshold THEN
      v_gain := v_gain + (v_smooth[i] - v_ref);
      v_ref := v_smooth[i];
    ELSIF v_ref - v_smooth[i] >= c_threshold THEN
      v_ref := v_smooth[i];
    END IF;
  END LOOP;

  RETURN round(v_gain)::integer;
END;
$$;


--
-- Name: trace_geojson_ok(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trace_geojson_ok(p_geojson jsonb) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $_$
  -- 00484: coalesce — a missing key made the whole test NULL, and callers
  -- write `IF NOT trace_geojson_ok(x)`, so NULL let the trace through.
  SELECT coalesce(p_geojson IS NOT NULL
    AND pg_column_size(p_geojson) <= 1000000
    AND jsonb_typeof(p_geojson) = 'object'
    AND p_geojson ? 'type' AND p_geojson ? 'coordinates'
    AND p_geojson->>'type' = 'LineString'
    AND jsonb_typeof(p_geojson->'coordinates') = 'array'
    AND jsonb_array_length(p_geojson->'coordinates') BETWEEN 2 AND 10000
    -- Same per-point rules as before (00470), evaluated in C by jsonpath.
    -- strict mode: no automatic unwrapping of the coordinate arrays.
    AND NOT jsonb_path_exists(p_geojson, 'strict $.coordinates[*] ? (
         @.type() != "array"
      || @.size() < 2 || @.size() > 4
      || @[0].type() != "number" || @[1].type() != "number"
      || @[0] < -180 || @[0] > 180 || @[1] < -90 || @[1] > 90
      || (@.size() >= 3 && @[2].type() != "number" && @[2].type() != "null")
      || (@.size() >= 3 && @[2].type() == "number" && (@[2] < -100000 || @[2] > 100000))
      || (@.size() == 4 && @[3].type() != "number" && @[3].type() != "null")
      || (@.size() == 4 && @[3].type() == "number" && (@[3] < -1e13 || @[3] > 1e13))
      || (@[0] != 0 && @[0] > -1e-300 && @[0] < 1e-300)
      || (@[1] != 0 && @[1] > -1e-300 && @[1] < 1e-300)
      || (@.size() >= 3 && @[2].type() == "number" && @[2] != 0 && @[2] > -1e-300 && @[2] < 1e-300)
      || (@.size() == 4 && @[3].type() == "number" && @[3] != 0 && @[3] > -1e-300 && @[3] < 1e-300)
    )', '{}', true), false);
$_$;


--
-- Name: transition_single_activity(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.transition_single_activity(p_activity_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN NULL;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  SELECT id, creator_id, status, title, starts_at, duration, requires_presence, deleted_at
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN NULL; END IF;
  -- 00495: a suspended organiser's outing is frozen (no reminders, no vote
  -- requests, no finalisation) — same as the minute sweep.
  IF private.user_is_suspended(v_activity.creator_id) THEN RETURN v_activity.status; END IF;
  -- 00429 : même garde que le balayage cron — une sortie supprimée ne transite
  -- plus (sinon elle passait 'completed' puis se faisait finaliser).
  IF v_activity.deleted_at IS NOT NULL THEN RETURN v_activity.status; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress', 'completed') THEN
    RETURN v_activity.status;
  END IF;

  IF v_activity.status = 'published'
     AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id
          AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
      -- CORRIGÉ (00428) : notify_presence_reminders(UUID) a été SUPPRIMÉE en
      -- 00148 (spine de notifs simplifié) mais l'appel a été transporté
      -- verbatim de migration en migration (00136 → 00225 → 00286 → 00427).
      -- Résultat : cette RPC levait « function does not exist » à chaque
      -- appel, donc le flip completed, la fermeture de fenêtre de présence et
      -- rate_participants côté lazy n'ont JAMAIS tourné (les deux appelants
      -- client avalent l'erreur). Les rappels pré-event vivent dans
      -- notify_presence_pre_warning / _10min, appelés par le balayage cron.
      PERFORM notify_creator_qr_reminder(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    PERFORM notify_creator_qr_reminder(p_activity_id);
  END IF;

  IF v_activity.status = 'in_progress' AND v_activity.starts_at + v_activity.duration <= now() THEN
    -- Solo end-of-window → expired, not completed (see header).
    IF (SELECT count(*) FROM participations p
        WHERE p.activity_id = p_activity_id
        AND p.status = 'accepted'
        AND p.user_id != v_activity.creator_id) = 0
    THEN
      UPDATE activities SET status = 'expired', updated_at = now()
      WHERE id = p_activity_id AND status = 'in_progress';
      IF FOUND THEN
        RETURN 'expired';
      END IF;
    END IF;

    UPDATE activities SET status = 'completed', updated_at = now()
    WHERE id = p_activity_id AND status = 'in_progress';
    IF FOUND THEN
      v_activity.status := 'completed';
    END IF;
  END IF;

  IF v_activity.status = 'completed' THEN
    PERFORM close_presence_window_for(p_activity_id);
    -- 00427: emit rate_participants here too (lazy path) — gates internally
    -- on the real vote window [end+15min, end+24h] + dedup.
    PERFORM notify_rate_participants(p_activity_id);
  END IF;

  RETURN v_activity.status;
END;
$$;


--
-- Name: transition_statuses_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.transition_statuses_only() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published' AND starts_at <= now();

  -- Solo end-of-window: nobody (besides the creator) ever joined → the
  -- outing didn't happen. Must run BEFORE the completed update.
  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'in_progress' AND starts_at + duration <= now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

  UPDATE activities
  SET status = 'completed', updated_at = now()
  WHERE status = 'in_progress' AND starts_at + duration <= now();

  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'published'
    AND starts_at + INTERVAL '2 hours' < now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

  -- Pre-event sweep: published activities approaching start. All three
  -- emitters gate internally on their respective time windows (pre_warning
  -- T-2h..T0, pre_warning_10min T-10..T0, qr_reminder T-10..T0 creator-only).
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'published'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND a.starts_at - INTERVAL '2 hours' <= now()
      AND a.starts_at > now()
  LOOP
    PERFORM notify_presence_pre_warning(v_activity_id);
    PERFORM notify_presence_pre_warning_10min(v_activity_id);
    PERFORM notify_creator_qr_reminder(v_activity_id);
  END LOOP;

  -- During-event sweep: in_progress activities. validate_warning gates on
  -- T+duration/2 internally. (qr_create_reminder no longer called here —
  -- moved to the published sweep at T-10min.)
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'in_progress'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
  LOOP
    PERFORM notify_presence_validate_warning(v_activity_id);
  END LOOP;

  -- Post-event sweep: completed activities. validate_overdue at T+1h after
  -- end, peer_review_closing at T+22h. Each gates internally.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '1 hour'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    PERFORM notify_presence_validate_overdue(v_activity_id);
  END LOOP;

  -- 00427: rate_participants only once the vote window is actually OPEN
  -- (end+15min) — the completion trigger no longer emits it at the flip,
  -- where tapping the notification guaranteed a "too early" refusal.
  -- No requires_presence gate: trait/level votes apply to every outing
  -- with >=2 accepted participants. notify_* gates + dedups internally.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '15 minutes'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    PERFORM notify_rate_participants(v_activity_id);
  END LOOP;

  PERFORM close_due_presence_windows();
END;
$$;


--
-- Name: unregister_as_pro(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.unregister_as_pro() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00518 (L4): lock all of this pro's offerings before the check.
  PERFORM 1 FROM pro_offerings WHERE pro_id = v_user_id FOR UPDATE;

  -- 00416 : refuser tant que des réservations futures vivantes existent
  -- (le CASCADE pro_profiles → pro_offerings → bookings serait silencieux).
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE pro_id = v_user_id
      AND status IN ('pending', 'accepted')
      AND day >= private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  -- 00443 B6 : pro_availabilities référence users, pas pro_profiles — sans
  -- ceci les créneaux ouverts survivaient à la désinscription et redevenaient
  -- réservables tels quels à une ré-inscription.
  DELETE FROM pro_availabilities WHERE pro_id = v_user_id;
  DELETE FROM pro_profiles WHERE user_id = v_user_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tier = 'free' WHERE id = v_user_id;
END;
$$;


--
-- Name: update_activity(uuid, text, text, text, integer, double precision, double precision, timestamp with time zone, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_activity(p_activity_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_level text DEFAULT NULL::text, p_max_participants integer DEFAULT NULL::integer, p_meeting_lng double precision DEFAULT NULL::double precision, p_meeting_lat double precision DEFAULT NULL::double precision, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_duration text DEFAULT NULL::text, p_visibility text DEFAULT NULL::text, p_level_max text DEFAULT NULL::text, p_meeting_locality text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_old RECORD;
  v_new RECORD;
  v_participant RECORD;
  v_trimmed_title TEXT;
  v_level_max TEXT;
  v_changes JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00516: coordinates must be real places.
  IF NOT ((p_meeting_lng IS NULL AND p_meeting_lat IS NULL) OR (p_meeting_lng BETWEEN -180 AND 180 AND p_meeting_lat BETWEEN -90 AND 90)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('activity_update', 30, INTERVAL '1 hour');

  IF p_title IS NOT NULL THEN
    v_trimmed_title := trim(p_title);
    IF char_length(v_trimmed_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;
  END IF;

  -- Normalised range high end (only applied when the level is being edited).
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF p_level IS NOT NULL AND v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  SELECT id, creator_id, status, title, description, starts_at, duration,
         location_meeting, max_participants, level, visibility, deleted_at
  INTO v_old FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_old IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_old.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_old.status NOT IN ('published', 'in_progress') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00494 (BR-8): an outing removed by moderation is frozen.
  IF v_old.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- The client resends starts_at as an ISO string (millisecond precision)
  -- while Postgres stores microseconds — a raw IS DISTINCT FROM would see a
  -- sub-millisecond ghost diff on any row whose date has non-zero µs (seed,
  -- manual INSERTs) and re-trigger the date_in_past bug plus phantom
  -- "activity updated" notifs. Normalise: an unchanged-at-ms-precision date
  -- is treated as "not provided" for everything downstream (validation,
  -- UPDATE, change diff).
  IF p_starts_at IS NOT NULL
     AND date_trunc('milliseconds', p_starts_at) IS NOT DISTINCT FROM date_trunc('milliseconds', v_old.starts_at) THEN
    p_starts_at := NULL;
  END IF;

  -- Only validate the date when it actually changes — resending the
  -- unchanged (now past) starts_at of an in-progress activity is not a
  -- reschedule and must not block editing the other fields.
  -- 00503: the organiser cannot move their outing onto a slot where they are
  -- already accepted elsewhere (participants are told of the change).
  -- 00519: with accepted participants the duration is frozen by the trigger,
  -- so it must not take part in the conflict test.
  IF EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id <> v_user_id) THEN
    p_duration := NULL;
  END IF;
  IF (p_starts_at IS NOT NULL OR p_duration IS NOT NULL) AND NOT EXISTS (
       SELECT 1 FROM activities x WHERE x.id = p_activity_id AND x.is_demo) AND EXISTS (
    SELECT 1 FROM participations p JOIN activities a ON a.id = p.activity_id
    WHERE p.user_id = v_user_id AND p.status = 'accepted' AND p.activity_id <> p_activity_id
      AND a.status IN ('published', 'in_progress') AND a.deleted_at IS NULL AND NOT a.is_demo
      AND tstzrange(a.starts_at, a.starts_at + a.duration)
          && tstzrange(coalesce(p_starts_at, v_old.starts_at),
                       coalesce(p_starts_at, v_old.starts_at) + coalesce(p_duration::interval, v_old.duration))
  ) THEN
    RAISE EXCEPTION 'junto.schedule_conflict';
  END IF;

  -- 00494 (BR-7): once under way, an outing's date no longer moves (it
  -- would leave « in progress » with a future start).
  IF p_starts_at IS NOT NULL AND v_old.status = 'in_progress' THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  -- 00496 (BR-7): nor its duration (the app locks it; the server too).
  IF p_duration IS NOT NULL AND v_old.status = 'in_progress'
     AND p_duration::interval IS DISTINCT FROM v_old.duration THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  IF p_starts_at IS NOT NULL THEN
    IF p_starts_at <= NOW() THEN
      RAISE EXCEPTION 'junto.date_in_past';
    END IF;
    IF p_starts_at > NOW() + INTERVAL '6 months' THEN
      RAISE EXCEPTION 'junto.date_too_far';
    END IF;
  END IF;

  -- p_max_participants = 0 is the explicit "make it open" sentinel (NULL
  -- means "unchanged", so it can't express open — the edit screen's open
  -- toggle silently did nothing before this). 0 sits outside the valid
  -- [2,50] range so it can't collide with a real cap. Any other
  -- out-of-range value is rejected (parity with create_activity — before
  -- this it surfaced as a raw table CHECK violation).
  IF p_max_participants IS NOT NULL AND p_max_participants != 0
     AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'junto.participants_range';
  END IF;

  -- Tamper guard (UI only sends valid values): generic. Parity with create_activity.
  IF p_visibility IS NOT NULL
     AND p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Private-link visibilities open to all (Scott 2026-07-10) — no gate.

  UPDATE activities SET
    title = COALESCE(v_trimmed_title, title),
    description = CASE WHEN p_description IS NOT NULL THEN trim(p_description) ELSE description END,
    level = COALESCE(p_level, level),
    level_max = CASE WHEN p_level IS NOT NULL THEN v_level_max ELSE level_max END,
    max_participants = CASE
      WHEN p_max_participants = 0 THEN NULL
      WHEN p_max_participants IS NOT NULL THEN p_max_participants
      ELSE max_participants END,
    location_meeting = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE location_meeting END,
    -- Only alongside a pin move (00441); the trigger freezes it otherwise.
    meeting_locality = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN CASE WHEN p_meeting_locality IS NOT NULL AND char_length(trim(p_meeting_locality)) > 0
                THEN left(trim(p_meeting_locality), 80) ELSE NULL END
      ELSE meeting_locality END,
    starts_at = COALESCE(p_starts_at, starts_at),
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE duration END,
    visibility = COALESCE(p_visibility, visibility)
  WHERE id = p_activity_id;

  -- Re-fetch after the UPDATE (whitelist trigger may have forced privileged
  -- columns back to OLD when participants exist — only notify on real changes).
  SELECT title, description, starts_at, duration, location_meeting,
         max_participants, level, visibility
  INTO v_new FROM activities WHERE id = p_activity_id;

  -- 00489 (AC-8): turning a public / on-request outing private rotates its
  -- link — anyone who saw the old token while it was public loses access.
  IF v_old.visibility IN ('public', 'approval')
     AND v_new.visibility IN ('private_link', 'private_link_approval') THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE activities SET invite_token = gen_random_uuid() WHERE id = p_activity_id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    DELETE FROM invite_grants WHERE activity_id = p_activity_id;
  END IF;

  v_changes := '{}'::jsonb;
  IF v_old.title IS DISTINCT FROM v_new.title THEN
    v_changes := v_changes || jsonb_build_object('title', true);
  END IF;
  IF v_old.starts_at IS DISTINCT FROM v_new.starts_at THEN
    v_changes := v_changes || jsonb_build_object('starts_at', true);
  END IF;
  IF v_old.duration IS DISTINCT FROM v_new.duration THEN
    v_changes := v_changes || jsonb_build_object('duration', true);
  END IF;
  IF v_old.location_meeting IS DISTINCT FROM v_new.location_meeting THEN
    v_changes := v_changes || jsonb_build_object('location_meeting', true);
  END IF;
  IF v_old.description IS DISTINCT FROM v_new.description THEN
    v_changes := v_changes || jsonb_build_object('description', true);
  END IF;
  IF v_old.level IS DISTINCT FROM v_new.level THEN
    v_changes := v_changes || jsonb_build_object('level', true);
  END IF;
  IF v_old.max_participants IS DISTINCT FROM v_new.max_participants THEN
    v_changes := v_changes || jsonb_build_object('max_participants', true);
  END IF;
  IF v_old.visibility IS DISTINCT FROM v_new.visibility THEN
    v_changes := v_changes || jsonb_build_object('visibility', true);
  END IF;

  -- No real change happened (every requested field was rejected by trigger or unchanged) — skip notif
  IF v_changes = '{}'::jsonb THEN RETURN; END IF;

  FOR v_participant IN
    SELECT user_id FROM participations
    -- 00516 (AC-7): requesters are told too — they must not be accepted
    -- into an outing that changed under them without knowing.
    WHERE activity_id = p_activity_id AND status IN ('accepted', 'pending') AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_updated',
      'Sortie modifiée',
      '« ' || v_new.title || ' » a changé — vérifie l''heure et le rendez-vous.',
      jsonb_build_object('activity_id', p_activity_id, 'changes', v_changes,
        'params', jsonb_build_object('title', v_new.title))
    );
  END LOOP;
END;
$$;


--
-- Name: update_activity_trace(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_old_trace JSONB;
  v_title TEXT;
  v_participant RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('activity_trace', 20, INTERVAL '1 hour');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND creator_id = v_user_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00470 (audit M6): same gate as create_activity.
  -- 00483: an invalid trace is REPORTED, not raised, so the frequency
  -- counter above stays committed (a raise rolled it back and made the
  -- failing path free). NULL = saved; a junto.<code> = refused.
  IF p_trace_geojson IS NOT NULL AND NOT trace_geojson_ok(p_trace_geojson) THEN
    RETURN 'junto.trace_geojson_invalid';
  END IF;

  SELECT trace_geojson, title INTO v_old_trace, v_title FROM activities WHERE id = p_activity_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET trace_geojson = p_trace_geojson,
      distance_km = CASE
        WHEN p_trace_geojson IS NOT NULL AND distance_km IS NULL
          THEN (SELECT CASE WHEN round(d, 1) > 0 AND d <= 9999 THEN d END FROM (SELECT trace_distance_km(p_trace_geojson) AS d) x)
        ELSE distance_km END,
      elevation_gain_m = CASE
        WHEN p_trace_geojson IS NOT NULL AND elevation_gain_m IS NULL
          THEN (SELECT CASE WHEN g > 0 AND g <= 99999 THEN g END FROM (SELECT trace_elevation_gain_m(p_trace_geojson) AS g) x)
        ELSE elevation_gain_m END,
      updated_at = now()
  WHERE id = p_activity_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  -- 00475 (audit L9, Scott 2026-10-21): the route is part of what people
  -- signed up for — a changed trace notifies the accepted participants, like
  -- an hour or meeting-point change does in update_activity.
  IF v_old_trace IS DISTINCT FROM p_trace_geojson THEN
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
    LOOP
      PERFORM create_notification(
        v_participant.user_id,
        'activity_updated',
        'Itinéraire modifié',
        '« ' || v_title || ' » a un nouvel itinéraire — jette un œil à la trace.',
        jsonb_build_object('activity_id', p_activity_id,
          'changes', jsonb_build_object('trace', true),
          'variant', 'trace',
          'params', jsonb_build_object('title', v_title))
      );
    END LOOP;
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: update_offering_review(uuid, smallint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_offering_review(p_review_id uuid, p_rating smallint, p_body text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_body TEXT;
  v_pro UUID;
  v_replied BOOLEAN;
  v_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM offering_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  SELECT (SELECT o.pro_id FROM pro_offerings o WHERE o.id = r.offering_id), r.pro_reply IS NOT NULL, (SELECT o.title FROM pro_offerings o WHERE o.id = r.offering_id) INTO v_pro, v_replied, v_label
  FROM offering_reviews r WHERE r.id = p_review_id;
  -- 00501 (PO-4): not while blocked by the pro.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_pro AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE offering_reviews SET rating = p_rating, body = v_body WHERE id = p_review_id;

  -- 00501 (PO-11): a review rewritten after the pro answered — the pro is told
  -- (their reply may no longer match). At most once a day per review.
  IF v_replied THEN
    PERFORM notify_review_received(v_pro, (SELECT display_name FROM users WHERE id = v_user_id), p_rating, v_label,
      jsonb_build_object('review_id', p_review_id, 'reviewer_id', v_user_id, 'variant', 'updated',
        'offering_id', (SELECT r.offering_id FROM offering_reviews r WHERE r.id = p_review_id)));  -- 00505: tappable
  END IF;
END;
$$;


--
-- Name: update_pro_offering(uuid, uuid, text, text, text, double precision, double precision, text, text, integer, text, numeric, integer, numeric, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_pro_offering(p_offering_id uuid, p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text DEFAULT NULL::text, p_max_participants integer DEFAULT NULL::integer, p_schedule_text text DEFAULT NULL::text, p_distance_km numeric DEFAULT NULL::numeric, p_elevation_gain_m integer DEFAULT NULL::integer, p_price_eur numeric DEFAULT NULL::numeric, p_price_unit text DEFAULT NULL::text, p_min_participants integer DEFAULT NULL::integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_clean_title TEXT;
  v_clean_location_name TEXT;
  v_clean_schedule TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00519: duration between 15 min and 30 days, readable error.
  IF p_duration IS NOT NULL AND NOT private.offering_duration_ok(p_duration) THEN RAISE EXCEPTION 'junto.offering_duration'; END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Ownership check
  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Input validation (identical to create)
  v_clean_title := trim(p_title);
  IF char_length(v_clean_title) < 3 OR char_length(v_clean_title) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_description IS NULL OR char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_level IS NULL OR char_length(trim(p_level)) < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_location_name := trim(p_location_name);
  IF char_length(v_clean_location_name) < 1 OR char_length(v_clean_location_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_location_lng IS NULL OR p_location_lat IS NULL
     OR p_location_lng < -180 OR p_location_lng > 180
     OR p_location_lat < -90 OR p_location_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 1 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_min_participants IS NOT NULL AND (p_min_participants < 1 OR p_min_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_min_participants IS NOT NULL AND p_max_participants IS NOT NULL
     AND p_min_participants > p_max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_schedule_text IS NOT NULL THEN
    v_clean_schedule := trim(p_schedule_text);
    IF char_length(v_clean_schedule) > 100 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF char_length(v_clean_schedule) = 0 THEN
      v_clean_schedule := NULL;
    END IF;
  END IF;

  IF p_distance_km IS NOT NULL AND (p_distance_km <= 0 OR p_distance_km > 9999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_elevation_gain_m IS NOT NULL AND (p_elevation_gain_m <= 0 OR p_elevation_gain_m > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_eur IS NOT NULL AND (p_price_eur <= 0 OR p_price_eur > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_unit IS NOT NULL AND p_price_unit NOT IN ('person', 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF (p_price_eur IS NULL) <> (p_price_unit IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE pro_offerings SET
    sport_id = p_sport_id,
    title = v_clean_title,
    description = p_description,
    level = p_level,
    location = ST_SetSRID(ST_MakePoint(p_location_lng, p_location_lat), 4326)::geography,
    location_name = v_clean_location_name,
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE NULL END,
    max_participants = p_max_participants,
    schedule_text = v_clean_schedule,
    distance_km = p_distance_km,
    elevation_gain_m = p_elevation_gain_m,
    price_eur = p_price_eur,
    price_unit = p_price_unit,
    min_participants = p_min_participants
  WHERE id = p_offering_id;
END;
$$;


--
-- Name: update_pro_profile(text, text, text, text, text, text, text, text, double precision, double precision, text, text, text, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_pro_profile(p_display_name text DEFAULT NULL::text, p_tagline text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_instagram text DEFAULT NULL::text, p_facebook text DEFAULT NULL::text, p_primary_lng double precision DEFAULT NULL::double precision, p_primary_lat double precision DEFAULT NULL::double precision, p_primary_location_name text DEFAULT NULL::text, p_company_name text DEFAULT NULL::text, p_real_name text DEFAULT NULL::text, p_clear text[] DEFAULT NULL::text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $_$
DECLARE
  v_user_id UUID;
  v_existing RECORD;
  v_location_changing BOOLEAN := false;
  v_clear TEXT[] := COALESCE(p_clear, ARRAY[]::TEXT[]);
  v_col TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_existing FROM pro_profiles WHERE user_id = v_user_id FOR UPDATE;
  IF v_existing IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00443 B3 : une fois APPROUVÉ, raison sociale et identité sont gelées —
  -- les renvoyer inchangées est permis, les changer passe par nous.
  IF v_existing.status = 'approved' THEN
    IF (p_company_name IS NOT NULL
        AND trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g')) IS DISTINCT FROM v_existing.company_name)
       OR (p_real_name IS NOT NULL
        AND trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g')) IS DISTINCT FROM v_existing.real_name) THEN
      RAISE EXCEPTION 'junto.pro_identity_locked';
    END IF;
  END IF;

  -- 00444 (1) : liste blanche des colonnes vidables. ≤ 7 entrées, toutes connues.
  IF array_length(v_clear, 1) > 7 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  FOREACH v_col IN ARRAY v_clear LOOP
    IF v_col IS NULL OR v_col NOT IN ('tagline', 'description', 'website', 'email', 'phone', 'instagram', 'facebook') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END LOOP;

  IF p_primary_lng IS NOT NULL OR p_primary_lat IS NOT NULL THEN
    IF p_primary_lng IS NULL OR p_primary_lat IS NULL OR p_primary_location_name IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 00444 (2) : cooldown seulement pour une enseigne publique (approved).
    IF v_existing.status = 'approved'
       AND v_existing.last_location_change_at > now() - INTERVAL '30 days' THEN
      RAISE EXCEPTION 'junto.pro_location_cooldown';
    END IF;
    v_location_changing := true;
  END IF;

  IF p_display_name IS NOT NULL AND (char_length(trim(regexp_replace(p_display_name, '<[^>]*>', '', 'g'))) < 1 OR char_length(p_display_name) > 100) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_company_name IS NOT NULL AND (char_length(trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g'))) < 2 OR char_length(p_company_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NOT NULL AND (char_length(trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g'))) < 2 OR char_length(p_real_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00499 (B11): a tappable link must be a web address (no javascript:, data:…).
  IF p_website IS NOT NULL AND p_website !~* '^https?://[^[:space:]]+$' THEN RAISE EXCEPTION 'junto.pro_website_invalid'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: same link rules as the table checks, with a readable error.
  IF p_website IS NOT NULL AND p_website !~* '^https?://[^[:space:]]+$' THEN RAISE EXCEPTION 'junto.pro_website_invalid'; END IF;
  IF (p_facebook IS NOT NULL AND p_facebook ~* '^[a-z][a-z0-9+.-]*:' AND p_facebook !~* '^https?://')
     OR (p_instagram IS NOT NULL AND p_instagram ~* '^[a-z][a-z0-9+.-]*:' AND p_instagram !~* '^https?://') THEN
    RAISE EXCEPTION 'junto.pro_website_invalid';
  END IF;
  IF p_primary_location_name IS NOT NULL AND (char_length(trim(regexp_replace(p_primary_location_name, '<[^>]*>', '', 'g'))) < 1 OR char_length(p_primary_location_name) > 200) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles SET
    display_name = COALESCE(trim(regexp_replace(p_display_name, '<[^>]*>', '', 'g')), display_name),
    company_name = CASE WHEN p_company_name IS NOT NULL THEN trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g')) ELSE company_name END,
    real_name = CASE WHEN p_real_name IS NOT NULL THEN trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g')) ELSE real_name END,
    tagline = CASE WHEN 'tagline' = ANY(v_clear) THEN NULL
                   WHEN p_tagline IS NOT NULL THEN trim(regexp_replace(p_tagline, '<[^>]*>', '', 'g')) ELSE tagline END,
    description = CASE WHEN 'description' = ANY(v_clear) THEN NULL
                       WHEN p_description IS NOT NULL THEN trim(regexp_replace(p_description, '<[^>]*>', '', 'g')) ELSE description END,
    website = CASE WHEN 'website' = ANY(v_clear) THEN NULL ELSE COALESCE(p_website, website) END,
    email = CASE WHEN 'email' = ANY(v_clear) THEN NULL ELSE COALESCE(p_email, email) END,
    phone = CASE WHEN 'phone' = ANY(v_clear) THEN NULL ELSE COALESCE(p_phone, phone) END,
    instagram = CASE WHEN 'instagram' = ANY(v_clear) THEN NULL ELSE COALESCE(p_instagram, instagram) END,
    facebook = CASE WHEN 'facebook' = ANY(v_clear) THEN NULL ELSE COALESCE(p_facebook, facebook) END,
    primary_lng = CASE WHEN v_location_changing THEN p_primary_lng ELSE primary_lng END,
    primary_lat = CASE WHEN v_location_changing THEN p_primary_lat ELSE primary_lat END,
    primary_location = CASE WHEN v_location_changing
                            THEN ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography
                            ELSE primary_location END,
    primary_location_name = CASE WHEN v_location_changing THEN trim(regexp_replace(p_primary_location_name, '<[^>]*>', '', 'g')) ELSE primary_location_name END,
    last_location_change_at = CASE WHEN v_location_changing THEN now() ELSE last_location_change_at END
  WHERE user_id = v_user_id;
END;
$_$;


--
-- Name: update_pro_review(uuid, smallint, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_pro_review(p_review_id uuid, p_rating smallint, p_body text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_body TEXT;
  v_pro UUID;
  v_replied BOOLEAN;
  v_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  SELECT r.pro_id, r.pro_reply IS NOT NULL, (SELECT display_name FROM pro_profiles WHERE user_id = r.pro_id) INTO v_pro, v_replied, v_label
  FROM pro_reviews r WHERE r.id = p_review_id;
  -- 00501 (PO-4): not while blocked by the pro.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_pro AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE pro_reviews SET rating = p_rating, body = v_body WHERE id = p_review_id;

  -- 00501 (PO-11): a review rewritten after the pro answered — the pro is told
  -- (their reply may no longer match). At most once a day per review.
  IF v_replied THEN
    PERFORM notify_review_received(v_pro, (SELECT display_name FROM users WHERE id = v_user_id), p_rating, v_label,
      jsonb_build_object('review_id', p_review_id, 'reviewer_id', v_user_id, 'variant', 'updated', 'pro_id', v_pro));  -- 00505: tappable
  END IF;
END;
$$;


--
-- Name: upsert_dispo(text[], jsonb, double precision, double precision, text, integer, text[], timestamp with time zone, timestamp with time zone, text[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.upsert_dispo(p_sport_keys text[], p_levels jsonb, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_transport_modes text[], p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_intent text[] DEFAULT NULL::text[], p_about text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_id UUID;
  v_label TEXT;
  v_intent TEXT[];
  v_about TEXT;
  v_lng DOUBLE PRECISION;
  v_lat DOUBLE PRECISION;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_sport_keys IS NULL OR array_length(p_sport_keys, 1) IS NULL
     OR array_length(p_sport_keys, 1) NOT BETWEEN 1 AND 3
     OR EXISTS (SELECT 1 FROM unnest(p_sport_keys) k
                WHERE NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = k AND s.is_active))
  THEN RAISE EXCEPTION 'junto.dispo_sports'; END IF;

  -- Levels: optional. If present it MUST be an object whose keys ⊆ chosen sports
  -- and whose values are short strings (cotation codes) — no unbounded / non-object
  -- blob can be stored and fanned out to matches.
  IF p_levels IS NOT NULL THEN
    IF jsonb_typeof(p_levels) <> 'object'
       OR EXISTS (
         SELECT 1 FROM jsonb_object_keys(p_levels) AS lk(sport)
         WHERE lk.sport <> ALL(p_sport_keys)
       )
       OR EXISTS (
         SELECT 1 FROM jsonb_each_text(p_levels) AS e(k, v)
         WHERE v IS NULL OR char_length(v) > 20
       )
    THEN RAISE EXCEPTION 'junto.dispo_levels'; END IF;
  END IF;

  IF p_intent IS NULL OR cardinality(p_intent) = 0 THEN
    v_intent := NULL;
  ELSIF NOT (p_intent <@ ARRAY[
              'discovery','progression','performance','detente','conviviality',
              'dog','child','group','solo','active','calm','early',
              'nature','challenge','photo','mixed','same_level','beginners',
              'long_outing','after_work','regular','adapted','training',
              'experienced','competition'
            ]::text[])
        OR cardinality(p_intent) > 10 THEN
    RAISE EXCEPTION 'junto.dispo_intent';
  ELSE
    v_intent := p_intent;
  END IF;

  v_about := NULLIF(trim(regexp_replace(COALESCE(p_about, ''), '<[^>]*>', '', 'g')), '');
  IF v_about IS NOT NULL AND (
       char_length(v_about) > 1600
       OR array_length(regexp_split_to_array(v_about, '\s+'), 1) > 250
     ) THEN
    RAISE EXCEPTION 'junto.dispo_about';
  END IF;

  IF p_radius_km IS NOT NULL AND p_radius_km NOT IN (5, 10, 15, 30, 50) THEN
    RAISE EXCEPTION 'junto.dispo_radius';
  END IF;

  IF p_transport_modes IS NULL OR array_length(p_transport_modes, 1) IS NULL
     OR array_length(p_transport_modes, 1) < 1
     OR NOT (p_transport_modes <@ ARRAY['car', 'motorbike', 'bike', 'on_foot', 'public_transport'])
  THEN RAISE EXCEPTION 'junto.dispo_transport'; END IF;

  IF p_window_start IS NULL OR p_window_end IS NULL OR p_window_end <= p_window_start
     OR p_window_end > now() + INTERVAL '4 weeks' OR p_window_start < now() - INTERVAL '1 day'
  THEN RAISE EXCEPTION 'junto.dispo_window'; END IF;

  IF p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_base_lng NOT BETWEEN -180 AND 180 OR p_base_lat NOT BETWEEN -90 AND 90
  THEN RAISE EXCEPTION 'junto.dispo_place'; END IF;

  -- 00485 (DC-1 / DX-2): the base is rounded to ~1 km BEFORE it is stored,
  -- so no read or matching probe can ever recover an exact address.
  v_lng := round(p_base_lng::numeric, 2)::float8;
  v_lat := round(p_base_lat::numeric, 2)::float8;

  v_label := NULLIF(trim(regexp_replace(COALESCE(p_base_label, ''), '<[^>]*>', '', 'g')), '');
  IF v_label IS NULL OR char_length(v_label) > 120 THEN
    RAISE EXCEPTION 'junto.dispo_place';
  END IF;

  -- 00488: counted only once every input check has passed.
  PERFORM private.rate_hit('dispo', 30, INTERVAL '1 day');

  -- 00503: serialised (one dispo per account is a unique index since 00499).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_dispo'));
  SELECT id INTO v_id FROM discovery_availabilities WHERE user_id = v_user_id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO discovery_availabilities
      (user_id, sport_keys, levels, intent, about, base, base_label, radius_km, transport_modes, window_start, window_end)
    VALUES
      (v_user_id, p_sport_keys, p_levels, v_intent, v_about,
       ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326)::geography,
       v_label, p_radius_km, p_transport_modes, p_window_start, p_window_end)
    RETURNING id INTO v_id;
  ELSE
    UPDATE discovery_availabilities SET
      sport_keys = p_sport_keys, levels = p_levels, intent = v_intent, about = v_about,
      base = ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326)::geography,
      base_label = v_label, radius_km = p_radius_km, transport_modes = p_transport_modes,
      window_start = p_window_start, window_end = p_window_end
    WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;


--
-- Name: waive_late_cancel_penalty(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.waive_late_cancel_penalty(p_participation_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_target UUID;
  v_activity UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_user_id AND u0.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM private.rate_hit('waive', 20, INTERVAL '1 minute');  -- 00516 (L5)

  SELECT p.user_id, p.activity_id, a.creator_id INTO v_target, v_activity, v_creator
  FROM participations p JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id;
  IF NOT FOUND OR v_user_id IS DISTINCT FROM v_creator THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00478: keyed on the ledger, so a waiver still works after the person rejoined.
  IF NOT EXISTS (SELECT 1 FROM late_cancels WHERE user_id = v_target AND activity_id = v_activity) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE late_cancels SET waived = TRUE WHERE user_id = v_target AND activity_id = v_activity;
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET penalty_waived = TRUE WHERE id = p_participation_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM recalculate_reliability_score(v_target);
END;
$$;


--
-- Name: activity_alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_alerts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    sport_key text,
    location extensions.geography(Point,4326) NOT NULL,
    radius_km integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    levels text[],
    starts_on date,
    ends_on date,
    CONSTRAINT activity_alerts_radius_km_check CHECK (((radius_km >= 5) AND (radius_km <= 200))),
    CONSTRAINT alerts_levels_nonempty CHECK (((levels IS NULL) OR (array_length(levels, 1) > 0))),
    CONSTRAINT alerts_period_valid CHECK (((ends_on IS NULL) OR (starts_on IS NULL) OR (ends_on >= starts_on)))
);

ALTER TABLE ONLY public.activity_alerts FORCE ROW LEVEL SECURITY;


--
-- Name: activity_gear; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_gear (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    activity_id uuid NOT NULL,
    user_id uuid NOT NULL,
    gear_name text NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_shared boolean DEFAULT false NOT NULL,
    CONSTRAINT activity_gear_gear_name_check CHECK (((char_length(gear_name) >= 1) AND (char_length(gear_name) <= 100))),
    CONSTRAINT activity_gear_quantity_check CHECK (((quantity >= 1) AND (quantity <= 99)))
);

ALTER TABLE ONLY public.activity_gear FORCE ROW LEVEL SECURITY;


--
-- Name: activity_gear_missing; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_gear_missing (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    activity_id uuid NOT NULL,
    name text NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT activity_gear_missing_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 60))),
    CONSTRAINT activity_gear_missing_quantity_check CHECK (((quantity >= 1) AND (quantity <= 99)))
);

ALTER TABLE ONLY public.activity_gear_missing FORCE ROW LEVEL SECURITY;


--
-- Name: activity_participants; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.activity_participants AS
 SELECT p.id AS participation_id,
    p.activity_id,
    p.user_id,
    p.status,
    p.created_at,
    p.left_at,
    p.left_reason,
    p.penalty_waived,
    p.confirmed_present,
    p.transport_type,
    p.transport_seats,
    p.transport_from_name,
    p.transport_departs_at,
    a.creator_id,
    pp.display_name,
    pp.avatar_url,
    pp.sports,
    pp.levels_per_sport,
    public.reliability_tier(u.reliability_score) AS reliability_tier
   FROM (((public.participations p
     JOIN public.activities a ON ((a.id = p.activity_id)))
     JOIN public.public_profiles pp ON ((pp.id = p.user_id)))
     JOIN public.users u ON ((u.id = p.user_id)))
  WHERE ((a.creator_id = auth.uid()) AND (p.user_id <> a.creator_id) AND (p.status <> 'removed'::text) AND (a.deleted_at IS NULL) AND (NOT (p.user_id IN ( SELECT blocked_users.blocked_id
           FROM public.blocked_users
          WHERE (blocked_users.blocker_id = auth.uid())))));


--
-- Name: admin_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_actions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    admin_id uuid,
    action text NOT NULL,
    target_type text,
    target_id uuid,
    reason text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.admin_actions FORCE ROW LEVEL SECURITY;


--
-- Name: app_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_config (
    name text NOT NULL,
    value text NOT NULL
);

ALTER TABLE ONLY public.app_config FORCE ROW LEVEL SECURITY;


--
-- Name: banned_email_hashes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banned_email_hashes (
    email_hash text NOT NULL,
    banned_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT banned_email_hashes_email_hash_check CHECK ((char_length(email_hash) = 64))
);

ALTER TABLE ONLY public.banned_email_hashes FORCE ROW LEVEL SECURITY;


--
-- Name: bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    offering_id uuid NOT NULL,
    pro_id uuid NOT NULL,
    client_id uuid,
    manual_name text,
    manual_phone text,
    day date NOT NULL,
    period text NOT NULL,
    party_size integer NOT NULL,
    message text,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    submitted_count integer DEFAULT 1 NOT NULL,
    last_submitted_at timestamp with time zone DEFAULT now() NOT NULL,
    participant_info jsonb,
    price_eur numeric,
    price_unit text,
    CONSTRAINT bookings_check CHECK ((client_id <> pro_id)),
    CONSTRAINT bookings_check1 CHECK ((((client_id IS NOT NULL) AND (manual_name IS NULL) AND (manual_phone IS NULL)) OR ((client_id IS NULL) AND (manual_name IS NOT NULL)))),
    CONSTRAINT bookings_manual_name_check CHECK (((manual_name IS NULL) OR ((char_length(manual_name) >= 1) AND (char_length(manual_name) <= 80)))),
    CONSTRAINT bookings_manual_phone_check CHECK (((manual_phone IS NULL) OR ((char_length(manual_phone) >= 3) AND (char_length(manual_phone) <= 30)))),
    CONSTRAINT bookings_message_check CHECK (((message IS NULL) OR ((char_length(message) >= 1) AND (char_length(message) <= 500)))),
    CONSTRAINT bookings_participant_info_check CHECK (((participant_info IS NULL) OR (jsonb_typeof(participant_info) = 'array'::text))),
    CONSTRAINT bookings_party_size_check CHECK (((party_size >= 1) AND (party_size <= 50))),
    CONSTRAINT bookings_period_check CHECK ((period = ANY (ARRAY['am'::text, 'pm'::text]))),
    CONSTRAINT bookings_price_eur_check CHECK (((price_eur IS NULL) OR (price_eur >= (0)::numeric))),
    CONSTRAINT bookings_price_unit_check CHECK (((price_unit IS NULL) OR (price_unit = ANY (ARRAY['person'::text, 'group'::text])))),
    CONSTRAINT bookings_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text, 'cancelled'::text, 'cancelled_pro'::text, 'expired'::text])))
);

ALTER TABLE ONLY public.bookings FORCE ROW LEVEL SECURITY;


--
-- Name: channel_bans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_bans (
    conversation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    banned_by uuid,
    banned_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.channel_bans FORCE ROW LEVEL SECURITY;


--
-- Name: channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channels (
    conversation_id uuid NOT NULL,
    base extensions.geography(Point,4326) NOT NULL,
    base_label text NOT NULL,
    description text,
    created_by uuid,
    closed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    radius_km integer NOT NULL,
    photo_url text,
    sport_key text,
    CONSTRAINT channels_base_label_check CHECK (((char_length(base_label) >= 1) AND (char_length(base_label) <= 120))),
    CONSTRAINT channels_description_check CHECK (((description IS NULL) OR (char_length(description) <= 500))),
    CONSTRAINT channels_photo_url_check CHECK (((photo_url IS NULL) OR (char_length(photo_url) <= 500))),
    CONSTRAINT channels_radius_tier CHECK ((radius_km = ANY (ARRAY[35, 60, 100])))
);

ALTER TABLE ONLY public.channels FORCE ROW LEVEL SECURITY;


--
-- Name: contact_qr_scans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_qr_scans (
    user_id uuid NOT NULL,
    scanned_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.contact_qr_scans FORCE ROW LEVEL SECURITY;


--
-- Name: contact_qr_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_qr_tokens (
    token text NOT NULL,
    user_id uuid NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT contact_qr_tokens_token_check CHECK ((token ~ '^[0-9a-f]{64}$'::text))
);

ALTER TABLE ONLY public.contact_qr_tokens FORCE ROW LEVEL SECURITY;


--
-- Name: contact_removal_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_removal_archive (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    user_1 uuid NOT NULL,
    user_2 uuid NOT NULL,
    removed_by uuid NOT NULL,
    removed_at timestamp with time zone DEFAULT now() NOT NULL,
    messages jsonb DEFAULT '[]'::jsonb NOT NULL
);

ALTER TABLE ONLY public.contact_removal_archive FORCE ROW LEVEL SECURITY;


--
-- Name: conversation_departures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_departures (
    conversation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.conversation_departures FORCE ROW LEVEL SECURITY;


--
-- Name: conversation_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_members (
    conversation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    added_by uuid,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    last_read_at timestamp with time zone,
    hidden_at timestamp with time zone
);

ALTER TABLE ONLY public.conversation_members FORCE ROW LEVEL SECURITY;


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_1 uuid,
    user_2 uuid,
    initiated_by uuid,
    last_message_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    initiated_from text,
    request_sender_id uuid,
    request_message text,
    request_expires_at timestamp with time zone,
    type text DEFAULT 'dm'::text NOT NULL,
    activity_id uuid,
    name text,
    icon text,
    created_by uuid,
    pending_activity_id uuid,
    moderated_at timestamp with time zone,
    CONSTRAINT conversations_activity_check CHECK (((type = 'activity'::text) = (activity_id IS NOT NULL))),
    CONSTRAINT conversations_check CHECK ((user_1 <> user_2)),
    CONSTRAINT conversations_dm_ordered_check CHECK (((type <> 'dm'::text) OR (user_1 < user_2))),
    CONSTRAINT conversations_dm_pair_check CHECK (((type = 'dm'::text) = ((user_1 IS NOT NULL) AND (user_2 IS NOT NULL)))),
    CONSTRAINT conversations_group_name_check CHECK (((type = ANY (ARRAY['group'::text, 'channel'::text])) = (name IS NOT NULL))),
    CONSTRAINT conversations_icon_len_check CHECK (((icon IS NULL) OR ((char_length(icon) >= 1) AND (char_length(icon) <= 8)))),
    CONSTRAINT conversations_initiated_from_check CHECK (((initiated_from IS NULL) OR (initiated_from = ANY (ARRAY['profile'::text, 'discovery'::text, 'transport'::text, 'invite'::text, 'request_reply'::text, 'booking'::text])))),
    CONSTRAINT conversations_name_len_check CHECK (((name IS NULL) OR ((char_length(name) >= 1) AND (char_length(name) <= 60)))),
    CONSTRAINT conversations_request_message_len CHECK (((request_message IS NULL) OR ((char_length(request_message) >= 1) AND (char_length(request_message) <= 500)))),
    CONSTRAINT conversations_status_by_type_check CHECK ((((type = 'dm'::text) AND (status = ANY (ARRAY['pending_request'::text, 'active'::text, 'declined'::text]))) OR ((type <> 'dm'::text) AND (status = 'active'::text)))),
    CONSTRAINT conversations_status_check CHECK ((status = ANY (ARRAY['pending_request'::text, 'active'::text, 'declined'::text]))),
    CONSTRAINT conversations_type_check CHECK ((type = ANY (ARRAY['dm'::text, 'group'::text, 'activity'::text, 'channel'::text])))
);

ALTER TABLE ONLY public.conversations FORCE ROW LEVEL SECURITY;


--
-- Name: discovery_availabilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.discovery_availabilities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    sport_keys text[] NOT NULL,
    levels jsonb,
    base extensions.geography(Point,4326) NOT NULL,
    base_label text NOT NULL,
    radius_km integer,
    transport_modes text[] NOT NULL,
    window_start timestamp with time zone NOT NULL,
    window_end timestamp with time zone NOT NULL,
    is_active boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    intent text[],
    is_demo boolean DEFAULT false NOT NULL,
    about text,
    CONSTRAINT discovery_availabilities_about_check CHECK (((about IS NULL) OR (char_length(about) <= 1600))),
    CONSTRAINT discovery_availabilities_base_label_check CHECK (((char_length(base_label) >= 1) AND (char_length(base_label) <= 120))),
    CONSTRAINT discovery_availabilities_check CHECK ((window_end > window_start)),
    CONSTRAINT discovery_availabilities_intent_check CHECK (((intent IS NULL) OR ((intent <@ ARRAY['discovery'::text, 'progression'::text, 'performance'::text, 'detente'::text, 'conviviality'::text, 'dog'::text, 'child'::text, 'group'::text, 'solo'::text, 'active'::text, 'calm'::text, 'early'::text, 'nature'::text, 'challenge'::text, 'photo'::text, 'mixed'::text, 'same_level'::text, 'beginners'::text, 'long_outing'::text, 'after_work'::text, 'regular'::text, 'adapted'::text, 'training'::text, 'experienced'::text, 'competition'::text]) AND ((COALESCE(array_length(intent, 1), 0) >= 1) AND (COALESCE(array_length(intent, 1), 0) <= 10))))),
    CONSTRAINT discovery_availabilities_radius_km_check CHECK (((radius_km IS NULL) OR (radius_km = ANY (ARRAY[5, 10, 15, 30, 50])))),
    CONSTRAINT discovery_availabilities_sport_keys_check CHECK (((array_length(sport_keys, 1) >= 1) AND (array_length(sport_keys, 1) <= 3))),
    CONSTRAINT discovery_availabilities_transport_modes_check CHECK ((((array_length(transport_modes, 1) >= 1) AND (array_length(transport_modes, 1) <= 5)) AND (transport_modes <@ ARRAY['car'::text, 'motorbike'::text, 'bike'::text, 'on_foot'::text, 'public_transport'::text])))
);

ALTER TABLE ONLY public.discovery_availabilities FORCE ROW LEVEL SECURITY;


--
-- Name: favorites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.favorites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid NOT NULL,
    activity_id uuid,
    offering_id uuid,
    pro_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT favorites_check CHECK ((num_nonnulls(activity_id, offering_id, pro_id) = 1))
);

ALTER TABLE ONLY public.favorites FORCE ROW LEVEL SECURITY;


--
-- Name: gear_catalog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gear_catalog (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name_key text NOT NULL,
    sport_keys text[] DEFAULT '{}'::text[] NOT NULL,
    display_order integer DEFAULT 0 NOT NULL,
    category_key text DEFAULT 'personal'::text NOT NULL,
    per_person boolean DEFAULT true NOT NULL,
    shared_recommended_qty integer,
    is_shared boolean DEFAULT false NOT NULL,
    CONSTRAINT gear_catalog_category_key_check CHECK ((category_key = ANY (ARRAY['safety'::text, 'technical'::text, 'water'::text, 'personal'::text]))),
    CONSTRAINT gear_catalog_qty_logic_check CHECK ((((per_person = true) AND (shared_recommended_qty IS NULL)) OR ((per_person = false) AND (shared_recommended_qty IS NOT NULL) AND (shared_recommended_qty > 0))))
);

ALTER TABLE ONLY public.gear_catalog FORCE ROW LEVEL SECURITY;


--
-- Name: invitation_declines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitation_declines (
    activity_id uuid NOT NULL,
    user_id uuid NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.invitation_declines FORCE ROW LEVEL SECURITY;


--
-- Name: invite_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invite_grants (
    user_id uuid NOT NULL,
    activity_id uuid NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.invite_grants FORCE ROW LEVEL SECURITY;


--
-- Name: late_cancels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.late_cancels (
    user_id uuid NOT NULL,
    activity_id uuid NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL,
    waived boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY public.late_cancels FORCE ROW LEVEL SECURITY;


--
-- Name: map_broadcasts; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.map_broadcasts (
    activity_id uuid NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.map_broadcasts FORCE ROW LEVEL SECURITY;


--
-- Name: message_original_content; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_original_content (
    message_id uuid NOT NULL,
    content text NOT NULL,
    saved_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.message_original_content FORCE ROW LEVEL SECURITY;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    sender_id uuid,
    content text NOT NULL,
    metadata jsonb,
    reply_to_message_id uuid,
    edited_at timestamp with time zone,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT messages_content_check CHECK (((char_length(content) >= 1) AND (char_length(content) <= 2000)))
);

ALTER TABLE ONLY public.messages FORCE ROW LEVEL SECURITY;


--
-- Name: my_activities; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.my_activities AS
 SELECT a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.distance_km,
    a.elevation_gain_m,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.requires_presence,
    a.status,
    a.deleted_at,
    a.created_at,
    a.updated_at,
    a.objective_name,
    a.meeting_name,
    a.trace_geojson,
    extensions.st_x((COALESCE(a.location_objective, a.location_meeting))::extensions.geometry) AS lng,
    extensions.st_y((COALESCE(a.location_objective, a.location_meeting))::extensions.geometry) AS lat,
    extensions.st_x((a.location_meeting)::extensions.geometry) AS meeting_lng,
    extensions.st_y((a.location_meeting)::extensions.geometry) AS meeting_lat,
    extensions.st_x((a.location_end)::extensions.geometry) AS end_lng,
    extensions.st_y((a.location_end)::extensions.geometry) AS end_lat,
    extensions.st_x((a.location_objective)::extensions.geometry) AS objective_lng,
    extensions.st_y((a.location_objective)::extensions.geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    ( SELECT (count(*))::integer AS count
           FROM public.participations p
          WHERE ((p.activity_id = a.id) AND (p.status = 'accepted'::text))) AS participant_count,
    a.level_max,
    a.meeting_locality
   FROM ((public.activities a
     JOIN public.public_profiles pp ON ((a.creator_id = pp.id)))
     JOIN public.sports s ON ((a.sport_id = s.id)))
  WHERE (a.creator_id = auth.uid());


--
-- Name: my_joined_activities; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.my_joined_activities AS
 SELECT a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.distance_km,
    a.elevation_gain_m,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.requires_presence,
    a.status,
    a.deleted_at,
    a.created_at,
    a.updated_at,
    a.objective_name,
    a.meeting_name,
    a.trace_geojson,
    extensions.st_x((COALESCE(a.location_objective, a.location_meeting))::extensions.geometry) AS lng,
    extensions.st_y((COALESCE(a.location_objective, a.location_meeting))::extensions.geometry) AS lat,
    extensions.st_x((a.location_meeting)::extensions.geometry) AS meeting_lng,
    extensions.st_y((a.location_meeting)::extensions.geometry) AS meeting_lat,
    extensions.st_x((a.location_end)::extensions.geometry) AS end_lng,
    extensions.st_y((a.location_end)::extensions.geometry) AS end_lat,
    extensions.st_x((a.location_objective)::extensions.geometry) AS objective_lng,
    extensions.st_y((a.location_objective)::extensions.geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    ( SELECT (count(*))::integer AS count
           FROM public.participations p
          WHERE ((p.activity_id = a.id) AND (p.status = 'accepted'::text))) AS participant_count,
    a.level_max,
    a.meeting_locality
   FROM (((public.activities a
     JOIN public.participations par ON (((par.activity_id = a.id) AND (par.user_id = auth.uid()) AND (par.status = 'accepted'::text))))
     JOIN public.public_profiles pp ON ((a.creator_id = pp.id)))
     JOIN public.sports s ON ((a.sport_id = s.id)))
  WHERE ((a.creator_id <> auth.uid()) AND (a.deleted_at IS NULL));


--
-- Name: my_pending_activities; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.my_pending_activities AS
 SELECT a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.distance_km,
    a.elevation_gain_m,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.requires_presence,
    a.status,
    a.deleted_at,
    a.created_at,
    a.updated_at,
    a.objective_name,
    a.meeting_name,
    a.trace_geojson,
    extensions.st_x((COALESCE(a.location_objective, a.location_meeting))::extensions.geometry) AS lng,
    extensions.st_y((COALESCE(a.location_objective, a.location_meeting))::extensions.geometry) AS lat,
    extensions.st_x((a.location_meeting)::extensions.geometry) AS meeting_lng,
    extensions.st_y((a.location_meeting)::extensions.geometry) AS meeting_lat,
    extensions.st_x((a.location_end)::extensions.geometry) AS end_lng,
    extensions.st_y((a.location_end)::extensions.geometry) AS end_lat,
    extensions.st_x((a.location_objective)::extensions.geometry) AS objective_lng,
    extensions.st_y((a.location_objective)::extensions.geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    ( SELECT (count(*))::integer AS count
           FROM public.participations p
          WHERE ((p.activity_id = a.id) AND (p.status = 'accepted'::text))) AS participant_count,
    a.level_max,
    a.meeting_locality
   FROM (((public.activities a
     JOIN public.participations par ON (((par.activity_id = a.id) AND (par.user_id = auth.uid()) AND (par.status = 'pending'::text))))
     JOIN public.public_profiles pp ON ((a.creator_id = pp.id)))
     JOIN public.sports s ON ((a.sport_id = s.id)))
  WHERE ((a.creator_id <> auth.uid()) AND (a.deleted_at IS NULL));


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    type text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    data jsonb,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.notifications REPLICA IDENTITY FULL;

ALTER TABLE ONLY public.notifications FORCE ROW LEVEL SECURITY;


--
-- Name: offering_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.offering_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    offering_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    rating smallint NOT NULL,
    body text,
    pro_reply text,
    pro_reply_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT offering_reviews_body_check CHECK (((body IS NULL) OR (char_length(body) <= 1000))),
    CONSTRAINT offering_reviews_pro_reply_check CHECK (((pro_reply IS NULL) OR (char_length(pro_reply) <= 1000))),
    CONSTRAINT offering_reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);

ALTER TABLE ONLY public.offering_reviews FORCE ROW LEVEL SECURITY;


--
-- Name: pro_offerings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_offerings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    sport_id uuid NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    level text NOT NULL,
    location extensions.geography(Point,4326) NOT NULL,
    location_name text NOT NULL,
    duration interval,
    max_participants integer,
    schedule_text text,
    distance_km numeric,
    elevation_gain_m integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    price_eur numeric,
    price_unit text,
    min_participants integer,
    is_demo boolean DEFAULT false NOT NULL,
    equipment_provided jsonb DEFAULT '[]'::jsonb NOT NULL,
    equipment_required jsonb DEFAULT '[]'::jsonb NOT NULL,
    participant_fields jsonb DEFAULT '{"std": [], "custom": []}'::jsonb NOT NULL,
    CONSTRAINT pro_offerings_description_check CHECK ((char_length(description) <= 2000)),
    CONSTRAINT pro_offerings_distance_km_check CHECK (((distance_km IS NULL) OR ((distance_km > (0)::numeric) AND (distance_km <= (9999)::numeric)))),
    CONSTRAINT pro_offerings_duration_range CHECK (((duration IS NULL) OR ((duration >= '00:15:00'::interval) AND (duration <= '30 days'::interval)))),
    CONSTRAINT pro_offerings_elevation_gain_m_check CHECK (((elevation_gain_m IS NULL) OR ((elevation_gain_m > 0) AND (elevation_gain_m <= 99999)))),
    CONSTRAINT pro_offerings_equipment_provided_check CHECK ((jsonb_typeof(equipment_provided) = 'array'::text)),
    CONSTRAINT pro_offerings_equipment_required_check CHECK ((jsonb_typeof(equipment_required) = 'array'::text)),
    CONSTRAINT pro_offerings_level_len CHECK ((char_length(level) <= 60)),
    CONSTRAINT pro_offerings_location_name_check CHECK (((char_length(TRIM(BOTH FROM location_name)) >= 1) AND (char_length(TRIM(BOTH FROM location_name)) <= 100))),
    CONSTRAINT pro_offerings_max_participants_check CHECK (((max_participants IS NULL) OR ((max_participants >= 1) AND (max_participants <= 50)))),
    CONSTRAINT pro_offerings_min_max_chk CHECK (((min_participants IS NULL) OR (max_participants IS NULL) OR (min_participants <= max_participants))),
    CONSTRAINT pro_offerings_min_participants_check CHECK (((min_participants IS NULL) OR ((min_participants >= 1) AND (min_participants <= 50)))),
    CONSTRAINT pro_offerings_participant_fields_check CHECK ((jsonb_typeof(participant_fields) = 'object'::text)),
    CONSTRAINT pro_offerings_price_eur_check CHECK (((price_eur IS NULL) OR ((price_eur > (0)::numeric) AND (price_eur <= (99999)::numeric)))),
    CONSTRAINT pro_offerings_price_pair_chk CHECK (((price_eur IS NULL) = (price_unit IS NULL))),
    CONSTRAINT pro_offerings_price_unit_check CHECK (((price_unit IS NULL) OR (price_unit = ANY (ARRAY['person'::text, 'group'::text])))),
    CONSTRAINT pro_offerings_schedule_text_check CHECK (((schedule_text IS NULL) OR (char_length(schedule_text) <= 100))),
    CONSTRAINT pro_offerings_title_check CHECK (((char_length(TRIM(BOTH FROM title)) >= 3) AND (char_length(TRIM(BOTH FROM title)) <= 100)))
);

ALTER TABLE ONLY public.pro_offerings FORCE ROW LEVEL SECURITY;


--
-- Name: pro_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_profiles (
    user_id uuid NOT NULL,
    display_name text NOT NULL,
    tagline text,
    description text,
    website text,
    email text,
    phone text,
    instagram text,
    facebook text,
    primary_lng double precision NOT NULL,
    primary_lat double precision NOT NULL,
    primary_location extensions.geography(Point,4326) NOT NULL,
    primary_location_name text NOT NULL,
    last_location_change_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    pin_image_url text,
    status text DEFAULT 'pending'::text NOT NULL,
    company_name text,
    real_name text,
    rejection_reason text,
    reviewed_at timestamp with time zone,
    reviewed_by uuid,
    pin_icon text,
    is_demo boolean DEFAULT false NOT NULL,
    CONSTRAINT pro_profiles_company_name_check CHECK (((company_name IS NULL) OR ((char_length(company_name) >= 2) AND (char_length(company_name) <= 120)))),
    CONSTRAINT pro_profiles_description_check CHECK (((description IS NULL) OR (char_length(description) <= 2000))),
    CONSTRAINT pro_profiles_display_name_check CHECK (((char_length(display_name) >= 1) AND (char_length(display_name) <= 100))),
    CONSTRAINT pro_profiles_email_check CHECK (((email IS NULL) OR (char_length(email) <= 200))),
    CONSTRAINT pro_profiles_facebook_check CHECK (((facebook IS NULL) OR (char_length(facebook) <= 200))),
    CONSTRAINT pro_profiles_instagram_check CHECK (((instagram IS NULL) OR (char_length(instagram) <= 100))),
    CONSTRAINT pro_profiles_phone_check CHECK (((phone IS NULL) OR (char_length(phone) <= 30))),
    CONSTRAINT pro_profiles_pin_icon_check CHECK (((pin_icon IS NULL) OR (pin_icon = ANY (ARRAY['mountain'::text, 'water'::text, 'air'::text, 'cycling'::text, 'wellness'::text])))),
    CONSTRAINT pro_profiles_pin_image_url_check CHECK (((pin_image_url IS NULL) OR (char_length(pin_image_url) <= 500))),
    CONSTRAINT pro_profiles_primary_lat_check CHECK (((primary_lat >= ('-90'::integer)::double precision) AND (primary_lat <= (90)::double precision))),
    CONSTRAINT pro_profiles_primary_lng_check CHECK (((primary_lng >= ('-180'::integer)::double precision) AND (primary_lng <= (180)::double precision))),
    CONSTRAINT pro_profiles_primary_location_name_check CHECK (((char_length(primary_location_name) >= 1) AND (char_length(primary_location_name) <= 200))),
    CONSTRAINT pro_profiles_real_name_check CHECK (((real_name IS NULL) OR ((char_length(real_name) >= 2) AND (char_length(real_name) <= 120)))),
    CONSTRAINT pro_profiles_rejection_reason_check CHECK (((rejection_reason IS NULL) OR (char_length(rejection_reason) <= 500))),
    CONSTRAINT pro_profiles_social_no_scheme CHECK ((((facebook IS NULL) OR (facebook !~* '^[a-z][a-z0-9+.-]*:'::text) OR (facebook ~* '^https?://'::text)) AND ((instagram IS NULL) OR (instagram !~* '^[a-z][a-z0-9+.-]*:'::text) OR (instagram ~* '^https?://'::text)))),
    CONSTRAINT pro_profiles_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]))),
    CONSTRAINT pro_profiles_tagline_check CHECK (((tagline IS NULL) OR (char_length(tagline) <= 120))),
    CONSTRAINT pro_profiles_website_check CHECK (((website IS NULL) OR (char_length(website) <= 200))),
    CONSTRAINT pro_profiles_website_http CHECK (((website IS NULL) OR (website ~* '^https?://[^[:space:]]+$'::text)))
);

ALTER TABLE ONLY public.pro_profiles FORCE ROW LEVEL SECURITY;


--
-- Name: offering_review_stats; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.offering_review_stats AS
 SELECT r.offering_id,
    (count(*))::integer AS review_count,
    (avg(r.rating))::numeric(3,2) AS avg_rating
   FROM (public.offering_reviews r
     JOIN public.pro_offerings o ON ((o.id = r.offering_id)))
  WHERE ((NOT private.user_is_suspended(r.reviewer_id)) AND (NOT private.user_is_suspended(o.pro_id)) AND ((o.is_demo = false) OR public.demo_content_visible()) AND (EXISTS ( SELECT 1
           FROM public.pro_profiles pp_appr
          WHERE ((pp_appr.user_id = o.pro_id) AND (pp_appr.status = 'approved'::text)))))
  GROUP BY r.offering_id;


--
-- Name: offering_reviews_with_profiles; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.offering_reviews_with_profiles AS
 SELECT r.id,
    r.offering_id,
    r.reviewer_id,
    r.rating,
    r.body,
    r.pro_reply,
    r.pro_reply_at,
    r.created_at,
    r.updated_at,
    pp.display_name AS reviewer_name,
    pp.avatar_url AS reviewer_avatar
   FROM ((public.offering_reviews r
     JOIN public.public_profiles pp ON ((pp.id = r.reviewer_id)))
     JOIN public.pro_offerings o ON ((o.id = r.offering_id)))
  WHERE ((NOT private.user_is_suspended(r.reviewer_id)) AND (NOT private.user_is_suspended(o.pro_id)) AND ((o.is_demo = false) OR public.demo_content_visible()) AND (EXISTS ( SELECT 1
           FROM public.pro_profiles pp_appr
          WHERE ((pp_appr.user_id = o.pro_id) AND (pp_appr.status = 'approved'::text)))));


--
-- Name: presence_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.presence_tokens (
    token text NOT NULL,
    activity_id uuid NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.presence_tokens FORCE ROW LEVEL SECURITY;


--
-- Name: pro_availabilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_availabilities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    day date NOT NULL,
    period text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pro_availabilities_period_check CHECK ((period = ANY (ARRAY['am'::text, 'pm'::text])))
);

ALTER TABLE ONLY public.pro_availabilities FORCE ROW LEVEL SECURITY;


--
-- Name: pro_community_photos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_community_photos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    contributor_id uuid NOT NULL,
    photo_url text NOT NULL,
    review_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    offering_id uuid,
    CONSTRAINT pro_community_photos_photo_url_check CHECK (((char_length(photo_url) >= 1) AND (char_length(photo_url) <= 500)))
);

ALTER TABLE ONLY public.pro_community_photos FORCE ROW LEVEL SECURITY;


--
-- Name: pro_offering_photos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_offering_photos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    offering_id uuid NOT NULL,
    photo_url text NOT NULL,
    order_index integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pro_offering_photos_order_index_check CHECK ((order_index >= 0)),
    CONSTRAINT pro_offering_photos_photo_url_check CHECK (((char_length(photo_url) >= 1) AND (char_length(photo_url) <= 500)))
);

ALTER TABLE ONLY public.pro_offering_photos FORCE ROW LEVEL SECURITY;


--
-- Name: pro_offerings_with_coords; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.pro_offerings_with_coords AS
 SELECT o.id,
    o.pro_id,
    o.sport_id,
    o.title,
    o.description,
    o.level,
    o.location_name,
    o.duration,
    o.max_participants,
    o.schedule_text,
    o.distance_km,
    o.elevation_gain_m,
    ( SELECT p.photo_url
           FROM public.pro_offering_photos p
          WHERE (p.offering_id = o.id)
          ORDER BY p.order_index
         LIMIT 1) AS image_url,
    o.created_at,
    o.updated_at,
    extensions.st_x((o.location)::extensions.geometry) AS lng,
    extensions.st_y((o.location)::extensions.geometry) AS lat,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    pp.display_name AS pro_name,
    o.price_eur,
    o.price_unit,
    o.min_participants,
    o.equipment_provided,
    o.equipment_required,
    o.participant_fields
   FROM ((public.pro_offerings o
     JOIN public.sports s ON ((o.sport_id = s.id)))
     JOIN public.pro_profiles pp ON ((o.pro_id = pp.user_id)))
  WHERE ((NOT (EXISTS ( SELECT 1
           FROM public.users u
          WHERE ((u.id = o.pro_id) AND (u.suspended_at IS NOT NULL))))) AND ((o.is_demo = false) OR public.demo_content_visible()) AND ((pp.status = 'approved'::text) OR (o.pro_id = auth.uid())));


--
-- Name: pro_profile_photos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_profile_photos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    photo_url text NOT NULL,
    order_index integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pro_profile_photos_order_index_check CHECK ((order_index >= 0)),
    CONSTRAINT pro_profile_photos_photo_url_check CHECK (((char_length(photo_url) >= 1) AND (char_length(photo_url) <= 500)))
);

ALTER TABLE ONLY public.pro_profile_photos FORCE ROW LEVEL SECURITY;


--
-- Name: pro_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    rating smallint NOT NULL,
    body text,
    pro_reply text,
    pro_reply_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pro_reviews_body_check CHECK (((body IS NULL) OR (char_length(body) <= 1000))),
    CONSTRAINT pro_reviews_pro_reply_check CHECK (((pro_reply IS NULL) OR (char_length(pro_reply) <= 1000))),
    CONSTRAINT pro_reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);

ALTER TABLE ONLY public.pro_reviews FORCE ROW LEVEL SECURITY;


--
-- Name: pro_review_stats; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.pro_review_stats AS
 SELECT pro_id,
    (count(*))::integer AS review_count,
    (avg(rating))::numeric(3,2) AS avg_rating
   FROM public.pro_reviews r
  WHERE ((NOT private.user_is_suspended(reviewer_id)) AND (NOT private.user_is_suspended(pro_id)) AND (public.demo_content_visible() OR (EXISTS ( SELECT 1
           FROM public.pro_profiles dp
          WHERE ((dp.user_id = r.pro_id) AND (dp.is_demo = false))))))
  GROUP BY pro_id;


--
-- Name: pro_reviews_with_profiles; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.pro_reviews_with_profiles AS
 SELECT r.id,
    r.pro_id,
    r.reviewer_id,
    r.rating,
    r.body,
    r.pro_reply,
    r.pro_reply_at,
    r.created_at,
    r.updated_at,
    pp.display_name AS reviewer_name,
    pp.avatar_url AS reviewer_avatar
   FROM (public.pro_reviews r
     JOIN public.public_profiles pp ON ((pp.id = r.reviewer_id)))
  WHERE ((NOT private.user_is_suspended(r.reviewer_id)) AND (NOT private.user_is_suspended(r.pro_id)) AND (public.demo_content_visible() OR (EXISTS ( SELECT 1
           FROM public.pro_profiles dp
          WHERE ((dp.user_id = r.pro_id) AND (dp.is_demo = false))))));


--
-- Name: push_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_tokens (
    user_id uuid NOT NULL,
    token text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    device_id text
);

ALTER TABLE ONLY public.push_tokens FORCE ROW LEVEL SECURITY;


--
-- Name: rate_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rate_events (
    user_id uuid NOT NULL,
    kind text NOT NULL,
    at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rate_events_kind_check CHECK (((char_length(kind) >= 1) AND (char_length(kind) <= 40)))
);

ALTER TABLE ONLY public.rate_events FORCE ROW LEVEL SECURITY;


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reporter_id uuid,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    reason text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    admin_note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    CONSTRAINT reports_reason_check CHECK (((char_length(reason) >= 10) AND (char_length(reason) <= 1000))),
    CONSTRAINT reports_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'dismissed'::text, 'actioned'::text]))),
    CONSTRAINT reports_target_type_check CHECK ((target_type = ANY (ARRAY['user'::text, 'activity'::text, 'pro_review'::text, 'offering_review'::text, 'message'::text, 'group'::text, 'channel'::text])))
);

ALTER TABLE ONLY public.reports FORCE ROW LEVEL SECURITY;


--
-- Name: reputation_votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reputation_votes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    voter_id uuid NOT NULL,
    voted_id uuid NOT NULL,
    activity_id uuid NOT NULL,
    badge_key text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    counted_at timestamp with time zone
);

ALTER TABLE ONLY public.reputation_votes FORCE ROW LEVEL SECURITY;


--
-- Name: seat_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seat_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    activity_id uuid NOT NULL,
    requester_id uuid NOT NULL,
    driver_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pickup_from text,
    message text,
    requested_pickup_at timestamp with time zone,
    CONSTRAINT seat_requests_check CHECK ((requester_id <> driver_id)),
    CONSTRAINT seat_requests_message_check CHECK (((message IS NULL) OR ((char_length(message) >= 1) AND (char_length(message) <= 500)))),
    CONSTRAINT seat_requests_pickup_from_check CHECK (((pickup_from IS NULL) OR ((char_length(pickup_from) >= 1) AND (char_length(pickup_from) <= 100)))),
    CONSTRAINT seat_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text, 'cancelled'::text, 'expired'::text])))
);

ALTER TABLE ONLY public.seat_requests FORCE ROW LEVEL SECURITY;


--
-- Name: snap_trail_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.snap_trail_calls (
    user_id uuid NOT NULL,
    called_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.snap_trail_calls FORCE ROW LEVEL SECURITY;


--
-- Name: trace_elevation_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trace_elevation_calls (
    user_id uuid NOT NULL,
    called_at timestamp with time zone DEFAULT now() NOT NULL,
    points integer DEFAULT 0 NOT NULL,
    CONSTRAINT trace_elevation_calls_points_check CHECK (((points >= 0) AND (points <= 10000)))
);

ALTER TABLE ONLY public.trace_elevation_calls FORCE ROW LEVEL SECURITY;


--
-- Name: user_badge_progression; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_badge_progression (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    category text NOT NULL,
    sport_key text,
    tier_key text NOT NULL,
    awarded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_badge_progression_category_check CHECK ((category = ANY (ARRAY['joined'::text, 'created'::text]))),
    CONSTRAINT user_badge_progression_tier_key_check CHECK ((tier_key = ANY (ARRAY['bronze'::text, 'silver'::text, 'gold'::text])))
);

ALTER TABLE ONLY public.user_badge_progression FORCE ROW LEVEL SECURITY;


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (id);


--
-- Name: activity_alerts activity_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_alerts
    ADD CONSTRAINT activity_alerts_pkey PRIMARY KEY (id);


--
-- Name: activity_gear activity_gear_activity_id_user_id_gear_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_gear
    ADD CONSTRAINT activity_gear_activity_id_user_id_gear_name_key UNIQUE (activity_id, user_id, gear_name);


--
-- Name: activity_gear_missing activity_gear_missing_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_gear_missing
    ADD CONSTRAINT activity_gear_missing_pkey PRIMARY KEY (id);


--
-- Name: activity_gear activity_gear_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_gear
    ADD CONSTRAINT activity_gear_pkey PRIMARY KEY (id);


--
-- Name: admin_actions admin_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_actions
    ADD CONSTRAINT admin_actions_pkey PRIMARY KEY (id);


--
-- Name: app_config app_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_config
    ADD CONSTRAINT app_config_pkey PRIMARY KEY (name);


--
-- Name: banned_email_hashes banned_email_hashes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banned_email_hashes
    ADD CONSTRAINT banned_email_hashes_pkey PRIMARY KEY (email_hash);


--
-- Name: blocked_users blocked_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_users
    ADD CONSTRAINT blocked_users_pkey PRIMARY KEY (blocker_id, blocked_id);


--
-- Name: bookings bookings_offering_id_client_id_day_period_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_offering_id_client_id_day_period_key UNIQUE (offering_id, client_id, day, period);


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (id);


--
-- Name: channel_bans channel_bans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_bans
    ADD CONSTRAINT channel_bans_pkey PRIMARY KEY (conversation_id, user_id);


--
-- Name: channels channels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_pkey PRIMARY KEY (conversation_id);


--
-- Name: contact_qr_tokens contact_qr_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_qr_tokens
    ADD CONSTRAINT contact_qr_tokens_pkey PRIMARY KEY (token);


--
-- Name: contact_removal_archive contact_removal_archive_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_removal_archive
    ADD CONSTRAINT contact_removal_archive_pkey PRIMARY KEY (id);


--
-- Name: conversation_departures conversation_departures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_departures
    ADD CONSTRAINT conversation_departures_pkey PRIMARY KEY (conversation_id, user_id);


--
-- Name: conversation_members conversation_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_members
    ADD CONSTRAINT conversation_members_pkey PRIMARY KEY (conversation_id, user_id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_user_1_user_2_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_user_1_user_2_key UNIQUE (user_1, user_2);


--
-- Name: discovery_availabilities discovery_availabilities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_availabilities
    ADD CONSTRAINT discovery_availabilities_pkey PRIMARY KEY (id);


--
-- Name: favorites favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_pkey PRIMARY KEY (id);


--
-- Name: gear_catalog gear_catalog_name_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gear_catalog
    ADD CONSTRAINT gear_catalog_name_key_key UNIQUE (name_key);


--
-- Name: gear_catalog gear_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gear_catalog
    ADD CONSTRAINT gear_catalog_pkey PRIMARY KEY (id);


--
-- Name: gpx_traces gpx_traces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gpx_traces
    ADD CONSTRAINT gpx_traces_pkey PRIMARY KEY (id);


--
-- Name: invitation_declines invitation_declines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitation_declines
    ADD CONSTRAINT invitation_declines_pkey PRIMARY KEY (activity_id, user_id);


--
-- Name: invite_grants invite_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invite_grants
    ADD CONSTRAINT invite_grants_pkey PRIMARY KEY (user_id, activity_id);


--
-- Name: late_cancels late_cancels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.late_cancels
    ADD CONSTRAINT late_cancels_pkey PRIMARY KEY (user_id, activity_id);


--
-- Name: map_broadcasts map_broadcasts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_broadcasts
    ADD CONSTRAINT map_broadcasts_pkey PRIMARY KEY (activity_id);


--
-- Name: message_original_content message_original_content_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_original_content
    ADD CONSTRAINT message_original_content_pkey PRIMARY KEY (message_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: offering_reviews offering_reviews_offering_id_reviewer_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offering_reviews
    ADD CONSTRAINT offering_reviews_offering_id_reviewer_id_key UNIQUE (offering_id, reviewer_id);


--
-- Name: offering_reviews offering_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offering_reviews
    ADD CONSTRAINT offering_reviews_pkey PRIMARY KEY (id);


--
-- Name: participations participations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participations
    ADD CONSTRAINT participations_pkey PRIMARY KEY (id);


--
-- Name: participations participations_user_id_activity_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participations
    ADD CONSTRAINT participations_user_id_activity_id_key UNIQUE (user_id, activity_id);


--
-- Name: presence_tokens presence_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presence_tokens
    ADD CONSTRAINT presence_tokens_pkey PRIMARY KEY (token);


--
-- Name: pro_availabilities pro_availabilities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_availabilities
    ADD CONSTRAINT pro_availabilities_pkey PRIMARY KEY (id);


--
-- Name: pro_availabilities pro_availabilities_pro_id_day_period_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_availabilities
    ADD CONSTRAINT pro_availabilities_pro_id_day_period_key UNIQUE (pro_id, day, period);


--
-- Name: pro_community_photos pro_community_photos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_community_photos
    ADD CONSTRAINT pro_community_photos_pkey PRIMARY KEY (id);


--
-- Name: pro_offering_photos pro_offering_photos_offering_id_order_index_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_offering_photos
    ADD CONSTRAINT pro_offering_photos_offering_id_order_index_key UNIQUE (offering_id, order_index);


--
-- Name: pro_offering_photos pro_offering_photos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_offering_photos
    ADD CONSTRAINT pro_offering_photos_pkey PRIMARY KEY (id);


--
-- Name: pro_offerings pro_offerings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_offerings
    ADD CONSTRAINT pro_offerings_pkey PRIMARY KEY (id);


--
-- Name: pro_profile_photos pro_profile_photos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_profile_photos
    ADD CONSTRAINT pro_profile_photos_pkey PRIMARY KEY (id);


--
-- Name: pro_profile_photos pro_profile_photos_pro_id_order_index_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_profile_photos
    ADD CONSTRAINT pro_profile_photos_pro_id_order_index_key UNIQUE (pro_id, order_index);


--
-- Name: pro_profiles pro_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_profiles
    ADD CONSTRAINT pro_profiles_pkey PRIMARY KEY (user_id);


--
-- Name: pro_reviews pro_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_reviews
    ADD CONSTRAINT pro_reviews_pkey PRIMARY KEY (id);


--
-- Name: pro_reviews pro_reviews_pro_id_reviewer_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_reviews
    ADD CONSTRAINT pro_reviews_pro_id_reviewer_id_key UNIQUE (pro_id, reviewer_id);


--
-- Name: push_tokens push_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_pkey PRIMARY KEY (user_id, token);


--
-- Name: push_tokens push_tokens_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_token_key UNIQUE (token);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: reputation_votes reputation_votes_check; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.reputation_votes
    ADD CONSTRAINT reputation_votes_check CHECK ((voter_id <> voted_id)) NOT VALID;


--
-- Name: reputation_votes reputation_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reputation_votes
    ADD CONSTRAINT reputation_votes_pkey PRIMARY KEY (id);


--
-- Name: reputation_votes reputation_votes_voter_id_voted_id_activity_id_badge_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reputation_votes
    ADD CONSTRAINT reputation_votes_voter_id_voted_id_activity_id_badge_key_key UNIQUE (voter_id, voted_id, activity_id, badge_key);


--
-- Name: seat_requests seat_requests_activity_id_requester_id_driver_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seat_requests
    ADD CONSTRAINT seat_requests_activity_id_requester_id_driver_id_key UNIQUE (activity_id, requester_id, driver_id);


--
-- Name: seat_requests seat_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seat_requests
    ADD CONSTRAINT seat_requests_pkey PRIMARY KEY (id);


--
-- Name: sports sports_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sports
    ADD CONSTRAINT sports_key_key UNIQUE (key);


--
-- Name: sports sports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sports
    ADD CONSTRAINT sports_pkey PRIMARY KEY (id);


--
-- Name: user_badge_progression user_badge_progression_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_badge_progression
    ADD CONSTRAINT user_badge_progression_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: activities_location_meeting_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX activities_location_meeting_idx ON public.activities USING gist (location_meeting);


--
-- Name: activities_status_starts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX activities_status_starts_idx ON public.activities USING btree (status, starts_at DESC) WHERE (deleted_at IS NULL);


--
-- Name: bookings_client_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_client_idx ON public.bookings USING btree (client_id) WHERE (client_id IS NOT NULL);


--
-- Name: bookings_pro_day_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_pro_day_idx ON public.bookings USING btree (pro_id, day);


--
-- Name: channels_base_gist; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_base_gist ON public.channels USING gist (base);


--
-- Name: channels_sport_key_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channels_sport_key_idx ON public.channels USING btree (sport_key);


--
-- Name: contact_qr_scans_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_qr_scans_user_idx ON public.contact_qr_scans USING btree (user_id, scanned_at DESC);


--
-- Name: contact_qr_tokens_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_qr_tokens_user_idx ON public.contact_qr_tokens USING btree (user_id, created_at DESC);


--
-- Name: contact_removal_archive_removed_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_removal_archive_removed_at_idx ON public.contact_removal_archive USING btree (removed_at);


--
-- Name: conversation_members_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX conversation_members_user_idx ON public.conversation_members USING btree (user_id);


--
-- Name: conversations_activity_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX conversations_activity_unique ON public.conversations USING btree (activity_id) WHERE (activity_id IS NOT NULL);


--
-- Name: discovery_active_base_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discovery_active_base_gix ON public.discovery_availabilities USING gist (base) WHERE is_active;


--
-- Name: discovery_availabilities_intent_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discovery_availabilities_intent_gin ON public.discovery_availabilities USING gin (intent);


--
-- Name: discovery_availabilities_one_per_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX discovery_availabilities_one_per_user ON public.discovery_availabilities USING btree (user_id);


--
-- Name: discovery_one_active_per_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX discovery_one_active_per_user ON public.discovery_availabilities USING btree (user_id) WHERE is_active;


--
-- Name: favorites_owner_activity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX favorites_owner_activity ON public.favorites USING btree (owner_id, activity_id) WHERE (activity_id IS NOT NULL);


--
-- Name: favorites_owner_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX favorites_owner_idx ON public.favorites USING btree (owner_id, created_at DESC);


--
-- Name: favorites_owner_offering; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX favorites_owner_offering ON public.favorites USING btree (owner_id, offering_id) WHERE (offering_id IS NOT NULL);


--
-- Name: favorites_owner_pro; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX favorites_owner_pro ON public.favorites USING btree (owner_id, pro_id) WHERE (pro_id IS NOT NULL);


--
-- Name: idx_activity_alerts_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_alerts_location ON public.activity_alerts USING gist (location);


--
-- Name: idx_activity_alerts_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_alerts_user ON public.activity_alerts USING btree (user_id);


--
-- Name: idx_admin_actions_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_actions_created ON public.admin_actions USING btree (created_at DESC);


--
-- Name: idx_admin_actions_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_actions_target ON public.admin_actions USING btree (target_type, target_id);


--
-- Name: idx_conversations_user2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_user2 ON public.conversations USING btree (user_2);


--
-- Name: idx_gear_catalog_category_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gear_catalog_category_key ON public.gear_catalog USING btree (category_key);


--
-- Name: idx_gpx_traces_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gpx_traces_user ON public.gpx_traces USING btree (user_id, created_at DESC);


--
-- Name: idx_notif_presence_confirmed_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_notif_presence_confirmed_dedup ON public.notifications USING btree (user_id, type, ((data ->> 'activity_id'::text))) WHERE (type = 'presence_confirmed'::text);


--
-- Name: idx_notif_presence_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_notif_presence_dedup ON public.notifications USING btree (user_id, type, ((data ->> 'activity_id'::text))) WHERE (type = ANY (ARRAY['presence_pre_warning'::text, 'presence_pre_warning_10min'::text, 'presence_validate_warning'::text, 'presence_validate_overdue'::text, 'presence_validate_final'::text, 'qr_create_reminder'::text, 'peer_review_closing'::text, 'rate_participants'::text]));


--
-- Name: idx_presence_tokens_activity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_presence_tokens_activity ON public.presence_tokens USING btree (activity_id);


--
-- Name: idx_reports_reporter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reports_reporter ON public.reports USING btree (reporter_id);


--
-- Name: idx_reports_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reports_status ON public.reports USING btree (status);


--
-- Name: idx_reputation_votes_counted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reputation_votes_counted ON public.reputation_votes USING btree (voted_id) WHERE (counted_at IS NOT NULL);


--
-- Name: idx_reputation_votes_voted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reputation_votes_voted ON public.reputation_votes USING btree (voted_id);


--
-- Name: idx_ubp_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_ubp_unique ON public.user_badge_progression USING btree (user_id, category, COALESCE(sport_key, ''::text), tier_key);


--
-- Name: idx_ubp_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ubp_user ON public.user_badge_progression USING btree (user_id);


--
-- Name: late_cancels_activity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX late_cancels_activity_idx ON public.late_cancels USING btree (activity_id);


--
-- Name: messages_conversation_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_conversation_created_idx ON public.messages USING btree (conversation_id, created_at DESC);


--
-- Name: messages_reply_to_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_reply_to_idx ON public.messages USING btree (reply_to_message_id) WHERE (reply_to_message_id IS NOT NULL);


--
-- Name: messages_sender_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_sender_created_idx ON public.messages USING btree (sender_id, created_at DESC);


--
-- Name: offering_reviews_offering_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX offering_reviews_offering_created_idx ON public.offering_reviews USING btree (offering_id, created_at DESC);


--
-- Name: offering_reviews_reviewer_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX offering_reviews_reviewer_created_idx ON public.offering_reviews USING btree (reviewer_id, created_at DESC);


--
-- Name: participations_activity_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX participations_activity_status_idx ON public.participations USING btree (activity_id, status);


--
-- Name: participations_activity_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX participations_activity_user_idx ON public.participations USING btree (activity_id, user_id);


--
-- Name: pro_community_photos_contributor_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_community_photos_contributor_idx ON public.pro_community_photos USING btree (contributor_id, pro_id);


--
-- Name: pro_community_photos_offering_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_community_photos_offering_idx ON public.pro_community_photos USING btree (offering_id, created_at DESC) WHERE (offering_id IS NOT NULL);


--
-- Name: pro_community_photos_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_community_photos_pro_idx ON public.pro_community_photos USING btree (pro_id, created_at DESC);


--
-- Name: pro_community_photos_review_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_community_photos_review_idx ON public.pro_community_photos USING btree (review_id);


--
-- Name: pro_offerings_location_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_offerings_location_idx ON public.pro_offerings USING gist (location);


--
-- Name: pro_offerings_pro_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_offerings_pro_created_idx ON public.pro_offerings USING btree (pro_id, created_at DESC);


--
-- Name: pro_profiles_location_gist; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_profiles_location_gist ON public.pro_profiles USING gist (primary_location);


--
-- Name: pro_reviews_pro_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_reviews_pro_created_idx ON public.pro_reviews USING btree (pro_id, created_at DESC);


--
-- Name: pro_reviews_reviewer_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_reviews_reviewer_created_idx ON public.pro_reviews USING btree (reviewer_id, created_at DESC);


--
-- Name: push_tokens_user_device_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX push_tokens_user_device_idx ON public.push_tokens USING btree (user_id, device_id) WHERE (device_id IS NOT NULL);


--
-- Name: rate_events_user_kind_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX rate_events_user_kind_at_idx ON public.rate_events USING btree (user_id, kind, at DESC);


--
-- Name: reports_one_per_target; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reports_one_per_target ON public.reports USING btree (reporter_id, target_type, target_id);


--
-- Name: seat_requests_one_accepted_per_passenger; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX seat_requests_one_accepted_per_passenger ON public.seat_requests USING btree (activity_id, requester_id) WHERE (status = 'accepted'::text);


--
-- Name: snap_trail_calls_called_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX snap_trail_calls_called_at_idx ON public.snap_trail_calls USING btree (called_at);


--
-- Name: snap_trail_calls_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX snap_trail_calls_user_idx ON public.snap_trail_calls USING btree (user_id, called_at DESC);


--
-- Name: trace_elevation_calls_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX trace_elevation_calls_user_idx ON public.trace_elevation_calls USING btree (user_id, called_at DESC);


--
-- Name: ux_gear_missing_activity_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_gear_missing_activity_name ON public.activity_gear_missing USING btree (activity_id, lower(name));


--
-- Name: activities activities_strip_html; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER activities_strip_html BEFORE INSERT OR UPDATE ON public.activities FOR EACH ROW EXECUTE FUNCTION public.strip_html_tags();


--
-- Name: bookings bookings_whitelist_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bookings_whitelist_trg BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.bookings_whitelist_columns();


--
-- Name: bookings bookings_zz_clear_participant_info; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bookings_zz_clear_participant_info BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.bookings_clear_participant_info();


--
-- Name: channels channels_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER channels_lock_privileged BEFORE UPDATE ON public.channels FOR EACH ROW EXECUTE FUNCTION public.channels_whitelist_columns();


--
-- Name: conversation_members conversation_members_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER conversation_members_lock_privileged BEFORE UPDATE ON public.conversation_members FOR EACH ROW EXECUTE FUNCTION public.conversation_members_whitelist_columns();


--
-- Name: conversations conversations_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER conversations_lock_privileged BEFORE UPDATE ON public.conversations FOR EACH ROW EXECUTE FUNCTION public.conversations_whitelist_columns();


--
-- Name: discovery_availabilities discovery_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER discovery_lock_privileged BEFORE UPDATE ON public.discovery_availabilities FOR EACH ROW EXECUTE FUNCTION public.discovery_availabilities_whitelist_columns();


--
-- Name: messages messages_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER messages_lock_privileged BEFORE UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION public.messages_whitelist_columns();


--
-- Name: messages messages_no_closed_channel; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER messages_no_closed_channel BEFORE INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.messages_block_closed_channel();


--
-- Name: messages messages_strip_html; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER messages_strip_html BEFORE INSERT OR UPDATE OF content ON public.messages FOR EACH ROW EXECUTE FUNCTION public.strip_html_messages();


--
-- Name: offering_reviews offering_reviews_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER offering_reviews_lock_privileged BEFORE UPDATE ON public.offering_reviews FOR EACH ROW EXECUTE FUNCTION public.offering_reviews_whitelist_columns();


--
-- Name: offering_reviews offering_reviews_strip_html; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER offering_reviews_strip_html BEFORE INSERT OR UPDATE ON public.offering_reviews FOR EACH ROW EXECUTE FUNCTION public.strip_html_reviews();


--
-- Name: offering_reviews offering_reviews_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER offering_reviews_touch_updated_at BEFORE UPDATE ON public.offering_reviews FOR EACH ROW EXECUTE FUNCTION public.reviews_touch_updated_at();


--
-- Name: activities on_activity_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_activity_update BEFORE UPDATE ON public.activities FOR EACH ROW EXECUTE FUNCTION public.handle_activity_update();


--
-- Name: notifications on_notification_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_notification_update BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.handle_notification_update();


--
-- Name: users on_user_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_user_update BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.handle_user_update();


--
-- Name: pro_availabilities pro_availabilities_whitelist_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_availabilities_whitelist_trg BEFORE UPDATE ON public.pro_availabilities FOR EACH ROW EXECUTE FUNCTION public.pro_availabilities_whitelist_columns();


--
-- Name: pro_community_photos pro_community_photos_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_community_photos_lock_privileged BEFORE UPDATE ON public.pro_community_photos FOR EACH ROW EXECUTE FUNCTION public.pro_community_photos_whitelist_columns();


--
-- Name: pro_offering_photos pro_offering_photos_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_offering_photos_lock_privileged BEFORE UPDATE ON public.pro_offering_photos FOR EACH ROW EXECUTE FUNCTION public.pro_offering_photos_whitelist_columns();


--
-- Name: pro_offerings pro_offerings_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_offerings_lock_privileged BEFORE UPDATE ON public.pro_offerings FOR EACH ROW EXECUTE FUNCTION public.pro_offerings_whitelist_columns();


--
-- Name: pro_offerings pro_offerings_require_approved_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_offerings_require_approved_trg BEFORE INSERT ON public.pro_offerings FOR EACH ROW EXECUTE FUNCTION public.pro_offerings_require_approved();


--
-- Name: pro_offerings pro_offerings_touch_updated_at_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_offerings_touch_updated_at_trg BEFORE UPDATE ON public.pro_offerings FOR EACH ROW EXECUTE FUNCTION public.pro_offerings_touch_updated_at();


--
-- Name: pro_profile_photos pro_profile_photos_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_profile_photos_lock_privileged BEFORE UPDATE ON public.pro_profile_photos FOR EACH ROW EXECUTE FUNCTION public.pro_profile_photos_whitelist_columns();


--
-- Name: pro_profiles pro_profiles_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_profiles_lock_privileged BEFORE UPDATE ON public.pro_profiles FOR EACH ROW EXECUTE FUNCTION public.pro_profiles_whitelist_columns();


--
-- Name: pro_profiles pro_profiles_touch_updated_at_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_profiles_touch_updated_at_trg BEFORE UPDATE ON public.pro_profiles FOR EACH ROW EXECUTE FUNCTION public.pro_profiles_touch_updated_at();


--
-- Name: pro_reviews pro_reviews_lock_privileged; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_reviews_lock_privileged BEFORE UPDATE ON public.pro_reviews FOR EACH ROW EXECUTE FUNCTION public.pro_reviews_whitelist_columns();


--
-- Name: pro_reviews pro_reviews_require_approved_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_reviews_require_approved_trg BEFORE INSERT ON public.pro_reviews FOR EACH ROW EXECUTE FUNCTION public.pro_reviews_require_approved();


--
-- Name: pro_reviews pro_reviews_strip_html; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_reviews_strip_html BEFORE INSERT OR UPDATE ON public.pro_reviews FOR EACH ROW EXECUTE FUNCTION public.strip_html_reviews();


--
-- Name: pro_reviews pro_reviews_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_reviews_touch_updated_at BEFORE UPDATE ON public.pro_reviews FOR EACH ROW EXECUTE FUNCTION public.reviews_touch_updated_at();


--
-- Name: activities trg_activities_map_broadcast; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activities_map_broadcast AFTER INSERT OR DELETE OR UPDATE ON public.activities FOR EACH ROW EXECUTE FUNCTION public.broadcast_map_activity();


--
-- Name: activities trg_activities_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activities_onboarded BEFORE INSERT ON public.activities FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: activities trg_activity_conversation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_conversation AFTER INSERT ON public.activities FOR EACH ROW EXECUTE FUNCTION public.create_activity_conversation();


--
-- Name: activities trg_activity_finished_expire_seat_requests; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_finished_expire_seat_requests AFTER UPDATE OF status ON public.activities FOR EACH ROW EXECUTE FUNCTION public.on_activity_finished_expire_seat_requests();


--
-- Name: activity_gear trg_activity_gear_bc_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_gear_bc_del AFTER DELETE ON public.activity_gear REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.broadcast_activity_change_stmt();


--
-- Name: activity_gear trg_activity_gear_bc_ins; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_gear_bc_ins AFTER INSERT ON public.activity_gear REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.broadcast_activity_change_stmt();


--
-- Name: activity_gear trg_activity_gear_bc_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_gear_bc_upd AFTER UPDATE ON public.activity_gear REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.broadcast_activity_change_stmt();


--
-- Name: activity_gear_missing trg_activity_gear_missing_bc_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_gear_missing_bc_del AFTER DELETE ON public.activity_gear_missing REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.broadcast_activity_change_stmt();


--
-- Name: activity_gear_missing trg_activity_gear_missing_bc_ins; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_gear_missing_bc_ins AFTER INSERT ON public.activity_gear_missing REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.broadcast_activity_change_stmt();


--
-- Name: activity_gear_missing trg_activity_gear_missing_bc_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_activity_gear_missing_bc_upd AFTER UPDATE ON public.activity_gear_missing REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.broadcast_activity_change_stmt();


--
-- Name: activities trg_award_badges_on_complete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_award_badges_on_complete AFTER UPDATE OF status ON public.activities FOR EACH ROW EXECUTE FUNCTION public.on_activity_completed_award_badges();


--
-- Name: blocked_users trg_block_cascade_requests; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_block_cascade_requests AFTER INSERT ON public.blocked_users FOR EACH ROW EXECUTE FUNCTION public.cascade_block_to_requests();


--
-- Name: blocked_users trg_blocked_users_cascade; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_blocked_users_cascade AFTER INSERT ON public.blocked_users FOR EACH ROW EXECUTE FUNCTION public.cascade_block_cleanup();


--
-- Name: bookings trg_bookings_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_bookings_onboarded BEFORE INSERT ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: blocked_users trg_cascade_block_invited; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cascade_block_invited AFTER INSERT ON public.blocked_users FOR EACH ROW EXECUTE FUNCTION public.cascade_block_invited();


--
-- Name: conversations trg_cleanup_notifications_on_conversation_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cleanup_notifications_on_conversation_delete AFTER DELETE ON public.conversations FOR EACH ROW EXECUTE FUNCTION public.cleanup_notifications_on_conversation_delete();


--
-- Name: activity_gear trg_clear_missing_on_shared_gear; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_clear_missing_on_shared_gear AFTER INSERT ON public.activity_gear FOR EACH ROW EXECUTE FUNCTION public.clear_missing_on_shared_gear();


--
-- Name: users trg_clear_push_on_suspension; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_clear_push_on_suspension AFTER UPDATE OF suspended_at ON public.users FOR EACH ROW WHEN (((old.suspended_at IS NULL) AND (new.suspended_at IS NOT NULL))) EXECUTE FUNCTION public.clear_push_token_on_suspension();


--
-- Name: contact_qr_tokens trg_contact_qr_tokens_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contact_qr_tokens_onboarded BEFORE INSERT ON public.contact_qr_tokens FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: conversation_members trg_conversation_members_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_conversation_members_onboarded BEFORE INSERT ON public.conversation_members FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: conversations trg_conversations_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_conversations_onboarded BEFORE INSERT ON public.conversations FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: discovery_availabilities trg_discovery_availabilities_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_discovery_availabilities_onboarded BEFORE INSERT ON public.discovery_availabilities FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: conversations trg_dm_member_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_dm_member_rows AFTER INSERT ON public.conversations FOR EACH ROW EXECUTE FUNCTION public.create_dm_member_rows();


--
-- Name: activities trg_expire_invited; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_expire_invited AFTER UPDATE OF status ON public.activities FOR EACH ROW EXECUTE FUNCTION public.expire_invited_on_activity_end();


--
-- Name: gpx_traces trg_gpx_traces_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_gpx_traces_onboarded BEFORE INSERT ON public.gpx_traces FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: messages trg_messages_broadcast_push; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_messages_broadcast_push AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.broadcast_and_push_message();


--
-- Name: messages trg_messages_broadcast_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_messages_broadcast_update AFTER UPDATE OF content, deleted_at ON public.messages FOR EACH ROW EXECUTE FUNCTION private.broadcast_message_update();


--
-- Name: messages trg_messages_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_messages_onboarded BEFORE INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: notifications trg_notification_push; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notification_push AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.push_notification_to_device();


--
-- Name: participations trg_participations_accepted_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_participations_accepted_at BEFORE INSERT OR UPDATE OF status ON public.participations FOR EACH ROW EXECUTE FUNCTION private.stamp_accepted_at();


--
-- Name: participations trg_participations_broadcast; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_participations_broadcast AFTER INSERT OR DELETE OR UPDATE ON public.participations FOR EACH ROW EXECUTE FUNCTION public.broadcast_activity_change();


--
-- Name: participations trg_participations_clear_join_request; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_participations_clear_join_request AFTER UPDATE OF status ON public.participations FOR EACH ROW EXECUTE FUNCTION private.clear_stale_join_request();


--
-- Name: participations trg_participations_late_presence_award; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_participations_late_presence_award AFTER UPDATE OF confirmed_present ON public.participations FOR EACH ROW EXECUTE FUNCTION private.award_on_late_presence();


--
-- Name: participations trg_participations_map_broadcast; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_participations_map_broadcast AFTER INSERT OR DELETE OR UPDATE OF status ON public.participations FOR EACH ROW EXECUTE FUNCTION public.broadcast_map_participation();


--
-- Name: participations trg_participations_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_participations_onboarded BEFORE INSERT ON public.participations FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: participations trg_participations_schedule_conflict; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_participations_schedule_conflict BEFORE INSERT OR UPDATE OF status ON public.participations FOR EACH ROW EXECUTE FUNCTION private.check_schedule_conflict();


--
-- Name: participations trg_participations_seat_cleanup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_participations_seat_cleanup AFTER UPDATE OF status ON public.participations FOR EACH ROW EXECUTE FUNCTION private.seat_cleanup_on_participation_loss();


--
-- Name: participations trg_participations_shared_block; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_participations_shared_block BEFORE INSERT OR UPDATE OF status ON public.participations FOR EACH ROW EXECUTE FUNCTION private.check_shared_outing_block();


--
-- Name: pro_profiles trg_pro_profiles_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pro_profiles_onboarded BEFORE INSERT ON public.pro_profiles FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: pro_profiles trg_pro_profiles_renamed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pro_profiles_renamed AFTER UPDATE OF display_name ON public.pro_profiles FOR EACH ROW EXECUTE FUNCTION private.notify_pro_renamed();


--
-- Name: participations trg_recalc_creator_on_participant_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_recalc_creator_on_participant_change AFTER INSERT OR UPDATE OF status ON public.participations FOR EACH ROW EXECUTE FUNCTION public.recalc_creator_on_participant_change();


--
-- Name: reputation_votes trg_reputation_votes_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reputation_votes_onboarded BEFORE INSERT ON public.reputation_votes FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: seat_requests trg_seat_requests_broadcast; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_seat_requests_broadcast AFTER INSERT OR DELETE OR UPDATE ON public.seat_requests FOR EACH ROW EXECUTE FUNCTION public.broadcast_activity_change();


--
-- Name: seat_requests trg_seat_requests_onboarded; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_seat_requests_onboarded BEFORE INSERT ON public.seat_requests FOR EACH ROW EXECUTE FUNCTION private.require_onboarded_actor();


--
-- Name: seat_requests trg_seat_requests_release; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_seat_requests_release AFTER UPDATE OF status ON public.seat_requests FOR EACH ROW EXECUTE FUNCTION private.seat_release_on_end();


--
-- Name: participations trg_sync_activity_membership; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_activity_membership AFTER INSERT OR DELETE OR UPDATE ON public.participations FOR EACH ROW EXECUTE FUNCTION public.sync_activity_membership();


--
-- Name: users trg_users_avatar_url; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_avatar_url BEFORE UPDATE OF avatar_url ON public.users FOR EACH ROW EXECUTE FUNCTION private.check_avatar_url();


--
-- Name: users trg_users_ban_email_on_suspended_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_ban_email_on_suspended_delete BEFORE DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION private.ban_email_on_suspended_delete();


--
-- Name: users trg_users_map_broadcast; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_map_broadcast AFTER UPDATE OF display_name, avatar_url, suspended_at ON public.users FOR EACH ROW WHEN (((new.display_name IS DISTINCT FROM old.display_name) OR (new.avatar_url IS DISTINCT FROM old.avatar_url) OR ((new.suspended_at IS NULL) IS DISTINCT FROM (old.suspended_at IS NULL)))) EXECUTE FUNCTION public.broadcast_map_creator();


--
-- Name: users users_strip_html; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_strip_html BEFORE INSERT OR UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.strip_html_users();


--
-- Name: activities activities_creator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: activities activities_sport_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_sport_id_fkey FOREIGN KEY (sport_id) REFERENCES public.sports(id) ON DELETE RESTRICT;


--
-- Name: activity_alerts activity_alerts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_alerts
    ADD CONSTRAINT activity_alerts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: activity_gear activity_gear_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_gear
    ADD CONSTRAINT activity_gear_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: activity_gear_missing activity_gear_missing_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_gear_missing
    ADD CONSTRAINT activity_gear_missing_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: activity_gear_missing activity_gear_missing_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_gear_missing
    ADD CONSTRAINT activity_gear_missing_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: activity_gear activity_gear_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_gear
    ADD CONSTRAINT activity_gear_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: admin_actions admin_actions_admin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_actions
    ADD CONSTRAINT admin_actions_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: blocked_users blocked_users_blocked_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_users
    ADD CONSTRAINT blocked_users_blocked_id_fkey FOREIGN KEY (blocked_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: blocked_users blocked_users_blocker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_users
    ADD CONSTRAINT blocked_users_blocker_id_fkey FOREIGN KEY (blocker_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.pro_offerings(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: channel_bans channel_bans_banned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_bans
    ADD CONSTRAINT channel_bans_banned_by_fkey FOREIGN KEY (banned_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: channel_bans channel_bans_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_bans
    ADD CONSTRAINT channel_bans_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.channels(conversation_id) ON DELETE CASCADE;


--
-- Name: channel_bans channel_bans_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_bans
    ADD CONSTRAINT channel_bans_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: channels channels_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: channels channels_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: channels channels_sport_key_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_sport_key_fk FOREIGN KEY (sport_key) REFERENCES public.sports(key) ON DELETE SET NULL;


--
-- Name: contact_qr_scans contact_qr_scans_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_qr_scans
    ADD CONSTRAINT contact_qr_scans_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: contact_qr_tokens contact_qr_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_qr_tokens
    ADD CONSTRAINT contact_qr_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: conversation_departures conversation_departures_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_departures
    ADD CONSTRAINT conversation_departures_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: conversation_departures conversation_departures_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_departures
    ADD CONSTRAINT conversation_departures_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: conversation_members conversation_members_added_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_members
    ADD CONSTRAINT conversation_members_added_by_fkey FOREIGN KEY (added_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: conversation_members conversation_members_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_members
    ADD CONSTRAINT conversation_members_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: conversation_members conversation_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_members
    ADD CONSTRAINT conversation_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: conversations conversations_initiated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_initiated_by_fkey FOREIGN KEY (initiated_by) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_pending_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pending_activity_id_fkey FOREIGN KEY (pending_activity_id) REFERENCES public.activities(id) ON DELETE SET NULL;


--
-- Name: conversations conversations_request_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_request_sender_id_fkey FOREIGN KEY (request_sender_id) REFERENCES public.users(id);


--
-- Name: conversations conversations_user_1_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_user_1_fkey FOREIGN KEY (user_1) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_user_2_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_user_2_fkey FOREIGN KEY (user_2) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: discovery_availabilities discovery_availabilities_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_availabilities
    ADD CONSTRAINT discovery_availabilities_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: favorites favorites_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: favorites favorites_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.pro_offerings(id) ON DELETE CASCADE;


--
-- Name: favorites favorites_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: favorites favorites_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favorites
    ADD CONSTRAINT favorites_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pro_profiles(user_id) ON DELETE CASCADE;


--
-- Name: gpx_traces gpx_traces_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gpx_traces
    ADD CONSTRAINT gpx_traces_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: invitation_declines invitation_declines_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitation_declines
    ADD CONSTRAINT invitation_declines_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: invitation_declines invitation_declines_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitation_declines
    ADD CONSTRAINT invitation_declines_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: invite_grants invite_grants_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invite_grants
    ADD CONSTRAINT invite_grants_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: invite_grants invite_grants_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invite_grants
    ADD CONSTRAINT invite_grants_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: late_cancels late_cancels_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.late_cancels
    ADD CONSTRAINT late_cancels_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: late_cancels late_cancels_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.late_cancels
    ADD CONSTRAINT late_cancels_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: message_original_content message_original_content_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_original_content
    ADD CONSTRAINT message_original_content_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE CASCADE;


--
-- Name: messages messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: messages messages_reply_to_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_reply_to_message_id_fkey FOREIGN KEY (reply_to_message_id) REFERENCES public.messages(id) ON DELETE SET NULL;


--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: offering_reviews offering_reviews_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offering_reviews
    ADD CONSTRAINT offering_reviews_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.pro_offerings(id) ON DELETE CASCADE;


--
-- Name: offering_reviews offering_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offering_reviews
    ADD CONSTRAINT offering_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: participations participations_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participations
    ADD CONSTRAINT participations_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: participations participations_invited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participations
    ADD CONSTRAINT participations_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: participations participations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.participations
    ADD CONSTRAINT participations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: presence_tokens presence_tokens_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presence_tokens
    ADD CONSTRAINT presence_tokens_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: pro_availabilities pro_availabilities_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_availabilities
    ADD CONSTRAINT pro_availabilities_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: pro_community_photos pro_community_photos_contributor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_community_photos
    ADD CONSTRAINT pro_community_photos_contributor_id_fkey FOREIGN KEY (contributor_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: pro_community_photos pro_community_photos_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_community_photos
    ADD CONSTRAINT pro_community_photos_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.pro_offerings(id) ON DELETE CASCADE;


--
-- Name: pro_community_photos pro_community_photos_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_community_photos
    ADD CONSTRAINT pro_community_photos_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pro_profiles(user_id) ON DELETE CASCADE;


--
-- Name: pro_community_photos pro_community_photos_review_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_community_photos
    ADD CONSTRAINT pro_community_photos_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.pro_reviews(id) ON DELETE CASCADE;


--
-- Name: pro_offering_photos pro_offering_photos_offering_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_offering_photos
    ADD CONSTRAINT pro_offering_photos_offering_id_fkey FOREIGN KEY (offering_id) REFERENCES public.pro_offerings(id) ON DELETE CASCADE;


--
-- Name: pro_offerings pro_offerings_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_offerings
    ADD CONSTRAINT pro_offerings_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pro_profiles(user_id) ON DELETE CASCADE;


--
-- Name: pro_offerings pro_offerings_sport_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_offerings
    ADD CONSTRAINT pro_offerings_sport_id_fkey FOREIGN KEY (sport_id) REFERENCES public.sports(id) ON DELETE RESTRICT;


--
-- Name: pro_profile_photos pro_profile_photos_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_profile_photos
    ADD CONSTRAINT pro_profile_photos_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pro_profiles(user_id) ON DELETE CASCADE;


--
-- Name: pro_profiles pro_profiles_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_profiles
    ADD CONSTRAINT pro_profiles_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: pro_profiles pro_profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_profiles
    ADD CONSTRAINT pro_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: pro_reviews pro_reviews_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_reviews
    ADD CONSTRAINT pro_reviews_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pro_profiles(user_id) ON DELETE CASCADE;


--
-- Name: pro_reviews pro_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_reviews
    ADD CONSTRAINT pro_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: push_tokens push_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reports reports_reporter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: reputation_votes reputation_votes_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reputation_votes
    ADD CONSTRAINT reputation_votes_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: reputation_votes reputation_votes_voted_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reputation_votes
    ADD CONSTRAINT reputation_votes_voted_id_fkey FOREIGN KEY (voted_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reputation_votes reputation_votes_voter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reputation_votes
    ADD CONSTRAINT reputation_votes_voter_id_fkey FOREIGN KEY (voter_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: seat_requests seat_requests_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seat_requests
    ADD CONSTRAINT seat_requests_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activities(id) ON DELETE CASCADE;


--
-- Name: seat_requests seat_requests_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seat_requests
    ADD CONSTRAINT seat_requests_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: seat_requests seat_requests_requester_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seat_requests
    ADD CONSTRAINT seat_requests_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: snap_trail_calls snap_trail_calls_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.snap_trail_calls
    ADD CONSTRAINT snap_trail_calls_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: trace_elevation_calls trace_elevation_calls_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trace_elevation_calls
    ADD CONSTRAINT trace_elevation_calls_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_badge_progression user_badge_progression_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_badge_progression
    ADD CONSTRAINT user_badge_progression_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: gear_catalog Anyone can read gear catalog; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone can read gear catalog" ON public.gear_catalog FOR SELECT USING (true);


--
-- Name: activity_gear Participants can read activity gear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Participants can read activity gear" ON public.activity_gear FOR SELECT USING ((((EXISTS ( SELECT 1
   FROM public.participations
  WHERE ((participations.activity_id = activity_gear.activity_id) AND (participations.user_id = auth.uid()) AND (participations.status = 'accepted'::text)))) OR (EXISTS ( SELECT 1
   FROM public.activities
  WHERE ((activities.id = activity_gear.activity_id) AND (activities.creator_id = auth.uid()))))) AND (NOT (user_id IN ( SELECT blocked_users.blocked_id
   FROM public.blocked_users
  WHERE (blocked_users.blocker_id = auth.uid()))))));


--
-- Name: activity_gear_missing Participants can read missing gear; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Participants can read missing gear" ON public.activity_gear_missing FOR SELECT USING ((((EXISTS ( SELECT 1
   FROM public.participations
  WHERE ((participations.activity_id = activity_gear_missing.activity_id) AND (participations.user_id = auth.uid()) AND (participations.status = 'accepted'::text)))) OR (EXISTS ( SELECT 1
   FROM public.activities
  WHERE ((activities.id = activity_gear_missing.activity_id) AND (activities.creator_id = auth.uid()))))) AND ((created_by IS NULL) OR (NOT (created_by IN ( SELECT blocked_users.blocked_id
   FROM public.blocked_users
  WHERE (blocked_users.blocker_id = auth.uid())))))));


--
-- Name: seat_requests Users see their own seat requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users see their own seat requests" ON public.seat_requests FOR SELECT USING ((((requester_id = auth.uid()) OR (driver_id = auth.uid())) AND (NOT (EXISTS ( SELECT 1
   FROM public.blocked_users
  WHERE ((blocked_users.blocker_id = auth.uid()) AND (blocked_users.blocked_id =
        CASE
            WHEN (seat_requests.requester_id = auth.uid()) THEN seat_requests.driver_id
            ELSE seat_requests.requester_id
        END)))))));


--
-- Name: activities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;

--
-- Name: activities activities_select_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activities_select_authenticated ON public.activities FOR SELECT TO authenticated USING (((NOT private.user_is_suspended(auth.uid())) AND (((status = ANY (ARRAY['published'::text, 'in_progress'::text])) AND (deleted_at IS NULL) AND (visibility = ANY (ARRAY['public'::text, 'approval'::text])) AND ((is_demo = false) OR public.demo_content_visible()) AND (NOT private.user_is_suspended(creator_id)) AND (NOT (creator_id IN ( SELECT blocked_users.blocked_id
   FROM public.blocked_users
  WHERE (blocked_users.blocker_id = auth.uid()))))) OR (auth.uid() = creator_id) OR (EXISTS ( SELECT 1
   FROM public.participations
  WHERE ((participations.activity_id = activities.id) AND (participations.user_id = auth.uid()) AND (participations.status = ANY (ARRAY['accepted'::text, 'pending'::text]))))))));


--
-- Name: activity_alerts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activity_alerts ENABLE ROW LEVEL SECURITY;

--
-- Name: activity_gear; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activity_gear ENABLE ROW LEVEL SECURITY;

--
-- Name: activity_gear_missing; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activity_gear_missing ENABLE ROW LEVEL SECURITY;

--
-- Name: admin_actions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_actions ENABLE ROW LEVEL SECURITY;

--
-- Name: admin_actions admin_actions_select_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_actions_select_admin ON public.admin_actions FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))));


--
-- Name: activity_alerts alerts_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY alerts_delete_own ON public.activity_alerts FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: activity_alerts alerts_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY alerts_select_own ON public.activity_alerts FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: app_config; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

--
-- Name: banned_email_hashes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banned_email_hashes ENABLE ROW LEVEL SECURITY;

--
-- Name: blocked_users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

--
-- Name: blocked_users blocked_users_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY blocked_users_delete_own ON public.blocked_users FOR DELETE TO authenticated USING ((blocker_id = auth.uid()));


--
-- Name: blocked_users blocked_users_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY blocked_users_insert_own ON public.blocked_users FOR INSERT TO authenticated WITH CHECK ((blocker_id = auth.uid()));


--
-- Name: blocked_users blocked_users_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY blocked_users_select_own ON public.blocked_users FOR SELECT TO authenticated USING (((blocker_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_admin = true))))));


--
-- Name: bookings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

--
-- Name: bookings bookings_select_parties; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bookings_select_parties ON public.bookings FOR SELECT USING ((((client_id = auth.uid()) OR (pro_id = auth.uid())) AND (NOT private.user_is_suspended(auth.uid()))));


--
-- Name: channel_bans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.channel_bans ENABLE ROW LEVEL SECURITY;

--
-- Name: channels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.channels ENABLE ROW LEVEL SECURITY;

--
-- Name: contact_qr_scans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contact_qr_scans ENABLE ROW LEVEL SECURITY;

--
-- Name: contact_qr_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contact_qr_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: contact_removal_archive; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contact_removal_archive ENABLE ROW LEVEL SECURITY;

--
-- Name: conversation_departures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversation_departures ENABLE ROW LEVEL SECURITY;

--
-- Name: conversation_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;

--
-- Name: conversation_members conversation_members_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversation_members_select_own ON public.conversation_members FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: discovery_availabilities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.discovery_availabilities ENABLE ROW LEVEL SECURITY;

--
-- Name: discovery_availabilities discovery_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY discovery_select_own ON public.discovery_availabilities FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: favorites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

--
-- Name: favorites favorites_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY favorites_select_own ON public.favorites FOR SELECT TO authenticated USING ((owner_id = auth.uid()));


--
-- Name: gear_catalog; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gear_catalog ENABLE ROW LEVEL SECURITY;

--
-- Name: gpx_traces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gpx_traces ENABLE ROW LEVEL SECURITY;

--
-- Name: gpx_traces gpx_traces_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gpx_traces_select_own ON public.gpx_traces FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: invitation_declines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitation_declines ENABLE ROW LEVEL SECURITY;

--
-- Name: invite_grants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invite_grants ENABLE ROW LEVEL SECURITY;

--
-- Name: late_cancels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.late_cancels ENABLE ROW LEVEL SECURITY;

--
-- Name: map_broadcasts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.map_broadcasts ENABLE ROW LEVEL SECURITY;

--
-- Name: message_original_content; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.message_original_content ENABLE ROW LEVEL SECURITY;

--
-- Name: messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: messages messages_select_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY messages_select_member ON public.messages FOR SELECT TO authenticated USING (((deleted_at IS NULL) AND private.is_conversation_member(conversation_id, auth.uid()) AND private.message_author_visible(conversation_id, sender_id, auth.uid())));


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications notifications_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_select_own ON public.notifications FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: notifications notifications_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_update_own ON public.notifications FOR UPDATE TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: offering_reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.offering_reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: offering_reviews offering_reviews_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY offering_reviews_select ON public.offering_reviews FOR SELECT TO authenticated USING (((NOT private.user_is_suspended(reviewer_id)) AND (EXISTS ( SELECT 1
   FROM public.pro_offerings o
  WHERE ((o.id = offering_reviews.offering_id) AND ((o.is_demo = false) OR public.demo_content_visible()))))));


--
-- Name: participations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.participations ENABLE ROW LEVEL SECURITY;

--
-- Name: participations participations_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY participations_select_own ON public.participations FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: presence_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.presence_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_availabilities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_availabilities ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_availabilities pro_availabilities_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_availabilities_select_own ON public.pro_availabilities FOR SELECT USING ((pro_id = auth.uid()));


--
-- Name: pro_community_photos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_community_photos ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_community_photos pro_community_photos_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_community_photos_public_read ON public.pro_community_photos FOR SELECT TO authenticated USING (((NOT private.user_is_suspended(pro_id)) AND (public.demo_content_visible() OR (EXISTS ( SELECT 1
   FROM public.pro_profiles dp
  WHERE ((dp.user_id = pro_community_photos.pro_id) AND (dp.is_demo = false))))) AND (NOT private.user_is_suspended(contributor_id))));


--
-- Name: pro_offering_photos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_offering_photos ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_offering_photos pro_offering_photos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_offering_photos_select ON public.pro_offering_photos FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.pro_offerings o
  WHERE ((o.id = pro_offering_photos.offering_id) AND (NOT private.user_is_suspended(o.pro_id)) AND ((o.is_demo = false) OR public.demo_content_visible())))));


--
-- Name: pro_offerings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_offerings ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_offerings pro_offerings_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_offerings_select ON public.pro_offerings FOR SELECT TO authenticated USING (((NOT private.user_is_suspended(pro_id)) AND ((is_demo = false) OR public.demo_content_visible()) AND ((pro_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.pro_profiles pp
  WHERE ((pp.user_id = pro_offerings.pro_id) AND (pp.status = 'approved'::text)))))));


--
-- Name: pro_profile_photos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_profile_photos ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_profile_photos pro_profile_photos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_profile_photos_select ON public.pro_profile_photos FOR SELECT TO authenticated USING (((NOT private.user_is_suspended(pro_id)) AND (public.demo_content_visible() OR (EXISTS ( SELECT 1
   FROM public.pro_profiles dp
  WHERE ((dp.user_id = pro_profile_photos.pro_id) AND (dp.is_demo = false)))))));


--
-- Name: pro_profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_profiles pro_profiles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_profiles_select ON public.pro_profiles FOR SELECT TO authenticated USING (((NOT private.user_is_suspended(user_id)) AND ((is_demo = false) OR public.demo_content_visible()) AND ((status = 'approved'::text) OR (user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_admin = true) AND (users.suspended_at IS NULL)))))));


--
-- Name: pro_reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_reviews pro_reviews_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_reviews_select ON public.pro_reviews FOR SELECT TO authenticated USING (((NOT private.user_is_suspended(reviewer_id)) AND (NOT private.user_is_suspended(pro_id)) AND (public.demo_content_visible() OR (EXISTS ( SELECT 1
   FROM public.pro_profiles dp
  WHERE ((dp.user_id = pro_reviews.pro_id) AND (dp.is_demo = false)))))));


--
-- Name: push_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: rate_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rate_events ENABLE ROW LEVEL SECURITY;

--
-- Name: reports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

--
-- Name: reports reports_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reports_select ON public.reports FOR SELECT TO authenticated USING (((reporter_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_admin = true))))));


--
-- Name: reports reports_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reports_update_admin ON public.reports FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_admin = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))));


--
-- Name: reputation_votes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reputation_votes ENABLE ROW LEVEL SECURITY;

--
-- Name: reputation_votes reputation_votes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reputation_votes_select ON public.reputation_votes FOR SELECT TO authenticated USING ((auth.uid() = voter_id));


--
-- Name: seat_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.seat_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: snap_trail_calls; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.snap_trail_calls ENABLE ROW LEVEL SECURITY;

--
-- Name: sports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sports ENABLE ROW LEVEL SECURITY;

--
-- Name: sports sports_delete_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sports_delete_admin ON public.sports FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))));


--
-- Name: sports sports_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sports_insert_admin ON public.sports FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))));


--
-- Name: sports sports_select_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sports_select_all ON public.sports FOR SELECT USING (true);


--
-- Name: sports sports_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sports_update_admin ON public.sports FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))));


--
-- Name: trace_elevation_calls; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.trace_elevation_calls ENABLE ROW LEVEL SECURITY;

--
-- Name: user_badge_progression; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_badge_progression ENABLE ROW LEVEL SECURITY;

--
-- Name: user_badge_progression user_badge_progression_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_badge_progression_select_own ON public.user_badge_progression FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: users users_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_select_own ON public.users FOR SELECT TO authenticated USING ((auth.uid() = id));


--
-- Name: users users_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY users_update_own ON public.users FOR UPDATE TO authenticated USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));


--
-- Name: SCHEMA private; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA private TO authenticated;
GRANT USAGE ON SCHEMA private TO anon;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION assert_approved_pro(p_user_id uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.assert_approved_pro(p_user_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION assert_can_send(p_conversation_id uuid, p_user_id uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.assert_can_send(p_conversation_id uuid, p_user_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION award_on_late_presence(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.award_on_late_presence() FROM PUBLIC;


--
-- Name: FUNCTION ban_email_on_suspended_delete(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.ban_email_on_suspended_delete() FROM PUBLIC;


--
-- Name: FUNCTION broadcast_message_update(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.broadcast_message_update() FROM PUBLIC;


--
-- Name: FUNCTION check_avatar_url(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.check_avatar_url() FROM PUBLIC;


--
-- Name: FUNCTION check_schedule_conflict(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.check_schedule_conflict() FROM PUBLIC;


--
-- Name: FUNCTION check_shared_outing_block(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.check_shared_outing_block() FROM PUBLIC;


--
-- Name: FUNCTION clear_stale_join_request(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.clear_stale_join_request() FROM PUBLIC;


--
-- Name: FUNCTION email_hash(p_email text); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.email_hash(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION email_is_banned(p_email text); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.email_is_banned(p_email text) FROM PUBLIC;


--
-- Name: FUNCTION insert_rich_message(p_conversation_id uuid, p_sender_id uuid, p_content text, p_metadata jsonb); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.insert_rich_message(p_conversation_id uuid, p_sender_id uuid, p_content text, p_metadata jsonb) FROM PUBLIC;


--
-- Name: FUNCTION is_conversation_member(p_conversation_id uuid, p_user_id uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.is_conversation_member(p_conversation_id uuid, p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION private.is_conversation_member(p_conversation_id uuid, p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION private.is_conversation_member(p_conversation_id uuid, p_user_id uuid) TO anon;


--
-- Name: FUNCTION is_messaging_eligible(p_caller uuid, p_target uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.is_messaging_eligible(p_caller uuid, p_target uuid) FROM PUBLIC;


--
-- Name: FUNCTION level_tier(p_sport_key text, p_level text); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.level_tier(p_sport_key text, p_level text) FROM PUBLIC;


--
-- Name: FUNCTION message_author_visible(p_conversation_id uuid, p_sender_id uuid, p_viewer_id uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.message_author_visible(p_conversation_id uuid, p_sender_id uuid, p_viewer_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION private.message_author_visible(p_conversation_id uuid, p_sender_id uuid, p_viewer_id uuid) TO authenticated;
GRANT ALL ON FUNCTION private.message_author_visible(p_conversation_id uuid, p_sender_id uuid, p_viewer_id uuid) TO anon;


--
-- Name: FUNCTION notify_pro_renamed(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.notify_pro_renamed() FROM PUBLIC;


--
-- Name: FUNCTION offering_duration_ok(p text); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.offering_duration_ok(p text) FROM PUBLIC;


--
-- Name: FUNCTION private_activity_access(p_activity_id uuid, p_user_id uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.private_activity_access(p_activity_id uuid, p_user_id uuid) FROM PUBLIC;


--
-- Name: FUNCTION pro_photo_url_ok(p_url text, p_uid uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.pro_photo_url_ok(p_url text, p_uid uuid) FROM PUBLIC;


--
-- Name: FUNCTION project_url(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.project_url() FROM PUBLIC;


--
-- Name: FUNCTION rate_hit(p_kind text, p_limit integer, p_window interval); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.rate_hit(p_kind text, p_limit integer, p_window interval) FROM PUBLIC;


--
-- Name: FUNCTION refuse_banned_email_change(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.refuse_banned_email_change() FROM PUBLIC;


--
-- Name: FUNCTION require_onboarded_actor(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.require_onboarded_actor() FROM PUBLIC;


--
-- Name: FUNCTION seat_cleanup_on_participation_loss(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.seat_cleanup_on_participation_loss() FROM PUBLIC;


--
-- Name: FUNCTION seat_release_on_end(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.seat_release_on_end() FROM PUBLIC;


--
-- Name: FUNCTION stamp_accepted_at(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.stamp_accepted_at() FROM PUBLIC;


--
-- Name: FUNCTION storage_object_quota(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.storage_object_quota() FROM PUBLIC;


--
-- Name: FUNCTION today_paris(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.today_paris() FROM PUBLIC;


--
-- Name: FUNCTION user_is_suspended(p_user_id uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.user_is_suspended(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION private.user_is_suspended(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION private.user_is_suspended(p_user_id uuid) TO anon;


--
-- Name: FUNCTION accept_activity_invitation(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.accept_activity_invitation(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_activity_invitation(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.accept_activity_invitation(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION accept_booking(p_booking_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.accept_booking(p_booking_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_booking(p_booking_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.accept_booking(p_booking_id uuid) TO service_role;


--
-- Name: FUNCTION accept_contact_request(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.accept_contact_request(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_contact_request(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.accept_contact_request(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION accept_participation(p_participation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.accept_participation(p_participation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_participation(p_participation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.accept_participation(p_participation_id uuid) TO service_role;


--
-- Name: FUNCTION accept_seat_request(p_request_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.accept_seat_request(p_request_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_seat_request(p_request_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.accept_seat_request(p_request_id uuid) TO service_role;


--
-- Name: FUNCTION accept_tos(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.accept_tos() FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_tos() TO authenticated;
GRANT ALL ON FUNCTION public.accept_tos() TO service_role;


--
-- Name: FUNCTION activate_dispo(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.activate_dispo() FROM PUBLIC;
GRANT ALL ON FUNCTION public.activate_dispo() TO authenticated;
GRANT ALL ON FUNCTION public.activate_dispo() TO service_role;


--
-- Name: FUNCTION add_favorite(p_kind text, p_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.add_favorite(p_kind text, p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_favorite(p_kind text, p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.add_favorite(p_kind text, p_id uuid) TO service_role;


--
-- Name: FUNCTION add_group_member(p_conversation_id uuid, p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.add_group_member(p_conversation_id uuid, p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_group_member(p_conversation_id uuid, p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.add_group_member(p_conversation_id uuid, p_user_id uuid) TO service_role;


--
-- Name: FUNCTION add_missing_gear(p_activity_id uuid, p_name text, p_quantity integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.add_missing_gear(p_activity_id uuid, p_name text, p_quantity integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_missing_gear(p_activity_id uuid, p_name text, p_quantity integer) TO authenticated;
GRANT ALL ON FUNCTION public.add_missing_gear(p_activity_id uuid, p_name text, p_quantity integer) TO service_role;


--
-- Name: FUNCTION add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid, p_offering_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid, p_offering_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid, p_offering_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid, p_offering_id uuid) TO service_role;


--
-- Name: FUNCTION add_pro_offering_photo(p_offering_id uuid, p_photo_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.add_pro_offering_photo(p_offering_id uuid, p_photo_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_pro_offering_photo(p_offering_id uuid, p_photo_url text) TO authenticated;
GRANT ALL ON FUNCTION public.add_pro_offering_photo(p_offering_id uuid, p_photo_url text) TO service_role;


--
-- Name: FUNCTION add_pro_photo(p_photo_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.add_pro_photo(p_photo_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_pro_photo(p_photo_url text) TO authenticated;
GRANT ALL ON FUNCTION public.add_pro_photo(p_photo_url text) TO service_role;


--
-- Name: FUNCTION admin_get_pending_pro_applications(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_get_pending_pro_applications() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_get_pending_pro_applications() TO authenticated;
GRANT ALL ON FUNCTION public.admin_get_pending_pro_applications() TO service_role;


--
-- Name: FUNCTION admin_pro_owner(p_pro_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_pro_owner(p_pro_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_pro_owner(p_pro_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_pro_owner(p_pro_id uuid) TO service_role;


--
-- Name: FUNCTION admin_remove_content(p_target_type text, p_target_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_remove_content(p_target_type text, p_target_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_remove_content(p_target_type text, p_target_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_remove_content(p_target_type text, p_target_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION admin_resolve_user(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_resolve_user(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_resolve_user(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_resolve_user(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION admin_set_demo_mode(p_on boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_set_demo_mode(p_on boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_set_demo_mode(p_on boolean) TO authenticated;
GRANT ALL ON FUNCTION public.admin_set_demo_mode(p_on boolean) TO service_role;


--
-- Name: FUNCTION admin_suspend_user(p_user_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_suspend_user(p_user_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_suspend_user(p_user_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_suspend_user(p_user_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION admin_unsuspend_user(p_user_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_unsuspend_user(p_user_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_unsuspend_user(p_user_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_unsuspend_user(p_user_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION approve_pro(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.approve_pro(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.approve_pro(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.approve_pro(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION award_badge_progression(p_user_id uuid, p_silent boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.award_badge_progression(p_user_id uuid, p_silent boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.award_badge_progression(p_user_id uuid, p_silent boolean) TO service_role;


--
-- Name: FUNCTION badge_label_fr(p_category text, p_tier text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.badge_label_fr(p_category text, p_tier text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.badge_label_fr(p_category text, p_tier text) TO service_role;


--
-- Name: FUNCTION badge_tier_for(p_count integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.badge_tier_for(p_count integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.badge_tier_for(p_count integer) TO service_role;


--
-- Name: FUNCTION bookings_clear_participant_info(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bookings_clear_participant_info() FROM PUBLIC;
GRANT ALL ON FUNCTION public.bookings_clear_participant_info() TO service_role;


--
-- Name: FUNCTION bookings_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bookings_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.bookings_whitelist_columns() TO service_role;


--
-- Name: FUNCTION broadcast_activity_change(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.broadcast_activity_change() FROM PUBLIC;
GRANT ALL ON FUNCTION public.broadcast_activity_change() TO service_role;


--
-- Name: FUNCTION broadcast_activity_change_stmt(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.broadcast_activity_change_stmt() FROM PUBLIC;
GRANT ALL ON FUNCTION public.broadcast_activity_change_stmt() TO service_role;


--
-- Name: FUNCTION broadcast_and_push_message(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.broadcast_and_push_message() FROM PUBLIC;
GRANT ALL ON FUNCTION public.broadcast_and_push_message() TO service_role;


--
-- Name: FUNCTION broadcast_map_activity(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.broadcast_map_activity() FROM PUBLIC;
GRANT ALL ON FUNCTION public.broadcast_map_activity() TO service_role;


--
-- Name: FUNCTION broadcast_map_creator(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.broadcast_map_creator() FROM PUBLIC;
GRANT ALL ON FUNCTION public.broadcast_map_creator() TO service_role;


--
-- Name: FUNCTION broadcast_map_participation(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.broadcast_map_participation() FROM PUBLIC;
GRANT ALL ON FUNCTION public.broadcast_map_participation() TO service_role;


--
-- Name: FUNCTION cancel_accepted_seat(p_request_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_accepted_seat(p_request_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_accepted_seat(p_request_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_accepted_seat(p_request_id uuid) TO service_role;


--
-- Name: FUNCTION cancel_activity(p_activity_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_activity(p_activity_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_activity(p_activity_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_activity(p_activity_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION cancel_booking(p_booking_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_booking(p_booking_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_booking(p_booking_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_booking(p_booking_id uuid) TO service_role;


--
-- Name: FUNCTION cancel_booking_pro(p_booking_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_booking_pro(p_booking_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_booking_pro(p_booking_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_booking_pro(p_booking_id uuid) TO service_role;


--
-- Name: FUNCTION cancel_pending_seat_request(p_request_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_pending_seat_request(p_request_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_pending_seat_request(p_request_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_pending_seat_request(p_request_id uuid) TO service_role;


--
-- Name: FUNCTION cascade_block_cleanup(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cascade_block_cleanup() FROM PUBLIC;
GRANT ALL ON FUNCTION public.cascade_block_cleanup() TO service_role;


--
-- Name: FUNCTION cascade_block_invited(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cascade_block_invited() FROM PUBLIC;
GRANT ALL ON FUNCTION public.cascade_block_invited() TO service_role;


--
-- Name: FUNCTION cascade_block_to_requests(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cascade_block_to_requests() FROM PUBLIC;
GRANT ALL ON FUNCTION public.cascade_block_to_requests() TO service_role;


--
-- Name: FUNCTION channels_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.channels_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.channels_whitelist_columns() TO service_role;


--
-- Name: FUNCTION check_activity_transitions(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.check_activity_transitions() FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_activity_transitions() TO service_role;


--
-- Name: FUNCTION check_alerts_for_activity(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.check_alerts_for_activity(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_alerts_for_activity(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION cleanup_notifications_on_conversation_delete(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cleanup_notifications_on_conversation_delete() FROM PUBLIC;
GRANT ALL ON FUNCTION public.cleanup_notifications_on_conversation_delete() TO service_role;


--
-- Name: FUNCTION clear_missing_on_shared_gear(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.clear_missing_on_shared_gear() FROM PUBLIC;
GRANT ALL ON FUNCTION public.clear_missing_on_shared_gear() TO service_role;


--
-- Name: FUNCTION clear_push_token_on_suspension(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.clear_push_token_on_suspension() FROM PUBLIC;
GRANT ALL ON FUNCTION public.clear_push_token_on_suspension() TO service_role;


--
-- Name: FUNCTION close_channel(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.close_channel(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.close_channel(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.close_channel(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION close_due_presence_windows(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.close_due_presence_windows() FROM PUBLIC;
GRANT ALL ON FUNCTION public.close_due_presence_windows() TO service_role;


--
-- Name: FUNCTION close_presence_window_for(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.close_presence_window_for(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.close_presence_window_for(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION compute_trace_stats(p_geojson jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.compute_trace_stats(p_geojson jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.compute_trace_stats(p_geojson jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.compute_trace_stats(p_geojson jsonb) TO service_role;


--
-- Name: FUNCTION confirm_age_adult(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.confirm_age_adult() FROM PUBLIC;
GRANT ALL ON FUNCTION public.confirm_age_adult() TO authenticated;
GRANT ALL ON FUNCTION public.confirm_age_adult() TO service_role;


--
-- Name: FUNCTION confirm_presence_via_geo(p_activity_id uuid, p_lng double precision, p_lat double precision, p_captured_at timestamp with time zone, p_skip_push boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.confirm_presence_via_geo(p_activity_id uuid, p_lng double precision, p_lat double precision, p_captured_at timestamp with time zone, p_skip_push boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.confirm_presence_via_geo(p_activity_id uuid, p_lng double precision, p_lat double precision, p_captured_at timestamp with time zone, p_skip_push boolean) TO authenticated;
GRANT ALL ON FUNCTION public.confirm_presence_via_geo(p_activity_id uuid, p_lng double precision, p_lat double precision, p_captured_at timestamp with time zone, p_skip_push boolean) TO service_role;


--
-- Name: FUNCTION confirm_presence_via_token(p_token text, p_skip_push boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.confirm_presence_via_token(p_token text, p_skip_push boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.confirm_presence_via_token(p_token text, p_skip_push boolean) TO authenticated;
GRANT ALL ON FUNCTION public.confirm_presence_via_token(p_token text, p_skip_push boolean) TO service_role;


--
-- Name: FUNCTION connect_via_qr_token(p_token text, p_expected_owner uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.connect_via_qr_token(p_token text, p_expected_owner uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.connect_via_qr_token(p_token text, p_expected_owner uuid) TO authenticated;
GRANT ALL ON FUNCTION public.connect_via_qr_token(p_token text, p_expected_owner uuid) TO service_role;


--
-- Name: FUNCTION consume_snap_trail_quota(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.consume_snap_trail_quota() FROM PUBLIC;
GRANT ALL ON FUNCTION public.consume_snap_trail_quota() TO authenticated;
GRANT ALL ON FUNCTION public.consume_snap_trail_quota() TO service_role;


--
-- Name: FUNCTION consume_trace_elevation_points(p_points integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.consume_trace_elevation_points(p_points integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.consume_trace_elevation_points(p_points integer) TO authenticated;
GRANT ALL ON FUNCTION public.consume_trace_elevation_points(p_points integer) TO service_role;


--
-- Name: FUNCTION consume_trace_elevation_quota(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.consume_trace_elevation_quota() FROM PUBLIC;
GRANT ALL ON FUNCTION public.consume_trace_elevation_quota() TO authenticated;
GRANT ALL ON FUNCTION public.consume_trace_elevation_quota() TO service_role;


--
-- Name: FUNCTION conversation_members_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.conversation_members_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.conversation_members_whitelist_columns() TO service_role;


--
-- Name: FUNCTION conversations_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.conversations_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.conversations_whitelist_columns() TO service_role;


--
-- Name: FUNCTION create_activity(p_sport_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_end_lng double precision, p_end_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_requires_presence boolean, p_objective_lng double precision, p_objective_lat double precision, p_objective_name text, p_distance_km numeric, p_elevation_gain_m integer, p_meeting_name text, p_trace_geojson jsonb, p_level_max text, p_meeting_locality text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_activity(p_sport_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_end_lng double precision, p_end_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_requires_presence boolean, p_objective_lng double precision, p_objective_lat double precision, p_objective_name text, p_distance_km numeric, p_elevation_gain_m integer, p_meeting_name text, p_trace_geojson jsonb, p_level_max text, p_meeting_locality text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_activity(p_sport_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_end_lng double precision, p_end_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_requires_presence boolean, p_objective_lng double precision, p_objective_lat double precision, p_objective_name text, p_distance_km numeric, p_elevation_gain_m integer, p_meeting_name text, p_trace_geojson jsonb, p_level_max text, p_meeting_locality text) TO authenticated;
GRANT ALL ON FUNCTION public.create_activity(p_sport_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_end_lng double precision, p_end_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_requires_presence boolean, p_objective_lng double precision, p_objective_lat double precision, p_objective_name text, p_distance_km numeric, p_elevation_gain_m integer, p_meeting_name text, p_trace_geojson jsonb, p_level_max text, p_meeting_locality text) TO service_role;


--
-- Name: FUNCTION create_activity_conversation(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_activity_conversation() FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_activity_conversation() TO service_role;


--
-- Name: FUNCTION create_alert(p_lng double precision, p_lat double precision, p_radius_km integer, p_sport_key text, p_levels text[], p_starts_on date, p_ends_on date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_alert(p_lng double precision, p_lat double precision, p_radius_km integer, p_sport_key text, p_levels text[], p_starts_on date, p_ends_on date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_alert(p_lng double precision, p_lat double precision, p_radius_km integer, p_sport_key text, p_levels text[], p_starts_on date, p_ends_on date) TO authenticated;
GRANT ALL ON FUNCTION public.create_alert(p_lng double precision, p_lat double precision, p_radius_km integer, p_sport_key text, p_levels text[], p_starts_on date, p_ends_on date) TO service_role;


--
-- Name: FUNCTION create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text) TO authenticated;
GRANT ALL ON FUNCTION public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text) TO service_role;


--
-- Name: FUNCTION create_channel(p_name text, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_sport_key text, p_description text, p_photo_url text, p_force boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_channel(p_name text, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_sport_key text, p_description text, p_photo_url text, p_force boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_channel(p_name text, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_sport_key text, p_description text, p_photo_url text, p_force boolean) TO authenticated;
GRANT ALL ON FUNCTION public.create_channel(p_name text, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_sport_key text, p_description text, p_photo_url text, p_force boolean) TO service_role;


--
-- Name: FUNCTION create_contact_qr_token(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_contact_qr_token() FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_contact_qr_token() TO authenticated;
GRANT ALL ON FUNCTION public.create_contact_qr_token() TO service_role;


--
-- Name: FUNCTION create_dm_member_rows(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_dm_member_rows() FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_dm_member_rows() TO service_role;


--
-- Name: TABLE gpx_traces; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.gpx_traces TO service_role;
GRANT SELECT ON TABLE public.gpx_traces TO authenticated;


--
-- Name: FUNCTION create_gpx_trace(p_name text, p_geojson jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_gpx_trace(p_name text, p_geojson jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_gpx_trace(p_name text, p_geojson jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.create_gpx_trace(p_name text, p_geojson jsonb) TO service_role;


--
-- Name: FUNCTION create_group(p_name text, p_icon text, p_member_ids uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_group(p_name text, p_icon text, p_member_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_group(p_name text, p_icon text, p_member_ids uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.create_group(p_name text, p_icon text, p_member_ids uuid[]) TO service_role;


--
-- Name: FUNCTION create_manual_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_name text, p_phone text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_manual_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_name text, p_phone text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_manual_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_name text, p_phone text) TO authenticated;
GRANT ALL ON FUNCTION public.create_manual_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_name text, p_phone text) TO service_role;


--
-- Name: FUNCTION create_notification(p_user_id uuid, p_type text, p_title text, p_body text, p_data jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_notification(p_user_id uuid, p_type text, p_title text, p_body text, p_data jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_notification(p_user_id uuid, p_type text, p_title text, p_body text, p_data jsonb) TO service_role;


--
-- Name: FUNCTION create_offering_review(p_offering_id uuid, p_rating smallint, p_body text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_offering_review(p_offering_id uuid, p_rating smallint, p_body text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_offering_review(p_offering_id uuid, p_rating smallint, p_body text) TO authenticated;
GRANT ALL ON FUNCTION public.create_offering_review(p_offering_id uuid, p_rating smallint, p_body text) TO service_role;


--
-- Name: FUNCTION create_presence_token(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_presence_token(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_presence_token(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_presence_token(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION create_pro_offering(p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_pro_offering(p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_pro_offering(p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer) TO authenticated;
GRANT ALL ON FUNCTION public.create_pro_offering(p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer) TO service_role;


--
-- Name: FUNCTION create_pro_review(p_pro_id uuid, p_rating smallint, p_body text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_pro_review(p_pro_id uuid, p_rating smallint, p_body text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_pro_review(p_pro_id uuid, p_rating smallint, p_body text) TO authenticated;
GRANT ALL ON FUNCTION public.create_pro_review(p_pro_id uuid, p_rating smallint, p_body text) TO service_role;


--
-- Name: FUNCTION create_report(p_target_type text, p_target_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_report(p_target_type text, p_target_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_report(p_target_type text, p_target_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.create_report(p_target_type text, p_target_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION deactivate_dispo(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.deactivate_dispo() FROM PUBLIC;
GRANT ALL ON FUNCTION public.deactivate_dispo() TO authenticated;
GRANT ALL ON FUNCTION public.deactivate_dispo() TO service_role;


--
-- Name: FUNCTION decline_activity_invitation(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.decline_activity_invitation(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.decline_activity_invitation(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.decline_activity_invitation(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION decline_booking(p_booking_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.decline_booking(p_booking_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.decline_booking(p_booking_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.decline_booking(p_booking_id uuid) TO service_role;


--
-- Name: FUNCTION decline_contact_request(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.decline_contact_request(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.decline_contact_request(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.decline_contact_request(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION decline_seat_request(p_request_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.decline_seat_request(p_request_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.decline_seat_request(p_request_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.decline_seat_request(p_request_id uuid) TO service_role;


--
-- Name: FUNCTION delete_account_as(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_account_as(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_account_as(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION delete_gpx_trace(p_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_gpx_trace(p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_gpx_trace(p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_gpx_trace(p_id uuid) TO service_role;


--
-- Name: FUNCTION delete_message(p_message_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_message(p_message_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_message(p_message_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_message(p_message_id uuid) TO service_role;


--
-- Name: FUNCTION delete_offering_review(p_review_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_offering_review(p_review_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_offering_review(p_review_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_offering_review(p_review_id uuid) TO service_role;


--
-- Name: FUNCTION delete_own_account(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_own_account() FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_own_account() TO service_role;


--
-- Name: FUNCTION delete_pro_offering(p_offering_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_pro_offering(p_offering_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_pro_offering(p_offering_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_pro_offering(p_offering_id uuid) TO service_role;


--
-- Name: FUNCTION delete_pro_review(p_review_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_pro_review(p_review_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_pro_review(p_review_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_pro_review(p_review_id uuid) TO service_role;


--
-- Name: FUNCTION demo_content_visible(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.demo_content_visible() TO authenticated;
GRANT ALL ON FUNCTION public.demo_content_visible() TO service_role;
GRANT ALL ON FUNCTION public.demo_content_visible() TO anon;


--
-- Name: FUNCTION discovery_availabilities_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.discovery_availabilities_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.discovery_availabilities_whitelist_columns() TO service_role;


--
-- Name: FUNCTION edit_message(p_message_id uuid, p_content text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.edit_message(p_message_id uuid, p_content text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.edit_message(p_message_id uuid, p_content text) TO authenticated;
GRANT ALL ON FUNCTION public.edit_message(p_message_id uuid, p_content text) TO service_role;


--
-- Name: FUNCTION ensure_user_row(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ensure_user_row() FROM PUBLIC;
GRANT ALL ON FUNCTION public.ensure_user_row() TO authenticated;
GRANT ALL ON FUNCTION public.ensure_user_row() TO service_role;


--
-- Name: FUNCTION expire_idle_seat_requests(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.expire_idle_seat_requests() FROM PUBLIC;
GRANT ALL ON FUNCTION public.expire_idle_seat_requests() TO service_role;


--
-- Name: FUNCTION expire_invited_on_activity_end(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.expire_invited_on_activity_end() FROM PUBLIC;
GRANT ALL ON FUNCTION public.expire_invited_on_activity_end() TO service_role;


--
-- Name: FUNCTION expire_stale_contact_requests(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.expire_stale_contact_requests() FROM PUBLIC;
GRANT ALL ON FUNCTION public.expire_stale_contact_requests() TO service_role;


--
-- Name: FUNCTION generate_random_name(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.generate_random_name() FROM PUBLIC;
GRANT ALL ON FUNCTION public.generate_random_name() TO service_role;


--
-- Name: FUNCTION get_active_negative_count(p_voted_id uuid, p_badge_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_active_negative_count(p_voted_id uuid, p_badge_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_active_negative_count(p_voted_id uuid, p_badge_key text) TO service_role;


--
-- Name: FUNCTION get_activity_by_invite_token(p_token uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_activity_by_invite_token(p_token uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_activity_by_invite_token(p_token uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_activity_by_invite_token(p_token uuid) TO service_role;


--
-- Name: FUNCTION reliability_tier(p_score double precision); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reliability_tier(p_score double precision) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reliability_tier(p_score double precision) TO authenticated;
GRANT ALL ON FUNCTION public.reliability_tier(p_score double precision) TO service_role;


--
-- Name: TABLE activities; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.activities TO service_role;


--
-- Name: COLUMN activities.id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(id) ON TABLE public.activities TO anon;
GRANT SELECT(id) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.creator_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(creator_id) ON TABLE public.activities TO anon;
GRANT SELECT(creator_id) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.sport_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(sport_id) ON TABLE public.activities TO anon;
GRANT SELECT(sport_id) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.title; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(title) ON TABLE public.activities TO anon;
GRANT SELECT(title) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.description; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(description) ON TABLE public.activities TO anon;
GRANT SELECT(description) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.level; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(level) ON TABLE public.activities TO anon;
GRANT SELECT(level) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.max_participants; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(max_participants) ON TABLE public.activities TO anon;
GRANT SELECT(max_participants) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.location_meeting; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(location_meeting) ON TABLE public.activities TO anon;
GRANT SELECT(location_meeting) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.route; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(route) ON TABLE public.activities TO anon;
GRANT SELECT(route) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.starts_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(starts_at) ON TABLE public.activities TO anon;
GRANT SELECT(starts_at) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.duration; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(duration) ON TABLE public.activities TO anon;
GRANT SELECT(duration) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.visibility; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(visibility) ON TABLE public.activities TO anon;
GRANT SELECT(visibility) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.status; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(status) ON TABLE public.activities TO anon;
GRANT SELECT(status) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.deleted_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(deleted_at) ON TABLE public.activities TO anon;
GRANT SELECT(deleted_at) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.created_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(created_at) ON TABLE public.activities TO anon;
GRANT SELECT(created_at) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.updated_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(updated_at) ON TABLE public.activities TO anon;
GRANT SELECT(updated_at) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.location_end; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(location_end) ON TABLE public.activities TO anon;
GRANT SELECT(location_end) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.cancelled_reason; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(cancelled_reason) ON TABLE public.activities TO anon;
GRANT SELECT(cancelled_reason) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.requires_presence; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(requires_presence) ON TABLE public.activities TO anon;
GRANT SELECT(requires_presence) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.location_objective; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(location_objective) ON TABLE public.activities TO anon;
GRANT SELECT(location_objective) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.objective_name; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(objective_name) ON TABLE public.activities TO anon;
GRANT SELECT(objective_name) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.distance_km; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(distance_km) ON TABLE public.activities TO anon;
GRANT SELECT(distance_km) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.elevation_gain_m; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(elevation_gain_m) ON TABLE public.activities TO anon;
GRANT SELECT(elevation_gain_m) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.meeting_name; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(meeting_name) ON TABLE public.activities TO anon;
GRANT SELECT(meeting_name) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.trace_geojson; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(trace_geojson) ON TABLE public.activities TO anon;
GRANT SELECT(trace_geojson) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.level_max; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(level_max) ON TABLE public.activities TO anon;
GRANT SELECT(level_max) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.is_demo; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(is_demo) ON TABLE public.activities TO anon;
GRANT SELECT(is_demo) ON TABLE public.activities TO authenticated;


--
-- Name: COLUMN activities.meeting_locality; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(meeting_locality) ON TABLE public.activities TO anon;
GRANT SELECT(meeting_locality) ON TABLE public.activities TO authenticated;


--
-- Name: TABLE blocked_users; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.blocked_users TO anon;
GRANT SELECT,INSERT,DELETE ON TABLE public.blocked_users TO authenticated;
GRANT ALL ON TABLE public.blocked_users TO service_role;


--
-- Name: TABLE participations; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.participations TO anon;
GRANT SELECT ON TABLE public.participations TO authenticated;
GRANT ALL ON TABLE public.participations TO service_role;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,UPDATE ON TABLE public.users TO authenticated;
GRANT ALL ON TABLE public.users TO service_role;


--
-- Name: TABLE public_profiles; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.public_profiles TO authenticated;
GRANT ALL ON TABLE public.public_profiles TO service_role;


--
-- Name: TABLE sports; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.sports TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.sports TO authenticated;
GRANT ALL ON TABLE public.sports TO service_role;


--
-- Name: TABLE activities_with_coords; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.activities_with_coords TO anon;
GRANT SELECT ON TABLE public.activities_with_coords TO authenticated;
GRANT ALL ON TABLE public.activities_with_coords TO service_role;


--
-- Name: FUNCTION get_activity_detail(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_activity_detail(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_activity_detail(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_activity_detail(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION get_activity_participants(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_activity_participants(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_activity_participants(p_activity_id uuid) TO service_role;
GRANT ALL ON FUNCTION public.get_activity_participants(p_activity_id uuid) TO authenticated;


--
-- Name: FUNCTION get_activity_peer_review_state(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_activity_peer_review_state(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_activity_peer_review_state(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_activity_peer_review_state(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION get_activity_seat_assignments(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_activity_seat_assignments(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_activity_seat_assignments(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_activity_seat_assignments(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION get_channel(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_channel(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_channel(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_channel(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION get_channel_members(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_channel_members(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_channel_members(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_channel_members(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION get_contacts(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_contacts() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_contacts() TO authenticated;
GRANT ALL ON FUNCTION public.get_contacts() TO service_role;


--
-- Name: FUNCTION get_conversation_peer(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_conversation_peer(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_conversation_peer(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_conversation_peer(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION get_conversation_state_with(p_other_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_conversation_state_with(p_other_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_conversation_state_with(p_other_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_conversation_state_with(p_other_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_discovery_cards(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_discovery_cards() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_discovery_cards() TO authenticated;
GRANT ALL ON FUNCTION public.get_discovery_cards() TO service_role;


--
-- Name: FUNCTION get_discovery_count(p_sport_keys text[], p_base_lng double precision, p_base_lat double precision, p_radius_km integer, p_window_start timestamp with time zone, p_window_end timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_discovery_count(p_sport_keys text[], p_base_lng double precision, p_base_lat double precision, p_radius_km integer, p_window_start timestamp with time zone, p_window_end timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_discovery_count(p_sport_keys text[], p_base_lng double precision, p_base_lat double precision, p_radius_km integer, p_window_start timestamp with time zone, p_window_end timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.get_discovery_count(p_sport_keys text[], p_base_lng double precision, p_base_lat double precision, p_radius_km integer, p_window_start timestamp with time zone, p_window_end timestamp with time zone) TO service_role;


--
-- Name: FUNCTION get_dispo_zone(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_dispo_zone(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_dispo_zone(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_dispo_zone(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_favorites(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_favorites() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_favorites() TO authenticated;
GRANT ALL ON FUNCTION public.get_favorites() TO service_role;


--
-- Name: FUNCTION get_group_info(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_group_info(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_group_info(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_group_info(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION get_invitable_activities_for_dispo(p_target_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_invitable_activities_for_dispo(p_target_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_invitable_activities_for_dispo(p_target_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_invitable_activities_for_dispo(p_target_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_late_leavers(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_late_leavers(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_late_leavers(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_late_leavers(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION get_my_active_presence_activities(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_my_active_presence_activities() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_active_presence_activities() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_active_presence_activities() TO service_role;


--
-- Name: FUNCTION get_my_bookings(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_my_bookings() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_bookings() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_bookings() TO service_role;


--
-- Name: FUNCTION get_my_conversations(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_my_conversations() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_conversations() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_conversations() TO service_role;


--
-- Name: FUNCTION get_my_dispo(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_my_dispo() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_dispo() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_dispo() TO service_role;


--
-- Name: FUNCTION get_my_invitations(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_my_invitations() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_invitations() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_invitations() TO service_role;


--
-- Name: FUNCTION get_my_pro_application(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_my_pro_application() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_pro_application() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_pro_application() TO service_role;


--
-- Name: FUNCTION get_own_invite_token(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_own_invite_token(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_own_invite_token(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_own_invite_token(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION get_pending_contact_requests(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_pending_contact_requests() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_pending_contact_requests() TO authenticated;
GRANT ALL ON FUNCTION public.get_pending_contact_requests() TO service_role;


--
-- Name: FUNCTION get_pro_agenda(p_from date, p_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_pro_agenda(p_from date, p_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_pro_agenda(p_from date, p_to date) TO authenticated;
GRANT ALL ON FUNCTION public.get_pro_agenda(p_from date, p_to date) TO service_role;


--
-- Name: FUNCTION get_pro_availability(p_pro_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_pro_availability(p_pro_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_pro_availability(p_pro_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_pro_availability(p_pro_id uuid) TO service_role;


--
-- Name: FUNCTION get_recent_partners(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_recent_partners() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_recent_partners() TO authenticated;
GRANT ALL ON FUNCTION public.get_recent_partners() TO service_role;


--
-- Name: FUNCTION get_transport_summary(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_transport_summary(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_transport_summary(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_transport_summary(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION get_user_award_aggregates(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_user_award_aggregates(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_user_award_aggregates(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_user_award_aggregates(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_user_public_stats(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_user_public_stats(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_user_public_stats(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_user_public_stats(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_user_reputation(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_user_reputation(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_user_reputation(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_user_reputation(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_user_sport_level_votes(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_user_sport_level_votes(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_user_sport_level_votes(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_user_sport_level_votes(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_user_sport_levels(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_user_sport_levels(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_user_sport_levels(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_user_sport_levels(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_user_trophies(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_user_trophies(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_user_trophies(p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_user_trophies(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION get_voters_for_badge(p_user_id uuid, p_badge_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_voters_for_badge(p_user_id uuid, p_badge_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_voters_for_badge(p_user_id uuid, p_badge_key text) TO authenticated;
GRANT ALL ON FUNCTION public.get_voters_for_badge(p_user_id uuid, p_badge_key text) TO service_role;


--
-- Name: FUNCTION get_wall_messages(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_wall_messages(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_wall_messages(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_wall_messages(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION give_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.give_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.give_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text) TO authenticated;
GRANT ALL ON FUNCTION public.give_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text) TO service_role;


--
-- Name: FUNCTION handle_activity_update(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.handle_activity_update() FROM PUBLIC;
GRANT ALL ON FUNCTION public.handle_activity_update() TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


--
-- Name: FUNCTION handle_notification_update(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.handle_notification_update() FROM PUBLIC;
GRANT ALL ON FUNCTION public.handle_notification_update() TO service_role;


--
-- Name: FUNCTION handle_user_update(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.handle_user_update() FROM PUBLIC;
GRANT ALL ON FUNCTION public.handle_user_update() TO service_role;


--
-- Name: FUNCTION join_activity(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.join_activity(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.join_activity(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.join_activity(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION join_channel(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.join_channel(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.join_channel(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.join_channel(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION leave_activity(p_activity_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.leave_activity(p_activity_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.leave_activity(p_activity_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.leave_activity(p_activity_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION leave_channel(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.leave_channel(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.leave_channel(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.leave_channel(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION leave_group(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.leave_group(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.leave_group(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.leave_group(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION log_admin_action(p_admin uuid, p_action text, p_target_type text, p_target_id uuid, p_reason text, p_metadata jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.log_admin_action(p_admin uuid, p_action text, p_target_type text, p_target_id uuid, p_reason text, p_metadata jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.log_admin_action(p_admin uuid, p_action text, p_target_type text, p_target_id uuid, p_reason text, p_metadata jsonb) TO service_role;


--
-- Name: FUNCTION map_ping(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.map_ping(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.map_ping(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION mark_conversation_read(p_conversation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.mark_conversation_read(p_conversation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.mark_conversation_read(p_conversation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.mark_conversation_read(p_conversation_id uuid) TO service_role;


--
-- Name: FUNCTION mark_tutorial_seen(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.mark_tutorial_seen() FROM PUBLIC;
GRANT ALL ON FUNCTION public.mark_tutorial_seen() TO authenticated;
GRANT ALL ON FUNCTION public.mark_tutorial_seen() TO service_role;


--
-- Name: FUNCTION messages_block_closed_channel(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.messages_block_closed_channel() FROM PUBLIC;
GRANT ALL ON FUNCTION public.messages_block_closed_channel() TO service_role;


--
-- Name: FUNCTION messages_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.messages_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.messages_whitelist_columns() TO service_role;


--
-- Name: FUNCTION moderate_report(p_report_id uuid, p_action text, p_admin_note text, p_suspend_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.moderate_report(p_report_id uuid, p_action text, p_admin_note text, p_suspend_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.moderate_report(p_report_id uuid, p_action text, p_admin_note text, p_suspend_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.moderate_report(p_report_id uuid, p_action text, p_admin_note text, p_suspend_user_id uuid) TO service_role;


--
-- Name: FUNCTION notify_creator_qr_reminder(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_creator_qr_reminder(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_creator_qr_reminder(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION notify_participant_joined(p_creator_id uuid, p_activity_id uuid, p_joiner_name text, p_activity_title text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_participant_joined(p_creator_id uuid, p_activity_id uuid, p_joiner_name text, p_activity_title text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_participant_joined(p_creator_id uuid, p_activity_id uuid, p_joiner_name text, p_activity_title text) TO service_role;


--
-- Name: FUNCTION notify_presence_confirmed(p_user_id uuid, p_activity_id uuid, p_skip_push boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_presence_confirmed(p_user_id uuid, p_activity_id uuid, p_skip_push boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_presence_confirmed(p_user_id uuid, p_activity_id uuid, p_skip_push boolean) TO service_role;


--
-- Name: FUNCTION notify_presence_pre_warning(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_presence_pre_warning(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_presence_pre_warning(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION notify_presence_pre_warning_10min(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_presence_pre_warning_10min(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_presence_pre_warning_10min(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION notify_presence_validate_overdue(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_presence_validate_overdue(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_presence_validate_overdue(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION notify_presence_validate_warning(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_presence_validate_warning(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_presence_validate_warning(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION notify_rate_participants(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_rate_participants(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_rate_participants(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION notify_review_received(p_pro_id uuid, p_reviewer_name text, p_rating smallint, p_target_label text, p_data jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_review_received(p_pro_id uuid, p_reviewer_name text, p_rating smallint, p_target_label text, p_data jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_review_received(p_pro_id uuid, p_reviewer_name text, p_rating smallint, p_target_label text, p_data jsonb) TO service_role;


--
-- Name: FUNCTION notify_review_reply(p_reviewer_id uuid, p_pro_name text, p_target_label text, p_data jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_review_reply(p_reviewer_id uuid, p_pro_name text, p_target_label text, p_data jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_review_reply(p_reviewer_id uuid, p_pro_name text, p_target_label text, p_data jsonb) TO service_role;


--
-- Name: FUNCTION offering_reviews_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.offering_reviews_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.offering_reviews_whitelist_columns() TO service_role;


--
-- Name: FUNCTION on_activity_completed_award_badges(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.on_activity_completed_award_badges() FROM PUBLIC;
GRANT ALL ON FUNCTION public.on_activity_completed_award_badges() TO service_role;


--
-- Name: FUNCTION on_activity_finished_expire_seat_requests(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.on_activity_finished_expire_seat_requests() FROM PUBLIC;
GRANT ALL ON FUNCTION public.on_activity_finished_expire_seat_requests() TO service_role;


--
-- Name: FUNCTION pro_availabilities_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_availabilities_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_availabilities_whitelist_columns() TO service_role;


--
-- Name: FUNCTION pro_community_photos_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_community_photos_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_community_photos_whitelist_columns() TO service_role;


--
-- Name: FUNCTION pro_offering_photos_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_offering_photos_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_offering_photos_whitelist_columns() TO service_role;


--
-- Name: FUNCTION pro_offerings_require_approved(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_offerings_require_approved() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_offerings_require_approved() TO service_role;


--
-- Name: FUNCTION pro_offerings_touch_updated_at(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_offerings_touch_updated_at() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_offerings_touch_updated_at() TO service_role;


--
-- Name: FUNCTION pro_offerings_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_offerings_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_offerings_whitelist_columns() TO service_role;


--
-- Name: FUNCTION pro_profile_photos_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_profile_photos_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_profile_photos_whitelist_columns() TO service_role;


--
-- Name: FUNCTION pro_profiles_touch_updated_at(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_profiles_touch_updated_at() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_profiles_touch_updated_at() TO service_role;


--
-- Name: FUNCTION pro_profiles_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_profiles_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_profiles_whitelist_columns() TO service_role;


--
-- Name: FUNCTION pro_reviews_require_approved(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_reviews_require_approved() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_reviews_require_approved() TO service_role;


--
-- Name: FUNCTION pro_reviews_whitelist_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_reviews_whitelist_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_reviews_whitelist_columns() TO service_role;


--
-- Name: FUNCTION purge_booking_participant_info(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.purge_booking_participant_info() FROM PUBLIC;
GRANT ALL ON FUNCTION public.purge_booking_participant_info() TO service_role;


--
-- Name: FUNCTION purge_contact_removal_archive(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.purge_contact_removal_archive() FROM PUBLIC;
GRANT ALL ON FUNCTION public.purge_contact_removal_archive() TO service_role;


--
-- Name: FUNCTION purge_old_notifications(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.purge_old_notifications() FROM PUBLIC;
GRANT ALL ON FUNCTION public.purge_old_notifications() TO service_role;


--
-- Name: FUNCTION purge_throttle_tables(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.purge_throttle_tables() FROM PUBLIC;
GRANT ALL ON FUNCTION public.purge_throttle_tables() TO service_role;


--
-- Name: FUNCTION push_notification_to_device(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.push_notification_to_device() FROM PUBLIC;
GRANT ALL ON FUNCTION public.push_notification_to_device() TO service_role;


--
-- Name: FUNCTION recalc_creator_on_participant_change(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.recalc_creator_on_participant_change() FROM PUBLIC;
GRANT ALL ON FUNCTION public.recalc_creator_on_participant_change() TO service_role;


--
-- Name: FUNCTION recalculate_reliability_score(p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.recalculate_reliability_score(p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.recalculate_reliability_score(p_user_id uuid) TO service_role;


--
-- Name: FUNCTION refuse_participation(p_participation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.refuse_participation(p_participation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.refuse_participation(p_participation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.refuse_participation(p_participation_id uuid) TO service_role;


--
-- Name: FUNCTION register_as_pro(p_display_name text, p_company_name text, p_real_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.register_as_pro(p_display_name text, p_company_name text, p_real_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.register_as_pro(p_display_name text, p_company_name text, p_real_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text) TO authenticated;
GRANT ALL ON FUNCTION public.register_as_pro(p_display_name text, p_company_name text, p_real_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text) TO service_role;


--
-- Name: FUNCTION register_push_token(p_token text, p_device_id text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.register_push_token(p_token text, p_device_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.register_push_token(p_token text, p_device_id text) TO authenticated;
GRANT ALL ON FUNCTION public.register_push_token(p_token text, p_device_id text) TO service_role;


--
-- Name: FUNCTION reject_pro(p_user_id uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reject_pro(p_user_id uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reject_pro(p_user_id uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.reject_pro(p_user_id uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION remove_channel_member(p_conversation_id uuid, p_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.remove_channel_member(p_conversation_id uuid, p_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_channel_member(p_conversation_id uuid, p_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_channel_member(p_conversation_id uuid, p_user_id uuid) TO service_role;


--
-- Name: FUNCTION remove_connection(p_other_user_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.remove_connection(p_other_user_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_connection(p_other_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_connection(p_other_user_id uuid) TO service_role;


--
-- Name: FUNCTION remove_favorite(p_kind text, p_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.remove_favorite(p_kind text, p_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_favorite(p_kind text, p_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_favorite(p_kind text, p_id uuid) TO service_role;


--
-- Name: FUNCTION remove_missing_gear(p_activity_id uuid, p_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.remove_missing_gear(p_activity_id uuid, p_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_missing_gear(p_activity_id uuid, p_name text) TO authenticated;
GRANT ALL ON FUNCTION public.remove_missing_gear(p_activity_id uuid, p_name text) TO service_role;


--
-- Name: FUNCTION remove_participant(p_participation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.remove_participant(p_participation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_participant(p_participation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_participant(p_participation_id uuid) TO service_role;


--
-- Name: FUNCTION remove_pro_community_photo(p_photo_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.remove_pro_community_photo(p_photo_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_pro_community_photo(p_photo_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_pro_community_photo(p_photo_id uuid) TO service_role;


--
-- Name: FUNCTION remove_pro_offering_photo(p_photo_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.remove_pro_offering_photo(p_photo_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_pro_offering_photo(p_photo_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_pro_offering_photo(p_photo_id uuid) TO service_role;


--
-- Name: FUNCTION remove_pro_photo(p_photo_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.remove_pro_photo(p_photo_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_pro_photo(p_photo_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.remove_pro_photo(p_photo_id uuid) TO service_role;


--
-- Name: FUNCTION rename_channel(p_conversation_id uuid, p_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.rename_channel(p_conversation_id uuid, p_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.rename_channel(p_conversation_id uuid, p_name text) TO authenticated;
GRANT ALL ON FUNCTION public.rename_channel(p_conversation_id uuid, p_name text) TO service_role;


--
-- Name: FUNCTION rename_gpx_trace(p_id uuid, p_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.rename_gpx_trace(p_id uuid, p_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.rename_gpx_trace(p_id uuid, p_name text) TO authenticated;
GRANT ALL ON FUNCTION public.rename_gpx_trace(p_id uuid, p_name text) TO service_role;


--
-- Name: FUNCTION rename_group(p_conversation_id uuid, p_name text, p_icon text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.rename_group(p_conversation_id uuid, p_name text, p_icon text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.rename_group(p_conversation_id uuid, p_name text, p_icon text) TO authenticated;
GRANT ALL ON FUNCTION public.rename_group(p_conversation_id uuid, p_name text, p_icon text) TO service_role;


--
-- Name: FUNCTION reorder_pro_offering_photos(p_offering_id uuid, p_photo_ids uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reorder_pro_offering_photos(p_offering_id uuid, p_photo_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reorder_pro_offering_photos(p_offering_id uuid, p_photo_ids uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.reorder_pro_offering_photos(p_offering_id uuid, p_photo_ids uuid[]) TO service_role;


--
-- Name: FUNCTION reorder_pro_photos(p_photo_ids uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reorder_pro_photos(p_photo_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reorder_pro_photos(p_photo_ids uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.reorder_pro_photos(p_photo_ids uuid[]) TO service_role;


--
-- Name: FUNCTION reply_to_offering_review(p_review_id uuid, p_reply text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reply_to_offering_review(p_review_id uuid, p_reply text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reply_to_offering_review(p_review_id uuid, p_reply text) TO authenticated;
GRANT ALL ON FUNCTION public.reply_to_offering_review(p_review_id uuid, p_reply text) TO service_role;


--
-- Name: FUNCTION reply_to_pro_review(p_review_id uuid, p_reply text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reply_to_pro_review(p_review_id uuid, p_reply text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reply_to_pro_review(p_review_id uuid, p_reply text) TO authenticated;
GRANT ALL ON FUNCTION public.reply_to_pro_review(p_review_id uuid, p_reply text) TO service_role;


--
-- Name: FUNCTION request_seat(p_activity_id uuid, p_driver_id uuid, p_pickup_from text, p_message text, p_requested_pickup_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.request_seat(p_activity_id uuid, p_driver_id uuid, p_pickup_from text, p_message text, p_requested_pickup_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.request_seat(p_activity_id uuid, p_driver_id uuid, p_pickup_from text, p_message text, p_requested_pickup_at timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.request_seat(p_activity_id uuid, p_driver_id uuid, p_pickup_from text, p_message text, p_requested_pickup_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION resubmit_pro_application(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.resubmit_pro_application() FROM PUBLIC;
GRANT ALL ON FUNCTION public.resubmit_pro_application() TO authenticated;
GRANT ALL ON FUNCTION public.resubmit_pro_application() TO service_role;


--
-- Name: FUNCTION reviews_touch_updated_at(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reviews_touch_updated_at() FROM PUBLIC;
GRANT ALL ON FUNCTION public.reviews_touch_updated_at() TO service_role;


--
-- Name: FUNCTION revoke_contact_qr_tokens(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revoke_contact_qr_tokens(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revoke_contact_qr_tokens(p_token text) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_contact_qr_tokens(p_token text) TO service_role;


--
-- Name: FUNCTION revoke_push_token_for_device(p_device_id text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revoke_push_token_for_device(p_device_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revoke_push_token_for_device(p_device_id text) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_push_token_for_device(p_device_id text) TO service_role;


--
-- Name: FUNCTION revoke_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revoke_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revoke_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text) TO service_role;


--
-- Name: FUNCTION sanitize_notif_text(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sanitize_notif_text(p text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sanitize_notif_text(p text) TO service_role;


--
-- Name: FUNCTION search_channels(p_query text, p_sport_key text, p_near_lng double precision, p_near_lat double precision); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.search_channels(p_query text, p_sport_key text, p_near_lng double precision, p_near_lat double precision) FROM PUBLIC;
GRANT ALL ON FUNCTION public.search_channels(p_query text, p_sport_key text, p_near_lng double precision, p_near_lat double precision) TO authenticated;
GRANT ALL ON FUNCTION public.search_channels(p_query text, p_sport_key text, p_near_lng double precision, p_near_lat double precision) TO service_role;


--
-- Name: FUNCTION send_activity_invitations(p_activity_id uuid, p_user_ids uuid[], p_message text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.send_activity_invitations(p_activity_id uuid, p_user_ids uuid[], p_message text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_activity_invitations(p_activity_id uuid, p_user_ids uuid[], p_message text) TO authenticated;
GRANT ALL ON FUNCTION public.send_activity_invitations(p_activity_id uuid, p_user_ids uuid[], p_message text) TO service_role;


--
-- Name: FUNCTION send_contact_request(p_target_user_id uuid, p_message text, p_source text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.send_contact_request(p_target_user_id uuid, p_message text, p_source text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_contact_request(p_target_user_id uuid, p_message text, p_source text) TO authenticated;
GRANT ALL ON FUNCTION public.send_contact_request(p_target_user_id uuid, p_message text, p_source text) TO service_role;


--
-- Name: FUNCTION send_discovery_invite(p_target_user_id uuid, p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.send_discovery_invite(p_target_user_id uuid, p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_discovery_invite(p_target_user_id uuid, p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.send_discovery_invite(p_target_user_id uuid, p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION send_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.send_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.send_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid) TO service_role;


--
-- Name: FUNCTION send_private_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.send_private_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_private_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.send_private_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid) TO service_role;


--
-- Name: FUNCTION send_wall_message(p_activity_id uuid, p_content text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.send_wall_message(p_activity_id uuid, p_content text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_wall_message(p_activity_id uuid, p_content text) TO authenticated;
GRANT ALL ON FUNCTION public.send_wall_message(p_activity_id uuid, p_content text) TO service_role;


--
-- Name: FUNCTION set_activity_gear(p_activity_id uuid, p_items jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_activity_gear(p_activity_id uuid, p_items jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_activity_gear(p_activity_id uuid, p_items jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.set_activity_gear(p_activity_id uuid, p_items jsonb) TO service_role;


--
-- Name: FUNCTION set_booking_participant_info(p_booking_id uuid, p_info jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_booking_participant_info(p_booking_id uuid, p_info jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_booking_participant_info(p_booking_id uuid, p_info jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.set_booking_participant_info(p_booking_id uuid, p_info jsonb) TO service_role;


--
-- Name: FUNCTION set_channel_photo(p_conversation_id uuid, p_photo_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_channel_photo(p_conversation_id uuid, p_photo_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_channel_photo(p_conversation_id uuid, p_photo_url text) TO authenticated;
GRANT ALL ON FUNCTION public.set_channel_photo(p_conversation_id uuid, p_photo_url text) TO service_role;


--
-- Name: FUNCTION set_conversation_hidden(p_conversation_id uuid, p_hidden boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_conversation_hidden(p_conversation_id uuid, p_hidden boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_conversation_hidden(p_conversation_id uuid, p_hidden boolean) TO authenticated;
GRANT ALL ON FUNCTION public.set_conversation_hidden(p_conversation_id uuid, p_hidden boolean) TO service_role;


--
-- Name: FUNCTION set_offering_details(p_offering_id uuid, p_equipment_provided text[], p_equipment_required text[], p_participant_std text[], p_participant_custom text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_offering_details(p_offering_id uuid, p_equipment_provided text[], p_equipment_required text[], p_participant_std text[], p_participant_custom text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_offering_details(p_offering_id uuid, p_equipment_provided text[], p_equipment_required text[], p_participant_std text[], p_participant_custom text[]) TO authenticated;
GRANT ALL ON FUNCTION public.set_offering_details(p_offering_id uuid, p_equipment_provided text[], p_equipment_required text[], p_participant_std text[], p_participant_custom text[]) TO service_role;


--
-- Name: FUNCTION set_participation_transport(p_activity_id uuid, p_transport_type text, p_transport_seats smallint, p_transport_from_name text, p_transport_departs_at timestamp with time zone, p_transport_from_lat double precision, p_transport_from_lng double precision, p_transport_from_locality text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_participation_transport(p_activity_id uuid, p_transport_type text, p_transport_seats smallint, p_transport_from_name text, p_transport_departs_at timestamp with time zone, p_transport_from_lat double precision, p_transport_from_lng double precision, p_transport_from_locality text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_participation_transport(p_activity_id uuid, p_transport_type text, p_transport_seats smallint, p_transport_from_name text, p_transport_departs_at timestamp with time zone, p_transport_from_lat double precision, p_transport_from_lng double precision, p_transport_from_locality text) TO service_role;
GRANT ALL ON FUNCTION public.set_participation_transport(p_activity_id uuid, p_transport_type text, p_transport_seats smallint, p_transport_from_name text, p_transport_departs_at timestamp with time zone, p_transport_from_lat double precision, p_transport_from_lng double precision, p_transport_from_locality text) TO authenticated;


--
-- Name: FUNCTION set_pro_availability(p_day date, p_period text, p_available boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_pro_availability(p_day date, p_period text, p_available boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_pro_availability(p_day date, p_period text, p_available boolean) TO authenticated;
GRANT ALL ON FUNCTION public.set_pro_availability(p_day date, p_period text, p_available boolean) TO service_role;


--
-- Name: FUNCTION set_pro_availability_bulk(p_days date[], p_periods text[], p_available boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_pro_availability_bulk(p_days date[], p_periods text[], p_available boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_pro_availability_bulk(p_days date[], p_periods text[], p_available boolean) TO authenticated;
GRANT ALL ON FUNCTION public.set_pro_availability_bulk(p_days date[], p_periods text[], p_available boolean) TO service_role;


--
-- Name: FUNCTION set_pro_pin_icon(p_pin_icon text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_pro_pin_icon(p_pin_icon text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_pro_pin_icon(p_pin_icon text) TO authenticated;
GRANT ALL ON FUNCTION public.set_pro_pin_icon(p_pin_icon text) TO service_role;


--
-- Name: FUNCTION set_pro_pin_image(p_pin_image_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_pro_pin_image(p_pin_image_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_pro_pin_image(p_pin_image_url text) TO authenticated;
GRANT ALL ON FUNCTION public.set_pro_pin_image(p_pin_image_url text) TO service_role;


--
-- Name: FUNCTION set_sport_level(p_sport_key text, p_new_level text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_sport_level(p_sport_key text, p_new_level text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_sport_level(p_sport_key text, p_new_level text) TO authenticated;
GRANT ALL ON FUNCTION public.set_sport_level(p_sport_key text, p_new_level text) TO service_role;


--
-- Name: FUNCTION share_activity_message(p_conversation_id uuid, p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.share_activity_message(p_conversation_id uuid, p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.share_activity_message(p_conversation_id uuid, p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.share_activity_message(p_conversation_id uuid, p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION share_trace_message(p_conversation_id uuid, p_trace_geojson jsonb, p_name text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.share_trace_message(p_conversation_id uuid, p_trace_geojson jsonb, p_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.share_trace_message(p_conversation_id uuid, p_trace_geojson jsonb, p_name text) TO authenticated;
GRANT ALL ON FUNCTION public.share_trace_message(p_conversation_id uuid, p_trace_geojson jsonb, p_name text) TO service_role;


--
-- Name: FUNCTION strip_html_messages(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.strip_html_messages() FROM PUBLIC;
GRANT ALL ON FUNCTION public.strip_html_messages() TO service_role;


--
-- Name: FUNCTION strip_html_reviews(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.strip_html_reviews() FROM PUBLIC;
GRANT ALL ON FUNCTION public.strip_html_reviews() TO service_role;


--
-- Name: FUNCTION strip_html_tags(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.strip_html_tags() FROM PUBLIC;
GRANT ALL ON FUNCTION public.strip_html_tags() TO service_role;


--
-- Name: FUNCTION strip_html_users(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.strip_html_users() FROM PUBLIC;
GRANT ALL ON FUNCTION public.strip_html_users() TO service_role;


--
-- Name: FUNCTION sync_activity_membership(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sync_activity_membership() FROM PUBLIC;
GRANT ALL ON FUNCTION public.sync_activity_membership() TO service_role;


--
-- Name: FUNCTION trace_distance_km(p_geojson jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trace_distance_km(p_geojson jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.trace_distance_km(p_geojson jsonb) TO service_role;


--
-- Name: FUNCTION trace_elevation_gain_m(p_geojson jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trace_elevation_gain_m(p_geojson jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.trace_elevation_gain_m(p_geojson jsonb) TO service_role;


--
-- Name: FUNCTION trace_geojson_ok(p_geojson jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trace_geojson_ok(p_geojson jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.trace_geojson_ok(p_geojson jsonb) TO service_role;


--
-- Name: FUNCTION transition_single_activity(p_activity_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.transition_single_activity(p_activity_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.transition_single_activity(p_activity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.transition_single_activity(p_activity_id uuid) TO service_role;


--
-- Name: FUNCTION transition_statuses_only(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.transition_statuses_only() FROM PUBLIC;
GRANT ALL ON FUNCTION public.transition_statuses_only() TO service_role;


--
-- Name: FUNCTION unregister_as_pro(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.unregister_as_pro() FROM PUBLIC;
GRANT ALL ON FUNCTION public.unregister_as_pro() TO authenticated;
GRANT ALL ON FUNCTION public.unregister_as_pro() TO service_role;


--
-- Name: FUNCTION update_activity(p_activity_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_level_max text, p_meeting_locality text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_activity(p_activity_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_level_max text, p_meeting_locality text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_activity(p_activity_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_level_max text, p_meeting_locality text) TO authenticated;
GRANT ALL ON FUNCTION public.update_activity(p_activity_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_level_max text, p_meeting_locality text) TO service_role;


--
-- Name: FUNCTION update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb) TO service_role;


--
-- Name: FUNCTION update_offering_review(p_review_id uuid, p_rating smallint, p_body text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_offering_review(p_review_id uuid, p_rating smallint, p_body text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_offering_review(p_review_id uuid, p_rating smallint, p_body text) TO authenticated;
GRANT ALL ON FUNCTION public.update_offering_review(p_review_id uuid, p_rating smallint, p_body text) TO service_role;


--
-- Name: FUNCTION update_pro_offering(p_offering_id uuid, p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_pro_offering(p_offering_id uuid, p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_pro_offering(p_offering_id uuid, p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer) TO authenticated;
GRANT ALL ON FUNCTION public.update_pro_offering(p_offering_id uuid, p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer) TO service_role;


--
-- Name: FUNCTION update_pro_profile(p_display_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text, p_company_name text, p_real_name text, p_clear text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_pro_profile(p_display_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text, p_company_name text, p_real_name text, p_clear text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_pro_profile(p_display_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text, p_company_name text, p_real_name text, p_clear text[]) TO authenticated;
GRANT ALL ON FUNCTION public.update_pro_profile(p_display_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text, p_company_name text, p_real_name text, p_clear text[]) TO service_role;


--
-- Name: FUNCTION update_pro_review(p_review_id uuid, p_rating smallint, p_body text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_pro_review(p_review_id uuid, p_rating smallint, p_body text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_pro_review(p_review_id uuid, p_rating smallint, p_body text) TO authenticated;
GRANT ALL ON FUNCTION public.update_pro_review(p_review_id uuid, p_rating smallint, p_body text) TO service_role;


--
-- Name: FUNCTION upsert_dispo(p_sport_keys text[], p_levels jsonb, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_transport_modes text[], p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_intent text[], p_about text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.upsert_dispo(p_sport_keys text[], p_levels jsonb, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_transport_modes text[], p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_intent text[], p_about text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.upsert_dispo(p_sport_keys text[], p_levels jsonb, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_transport_modes text[], p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_intent text[], p_about text) TO authenticated;
GRANT ALL ON FUNCTION public.upsert_dispo(p_sport_keys text[], p_levels jsonb, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_transport_modes text[], p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_intent text[], p_about text) TO service_role;


--
-- Name: FUNCTION waive_late_cancel_penalty(p_participation_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.waive_late_cancel_penalty(p_participation_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.waive_late_cancel_penalty(p_participation_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.waive_late_cancel_penalty(p_participation_id uuid) TO service_role;


--
-- Name: TABLE activity_alerts; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.activity_alerts TO anon;
GRANT SELECT,DELETE ON TABLE public.activity_alerts TO authenticated;
GRANT ALL ON TABLE public.activity_alerts TO service_role;


--
-- Name: TABLE activity_gear; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.activity_gear TO anon;
GRANT SELECT ON TABLE public.activity_gear TO authenticated;
GRANT ALL ON TABLE public.activity_gear TO service_role;


--
-- Name: TABLE activity_gear_missing; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.activity_gear_missing TO authenticated;
GRANT ALL ON TABLE public.activity_gear_missing TO service_role;


--
-- Name: TABLE activity_participants; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.activity_participants TO authenticated;
GRANT ALL ON TABLE public.activity_participants TO service_role;


--
-- Name: TABLE admin_actions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.admin_actions TO service_role;
GRANT SELECT ON TABLE public.admin_actions TO authenticated;


--
-- Name: TABLE app_config; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.app_config TO anon;
GRANT SELECT ON TABLE public.app_config TO authenticated;
GRANT ALL ON TABLE public.app_config TO service_role;


--
-- Name: TABLE banned_email_hashes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.banned_email_hashes TO service_role;


--
-- Name: TABLE bookings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.bookings TO service_role;


--
-- Name: COLUMN bookings.id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(id) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.offering_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(offering_id) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.pro_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(pro_id) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.client_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(client_id) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.manual_name; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(manual_name) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.manual_phone; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(manual_phone) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.day; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(day) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.period; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(period) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.party_size; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(party_size) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.message; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(message) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.status; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(status) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.created_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(created_at) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.updated_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(updated_at) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.submitted_count; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(submitted_count) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.last_submitted_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(last_submitted_at) ON TABLE public.bookings TO authenticated;


--
-- Name: TABLE channel_bans; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.channel_bans TO service_role;


--
-- Name: TABLE channels; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.channels TO service_role;


--
-- Name: TABLE contact_qr_scans; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.contact_qr_scans TO service_role;


--
-- Name: TABLE contact_qr_tokens; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.contact_qr_tokens TO service_role;


--
-- Name: TABLE contact_removal_archive; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.contact_removal_archive TO service_role;


--
-- Name: TABLE conversation_departures; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.conversation_departures TO service_role;


--
-- Name: TABLE conversation_members; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.conversation_members TO authenticated;
GRANT ALL ON TABLE public.conversation_members TO service_role;


--
-- Name: TABLE conversations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.conversations TO service_role;


--
-- Name: TABLE discovery_availabilities; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.discovery_availabilities TO authenticated;
GRANT ALL ON TABLE public.discovery_availabilities TO service_role;


--
-- Name: TABLE favorites; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.favorites TO authenticated;
GRANT ALL ON TABLE public.favorites TO service_role;


--
-- Name: TABLE gear_catalog; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.gear_catalog TO anon;
GRANT SELECT ON TABLE public.gear_catalog TO authenticated;
GRANT ALL ON TABLE public.gear_catalog TO service_role;


--
-- Name: TABLE invitation_declines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.invitation_declines TO service_role;


--
-- Name: TABLE invite_grants; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.invite_grants TO service_role;


--
-- Name: TABLE late_cancels; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.late_cancels TO service_role;


--
-- Name: TABLE map_broadcasts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.map_broadcasts TO service_role;


--
-- Name: TABLE message_original_content; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.message_original_content TO service_role;


--
-- Name: TABLE messages; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.messages TO authenticated;
GRANT ALL ON TABLE public.messages TO service_role;


--
-- Name: TABLE my_activities; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.my_activities TO anon;
GRANT SELECT ON TABLE public.my_activities TO authenticated;
GRANT ALL ON TABLE public.my_activities TO service_role;


--
-- Name: TABLE my_joined_activities; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.my_joined_activities TO anon;
GRANT SELECT ON TABLE public.my_joined_activities TO authenticated;
GRANT ALL ON TABLE public.my_joined_activities TO service_role;


--
-- Name: TABLE my_pending_activities; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.my_pending_activities TO anon;
GRANT SELECT ON TABLE public.my_pending_activities TO authenticated;
GRANT ALL ON TABLE public.my_pending_activities TO service_role;


--
-- Name: TABLE notifications; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.notifications TO anon;
GRANT SELECT,UPDATE ON TABLE public.notifications TO authenticated;
GRANT ALL ON TABLE public.notifications TO service_role;


--
-- Name: TABLE offering_reviews; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.offering_reviews TO anon;
GRANT SELECT ON TABLE public.offering_reviews TO authenticated;
GRANT ALL ON TABLE public.offering_reviews TO service_role;


--
-- Name: TABLE pro_offerings; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.pro_offerings TO anon;
GRANT SELECT ON TABLE public.pro_offerings TO authenticated;
GRANT ALL ON TABLE public.pro_offerings TO service_role;


--
-- Name: TABLE pro_profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_profiles TO service_role;


--
-- Name: COLUMN pro_profiles.user_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(user_id) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.display_name; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(display_name) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.tagline; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(tagline) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.description; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(description) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.website; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(website) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.email; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(email) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.phone; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(phone) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.instagram; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(instagram) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.facebook; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(facebook) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.primary_lng; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(primary_lng) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.primary_lat; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(primary_lat) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.primary_location_name; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(primary_location_name) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.last_location_change_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(last_location_change_at) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.created_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(created_at) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.updated_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(updated_at) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.pin_image_url; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(pin_image_url) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.status; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(status) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.pin_icon; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(pin_icon) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: COLUMN pro_profiles.is_demo; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(is_demo) ON TABLE public.pro_profiles TO authenticated;


--
-- Name: TABLE offering_review_stats; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.offering_review_stats TO authenticated;
GRANT ALL ON TABLE public.offering_review_stats TO service_role;


--
-- Name: TABLE offering_reviews_with_profiles; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.offering_reviews_with_profiles TO authenticated;
GRANT ALL ON TABLE public.offering_reviews_with_profiles TO service_role;


--
-- Name: TABLE presence_tokens; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.presence_tokens TO anon;
GRANT SELECT ON TABLE public.presence_tokens TO authenticated;
GRANT ALL ON TABLE public.presence_tokens TO service_role;


--
-- Name: TABLE pro_availabilities; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.pro_availabilities TO authenticated;
GRANT ALL ON TABLE public.pro_availabilities TO service_role;


--
-- Name: TABLE pro_community_photos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.pro_community_photos TO authenticated;
GRANT ALL ON TABLE public.pro_community_photos TO service_role;


--
-- Name: TABLE pro_offering_photos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.pro_offering_photos TO anon;
GRANT SELECT ON TABLE public.pro_offering_photos TO authenticated;
GRANT ALL ON TABLE public.pro_offering_photos TO service_role;


--
-- Name: TABLE pro_offerings_with_coords; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.pro_offerings_with_coords TO anon;
GRANT SELECT ON TABLE public.pro_offerings_with_coords TO authenticated;
GRANT ALL ON TABLE public.pro_offerings_with_coords TO service_role;


--
-- Name: TABLE pro_profile_photos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.pro_profile_photos TO anon;
GRANT SELECT ON TABLE public.pro_profile_photos TO authenticated;
GRANT ALL ON TABLE public.pro_profile_photos TO service_role;


--
-- Name: TABLE pro_reviews; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.pro_reviews TO anon;
GRANT SELECT ON TABLE public.pro_reviews TO authenticated;
GRANT ALL ON TABLE public.pro_reviews TO service_role;


--
-- Name: TABLE pro_review_stats; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.pro_review_stats TO authenticated;
GRANT ALL ON TABLE public.pro_review_stats TO service_role;


--
-- Name: TABLE pro_reviews_with_profiles; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.pro_reviews_with_profiles TO authenticated;
GRANT ALL ON TABLE public.pro_reviews_with_profiles TO service_role;


--
-- Name: TABLE push_tokens; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.push_tokens TO anon;
GRANT SELECT ON TABLE public.push_tokens TO authenticated;
GRANT ALL ON TABLE public.push_tokens TO service_role;


--
-- Name: TABLE rate_events; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.rate_events TO service_role;


--
-- Name: TABLE reports; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.reports TO anon;
GRANT SELECT,UPDATE ON TABLE public.reports TO authenticated;
GRANT ALL ON TABLE public.reports TO service_role;


--
-- Name: TABLE reputation_votes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.reputation_votes TO anon;
GRANT SELECT ON TABLE public.reputation_votes TO authenticated;
GRANT ALL ON TABLE public.reputation_votes TO service_role;


--
-- Name: TABLE seat_requests; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.seat_requests TO anon;
GRANT SELECT ON TABLE public.seat_requests TO authenticated;
GRANT ALL ON TABLE public.seat_requests TO service_role;


--
-- Name: TABLE snap_trail_calls; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.snap_trail_calls TO service_role;


--
-- Name: TABLE trace_elevation_calls; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.trace_elevation_calls TO service_role;


--
-- Name: TABLE user_badge_progression; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT ON TABLE public.user_badge_progression TO anon;
GRANT SELECT ON TABLE public.user_badge_progression TO authenticated;
GRANT ALL ON TABLE public.user_badge_progression TO service_role;



-- ===== 50_outside_dump.sql =====
-- Generated from the old project 2026-10-22 — do not edit by hand.

CREATE TRIGGER junto_storage_object_quota BEFORE INSERT ON storage.objects FOR EACH ROW EXECUTE FUNCTION private.storage_object_quota();
CREATE TRIGGER junto_refuse_banned_email_change BEFORE UPDATE OF email ON auth.users FOR EACH ROW EXECUTE FUNCTION private.refuse_banned_email_change();
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('avatars', 'avatars', 't', 5242880, '{image/jpeg,image/png,image/webp}');
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('channel-photos', 'channel-photos', 't', 5242880, '{image/jpeg,image/png,image/webp}');
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('pro-photos', 'pro-photos', 't', 5242880, '{image/jpeg,image/png,image/webp}');

CREATE POLICY realtime_activity_topics_read ON realtime.messages AS PERMISSIVE FOR SELECT TO authenticated USING (((realtime.topic() ~~ 'activity:%'::text) AND ((EXISTS ( SELECT 1
   FROM public.participations p
  WHERE (((p.activity_id)::text = "substring"(realtime.topic(), 10)) AND (p.user_id = auth.uid()) AND (p.status = 'accepted'::text)))) OR (EXISTS ( SELECT 1
   FROM public.activities a
  WHERE (((a.id)::text = "substring"(realtime.topic(), 10)) AND (a.creator_id = auth.uid()))))) AND (NOT private.user_is_suspended(auth.uid()))));
CREATE POLICY realtime_conversation_topics_read ON realtime.messages AS PERMISSIVE FOR SELECT TO authenticated USING (((realtime.topic() ~~ 'conversation:%'::text) AND (EXISTS ( SELECT 1
   FROM public.conversation_members cm
  WHERE (((cm.conversation_id)::text = "substring"(realtime.topic(), 14)) AND (cm.user_id = auth.uid())))) AND (NOT private.user_is_suspended(auth.uid()))));
CREATE POLICY realtime_map_topic_read ON realtime.messages AS PERMISSIVE FOR SELECT TO authenticated USING ((realtime.topic() = 'map'::text));
CREATE POLICY realtime_user_topic_read ON realtime.messages AS PERMISSIVE FOR SELECT TO authenticated USING ((realtime.topic() = ('user:'::text || (auth.uid())::text)));
CREATE POLICY avatars_delete_own ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY avatars_insert_own ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY avatars_read_own ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY avatars_update_own ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY channel_photos_delete_own ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated USING (((bucket_id = 'channel-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY channel_photos_insert_own ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'channel-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY channel_photos_read_own ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated USING (((bucket_id = 'channel-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY channel_photos_update_own ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated USING (((bucket_id = 'channel-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY pro_photos_delete_own ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated USING (((bucket_id = 'pro-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY pro_photos_insert_own ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'pro-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY pro_photos_read_own ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated USING (((bucket_id = 'pro-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY pro_photos_update_own ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated USING (((bucket_id = 'pro-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));

ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.seat_requests;

SELECT cron.schedule('junto-booking-participant-purge', '15 4 * * *', 'SELECT public.purge_booking_participant_info();');
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'junto-booking-participant-purge'), active := false);
SELECT cron.schedule('junto-contact-archive-purge', '30 4 * * *', 'SELECT public.purge_contact_removal_archive();');
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'junto-contact-archive-purge'), active := false);
SELECT cron.schedule('junto-cron-log-purge', '50 4 * * *', 'DELETE FROM cron.job_run_details WHERE end_time < now() - interval ''7 days''');
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'junto-cron-log-purge'), active := false);
SELECT cron.schedule('junto-notif-purge', '0 4 * * *', 'SELECT public.purge_old_notifications();');
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'junto-notif-purge'), active := false);
SELECT cron.schedule('junto-presence-sweep', '* * * * *', 'SELECT public.check_activity_transitions();');
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'junto-presence-sweep'), active := false);
SELECT cron.schedule('junto-throttle-purge', '45 4 * * *', 'SELECT public.purge_throttle_tables();');
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'junto-throttle-purge'), active := false);
-- ===== 55_role_time_limits.sql =====
DO $r$ BEGIN EXECUTE 'ALTER ROLE anon SET statement_timeout = ''3s'''; EXCEPTION WHEN insufficient_privilege THEN RAISE WARNING 'refused: anon statement_timeout=3s'; END $r$;
DO $r$ BEGIN EXECUTE 'ALTER ROLE authenticated SET statement_timeout = ''8s'''; EXCEPTION WHEN insufficient_privilege THEN RAISE WARNING 'refused: authenticated statement_timeout=8s'; END $r$;
DO $r$ BEGIN EXECUTE 'ALTER ROLE authenticator SET lock_timeout = ''8s'''; EXCEPTION WHEN insufficient_privilege THEN RAISE WARNING 'refused: authenticator lock_timeout=8s'; END $r$;
DO $r$ BEGIN EXECUTE 'ALTER ROLE authenticator SET statement_timeout = ''8s'''; EXCEPTION WHEN insufficient_privilege THEN RAISE WARNING 'refused: authenticator statement_timeout=8s'; END $r$;
-- ===== 60_reference_data.sql =====
--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: banned_email_hashes; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: gear_catalog; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('005dae45-d2c3-46f7-8f57-2e61bec65aa2', 'Eau / Gourde', '{hiking,mountaineering,trail-running,cycling,climbing-sport,climbing-multipitch,mtb-xc,mtb-enduro,mtb-downhill,gravel,snowshoeing,trekking}', 32, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('32442737-23e1-4646-b2db-72c4679b3f93', 'Chaussons escalade', '{climbing-sport,climbing-multipitch}', 9, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('d39c3e32-8937-4658-992a-849e36d5049a', 'Magnésie', '{climbing-sport,climbing-multipitch}', 10, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('b04679f5-09de-4217-bb26-02857e477200', 'Corde 70m', '{mountaineering,ice-climbing,climbing-sport,climbing-multipitch}', 2, 'technical', false, 1, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('e95405e3-62e8-4834-8968-69a6066897f8', 'Piolet', '{mountaineering,ice-climbing}', 12, 'technical', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('e0ad6f4b-6640-4302-a471-55d2d2dba281', 'Voile', '{paragliding}', 17, 'technical', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('8880fb08-5034-48ec-951e-4400c4f198cb', 'Sellette', '{paragliding}', 18, 'technical', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('0c9d5c65-6ebf-42f2-8bd0-e0dca12f3dce', 'Planche', '{surfing,stand-up-paddle}', 24, 'water', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('b15ab9cf-0039-48e9-b5bf-2be26bb68903', 'Carte / GPS', '{hiking,mountaineering,ski-touring,trail-running}', 31, 'personal', false, 1, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('7665a2b9-36f6-49fb-8029-c18b25f6780b', 'Pagaie', '{kayaking,stand-up-paddle,rafting}', 22, 'water', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('775bb883-4db0-463b-9a5e-3461ab1b52bb', 'Combinaison néoprène', '{canyoning,kayaking,surfing,diving,freediving,caving}', 14, 'water', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('d7bf0be4-7b91-492c-bf15-0cdbf333c4fd', 'Corde 30m (canyon)', '{canyoning}', 16, 'technical', false, 1, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('04ff4348-af90-4e32-afea-c5d326d2fdee', 'Corde 60m (canyon)', '{canyoning}', 17, 'technical', false, 1, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('e2a03fea-38df-489e-8095-6fb5b6f2f03f', 'Corde 80m (canyon)', '{canyoning}', 18, 'technical', false, 1, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('1ef2f2a8-4cd7-42f1-99b7-ec285829539e', 'Sangles', '{ice-climbing,mountaineering,climbing-sport,climbing-multipitch,canyoning}', 8, 'technical', false, 3, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('ead71ed4-5895-4e39-943c-bf349aad15bd', 'Broches à glace', '{ice-climbing,mountaineering}', 13, 'technical', false, 3, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('5d4f7362-dab4-400b-b084-095005833f2d', 'Bidon étanche', '{canyoning,kayaking,rafting,stand-up-paddle}', 16, 'water', false, 1, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('5e4d65c1-56f2-4efc-bba9-c318d0a09f11', 'Baudrier', '{ice-climbing,mountaineering,via-ferrata,climbing-sport,climbing-multipitch,dry-tooling,caving,canyoning}', 4, 'safety', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('de4c8e53-936b-4b72-a175-01342601a586', 'Peaux de phoque', '{ski-touring,splitboard}', 28, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('931b1e35-816d-4b47-a49e-8d80e5c8cd8e', 'DVA', '{ski-touring,skiing,snowshoeing,ski-freeride,splitboard}', 25, 'safety', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('3b42019b-cfaf-4cc5-8056-1c2dd6c25510', 'Pelle', '{ski-touring,snowshoeing,ski-freeride,splitboard}', 26, 'safety', false, 1, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('8e3097c4-ec12-497b-a4b6-875fa6917673', 'Sonde', '{ski-touring,snowshoeing,ski-freeride,splitboard}', 27, 'safety', false, 1, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('e664b612-0f46-4500-91c7-1ddd6bc16213', 'Assureur', '{mountaineering,ice-climbing,climbing-sport,climbing-multipitch,dry-tooling}', 6, 'technical', false, 1, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('7ede7590-3e2c-4d33-b005-f26db0524283', 'Corde 60m', '{mountaineering,ice-climbing,climbing-sport,climbing-multipitch,dry-tooling}', 1, 'technical', false, 1, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('cab869e2-44e2-470e-a577-b878a309ba6a', 'Crampons', '{mountaineering,ice-climbing,ski-touring,dry-tooling}', 11, 'technical', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('aafec1af-1c24-4deb-89ff-9ecf0180ec10', 'Dégaines', '{mountaineering,via-ferrata,climbing-sport,climbing-multipitch,dry-tooling}', 3, 'technical', false, 6, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('dde4bcac-583d-4322-bd38-c5281d0fb2a4', 'Secours', '{paragliding,hang-gliding}', 19, 'safety', false, 1, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('7f552dac-f872-4699-a8e1-c7aad1c6040c', 'Variomètre', '{paragliding,hang-gliding}', 20, 'technical', false, 1, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('c5d42cfa-f181-407e-9e23-f12f9e398a01', 'Radio', '{paragliding,mountaineering,ski-touring,speed-riding,hang-gliding}', 21, 'personal', false, 1, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('b6e5bc07-657f-4a8b-8531-5b3136d779c8', 'Descendeur', '{canyoning,caving}', 15, 'technical', false, 1, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('e511b104-1811-48e0-ab6e-2157884415bf', 'Bouteille de plongée', '{diving}', 40, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('508477e5-6db2-49d5-ae5e-16854a770891', 'Détendeur', '{diving}', 41, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('2f708064-fbc9-463e-a81c-4aaa86a67744', 'Gilet stabilisateur', '{diving}', 42, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('6daeab7f-435c-40c5-be3f-462ff2342cdc', 'Masque', '{diving,freediving}', 43, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('7f23b274-7d9b-4a70-92d9-715f9e03dd45', 'Palmes', '{diving,freediving}', 44, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('bcac9bdb-cf76-4d4a-b496-c67adb611e2f', 'Ordinateur de plongée', '{diving,freediving}', 45, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('5f19abfa-351e-462c-bd49-b4796ae7cc06', 'Gants', '{mtb-xc,mtb-enduro,mtb-downhill,gravel,cycling}', 46, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('bd0b7817-829b-429f-85eb-12a56acaeee9', 'Chambre à air', '{mtb-xc,mtb-enduro,mtb-downhill,gravel,cycling}', 47, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('341aba07-5f01-4224-9b38-868b90c9c6c2', 'Kit de réparation', '{mtb-xc,mtb-enduro,mtb-downhill,gravel,cycling}', 48, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('0f584faa-455a-406f-a906-57f317cf344d', 'Pompe', '{mtb-xc,mtb-enduro,mtb-downhill,gravel,cycling}', 49, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('806fcdba-dd83-48ac-bc08-b5823be27ee6', 'Protections (genoux/coudes)', '{mtb-enduro,mtb-downhill}', 50, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('c777dec3-ca26-402a-b858-2dc7b0ec3312', 'Casque intégral', '{mtb-downhill}', 51, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('be1449c1-bd3e-448f-9634-506d28865a99', 'Crashpad', '{bouldering}', 52, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('65c7ff44-607c-4edb-af72-506db574080c', 'Brosse', '{bouldering}', 53, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('f327cd81-c958-47c1-8fd2-138f862fa919', 'Coinceurs / Friends', '{climbing-multipitch,mountaineering}', 54, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('077a4431-a447-48d7-94f3-734b7d42e306', 'Topo', '{climbing-multipitch,caving}', 55, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('fd03dd7f-2736-466a-bd98-073756bd156b', 'Piolets dry-tooling', '{dry-tooling}', 56, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('67d13df2-d23b-4563-a8e4-1f584c2e2203', 'Raquettes', '{snowshoeing}', 57, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('9b3d7e28-722d-4892-a2d7-c53c573838a0', 'Airbag', '{ski-freeride,splitboard,ski-touring}', 58, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('c710df97-7d38-4d80-bfa6-9988fbf7fa6b', 'Aile', '{speed-riding,hang-gliding}', 59, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('be57645c-bd2e-4d03-8d0b-4e672606d0e3', 'Sellette / harnais', '{speed-riding,hang-gliding}', 60, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('94bf6d57-39d7-4602-9730-8093658c2397', 'Plomb', '{freediving}', 61, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('92d9e8be-2863-41e2-a4b9-fbb4558397a6', 'Descendeur / croll', '{caving}', 64, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('287f6d53-a9de-4635-9910-c0d8508ffc18', 'Skis de fond', '{cross-country-ski}', 65, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('ba910d85-bcbe-43c9-af73-f35da042d851', 'Lampe frontale', '{hiking,mountaineering,canyoning,trail-running,via-ferrata,ski-touring,climbing-sport,climbing-multipitch,snowshoeing,caving,trekking}', 30, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('8eae6662-d200-43d0-9bad-d2260ae0fd3f', 'Trousse de secours', '{hiking,mountaineering,ski-touring,trail-running,canyoning,via-ferrata,climbing-sport,climbing-multipitch,snowshoeing,caving,trekking}', 29, 'safety', false, 1, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('16a9e4b5-edaa-4a63-8db6-cd18a92d97ce', 'Mousquetons', '{ice-climbing,mountaineering,via-ferrata,climbing-sport,climbing-multipitch,dry-tooling,caving,canyoning}', 7, 'technical', false, 15, true);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('f56a1477-06e0-4627-add2-6a0fcfa92924', 'Sangle highline', '{}', 62, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('bb4e4b83-1a76-46d2-a7e2-d127fb7a2828', 'Backup / longe', '{}', 63, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('8d5113d9-85e8-4abe-9df9-7cfa96951938', 'Bâtons', '{cross-country-ski,ski-touring,snowshoeing,trekking}', 66, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('4c433950-89ec-43e8-88f9-cb9dba6ef4f5', 'Casque', '{ice-climbing,kayaking,mountaineering,ski-touring,skiing,via-ferrata,climbing-sport,climbing-multipitch,dry-tooling,ski-freeride,splitboard,speed-riding,hang-gliding,cycling,mtb-xc,mtb-enduro,mtb-downhill,gravel,caving,canoe,canyoning}', 5, 'safety', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('b55a9a50-3f24-4082-94df-8cef6486bd40', 'Combinaison', '{canoe}', 67, 'personal', true, NULL, false);
INSERT INTO public.gear_catalog (id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared) VALUES ('0d05f89f-69aa-45ad-9836-27da6a89d9df', 'Gilet de sauvetage', '{kayaking,rafting,sailing,stand-up-paddle,canoe}', 23, 'safety', true, NULL, false);


--
-- Data for Name: sports; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('52efcfad-0ea7-4392-9a54-60a688d18b3f', 'nordic-walking', 'nordic-walking', 'on-foot', 49, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('2cc02fb0-fce5-40fa-a328-e6f5408a998d', 'kitesurfing', 'kitesurfing', 'water', 50, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('31d84bd1-ee10-4ed3-8ad9-7365d1b14394', 'wingfoil', 'wingfoil', 'water', 51, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('5944d9e5-b586-4c1e-ab14-9e2930f34945', 'cross-country-ski', 'cross-country-ski', 'mountain', 4, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('c8f608e4-347d-4d9d-801d-78ef0f15c51a', 'diving', 'diving', 'water', 7, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('3d5e407f-3081-440d-8402-d01c8a9edda5', 'ice-climbing', 'ice-climbing', 'mountain', 11, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('89d6c7d5-24aa-4618-ab9c-6a56d978c539', 'kayaking', 'kayaking', 'water', 12, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('d249838e-b505-4dfb-b8ad-6c0d4332236e', 'mountaineering', 'mountaineering', 'mountain', 14, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('1fa71b33-b2e2-4ae6-a29d-8bd8b3f46478', 'paragliding', 'paragliding', 'air', 15, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('86c24bec-b33f-480d-ad3b-0fe47feb3522', 'rafting', 'rafting', 'water', 16, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('8bdc6597-e40d-463c-ac69-26c24f9dea2f', 'sailing', 'sailing', 'water', 19, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('d6dc5a6f-690f-4bde-9f68-3faadd4713cc', 'ski-touring', 'ski-touring', 'mountain', 21, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('576061a8-0d41-4e30-9c9e-3079be42a572', 'skiing', 'skiing', 'mountain', 22, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('ccb62227-7055-4a39-95ec-026f502fe580', 'skydiving', 'skydiving', 'air', 23, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('44a7c956-1179-4f1a-823a-fe31cf3ed9c7', 'snowboarding', 'snowboarding', 'mountain', 25, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('443ceeba-bece-425c-983c-e377e158a95b', 'stand-up-paddle', 'stand-up-paddle', 'water', 26, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('551c2af2-d650-4b7a-bc0b-8b1ee30f4d71', 'surfing', 'surfing', 'water', 27, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('077578a3-2121-4d4d-8e7b-343e60d921e5', 'swimming', 'swimming', 'water', 28, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('852f103e-19a6-4916-9107-ffa1726e35b9', 'via-ferrata', 'via-ferrata', 'mountain', 32, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('d8568b91-d02d-4fd1-aade-c12e0ca66652', 'climbing-sport', 'climbing-sport', 'mountain', 20, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('9be2b860-0961-4784-aeca-62ab39907188', 'climbing-multipitch', 'climbing-multipitch', 'mountain', 21, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('ea5be97f-3101-491f-b4db-7aff662f0f6d', 'bouldering', 'bouldering', 'mountain', 22, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('879729f8-493a-41fc-996e-03aa9f654a86', 'dry-tooling', 'dry-tooling', 'mountain', 23, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('654345bb-fac1-40a1-8153-846dc9e1b67a', 'snowshoeing', 'snowshoeing', 'mountain', 26, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('04886c25-6afb-4001-abce-8e002c8a4fc0', 'ski-freeride', 'ski-freeride', 'mountain', 27, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('2ac9adc7-6b23-49ec-ad01-f78e3decf2e1', 'splitboard', 'splitboard', 'mountain', 28, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('21e697b6-db31-4a6d-96f6-81d773d5ce4a', 'speed-riding', 'speed-riding', 'air', 33, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('6f4b7859-ae78-4d6a-b86b-39fd0a0e1b30', 'hang-gliding', 'hang-gliding', 'air', 34, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('ecc3071d-cd10-4ec0-8d6c-5f28cf63e665', 'freediving', 'freediving', 'water', 35, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('bbdfff6f-28f7-4aad-93ee-cd0a103e9d02', 'cycling', 'cycling', 'cycling', 6, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('eecfea77-6b63-4efc-a4c2-5f7d3fc75848', 'mtb-xc', 'mtb-xc', 'cycling', 29, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('6a96e5e3-665c-4d81-a848-004dd1e5bca4', 'mtb-enduro', 'mtb-enduro', 'cycling', 30, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('598452bb-3ef1-41a7-8000-6b9bfc94aa34', 'mtb-downhill', 'mtb-downhill', 'cycling', 31, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('6367be54-59b8-46ef-840d-9d23e979fb43', 'gravel', 'gravel', 'cycling', 32, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('d90e7d3c-91d1-49aa-925c-9bc8145eff02', 'caving', 'caving', 'mountain', 24, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('2ba07e3f-14f5-4fcf-ab8f-539aab627ad6', 'canoe', 'canoe', 'water', 41, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('3f3eaa77-1de6-468a-b759-1102e8194f20', 'running', 'running', 'on-foot', 18, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('a1e46b33-0e11-4de5-a11f-55b7e772a651', 'hiking', 'hiking', 'on-foot', 9, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('9166b9f5-bef1-4999-8b9c-703d4f3ae7e0', 'trail-running', 'trail-running', 'on-foot', 30, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('9a8a980c-9fb3-4242-b90c-b82ca711d3cd', 'trekking', 'trekking', 'on-foot', 40, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('12879550-9bb8-4ec0-9dc3-5a1c2e82c40d', 'canyoning', 'canyoning', 'water', 2, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('8055ff58-02bb-4b09-b07e-a5fb47708ff2', 'football', 'football', 'on-foot', 42, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('9c455cd5-be79-48b1-9012-aeff9d2fab43', 'windsurfing', 'windsurfing', 'water', 43, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('78153aca-31ad-486a-bfed-b169c6381eee', 'wakeboard', 'wakeboard', 'water', 44, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('6b458948-ed3d-4115-8297-b5ea587db4fc', 'yoga', 'yoga', 'wellness', 45, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('ea68c603-83f5-444a-8dcb-ba65aa047bc7', 'tai-chi', 'tai-chi', 'wellness', 46, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('36e6be24-8994-470b-90e5-404ee48fe250', 'qi-gong', 'qi-gong', 'wellness', 47, true);
INSERT INTO public.sports (id, key, icon, category, display_order, is_active) VALUES ('63017b5b-4976-475e-a9c1-36abdc9af46c', 'meditation', 'meditation', 'wellness', 48, true);


--
-- PostgreSQL database dump complete
--



INSERT INTO public.app_config (name, value) VALUES
  ('demo_mode', 'false'),
  ('project_url', 'https://fajfigpwfdwmchhzecwe.supabase.co'),
  ('email_ban_pepper', '<set from the old project>'),  -- same key: banned fingerprints stay valid
  ('push_webhook_secret', '<set in phase D>');

-- ===== 70_default_privileges_final.sql =====
-- Old project (2026-10-22): functions executable by nobody unless granted;
-- public tables give clients SELECT only; service_role keeps full access.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO service_role;
NOTIFY pgrst, 'reload schema';

-- ===== 80_migration_history.sql =====
CREATE SCHEMA IF NOT EXISTS supabase_migrations;
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (version text PRIMARY KEY, statements text[], name text);
INSERT INTO supabase_migrations.schema_migrations (version, name) VALUES ('00526', 'baseline')
ON CONFLICT (version) DO NOTHING;
