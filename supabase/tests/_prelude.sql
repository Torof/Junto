-- Junto DB test harness — prelude (executed at the top of every test block).
--
-- Every test file runs inside ONE `DO` block that ALWAYS ends with an
-- exception carrying the results: the whole block is rolled back, nothing is
-- ever committed (accounts, rows, queued HTTP calls, realtime messages). The
-- runner then checks that no test account survived.
--
-- Helpers (all in pg_temp, gone with the transaction):
--   pg_temp.user(label, flags)  create an auth user (+ public.users via trigger);
--                               flags: 'tos' 'admin' 'suspended' 'demo' (comma list)
--   pg_temp.id(label) / pg_temp.put(label, value) / pg_temp.get(label)
--   pg_temp.as_(label)          act as that user (role authenticated + JWT sub);
--                               'anon' = anonymous visitor, 'db' = back to postgres
--   pg_temp.ok(name, sql [, known])        passes if the statement runs; returns its first value
--   pg_temp.denied(name, sql [, pattern [, known]])  passes if it raises an error matching pattern
--   pg_temp.eq(name, sql, expected [, known])        passes if the first value equals expected
-- `known` = id of an audit finding (e.g. 'ID-2'): the check documents a known hole and is
-- EXPECTED to fail until fixed (reported as xfail; an unexpected pass is reported as xpass).

EXECUTE $p$CREATE TEMP TABLE junto_ctx (k text PRIMARY KEY, v text)$p$;
EXECUTE $p$CREATE TEMP TABLE junto_results (n serial, name text, status text, detail text, known text)$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.put(p_k text, p_v text) RETURNS text
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  BEGIN INSERT INTO pg_temp.junto_ctx VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v; RETURN p_v; END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.get(p_k text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT v FROM pg_temp.junto_ctx WHERE k = p_k $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT v::uuid FROM pg_temp.junto_ctx WHERE k = p_k $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.rec(p_name text, p_ok boolean, p_detail text, p_known text) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  BEGIN
    INSERT INTO pg_temp.junto_results (name, status, detail, known) VALUES (
      p_name,
      CASE WHEN p_ok AND p_known IS NULL THEN 'pass'
           WHEN p_ok THEN 'xpass'
           WHEN p_known IS NULL THEN 'fail'
           ELSE 'xfail' END,
      left(p_detail, 300), p_known);
  END $b$$p$;

-- 00524: the project host comes from app_config (never hardcoded in tests).
EXECUTE $p$CREATE FUNCTION pg_temp.host() RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT private.project_url() $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.user(p_label text, p_flags text DEFAULT '') RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid := gen_random_uuid(); f text := ',' || coalesce(p_flags, '') || ',';
  BEGIN
    INSERT INTO auth.users (id, email, aud, role, raw_user_meta_data, created_at, updated_at)
    VALUES (v, 'test-' || v || '@junto.test', 'authenticated', 'authenticated', '{}'::jsonb, now(), now());
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE public.users SET
      accepted_tos_at  = CASE WHEN f LIKE '%,tos,%' THEN now() ELSE accepted_tos_at END,
      age_confirmed_at = CASE WHEN f LIKE '%,tos,%' THEN now() ELSE age_confirmed_at END,
      is_admin         = (f LIKE '%,admin,%'),
      suspended_at     = CASE WHEN f LIKE '%,suspended,%' THEN now() ELSE NULL END,
      is_demo          = (f LIKE '%,demo,%')
    WHERE id = v;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.as_(p_label text) RETURNS void
  LANGUAGE plpgsql AS $b$
  BEGIN
    EXECUTE 'RESET ROLE';
    -- 00511: new functions get no EXECUTE for PUBLIC by default — the harness
    -- grants its own temporary helpers before switching to a client role.
    EXECUTE format('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA %I TO PUBLIC', pg_my_temp_schema()::regnamespace::text);
    IF p_label = 'db' THEN
      PERFORM set_config('request.jwt.claims', '', true);
    ELSIF p_label = 'anon' THEN
      PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
      EXECUTE 'SET LOCAL ROLE anon';
    ELSE
      PERFORM set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.id(p_label), 'role', 'authenticated')::text, true);
      EXECUTE 'SET LOCAL ROLE authenticated';
    END IF;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.run(p_sql text) RETURNS text
  LANGUAGE plpgsql AS $b$
  DECLARE v text; n bigint;
  BEGIN
    -- Some RPCs leave junto.bypass_lock on until the end of the transaction (harmless over
    -- PostgREST, one call = one transaction). Inside a test block it would silently disable
    -- the protective triggers for every later statement: reset it before each check.
    PERFORM set_config('junto.bypass_lock', 'false', true);
    -- Statements that return rows give their first value; plain writes give their row count.
    IF p_sql ~* '^\s*(select|with|values|table)\M' OR p_sql ~* '\mreturning\M' THEN
      EXECUTE p_sql INTO v;
    ELSE
      EXECUTE p_sql;
      GET DIAGNOSTICS n = ROW_COUNT;
      v := n::text;
    END IF;
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.ok(p_name text, p_sql text, p_known text DEFAULT NULL) RETURNS text
  LANGUAGE plpgsql AS $b$
  DECLARE v text;
  BEGIN
    BEGIN
      v := pg_temp.run(p_sql);
    EXCEPTION WHEN OTHERS THEN
      PERFORM pg_temp.rec(p_name, false, 'error: ' || SQLERRM, p_known);
      RETURN NULL;
    END;
    PERFORM pg_temp.rec(p_name, true, v, p_known);
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.denied(p_name text, p_sql text,
    p_pattern text DEFAULT 'Operation not permitted|permission denied|row-level security|violates',
    p_known text DEFAULT NULL) RETURNS void
  LANGUAGE plpgsql AS $b$
  DECLARE v text;
  BEGIN
    BEGIN
      v := pg_temp.run(p_sql);
    EXCEPTION WHEN OTHERS THEN
      PERFORM pg_temp.rec(p_name, SQLERRM ~* p_pattern,
        CASE WHEN SQLERRM ~* p_pattern THEN 'refused: ' ELSE 'unexpected error: ' END || SQLERRM, p_known);
      RETURN;
    END;
    PERFORM pg_temp.rec(p_name, false, 'was allowed (returned ' || coalesce(v, 'null') || ')', p_known);
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.eq(p_name text, p_sql text, p_expected text, p_known text DEFAULT NULL) RETURNS void
  LANGUAGE plpgsql AS $b$
  DECLARE v text;
  BEGIN
    BEGIN
      v := pg_temp.run(p_sql);
    EXCEPTION WHEN OTHERS THEN
      PERFORM pg_temp.rec(p_name, false, 'error: ' || SQLERRM, p_known);
      RETURN;
    END;
    PERFORM pg_temp.rec(p_name, v IS NOT DISTINCT FROM p_expected,
      'expected ' || coalesce(p_expected, 'null') || ', got ' || coalesce(v, 'null'), p_known);
  END $b$$p$;
