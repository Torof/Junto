#!/usr/bin/env python3
"""Copy the demo (24 demo accounts, their outings, history, messages, carpools,
gear, votes, discovery, the demo pro and its photos) from the OLD project to the
NEW one — identical rows, ids and timestamps.

    python3 scripts/migration/copy-demo.py <new-ref>            # dry run: export + counts only
    python3 scripts/migration/copy-demo.py <new-ref> --apply    # load + copy photos + verify

A row is copied only when EVERY account it names is a demo account and every
outing / conversation / pro row it points to is itself copied — nothing that
touches a real account. Technical journals (notifications, push tokens, rate
limits, admin actions, reports, QR scans) are not copied. Rows are loaded in
ONE transaction with the tables' own triggers paused (owner-level DISABLE
TRIGGER USER), so nothing is re-derived, re-notified or pushed; either all of
it lands or none. Old-project photo URLs are rewritten to the new project.
"""
import json, os, re, subprocess, sys, base64, urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OLD = 'lvjlthzdydzatcvwwriu'
LINK = os.path.expanduser('~/junto-migration/link')
OUT = os.path.expanduser('~/junto-migration/demo')

# table → {fk column: referenced set}. Sets: users, activities, conversations,
# messages, channels, pro_profiles, pro_offerings, pro_reviews.
TABLES = [
    ('users', {}),  # filter: is_demo
    ('activities', {'creator_id': 'users'}),  # + is_demo
    ('conversations', {'activity_id': 'activities', 'pending_activity_id': 'activities', 'created_by': 'users',
                       'initiated_by': 'users', 'request_sender_id': 'users', 'user_1': 'users', 'user_2': 'users'}),
    ('channels', {'conversation_id': 'conversations', 'created_by': 'users'}),
    ('channel_bans', {'conversation_id': 'channels', 'banned_by': 'users', 'user_id': 'users'}),
    ('conversation_members', {'conversation_id': 'conversations', 'added_by': 'users', 'user_id': 'users'}),
    ('conversation_departures', {'conversation_id': 'conversations', 'user_id': 'users'}),
    ('messages', {'conversation_id': 'conversations', 'reply_to_message_id': 'messages', 'sender_id': 'users'}),
    ('message_original_content', {'message_id': 'messages'}),
    ('participations', {'activity_id': 'activities', 'invited_by': 'users', 'user_id': 'users'}),
    ('seat_requests', {'activity_id': 'activities', 'driver_id': 'users', 'requester_id': 'users'}),
    ('activity_gear', {'activity_id': 'activities', 'user_id': 'users'}),
    ('activity_gear_missing', {'activity_id': 'activities', 'created_by': 'users'}),
    ('reputation_votes', {'activity_id': 'activities', 'voted_id': 'users', 'voter_id': 'users'}),
    ('late_cancels', {'activity_id': 'activities', 'user_id': 'users'}),
    ('invitation_declines', {'activity_id': 'activities', 'user_id': 'users'}),
    ('discovery_availabilities', {'user_id': 'users'}),
    ('gpx_traces', {'user_id': 'users'}),
    ('user_badge_progression', {'user_id': 'users'}),
    ('blocked_users', {'blocker_id': 'users', 'blocked_id': 'users'}),
    ('pro_profiles', {'user_id': 'users', 'reviewed_by': 'users'}),
    ('pro_profile_photos', {'pro_id': 'pro_profiles'}),
    ('pro_offerings', {'pro_id': 'pro_profiles'}),
    ('pro_offering_photos', {'offering_id': 'pro_offerings'}),
    ('pro_availabilities', {'pro_id': 'users'}),
    ('pro_reviews', {'pro_id': 'pro_profiles', 'reviewer_id': 'users'}),
    ('offering_reviews', {'offering_id': 'pro_offerings', 'reviewer_id': 'users'}),
    ('pro_community_photos', {'contributor_id': 'users', 'offering_id': 'pro_offerings', 'pro_id': 'pro_profiles', 'review_id': 'pro_reviews'}),
    ('bookings', {'client_id': 'users', 'offering_id': 'pro_offerings', 'pro_id': 'users'}),
    ('favorites', {'activity_id': 'activities', 'offering_id': 'pro_offerings', 'owner_id': 'users', 'pro_id': 'pro_profiles'}),
]
KEY = {'pro_profiles': 'user_id', 'channels': 'conversation_id'}  # primary key column when it is not "id" (read from the catalog)


def q(sql, cwd=ROOT):
    path = os.path.join(OUT, '.q.sql')
    open(path, 'w').write(sql)
    out = subprocess.run(['npx', 'supabase', 'db', 'query', '--experimental', '--linked', '-f', path],
                         cwd=cwd, capture_output=True, text=True).stdout
    os.remove(path)
    i = out.find('{')
    if i < 0:
        sys.exit(f'ARRÊT : pas de réponse\n{out[-800:]}')
    d = json.loads(out[i:])
    if 'rows' not in d:
        sys.exit(f'ARRÊT : {json.dumps(d)[:800]}')
    return d['rows']


def filters():
    """WHERE clause per table, each referenced set expressed through its own filter."""
    where = {'users': 'is_demo', 'activities': 'is_demo AND creator_id IN (SELECT id FROM public.users WHERE is_demo)'}
    def subset(ref):
        return f'(SELECT {KEY.get(ref, "id")} FROM public.{ref} WHERE {where[ref]})'
    for t, fks in TABLES:
        if t in where:
            continue
        # A self-reference (messages.reply_to_message_id) is resolved after export.
        all_ok = ' AND '.join(f'({c} IS NULL OR {c} IN {subset(r)})' for c, r in fks.items() if r != t)
        any_ok = ' OR '.join(f'{c} IN {subset(r)}' for c, r in fks.items() if r != t)
        where[t] = f'({all_ok}) AND ({any_ok})'
    return where


def main():
    if len(sys.argv) < 2 or not re.fullmatch(r'[a-z0-9]{20}', sys.argv[1]) or sys.argv[1] == OLD:
        sys.exit('Usage : copy-demo.py <référence du nouveau projet> [--apply]')
    new, apply = sys.argv[1], '--apply' in sys.argv
    os.makedirs(OUT, exist_ok=True)
    os.umask(0o077)
    where = filters()

    # ── 1. Export from the old project (read-only) ───────────────────────────
    data = {}
    auth = q("SELECT coalesce(json_agg(json_build_object('id', id, 'email', email, 'created_at', created_at, "
             "'email_confirmed_at', email_confirmed_at, 'raw_user_meta_data', raw_user_meta_data)), '[]') AS j "
             "FROM auth.users WHERE id IN (SELECT id FROM public.users WHERE is_demo)")[0]['j']
    data['auth.users'] = auth if isinstance(auth, list) else json.loads(auth)
    for t, _ in TABLES:
        rows = q(f'SELECT coalesce(json_agg(x ORDER BY x.created_at NULLS FIRST), \'[]\') AS j FROM public.{t} x WHERE {where[t]}'
                 if t in ('messages',) else f'SELECT coalesce(json_agg(x), \'[]\') AS j FROM public.{t} x WHERE {where[t]}')[0]['j']
        data[t] = rows if isinstance(rows, list) else json.loads(rows)
    # A reply to a message that is not copied (written by a real account) loses its link.
    kept = {m['id'] for m in data['messages']}
    for m in data['messages']:
        if m.get('reply_to_message_id') and m['reply_to_message_id'] not in kept:
            m['reply_to_message_id'] = None
    text = json.dumps(data).replace(f'{OLD}.supabase.co', f'{new}.supabase.co')
    if OLD in text:
        sys.exit("ARRÊT : la référence de l'ancien projet reste dans les données")
    data = json.loads(text)
    counts = {t: len(v) for t, v in data.items()}
    print('Export :', ', '.join(f'{t}={n}' for t, n in counts.items() if n))
    photos = sorted(set(re.findall(rf'https://{new}\.supabase\.co/storage/v1/object/public/([a-z-]+)/([^"\s]+)', text)))
    print(f'Photos à recopier : {len(photos)}')
    json.dump({'counts': counts}, open(os.path.join(OUT, 'export-counts.json'), 'w'))
    if not apply:
        print('Essai à blanc : rien écrit. Relancer avec --apply.')
        return

    # ── 2. Load on the new project, one transaction, triggers paused ─────────
    if open(os.path.join(LINK, 'supabase', '.temp', 'project-ref')).read().strip() != new:
        sys.exit('ARRÊT : le dossier lié ne vise pas le nouveau projet')
    payload = base64.b64encode(json.dumps(data).encode()).decode()
    tables = [t for t, _ in TABLES]
    lines = ['DO $demo$', 'DECLARE d jsonb; cols text; t text;', 'BEGIN',
             f"  d := convert_from(decode('{payload}', 'base64'), 'UTF8')::jsonb;",
             "  IF EXISTS (SELECT 1 FROM public.users WHERE is_demo) THEN RAISE EXCEPTION 'demo already present'; END IF;",
             "  PERFORM set_config('junto.bypass_lock', 'true', true);"]
    lines += [f'  ALTER TABLE public.{t} DISABLE TRIGGER USER;' for t in tables]
    # Accounts: auth row (its trigger creates a default profile), then the exact profile.
    # Token columns as empty strings (NULL breaks the auth service's user listing).
    lines += ["  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,",
              "                          confirmation_token, recovery_token, email_change_token_new, email_change)",
              "  SELECT '00000000-0000-0000-0000-000000000000', (u->>'id')::uuid, 'authenticated', 'authenticated', u->>'email', '', (u->>'email_confirmed_at')::timestamptz,",
              "         '{\"provider\":\"email\",\"providers\":[\"email\"]}'::jsonb, coalesce(u->'raw_user_meta_data', '{}'::jsonb), (u->>'created_at')::timestamptz, (u->>'created_at')::timestamptz, '', '', '', ''",
              "  FROM jsonb_array_elements(d->'auth.users') u;",
              "  DELETE FROM public.users WHERE id IN (SELECT (u->>'id')::uuid FROM jsonb_array_elements(d->'auth.users') u);"]
    for t in tables:
        lines += [f"  SELECT string_agg(quote_ident(attname), ', ' ORDER BY attnum) INTO cols FROM pg_attribute",
                  f"   WHERE attrelid = 'public.{t}'::regclass AND attnum > 0 AND NOT attisdropped AND attgenerated = '';",
                  f"  EXECUTE format('INSERT INTO public.{t} (%s) SELECT %s FROM jsonb_populate_recordset(NULL::public.{t}, $1)', cols, cols) USING d->'{t}';"]
    lines += [f'  ALTER TABLE public.{t} ENABLE TRIGGER USER;' for t in tables]
    lines += ["  PERFORM set_config('junto.bypass_lock', 'false', true);", 'END $demo$;']
    sql = '\n'.join(lines)
    path = os.path.join(OUT, 'load.sql')
    open(path, 'w').write(sql)
    out = subprocess.run(['npx', 'supabase', 'db', 'query', '--experimental', '--linked', '-f', path],
                         cwd=LINK, capture_output=True, text=True).stdout
    if 'error' in out.lower() and '"rows"' not in out:
        sys.exit('ARRÊT : chargement refusé (rien n\'est écrit)\n' + out[-1200:])
    print('Chargement : fait (une transaction).')

    # ── 3. Photos: old public URL → new storage, same path ───────────────────
    keys = json.loads(subprocess.run(['npx', 'supabase', 'projects', 'api-keys', '--project-ref', new, '-o', 'json'],
                                     cwd=ROOT, capture_output=True, text=True).stdout)
    keys = keys['keys'] if isinstance(keys, dict) else keys
    service = [k['api_key'] for k in keys if k.get('name') == 'service_role'][0]
    done = 0
    for bucket, name in photos:
        src = f'https://{OLD}.supabase.co/storage/v1/object/public/{bucket}/{name}'
        body = urllib.request.urlopen(src, timeout=30).read()
        ctype = 'image/png' if name.endswith('.png') else 'image/webp' if name.endswith('.webp') else 'image/jpeg'
        req = urllib.request.Request(f'https://{new}.supabase.co/storage/v1/object/{bucket}/{name}', data=body, method='POST',
                                     headers={'Authorization': f'Bearer {service}', 'apikey': service,
                                              'Content-Type': ctype, 'x-upsert': 'true'})
        urllib.request.urlopen(req, timeout=60).read()
        done += 1
    del service
    print(f'Photos recopiées : {done}/{len(photos)}')

    # ── 4. Verify: same counts on the new project ─────────────────────────────
    checks = ' UNION ALL '.join(
        [f"SELECT 'auth.users' t, count(*) n FROM auth.users WHERE id IN (SELECT id FROM public.users WHERE is_demo)"] +
        [f"SELECT '{t}', count(*) FROM public.{t} WHERE {where[t]}" for t, _ in TABLES])
    got = {r['t']: r['n'] for r in q(checks, cwd=LINK)}
    bad = {t: (counts[t], got.get(t)) for t in counts if counts[t] != got.get(t)}
    print('Vérification :', 'identique pour toutes les tables' if not bad else f'ÉCARTS {bad}')


if __name__ == '__main__':
    main()
