-- Domaine 1 — identité, comptes, administration.
-- Fixtures
PERFORM pg_temp.user('alice', 'tos');
PERFORM pg_temp.user('bob', 'tos');
PERFORM pg_temp.user('sam', 'tos,suspended');
PERFORM pg_temp.user('noob');               -- n'a ni âge confirmé ni CGU acceptées
PERFORM pg_temp.user('adm', 'tos,admin');
PERFORM pg_temp.user('adm2', 'tos,admin');
PERFORM pg_temp.user('demo1', 'tos,demo');

-- ───── Table users : lecture ─────
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne lit pas users', $$SELECT count(*)::text FROM public.users$$);

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('alice ne voit que sa propre ligne users', $$SELECT count(*)::text FROM public.users$$, '1');
PERFORM pg_temp.eq('alice ne lit pas l''e-mail de bob', format($$SELECT count(*)::text FROM public.users WHERE id = %L$$, pg_temp.id('bob')), '0');

-- ───── Table users : écriture ─────
PERFORM pg_temp.eq('alice modifie son nom affiché',
  format($$WITH u AS (UPDATE public.users SET display_name = 'Alice Test' WHERE id = %L RETURNING display_name) SELECT display_name FROM u$$, pg_temp.id('alice')),
  'Alice Test');
PERFORM pg_temp.eq('alice ne peut pas modifier la ligne de bob',
  format($$WITH u AS (UPDATE public.users SET bio = 'x' WHERE id = %L RETURNING 1) SELECT count(*)::text FROM u$$, pg_temp.id('bob')), '0');

-- Colonnes privilégiées : la mise à jour passe mais le trigger remet l'ancienne valeur.
PERFORM pg_temp.ok('alice tente de se donner des droits privilégiés', format(
  $$UPDATE public.users SET is_admin = true, tier = 'pro', reliability_score = 100, is_demo = true,
      suspended_at = NULL, levels_per_sport = '{"climbing":"8a"}'::jsonb, email = 'x@evil.test' WHERE id = %L$$, pg_temp.id('alice')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('is_admin reste faux', format($$SELECT is_admin::text FROM public.users WHERE id = %L$$, pg_temp.id('alice')), 'false');
PERFORM pg_temp.eq('reliability_score inchangé', format($$SELECT coalesce(reliability_score::text, 'null') FROM public.users WHERE id = %L$$, pg_temp.id('alice')), 'null');
PERFORM pg_temp.eq('is_demo reste faux', format($$SELECT is_demo::text FROM public.users WHERE id = %L$$, pg_temp.id('alice')), 'false');
PERFORM pg_temp.eq('levels_per_sport inchangé', format($$SELECT coalesce(levels_per_sport::text, '{}') FROM public.users WHERE id = %L$$, pg_temp.id('alice')),
  (SELECT coalesce(levels_per_sport::text, '{}') FROM public.users WHERE id = pg_temp.id('alice')));
PERFORM pg_temp.eq('e-mail inchangé', format($$SELECT (email LIKE '%%@junto.test')::text FROM public.users WHERE id = %L$$, pg_temp.id('alice')), 'true');

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('avatar hors du stockage du projet refusé',
  format($$UPDATE public.users SET avatar_url = 'https://evil.example/pixel.png' WHERE id = %L$$, pg_temp.id('alice')),
  '.');
PERFORM pg_temp.denied('avatar : remontée « .. » vers le dossier d''un autre refusée',
  format($$UPDATE public.users SET avatar_url = %L WHERE id = %L$$,
    'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/avatars/' || pg_temp.id('alice') || '/../' || pg_temp.id('bob') || '/avatar', pg_temp.id('alice')),
  'Operation not permitted');
PERFORM pg_temp.ok('avatar : une image de son propre dossier est acceptée',
  format($$UPDATE public.users SET avatar_url = %L WHERE id = %L$$,
    'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/avatars/' || pg_temp.id('alice') || '/avatar?t=1', pg_temp.id('alice')));

-- ───── Vue public_profiles (00476) ─────
PERFORM pg_temp.eq('alice voit le profil public de bob', format($$SELECT count(*)::text FROM public.public_profiles WHERE id = %L$$, pg_temp.id('bob')), '1');
PERFORM pg_temp.eq('un compte suspendu n''apparaît pas', format($$SELECT count(*)::text FROM public.public_profiles WHERE id = %L$$, pg_temp.id('sam')), '0');
PERFORM pg_temp.eq('un compte démo n''apparaît pas hors mode démo', format($$SELECT count(*)::text FROM public.public_profiles WHERE id = %L$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.denied('modifier un profil via la vue est refusé (ID-1)', format($$UPDATE public.public_profiles SET bio = 'x' WHERE id = %L$$, pg_temp.id('bob')));
PERFORM pg_temp.denied('supprimer un profil via la vue est refusé (ID-1)', format($$DELETE FROM public.public_profiles WHERE id = %L$$, pg_temp.id('bob')));
PERFORM pg_temp.eq('le score brut n''est pas exposé par la vue', format($$SELECT coalesce(reliability_score::text, 'null') FROM public.public_profiles WHERE id = %L$$, pg_temp.id('bob')), 'null');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne lit pas public_profiles', $$SELECT count(*)::text FROM public.public_profiles$$);

-- ───── Blocage ─────
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice bloque bob', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L) RETURNING 'ok'$$, pg_temp.id('alice'), pg_temp.id('bob')));
PERFORM pg_temp.denied('alice ne peut pas créer un blocage au nom de bob',
  format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('bob'), pg_temp.id('alice')));
PERFORM pg_temp.denied('on ne peut pas se bloquer soi-même',
  format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('alice'), pg_temp.id('alice')));

-- ───── Signalements ─────
PERFORM pg_temp.ok('alice signale bob', format($$SELECT public.create_report('user', %L, 'Raison de test suffisamment longue')::text$$, pg_temp.id('bob')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne peut pas signaler', format($$SELECT public.create_report('user', %L, 'Raison de test suffisamment longue')::text$$, pg_temp.id('bob')));

-- ───── Administration ─────
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('un non-admin ne peut pas suspendre', format($$SELECT public.admin_suspend_user(%L, 'raison de test')::text$$, pg_temp.id('bob')));
PERFORM pg_temp.denied('un non-admin ne peut pas chercher un compte', format($$SELECT count(*)::text FROM public.admin_resolve_user(%L)$$, pg_temp.id('bob')), 'Operation not permitted');
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.eq('un admin retrouve un compte par son identifiant', format($$SELECT count(*)::text FROM public.admin_resolve_user(%L)$$, pg_temp.id('bob')), '1');
PERFORM pg_temp.denied('un admin ne peut pas suspendre un autre admin', format($$SELECT public.admin_suspend_user(%L, 'raison de test')::text$$, pg_temp.id('adm2')));
PERFORM pg_temp.ok('un admin suspend un utilisateur', format($$SELECT public.admin_suspend_user(%L, 'raison de test')::text$$, pg_temp.id('bob')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la suspension est effective', format($$SELECT (suspended_at IS NOT NULL)::text FROM public.users WHERE id = %L$$, pg_temp.id('bob')), 'true');
PERFORM pg_temp.eq('l''action admin est journalisée', format($$SELECT (count(*) > 0)::text FROM public.admin_actions WHERE target_id = %L$$, pg_temp.id('bob')), 'true');

-- ───── Trous connus (doivent échouer tant qu'ils ne sont pas corrigés) ─────
-- ID-2 (00506, décision Scott) : un suspendu peut effacer son compte, mais son e-mail ne sert plus
-- à se réinscrire (empreinte HMAC gardée ; réinscription par le support).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('sam_email', (SELECT email FROM auth.users WHERE id = pg_temp.id('sam')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.ok('un compte suspendu peut effacer son compte', $$SELECT public.delete_own_account()::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('ID-2 : l''empreinte de l''e-mail est gardée, pas l''e-mail', $$SELECT private.email_is_banned(pg_temp.get('sam_email'))::text$$, 'true');
PERFORM pg_temp.denied('ID-2 : se réinscrire avec cet e-mail (variante +tag, majuscules) est refusé',
  $$INSERT INTO auth.users (id, email, aud, role, raw_user_meta_data, created_at, updated_at)
    VALUES (gen_random_uuid(), upper(replace(pg_temp.get('sam_email'), '@', '+re@')), 'authenticated', 'authenticated', '{}'::jsonb, now(), now())$$, 'Operation not permitted');
PERFORM pg_temp.eq('ID-2 : un compte non suspendu qui s''efface ne laisse aucune empreinte',
  $$SELECT private.email_is_banned('test-' || pg_temp.id('bob') || '@junto.test')::text$$, 'false');
PERFORM pg_temp.as_('noob');
PERFORM pg_temp.denied('sans âge confirmé ni CGU acceptées, on ne peut pas créer de sortie',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test', 'x', 'Tous niveaux', 5, 6.6, 44.9, NULL, NULL, now() + interval '2 days')::text$$,
  '.');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('un visiteur sans compte ne peut pas écrire dans spatial_ref_sys',
  $$DELETE FROM public.spatial_ref_sys WHERE srid = -1$$, 'permission denied', 'TX-2');
