-- Domaine 8 — garde-fous de non-régression (audit de la suite, 2026-10-22).
-- Chaque bloc vise une règle des migrations 00467-00522 qu'aucun autre fichier ne
-- protégeait : si la condition était retirée de la fonction, au moins une vérification
-- ici échouerait. Motifs d'erreur précis (code junto.* exact ou refus générique exact),
-- et pour chaque refus, le chemin légitime voisin est vérifié aussi.
-- Fixtures en plein Pacifique (aucune alerte réelle), sorties créées en `db`.

-- ───── Utilitaires locaux ─────
EXECUTE 'CREATE TEMP SEQUENCE gf_slot';
EXECUTE 'GRANT USAGE ON SEQUENCE pg_temp.gf_slot TO PUBLIC';

-- Sortie créée en db (créateur inscrit « accepted »), créneau propre si p_start est NULL.
EXECUTE $p$CREATE FUNCTION pg_temp.gf_act(p_label text, p_creator text, p_start interval DEFAULT NULL,
    p_status text DEFAULT 'published', p_vis text DEFAULT 'public', p_rp boolean DEFAULT false,
    p_cp boolean DEFAULT NULL) RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting,
      starts_at, duration, visibility, status, requires_presence)
    VALUES (pg_temp.id(p_creator), (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie garde-fou ' || p_label,
      'Tous niveaux', 10, ST_SetSRID(ST_MakePoint(-140.5, -48.5), 4326)::geography,
      now() + coalesce(p_start, interval '100 days' + nextval('pg_temp.gf_slot') * interval '5 hours'),
      interval '3 hours', p_vis, p_status, p_rp)
    RETURNING id INTO v;
    INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, created_at)
    VALUES (v, pg_temp.id(p_creator), 'accepted', p_cp, now() - interval '3 days');
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;

-- Participation posée en db.
EXECUTE $p$CREATE FUNCTION pg_temp.gf_part(p_act text, p_user text, p_status text DEFAULT 'accepted',
    p_cp boolean DEFAULT NULL, p_by text DEFAULT NULL) RETURNS void
  LANGUAGE sql AS $b$
  INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, invited_by, created_at)
  VALUES (pg_temp.id(p_act), pg_temp.id(p_user), p_status, p_cp, pg_temp.id(p_by), now() - interval '2 days') $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.gf_pid(p_act text, p_user text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT id::text FROM public.participations WHERE activity_id = pg_temp.id(p_act) AND user_id = pg_temp.id(p_user) $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.gf_sr(p_act text, p_req text, p_drv text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT id::text FROM public.seat_requests WHERE activity_id = pg_temp.id(p_act)
    AND requester_id = pg_temp.id(p_req) AND driver_id = pg_temp.id(p_drv) ORDER BY created_at DESC LIMIT 1 $b$$p$;

-- Fil DM actif (db) entre deux comptes.
EXECUTE $p$CREATE FUNCTION pg_temp.gf_connect(a text, b text) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
    VALUES ('dm', LEAST(pg_temp.id(a), pg_temp.id(b)), GREATEST(pg_temp.id(a), pg_temp.id(b)), pg_temp.id(a),
            'active', 'profile', now(), now())
    RETURNING id INTO v;
    RETURN v;
  END $b$$p$;

-- Suspension / levée en db.
EXECUTE $p$CREATE FUNCTION pg_temp.gf_suspend(p_user text, p_on boolean DEFAULT true) RETURNS void
  LANGUAGE plpgsql AS $b$
  BEGIN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE public.users SET suspended_at = CASE WHEN p_on THEN now() END WHERE id = pg_temp.id(p_user);
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END $b$$p$;

-- Appelle p_sql jusqu'à p_n fois avec le rôle courant ; renvoie « nb de succès:première erreur ».
EXECUTE $p$CREATE FUNCTION pg_temp.gf_loop(p_sql text, p_n int) RETURNS text
  LANGUAGE plpgsql AS $b$
  BEGIN
    FOR i IN 1..p_n LOOP
      BEGIN
        EXECUTE p_sql;
      EXCEPTION WHEN OTHERS THEN RETURN (i - 1) || ':' || SQLERRM; END;
    END LOOP;
    RETURN p_n || ':none';
  END $b$$p$;

-- Événements de limitation posés en db (rate_events), datés de maintenant.
EXECUTE $p$CREATE FUNCTION pg_temp.gf_rate(p_user text, p_kind text, p_n int) RETURNS void
  LANGUAGE sql AS $b$
  INSERT INTO public.rate_events (user_id, kind, at) SELECT pg_temp.id(p_user), p_kind, now() FROM generate_series(1, p_n) $b$$p$;

-- Pro approuvé + une offre (db).
EXECUTE $p$CREATE FUNCTION pg_temp.gf_pro(p_user text, p_off_label text) RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.pro_profiles (user_id, display_name, primary_lng, primary_lat, primary_location, primary_location_name, status)
    VALUES (pg_temp.id(p_user), 'Pro ' || p_user, -140.5, -48.5, ST_SetSRID(ST_MakePoint(-140.5, -48.5), 4326)::geography, 'Océan', 'approved');
    INSERT INTO public.pro_offerings (pro_id, sport_id, title, description, level, location, location_name, max_participants, price_eur, price_unit)
    VALUES (pg_temp.id(p_user), (SELECT id FROM public.sports WHERE key = 'hiking'), 'Offre garde-fou ' || p_user, 'Desc', 'Tous niveaux',
      ST_SetSRID(ST_MakePoint(-140.5, -48.5), 4326)::geography, 'Océan', 8, 50, 'person')
    RETURNING id INTO v;
    PERFORM pg_temp.put(p_off_label, v::text);
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE public.users SET tier = 'pro' WHERE id = pg_temp.id(p_user);
    PERFORM set_config('junto.bypass_lock', 'false', true);
    RETURN v;
  END $b$$p$;

-- Dispo posée en db.
EXECUTE $p$CREATE FUNCTION pg_temp.gf_dispo(p_user text, p_lng float8, p_lat float8, p_radius int,
    p_ws timestamptz, p_we timestamptz) RETURNS void
  LANGUAGE sql SET search_path = public, extensions AS $b$
  INSERT INTO public.discovery_availabilities (user_id, sport_keys, base, base_label, radius_km, transport_modes,
    window_start, window_end, is_active, is_demo)
  VALUES (pg_temp.id(p_user), ARRAY['hiking'], ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, 'Océan', p_radius,
    ARRAY['car'], p_ws, p_we, true, false) $b$$p$;

PERFORM pg_temp.as_('db');
PERFORM set_config('junto.skip_message_push', 'false', true);

-- ═════════════════════════════════════════════════════════════════════════════
-- A. Sorties
-- ═════════════════════════════════════════════════════════════════════════════

-- A1 — Durée : modifiable sans participant (bornée à 7 jours), figée avec des
-- participants (00516 L1), figée dès le départ (00467 M1), refusée en cours (00496 BR-7).
PERFORM pg_temp.user('d_org', 'tos'); PERFORM pg_temp.user('d_org2', 'tos'); PERFORM pg_temp.user('d_org3', 'tos'); PERFORM pg_temp.user('d_p', 'tos');
PERFORM pg_temp.gf_act('d_act', 'd_org');
PERFORM pg_temp.gf_act('d_run', 'd_org2', interval '-10 minutes');                   -- publiée, déjà commencée
PERFORM pg_temp.gf_act('d_ip', 'd_org3', interval '-20 minutes', 'in_progress');
PERFORM pg_temp.as_('d_org');
PERFORM pg_temp.ok('A1 durée : sans participant, l''organisateur change la durée', format($$SELECT public.update_activity(%L, p_duration := '4 hours')::text$$, pg_temp.id('d_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A1 durée : changement appliqué sans participant', format($$SELECT duration::text FROM public.activities WHERE id = %L$$, pg_temp.id('d_act')), '04:00:00');
PERFORM pg_temp.as_('d_org');
PERFORM pg_temp.denied('A1 durée : plus de 7 jours refusée par la table', format($$SELECT public.update_activity(%L, p_duration := '8 days')::text$$, pg_temp.id('d_act')), 'activities_duration_check');
PERFORM pg_temp.as_('d_p');
PERFORM pg_temp.eq('A1 durée : un participant rejoint', format($$SELECT public.join_activity(%L)$$, pg_temp.id('d_act')), 'accepted');
PERFORM pg_temp.as_('d_org');
PERFORM pg_temp.ok('A1 durée : l''organisateur tente de rallonger avec un participant', format($$SELECT public.update_activity(%L, p_duration := '6 hours')::text$$, pg_temp.id('d_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A1 durée figée dès qu''il y a un participant (00516 L1)', format($$SELECT duration::text FROM public.activities WHERE id = %L$$, pg_temp.id('d_act')), '04:00:00');
PERFORM pg_temp.as_('d_org2');
PERFORM pg_temp.ok('A1 durée : modification d''une sortie publiée déjà commencée', format($$SELECT public.update_activity(%L, p_duration := '5 hours')::text$$, pg_temp.id('d_run')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A1 durée figée dès le départ, même sans participant (00467 M1)', format($$SELECT duration::text FROM public.activities WHERE id = %L$$, pg_temp.id('d_run')), '03:00:00');
PERFORM pg_temp.as_('d_org3');
PERFORM pg_temp.denied('A1 durée d''une sortie en cours refusée avec un code (00496 BR-7)', format($$SELECT public.update_activity(%L, p_duration := '5 hours')::text$$, pg_temp.id('d_ip')), 'junto\.activity_locked');

-- A2 — Motif d'annulation borné à 300 caractères (00474 F9).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.gf_act('c_act', 'd_org');
PERFORM pg_temp.as_('d_org');
PERFORM pg_temp.ok('A2 annulation avec un motif de 1000 caractères', format($$SELECT public.cancel_activity(%L, %L)::text$$, pg_temp.id('c_act'), repeat('m', 1000)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A2 le motif est coupé à 300 caractères (00474 F9)', format($$SELECT char_length(cancelled_reason)::text FROM public.activities WHERE id = %L$$, pg_temp.id('c_act')), '300');

-- A3 — Les demandeurs en attente sont prévenus d'un changement (00516 AC-7).
PERFORM pg_temp.user('n_org', 'tos'); PERFORM pg_temp.user('n_req', 'tos');
PERFORM pg_temp.gf_act('n_act', 'n_org', NULL, 'published', 'approval');
-- activity_updated est désactivé par défaut dans les préférences : on l'active pour l'observer.
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET notification_preferences = notification_preferences || '{"activity_updated": true}'::jsonb WHERE id IN (pg_temp.id('n_req'));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('n_req');
PERFORM pg_temp.eq('A3 la demande part en attente', format($$SELECT public.join_activity(%L)$$, pg_temp.id('n_act')), 'pending');
PERFORM pg_temp.as_('n_org');
PERFORM pg_temp.ok('A3 l''organisateur change le titre', format($$SELECT public.update_activity(%L, 'Titre changé garde-fou')::text$$, pg_temp.id('n_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A3 le demandeur en attente est prévenu (00516 AC-7)', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'activity_updated' AND data->>'activity_id' = %L$$, pg_temp.id('n_req'), pg_temp.get('n_act')), '1');

-- A4 — Sortie retirée par la modération : ni acceptation, ni refus, ni annulation,
-- ni liste de participants (00516 L3).
PERFORM pg_temp.user('l_org', 'tos'); PERFORM pg_temp.user('l_r1', 'tos'); PERFORM pg_temp.user('l_r2', 'tos');
PERFORM pg_temp.gf_act('l_act', 'l_org', NULL, 'published', 'approval');
PERFORM pg_temp.as_('l_r1'); PERFORM pg_temp.eq('A4 demande 1 en attente', format($$SELECT public.join_activity(%L)$$, pg_temp.id('l_act')), 'pending');
PERFORM pg_temp.as_('l_r2'); PERFORM pg_temp.eq('A4 demande 2 en attente', format($$SELECT public.join_activity(%L)$$, pg_temp.id('l_act')), 'pending');
PERFORM pg_temp.as_('l_org');
PERFORM pg_temp.eq('A4 avant retrait, l''organisateur liste ses participants', format($$SELECT (count(*) > 0)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('l_act')), 'true');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET deleted_at = now() WHERE id = pg_temp.id('l_act');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('l_org');
PERFORM pg_temp.denied('A4 sortie retirée : pas d''acceptation (00516 L3)', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.gf_pid('l_act', 'l_r1')), 'junto\.activity_locked');
PERFORM pg_temp.denied('A4 sortie retirée : pas de refus (00516 L3)', format($$SELECT public.refuse_participation(%L)::text$$, pg_temp.gf_pid('l_act', 'l_r2')), '^Operation not permitted$');
PERFORM pg_temp.denied('A4 sortie retirée : pas d''annulation (00516 L3)', format($$SELECT public.cancel_activity(%L, 'raison valable')::text$$, pg_temp.id('l_act')), '^Operation not permitted$');
PERFORM pg_temp.eq('A4 sortie retirée : plus de liste de participants (00516 L3)', format($$SELECT count(*)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('l_act')), '0');

-- A5 — Pas d'acceptation d'un demandeur suspendu entre-temps (00520 authz 4).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s_org', 'tos'); PERFORM pg_temp.user('s_r1', 'tos'); PERFORM pg_temp.user('s_r2', 'tos');
PERFORM pg_temp.gf_act('s_act', 's_org', NULL, 'published', 'approval');
PERFORM pg_temp.as_('s_r1'); PERFORM pg_temp.eq('A5 demande 1', format($$SELECT public.join_activity(%L)$$, pg_temp.id('s_act')), 'pending');
PERFORM pg_temp.as_('s_r2'); PERFORM pg_temp.eq('A5 demande 2', format($$SELECT public.join_activity(%L)$$, pg_temp.id('s_act')), 'pending');
PERFORM pg_temp.as_('db'); PERFORM pg_temp.gf_suspend('s_r1');
PERFORM pg_temp.as_('s_org');
PERFORM pg_temp.denied('A5 un demandeur suspendu n''est pas accepté (00520)', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.gf_pid('s_act', 's_r1')), '^Operation not permitted$');
PERFORM pg_temp.ok('A5 un demandeur non suspendu est accepté', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.gf_pid('s_act', 's_r2')));

-- A6 — Lien d'invitation : jamais pour une personne retirée ou bloquée par
-- l'organisateur, ni pour la sortie d'un organisateur suspendu (00520 authz 1).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('i_org', 'tos'); PERFORM pg_temp.user('i_ok', 'tos'); PERFORM pg_temp.user('i_blk', 'tos');
PERFORM pg_temp.user('i_rm', 'tos'); PERFORM pg_temp.user('i_late', 'tos');
PERFORM pg_temp.gf_act('i_act', 'i_org', NULL, 'published', 'private_link');
PERFORM pg_temp.gf_part('i_act', 'i_rm', 'removed');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('i_org'), pg_temp.id('i_blk'));
PERFORM pg_temp.put('i_tok', (SELECT invite_token::text FROM public.activities WHERE id = pg_temp.id('i_act')));
PERFORM pg_temp.as_('i_ok');
PERFORM pg_temp.eq('A6 le lien ouvre la sortie à un invité ordinaire', format($$SELECT count(*)::text FROM public.get_activity_by_invite_token(%L::uuid)$$, pg_temp.get('i_tok')), '1');
PERFORM pg_temp.as_('i_blk');
PERFORM pg_temp.eq('A6 le lien n''ouvre rien à une personne bloquée par l''organisateur', format($$SELECT count(*)::text FROM public.get_activity_by_invite_token(%L::uuid)$$, pg_temp.get('i_tok')), '0');
PERFORM pg_temp.as_('i_rm');
PERFORM pg_temp.eq('A6 le lien n''ouvre rien à une personne retirée', format($$SELECT count(*)::text FROM public.get_activity_by_invite_token(%L::uuid)$$, pg_temp.get('i_tok')), '0');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A6 aucun droit d''accès enregistré pour la personne bloquée ni la retirée',
  format($$SELECT count(*)::text FROM public.invite_grants WHERE activity_id = %L AND user_id IN (%L, %L)$$, pg_temp.id('i_act'), pg_temp.id('i_blk'), pg_temp.id('i_rm')), '0');
PERFORM pg_temp.gf_suspend('i_org');
PERFORM pg_temp.as_('i_late');
PERFORM pg_temp.eq('A6 le lien n''ouvre plus la sortie d''un organisateur suspendu', format($$SELECT count(*)::text FROM public.get_activity_by_invite_token(%L::uuid)$$, pg_temp.get('i_tok')), '0');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A6 ni droit d''accès enregistré', format($$SELECT count(*)::text FROM public.invite_grants WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('i_act'), pg_temp.id('i_late')), '0');

-- A7 — Accès à une sortie privée (00489) : jamais pour une personne retirée après
-- avoir ouvert le lien ; retour possible depuis l'historique (désistée) ; un partage
-- dans un groupe n'ouvre pas l'accès (seulement en conversation directe).
PERFORM pg_temp.user('pa_org', 'tos'); PERFORM pg_temp.user('pa_rm', 'tos'); PERFORM pg_temp.user('pa_ok', 'tos');
PERFORM pg_temp.user('pa_w', 'tos'); PERFORM pg_temp.user('pa_g1', 'tos'); PERFORM pg_temp.user('pa_g2', 'tos');
PERFORM pg_temp.gf_act('pa_act', 'pa_org', NULL, 'published', 'private_link');
PERFORM pg_temp.put('pa_tok', (SELECT invite_token::text FROM public.activities WHERE id = pg_temp.id('pa_act')));
PERFORM pg_temp.as_('pa_rm');
PERFORM pg_temp.eq('A7 pa_rm ouvre le lien', format($$SELECT count(*)::text FROM public.get_activity_by_invite_token(%L::uuid)$$, pg_temp.get('pa_tok')), '1');
PERFORM pg_temp.as_('pa_ok');
PERFORM pg_temp.eq('A7 pa_ok ouvre le lien', format($$SELECT count(*)::text FROM public.get_activity_by_invite_token(%L::uuid)$$, pg_temp.get('pa_tok')), '1');
PERFORM pg_temp.eq('A7 lien ouvert : le détail s''affiche', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('pa_act')), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.gf_part('pa_act', 'pa_rm', 'removed');
PERFORM pg_temp.gf_part('pa_act', 'pa_w', 'withdrawn');
PERFORM pg_temp.as_('pa_rm');
PERFORM pg_temp.eq('A7 retirée par l''organisatrice : le détail se ferme malgré le lien ouvert (00489)', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('pa_act')), '0');
PERFORM pg_temp.as_('pa_w');
PERFORM pg_temp.eq('A7 désistée : la sortie se rouvre depuis l''historique, sans lien (00489)', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('pa_act')), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.gf_connect('pa_org', 'pa_g1'); PERFORM pg_temp.gf_connect('pa_org', 'pa_g2');
PERFORM pg_temp.as_('pa_org');
PERFORM pg_temp.put('pa_grp', pg_temp.ok('A7 l''organisatrice crée un groupe', format($$SELECT public.create_group('Groupe garde-fou', NULL, ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('pa_g1'), pg_temp.id('pa_g2'))));
PERFORM pg_temp.ok('A7 elle partage sa sortie privée dans le groupe', format($$SELECT public.share_activity_message(%L, %L)::text$$, pg_temp.id('pa_grp'), pg_temp.id('pa_act')));
PERFORM pg_temp.as_('pa_g1');
PERFORM pg_temp.eq('A7 un partage dans un groupe n''ouvre pas la sortie privée (00489)', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('pa_act')), '0');

-- A8 — Blocage dans une même sortie (00522 F1, F2, F14).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('b_org', 'tos'); PERFORM pg_temp.user('b_m', 'tos'); PERFORM pg_temp.user('b_r', 'tos');
PERFORM pg_temp.user('b_r2', 'tos'); PERFORM pg_temp.user('b_r3', 'tos'); PERFORM pg_temp.user('b_x', 'tos'); PERFORM pg_temp.user('b_y', 'tos');
PERFORM pg_temp.gf_act('b_act', 'b_org', NULL, 'published', 'approval');
PERFORM pg_temp.as_('b_m'); PERFORM pg_temp.eq('A8 b_m demande', format($$SELECT public.join_activity(%L)$$, pg_temp.id('b_act')), 'pending');
PERFORM pg_temp.as_('b_r'); PERFORM pg_temp.eq('A8 b_r demande', format($$SELECT public.join_activity(%L)$$, pg_temp.id('b_act')), 'pending');
PERFORM pg_temp.ok('A8 b_r bloque b_m (encore en attente)', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('b_r'), pg_temp.id('b_m')));
PERFORM pg_temp.as_('b_org');
PERFORM pg_temp.ok('A8 l''organisateur accepte b_m', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.gf_pid('b_act', 'b_m')));
PERFORM pg_temp.denied('A8 accepter b_r, qui bloque un membre : refus générique pour l''organisateur (00522 F1)',
  format($$SELECT public.accept_participation(%L)::text$$, pg_temp.gf_pid('b_act', 'b_r')), '^Operation not permitted$');
PERFORM pg_temp.as_('b_r2'); PERFORM pg_temp.eq('A8 b_r2 demande', format($$SELECT public.join_activity(%L)$$, pg_temp.id('b_act')), 'pending');
PERFORM pg_temp.as_('b_r3'); PERFORM pg_temp.eq('A8 b_r3 demande', format($$SELECT public.join_activity(%L)$$, pg_temp.id('b_act')), 'pending');
PERFORM pg_temp.as_('b_m');
PERFORM pg_temp.ok('A8 le membre accepté bloque b_r2', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('b_m'), pg_temp.id('b_r2')));
PERFORM pg_temp.as_('b_r3');
PERFORM pg_temp.ok('A8 b_r3 bloque le membre accepté', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('b_r3'), pg_temp.id('b_m')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A8 demande impossible retirée : bloquée par un membre (00522 F2)', format($$SELECT status FROM public.participations WHERE id = %L$$, pg_temp.gf_pid('b_act', 'b_r2')), 'withdrawn');
PERFORM pg_temp.eq('A8 demande impossible retirée : elle bloque un membre (00522 F2)', format($$SELECT status FROM public.participations WHERE id = %L$$, pg_temp.gf_pid('b_act', 'b_r3')), 'withdrawn');
PERFORM pg_temp.gf_connect('b_org', 'b_x'); PERFORM pg_temp.gf_connect('b_org', 'b_y');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('b_m'), pg_temp.id('b_x'));
PERFORM pg_temp.as_('b_org');
PERFORM pg_temp.ok('A8 l''organisateur invite b_x (bloqué par un membre) et b_y', format($$SELECT public.send_activity_invitations(%L, ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('b_act'), pg_temp.id('b_x'), pg_temp.id('b_y')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A8 pas d''invitation impossible à accepter (00522 F14)', format($$SELECT count(*)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('b_act'), pg_temp.id('b_x')), '0');
PERFORM pg_temp.eq('A8 l''autre contact est bien invité', format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('b_act'), pg_temp.id('b_y')), 'invited');

-- A9 — Accepter une invitation : pas chez un organisateur suspendu (00496 AC-11).
PERFORM pg_temp.user('ai_org', 'tos'); PERFORM pg_temp.user('ai_org2', 'tos'); PERFORM pg_temp.user('ai_g', 'tos');
PERFORM pg_temp.gf_act('ai_act', 'ai_org'); PERFORM pg_temp.gf_act('ai_act2', 'ai_org2');
PERFORM pg_temp.gf_part('ai_act', 'ai_g', 'invited', NULL, 'ai_org');
PERFORM pg_temp.gf_part('ai_act2', 'ai_g', 'invited', NULL, 'ai_org2');
PERFORM pg_temp.gf_suspend('ai_org');
PERFORM pg_temp.as_('ai_g');
PERFORM pg_temp.denied('A9 pas d''acceptation d''invitation chez un organisateur suspendu (00496)', format($$SELECT public.accept_activity_invitation(%L)::text$$, pg_temp.id('ai_act')), '^Operation not permitted$');
PERFORM pg_temp.ok('A9 l''invitation d''un organisateur actif s''accepte', format($$SELECT public.accept_activity_invitation(%L)::text$$, pg_temp.id('ai_act2')));

-- A10 — Âge + CGU exigés au niveau des données sur les tables d'action, pas seulement
-- activities (00494 / 00496 BR-4).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('nb', '');      -- ni âge ni CGU
PERFORM pg_temp.user('nb_peer', 'tos');
PERFORM pg_temp.gf_act('nb_act', 'nb_peer');
PERFORM pg_temp.put('nb_conv', pg_temp.gf_connect('nb_peer', 'nb')::text);
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.conversations SET status = 'pending_request', request_sender_id = pg_temp.id('nb_peer'), request_message = 'Salut', request_expires_at = now() + interval '20 days'
WHERE id = pg_temp.id('nb_conv');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('nb');
PERFORM pg_temp.denied('A10 sans âge ni CGU : pas d''inscription à une sortie', format($$SELECT public.join_activity(%L)$$, pg_temp.id('nb_act')), '^Operation not permitted$');
PERFORM pg_temp.denied('A10 sans âge ni CGU : pas de dispo', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, -140.5, -48.5, 'Océan', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, '^Operation not permitted$');
PERFORM pg_temp.denied('A10 sans âge ni CGU : pas de trace GPX', $$SELECT (public.create_gpx_trace('Trace', '{"type":"LineString","coordinates":[[-140.5,-48.5],[-140.51,-48.51]]}'::jsonb)).id::text$$, '^Operation not permitted$');
PERFORM pg_temp.denied('A10 sans âge ni CGU : pas d''acceptation de contact', format($$SELECT public.accept_contact_request(%L)::text$$, pg_temp.id('nb_conv')), '^Operation not permitted$');
PERFORM pg_temp.ok('A10 le compte confirme sa majorité', $$SELECT public.confirm_age_adult()::text$$);
PERFORM pg_temp.ok('A10 le compte accepte les CGU', $$SELECT public.accept_tos()::text$$);
PERFORM pg_temp.eq('A10 une fois l''accueil fait, il rejoint la sortie', format($$SELECT public.join_activity(%L)$$, pg_temp.id('nb_act')), 'accepted');

-- A11 — Covoiturage (00494/00496 BR-3, 00522 F11, 00521 point de prise en charge,
-- 00488 blocage dans les deux sens, 00520 plafond de 8 places, 00516 L5 limites).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('cp_org', 'tos'); PERFORM pg_temp.user('cp_d1', 'tos'); PERFORM pg_temp.user('cp_d2', 'tos');
PERFORM pg_temp.user('cp_p', 'tos'); PERFORM pg_temp.user('cp_q', 'tos'); PERFORM pg_temp.user('cp_m', 'tos'); PERFORM pg_temp.user('cp_lv', 'tos');
PERFORM pg_temp.gf_act('cp_act', 'cp_org');
PERFORM pg_temp.gf_part('cp_act', u) FROM unnest(ARRAY['cp_d1', 'cp_d2', 'cp_p', 'cp_q', 'cp_m', 'cp_lv']) u;
PERFORM pg_temp.as_('cp_d1');
PERFORM pg_temp.ok('A11 cp_d1 propose 3 places', format($$SELECT public.set_participation_transport(%L, 'car', 3::smallint, 'Gap', NULL, 44.56, 6.08, 'Gap')::text$$, pg_temp.id('cp_act')));
PERFORM pg_temp.as_('cp_d2');
PERFORM pg_temp.ok('A11 cp_d2 propose 3 places', format($$SELECT public.set_participation_transport(%L, 'car', 3::smallint, 'Embrun', NULL, 44.56, 6.49, 'Embrun')::text$$, pg_temp.id('cp_act')));
PERFORM pg_temp.as_('cp_p');
PERFORM pg_temp.ok('A11 cp_p déclare son point de départ', format($$SELECT public.set_participation_transport(%L, 'on_foot', NULL, 'Chez moi', NULL, 44.50, 6.00, 'Chorges')::text$$, pg_temp.id('cp_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A11 fixture : le point de départ de cp_p est enregistré', format($$SELECT (transport_from_lat IS NOT NULL AND transport_from_locality IS NOT NULL)::text FROM public.participations WHERE id = %L$$, pg_temp.gf_pid('cp_act', 'cp_p')), 'true');
PERFORM pg_temp.as_('cp_p');
PERFORM pg_temp.ok('A11 cp_p demande une place à cp_d1', format($$SELECT public.request_seat(%L, %L, 'Gap gare')::text$$, pg_temp.id('cp_act'), pg_temp.id('cp_d1')));
PERFORM pg_temp.ok('A11 cp_p demande aussi une place à cp_d2', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('cp_act'), pg_temp.id('cp_d2')));
PERFORM pg_temp.as_('cp_d1');
PERFORM pg_temp.ok('A11 cp_d1 accepte cp_p', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.gf_sr('cp_act', 'cp_p', 'cp_d1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A11 monter dans une voiture efface tout son point de départ (00522 F11)',
  format($$SELECT (transport_from_lat IS NULL AND transport_from_lng IS NULL AND transport_from_locality IS NULL)::text FROM public.participations WHERE id = %L$$, pg_temp.gf_pid('cp_act', 'cp_p')), 'true');
PERFORM pg_temp.eq('A11 ses autres demandes en attente sont retirées (00496 BR-3)', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.gf_sr('cp_act', 'cp_p', 'cp_d2')), 'cancelled');
PERFORM pg_temp.as_('cp_p');
PERFORM pg_temp.denied('A11 une passagère placée ne propose pas de places (00496 BR-3)', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint)::text$$, pg_temp.id('cp_act')), 'junto\.already_seated');
PERFORM pg_temp.as_('cp_d1');
PERFORM pg_temp.denied('A11 un conducteur qui transporte quelqu''un ne demande pas de place (00496 BR-3)', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('cp_act'), pg_temp.id('cp_d2')), 'junto\.driver_has_passengers');
-- Point de prise en charge (00521) : conducteur, passagère, organisatrice ; pas les autres membres.
PERFORM pg_temp.as_('cp_m');
PERFORM pg_temp.eq('A11 un autre membre voit l''affectation sans le point de prise en charge (00521)', format($$SELECT count(*) || '|' || count(pickup_from) FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('cp_act')), '1|0');
PERFORM pg_temp.as_('cp_p');
PERFORM pg_temp.eq('A11 la passagère voit son point de prise en charge', format($$SELECT count(*) || '|' || count(pickup_from) FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('cp_act')), '1|1');
PERFORM pg_temp.as_('cp_d1');
PERFORM pg_temp.eq('A11 le conducteur voit le point de prise en charge', format($$SELECT count(*) || '|' || count(pickup_from) FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('cp_act')), '1|1');
PERFORM pg_temp.as_('cp_org');
PERFORM pg_temp.eq('A11 l''organisatrice voit le point de prise en charge', format($$SELECT count(*) || '|' || count(pickup_from) FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('cp_act')), '1|1');
-- Côté acceptation : un passager qui transporte des passagers ne monte pas ailleurs ;
-- un conducteur assis chez un autre ne prend personne (00496 BR-3).
PERFORM pg_temp.as_('db');
INSERT INTO public.seat_requests (activity_id, requester_id, driver_id, status) VALUES (pg_temp.id('cp_act'), pg_temp.id('cp_d1'), pg_temp.id('cp_d2'), 'pending');
PERFORM pg_temp.as_('cp_d2');
PERFORM pg_temp.denied('A11 accepter un demandeur qui transporte déjà quelqu''un est refusé (00496 BR-3)', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.gf_sr('cp_act', 'cp_d1', 'cp_d2')), 'junto\.driver_has_passengers');
PERFORM pg_temp.as_('db');
INSERT INTO public.seat_requests (activity_id, requester_id, driver_id, status) VALUES (pg_temp.id('cp_act'), pg_temp.id('cp_d2'), pg_temp.id('cp_org'), 'accepted');
INSERT INTO public.seat_requests (activity_id, requester_id, driver_id, status) VALUES (pg_temp.id('cp_act'), pg_temp.id('cp_q'), pg_temp.id('cp_d2'), 'pending');
PERFORM pg_temp.as_('cp_d2');
PERFORM pg_temp.denied('A11 un conducteur assis dans une autre voiture ne prend personne (00496 BR-3)', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.gf_sr('cp_act', 'cp_q', 'cp_d2')), 'junto\.already_seated');
-- Blocage pris dans les deux sens sur les affectations (00488).
PERFORM pg_temp.as_('db');
DELETE FROM public.seat_requests WHERE activity_id = pg_temp.id('cp_act') AND requester_id = pg_temp.id('cp_d2') AND driver_id = pg_temp.id('cp_org');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('cp_p'), pg_temp.id('cp_m'));
PERFORM pg_temp.as_('cp_m');
PERFORM pg_temp.eq('A11 bloqué par la passagère : l''affectation n''est plus listée (00488)', format($$SELECT count(*)::text FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('cp_act')), '0');
-- Rendre une place ne dépasse jamais 8 (00520 authz 5).
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.participations SET transport_seats = 8 WHERE id = pg_temp.gf_pid('cp_act', 'cp_d1')::uuid;
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('cp_p');
PERFORM pg_temp.ok('A11 la passagère rend sa place chez un conducteur à 8 places', format($$SELECT public.cancel_accepted_seat(%L)::text$$, pg_temp.gf_sr('cp_act', 'cp_p', 'cp_d1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A11 les places restent bornées à 8 (00520)', format($$SELECT transport_seats::text FROM public.participations WHERE id = %L$$, pg_temp.gf_pid('cp_act', 'cp_d1')), '8');
-- Quitter la sortie efface tout le point de départ (00522 F11).
PERFORM pg_temp.as_('cp_lv');
PERFORM pg_temp.ok('A11 cp_lv propose sa voiture depuis chez lui', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint, 'Chez moi', NULL, 44.55, 6.07, 'La Bâtie')::text$$, pg_temp.id('cp_act')));
PERFORM pg_temp.ok('A11 cp_lv quitte la sortie', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('cp_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A11 quitter efface coordonnées et village de départ (00522 F11)',
  format($$SELECT (transport_from_lat IS NULL AND transport_from_lng IS NULL AND transport_from_locality IS NULL)::text FROM public.participations WHERE id = %L$$, pg_temp.gf_pid('cp_act', 'cp_lv')), 'true');
-- Limites : transport et levée de pénalité, 20 / minute (00516 L5).
PERFORM pg_temp.as_('cp_q');
PERFORM pg_temp.eq('A11 transport : 20 déclarations par minute, la 21e est refusée (00516 L5)',
  format($$SELECT pg_temp.gf_loop(%L, 21)$$, format($s$SELECT public.set_participation_transport(%L, 'bike')$s$, pg_temp.id('cp_act'))), '20:junto.too_many_actions');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.gf_rate('cp_org', 'waive', 20);
PERFORM pg_temp.as_('cp_org');
PERFORM pg_temp.denied('A11 levée de pénalité : au-delà de 20 par minute, refus (00516 L5)', format($$SELECT public.waive_late_cancel_penalty(%L)::text$$, pg_temp.gf_pid('cp_act', 'cp_lv')), 'junto\.too_many_actions');

-- A12 — Pas d'annulation tardive en quittant la sortie d'un organisateur suspendu (00516).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('lp_org', 'tos'); PERFORM pg_temp.user('lp_org2', 'tos'); PERFORM pg_temp.user('lp_p', 'tos');
PERFORM pg_temp.gf_act('lp_act', 'lp_org', interval '6 hours', 'published', 'public', true);
PERFORM pg_temp.gf_act('lp_act2', 'lp_org2', interval '7 hours 30 minutes', 'published', 'public', true);
PERFORM pg_temp.gf_part('lp_act', 'lp_p'); PERFORM pg_temp.gf_part('lp_act2', 'lp_p');
PERFORM pg_temp.gf_suspend('lp_org');
PERFORM pg_temp.as_('lp_p');
PERFORM pg_temp.ok('A12 lp_p quitte tard la sortie de l''organisateur suspendu', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('lp_act')));
PERFORM pg_temp.ok('A12 lp_p quitte tard une sortie ordinaire', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('lp_act2')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A12 organisateur suspendu : aucune annulation tardive (00516)', format($$SELECT count(*)::text FROM public.late_cancels WHERE user_id = %L AND activity_id = %L$$, pg_temp.id('lp_p'), pg_temp.id('lp_act')), '0');
PERFORM pg_temp.eq('A12 organisateur actif : l''annulation tardive est enregistrée', format($$SELECT count(*)::text FROM public.late_cancels WHERE user_id = %L AND activity_id = %L$$, pg_temp.id('lp_p'), pg_temp.id('lp_act2')), '1');

-- A13 — La sortie d'un organisateur suspendu est figée à l'ouverture aussi (00495 L1).
PERFORM pg_temp.user('tf_org', 'tos'); PERFORM pg_temp.user('tf_org2', 'tos'); PERFORM pg_temp.user('tf_p', 'tos');
PERFORM pg_temp.gf_act('tf_act', 'tf_org', interval '-10 minutes', 'published', 'public', true);
PERFORM pg_temp.gf_act('tf_act2', 'tf_org2', interval '-10 minutes', 'published', 'public', true);
PERFORM pg_temp.gf_part('tf_act', 'tf_p'); PERFORM pg_temp.gf_part('tf_act2', 'tf_p');
PERFORM pg_temp.gf_suspend('tf_org');
PERFORM pg_temp.as_('tf_p');
PERFORM pg_temp.eq('A13 organisateur suspendu : la sortie ne passe pas « en cours » (00495 L1)', format($$SELECT public.transition_single_activity(%L)$$, pg_temp.id('tf_act')), 'published');
PERFORM pg_temp.eq('A13 organisateur actif : la sortie passe « en cours »', format($$SELECT public.transition_single_activity(%L)$$, pg_temp.id('tf_act2')), 'in_progress');

-- A14 — Changer la trace prévient les participants acceptés (00475).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('tr_org', 'tos'); PERFORM pg_temp.user('tr_p', 'tos');
PERFORM pg_temp.gf_act('tr_act', 'tr_org'); PERFORM pg_temp.gf_part('tr_act', 'tr_p');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET notification_preferences = notification_preferences || '{"activity_updated": true}'::jsonb WHERE id = pg_temp.id('tr_p');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('tr_org');
PERFORM pg_temp.ok('A14 l''organisateur pose une trace', format($$SELECT public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[-140.5,-48.5],[-140.52,-48.52]]}'::jsonb)::text$$, pg_temp.id('tr_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A14 le participant est prévenu du nouvel itinéraire (00475)', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'activity_updated' AND data->>'variant' = 'trace' AND data->>'activity_id' = %L$$, pg_temp.id('tr_p'), pg_temp.get('tr_act')), '1');

-- A15 — Écran d'évaluation fermé sur une sortie retirée (00520 authz 6).
PERFORM pg_temp.user('pv_org', 'tos'); PERFORM pg_temp.user('pv_p', 'tos');
PERFORM pg_temp.gf_act('pv_act', 'pv_org', interval '-1 day', 'completed', 'public', true, true);
PERFORM pg_temp.gf_part('pv_act', 'pv_p', 'accepted', true);
PERFORM pg_temp.as_('pv_p');
PERFORM pg_temp.ok('A15 un participant ouvre l''écran d''évaluation', format($$SELECT public.get_activity_peer_review_state(%L)::text$$, pg_temp.id('pv_act')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET deleted_at = now() WHERE id = pg_temp.id('pv_act');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('pv_p');
PERFORM pg_temp.denied('A15 sortie retirée : plus d''écran d''évaluation (00520)', format($$SELECT public.get_activity_peer_review_state(%L)::text$$, pg_temp.id('pv_act')), '^Operation not permitted$');

-- A16 — Compteurs, niveaux, badges, fiabilité : présences VALIDÉES, sorties retirées
-- ou annulées exclues (00495 PR-7/PR-10, 00520 authz 2, 00521 n° 3, 00522 F8).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('ag_org', 'tos'); PERFORM pg_temp.user('ag_j', 'tos'); PERFORM pg_temp.user('ag_u', 'tos'); PERFORM pg_temp.user('ag_obs', 'tos');
PERFORM pg_temp.user('ag_rl', 'tos'); PERFORM pg_temp.user('ag_sus', 'tos,suspended');
PERFORM pg_temp.gf_act('ag_c1', 'ag_org', interval '-3 days', 'completed', 'public', true, true);
PERFORM pg_temp.gf_act('ag_c2', 'ag_org', interval '-4 days', 'completed', 'public', true, true);
PERFORM pg_temp.gf_part('ag_c1', 'ag_j', 'accepted', true);
PERFORM pg_temp.gf_part('ag_c2', 'ag_j', 'accepted', true);
PERFORM pg_temp.gf_part('ag_c1', 'ag_u', 'accepted', NULL);
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET deleted_at = now() WHERE id = pg_temp.id('ag_c2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('ag_obs');
PERFORM pg_temp.eq('A16 compteurs : une sortie retirée ne compte pas (00520 authz 2)', format($$SELECT public.get_user_award_aggregates(%L) ->> 'joined'$$, pg_temp.id('ag_j')), '1');
PERFORM pg_temp.eq('A16 niveaux : une présence validée donne un niveau', format($$SELECT count(*)::text FROM public.get_user_sport_levels(%L) WHERE sport_key = 'hiking'$$, pg_temp.id('ag_j')), '1');
PERFORM pg_temp.eq('A16 niveaux : une sortie terminée sans présence validée compte aussi (00528)', format($$SELECT count(*)::text FROM public.get_user_sport_levels(%L)$$, pg_temp.id('ag_u')), '1');
PERFORM pg_temp.eq('A16 stats : une sortie terminée sans présence validée compte aussi (00528)', format($$SELECT coalesce((SELECT total_activities FROM public.get_user_public_stats(%L)), 0)::text$$, pg_temp.id('ag_u')), '1');
PERFORM pg_temp.eq('A16 stats : un appelant ordinaire lit les stats', format($$SELECT count(*)::text FROM public.get_user_public_stats(%L)$$, pg_temp.id('ag_j')), '1');
PERFORM pg_temp.as_('ag_sus');
PERFORM pg_temp.eq('A16 stats : rien pour un appelant suspendu (00520 ID-9)', format($$SELECT count(*)::text FROM public.get_user_public_stats(%L)$$, pg_temp.id('ag_j')), '0');
PERFORM pg_temp.eq('A16 niveaux : rien pour un appelant suspendu (00520 ID-9)', format($$SELECT count(*)::text FROM public.get_user_sport_levels(%L)$$, pg_temp.id('ag_j')), '0');
-- Badges de progression : 5 sorties.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('bg_org', 'tos'); PERFORM pg_temp.user('bg_org2', 'tos'); PERFORM pg_temp.user('bg_j', 'tos'); PERFORM pg_temp.user('bg_u', 'tos');
FOR i IN 1..5 LOOP
  PERFORM pg_temp.gf_act('bg_a' || i, 'bg_org', - (interval '10 days' + i * interval '1 day'), 'completed', 'public', true, true);
  PERFORM pg_temp.gf_part('bg_a' || i, 'bg_j', 'accepted', true);
  PERFORM pg_temp.gf_part('bg_a' || i, 'bg_u', 'accepted', NULL);
  PERFORM pg_temp.gf_act('bg_b' || i, 'bg_org2', - (interval '20 days' + i * interval '1 day'), 'completed', 'public', true, NULL);
  PERFORM pg_temp.gf_part('bg_b' || i, 'bg_j', 'accepted', NULL);
END LOOP;
PERFORM public.award_badge_progression(pg_temp.id(u), true) FROM unnest(ARRAY['bg_org', 'bg_org2', 'bg_j', 'bg_u']) u;
PERFORM pg_temp.eq('A16 badge « sorties rejointes » : 5 présences validées → bronze', format($$SELECT count(*)::text FROM public.user_badge_progression WHERE user_id = %L AND category = 'joined' AND tier_key = 'bronze'$$, pg_temp.id('bg_j')), '1');
PERFORM pg_temp.eq('A16 badge : 5 sorties terminées sans présence validée donnent aussi le bronze (00528)', format($$SELECT count(*)::text FROM public.user_badge_progression WHERE user_id = %L$$, pg_temp.id('bg_u')), '1');
PERFORM pg_temp.eq('A16 badge « organisateur » : présence de l''organisateur validée → bronze', format($$SELECT count(*)::text FROM public.user_badge_progression WHERE user_id = %L AND category = 'created'$$, pg_temp.id('bg_org')), '1');
PERFORM pg_temp.eq('A16 badge « organisateur » : 5 sorties terminées sans présence validée → bronze aussi (00528)', format($$SELECT count(*)::text FROM public.user_badge_progression WHERE user_id = %L AND category = 'created'$$, pg_temp.id('bg_org2')), '1');
-- Fiabilité : absences sur sorties retirées / annulées ignorées (00495 PR-10).
PERFORM pg_temp.gf_act('rl_del', 'ag_org', interval '-6 days', 'completed', 'public', true, true);
PERFORM pg_temp.gf_act('rl_cxl', 'ag_org', interval '-7 days', 'cancelled', 'public', true, true);
PERFORM pg_temp.gf_part('rl_del', 'ag_rl', 'accepted', false);
PERFORM pg_temp.gf_part('rl_cxl', 'ag_rl', 'accepted', false);
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET deleted_at = now() WHERE id = pg_temp.id('rl_del');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM public.recalculate_reliability_score(pg_temp.id('ag_rl'));
PERFORM pg_temp.eq('A16 fiabilité : absences sur sortie retirée ou annulée ignorées (00495 PR-10)', format($$SELECT reliability_score::int::text FROM public.users WHERE id = %L$$, pg_temp.id('ag_rl')), '100');

-- A17 — Compte visé suspendu : réputation, votants, trophées muets (00516 L7 / DX-3) ;
-- appelant suspendu : pas de votants.
PERFORM pg_temp.user('tv_s', 'tos');
FOR i IN 1..5 LOOP PERFORM pg_temp.user('tv_v' || i, 'tos'); END LOOP;
INSERT INTO public.reputation_votes (voter_id, voted_id, activity_id, badge_key, created_at, counted_at)
SELECT pg_temp.id('tv_v' || g), pg_temp.id('tv_s'), pg_temp.id('ag_c1'), 'punctual', now(), now() FROM generate_series(1, 5) g;
PERFORM pg_temp.gf_part('ag_c1', 'tv_s', 'accepted', true);
PERFORM pg_temp.as_('ag_obs');
PERFORM pg_temp.eq('A17 votants visibles à 5 personnes', format($$SELECT count(*)::text FROM public.get_voters_for_badge(%L, 'punctual')$$, pg_temp.id('tv_s')), '5');
PERFORM pg_temp.eq('A17 réputation visible', format($$SELECT (count(*) > 0)::text FROM public.get_user_reputation(%L)$$, pg_temp.id('tv_s')), 'true');
PERFORM pg_temp.eq('A17 trophées visibles', format($$SELECT (count(*) > 0)::text FROM public.get_user_trophies(%L)$$, pg_temp.id('tv_s')), 'true');
PERFORM pg_temp.as_('ag_sus');
PERFORM pg_temp.eq('A17 appelant suspendu : aucun votant (00516)', format($$SELECT count(*)::text FROM public.get_voters_for_badge(%L, 'punctual')$$, pg_temp.id('tv_s')), '0');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.gf_suspend('tv_s');
PERFORM pg_temp.as_('ag_obs');
PERFORM pg_temp.eq('A17 compte suspendu : aucun votant listé (00516 L7)', format($$SELECT count(*)::text FROM public.get_voters_for_badge(%L, 'punctual')$$, pg_temp.id('tv_s')), '0');
PERFORM pg_temp.eq('A17 compte suspendu : aucune réputation (00516 L7)', format($$SELECT count(*)::text FROM public.get_user_reputation(%L)$$, pg_temp.id('tv_s')), '0');
PERFORM pg_temp.eq('A17 compte suspendu : aucun trophée (00516 L7)', format($$SELECT count(*)::text FROM public.get_user_trophies(%L)$$, pg_temp.id('tv_s')), '0');

-- ═════════════════════════════════════════════════════════════════════════════
-- B. Messagerie
-- ═════════════════════════════════════════════════════════════════════════════

-- B1 — Discussions : 100 messages / jour / membre (00520 C8) ; un banni ne publie
-- jamais, même avec une ligne de membre restée (00522 F15) ; 500 membres au plus
-- (00514 MS-6) ; une discussion fermée ne se renomme plus (00514) ; photo : pas de
-- remontée « .. » (00503).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('ch_c', 'tos'); PERFORM pg_temp.user('ch_b', 'tos'); PERFORM pg_temp.user('ch_x', 'tos'); PERFORM pg_temp.user('ch_y', 'tos');
PERFORM pg_temp.as_('ch_c');
PERFORM pg_temp.put('ch1', pg_temp.ok('B1 ch_c crée une discussion', $$SELECT conversation_id::text FROM public.create_channel('Canal garde-fou', -151, -52, 'Océan', 35, NULL, NULL, NULL, true)$$));
PERFORM pg_temp.ok('B1 premier message du créateur', format($$SELECT public.send_message(%L, 'bonjour')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.gf_rate('ch_c', 'ch:' || pg_temp.get('ch1'), 99);
PERFORM pg_temp.as_('ch_c');
PERFORM pg_temp.denied('B1 101e message du jour dans la discussion refusé (00520 C8)', format($$SELECT public.send_message(%L, 'encore')::text$$, pg_temp.id('ch1')), 'junto\.too_many_actions');
PERFORM pg_temp.as_('ch_b'); PERFORM pg_temp.ok('B1 ch_b rejoint', format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.as_('ch_x'); PERFORM pg_temp.ok('B1 ch_x rejoint', format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.ok('B1 un membre ordinaire publie', format($$SELECT public.send_message(%L, 'salut')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.as_('ch_c'); PERFORM pg_temp.ok('B1 le créateur exclut ch_b', format($$SELECT public.remove_channel_member(%L, %L)::text$$, pg_temp.id('ch1'), pg_temp.id('ch_b')));
PERFORM pg_temp.as_('db');
INSERT INTO public.conversation_members (conversation_id, user_id, joined_at) VALUES (pg_temp.id('ch1'), pg_temp.id('ch_b'), now());
PERFORM pg_temp.as_('ch_b');
PERFORM pg_temp.denied('B1 un banni avec une ligne de membre restée ne publie pas (00522 F15)', format($$SELECT public.send_message(%L, 'retour')::text$$, pg_temp.id('ch1')), '^Operation not permitted$');
PERFORM pg_temp.as_('db');
EXECUTE 'CREATE TEMP TABLE gf_bulk AS SELECT gen_random_uuid() AS id FROM generate_series(1, 497)';
INSERT INTO auth.users (id, email, aud, role, raw_user_meta_data, created_at, updated_at)
SELECT b.id, 'test-' || b.id || '@junto.test', 'authenticated', 'authenticated', '{}'::jsonb, now(), now() FROM pg_temp.gf_bulk b;
INSERT INTO public.conversation_members (conversation_id, user_id, joined_at)
SELECT pg_temp.id('ch1'), b.id, now() FROM pg_temp.gf_bulk b
LIMIT (500 - (SELECT count(*) FROM public.conversation_members WHERE conversation_id = pg_temp.id('ch1')));
PERFORM pg_temp.eq('B1 fixture : la discussion compte 500 membres', format($$SELECT count(*)::text FROM public.conversation_members WHERE conversation_id = %L$$, pg_temp.id('ch1')), '500');
PERFORM pg_temp.as_('ch_y');
PERFORM pg_temp.denied('B1 discussion pleine à 500 membres (00514 MS-6)', format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('ch1')), 'junto\.channel_full');
PERFORM pg_temp.as_('ch_c');
PERFORM pg_temp.denied('B1 photo de discussion : remontée « .. » refusée (00503)', format($$SELECT public.set_channel_photo(%L, %L)::text$$, pg_temp.id('ch1'),
  pg_temp.host() || '/storage/v1/object/public/channel-photos/' || pg_temp.get('ch_c') || '/../' || pg_temp.get('ch_x') || '/x.jpg'), 'junto\.channel_photo');
PERFORM pg_temp.ok('B1 photo de son propre dossier acceptée', format($$SELECT public.set_channel_photo(%L, %L)::text$$, pg_temp.id('ch1'),
  pg_temp.host() || '/storage/v1/object/public/channel-photos/' || pg_temp.get('ch_c') || '/x.jpg'));
PERFORM pg_temp.ok('B1 le créateur ferme la discussion', format($$SELECT public.close_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.denied('B1 une discussion fermée ne se renomme plus (00514)', format($$SELECT public.rename_channel(%L, 'Nouveau nom')::text$$, pg_temp.id('ch1')), '^Operation not permitted$');

-- B2 — Groupe retiré par la modération : en lecture seule pour les partages, les
-- éditions et les ajouts (00519 F2).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('gm_a', 'tos'); PERFORM pg_temp.user('gm_b', 'tos'); PERFORM pg_temp.user('gm_c', 'tos'); PERFORM pg_temp.user('gm_d', 'tos');
PERFORM pg_temp.user('gm_adm', 'tos,admin');
PERFORM pg_temp.gf_connect('gm_a', u) FROM unnest(ARRAY['gm_b', 'gm_c', 'gm_d']) u;
PERFORM pg_temp.gf_act('gm_act', 'gm_a');
PERFORM pg_temp.as_('gm_a');
PERFORM pg_temp.put('gm_g', pg_temp.ok('B2 gm_a crée un groupe', format($$SELECT public.create_group('Groupe modéré', NULL, ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('gm_b'), pg_temp.id('gm_c'))));
PERFORM pg_temp.put('gm_m', pg_temp.ok('B2 gm_a écrit', format($$SELECT public.send_message(%L, 'premier jet')::text$$, pg_temp.id('gm_g'))));
PERFORM pg_temp.ok('B2 avant modération, le message se modifie', format($$SELECT public.edit_message(%L, 'premier jet corrigé')::text$$, pg_temp.id('gm_m')));
PERFORM pg_temp.as_('gm_adm');
PERFORM pg_temp.ok('B2 l''admin retire le groupe', format($$SELECT public.admin_remove_content('group', %L, 'Contenu signalé pour test')::text$$, pg_temp.id('gm_g')));
PERFORM pg_temp.as_('gm_a');
PERFORM pg_temp.denied('B2 groupe retiré : pas de partage (00519 F2)', format($$SELECT public.share_activity_message(%L, %L)::text$$, pg_temp.id('gm_g'), pg_temp.id('gm_act')), '^Operation not permitted$');
PERFORM pg_temp.denied('B2 groupe retiré : pas d''édition (00519 F2)', format($$SELECT public.edit_message(%L, 'réécrit')::text$$, pg_temp.id('gm_m')), '^Operation not permitted$');
PERFORM pg_temp.denied('B2 groupe retiré : pas d''ajout (00519 F2)', format($$SELECT public.add_group_member(%L, %L)::text$$, pg_temp.id('gm_g'), pg_temp.id('gm_d')), '^Operation not permitted$');

-- B3 — Quelqu'un qui a quitté un groupe n'y est pas remis par une copie, quel qu'en
-- soit l'auteur (00519 F1), ni ajouté par un autre membre dans un autre groupe.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('gc_a', 'tos'); PERFORM pg_temp.user('gc_b', 'tos'); PERFORM pg_temp.user('gc_c', 'tos');
PERFORM pg_temp.user('gc_d', 'tos'); PERFORM pg_temp.user('gc_e', 'tos');
PERFORM pg_temp.gf_connect('gc_a', u) FROM unnest(ARRAY['gc_b', 'gc_c', 'gc_d']) u;
PERFORM pg_temp.gf_connect('gc_b', u) FROM unnest(ARRAY['gc_c', 'gc_d', 'gc_e']) u;
PERFORM pg_temp.as_('gc_a');
PERFORM pg_temp.put('gc_g1', pg_temp.ok('B3 gc_a crée le groupe d''origine', format($$SELECT public.create_group('Origine', NULL, ARRAY[%L, %L, %L]::uuid[])::text$$, pg_temp.id('gc_b'), pg_temp.id('gc_c'), pg_temp.id('gc_d'))));
PERFORM pg_temp.as_('gc_c');
PERFORM pg_temp.ok('B3 gc_c quitte le groupe', format($$SELECT public.leave_group(%L)::text$$, pg_temp.id('gc_g1')));
PERFORM pg_temp.as_('gc_b');
PERFORM pg_temp.put('gc_g2', pg_temp.ok('B3 un autre membre (gc_b) crée une copie avec gc_c', format($$SELECT public.create_group('Copie', NULL, ARRAY[%L, %L, %L]::uuid[])::text$$, pg_temp.id('gc_c'), pg_temp.id('gc_d'), pg_temp.id('gc_e'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('B3 la copie ne remet pas la personne partie (00519 F1)', format($$SELECT count(*)::text FROM public.conversation_members WHERE conversation_id = %L AND user_id = %L$$, pg_temp.id('gc_g2'), pg_temp.id('gc_c')), '0');
PERFORM pg_temp.eq('B3 les autres sont bien dans la copie', format($$SELECT count(*)::text FROM public.conversation_members WHERE conversation_id = %L$$, pg_temp.id('gc_g2')), '3');
PERFORM pg_temp.as_('gc_b');
PERFORM pg_temp.denied('B3 ajouter la personne partie dans un autre groupe de l''ajouteur : refus codé (00519)', format($$SELECT public.add_group_member(%L, %L)::text$$, pg_temp.id('gc_g2'), pg_temp.id('gc_c')), 'junto\.member_left_recently');

-- B4 — Demandes de contact d'un compte suspendu masquées (00514 L4).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('cr_s', 'tos'); PERFORM pg_temp.user('cr_r', 'tos');
PERFORM pg_temp.as_('cr_s');
PERFORM pg_temp.ok('B4 cr_s envoie une demande de contact', format($$SELECT public.send_contact_request(%L, 'Bonjour')::text$$, pg_temp.id('cr_r')));
PERFORM pg_temp.as_('cr_r');
PERFORM pg_temp.eq('B4 la demande est visible', $$SELECT count(*)::text FROM public.get_pending_contact_requests()$$, '1');
PERFORM pg_temp.as_('db'); PERFORM pg_temp.gf_suspend('cr_s');
PERFORM pg_temp.as_('cr_r');
PERFORM pg_temp.eq('B4 la demande d''un compte suspendu est masquée (00514)', $$SELECT count(*)::text FROM public.get_pending_contact_requests()$$, '0');

-- B5 — Lien d'invitation porté par une demande de contact : une invitation refusée
-- ne revient pas par l'acceptation (00503 MS-3) ; un QR consomme le lien (00469 M3).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('mi_s', 'tos'); PERFORM pg_temp.user('mi_r', 'tos'); PERFORM pg_temp.user('mi_r2', 'tos'); PERFORM pg_temp.user('mi_q', 'tos');
PERFORM pg_temp.gf_act('mi_act', 'mi_s');
INSERT INTO public.conversations (type, user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message,
  request_expires_at, pending_activity_id, created_at, last_message_at)
SELECT 'dm', LEAST(pg_temp.id('mi_s'), pg_temp.id(r)), GREATEST(pg_temp.id('mi_s'), pg_temp.id(r)), pg_temp.id('mi_s'), 'pending_request', 'invite',
  pg_temp.id('mi_s'), 'Je t''invite', now() + interval '20 days', pg_temp.id('mi_act'), now(), now()
FROM unnest(ARRAY['mi_r', 'mi_r2', 'mi_q']) r;
INSERT INTO public.invitation_declines (activity_id, user_id, at) VALUES (pg_temp.id('mi_act'), pg_temp.id('mi_r'), now());
PERFORM pg_temp.put('mi_c1', (SELECT id::text FROM public.conversations WHERE user_1 = LEAST(pg_temp.id('mi_s'), pg_temp.id('mi_r')) AND user_2 = GREATEST(pg_temp.id('mi_s'), pg_temp.id('mi_r'))));
PERFORM pg_temp.put('mi_c2', (SELECT id::text FROM public.conversations WHERE user_1 = LEAST(pg_temp.id('mi_s'), pg_temp.id('mi_r2')) AND user_2 = GREATEST(pg_temp.id('mi_s'), pg_temp.id('mi_r2'))));
PERFORM pg_temp.as_('mi_r');
PERFORM pg_temp.ok('B5 mi_r accepte le contact', format($$SELECT public.accept_contact_request(%L)::text$$, pg_temp.id('mi_c1')));
PERFORM pg_temp.as_('mi_r2');
PERFORM pg_temp.ok('B5 mi_r2 accepte le contact', format($$SELECT public.accept_contact_request(%L)::text$$, pg_temp.id('mi_c2')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('B5 invitation déjà refusée : pas de nouvelle invitation par le contact (00503 MS-3)', format($$SELECT count(*)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('mi_act'), pg_temp.id('mi_r')), '0');
PERFORM pg_temp.eq('B5 sans refus antérieur, l''invitation est posée', format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('mi_act'), pg_temp.id('mi_r2')), 'invited');
PERFORM pg_temp.as_('mi_s');
PERFORM pg_temp.put('mi_qr', pg_temp.ok('B5 mi_s affiche son QR', $$SELECT public.create_contact_qr_token()$$));
PERFORM pg_temp.as_('mi_q');
PERFORM pg_temp.ok('B5 mi_q scanne le QR de mi_s', format($$SELECT public.connect_via_qr_token(%L)::text$$, pg_temp.get('mi_qr')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('B5 le QR consomme le lien d''invitation (00469 M3)', format($$SELECT (pending_activity_id IS NULL AND status = 'active')::text FROM public.conversations WHERE user_1 = LEAST(%L::uuid, %L::uuid) AND user_2 = GREATEST(%L::uuid, %L::uuid)$$,
  pg_temp.id('mi_s'), pg_temp.id('mi_q'), pg_temp.id('mi_s'), pg_temp.id('mi_q')), 'true');

-- B6 — QR de contact : un compte démo ne scanne pas (00469 L5) ; les échecs comptent
-- dans le quota de scans (L1) ; jeton de 2 min et 120 créations / h (M2).
PERFORM pg_temp.user('qr_demo', 'tos,demo'); PERFORM pg_temp.user('qr_u', 'tos'); PERFORM pg_temp.user('qr_u2', 'tos'); PERFORM pg_temp.user('qr_u3', 'tos');
PERFORM pg_temp.as_('qr_demo');
PERFORM pg_temp.denied('B6 un compte démo ne scanne pas de QR (00469 L5)', $$SELECT coalesce(public.connect_via_qr_token('pas-un-jeton')::text, 'null')$$, '^Operation not permitted$');
PERFORM pg_temp.as_('qr_u');
PERFORM pg_temp.eq('B6 les scans ratés comptent : 30 par heure, le 31e est refusé (00469 L1)',
  $$SELECT pg_temp.gf_loop('SELECT public.connect_via_qr_token(''pas-un-jeton'')', 31)$$, '30:junto.rate_limited');
PERFORM pg_temp.as_('qr_u2');
PERFORM pg_temp.put('qr_t', pg_temp.ok('B6 qr_u2 crée un QR', $$SELECT public.create_contact_qr_token()$$));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('B6 le jeton vit 2 minutes (00469 M2)', format($$SELECT (expires_at - now())::text FROM public.contact_qr_tokens WHERE token = %L$$, pg_temp.get('qr_t')), '00:02:00');
INSERT INTO public.contact_qr_tokens (token, user_id, expires_at, created_at)
SELECT md5(random()::text) || md5(random()::text), pg_temp.id('qr_u3'), now() - interval '1 minute', now() FROM generate_series(1, 119);
PERFORM pg_temp.as_('qr_u3');
PERFORM pg_temp.ok('B6 le 120e QR de l''heure est accepté (00469 M2)', $$SELECT public.create_contact_qr_token()$$);
PERFORM pg_temp.denied('B6 le 121e QR de l''heure est refusé (00469 M2)', $$SELECT public.create_contact_qr_token()$$, 'junto\.rate_limited');

-- B7 — Signalements : un seul par personne et cible (00520 authz 7).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('rp_a', 'tos'); PERFORM pg_temp.user('rp_b', 'tos');
PERFORM pg_temp.as_('rp_a');
PERFORM pg_temp.put('rp_1', pg_temp.ok('B7 rp_a signale rp_b', format($$SELECT public.create_report('user', %L, 'Raison de test suffisamment longue')::text$$, pg_temp.id('rp_b'))));
PERFORM pg_temp.denied('B7 un second signalement de la même cible est refusé (00520)', format($$SELECT public.create_report('user', %L, 'Raison de test suffisamment longue')::text$$, pg_temp.id('rp_b')), 'junto\.report_already_filed');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.denied('B7 l''index unique tient même en écriture directe (00520)',
  format($$INSERT INTO public.reports (reporter_id, target_type, target_id, reason, status) VALUES (%L, 'user', %L, 'Raison de test suffisamment longue', 'pending')$$, pg_temp.id('rp_a'), pg_temp.id('rp_b')), 'reports_one_per_target');

-- B8 — 10 appareils par compte, on garde les plus récemment utilisés (00514 AB-11, 00519 F6).
PERFORM pg_temp.user('pd_u', 'tos');
INSERT INTO public.push_tokens (user_id, token, created_at)
SELECT pg_temp.id('pd_u'), 'ExponentPushToken[gf-test-token-' || lpad(g::text, 2, '0') || ']', now() - (11 - g) * interval '1 hour' FROM generate_series(1, 10) g;
PERFORM pg_temp.as_('pd_u');
PERFORM pg_temp.ok('B8 réutiliser le plus ancien jeton le rafraîchit', $$SELECT public.register_push_token('ExponentPushToken[gf-test-token-01]')::text$$);
PERFORM pg_temp.ok('B8 un 11e appareil s''enregistre', $$SELECT public.register_push_token('ExponentPushToken[gf-test-token-new]')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('B8 au plus 10 appareils (00514 AB-11)', format($$SELECT count(*)::text FROM public.push_tokens WHERE user_id = %L$$, pg_temp.id('pd_u')), '10');
PERFORM pg_temp.eq('B8 le jeton réutilisé est gardé (00519 F6)', format($$SELECT count(*)::text FROM public.push_tokens WHERE user_id = %L AND token = 'ExponentPushToken[gf-test-token-01]'$$, pg_temp.id('pd_u')), '1');
PERFORM pg_temp.eq('B8 le moins récemment utilisé est retiré', format($$SELECT count(*)::text FROM public.push_tokens WHERE user_id = %L AND token = 'ExponentPushToken[gf-test-token-02]'$$, pg_temp.id('pd_u')), '0');

-- B9 — Aucun événement live vers un membre suspendu (00472 L12).
PERFORM pg_temp.user('gp_a', 'tos'); PERFORM pg_temp.user('gp_b', 'tos'); PERFORM pg_temp.user('gp_c', 'tos');
PERFORM pg_temp.gf_connect('gp_a', u) FROM unnest(ARRAY['gp_b', 'gp_c']) u;
PERFORM pg_temp.as_('gp_a');
PERFORM pg_temp.put('gp_g', pg_temp.ok('B9 gp_a crée un groupe', format($$SELECT public.create_group('Groupe live', NULL, ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('gp_b'), pg_temp.id('gp_c'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.gf_suspend('gp_c');
PERFORM pg_temp.put('gp_n_a', (SELECT count(*)::text FROM realtime.messages WHERE topic = 'user:' || pg_temp.get('gp_a')));
PERFORM pg_temp.put('gp_n_c', (SELECT count(*)::text FROM realtime.messages WHERE topic = 'user:' || pg_temp.get('gp_c')));
PERFORM pg_temp.as_('gp_b');
PERFORM pg_temp.ok('B9 gp_b écrit dans le groupe', format($$SELECT public.send_message(%L, 'live')::text$$, pg_temp.id('gp_g')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('B9 un membre actif reçoit l''événement live', format($$SELECT (count(*) - %s)::text FROM realtime.messages WHERE topic = 'user:' || %L$$, pg_temp.get('gp_n_a'), pg_temp.get('gp_a')), '1');
PERFORM pg_temp.eq('B9 un membre suspendu ne reçoit rien (00472 L12)', format($$SELECT (count(*) - %s)::text FROM realtime.messages WHERE topic = 'user:' || %L$$, pg_temp.get('gp_n_c'), pg_temp.get('gp_c')), '0');

-- ═════════════════════════════════════════════════════════════════════════════
-- C. Découverte
-- ═════════════════════════════════════════════════════════════════════════════

-- C1 — 30 enregistrements de dispo par jour, comptés seulement après les contrôles
-- (00485, 00488) ; 300 comptages par heure (00485 DC-2).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('dc_u', 'tos'); PERFORM pg_temp.user('dc_u2', 'tos'); PERFORM pg_temp.user('dc_u3', 'tos');
PERFORM pg_temp.gf_rate('dc_u', 'dispo', 29);
PERFORM pg_temp.as_('dc_u');
PERFORM pg_temp.denied('C1 une dispo invalide est refusée…', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, -152.0, -53.0, 'Océan', 7, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto\.dispo_radius');
PERFORM pg_temp.ok('C1 …sans entamer le quota : la 30e dispo du jour passe (00488)', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, -152.0, -53.0, 'Océan', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$);
PERFORM pg_temp.denied('C1 la 31e dispo du jour est refusée (00485)', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, -152.0, -53.0, 'Océan', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto\.too_many_actions');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.gf_rate('dc_u2', 'dispo_count', 300);
PERFORM pg_temp.as_('dc_u2');
PERFORM pg_temp.denied('C1 au-delà de 300 comptages par heure, refus (00485 DC-2)', $$SELECT public.get_discovery_count(ARRAY['hiking'], -152.0, -53.0, 15, now(), now() + interval '7 days')::text$$, 'junto\.too_many_actions');
PERFORM pg_temp.as_('dc_u3');
PERFORM pg_temp.ok('C1 un autre compte compte toujours', $$SELECT public.get_discovery_count(ARRAY['hiking'], -152.0, -53.0, 15, now(), now() + interval '7 days')::text$$);

-- C2 — Deux « peu importe » : 50 km, pas tout le pays (00522 F7).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('f7_p', 'tos'); PERFORM pg_temp.user('f7_near', 'tos'); PERFORM pg_temp.user('f7_far', 'tos');
PERFORM pg_temp.gf_dispo('f7_near', -149.53, -55.0, NULL, now() + interval '1 hour', now() + interval '7 days');  -- ≈ 30 km
PERFORM pg_temp.gf_dispo('f7_far', -148.75, -55.0, NULL, now() + interval '1 hour', now() + interval '7 days');   -- ≈ 80 km
PERFORM pg_temp.as_('f7_p');
PERFORM pg_temp.ok('C2 f7_p pose une dispo « peu importe » et l''active', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, -150.0, -55.0, 'Océan', NULL, ARRAY['car'], now() + interval '1 hour', now() + interval '7 days')::text || public.activate_dispo()::text$$);
PERFORM pg_temp.eq('C2 deux « peu importe » se croisent à 30 km mais pas à 80 km (00522 F7)',
  format($$SELECT coalesce(string_agg(CASE user_id WHEN %L THEN 'near' WHEN %L THEN 'far' END, ',' ORDER BY user_id = %L DESC), '') FROM public.get_discovery_cards() WHERE user_id IN (%L, %L)$$,
    pg_temp.id('f7_near'), pg_temp.id('f7_far'), pg_temp.id('f7_near'), pg_temp.id('f7_near'), pg_temp.id('f7_far')), 'near');

-- C3 — Invitation Découverte : jamais après un refus (00514 MS-3), jamais vers une dispo
-- dont la fenêtre est passée (00496 BR-5).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('di_s', 'tos'); PERFORM pg_temp.user('di_decl', 'tos'); PERFORM pg_temp.user('di_past', 'tos'); PERFORM pg_temp.user('di_ok', 'tos');
PERFORM pg_temp.gf_dispo('di_s', -160.0, -60.0, 15, now() - interval '1 day', now() + interval '20 days');
PERFORM pg_temp.gf_dispo('di_decl', -160.0, -60.0, 15, now() - interval '1 day', now() + interval '20 days');
PERFORM pg_temp.gf_dispo('di_ok', -160.0, -60.0, 15, now() - interval '1 day', now() + interval '20 days');
PERFORM pg_temp.gf_dispo('di_past', -160.0, -60.0, 15, now() - interval '2 days', now() - interval '1 hour');
PERFORM pg_temp.gf_act('di_act', 'di_s', interval '3 days');
INSERT INTO public.invitation_declines (activity_id, user_id, at) VALUES (pg_temp.id('di_act'), pg_temp.id('di_decl'), now());
PERFORM pg_temp.as_('di_s');
PERFORM pg_temp.denied('C3 pas d''invitation Découverte après un refus (00514 MS-3)', format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('di_decl'), pg_temp.id('di_act')), '^Operation not permitted$');
PERFORM pg_temp.denied('C3 pas d''invitation vers une dispo passée (00496 BR-5)', format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('di_past'), pg_temp.id('di_act')), '^Operation not permitted$');
PERFORM pg_temp.ok('C3 une dispo vivante qui correspond reçoit l''invitation', format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('di_ok'), pg_temp.id('di_act')));

-- ═════════════════════════════════════════════════════════════════════════════
-- D. Pro
-- ═════════════════════════════════════════════════════════════════════════════

-- D1 — Liens : site en http(s), Facebook / Instagram sans schéma exotique, dès
-- l'inscription et au niveau de la table (00518 L1, 00519 F4) ; nom vide après
-- nettoyage refusé (00473 L14 / 00474 F4).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('lk_u', 'tos');
PERFORM pg_temp.as_('lk_u');
PERFORM pg_temp.denied('D1 inscription : site en javascript: refusé avec un code (00519)',
  $$SELECT public.register_as_pro(p_display_name := 'Guide', p_company_name := 'SARL Test', p_real_name := 'Jean Test', p_website := 'javascript:alert(1)', p_primary_lng := -140.5, p_primary_lat := -48.5, p_primary_location_name := 'Océan')::text$$, 'junto\.pro_website_invalid');
PERFORM pg_temp.denied('D1 inscription : Facebook en javascript: refusé avec un code (00518 L1)',
  $$SELECT public.register_as_pro(p_display_name := 'Guide', p_company_name := 'SARL Test', p_real_name := 'Jean Test', p_facebook := 'javascript:alert(1)', p_primary_lng := -140.5, p_primary_lat := -48.5, p_primary_location_name := 'Océan')::text$$, 'junto\.pro_website_invalid');
PERFORM pg_temp.ok('D1 inscription avec des liens ordinaires',
  $$SELECT public.register_as_pro(p_display_name := 'Guide', p_company_name := 'SARL Test', p_real_name := 'Jean Test', p_website := 'https://example.org', p_facebook := 'maPage', p_instagram := 'https://instagram.com/x', p_primary_lng := -140.5, p_primary_lat := -48.5, p_primary_location_name := 'Océan')::text$$);
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.denied('D1 modification : Instagram en data: refusé avec un code (00518 L1)', $$SELECT public.update_pro_profile(p_instagram := 'data:text/html,x')::text$$, 'junto\.pro_website_invalid');
PERFORM pg_temp.denied('D1 modification : un nom fait de balises vides est refusé (00474 F4)', $$SELECT public.update_pro_profile(p_display_name := '<b>  </b>')::text$$, '^Operation not permitted$');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
PERFORM pg_temp.denied('D1 la table refuse un Instagram en schéma exotique (00518 L1)', format($$UPDATE public.pro_profiles SET instagram = 'javascript:alert(1)' WHERE user_id = %L$$, pg_temp.id('lk_u')), 'pro_profiles_social_no_scheme');
PERFORM set_config('junto.bypass_lock', 'false', true);

-- D2 — Une seule notification de renommage par pro et par jour (00522 F6).
PERFORM pg_temp.user('rn2_adm', 'tos,admin');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET status = 'approved' WHERE user_id = pg_temp.id('lk_u');
UPDATE public.pro_profiles SET display_name = 'Nom un' WHERE user_id = pg_temp.id('lk_u');
UPDATE public.pro_profiles SET display_name = 'Nom deux' WHERE user_id = pg_temp.id('lk_u');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('D2 deux renommages le même jour : une seule notification à l''admin (00522 F6)',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'pro_renamed' AND data->>'pro_id' = %L$$, pg_temp.id('rn2_adm'), pg_temp.get('lk_u')), '1');

-- D3 — Photos communautaires : pas sur la page d'un pro suspendu (00520 authz 8) ;
-- celle d'un contributeur suspendu est masquée (00518 L2).
PERFORM pg_temp.user('pc_pro', 'tos'); PERFORM pg_temp.user('pc_pro2', 'tos'); PERFORM pg_temp.user('pc_c1', 'tos'); PERFORM pg_temp.user('pc_c2', 'tos');
PERFORM pg_temp.gf_pro('pc_pro', 'pc_off'); PERFORM pg_temp.gf_pro('pc_pro2', 'pc_off2');
PERFORM pg_temp.as_('pc_c1');
PERFORM pg_temp.put('pc_ph', pg_temp.ok('D3 pc_c1 ajoute une photo communautaire', format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pc_pro'),
  pg_temp.host() || '/storage/v1/object/public/pro-photos/' || pg_temp.get('pc_c1') || '/c.jpg')));
PERFORM pg_temp.as_('pc_c2');
PERFORM pg_temp.eq('D3 la photo est visible des autres', format($$SELECT count(*)::text FROM public.pro_community_photos WHERE id = %L$$, pg_temp.id('pc_ph')), '1');
PERFORM pg_temp.as_('db'); PERFORM pg_temp.gf_suspend('pc_c1');
PERFORM pg_temp.as_('pc_c2');
PERFORM pg_temp.eq('D3 contributeur suspendu : sa photo est masquée (00518 L2)', format($$SELECT count(*)::text FROM public.pro_community_photos WHERE id = %L$$, pg_temp.id('pc_ph')), '0');
PERFORM pg_temp.as_('db'); PERFORM pg_temp.gf_suspend('pc_pro2');
PERFORM pg_temp.as_('pc_c2');
PERFORM pg_temp.denied('D3 pas de photo communautaire chez un pro suspendu (00520 authz 8)', format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pc_pro2'),
  pg_temp.host() || '/storage/v1/object/public/pro-photos/' || pg_temp.get('pc_c2') || '/c.jpg'), '^Operation not permitted$');

-- D4 — Bloqué par le pro : on ne réécrit pas un ancien avis (00501 PO-4).
PERFORM pg_temp.as_('db');  -- 00554 : avis réservé à qui a réservé
INSERT INTO public.bookings (offering_id, pro_id, client_id, day, period, party_size, status)
VALUES (pg_temp.id('pc_off'), pg_temp.id('pc_pro'), pg_temp.id('pc_c2'), current_date - 7, 'am', 1, 'accepted');
PERFORM pg_temp.as_('pc_c2');
PERFORM pg_temp.put('pc_rv', pg_temp.ok('D4 pc_c2 laisse un avis sur le pro', format($$SELECT public.create_pro_review(%L, 4::smallint, 'Bien')::text$$, pg_temp.id('pc_pro'))));
PERFORM pg_temp.put('pc_orv', pg_temp.ok('D4 pc_c2 laisse un avis sur l''offre', format($$SELECT public.create_offering_review(%L, 4::smallint, 'Bien')::text$$, pg_temp.id('pc_off'))));
PERFORM pg_temp.ok('D4 avant blocage, l''avis se réécrit', format($$SELECT public.update_pro_review(%L, 3::smallint, 'Moyen')::text$$, pg_temp.id('pc_rv')));
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('pc_pro'), pg_temp.id('pc_c2'));
PERFORM pg_temp.as_('pc_c2');
PERFORM pg_temp.denied('D4 bloqué par le pro : l''avis sur la page ne se réécrit plus (00501 PO-4)', format($$SELECT public.update_pro_review(%L, 1::smallint, 'Nul')::text$$, pg_temp.id('pc_rv')), '^Operation not permitted$');
PERFORM pg_temp.denied('D4 bloqué par le pro : l''avis sur l''offre ne se réécrit plus (00501 PO-4)', format($$SELECT public.update_offering_review(%L, 1::smallint, 'Nul')::text$$, pg_temp.id('pc_orv')), '^Operation not permitted$');

-- D5 — Favori sur l'offre d'un pro non approuvé refusé (00505 B8).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('pf_pro', 'tos'); PERFORM pg_temp.user('pf_u', 'tos');
PERFORM pg_temp.gf_pro('pf_pro', 'pf_off');
PERFORM pg_temp.as_('pf_u');
PERFORM pg_temp.ok('D5 favori sur l''offre d''un pro approuvé', format($$SELECT public.add_favorite('offering', %L)::text$$, pg_temp.id('pf_off')));
PERFORM pg_temp.ok('D5 retrait du favori', format($$SELECT public.remove_favorite('offering', %L)::text$$, pg_temp.id('pf_off')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET status = 'pending' WHERE user_id = pg_temp.id('pf_pro');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('pf_u');
PERFORM pg_temp.denied('D5 pas de favori sur l''offre d''un pro non approuvé (00505 B8)', format($$SELECT public.add_favorite('offering', %L)::text$$, pg_temp.id('pf_off')), '^Operation not permitted$');

-- D6 — Une réservation re-soumise reprend le prix du moment (00505 PO-5).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('pb_u', 'tos');
PERFORM pg_temp.put('pb_day', (current_date + 12)::text);
INSERT INTO public.pro_availabilities (pro_id, day, period) VALUES (pg_temp.id('pc_pro'), pg_temp.get('pb_day')::date, 'am');
PERFORM pg_temp.as_('pb_u');
PERFORM pg_temp.put('pb_bk', pg_temp.ok('D6 pb_u réserve à 50 €', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, pg_temp.id('pc_off'), pg_temp.get('pb_day'))));
PERFORM pg_temp.as_('pc_pro');
PERFORM pg_temp.ok('D6 le pro refuse', format($$SELECT public.decline_booking(%L)::text$$, pg_temp.id('pb_bk')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_offerings SET price_eur = 80 WHERE id = pg_temp.id('pc_off');
UPDATE public.bookings SET last_submitted_at = now() - interval '2 hours' WHERE id = pg_temp.id('pb_bk');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('pb_u');
PERFORM pg_temp.eq('D6 pb_u redemande le même créneau (même réservation)', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, pg_temp.id('pc_off'), pg_temp.get('pb_day')), pg_temp.get('pb_bk'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('D6 la demande re-soumise prend le prix du moment (00505 PO-5)', format($$SELECT price_eur::int::text FROM public.bookings WHERE id = %L$$, pg_temp.id('pb_bk')), '80');

-- ═════════════════════════════════════════════════════════════════════════════
-- E. Identité et quotas partagés
-- ═════════════════════════════════════════════════════════════════════════════

-- E1 — Empreinte d'e-mail interdit : points Gmail ignorés (00513) ; un changement
-- d'e-mail de connexion vers un e-mail interdit est refusé (00513).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('ban_local', 'gfban' || substr(md5(random()::text), 1, 10));
INSERT INTO public.banned_email_hashes (email_hash) VALUES (private.email_hash(pg_temp.get('ban_local') || '@gmail.com'));
PERFORM pg_temp.eq('E1 Gmail : points, +étiquette et googlemail.com ne contournent pas l''interdiction (00513)',
  $$SELECT private.email_is_banned(regexp_replace(pg_temp.get('ban_local'), '(.)', '\1.', 'g') || '+re@GoogleMail.com')::text$$, 'true');
PERFORM pg_temp.eq('E1 un autre domaine n''est pas concerné',
  $$SELECT private.email_is_banned(pg_temp.get('ban_local') || '@example.org')::text$$, 'false');
PERFORM pg_temp.user('em_u', 'tos');
PERFORM pg_temp.denied('E1 changer son e-mail de connexion pour un e-mail interdit est refusé (00513)',
  format($$UPDATE auth.users SET email = %L WHERE id = %L$$, substr(pg_temp.get('ban_local'), 1, 2) || '.' || substr(pg_temp.get('ban_local'), 3) || '@gmail.com', pg_temp.id('em_u')), '^Operation not permitted$');
PERFORM pg_temp.ok('E1 un changement d''e-mail ordinaire passe',
  format($$UPDATE auth.users SET email = %L WHERE id = %L$$, 'test-autre-' || pg_temp.get('em_u') || '@junto.test', pg_temp.id('em_u')));
PERFORM pg_temp.denied('E1 préférences de notification bornées (00513)',
  format($$UPDATE public.users SET notification_preferences = jsonb_build_object('x', repeat('y', 6000)) WHERE id = %L$$, pg_temp.id('em_u')), 'users_notification_preferences_size');

-- E2 — Plafond global quotidien des appels de tracé, compté sur la journée
-- (00520 AB-7, 00522 F3), et purge à 1 jour.
PERFORM pg_temp.user('gs_a', 'tos'); PERFORM pg_temp.user('gs_b', 'tos');
PERFORM pg_temp.as_('gs_b');
PERFORM pg_temp.ok('E2 un appel de tracé ordinaire passe', $$SELECT public.consume_snap_trail_quota()::text$$);
PERFORM pg_temp.as_('db');
INSERT INTO public.snap_trail_calls (user_id, called_at)
SELECT pg_temp.id('gs_a'), now() - interval '3 hours'
FROM generate_series(1, 1500 - (SELECT count(*)::int FROM public.snap_trail_calls WHERE called_at > now() - interval '1 day'));
PERFORM pg_temp.as_('gs_b');
PERFORM pg_temp.denied('E2 1500 appels sur la journée (vieux de 3 h) : plafond global atteint (00520 AB-7, 00522 F3)', $$SELECT public.consume_snap_trail_quota()::text$$, 'junto\.rate_limited');
PERFORM pg_temp.as_('db');
INSERT INTO public.snap_trail_calls (user_id, called_at) VALUES (pg_temp.id('gs_a'), now() - interval '25 hours');
PERFORM pg_temp.ok('E2 purge des tables de limitation', $$SELECT public.purge_throttle_tables()::text$$);
PERFORM pg_temp.eq('E2 la purge garde les appels du jour (00522 F3)', format($$SELECT (count(*) > 0)::text FROM public.snap_trail_calls WHERE user_id = %L AND called_at > now() - interval '1 day'$$, pg_temp.id('gs_a')), 'true');
PERFORM pg_temp.eq('E2 la purge retire les appels de plus d''un jour', format($$SELECT count(*)::text FROM public.snap_trail_calls WHERE user_id = %L AND called_at < now() - interval '1 day'$$, pg_temp.id('gs_a')), '0');
