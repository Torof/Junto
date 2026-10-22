#!/usr/bin/env python3
"""Phase B preparation — turn the export into ordered build files (MIGRATION_PLAN §B).

Run by Claude (no password needed): it reads $WORK/export (made by export.sh),
reads the OLD project's catalog through the linked Supabase CLI (read-only),
and writes $WORK/build/NN_*.sql, applied in order by build.sh.

    python3 scripts/migration/prepare.py <new-project-ref>

Every transformation is checked; any surprise stops the script with a message
instead of producing a doubtful file.
"""
import json
import os
import re
import secrets
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
WORK = os.environ.get('JUNTO_MIG_WORK', os.path.expanduser('~/junto-migration'))
EXPORT = os.path.join(WORK, 'export')
BUILD = os.path.join(WORK, 'build')
OLD_REF = 'lvjlthzdydzatcvwwriu'
# Folder linked to the OLD project (the repo itself is linked to the new one since F.6).
OLD_LINK = os.path.expanduser('~/junto-migration/link-old')
# First migration number of the new project (after the last one applied on the old).
BASELINE = '%05d' % (max(int(f[:5]) for f in os.listdir(os.path.join(ROOT, 'supabase', 'migrations')) if f[:5].isdigit()) + 1)


def die(msg):
    sys.exit(f'ARRÊT : {msg}')


def old_query(sql):
    """Read-only query on the OLD project (through OLD_LINK)."""
    path = os.path.join(WORK, '.q.sql')
    with open(path, 'w') as f:
        f.write(sql)
    out = subprocess.run(['npx', 'supabase', 'db', 'query', '--experimental', '--linked', '-f', path],
                         cwd=OLD_LINK, capture_output=True, text=True).stdout
    os.remove(path)
    data = json.loads(out[out.index('{'):])
    return data['rows']


def strip_meta(text):
    """psql meta lines added by pg_dump 17.6+/18 (\\restrict) are not SQL."""
    return '\n'.join(l for l in text.split('\n') if not re.match(r'^\\(un)?restrict\b', l))


def main():
    os.umask(0o077)  # build files carry the pepper and a provisional secret
    if len(sys.argv) != 2 or not re.fullmatch(r'[a-z0-9]{20}', sys.argv[1]):
        die('donner la référence du nouveau projet (20 caractères)')
    new_ref = sys.argv[1]
    if new_ref == OLD_REF:
        die("c'est la référence de l'ancien projet")
    linked = open(os.path.join(OLD_LINK, 'supabase', '.temp', 'project-ref')).read().strip()
    if linked != OLD_REF:
        die(f'{OLD_LINK} doit viser l\'ancien projet (vise {linked})')
    for f in ('schema.sql', 'reference.sql'):
        if not os.path.exists(os.path.join(EXPORT, f)):
            die(f'{f} absent de {EXPORT} — lancer export.sh')
    os.makedirs(BUILD, exist_ok=True)
    for f in os.listdir(BUILD):
        os.remove(os.path.join(BUILD, f))
    report = []

    # ── Old catalog facts (read-only) ────────────────────────────────────────
    meta = old_query("""
      select json_build_object(
        'types', (select json_agg(distinct t.typname) from pg_type t join pg_depend d on d.objid = t.oid
                  and d.classid = 'pg_type'::regclass and d.deptype = 'e' join pg_extension e on e.oid = d.refobjid
                  where e.extname = 'postgis' and t.typname !~ '^_'),
        'functions', (select json_agg(distinct p.proname) from pg_proc p join pg_depend d on d.objid = p.oid
                  and d.classid = 'pg_proc'::regclass and d.deptype = 'e' join pg_extension e on e.oid = d.refobjid
                  where e.extname = 'postgis'),
        'relations', (select json_agg(distinct c.relname) from pg_class c join pg_depend d on d.objid = c.oid
                  and d.classid = 'pg_class'::regclass and d.deptype = 'e' join pg_extension e on e.oid = d.refobjid
                  where e.extname = 'postgis'),
        'ours', (select json_agg(distinct p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname in ('public', 'private')
                  and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')),
        'n_geo_cols', (select count(*) from pg_attribute a join pg_class c on c.oid = a.attrelid
                  where c.relnamespace in ('public'::regnamespace, 'private'::regnamespace) and c.relkind in ('r', 'p')
                  and a.atttypid = 'geography'::regtype and not a.attisdropped),
        'map_views', (select json_agg(distinct c.relname) from pg_class c join pg_depend d on d.objid = c.oid or d.objid in
                  (select r.oid from pg_rewrite r where r.ev_class = c.oid)
                  where c.relnamespace = 'public'::regnamespace and c.relkind = 'v'
                  and not exists (select 1 from pg_depend z where z.objid = c.oid and z.deptype = 'e')
                  and d.refobjid in (select p.oid from pg_proc p join pg_depend e on e.objid = p.oid and e.deptype = 'e'
                                     join pg_extension x on x.oid = e.refobjid where x.extname = 'postgis')),
        'our_operators', (select count(*) from pg_operator o join pg_namespace n on n.oid = o.oprnamespace
                  where n.nspname = 'public' and not exists (select 1 from pg_depend d where d.objid = o.oid and d.deptype = 'e')),
        'n_functions', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname in ('public', 'private')
                  and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'))
      ) as m""")[0]['m']
    meta = json.loads(meta) if isinstance(meta, str) else meta
    postgis = set(meta['types']) | set(meta['functions']) | set(meta['relations'])
    clash = postgis & set(meta['ours'])
    if clash:
        die(f'nos fonctions portent des noms PostGIS : {sorted(clash)}')
    if meta['our_operators']:
        die('des opérateurs à nous existent dans public — requalification à revoir')
    outside = old_query(open(os.path.join(ROOT, 'scripts', 'migration', 'outside-dump.sql')).read())[0]['sql']
    # The ban fingerprints are HMACs keyed by this pepper: it must move with them.
    pepper = old_query("select value from app_config where name = 'email_ban_pepper'")[0]['value']
    if not re.fullmatch(r'[0-9a-f]{64}', pepper or ''):
        die('email_ban_pepper absent ou de forme inattendue sur l\'ancien projet')

    # ── 05 Target guard: a fresh, empty project — never anything else ────────
    write('05_target_guard', f"""
DO $$ BEGIN
  IF to_regnamespace('private') IS NOT NULL THEN RAISE EXCEPTION 'schema private already exists: not a fresh project'; END IF;
  IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r', 'v', 'm'))
  THEN RAISE EXCEPTION 'schema public is not empty: not a fresh project'; END IF;
  IF NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user)
  THEN RAISE EXCEPTION 'the build role cannot bypass RLS (reference data load would fail)'; END IF;
END $$;
""")

    # ── 10 Extensions ────────────────────────────────────────────────────────
    write('10_extensions', """
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
""")

    # ── 20 Default privileges = Postgres originals while restoring ───────────
    # pg_dump writes each ACL relative to Postgres's built-in default
    # (acldefault), NOT to pg_default_acl. Restoring under ANY other default
    # changes ACLs silently: open defaults would add table-wide SELECT
    # (bypassing column grants); closed defaults would drop a PUBLIC EXECUTE
    # the dump leaves implicit (demo_content_visible today). So: originals.
    write('20_default_privileges_pristine', """
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
""")

    # ── 30 Structure (transformed export) ────────────────────────────────────
    raw = strip_meta(open(os.path.join(EXPORT, 'schema.sql')).read())
    if re.search(r'^\s*CREATE EXTENSION', raw, re.M):
        die("l'export contient CREATE EXTENSION (inattendu avec -n)")
    # Split into pg_dump TOC blocks ("-- Name: …; Type: …; Schema: …").
    parts = re.split(r'(?m)^(?=--\n-- (?:Data for )?Name: )', raw)
    kept, dropped = [], []
    for part in parts:
        m = re.match(r'--\n-- (?:Data for )?Name: (.*?); Type: (.*?); Schema: (.*?);', part)
        if m and 'junto_pre_request' in m.group(1):  # plan v7 decision 4
            dropped.append(f'{m.group(2)} {m.group(1)}')
            continue
        if m and m.group(2) == 'DEFAULT ACL':  # set explicitly in 20 / 70
            dropped.append(f'{m.group(2)} {m.group(1)}')
            continue
        kept.append(part)
    schema = ''.join(kept)
    schema = re.sub(r'(?m)^CREATE SCHEMA public;', 'CREATE SCHEMA IF NOT EXISTS public;', schema)
    if re.search(r'(?m)^ALTER DEFAULT PRIVILEGES', schema):
        die('ALTER DEFAULT PRIVILEGES hors bloc DEFAULT ACL')
    # PostGIS: public.<postgis object> → extensions.<postgis object>, with or without quotes.
    names = '|'.join(sorted((re.escape(n) for n in postgis), key=len, reverse=True))
    pat = re.compile(r'\bpublic\.("?)(' + names + r')\1(?![\w$])')
    schema, n_requal = pat.subn(lambda m: 'extensions.' + m.group(1) + m.group(2) + m.group(1), schema)
    schema = schema.replace('OPERATOR(public.', 'OPERATOR(extensions.')
    # Independent check (not the pattern just used): any PostGIS-looking name still in public.
    left = re.findall(r'\bpublic\.("?)(st_\w+|geograph\w*|geometr\w*|postgis\w*|box[23]d\w*|spatial_ref_sys)\1', schema)
    if left:
        die(f'références PostGIS restantes dans public : {left[:5]}')
    n_geo_cols = len(re.findall(r'extensions\.geography\(', schema))
    if n_geo_cols != meta['n_geo_cols']:
        die(f'{n_geo_cols} colonnes geography requalifiées, {meta["n_geo_cols"]} attendues')
    for v in meta['map_views']:
        block = re.search(r'CREATE VIEW public\.' + re.escape(v) + r'\b.*?;\n', schema, re.S)
        if not block or 'extensions.' not in block.group(0):
            die(f'vue de carte {v} : PostGIS non requalifié')
    n_fn = len(re.findall(r'(?m)^CREATE FUNCTION ', schema))
    expected_fn = meta['n_functions'] - 1  # junto_pre_request removed
    if n_fn != expected_fn:
        die(f'{n_fn} fonctions dans l\'export transformé, {expected_fn} attendues')
    write('30_schema', schema)
    report += [f'30_schema : {n_fn} fonctions, {n_requal} références PostGIS requalifiées, '
               f'{n_geo_cols} colonnes geography, blocs retirés : {dropped}']

    # ── 50 What pg_dump -n does not carry ────────────────────────────────────
    write('50_outside_dump', outside)  # names fully qualified by the generator

    # ── 55 Our own time limits, set by us (not left to platform defaults) ────
    # Each one in its own block: if the platform refuses one, the build warns
    # (visible in build-logs) instead of stopping, and the catalog diff shows it.
    limits = old_query("""
      select string_agg(format('DO $r$ BEGIN EXECUTE %L; EXCEPTION WHEN insufficient_privilege THEN RAISE WARNING %L; END $r$;',
               format('ALTER ROLE %I SET %s = %L', r.rolname, split_part(c, '=', 1), substr(c, strpos(c, '=') + 1)),
               'refused: ' || r.rolname || ' ' || c), E'\n' order by r.rolname, c) as sql
      from pg_db_role_setting s join pg_roles r on r.oid = s.setrole cross join unnest(s.setconfig) c
      where r.rolname in ('authenticator', 'anon', 'authenticated', 'service_role')
        and split_part(c, '=', 1) in ('statement_timeout', 'lock_timeout', 'idle_in_transaction_session_timeout')""")[0]['sql']
    write('55_role_time_limits', limits or '-- none')

    # ── 60 Reference data + app_config ───────────────────────────────────────
    ref = strip_meta(open(os.path.join(EXPORT, 'reference.sql')).read())
    write('60_reference_data', ref + f"""
INSERT INTO public.app_config (name, value) VALUES
  ('demo_mode', 'false'),
  ('project_url', 'https://{new_ref}.supabase.co'),
  ('email_ban_pepper', '{pepper}'),  -- same key: banned fingerprints stay valid
  ('push_webhook_secret', 'provisoire-{secrets.token_hex(16)}');
""")

    # ── 70 Final default privileges = the old project's (postgres role) ─────
    write('70_default_privileges_final', """
-- Old project (2026-10-22): functions executable by nobody unless granted;
-- public tables give clients SELECT only; service_role keeps full access.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO service_role;
NOTIFY pgrst, 'reload schema';
""")

    # ── 80 Migration history: ONE baseline, already applied ──────────────────
    # Without it the CLI would replay the 500+ archived migrations on the next
    # `db push` — starting with 00001, which installs PostGIS in public (the very
    # defect we are leaving). Same table shape as the old project's.
    write('80_migration_history', f"""
CREATE SCHEMA IF NOT EXISTS supabase_migrations;
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (version text PRIMARY KEY, statements text[], name text);
INSERT INTO supabase_migrations.schema_migrations (version, name) VALUES ('{BASELINE}', 'baseline')
ON CONFLICT (version) DO NOTHING;
""")
    # The baseline file the repo will carry (supabase/migrations/{BASELINE}_baseline.sql at cutover):
    # the build itself, secrets masked — rebuilding a project from scratch replays it.
    parts = []
    for name in sorted(os.listdir(BUILD)):
        body = open(os.path.join(BUILD, name)).read()
        body = re.sub(r"\('email_ban_pepper', '[0-9a-f]{64}'\)", "('email_ban_pepper', '<set from the old project>')", body)
        body = re.sub(r"\('push_webhook_secret', '[^']*'\)", "('push_webhook_secret', '<set in phase D>')", body)
        parts.append(f'-- ===== {name} =====\n' + body)
    with open(os.path.join(WORK, f'{BASELINE}_baseline.sql'), 'w') as f:
        f.write(f'-- {BASELINE} baseline — the whole database as migrated (MIGRATION_PLAN v7).\n'
                '-- Earlier migrations live in supabase/migrations_archive/ (history only, never replayed).\n\n'
                + '\n'.join(parts))
    report.append(f'historique : une seule migration de base {BASELINE}, déjà marquée appliquée ; fichier {BASELINE}_baseline.sql prêt')

    with open(os.path.join(WORK, 'prepare-report.txt'), 'w') as f:
        f.write('\n'.join(report) + '\n')
    print('\n'.join(report))
    print(f'Fichiers prêts dans {BUILD} :', ', '.join(sorted(os.listdir(BUILD))))


def write(name, sql):
    with open(os.path.join(BUILD, name + '.sql'), 'w') as f:
        f.write(sql.lstrip('\n'))


if __name__ == '__main__':
    main()
