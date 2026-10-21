-- Domaine 7 — couverture : fonctions et tâches planifiées qu'aucun autre fichier ne touche
-- (premiers pas, administration restante, quotas des fonctions Edge, lectures diverses,
-- envois historiques, purges et expirations planifiées).

-- ───── Utilitaires locaux ─────
-- Sortie créée en tant que db (créateur inscrit 'accepted'), en plein Pacifique, décalage relatif à now().
EXECUTE $p$CREATE FUNCTION pg_temp.cv_act(p_label text, p_creator text, p_start interval, p_status text,
    p_rp boolean DEFAULT false) RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting,
      starts_at, duration, visibility, status, requires_presence)
    VALUES (pg_temp.id(p_creator), (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test ' || p_label,
      'Tous niveaux', 10, ST_SetSRID(ST_MakePoint(-130.2, -45.2), 4326)::geography,
      now() + p_start, interval '2 hours', 'public', p_status, p_rp)
    RETURNING id INTO v;
    INSERT INTO public.participations (activity_id, user_id, status, created_at)
    VALUES (v, pg_temp.id(p_creator), 'accepted', now() - interval '3 days');
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.cv_part(p_act text, p_user text, p_status text DEFAULT 'accepted',
    p_cp boolean DEFAULT NULL, p_by text DEFAULT NULL) RETURNS void
  LANGUAGE sql AS $b$
  INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, invited_by, created_at)
  VALUES (pg_temp.id(p_act), pg_temp.id(p_user), p_status, p_cp, pg_temp.id(p_by), now() - interval '2 days') $b$$p$;

-- Fil DM (db) entre deux comptes, statut et âge au choix.
EXECUTE $p$CREATE FUNCTION pg_temp.cv_dm(p_key text, a text, b text, p_status text DEFAULT 'active',
    p_age interval DEFAULT interval '0') RETURNS uuid
  LANGUAGE plpgsql AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.conversations (type, user_1, user_2, initiated_by, request_sender_id, status, initiated_from,
      created_at, last_message_at)
    VALUES ('dm', LEAST(pg_temp.id(a), pg_temp.id(b)), GREATEST(pg_temp.id(a), pg_temp.id(b)), pg_temp.id(a),
      CASE WHEN p_status = 'active' THEN NULL ELSE pg_temp.id(a) END, p_status, 'profile', now() - p_age, now() - p_age)
    RETURNING id INTO v;
    PERFORM pg_temp.put(p_key, v::text);
    RETURN v;
  END $b$$p$;

-- Appelle p_sql jusqu'à p_n fois avec le rôle courant ; renvoie « nb de succès:première erreur ».
EXECUTE $p$CREATE FUNCTION pg_temp.cv_loop(p_sql text, p_n int) RETURNS text
  LANGUAGE plpgsql AS $b$
  BEGIN
    FOR i IN 1..p_n LOOP
      BEGIN
        EXECUTE p_sql;
      EXCEPTION WHEN OTHERS THEN RETURN (i - 1) || ':' || SQLERRM; END;
    END LOOP;
    RETURN p_n || ':none';
  END $b$$p$;

-- Entrée d'un participant dans l'état de relecture entre pairs (jsonb texte, 'absent' si pas de ligne).
EXECUTE $p$CREATE FUNCTION pg_temp.cv_review(p_act text, p_user text, p_field text) RETURNS text
  LANGUAGE sql AS $b$
  SELECT coalesce((SELECT (e -> p_field)::text
    FROM jsonb_array_elements(public.get_activity_peer_review_state(pg_temp.id(p_act))) e
    WHERE e ->> 'user_id' = pg_temp.get(p_user)), 'absent') $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.user('noob');                    -- ni âge ni CGU
PERFORM pg_temp.user('noob2');
PERFORM pg_temp.user('nsus', 'suspended');       -- suspendu, sans CGU
PERFORM pg_temp.user('alice', 'tos');
PERFORM pg_temp.user('bob', 'tos');
PERFORM pg_temp.user('crea', 'tos');
PERFORM pg_temp.user('mal', 'tos');              -- étranger à tout
PERFORM pg_temp.user('dan', 'tos');
PERFORM pg_temp.user('sam', 'tos,suspended');
PERFORM pg_temp.user('demo1', 'tos,demo');
PERFORM pg_temp.user('adm', 'tos,admin');
PERFORM pg_temp.user('sadm', 'tos,admin,suspended');
PERFORM pg_temp.user('victim', 'tos,suspended'); -- à réactiver
PERFORM pg_temp.user('ppend', 'tos');            -- candidature pro en attente
PERFORM pg_temp.user('pro', 'tos');              -- pro approuvé (réservations)
PERFORM pg_temp.user('q1', 'tos');
PERFORM pg_temp.user('q2', 'tos');
PERFORM pg_temp.user('k1', 'tos');
PERFORM pg_temp.user('k2', 'tos');
PERFORM pg_temp.user('k3', 'tos');
PERFORM pg_temp.user('k4', 'tos');
PERFORM pg_temp.user('k5', 'tos');

-- ═════ 1. Premiers pas : âge, CGU, tutoriel ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne confirme pas d''âge', $$SELECT public.confirm_age_adult()::text$$, 'permission denied|Operation not permitted');
PERFORM pg_temp.denied('anon n''accepte pas de CGU', $$SELECT public.accept_tos()::text$$, 'permission denied|Operation not permitted');
PERFORM pg_temp.denied('anon ne marque pas le tutoriel', $$SELECT public.mark_tutorial_seen()::text$$, 'permission denied|Operation not permitted');

PERFORM pg_temp.as_('noob2');
PERFORM pg_temp.ok('noob2 tente d''écrire ses dates de CGU/âge en direct', format(
  $$UPDATE public.users SET accepted_tos_at = now(), age_confirmed_at = now(), tutorial_seen_at = now() WHERE id = %L$$, pg_temp.id('noob2')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('l''écriture directe des dates de CGU/âge/tutoriel est ignorée', format(
  $$SELECT (accepted_tos_at IS NULL AND age_confirmed_at IS NULL AND tutorial_seen_at IS NULL)::text FROM public.users WHERE id = %L$$, pg_temp.id('noob2')), 'true');

PERFORM pg_temp.as_('noob');
PERFORM pg_temp.ok('un nouveau compte confirme sa majorité', $$SELECT public.confirm_age_adult()::text$$);
PERFORM pg_temp.ok('un nouveau compte accepte les CGU', $$SELECT public.accept_tos()::text$$);
PERFORM pg_temp.ok('un nouveau compte marque le tutoriel vu', $$SELECT public.mark_tutorial_seen()::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('âge, CGU, confidentialité et tutoriel sont enregistrés', format(
  $$SELECT (age_confirmed_at IS NOT NULL AND accepted_tos_at IS NOT NULL AND accepted_privacy_at IS NOT NULL AND tutorial_seen_at IS NOT NULL)::text
    FROM public.users WHERE id = %L$$, pg_temp.id('noob')), 'true');
PERFORM pg_temp.eq('les appels de noob ne touchent pas les colonnes de noob2', format(
  $$SELECT (accepted_tos_at IS NULL AND age_confirmed_at IS NULL AND tutorial_seen_at IS NULL)::text FROM public.users WHERE id = %L$$, pg_temp.id('noob2')), 'true');
-- Idempotence : la date d'origine (valeur légale) est conservée.
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET accepted_tos_at = '2026-01-01 00:00:00+00', accepted_privacy_at = '2026-01-01 00:00:00+00',
  age_confirmed_at = '2026-01-01 00:00:00+00' WHERE id = pg_temp.id('noob');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('noob');
PERFORM pg_temp.ok('accepter les CGU une deuxième fois ne plante pas', $$SELECT public.accept_tos()::text$$);
PERFORM pg_temp.ok('confirmer la majorité une deuxième fois ne plante pas', $$SELECT public.confirm_age_adult()::text$$);
PERFORM pg_temp.ok('marquer le tutoriel une deuxième fois ne plante pas', $$SELECT public.mark_tutorial_seen()::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la date d''acceptation d''origine des CGU est conservée', format(
  $$SELECT (accepted_tos_at = '2026-01-01 00:00:00+00' AND accepted_privacy_at = '2026-01-01 00:00:00+00')::text FROM public.users WHERE id = %L$$, pg_temp.id('noob')), 'true');
PERFORM pg_temp.eq('la date de confirmation d''âge d''origine est conservée', format(
  $$SELECT (age_confirmed_at = '2026-01-01 00:00:00+00')::text FROM public.users WHERE id = %L$$, pg_temp.id('noob')), 'true');

PERFORM pg_temp.as_('nsus');
PERFORM pg_temp.denied('un compte suspendu ne confirme pas son âge', $$SELECT public.confirm_age_adult()::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('un compte suspendu n''accepte pas les CGU', $$SELECT public.accept_tos()::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le compte suspendu reste sans âge ni CGU', format(
  $$SELECT (accepted_tos_at IS NULL AND age_confirmed_at IS NULL)::text FROM public.users WHERE id = %L$$, pg_temp.id('nsus')), 'true');

-- ═════ 2. Administration ═════
-- Candidature pro en attente + pro approuvé avec une offre (fixtures db).
INSERT INTO public.pro_profiles (user_id, display_name, real_name, email, primary_lng, primary_lat, primary_location, primary_location_name, status)
VALUES (pg_temp.id('ppend'), 'Pro en attente', 'Nom Civil Test', 'pro-pending@junto.test', -130.2, -45.2,
  ST_SetSRID(ST_MakePoint(-130.2, -45.2), 4326)::geography, 'Océan', 'pending');
INSERT INTO public.pro_profiles (user_id, display_name, primary_lng, primary_lat, primary_location, primary_location_name, status)
VALUES (pg_temp.id('pro'), 'Pro approuvé', -130.2, -45.2, ST_SetSRID(ST_MakePoint(-130.2, -45.2), 4326)::geography, 'Océan', 'approved');
PERFORM pg_temp.put('off', pg_temp.run($q$INSERT INTO public.pro_offerings (pro_id, sport_id, title, description, level, location, location_name)
  VALUES (pg_temp.id('pro'), (SELECT id FROM public.sports WHERE key = 'hiking'), 'Offre test couverture', 'Desc', 'Tous niveaux',
    ST_SetSRID(ST_MakePoint(-130.2, -45.2), 4326)::geography, 'Océan') RETURNING id$q$));

PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne réactive pas de compte', format($$SELECT public.admin_unsuspend_user(%L, 'raison')::text$$, pg_temp.id('victim')), 'permission denied|Operation not permitted');
PERFORM pg_temp.denied('anon ne lit pas les candidatures pro', $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications()$$, 'permission denied|Operation not permitted');
PERFORM pg_temp.denied('anon ne lit pas le titulaire d''un pro', format($$SELECT count(*)::text FROM public.admin_pro_owner(%L)$$, pg_temp.id('pro')), 'permission denied|Operation not permitted');
PERFORM pg_temp.denied('anon ne bascule pas le mode démo', $$SELECT public.admin_set_demo_mode(false)::text$$, 'permission denied|Operation not permitted');

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('un non-admin ne réactive pas un compte', format($$SELECT public.admin_unsuspend_user(%L, 'raison')::text$$, pg_temp.id('victim')), 'Operation not permitted');
PERFORM pg_temp.denied('un non-admin ne lit pas les candidatures pro', $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications()$$, 'Operation not permitted');
PERFORM pg_temp.denied('un non-admin ne lit pas le titulaire d''un pro', format($$SELECT count(*)::text FROM public.admin_pro_owner(%L)$$, pg_temp.id('pro')), 'Operation not permitted');
PERFORM pg_temp.denied('un non-admin ne bascule pas le mode démo', $$SELECT public.admin_set_demo_mode(false)::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('un non-admin ne réactive pas un autre compte suspendu', format($$SELECT public.admin_unsuspend_user(%L, 'raison')::text$$, pg_temp.id('sam')), 'Operation not permitted');

PERFORM pg_temp.as_('sadm');
PERFORM pg_temp.denied('un admin suspendu ne réactive pas un compte', format($$SELECT public.admin_unsuspend_user(%L, 'raison')::text$$, pg_temp.id('victim')), 'Operation not permitted');
PERFORM pg_temp.denied('un admin suspendu ne se réactive pas lui-même', format($$SELECT public.admin_unsuspend_user(%L, 'raison')::text$$, pg_temp.id('sadm')), 'Operation not permitted');
PERFORM pg_temp.denied('un admin suspendu ne lit pas les candidatures pro', $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications()$$, 'Operation not permitted');
PERFORM pg_temp.denied('un admin suspendu ne lit pas le titulaire d''un pro', format($$SELECT count(*)::text FROM public.admin_pro_owner(%L)$$, pg_temp.id('pro')), 'Operation not permitted');
PERFORM pg_temp.denied('un admin suspendu ne bascule pas le mode démo', $$SELECT public.admin_set_demo_mode(false)::text$$, 'Operation not permitted');

PERFORM pg_temp.as_('adm');
PERFORM pg_temp.denied('réactiver sans motif est refusé', format($$SELECT public.admin_unsuspend_user(%L, '   ')::text$$, pg_temp.id('victim')), 'junto.admin_reason_required');
PERFORM pg_temp.denied('réactiver un compte non suspendu est refusé', format($$SELECT public.admin_unsuspend_user(%L, 'raison')::text$$, pg_temp.id('alice')), 'Operation not permitted');
PERFORM pg_temp.ok('un admin réactive un compte suspendu', format($$SELECT public.admin_unsuspend_user(%L, 'erreur de modération')::text$$, pg_temp.id('victim')));
PERFORM pg_temp.eq('l''admin voit la candidature pro en attente', format(
  $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications() WHERE user_id = %L AND real_name = 'Nom Civil Test'$$, pg_temp.id('ppend')), '1');
PERFORM pg_temp.eq('un pro déjà approuvé n''est pas listé comme candidature', format(
  $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications() WHERE user_id = %L$$, pg_temp.id('pro')), '0');
PERFORM pg_temp.eq('l''admin retrouve le titulaire d''un pro', format(
  $$SELECT (owner_email = 'test-' || %L || '@junto.test')::text FROM public.admin_pro_owner(%L)$$, pg_temp.id('pro'), pg_temp.id('pro')), 'true');
PERFORM pg_temp.denied('titulaire d''un identifiant qui n''est pas un pro : refusé', format($$SELECT count(*)::text FROM public.admin_pro_owner(%L)$$, pg_temp.id('alice')), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la réactivation est effective', format($$SELECT (suspended_at IS NULL)::text FROM public.users WHERE id = %L$$, pg_temp.id('victim')), 'true');
PERFORM pg_temp.eq('la réactivation est journalisée avec son motif', format(
  $$SELECT count(*)::text FROM public.admin_actions WHERE action = 'unsuspend_user' AND admin_id = %L AND target_id = %L AND reason = 'erreur de modération'$$,
  pg_temp.id('adm'), pg_temp.id('victim')), '1');
PERFORM pg_temp.eq('la consultation du titulaire d''un pro est journalisée', format(
  $$SELECT count(*)::text FROM public.admin_actions WHERE action = 'pro_owner' AND admin_id = %L AND target_id = %L$$, pg_temp.id('adm'), pg_temp.id('pro')), '1');
PERFORM pg_temp.eq('les refus ne laissent aucune trace de réactivation', format(
  $$SELECT count(*)::text FROM public.admin_actions WHERE action = 'unsuspend_user' AND target_id IN (%L, %L, %L)$$,
  pg_temp.id('alice'), pg_temp.id('sam'), pg_temp.id('sadm')), '0');
PERFORM pg_temp.eq('sam reste suspendu', format($$SELECT (suspended_at IS NOT NULL)::text FROM public.users WHERE id = %L$$, pg_temp.id('sam')), 'true');
PERFORM pg_temp.eq('les refus de bascule n''ont pas journalisé de mode démo', format(
  $$SELECT count(*)::text FROM public.admin_actions WHERE action LIKE 'demo_mode%%' AND admin_id IN (%L, %L)$$, pg_temp.id('alice'), pg_temp.id('sadm')), '0');

-- ═════ 3. Quotas des fonctions Edge (snap-trail, trace-elevation) ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne consomme pas de quota snap-trail', $$SELECT public.consume_snap_trail_quota()::text$$, 'permission denied|Operation not permitted');
PERFORM pg_temp.denied('anon ne consomme pas de quota altimétrie', $$SELECT public.consume_trace_elevation_quota()::text$$, 'permission denied|Operation not permitted');
PERFORM pg_temp.denied('anon ne consomme pas de points altimétrie', $$SELECT public.consume_trace_elevation_points(10)::text$$, 'permission denied|Operation not permitted');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un suspendu ne consomme pas de quota snap-trail', $$SELECT public.consume_snap_trail_quota()::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('un suspendu ne consomme pas de quota altimétrie', $$SELECT public.consume_trace_elevation_quota()::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('un suspendu ne consomme pas de points altimétrie', $$SELECT public.consume_trace_elevation_points(10)::text$$, 'Operation not permitted');

PERFORM pg_temp.as_('q1');
PERFORM pg_temp.eq('snap-trail : 200 appels par heure, le 201e est refusé',
  $$SELECT pg_temp.cv_loop('SELECT public.consume_snap_trail_quota()', 201)$$, '200:junto.rate_limited');
PERFORM pg_temp.eq('altimétrie : 150 appels par heure, le 151e est refusé',
  $$SELECT pg_temp.cv_loop('SELECT public.consume_trace_elevation_quota()', 151)$$, '150:junto.rate_limited');
PERFORM pg_temp.denied('altimétrie : 0 point refusé', $$SELECT public.consume_trace_elevation_points(0)::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('altimétrie : plus de 10 000 points par appel refusé', $$SELECT public.consume_trace_elevation_points(10001)::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('altimétrie : nombre de points absent refusé', $$SELECT public.consume_trace_elevation_points(NULL)::text$$, 'Operation not permitted');
PERFORM pg_temp.eq('altimétrie : 50 000 points par heure, au-delà refusé',
  $$SELECT pg_temp.cv_loop('SELECT public.consume_trace_elevation_points(10000)', 6)$$, '5:junto.rate_limited');
PERFORM pg_temp.as_('q2');
PERFORM pg_temp.ok('quota par compte : q2 garde son quota snap-trail', $$SELECT public.consume_snap_trail_quota()::text$$);
PERFORM pg_temp.ok('quota par compte : q2 garde son quota altimétrie', $$SELECT public.consume_trace_elevation_quota()::text$$);
PERFORM pg_temp.ok('quota par compte : q2 garde ses points altimétrie', $$SELECT public.consume_trace_elevation_points(10000)::text$$);
PERFORM pg_temp.denied('q2 ne lit pas les compteurs d''appels en direct', $$SELECT count(*)::text FROM public.snap_trail_calls$$, 'permission denied|row-level security');
PERFORM pg_temp.denied('q2 ne vide pas son compteur altimétrie en direct', $$DELETE FROM public.trace_elevation_calls$$, 'permission denied|row-level security');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le compteur snap-trail de q1 est à 200, pas plus', format($$SELECT count(*)::text FROM public.snap_trail_calls WHERE user_id = %L$$, pg_temp.id('q1')), '200');
PERFORM pg_temp.eq('aucun appel du suspendu n''a été compté', format(
  $$SELECT ((SELECT count(*) FROM public.snap_trail_calls WHERE user_id = %L) + (SELECT count(*) FROM public.trace_elevation_calls WHERE user_id = %L))::text$$,
  pg_temp.id('sam'), pg_temp.id('sam')), '0');

-- ═════ 4. Lectures et envois ═════
-- Le rideau démo dépend de app_config.demo_mode : on le fixe à « off » pour cette section,
-- puis on rétablit la valeur d'origine (tout est annulé de toute façon).
PERFORM pg_temp.put('demo_mode_orig', (SELECT value FROM public.app_config WHERE name = 'demo_mode'));
UPDATE public.app_config SET value = 'false' WHERE name = 'demo_mode';

-- C : sortie terminée (hier) ; W : sortie publiée (dans 2 jours) ; P : sortie à présence (dans 1 h).
PERFORM pg_temp.cv_act('C', 'crea', interval '-1 day', 'completed', true);
PERFORM pg_temp.cv_part('C', 'alice', 'accepted', true);
PERFORM pg_temp.cv_part('C', 'bob', 'accepted', false);
PERFORM pg_temp.cv_part('C', 'sam', 'accepted', true);
PERFORM pg_temp.cv_part('C', 'demo1', 'accepted', true);
PERFORM pg_temp.cv_part('C', 'dan', 'pending');
PERFORM pg_temp.cv_act('W', 'crea', interval '2 days', 'published');
PERFORM pg_temp.cv_part('W', 'alice');
PERFORM pg_temp.cv_part('W', 'bob');
PERFORM pg_temp.cv_part('W', 'sam');
PERFORM pg_temp.cv_act('P', 'crea', interval '1 hour', 'published', true);
PERFORM pg_temp.cv_part('P', 'alice');
PERFORM pg_temp.cv_part('P', 'sam');
PERFORM pg_temp.cv_part('P', 'bob', 'invited', NULL, 'crea');
PERFORM pg_temp.put('conv_W', (SELECT id::text FROM public.conversations WHERE activity_id = pg_temp.id('W')));

-- get_activity_peer_review_state
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne lit pas l''état de relecture', format($$SELECT public.get_activity_peer_review_state(%L)::text$$, pg_temp.id('C')), 'permission denied|Operation not permitted');
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('un non-participant ne lit pas l''état de relecture', format($$SELECT public.get_activity_peer_review_state(%L)::text$$, pg_temp.id('C')), 'Operation not permitted');
PERFORM pg_temp.as_('dan');
PERFORM pg_temp.denied('un demandeur non accepté ne lit pas l''état de relecture', format($$SELECT public.get_activity_peer_review_state(%L)::text$$, pg_temp.id('C')), 'Operation not permitted');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('relecture : le créateur figure dans la liste', $$SELECT (pg_temp.cv_review('C', 'crea', 'user_id') <> 'absent')::text$$, 'true');
PERFORM pg_temp.eq('relecture : on ne se voit pas soi-même', $$SELECT pg_temp.cv_review('C', 'alice', 'user_id')$$, 'absent');
PERFORM pg_temp.eq('relecture : l''absence d''un co-participant n''est pas révélée', $$SELECT pg_temp.cv_review('C', 'bob', 'confirmed_present')$$, 'null');
PERFORM pg_temp.eq('relecture : un participant suspendu n''apparaît pas', $$SELECT pg_temp.cv_review('C', 'sam', 'user_id')$$, 'absent');
PERFORM pg_temp.eq('relecture : un compte démo n''apparaît pas hors mode démo', $$SELECT pg_temp.cv_review('C', 'demo1', 'user_id')$$, 'absent');
PERFORM pg_temp.eq('relecture : un demandeur non accepté n''apparaît pas', $$SELECT pg_temp.cv_review('C', 'dan', 'user_id')$$, 'absent');
-- COV-1 : get_activity_peer_review_state ne vérifie pas la suspension de l'appelant (seulement
-- auth.uid() + participation 'accepted') : un compte suspendu relit la liste des co-participants
-- (noms, avatars, niveaux déclarés, ses votes), alors que 00514 coupe toute lecture aux suspendus.
-- Note : la fonction ne vérifie pas non plus que la sortie est terminée ni qu'elle exige la présence
-- (sans fuite au-delà de la liste des participants, déjà visible d'un participant accepté).
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un participant suspendu ne lit pas l''état de relecture', format($$SELECT public.get_activity_peer_review_state(%L)::text$$, pg_temp.id('C')), 'Operation not permitted');

-- get_my_active_presence_activities
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('présence : alice reçoit la zone de sa sortie à présence', format(
  $$SELECT count(*)::text FROM public.get_my_active_presence_activities() WHERE activity_id = %L$$, pg_temp.id('P')), '1');
PERFORM pg_temp.eq('présence : alice ne reçoit que ses sorties', format(
  $$SELECT count(*)::text FROM public.get_my_active_presence_activities() a
    WHERE NOT EXISTS (SELECT 1 FROM public.participations p WHERE p.activity_id = a.activity_id AND p.user_id = %L AND p.status = 'accepted')$$, pg_temp.id('alice')), '0');
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.eq('présence : un étranger ne reçoit pas la zone', format(
  $$SELECT count(*)::text FROM public.get_my_active_presence_activities() WHERE activity_id = %L$$, pg_temp.id('P')), '0');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('présence : un invité (pas encore inscrit) ne reçoit pas la zone', format(
  $$SELECT count(*)::text FROM public.get_my_active_presence_activities() WHERE activity_id = %L$$, pg_temp.id('P')), '0');
PERFORM pg_temp.as_('crea');
PERFORM pg_temp.eq('présence : l''organisateur ne se valide pas lui-même', format(
  $$SELECT count(*)::text FROM public.get_my_active_presence_activities() WHERE activity_id = %L$$, pg_temp.id('P')), '0');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.eq('présence : un suspendu ne reçoit rien', $$SELECT count(*)::text FROM public.get_my_active_presence_activities()$$, '0');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('présence : anon refusé', $$SELECT count(*)::text FROM public.get_my_active_presence_activities()$$, 'permission denied|Operation not permitted');

-- get_my_invitations
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('invitations : bob voit son invitation', format(
  $$SELECT count(*)::text FROM public.get_my_invitations() WHERE activity_id = %L AND invited_by = %L$$, pg_temp.id('P'), pg_temp.id('crea')), '1');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('invitations : alice ne voit pas celle de bob', format(
  $$SELECT count(*)::text FROM public.get_my_invitations() WHERE activity_id = %L$$, pg_temp.id('P')), '0');
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.eq('invitations : un compte sans invitation ne voit rien', $$SELECT count(*)::text FROM public.get_my_invitations()$$, '0');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('invitations : anon refusé', $$SELECT count(*)::text FROM public.get_my_invitations()$$, 'permission denied|Operation not permitted');

-- get_user_award_aggregates
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('compteurs : sortie rejointe comptée pour alice', format($$SELECT public.get_user_award_aggregates(%L) ->> 'joined'$$, pg_temp.id('alice')), '1');
PERFORM pg_temp.eq('00521 : sortie organisée sans présence validée : pas comptée', format($$SELECT public.get_user_award_aggregates(%L) ->> 'created'$$, pg_temp.id('crea')), '0');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.participations SET confirmed_present = true WHERE activity_id = pg_temp.id('C') AND user_id = pg_temp.id('crea');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('compteurs : sortie organisée comptée pour crea (présence validée)', format($$SELECT public.get_user_award_aggregates(%L) ->> 'created'$$, pg_temp.id('crea')), '1');
PERFORM pg_temp.eq('compteurs : rien pour un compte suspendu', format($$SELECT public.get_user_award_aggregates(%L) ->> 'joined'$$, pg_temp.id('sam')), '0');
PERFORM pg_temp.eq('compteurs : rien pour un compte démo hors mode démo', format($$SELECT public.get_user_award_aggregates(%L) ->> 'joined'$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.eq('compteurs : une demande en attente ne compte pas', format($$SELECT public.get_user_award_aggregates(%L) ->> 'joined'$$, pg_temp.id('dan')), '0');
PERFORM pg_temp.as_('db');
UPDATE public.app_config SET value = 'true' WHERE name = 'demo_mode';
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('compteurs : mode démo actif, un compte ordinaire ne voit toujours rien du compte démo', format($$SELECT public.get_user_award_aggregates(%L) ->> 'joined'$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.eq('compteurs : mode démo actif, l''admin voit le compte démo', format($$SELECT public.get_user_award_aggregates(%L) ->> 'joined'$$, pg_temp.id('demo1')), '1');
PERFORM pg_temp.as_('db');
UPDATE public.app_config SET value = 'false' WHERE name = 'demo_mode';
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('compteurs : anon refusé', format($$SELECT public.get_user_award_aggregates(%L)::text$$, pg_temp.id('alice')), 'permission denied|Operation not permitted');

-- Mur de sortie : send_wall_message / get_wall_messages
PERFORM pg_temp.as_('crea');
PERFORM pg_temp.ok('mur : l''organisateur publie', format($$SELECT public.send_wall_message(%L, 'Bonjour à tous')::text$$, pg_temp.id('W')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.put('msg_bob', pg_temp.ok('mur : un participant publie', format($$SELECT public.send_wall_message(%L, 'Message de bob')::text$$, pg_temp.id('W'))));
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('mur : un non-membre ne publie pas', format($$SELECT public.send_wall_message(%L, 'intrus')::text$$, pg_temp.id('W')), 'Operation not permitted');
PERFORM pg_temp.denied('mur : sortie inexistante refusée', $$SELECT public.send_wall_message(gen_random_uuid(), 'x')::text$$, 'Operation not permitted');
PERFORM pg_temp.eq('mur : un non-membre ne lit rien', format($$SELECT count(*)::text FROM public.get_wall_messages(%L)$$, pg_temp.id('W')), '0');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('mur : un participant suspendu ne publie pas', format($$SELECT public.send_wall_message(%L, 'suspendu')::text$$, pg_temp.id('W')), 'Operation not permitted');
PERFORM pg_temp.eq('mur : un participant suspendu ne lit rien', format($$SELECT count(*)::text FROM public.get_wall_messages(%L)$$, pg_temp.id('W')), '0');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('mur : anon ne publie pas', format($$SELECT public.send_wall_message(%L, 'anon')::text$$, pg_temp.id('W')), 'permission denied|Operation not permitted');
PERFORM pg_temp.denied('mur : anon ne lit pas', format($$SELECT count(*)::text FROM public.get_wall_messages(%L)$$, pg_temp.id('W')), 'permission denied|Operation not permitted');
-- Message d'un auteur suspendu depuis (inséré en db) + alice bloque bob.
PERFORM pg_temp.as_('db');
INSERT INTO public.messages (conversation_id, sender_id, content) VALUES (pg_temp.id('conv_W'), pg_temp.id('sam'), 'message de sam avant suspension');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('alice'), pg_temp.id('bob'));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('mur : alice lit le message de l''organisateur', format(
  $$SELECT count(*)::text FROM public.get_wall_messages(%L) WHERE user_id = %L$$, pg_temp.id('W'), pg_temp.id('crea')), '1');
PERFORM pg_temp.eq('mur : l''auteur bloqué par alice lui est masqué', format(
  $$SELECT count(*)::text FROM public.get_wall_messages(%L) WHERE user_id = %L$$, pg_temp.id('W'), pg_temp.id('bob')), '0');
PERFORM pg_temp.eq('mur : l''auteur suspendu est masqué', format(
  $$SELECT count(*)::text FROM public.get_wall_messages(%L) WHERE user_id = %L$$, pg_temp.id('W'), pg_temp.id('sam')), '0');
PERFORM pg_temp.as_('crea');
PERFORM pg_temp.eq('mur : le blocage d''alice ne masque pas bob aux autres', format(
  $$SELECT count(*)::text FROM public.get_wall_messages(%L) WHERE user_id = %L$$, pg_temp.id('W'), pg_temp.id('bob')), '1');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('mur : le blocage est à sens unique, bob lit toujours le mur', format(
  $$SELECT count(*)::text FROM public.get_wall_messages(%L) WHERE user_id = %L$$, pg_temp.id('W'), pg_temp.id('crea')), '1');

-- Messages privés : send_private_message
PERFORM pg_temp.as_('db');
PERFORM pg_temp.cv_dm('dm_ad', 'alice', 'dan');
PERFORM pg_temp.cv_dm('dm_cd', 'crea', 'dan');
PERFORM pg_temp.cv_dm('dm_as', 'alice', 'sam');
PERFORM pg_temp.cv_dm('dm_pend', 'crea', 'mal', 'pending_request');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('DM : alice écrit à dan', format($$SELECT public.send_private_message(%L, 'Salut Dan')::text$$, pg_temp.id('dm_ad')));
PERFORM pg_temp.denied('DM : alice écrit à un compte suspendu, refusé', format($$SELECT public.send_private_message(%L, 'Salut Sam')::text$$, pg_temp.id('dm_as')), 'Operation not permitted');
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('DM : un tiers n''écrit pas dans le fil d''alice et dan', format($$SELECT public.send_private_message(%L, 'intrus')::text$$, pg_temp.id('dm_ad')), 'Operation not permitted');
PERFORM pg_temp.denied('DM : demande de contact non acceptée, pas d''envoi libre', format($$SELECT public.send_private_message(%L, 'relance')::text$$, pg_temp.id('dm_pend')), 'Operation not permitted');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('DM : un compte suspendu n''écrit pas', format($$SELECT public.send_private_message(%L, 'je suis suspendu')::text$$, pg_temp.id('dm_as')), 'Operation not permitted');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('DM : anon n''écrit pas', format($$SELECT public.send_private_message(%L, 'anon')::text$$, pg_temp.id('dm_ad')), 'permission denied|Operation not permitted');
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('dan'), pg_temp.id('crea'));
PERFORM pg_temp.as_('crea');
PERFORM pg_temp.denied('DM : bloqué par dan, crea ne lui écrit plus', format($$SELECT public.send_private_message(%L, 'tu m''entends ?')::text$$, pg_temp.id('dm_cd')), 'Operation not permitted');
PERFORM pg_temp.as_('dan');
PERFORM pg_temp.denied('DM : dan (qui bloque) n''écrit pas non plus à crea', format($$SELECT public.send_private_message(%L, 'x')::text$$, pg_temp.id('dm_cd')), 'Operation not permitted');

PERFORM pg_temp.as_('db');
UPDATE public.app_config SET value = pg_temp.get('demo_mode_orig') WHERE name = 'demo_mode';

-- ═════ 5. Tâches planifiées (appelées en tant que db) ═════
-- Aucune n'est appelable par un client.
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('client : purge des notifications non appelable', $$SELECT public.purge_old_notifications()::text$$, 'permission denied');
PERFORM pg_temp.denied('client : purge des fiches de réservation non appelable', $$SELECT public.purge_booking_participant_info()::text$$, 'permission denied');
PERFORM pg_temp.denied('client : purge des archives de contacts non appelable', $$SELECT public.purge_contact_removal_archive()::text$$, 'permission denied');
PERFORM pg_temp.denied('client : purge des tables de limitation non appelable', $$SELECT public.purge_throttle_tables()::text$$, 'permission denied');
PERFORM pg_temp.denied('client : expiration des demandes de place non appelable', $$SELECT public.expire_idle_seat_requests()::text$$, 'permission denied');
PERFORM pg_temp.denied('client : expiration des demandes de contact non appelable', $$SELECT public.expire_stale_contact_requests()::text$$, 'permission denied');

PERFORM pg_temp.as_('db');
-- Notifications.
PERFORM pg_temp.put('n_old_info', pg_temp.run($q$INSERT INTO public.notifications (user_id, type, title, body, created_at)
  VALUES (pg_temp.id('k1'), 'activity_cancelled', 't', 'b', now() - interval '8 days') RETURNING id$q$));
PERFORM pg_temp.put('n_old_req', pg_temp.run($q$INSERT INTO public.notifications (user_id, type, title, body, created_at)
  VALUES (pg_temp.id('k1'), 'join_request', 't', 'b', now() - interval '8 days') RETURNING id$q$));
PERFORM pg_temp.put('n_old_req_read', pg_temp.run($q$INSERT INTO public.notifications (user_id, type, title, body, created_at, read_at)
  VALUES (pg_temp.id('k1'), 'join_request', 't', 'b', now() - interval '8 days', now() - interval '7 days') RETURNING id$q$));
PERFORM pg_temp.put('n_recent', pg_temp.run($q$INSERT INTO public.notifications (user_id, type, title, body, created_at, read_at)
  VALUES (pg_temp.id('k1'), 'activity_cancelled', 't', 'b', now() - interval '1 day', now()) RETURNING id$q$));
PERFORM pg_temp.ok('purge des notifications', $$SELECT public.purge_old_notifications()::text$$);
PERFORM pg_temp.eq('notification d''information de plus de 7 jours supprimée', format($$SELECT count(*)::text FROM public.notifications WHERE id = %L$$, pg_temp.id('n_old_info')), '0');
PERFORM pg_temp.eq('demande à traiter non lue gardée même ancienne', format($$SELECT count(*)::text FROM public.notifications WHERE id = %L$$, pg_temp.id('n_old_req')), '1');
PERFORM pg_temp.eq('demande à traiter déjà lue et ancienne supprimée', format($$SELECT count(*)::text FROM public.notifications WHERE id = %L$$, pg_temp.id('n_old_req_read')), '0');
PERFORM pg_temp.eq('notification récente gardée', format($$SELECT count(*)::text FROM public.notifications WHERE id = %L$$, pg_temp.id('n_recent')), '1');

-- Réservations : fiche participant, téléphone saisi par le pro, message du client.
PERFORM pg_temp.put('bk_old', pg_temp.run($q$INSERT INTO public.bookings (offering_id, pro_id, client_id, day, period, party_size, message, status, participant_info)
  VALUES (pg_temp.id('off'), pg_temp.id('pro'), pg_temp.id('k1'), current_date - 31, 'am', 1, 'Bonjour', 'accepted', '[{"shoe_size":"42"}]'::jsonb) RETURNING id$q$));
PERFORM pg_temp.put('bk_new', pg_temp.run($q$INSERT INTO public.bookings (offering_id, pro_id, client_id, day, period, party_size, message, status, participant_info)
  VALUES (pg_temp.id('off'), pg_temp.id('pro'), pg_temp.id('k2'), current_date - 29, 'am', 1, 'Bonjour', 'accepted', '[{"shoe_size":"40"}]'::jsonb) RETURNING id$q$));
PERFORM pg_temp.put('bk_man_old', pg_temp.run($q$INSERT INTO public.bookings (offering_id, pro_id, client_id, manual_name, manual_phone, day, period, party_size, status)
  VALUES (pg_temp.id('off'), pg_temp.id('pro'), NULL, 'Client Manuel', '0600000000', current_date - 31, 'pm', 2, 'accepted') RETURNING id$q$));
PERFORM pg_temp.put('bk_man_new', pg_temp.run($q$INSERT INTO public.bookings (offering_id, pro_id, client_id, manual_name, manual_phone, day, period, party_size, status)
  VALUES (pg_temp.id('off'), pg_temp.id('pro'), NULL, 'Client Manuel', '0600000001', current_date - 29, 'pm', 2, 'accepted') RETURNING id$q$));
PERFORM pg_temp.ok('purge des données de réservation', $$SELECT public.purge_booking_participant_info()::text$$);
PERFORM pg_temp.eq('J+31 : fiche participant et message effacés', format(
  $$SELECT (participant_info IS NULL AND message IS NULL)::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_old')), 'true');
PERFORM pg_temp.eq('J+31 : téléphone saisi par le pro effacé', format(
  $$SELECT (manual_phone IS NULL)::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_man_old')), 'true');
PERFORM pg_temp.eq('J+29 : fiche participant et message gardés', format(
  $$SELECT (participant_info IS NOT NULL AND message = 'Bonjour')::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_new')), 'true');
PERFORM pg_temp.eq('J+29 : téléphone gardé', format(
  $$SELECT manual_phone FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_man_new')), '0600000001');
PERFORM pg_temp.eq('la purge garde la réservation elle-même', format(
  $$SELECT count(*)::text FROM public.bookings WHERE id IN (%L, %L)$$, pg_temp.id('bk_old'), pg_temp.id('bk_man_old')), '2');

-- Archive des contacts retirés (90 jours).
PERFORM pg_temp.put('arc_old', pg_temp.run($q$INSERT INTO public.contact_removal_archive (conversation_id, user_1, user_2, removed_by, removed_at)
  VALUES (gen_random_uuid(), pg_temp.id('k1'), pg_temp.id('k2'), pg_temp.id('k1'), now() - interval '91 days') RETURNING id$q$));
PERFORM pg_temp.put('arc_new', pg_temp.run($q$INSERT INTO public.contact_removal_archive (conversation_id, user_1, user_2, removed_by, removed_at)
  VALUES (gen_random_uuid(), pg_temp.id('k1'), pg_temp.id('k3'), pg_temp.id('k1'), now() - interval '89 days') RETURNING id$q$));
PERFORM pg_temp.ok('purge des archives de contacts', $$SELECT public.purge_contact_removal_archive()::text$$);
PERFORM pg_temp.eq('archive de plus de 90 jours supprimée', format($$SELECT count(*)::text FROM public.contact_removal_archive WHERE id = %L$$, pg_temp.id('arc_old')), '0');
PERFORM pg_temp.eq('archive récente gardée', format($$SELECT count(*)::text FROM public.contact_removal_archive WHERE id = %L$$, pg_temp.id('arc_new')), '1');

-- Tables de limitation (map_broadcasts > 1 j, rate_events > 2 j).
INSERT INTO public.map_broadcasts (activity_id, at) VALUES (pg_temp.id('W'), now() - interval '25 hours')
  ON CONFLICT (activity_id) DO UPDATE SET at = EXCLUDED.at;
INSERT INTO public.map_broadcasts (activity_id, at) VALUES (pg_temp.id('P'), now() - interval '23 hours')
  ON CONFLICT (activity_id) DO UPDATE SET at = EXCLUDED.at;
INSERT INTO public.rate_events (user_id, kind, at) VALUES (pg_temp.id('k1'), 'test_cov_old', now() - interval '49 hours');
INSERT INTO public.rate_events (user_id, kind, at) VALUES (pg_temp.id('k1'), 'test_cov_new', now() - interval '47 hours');
PERFORM pg_temp.ok('purge des tables de limitation', $$SELECT public.purge_throttle_tables()::text$$);
PERFORM pg_temp.eq('diffusion carte de plus d''un jour supprimée', format($$SELECT count(*)::text FROM public.map_broadcasts WHERE activity_id = %L$$, pg_temp.id('W')), '0');
PERFORM pg_temp.eq('diffusion carte récente gardée', format($$SELECT count(*)::text FROM public.map_broadcasts WHERE activity_id = %L$$, pg_temp.id('P')), '1');
PERFORM pg_temp.eq('événement de limitation de plus de 2 jours supprimé', format($$SELECT count(*)::text FROM public.rate_events WHERE user_id = %L AND kind = 'test_cov_old'$$, pg_temp.id('k1')), '0');
PERFORM pg_temp.eq('événement de limitation récent gardé', format($$SELECT count(*)::text FROM public.rate_events WHERE user_id = %L AND kind = 'test_cov_new'$$, pg_temp.id('k1')), '1');

-- Demandes de place sans réponse (48 h, sorties vivantes seulement).
PERFORM pg_temp.cv_act('X', 'crea', interval '3 days', 'cancelled');
PERFORM pg_temp.put('sr_old', pg_temp.run($q$INSERT INTO public.seat_requests (activity_id, requester_id, driver_id, status, created_at)
  VALUES (pg_temp.id('W'), pg_temp.id('bob'), pg_temp.id('alice'), 'pending', now() - interval '49 hours') RETURNING id$q$));
PERFORM pg_temp.put('sr_new', pg_temp.run($q$INSERT INTO public.seat_requests (activity_id, requester_id, driver_id, status, created_at)
  VALUES (pg_temp.id('W'), pg_temp.id('crea'), pg_temp.id('alice'), 'pending', now() - interval '47 hours') RETURNING id$q$));
PERFORM pg_temp.put('sr_dead', pg_temp.run($q$INSERT INTO public.seat_requests (activity_id, requester_id, driver_id, status, created_at)
  VALUES (pg_temp.id('X'), pg_temp.id('bob'), pg_temp.id('crea'), 'pending', now() - interval '49 hours') RETURNING id$q$));
PERFORM pg_temp.ok('expiration des demandes de place', $$SELECT public.expire_idle_seat_requests()::text$$);
PERFORM pg_temp.eq('demande de place de plus de 48 h expirée', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.id('sr_old')), 'expired');
PERFORM pg_temp.eq('demande de place récente toujours en attente', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.id('sr_new')), 'pending');
PERFORM pg_temp.eq('demande sur sortie annulée laissée au déclencheur de fin de sortie', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.id('sr_dead')), 'pending');
PERFORM pg_temp.eq('le demandeur est prévenu de l''expiration', format(
  $$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'seat_request_expired' AND data ->> 'seat_request_id' = %L$$,
  pg_temp.id('bob'), pg_temp.get('sr_old')), '1');
PERFORM pg_temp.eq('pas de notification pour la demande récente', format(
  $$SELECT count(*)::text FROM public.notifications WHERE type = 'seat_request_expired' AND data ->> 'seat_request_id' = %L$$, pg_temp.get('sr_new')), '0');

-- Demandes de contact (30 jours, en attente ou refusées ; les fils actifs ne bougent pas).
PERFORM pg_temp.cv_dm('cr_old', 'k2', 'k3', 'pending_request', interval '31 days');
PERFORM pg_temp.cv_dm('cr_declined', 'k2', 'k4', 'declined', interval '31 days');
PERFORM pg_temp.cv_dm('cr_new', 'k2', 'k5', 'pending_request', interval '29 days');
PERFORM pg_temp.cv_dm('cr_active', 'k3', 'k4', 'active', interval '60 days');
PERFORM pg_temp.ok('expiration des demandes de contact', $$SELECT public.expire_stale_contact_requests()::text$$);
PERFORM pg_temp.eq('demande de contact de plus de 30 jours supprimée', format($$SELECT count(*)::text FROM public.conversations WHERE id = %L$$, pg_temp.id('cr_old')), '0');
PERFORM pg_temp.eq('demande refusée de plus de 30 jours supprimée', format($$SELECT count(*)::text FROM public.conversations WHERE id = %L$$, pg_temp.id('cr_declined')), '0');
PERFORM pg_temp.eq('demande de contact récente gardée', format($$SELECT status FROM public.conversations WHERE id = %L$$, pg_temp.id('cr_new')), 'pending_request');
PERFORM pg_temp.eq('fil actif ancien gardé', format($$SELECT status FROM public.conversations WHERE id = %L$$, pg_temp.id('cr_active')), 'active');
