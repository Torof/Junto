-- Phase A.2 — read-only checks on the NEW project before building
-- (run from a folder linked to it: JUNTO_DB_WORKDIR, see REPETITION.md).
SELECT json_build_object(
  'version', version(),
  'locale', (SELECT datlocprovider::text || ' ' || coalesce(datlocale, datcollate) FROM pg_database WHERE datname = current_database()),
  'timezone', current_setting('TimeZone'),
  'postgis_available', (SELECT string_agg(version, ', ') FROM pg_available_extension_versions WHERE name = 'postgis'),
  'installed', (SELECT json_object_agg(e.extname, n.nspname) FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace),
  'schemas', (SELECT json_agg(nspname ORDER BY nspname) FROM pg_namespace WHERE nspname !~ '^pg_' AND nspname <> 'information_schema'),
  'public_tables', (SELECT count(*) FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r', 'v')),
  'postgres_on_auth_users', (SELECT json_build_object(
      'trigger', has_table_privilege('postgres', 'auth.users', 'TRIGGER'),
      'references', has_table_privilege('postgres', 'auth.users', 'REFERENCES'),
      'insert', has_table_privilege('postgres', 'auth.users', 'INSERT'),
      'delete', has_table_privilege('postgres', 'auth.users', 'DELETE'))),
  'postgres_on_storage_objects', (SELECT json_build_object(
      'trigger', has_table_privilege('postgres', 'storage.objects', 'TRIGGER'),
      'owner', (SELECT relowner::regrole::text FROM pg_class WHERE oid = 'storage.objects'::regclass))),
  'realtime_messages_owner', (SELECT relowner::regrole::text FROM pg_class WHERE oid = 'realtime.messages'::regclass),
  'publication', (SELECT json_build_object('owner', pubowner::regrole::text,
      'tables', (SELECT count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime')) FROM pg_publication WHERE pubname = 'supabase_realtime'),
  'existing_policies', (SELECT json_object_agg(schemaname || '.' || tablename, n) FROM (SELECT schemaname, tablename, count(*) n FROM pg_policies GROUP BY 1, 2) p),
  'buckets', (SELECT count(*) FROM storage.buckets),
  'default_acl_postgres', (SELECT json_agg(json_build_object('schema', coalesce(n.nspname, '(global)'), 'type', d.defaclobjtype::text, 'acl', d.defaclacl::text))
      FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace WHERE d.defaclrole = 'postgres'::regrole),
  'role_settings', (SELECT json_object_agg(r.rolname, s.setconfig) FROM pg_db_role_setting s JOIN pg_roles r ON r.oid = s.setrole)
) AS precheck;
