-- Domaine 0 — socle structurel. Boucles sur le catalogue : tout nouvel objet
-- (table, vue, fonction) est couvert automatiquement.

-- Helper : passe si l'écriture/lecture est refusée OU n'affecte/ne renvoie aucune ligne.
EXECUTE $p$CREATE FUNCTION pg_temp.tx_none(p_name text, p_sql text, p_known text DEFAULT NULL) RETURNS void
  LANGUAGE plpgsql AS $b$
  DECLARE v text;
  BEGIN
    BEGIN
      v := pg_temp.run(p_sql);
    EXCEPTION WHEN OTHERS THEN
      PERFORM pg_temp.rec(p_name, SQLERRM ~* 'permission denied|row-level security|Operation not permitted',
        CASE WHEN SQLERRM ~* 'permission denied|row-level security|Operation not permitted' THEN 'refused: ' ELSE 'unexpected error: ' END || SQLERRM, p_known);
      RETURN;
    END;
    PERFORM pg_temp.rec(p_name, coalesce(v, '0') = '0', 'got ' || coalesce(v, 'null') || ' row(s)', p_known);
  END $b$$p$;

DECLARE
  r record;
  v_owner text;
  v_ctid text;
  v_col text;
  v_cmd text;
BEGIN
  PERFORM pg_temp.user('alice', 'tos');
  PERFORM pg_temp.user('bob', 'tos');
  PERFORM pg_temp.as_('db');

  -- ───── 1. RLS activée ET forcée sur chaque table de public ─────
  FOR r IN SELECT c.relname, c.relrowsecurity AS ena, c.relforcerowsecurity AS frc
           FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p') ORDER BY 1 LOOP
    PERFORM pg_temp.rec('RLS activée et forcée : ' || r.relname, r.ena AND r.frc,
      'enabled=' || r.ena || ' forced=' || r.frc,
      CASE WHEN r.relname = 'spatial_ref_sys' THEN 'TX-2' END);
  END LOOP;

  -- ───── 2. Vues de public en lecture seule pour les rôles clients (ID-1, 00476) ─────
  FOR r IN SELECT c.oid, c.relname FROM pg_class c
           WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('v', 'm') ORDER BY 1 LOOP
    PERFORM pg_temp.eq('vue en lecture seule pour anon/authenticated : ' || r.relname,
      format($$SELECT coalesce(string_agg(g.role || ':' || p.priv, ','), '') FROM
               unnest('{anon,authenticated}'::text[]) g(role) CROSS JOIN unnest('{INSERT,UPDATE,DELETE,TRUNCATE}'::text[]) p(priv)
               WHERE has_table_privilege(g.role, %s::oid, p.priv)$$, r.oid), '',
      CASE WHEN r.relname IN ('geometry_columns', 'geography_columns') THEN 'TX-2' END);
  END LOOP;

  -- ───── 3. SECURITY DEFINER => search_path fixé ─────
  PERFORM pg_temp.eq('toute fonction SECURITY DEFINER (public, private) fixe search_path',
    $$SELECT coalesce(string_agg(DISTINCT p.oid::regprocedure::text, ', '), '') FROM pg_proc p
      WHERE p.pronamespace IN ('public'::regnamespace, 'private'::regnamespace) AND p.prosecdef
        AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
        AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) x WHERE x LIKE 'search_path=%')$$, '');
  -- PostGIS (membre d'extension, hors de notre contrôle) : ST_EstimatedExtent est SECURITY DEFINER sans
  -- search_path et appelable sans compte — lit les statistiques internes (même famille que PV-1).
  PERFORM pg_temp.eq('aucune fonction d''extension SECURITY DEFINER appelable par anon dans public',
    $$SELECT coalesce(string_agg(DISTINCT p.proname, ', '), '') FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace AND p.prosecdef AND has_function_privilege('anon', p.oid, 'EXECUTE')
        AND EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')$$,
    '', 'PV-1');

  -- ───── 4. Fonctions de public exécutables par anon : liste blanche ─────
  -- Autorisé : fonctions trigger (non appelables directement), demo_content_visible (rideau démo des vues
  -- carte du site), membres d'extension (PostGIS — PV-2, fermé par la reconstruction).
  PERFORM pg_temp.eq('aucune fonction de public exécutable par anon hors liste blanche',
    $$SELECT coalesce(string_agg(DISTINCT p.oid::regprocedure::text, ', '), '') FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace AND has_function_privilege('anon', p.oid, 'EXECUTE')
        AND p.prorettype <> 'trigger'::regtype
        AND p.proname NOT IN ('demo_content_visible', 'junto_pre_request')  -- filtre d'API (00504), appelé par PostgREST avec le rôle du client
        AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')$$, '');
  PERFORM pg_temp.eq('anon ne peut pas exécuter _postgis_stats (où que soit PostGIS)',
    $$SELECT bool_or(has_function_privilege('anon', p.oid, 'EXECUTE')
                     AND has_schema_privilege('anon', p.pronamespace, 'USAGE'))::text FROM pg_proc p
      WHERE p.proname = '_postgis_stats'$$, 'false', 'PV-1');

  -- ───── 5. Fonctions internes non exécutables par les rôles clients ─────
  -- close_channel est une RPC client (modération par le créateur du canal), pas un job interne.
  -- Les fonctions trigger sont exclues : PostgreSQL refuse leur appel direct.
  PERFORM pg_temp.eq('fonctions internes non exécutables par authenticated/anon',
    $$SELECT coalesce(string_agg(DISTINCT p.oid::regprocedure::text, ', '), '') FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname ~ '^(create_notification|notify_|purge_|recalculate_|close_|expire_|award_|log_admin_action$|trace_)|_whitelist_columns$'
        AND p.proname <> 'close_channel'
        AND p.prorettype <> 'trigger'::regtype
        AND (has_function_privilege('authenticated', p.oid, 'EXECUTE') OR has_function_privilege('anon', p.oid, 'EXECUTE'))$$, '');
  PERFORM pg_temp.as_('alice');
  PERFORM pg_temp.denied('une fonction trigger *_whitelist_columns ne s''appelle pas directement',
    $$SELECT public.messages_whitelist_columns()::text$$, 'trigger|permission denied');
  PERFORM pg_temp.denied('authenticated ne peut pas appeler create_notification',
    $$SELECT count(*)::text FROM (SELECT public.create_notification(NULL, NULL, NULL, NULL)) x$$,
    'permission denied|function .* does not exist|is not unique');
  PERFORM pg_temp.as_('db');

  -- ───── 6. Tables sans écriture directe client (CLAUDE.md) ─────
  -- DB-TX-1 : activity_alerts garde la policy « alerts_delete_own » (00047) — un client supprime ses alertes
  -- en direct, alors que CLAUDE.md / SECURITY.md la classent « aucune écriture directe » (delete_alert).
  -- table | commandes interdites | expression du propriétaire d'une ligne existante (on se fait passer pour lui)
  FOR r IN SELECT * FROM (VALUES
      ('users',                 '{INSERT}',               'id'),
      ('notifications',         '{INSERT,DELETE}',        'user_id'),
      ('messages',              '{INSERT,UPDATE,DELETE}', 'sender_id'),
      ('conversation_members',  '{INSERT,UPDATE,DELETE}', 'user_id'),
      ('conversations',         '{INSERT,UPDATE,DELETE}', 'coalesce(user_1, created_by)'),
      ('participations',        '{INSERT,UPDATE,DELETE}', 'user_id'),
      ('reputation_votes',      '{INSERT,UPDATE,DELETE}', 'voter_id'),
      ('presence_tokens',       '{INSERT,UPDATE,DELETE}', '(SELECT a.creator_id FROM public.activities a WHERE a.id = activity_id)'),
      ('push_tokens',           '{INSERT,UPDATE,DELETE}', 'user_id'),
      ('seat_requests',         '{INSERT,UPDATE}',        'requester_id'),
      ('activity_alerts',       '{INSERT,UPDATE,DELETE}', 'user_id'),
      ('activity_gear',         '{INSERT,UPDATE,DELETE}', 'user_id'),
      ('activity_gear_missing', '{INSERT,UPDATE,DELETE}', 'created_by'),
      ('reports',               '{INSERT,DELETE}',        'reporter_id'),
      ('user_badge_progression','{INSERT,UPDATE,DELETE}', 'user_id'),
      ('pro_reviews',           '{INSERT,UPDATE,DELETE}', 'reviewer_id'),
      ('offering_reviews',      '{INSERT,UPDATE,DELETE}', 'reviewer_id'),
      ('pro_profiles',          '{INSERT,UPDATE,DELETE}', 'user_id'),
      ('pro_offerings',         '{INSERT,UPDATE,DELETE}', 'pro_id'),
      ('pro_profile_photos',    '{INSERT,UPDATE,DELETE}', 'pro_id'),
      ('pro_offering_photos',   '{INSERT,UPDATE,DELETE}', '(SELECT o.pro_id FROM public.pro_offerings o WHERE o.id = offering_id)'),
      ('pro_community_photos',  '{INSERT,UPDATE,DELETE}', 'contributor_id'),
      ('pro_availabilities',    '{INSERT,UPDATE,DELETE}', 'pro_id'),
      ('bookings',              '{INSERT,UPDATE,DELETE}', 'client_id')
    ) t(tbl, cmds, owner_expr) LOOP
    PERFORM pg_temp.as_('db');
    -- Catalogue : aucune policy permissive applicable aux clients pour ces commandes (si le privilège existe).
    FOREACH v_cmd IN ARRAY r.cmds::text[] LOOP
      PERFORM pg_temp.eq(format('%s : aucune policy %s pour les clients', r.tbl, v_cmd),
        format($$SELECT coalesce(string_agg(policyname, ','), '') FROM pg_policies
                 WHERE schemaname = 'public' AND tablename = %L AND cmd IN (%L, 'ALL') AND permissive = 'PERMISSIVE'
                   AND roles && '{public,authenticated,anon}'::name[]
                   AND (has_table_privilege('authenticated', %L, %L) OR has_table_privilege('anon', %L, %L))$$,
               r.tbl, v_cmd, 'public.' || r.tbl, v_cmd, 'public.' || r.tbl, v_cmd), '',
        CASE WHEN r.tbl = 'activity_alerts' AND v_cmd = 'DELETE' THEN 'DB-TX-1' END);
    END LOOP;
    -- Essais réels, en se faisant passer pour le propriétaire d'une ligne existante (sinon alice).
    v_owner := NULL; v_ctid := NULL;
    EXECUTE format('SELECT (%s)::text, ctid::text FROM public.%I WHERE (%s) IS NOT NULL LIMIT 1', r.owner_expr, r.tbl, r.owner_expr)
      INTO v_owner, v_ctid;
    SELECT a.attname INTO v_col FROM pg_attribute a
      WHERE a.attrelid = ('public.' || r.tbl)::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = ''
      ORDER BY a.attnum LIMIT 1;
    PERFORM pg_temp.put('owner', coalesce(v_owner, pg_temp.get('alice')));
    PERFORM pg_temp.as_('owner');
    IF 'INSERT' = ANY (r.cmds::text[]) THEN
      PERFORM pg_temp.tx_none(r.tbl || ' : INSERT direct refusé', format('INSERT INTO public.%I DEFAULT VALUES', r.tbl));
    END IF;
    IF 'UPDATE' = ANY (r.cmds::text[]) THEN
      PERFORM pg_temp.tx_none(r.tbl || ' : UPDATE direct refusé (propriétaire)' || CASE WHEN v_ctid IS NULL THEN ' [table vide]' ELSE '' END,
        format('UPDATE public.%I SET %I = %I WHERE %s', r.tbl, v_col, v_col,
               CASE WHEN v_ctid IS NULL THEN 'true' ELSE format('ctid = %L::tid', v_ctid) END));
    END IF;
    IF 'DELETE' = ANY (r.cmds::text[]) THEN
      PERFORM pg_temp.tx_none(r.tbl || ' : DELETE direct refusé (propriétaire)' || CASE WHEN v_ctid IS NULL THEN ' [table vide]' ELSE '' END,
        format('DELETE FROM public.%I WHERE %s', r.tbl,
               CASE WHEN v_ctid IS NULL THEN 'true' ELSE format('ctid = %L::tid', v_ctid) END),
        CASE WHEN r.tbl = 'activity_alerts' AND v_ctid IS NOT NULL THEN 'DB-TX-1' END);
    END IF;
  END LOOP;
  PERFORM pg_temp.as_('db');

  -- ───── 7. Lectures anonymes ─────
  PERFORM pg_temp.as_('anon');
  FOREACH v_cmd IN ARRAY '{users,conversations,messages,participations,bookings,notifications,push_tokens,app_config,presence_tokens,discovery_availabilities,gpx_traces}'::text[] LOOP
    PERFORM pg_temp.tx_none('anon ne lit pas ' || v_cmd, format('SELECT count(*)::text FROM public.%I', v_cmd));
  END LOOP;
  PERFORM pg_temp.ok('anon lit activities_with_coords (site)', $$SELECT count(*)::text FROM public.activities_with_coords$$);
  PERFORM pg_temp.ok('anon lit pro_offerings_with_coords (site)', $$SELECT count(*)::text FROM public.pro_offerings_with_coords$$);

  -- ───── 8. Stockage : pas d'écriture dans le dossier d'un autre ─────
  PERFORM pg_temp.as_('alice');
  FOREACH v_cmd IN ARRAY '{avatars,pro-photos,channel-photos}'::text[] LOOP
    PERFORM pg_temp.denied(format('stockage %s : alice n''écrit pas dans le dossier de bob', v_cmd),
      format($$INSERT INTO storage.objects (bucket_id, name, owner) VALUES (%L, %L, %L)$$,
             v_cmd, pg_temp.get('bob') || '/socle-test.jpg', pg_temp.get('alice')));
    PERFORM pg_temp.ok(format('stockage %s : alice écrit dans son propre dossier (contrôle)', v_cmd),
      format($$INSERT INTO storage.objects (bucket_id, name, owner) VALUES (%L, %L, %L)$$,
             v_cmd, pg_temp.get('alice') || '/socle-test.jpg', pg_temp.get('alice')));
  END LOOP;
  PERFORM pg_temp.as_('anon');
  PERFORM pg_temp.eq('anon ne peut pas lister les fichiers des buckets',
    $$SELECT (count(*) > 0)::text FROM storage.objects WHERE bucket_id IN ('avatars', 'pro-photos', 'channel-photos')$$, 'false');
  PERFORM pg_temp.as_('alice');
  PERFORM pg_temp.eq('un compte ne liste pas les fichiers des autres (TX-3)',
    format($$SELECT count(*)::text FROM storage.objects WHERE bucket_id IN ('avatars', 'pro-photos', 'channel-photos') AND (storage.foldername(name))[1] <> %L$$, pg_temp.get('alice')), '0');
  PERFORM pg_temp.as_('anon');
  PERFORM pg_temp.denied('anon n''écrit pas dans le stockage',
    $$INSERT INTO storage.objects (bucket_id, name) VALUES ('avatars', 'anon/socle-test.jpg')$$);

  -- ───── 9. Realtime : les clients ne diffusent pas ─────
  PERFORM pg_temp.as_('db');
  PERFORM pg_temp.eq('realtime.messages : aucune policy INSERT pour les clients',
    $$SELECT coalesce(string_agg(policyname, ','), '') FROM pg_policies WHERE schemaname = 'realtime' AND tablename = 'messages'
      AND cmd IN ('INSERT', 'ALL') AND roles && '{public,authenticated,anon}'::name[]$$, '');
  PERFORM pg_temp.eq('realtime.messages : RLS activée',
    $$SELECT relrowsecurity::text FROM pg_class WHERE oid = 'realtime.messages'::regclass$$, 'true');
  PERFORM pg_temp.as_('alice');
  PERFORM pg_temp.denied('alice ne peut pas diffuser sur realtime',
    $$INSERT INTO realtime.messages (topic, extension, payload, event, private) VALUES ('user:' || auth.uid(), 'broadcast', '{}'::jsonb, 'x', true)$$);

  -- ───── 10. app_config et cron ─────
  PERFORM pg_temp.tx_none('authenticated ne lit pas app_config', $$SELECT count(*)::text FROM public.app_config$$);
  PERFORM pg_temp.denied('authenticated n''accède pas à cron.job', $$SELECT count(*)::text FROM cron.job$$);
  PERFORM pg_temp.as_('anon');
  PERFORM pg_temp.denied('anon n''accède pas à cron.job', $$SELECT count(*)::text FROM cron.job$$);
  PERFORM pg_temp.as_('db');
  PERFORM pg_temp.eq('schéma cron inutilisable par les clients',
    $$SELECT (has_schema_privilege('anon', 'cron', 'USAGE') OR has_schema_privilege('authenticated', 'cron', 'USAGE'))::text$$, 'false');

  -- ───── Trous connus ─────
  PERFORM pg_temp.as_('anon');
  PERFORM pg_temp.denied('anon n''écrit pas dans spatial_ref_sys',
    format('DELETE FROM %s WHERE srid = -1', (SELECT c.oid::regclass::text FROM pg_class c WHERE c.relname = 'spatial_ref_sys' AND c.relkind = 'r')), 'permission denied', 'TX-2');  -- où que soit PostGIS
  PERFORM pg_temp.as_('db');
  -- TX-4 (00502) : nos tables (rôle postgres) n'accordent plus d'écriture par défaut aux clients.
  PERFORM pg_temp.eq('privilèges par défaut (postgres) : pas d''écriture accordée aux clients sur les nouvelles tables',
    $$SELECT count(*)::text FROM pg_default_acl d CROSS JOIN LATERAL aclexplode(d.defaclacl) a
      WHERE d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'r' AND d.defaclrole = 'postgres'::regrole
        AND a.grantee IN ('anon'::regrole, 'authenticated'::regrole)
        AND a.privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')$$, '0');
  -- Reste : les droits par défaut du rôle interne supabase_admin (non modifiables ici) — fermés par la migration.
  PERFORM pg_temp.eq('privilèges par défaut (supabase_admin) : pas d''écriture accordée aux clients',
    $$SELECT count(*)::text FROM pg_default_acl d CROSS JOIN LATERAL aclexplode(d.defaclacl) a
      WHERE d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'r' AND d.defaclrole = 'supabase_admin'::regrole
        AND a.grantee IN ('anon'::regrole, 'authenticated'::regrole)
        AND a.privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')$$, '0', 'TX-4');
  -- PV-3 (00502) : aucun TRUNCATE client sur nos tables (spatial_ref_sys, à supabase_admin, relève de TX-2).
  PERFORM pg_temp.eq('aucun TRUNCATE accordé aux clients sur les tables de public',
    $$SELECT count(*)::text FROM pg_class c CROSS JOIN unnest('{anon,authenticated}'::text[]) g(role)
      WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p') AND c.relname <> 'spatial_ref_sys'
        AND has_table_privilege(g.role, c.oid, 'TRUNCATE')$$, '0');
  PERFORM pg_temp.eq('les clients n''ont aucun droit sur net.http_request_queue',
    $$SELECT (has_table_privilege('anon', 'net.http_request_queue', 'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege('authenticated', 'net.http_request_queue', 'SELECT,INSERT,UPDATE,DELETE'))::text$$, 'false', 'PV-4');
  -- TX-2 (00504) : filtre d'API — aucune écriture sur les tables PostGIS par PostgREST.
  PERFORM pg_temp.as_('db');
  PERFORM pg_temp.eq('filtre d''API branché sur PostgREST',
    $$SELECT (EXISTS (SELECT 1 FROM pg_db_role_setting s JOIN pg_roles r ON r.oid = s.setrole
      WHERE r.rolname = 'authenticator' AND array_to_string(s.setconfig, ',') LIKE '%pgrst.db_pre_request=public.junto_pre_request%'))::text$$, 'true');
  PERFORM pg_temp.as_('anon');
  PERFORM pg_temp.denied('filtre d''API : DELETE sur spatial_ref_sys refusé',
    $$SELECT set_config('request.method', 'DELETE', true), set_config('request.path', '/spatial_ref_sys', true), public.junto_pre_request()$$, 'Operation not permitted');
  PERFORM pg_temp.denied('filtre d''API : PATCH sur geometry_columns refusé',
    $$SELECT set_config('request.method', 'PATCH', true), set_config('request.path', '/geometry_columns', true), public.junto_pre_request()$$, 'Operation not permitted');
  PERFORM pg_temp.denied('filtre d''API : DELETE sur « /spatial%5Fref%5Fsys » refusé (00512)',
    $$SELECT set_config('request.method', 'DELETE', true), set_config('request.path', '/spatial%5Fref%5Fsys', true), public.junto_pre_request()$$, 'Operation not permitted');
  PERFORM pg_temp.denied('filtre d''API : DELETE sur « /%73patial_ref_sys » refusé (00512)',
    $$SELECT set_config('request.method', 'DELETE', true), set_config('request.path', '/%73patial_ref_sys', true), public.junto_pre_request()$$, 'Operation not permitted');
  PERFORM pg_temp.denied('filtre d''API : DELETE sur « //spatial_ref_sys » refusé (00512)',
    $$SELECT set_config('request.method', 'DELETE', true), set_config('request.path', '//spatial_ref_sys', true), public.junto_pre_request()$$, 'Operation not permitted');
  PERFORM pg_temp.denied('filtre d''API : DELETE sur « /rpc/../spatial_ref_sys » refusé (00512)',
    $$SELECT set_config('request.method', 'DELETE', true), set_config('request.path', '/rpc/../spatial_ref_sys', true), public.junto_pre_request()$$, 'Operation not permitted');
  PERFORM pg_temp.ok('filtre d''API : lecture de spatial_ref_sys permise',
    $$SELECT set_config('request.method', 'GET', true), set_config('request.path', '/spatial_ref_sys', true), public.junto_pre_request()::text$$);
  PERFORM pg_temp.ok('filtre d''API : appel de fonction de l''app permis',
    $$SELECT set_config('request.method', 'POST', true), set_config('request.path', '/rpc/join_activity', true), public.junto_pre_request()::text$$);
  PERFORM set_config('request.method', '', true); PERFORM set_config('request.path', '', true);
  -- 00510 : une fonction créée plus tard n'est appelable par aucun client sans GRANT explicite.
  PERFORM pg_temp.as_('db');
  EXECUTE 'CREATE FUNCTION public.zz_resecure_probe() RETURNS int LANGUAGE sql AS $f$ SELECT 1 $f$';
  PERFORM pg_temp.eq('nouvelle fonction : pas d''EXECUTE par défaut pour authenticated',
    $$SELECT has_function_privilege('authenticated', 'public.zz_resecure_probe()', 'EXECUTE')::text$$, 'false');
  PERFORM pg_temp.eq('nouvelle fonction : pas d''EXECUTE par défaut pour anon',
    $$SELECT has_function_privilege('anon', 'public.zz_resecure_probe()', 'EXECUTE')::text$$, 'false');
  -- 00510 : users en liste blanche — une colonne ajoutée plus tard est figée pour le client.
  EXECUTE 'ALTER TABLE public.users ADD COLUMN zz_probe text';
  EXECUTE 'GRANT UPDATE (zz_probe) ON public.users TO authenticated';
  PERFORM pg_temp.as_('alice');
  PERFORM pg_temp.ok('alice tente d''écrire une colonne ajoutée plus tard', format($$UPDATE public.users SET zz_probe = 'x', bio = 'Bio ok' WHERE id = %L$$, pg_temp.get('alice')));
  PERFORM pg_temp.as_('db');
  PERFORM pg_temp.eq('la colonne ajoutée plus tard reste intacte, le champ de profil change',
    format($$SELECT coalesce(zz_probe, 'null') || '|' || bio FROM public.users WHERE id = %L$$, pg_temp.get('alice')), 'null|Bio ok');
  -- 00521-00522 (décision 5) : plafond d'envois de fichiers par compte et par jour (avatars : 20).
  PERFORM pg_temp.as_('db');
  PERFORM pg_temp.user('quota_u', 'tos');
  PERFORM pg_temp.as_('quota_u');
  PERFORM pg_temp.ok('quota : 20 envois d''avatar dans la journée acceptés', format($q$DO $d$ BEGIN FOR i IN 1..20 LOOP INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('avatars', %L || '/q' || i || '.jpg', %L); END LOOP; END $d$$q$, pg_temp.get('quota_u'), pg_temp.get('quota_u')));
  PERFORM pg_temp.denied('quota : le 21e envoi du jour est refusé', format($q$INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('avatars', %L || '/q21.jpg', %L)$q$, pg_temp.get('quota_u'), pg_temp.get('quota_u')), 'junto\.storage_quota');
END;
