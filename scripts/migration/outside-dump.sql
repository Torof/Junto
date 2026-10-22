-- Generates the SQL for what `pg_dump -n public -n private` does not carry
-- (MIGRATION_PLAN v7 §B.6). Read-only; run on the OLD project:
--   npx supabase db query --experimental --linked -f scripts/migration/outside-dump.sql
-- The single text column is the SQL file to apply on the new project.
-- Empty search_path: every printed name comes out schema-qualified (like pg_dump).
SET search_path = '';
SELECT concat_ws(E'\n\n',
  '-- Generated from the old project ' || now()::date || ' — do not edit by hand.',
  -- Triggers we own on auth.users and storage.objects
  (SELECT string_agg(pg_get_triggerdef(t.oid) || ';', E'\n' ORDER BY c.relname, t.tgname)
   FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
   JOIN pg_proc p ON p.oid = t.tgfoid JOIN pg_namespace pn ON pn.oid = p.pronamespace
   WHERE NOT t.tgisinternal AND n.nspname IN ('auth', 'storage') AND pn.nspname IN ('public', 'private')),
  -- Storage buckets
  (SELECT string_agg(format('INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES (%L, %L, %L, %s, %L);',
            b.id, b.name, b.public, coalesce(b.file_size_limit::text, 'NULL'), b.allowed_mime_types), E'\n' ORDER BY b.id)
   FROM storage.buckets b),
  -- Policies on storage.objects and realtime.messages
  (SELECT string_agg(format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s%s%s;',
            p.policyname, p.schemaname, p.tablename, p.permissive, p.cmd, array_to_string(p.roles, ', '),
            CASE WHEN p.qual IS NOT NULL THEN ' USING (' || p.qual || ')' ELSE '' END,
            CASE WHEN p.with_check IS NOT NULL THEN ' WITH CHECK (' || p.with_check || ')' ELSE '' END), E'\n' ORDER BY p.schemaname, p.tablename, p.policyname)
   FROM pg_policies p WHERE (p.schemaname, p.tablename) IN (('storage', 'objects'), ('realtime', 'messages'))),
  -- Realtime publication membership
  (SELECT string_agg(format('ALTER PUBLICATION supabase_realtime ADD TABLE %I.%I;', pt.schemaname, pt.tablename), E'\n' ORDER BY pt.tablename)
   FROM pg_publication_tables pt WHERE pt.pubname = 'supabase_realtime'),
  -- Role settings: none copied. The timeouts are Supabase's own defaults (a fresh
  -- project ships them; the catalog diff proves they match), the API hook is
  -- dropped (plan decision 4), session_preload_libraries is platform-owned.
  -- Scheduled jobs, created INACTIVE (activated in phase D)
  (SELECT string_agg(format('SELECT cron.schedule(%L, %L, %L);', j.jobname, j.schedule, j.command)
            || E'\n' || format('SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = %L), active := false);', j.jobname), E'\n' ORDER BY j.jobname)
   FROM cron.job j)
) AS sql;
