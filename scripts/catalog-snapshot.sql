-- Catalog snapshot of what Junto owns (migration proof, MIGRATION_PLAN v7 §C.2).
-- One row per object: (kind, name, fingerprint). Run on the old and the new
-- project, then `node scripts/catalog-diff.mjs old.json new.json`.
-- Values that differ by design between projects are left out: app_config
-- values (keys only), project host, secrets, row data, statistics, cron run
-- history, realtime partitions.
WITH ours AS (SELECT oid, nspname FROM pg_namespace WHERE nspname IN ('public', 'private')),
ext_member AS (SELECT objid FROM pg_depend WHERE deptype = 'e'),
rows AS (
  -- relations (tables, views, matviews, sequences), RLS flags, replica identity
  SELECT 'relation' AS kind, n.nspname || '.' || c.relname AS name,
         c.relkind::text || '|rls=' || c.relrowsecurity || '|force=' || c.relforcerowsecurity || '|ri=' || c.relreplident::text
         -- full text (not a hash): the diff normalises PostGIS schema prefixes first
         || CASE WHEN c.relkind IN ('v', 'm') THEN '|def=' || pg_get_viewdef(c.oid) ELSE '' END
         || '|opts=' || coalesce(array_to_string(c.reloptions, ','), '') AS fp
  FROM pg_class c JOIN ours n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S') AND c.oid NOT IN (SELECT objid FROM ext_member)
  UNION ALL
  -- columns
  SELECT 'column', n.nspname || '.' || c.relname || '.' || a.attname,
         format_type(a.atttypid, a.atttypmod) || '|nn=' || a.attnotnull || '|def=' || coalesce(pg_get_expr(d.adbin, d.adrelid), '')
         || '|gen=' || a.attgenerated::text || '|id=' || a.attidentity::text
  FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN ours n ON n.oid = c.relnamespace
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attnum > 0 AND NOT a.attisdropped AND c.relkind IN ('r', 'p', 'v', 'm') AND c.oid NOT IN (SELECT objid FROM ext_member)
  UNION ALL
  -- constraints
  SELECT 'constraint', n.nspname || '.' || c.relname || '.' || k.conname, k.contype::text || '|' || pg_get_constraintdef(k.oid) || '|valid=' || k.convalidated
  FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN ours n ON n.oid = c.relnamespace
  UNION ALL
  -- indexes
  SELECT 'index', n.nspname || '.' || i.relname, pg_get_indexdef(i.oid)
  FROM pg_index x JOIN pg_class i ON i.oid = x.indexrelid JOIN ours n ON n.oid = i.relnamespace
  WHERE i.oid NOT IN (SELECT objid FROM ext_member)
  UNION ALL
  -- RLS policies (ours + storage.objects + realtime.messages)
  SELECT 'policy', p.schemaname || '.' || p.tablename || '.' || p.policyname,
         p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|' || coalesce(p.qual, '') || '|' || coalesce(p.with_check, '')
  FROM pg_policies p WHERE p.schemaname IN ('public', 'private') OR (p.schemaname, p.tablename) IN (('storage', 'objects'), ('realtime', 'messages'))
  UNION ALL
  -- triggers (ours + the ones we put on auth.users and storage.objects)
  SELECT 'trigger', n2.nspname || '.' || c.relname || '.' || t.tgname, pg_get_triggerdef(t.oid) || '|en=' || t.tgenabled::text
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n2 ON n2.oid = c.relnamespace
  WHERE NOT t.tgisinternal AND (n2.nspname IN ('public', 'private')
    OR (n2.nspname = 'auth' AND c.relname = 'users' AND t.tgname LIKE '%junto%' OR n2.nspname = 'auth' AND t.tgfoid IN (SELECT p.oid FROM pg_proc p JOIN ours o ON o.oid = p.pronamespace))
    OR (n2.nspname = 'storage' AND t.tgfoid IN (SELECT p.oid FROM pg_proc p JOIN ours o ON o.oid = p.pronamespace)))
  UNION ALL
  -- functions: body hash, config, security, volatility, return type
  -- full definition: arguments and defaults, STRICT, LEAKPROOF, PARALLEL, COST,
  -- SECURITY, volatility, config and body (PostGIS prefixes normalised by the diff)
  SELECT 'function', p.oid::regprocedure::text, pg_get_functiondef(p.oid)
  FROM pg_proc p JOIN ours n ON n.oid = p.pronamespace
  WHERE p.oid NOT IN (SELECT objid FROM ext_member) AND p.prokind IN ('f', 'p')
  UNION ALL
  -- table and column privileges for client roles
  -- grants read from the ACLs themselves (MAINTAIN included, every grantee but the owner)
  SELECT 'grant.table', n.nspname || '.' || c.relname || '.' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END,
         string_agg(a.privilege_type || CASE WHEN a.is_grantable THEN '*' ELSE '' END, ',' ORDER BY a.privilege_type)
  FROM pg_class c JOIN ours n ON n.oid = c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a
  WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S') AND c.oid NOT IN (SELECT objid FROM ext_member) AND a.grantee <> c.relowner
  GROUP BY 1, 2
  UNION ALL
  SELECT 'grant.column', n.nspname || '.' || c.relname || '.' || att.attname || '.' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END,
         string_agg(a.privilege_type, ',' ORDER BY a.privilege_type)
  FROM pg_attribute att JOIN pg_class c ON c.oid = att.attrelid JOIN ours n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL aclexplode(att.attacl) a
  WHERE att.attnum > 0 AND NOT att.attisdropped AND att.attacl IS NOT NULL AND c.oid NOT IN (SELECT objid FROM ext_member)
  GROUP BY 1, 2
  UNION ALL
  -- owners (all postgres today)
  SELECT 'owner', 'relation.' || n.nspname || '.' || c.relname, c.relowner::regrole::text
  FROM pg_class c JOIN ours n ON n.oid = c.relnamespace WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S') AND c.oid NOT IN (SELECT objid FROM ext_member)
  UNION ALL
  SELECT 'owner', 'function.' || p.oid::regprocedure::text, p.proowner::regrole::text
  FROM pg_proc p JOIN ours n ON n.oid = p.pronamespace WHERE p.oid NOT IN (SELECT objid FROM ext_member)
  UNION ALL
  -- database-level settings
  SELECT 'db_setting', 'database', array_to_string(ARRAY(SELECT x FROM unnest(s.setconfig) x ORDER BY 1), ';')
  FROM pg_db_role_setting s WHERE s.setrole = 0 AND s.setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
  UNION ALL
  -- publication options
  SELECT 'publication_opts', p.pubname, 'ins=' || p.pubinsert || '|upd=' || p.pubupdate || '|del=' || p.pubdelete || '|trunc=' || p.pubtruncate || '|root=' || p.pubviaroot
  FROM pg_publication p WHERE p.pubname = 'supabase_realtime'
  UNION ALL
  -- identity (never compared: proves which project each snapshot came from)
  SELECT 'identity', 'project_url', coalesce(private.project_url(), '?')
  UNION ALL
  SELECT 'grant.function', p.oid::regprocedure::text || '.' || r.rolname,
         has_function_privilege(r.oid, p.oid, 'EXECUTE')::text
  FROM pg_proc p JOIN ours n ON n.oid = p.pronamespace CROSS JOIN pg_roles r
  WHERE r.rolname IN ('anon', 'authenticated', 'service_role') AND p.oid NOT IN (SELECT objid FROM ext_member)
  UNION ALL
  SELECT 'grant.schema', n.nspname || '.' || r.rolname, has_schema_privilege(r.oid, n.oid, 'USAGE')::text || '|create=' || has_schema_privilege(r.oid, n.oid, 'CREATE')::text
  FROM ours n CROSS JOIN pg_roles r WHERE r.rolname IN ('anon', 'authenticated', 'service_role')
  UNION ALL
  -- default privileges of the postgres role (ours; supabase_admin's are platform-owned)
  SELECT 'default_acl', coalesce(n.nspname, '(global)') || '.' || d.defaclobjtype::text, array_to_string(ARRAY(SELECT x::text FROM unnest(d.defaclacl) x ORDER BY 1), ',')
  FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
  WHERE d.defaclrole = 'postgres'::regrole
  UNION ALL
  -- realtime publication membership
  SELECT 'publication', pt.pubname || '.' || pt.schemaname || '.' || pt.tablename, 'member'
  FROM pg_publication_tables pt WHERE pt.pubname = 'supabase_realtime'
  UNION ALL
  -- extensions and where they live
  SELECT 'extension', e.extname, n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
  UNION ALL
  -- scheduled jobs (definition only)
  SELECT 'cron', j.jobname, j.schedule || '|' || md5(j.command) || '|active=' || j.active FROM cron.job j
  UNION ALL
  -- storage buckets
  SELECT 'bucket', b.id, b.public || '|' || coalesce(b.file_size_limit::text, '') || '|' || coalesce(array_to_string(b.allowed_mime_types, ','), '') FROM storage.buckets b
  UNION ALL
  -- role settings (API pre-request hook, etc.)
  SELECT 'role_setting', r.rolname, array_to_string(s.setconfig, ';')
  FROM pg_db_role_setting s JOIN pg_roles r ON r.oid = s.setrole WHERE r.rolname IN ('authenticator', 'anon', 'authenticated', 'service_role')
  UNION ALL
  -- app_config keys (values differ per project by design)
  SELECT 'app_config', c.name, 'present' FROM public.app_config c
)
SELECT json_agg(json_build_object('k', kind, 'n', name, 'f', fp) ORDER BY kind, name) AS snapshot FROM rows;
