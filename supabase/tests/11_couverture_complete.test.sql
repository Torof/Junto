-- Domaine 11 — couverture complète : chaque RPC client, chaque fonction trigger, chaque vue et
-- chaque tâche planifiée a au moins un test du chemin légitime (vérifié par son effet) et un
-- test du refus principal. Ce fichier ne contient que ce qui manquait aux fichiers 00 à 10
-- (inventaire du catalogue du 2026-10-22).
-- Fixtures en plein Pacifique (-152.5, -49.5), créées en `db` quand le chemin testé n'est pas
-- la création elle-même.

-- ───── Utilitaires locaux ─────
EXECUTE $p$CREATE FUNCTION pg_temp.fc_act(p_label text, p_creator text, p_start interval DEFAULT interval '90 days',
    p_status text DEFAULT 'published', p_vis text DEFAULT 'public', p_cp boolean DEFAULT NULL) RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting,
      starts_at, duration, visibility, status, requires_presence)
    VALUES (pg_temp.id(p_creator), (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie couverture ' || p_label,
      'Tous niveaux', 10, ST_SetSRID(ST_MakePoint(-152.5, -49.5), 4326)::geography,
      now() + p_start, interval '2 hours', p_vis, p_status, true)
    RETURNING id INTO v;
    INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, created_at)
    VALUES (v, pg_temp.id(p_creator), 'accepted', p_cp, now() - interval '3 days');
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.fc_part(p_act text, p_user text, p_status text DEFAULT 'accepted',
    p_cp boolean DEFAULT NULL) RETURNS void
  LANGUAGE sql AS $b$
  INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, created_at)
  VALUES (pg_temp.id(p_act), pg_temp.id(p_user), p_status, p_cp, now() - interval '2 days') $b$$p$;

-- Fil DM (db) entre deux comptes.
EXECUTE $p$CREATE FUNCTION pg_temp.fc_dm(p_key text, a text, b text, p_status text DEFAULT 'active') RETURNS uuid
  LANGUAGE plpgsql AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.conversations (type, user_1, user_2, initiated_by, request_sender_id, status, initiated_from,
      created_at, last_message_at)
    VALUES ('dm', LEAST(pg_temp.id(a), pg_temp.id(b)), GREATEST(pg_temp.id(a), pg_temp.id(b)), pg_temp.id(a),
      CASE WHEN p_status = 'active' THEN NULL ELSE pg_temp.id(a) END, p_status, 'profile', now(), now())
    RETURNING id INTO v;
    PERFORM pg_temp.put(p_key, v::text);
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.fc_url(p_bucket text, p_label text, p_file text) RETURNS text
  LANGUAGE sql AS $b$ SELECT pg_temp.host() || '/storage/v1/object/public/' || p_bucket || '/' || pg_temp.id(p_label)::text || '/' || p_file $b$$p$;

-- Nombre d'événements live sur un sujet (realtime.messages).
EXECUTE $p$CREATE FUNCTION pg_temp.fc_rt(p_topic text) RETURNS int
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT count(*)::int FROM realtime.messages WHERE topic = p_topic $b$$p$;

-- Nombre d'appels push en file pour un compte (corps de requête qui mentionne son id).
EXECUTE $p$CREATE FUNCTION pg_temp.fc_push(p_user text) RETURNS int
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT count(*)::int FROM net.http_request_queue WHERE convert_from(body, 'UTF8') LIKE '%' || pg_temp.get(p_user) || '%' $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.fc_lock(p_on boolean) RETURNS void
  LANGUAGE sql AS $b$ SELECT set_config('junto.bypass_lock', CASE WHEN p_on THEN 'true' ELSE 'false' END, true) $b$$p$;

-- La tâche minute prend un verrou « essai » : si l'exécution planifiée tourne au même instant,
-- l'appel ne fait rien. On réessaie quelques fois avant de conclure.
EXECUTE $p$CREATE FUNCTION pg_temp.fc_transitions(p_act text) RETURNS text
  LANGUAGE plpgsql AS $b$
  DECLARE v text;
  BEGIN
    FOR i IN 1..20 LOOP
      PERFORM public.check_activity_transitions();
      SELECT status INTO v FROM public.activities WHERE id = pg_temp.id(p_act);
      EXIT WHEN v <> 'published';
      PERFORM pg_sleep(0.5);
    END LOOP;
    RETURN v;
  END $b$$p$;

-- ───── Comptes ─────
PERFORM pg_temp.user('adm', 'tos,admin');
PERFORM pg_temp.user('sadm', 'tos,admin,suspended');
PERFORM pg_temp.user('sam', 'tos,suspended');
PERFORM pg_temp.user('a', 'tos');
PERFORM pg_temp.user('b', 'tos');
PERFORM pg_temp.user('c', 'tos');
PERFORM pg_temp.user('d', 'tos');
PERFORM pg_temp.user('mal', 'tos');   -- étranger à tout
PERFORM pg_temp.user('eu', 'tos');    -- profil à recréer
PERFORM pg_temp.user('cps', 'tos');   -- sera suspendu (jetons push)
PERFORM pg_temp.user('pn', 'tos');    -- destinataire de push
PERFORM pg_temp.user('pro', 'tos');
PERFORM pg_temp.user('pro2', 'tos');
PERFORM pg_temp.user('cand', 'tos');  -- candidature pro en attente
PERFORM pg_temp.user('cli', 'tos');
PERFORM pg_temp.put('sport', (SELECT id::text FROM public.sports WHERE key = 'hiking'));
PERFORM pg_temp.put('d1', ((now() AT TIME ZONE 'Europe/Paris')::date + 10)::text);
PERFORM pg_temp.put('d2', ((now() AT TIME ZONE 'Europe/Paris')::date + 11)::text);

-- ═════ 1. Administration et modération ═════
PERFORM pg_temp.fc_act('adm_act', 'c');
PERFORM pg_temp.as_('a');
PERFORM pg_temp.denied('admin_remove_content : un non-admin ne retire pas de contenu',
  format($$SELECT public.admin_remove_content('activity', %L, 'Contenu signalé')::text$$, pg_temp.id('adm_act')), '^Operation not permitted$');
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.ok('admin_remove_content : l''admin retire une sortie',
  format($$SELECT public.admin_remove_content('activity', %L, 'Contenu signalé')::text$$, pg_temp.id('adm_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('admin_remove_content : la sortie est retirée', format($$SELECT (deleted_at IS NOT NULL)::text FROM public.activities WHERE id = %L$$, pg_temp.id('adm_act')), 'true');

-- Rideau démo : visible pour un admin actif quand le mode démo est allumé.
PERFORM pg_temp.as_('db');
UPDATE public.app_config SET value = 'true' WHERE name = 'demo_mode';
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.eq('demo_content_visible : vrai pour un admin quand le mode démo est allumé', $$SELECT public.demo_content_visible()::text$$, 'true');
PERFORM pg_temp.as_('a');
PERFORM pg_temp.eq('demo_content_visible : faux pour un compte ordinaire même mode démo allumé', $$SELECT public.demo_content_visible()::text$$, 'false');
PERFORM pg_temp.as_('sadm');
PERFORM pg_temp.eq('demo_content_visible : faux pour un admin suspendu', $$SELECT public.demo_content_visible()::text$$, 'false');
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.ok('admin_set_demo_mode : l''admin éteint le mode démo', $$SELECT public.admin_set_demo_mode(false)::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('admin_set_demo_mode : le mode démo est éteint', $$SELECT value FROM public.app_config WHERE name = 'demo_mode'$$, 'false');
PERFORM pg_temp.eq('admin_set_demo_mode : l''action est journalisée', format($$SELECT count(*)::text FROM public.admin_actions WHERE admin_id = %L AND action = 'demo_mode_off'$$, pg_temp.id('adm')), '1');

-- Signalement puis modération.
PERFORM pg_temp.as_('a');
PERFORM pg_temp.put('rep', pg_temp.ok('create_report : a signale b', format($$SELECT public.create_report('user', %L, '<b>Raison</b> de test suffisamment longue')::text$$, pg_temp.id('b'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('create_report : le signalement est enregistré en attente, motif nettoyé',
  format($$SELECT status || '|' || reason || '|' || (reporter_id = %L)::text FROM public.reports WHERE id = %L$$, pg_temp.id('a'), pg_temp.id('rep')),
  'pending|Raison de test suffisamment longue|true');
PERFORM pg_temp.as_('c');
PERFORM pg_temp.denied('moderate_report : un non-admin ne traite pas un signalement',
  format($$SELECT public.moderate_report(%L, 'dismissed')::text$$, pg_temp.id('rep')), '^Operation not permitted$');
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.ok('moderate_report : l''admin classe le signalement', format($$SELECT public.moderate_report(%L, 'dismissed', 'Rien à signaler')::text$$, pg_temp.id('rep')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('moderate_report : statut, note et date de traitement posés',
  format($$SELECT status || '|' || admin_note || '|' || (resolved_at IS NOT NULL)::text FROM public.reports WHERE id = %L$$, pg_temp.id('rep')), 'dismissed|Rien à signaler|true');
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.denied('moderate_report : un signalement déjà traité ne se retraite pas',
  format($$SELECT public.moderate_report(%L, 'actioned')::text$$, pg_temp.id('rep')), '^Operation not permitted$');

-- ═════ 2. Identité : profil recréé, HTML, jetons push ═════
PERFORM pg_temp.as_('db');
DELETE FROM public.users WHERE id = pg_temp.id('eu');
PERFORM pg_temp.eq('ensure_user_row : fixture — le profil a disparu', format($$SELECT count(*)::text FROM public.users WHERE id = %L$$, pg_temp.id('eu')), '0');
PERFORM pg_temp.as_('eu');
PERFORM pg_temp.ok('ensure_user_row : la connexion recrée le profil manquant', $$SELECT public.ensure_user_row()::text$$);
PERFORM pg_temp.ok('ensure_user_row : un second appel est sans effet', $$SELECT public.ensure_user_row()::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('ensure_user_row : un seul profil, à l''e-mail du compte',
  format($$SELECT count(*)::text || '|' || bool_and(email = 'test-' || id || '@junto.test')::text FROM public.users WHERE id = %L$$, pg_temp.id('eu')), '1|true');

PERFORM pg_temp.as_('a');
PERFORM pg_temp.ok('strip_html_users : a écrit un nom et une bio avec du HTML',
  format($$UPDATE public.users SET display_name = '<b>Alice</b> Test', bio = '<script>x</script>Bio' WHERE id = %L$$, pg_temp.id('a')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('strip_html_users : nom et bio stockés sans balises', format($$SELECT display_name || '|' || bio FROM public.users WHERE id = %L$$, pg_temp.id('a')), 'Alice Test|xBio');

PERFORM pg_temp.as_('cps');
PERFORM pg_temp.ok('clear_push_token_on_suspension : fixture — cps enregistre un jeton', $$SELECT public.register_push_token('ExponentPushToken[fc-test-cps-00001]', 'dev-cps')::text$$);
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.ok('clear_push_token_on_suspension : l''admin suspend cps', format($$SELECT public.admin_suspend_user(%L, 'raison de test')::text$$, pg_temp.id('cps')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('clear_push_token_on_suspension : les jetons du compte suspendu sont effacés', format($$SELECT count(*)::text FROM public.push_tokens WHERE user_id = %L$$, pg_temp.id('cps')), '0');

PERFORM pg_temp.as_('b');
PERFORM pg_temp.ok('revoke_push_token_for_device : fixture — b enregistre son appareil', $$SELECT public.register_push_token('ExponentPushToken[fc-test-b-000001]', 'dev-fc-b')::text$$);
PERFORM pg_temp.as_('c');
PERFORM pg_temp.ok('revoke_push_token_for_device : c révoque l''identifiant d''appareil de b', $$SELECT public.revoke_push_token_for_device('dev-fc-b')::text$$);
PERFORM pg_temp.denied('revoke_push_token_for_device : identifiant d''appareil vide refusé', $$SELECT public.revoke_push_token_for_device('')::text$$, '^Operation not permitted$');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('revoke_push_token_for_device : le jeton de b est intact', format($$SELECT count(*)::text FROM public.push_tokens WHERE user_id = %L$$, pg_temp.id('b')), '1');

-- Push d'une notification : envoyé, sauf pour les types silencieux.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('pn0', pg_temp.fc_push('pn')::text);
INSERT INTO public.notifications (user_id, type, title, body, data)
VALUES (pg_temp.id('pn'), 'participant_joined', 'Nouveau participant', 'Quelqu''un a rejoint', jsonb_build_object('activity_id', gen_random_uuid(), 'secret_key', 'x'));
PERFORM pg_temp.eq('push_notification_to_device : une notification part en push', format($$SELECT (pg_temp.fc_push('pn') - %s)::text$$, pg_temp.get('pn0')), '1');
PERFORM pg_temp.eq('push_notification_to_device : les clés hors liste ne partent pas',
  $$SELECT count(*)::text FROM net.http_request_queue WHERE convert_from(body, 'UTF8') LIKE '%' || pg_temp.get('pn') || '%' AND convert_from(body, 'UTF8') LIKE '%secret_key%'$$, '0');
INSERT INTO public.notifications (user_id, type, title, body) VALUES (pg_temp.id('pn'), 'rate_participants', 'Évalue', 'Évalue tes partenaires');
PERFORM pg_temp.eq('push_notification_to_device : un type silencieux ne part pas', format($$SELECT (pg_temp.fc_push('pn') - %s)::text$$, pg_temp.get('pn0')), '1');

-- ═════ 3. Sorties : triggers de cycle de vie ═════
-- Titre et description sans HTML.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.fc_act('html_act', 'c');
PERFORM pg_temp.ok('strip_html_tags : réécriture d''un titre et d''une description balisés',
  format($$UPDATE public.activities SET title = '<b>Titre</b> balisé', description = '<i>Desc</i>ription' WHERE id = %L$$, pg_temp.id('html_act')));
PERFORM pg_temp.eq('strip_html_tags : titre et description stockés sans balises',
  format($$SELECT title || '|' || description FROM public.activities WHERE id = %L$$, pg_temp.id('html_act')), 'Titre balisé|Description');

-- Date et voie d'acceptation.
PERFORM pg_temp.fc_act('sa_act', 'c');
PERFORM pg_temp.fc_part('sa_act', 'a', 'accepted');
PERFORM pg_temp.eq('stamp_accepted_at : inscription directe → « self » et date posée',
  format($$SELECT accepted_via || '|' || (accepted_at IS NOT NULL)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('sa_act'), pg_temp.id('a')), 'self|true');
PERFORM pg_temp.fc_part('sa_act', 'b', 'pending');
UPDATE public.participations SET status = 'accepted' WHERE activity_id = pg_temp.id('sa_act') AND user_id = pg_temp.id('b');
PERFORM pg_temp.eq('stamp_accepted_at : demande acceptée → « organiser »',
  format($$SELECT accepted_via FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('sa_act'), pg_temp.id('b')), 'organiser');
UPDATE public.participations SET status = 'withdrawn' WHERE activity_id = pg_temp.id('sa_act') AND user_id = pg_temp.id('a');
PERFORM pg_temp.eq('stamp_accepted_at : un départ efface date et voie d''acceptation',
  format($$SELECT (accepted_at IS NULL AND accepted_via IS NULL)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('sa_act'), pg_temp.id('a')), 'true');

-- Événement live de la sortie quand une participation change.
PERFORM pg_temp.put('rt0', pg_temp.fc_rt('activity:' || pg_temp.get('sa_act'))::text);
PERFORM pg_temp.fc_part('sa_act', 'd', 'accepted');
PERFORM pg_temp.eq('broadcast_activity_change : une inscription émet un événement sur le canal de la sortie',
  format($$SELECT (pg_temp.fc_rt('activity:' || pg_temp.get('sa_act')) - %s)::text$$, pg_temp.get('rt0')), '1');
PERFORM pg_temp.eq('broadcast_activity_change : les événements ne transportent que la table et l''opération',
  format($$SELECT count(*)::text FROM realtime.messages WHERE topic = 'activity:' || %L AND (payload - 'id' - 'op' - 'table') <> '{}'::jsonb$$, pg_temp.get('sa_act')), '0');

-- Signal carte d'une participation : sorties publiques seulement.
PERFORM pg_temp.fc_act('mp_pub', 'c', interval '91 days');
PERFORM pg_temp.fc_act('mp_priv', 'c', interval '92 days', 'published', 'private_link');
DELETE FROM public.map_broadcasts WHERE activity_id IN (pg_temp.id('mp_pub'), pg_temp.id('mp_priv'));
PERFORM pg_temp.fc_part('mp_pub', 'a');
PERFORM pg_temp.fc_part('mp_priv', 'a');
PERFORM pg_temp.eq('broadcast_map_participation : une inscription à une sortie publique émet un signal carte',
  format($$SELECT count(*)::text FROM public.map_broadcasts WHERE activity_id = %L$$, pg_temp.id('mp_pub')), '1');
PERFORM pg_temp.eq('broadcast_map_participation : rien pour une sortie privée',
  format($$SELECT count(*)::text FROM public.map_broadcasts WHERE activity_id = %L$$, pg_temp.id('mp_priv')), '0');

-- Fin d'une sortie : invitations, demandes et demandes de place expirent.
PERFORM pg_temp.fc_act('ex_act', 'c', interval '93 days');
PERFORM pg_temp.fc_part('ex_act', 'a', 'invited');
PERFORM pg_temp.fc_part('ex_act', 'b', 'pending');
PERFORM pg_temp.fc_part('ex_act', 'd', 'accepted');
PERFORM pg_temp.fc_part('ex_act', 'mal', 'accepted');
INSERT INTO public.seat_requests (activity_id, requester_id, driver_id, status) VALUES (pg_temp.id('ex_act'), pg_temp.id('mal'), pg_temp.id('d'), 'pending');
PERFORM pg_temp.fc_lock(true);
UPDATE public.activities SET status = 'cancelled' WHERE id = pg_temp.id('ex_act');
PERFORM pg_temp.fc_lock(false);
PERFORM pg_temp.eq('expire_invited_on_activity_end : l''invitation expire avec la sortie',
  format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('ex_act'), pg_temp.id('a')), 'expired');
PERFORM pg_temp.eq('on_activity_finished_expire_seat_requests : la demande de participation expire',
  format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('ex_act'), pg_temp.id('b')), 'expired');
PERFORM pg_temp.eq('on_activity_finished_expire_seat_requests : la demande de place expire',
  format($$SELECT status FROM public.seat_requests WHERE activity_id = %L AND requester_id = %L$$, pg_temp.id('ex_act'), pg_temp.id('mal')), 'expired');
PERFORM pg_temp.eq('expire_invited_on_activity_end : un participant accepté n''est pas touché',
  format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('ex_act'), pg_temp.id('d')), 'accepted');

-- Sortie terminée : progression des trophées (4 présences + la 5e qui se termine = bronze).
PERFORM pg_temp.user('aw_u', 'tos');
PERFORM pg_temp.fc_act('aw_' || i, 'c', (-40 + i) * interval '1 day', 'completed', 'public', true) FROM generate_series(1, 4) i;
PERFORM pg_temp.fc_part('aw_' || i, 'aw_u', 'accepted', true) FROM generate_series(1, 4) i;
PERFORM pg_temp.fc_act('aw_run', 'c', interval '-3 hours', 'in_progress', 'public', true);
PERFORM pg_temp.fc_part('aw_run', 'aw_u', 'accepted', true);
PERFORM pg_temp.eq('on_activity_completed_award_badges : fixture — pas encore de trophée',
  format($$SELECT count(*)::text FROM public.user_badge_progression WHERE user_id = %L AND category = 'joined'$$, pg_temp.id('aw_u')), '0');
PERFORM pg_temp.fc_lock(true);
UPDATE public.activities SET status = 'completed' WHERE id = pg_temp.id('aw_run');
PERFORM pg_temp.fc_lock(false);
PERFORM pg_temp.eq('on_activity_completed_award_badges : la 5e sortie terminée donne le bronze',
  format($$SELECT tier_key FROM public.user_badge_progression WHERE user_id = %L AND category = 'joined'$$, pg_temp.id('aw_u')), 'bronze');

-- Score de l'organisateur recalculé quand le groupe change, s'il a validé sa présence.
PERFORM pg_temp.user('rc_o', 'tos'); PERFORM pg_temp.user('rc_o2', 'tos');
PERFORM pg_temp.fc_act('rc_act', 'rc_o', interval '-2 days', 'completed', 'public', true);
PERFORM pg_temp.fc_act('rc_act2', 'rc_o2', interval '-2 days', 'completed', 'public', NULL);
PERFORM pg_temp.fc_lock(true);
UPDATE public.users SET reliability_score = 1 WHERE id IN (pg_temp.id('rc_o'), pg_temp.id('rc_o2'));
PERFORM pg_temp.fc_lock(false);
PERFORM pg_temp.fc_part('rc_act', 'a', 'accepted', true);
PERFORM pg_temp.fc_part('rc_act2', 'a', 'accepted', true);
PERFORM pg_temp.eq('recalc_creator_on_participant_change : le score de l''organisateur présent est recalculé',
  format($$SELECT (reliability_score IS DISTINCT FROM 1)::text FROM public.users WHERE id = %L$$, pg_temp.id('rc_o')), 'true');
PERFORM pg_temp.eq('recalc_creator_on_participant_change : rien pour un organisateur sans présence enregistrée',
  format($$SELECT reliability_score::int::text FROM public.users WHERE id = %L$$, pg_temp.id('rc_o2')), '1');

-- Matériel partagé : il n'est plus « manquant ».
PERFORM pg_temp.fc_act('gear_act', 'c', interval '94 days');
INSERT INTO public.activity_gear_missing (activity_id, name, created_by) VALUES (pg_temp.id('gear_act'), 'Corde', pg_temp.id('c'));
INSERT INTO public.activity_gear_missing (activity_id, name, created_by) VALUES (pg_temp.id('gear_act'), 'Piolet', pg_temp.id('c'));
INSERT INTO public.activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES (pg_temp.id('gear_act'), pg_temp.id('c'), 'CORDE', 1, true);
PERFORM pg_temp.eq('clear_missing_on_shared_gear : le matériel apporté n''est plus manquant (casse ignorée), le reste demeure',
  format($$SELECT string_agg(name, ',') FROM public.activity_gear_missing WHERE activity_id = %L$$, pg_temp.id('gear_act')), 'Piolet');

-- Blocage : invitation retirée, demande de contact refusée.
PERFORM pg_temp.fc_act('bi_act', 'c', interval '95 days', 'published', 'private_link');
PERFORM pg_temp.fc_part('bi_act', 'mal', 'invited');
PERFORM pg_temp.fc_part('bi_act', 'b', 'invited');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('mal'), pg_temp.id('c'));
PERFORM pg_temp.eq('cascade_block_invited : bloquer l''organisateur retire son invitation',
  format($$SELECT count(*)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('bi_act'), pg_temp.id('mal')), '0');
PERFORM pg_temp.eq('cascade_block_invited : l''invitation d''un tiers reste',
  format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('bi_act'), pg_temp.id('b')), 'invited');
PERFORM pg_temp.fc_dm('dm_req', 'd', 'mal', 'pending_request');
PERFORM pg_temp.fc_dm('dm_req2', 'd', 'b', 'pending_request');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('mal'), pg_temp.id('d'));
PERFORM pg_temp.eq('cascade_block_to_requests : la demande de contact entre les deux est refusée',
  format($$SELECT status FROM public.conversations WHERE id = %L$$, pg_temp.id('dm_req')), 'declined');
PERFORM pg_temp.eq('cascade_block_to_requests : une demande avec un tiers reste en attente',
  format($$SELECT status FROM public.conversations WHERE id = %L$$, pg_temp.id('dm_req2')), 'pending_request');

-- Demande de place : annulation par le passager.
PERFORM pg_temp.fc_act('sr_act', 'c', interval '96 days');
PERFORM pg_temp.fc_part('sr_act', 'd');
PERFORM pg_temp.fc_part('sr_act', 'a');
UPDATE public.participations SET transport_type = 'car', transport_seats = 2 WHERE activity_id = pg_temp.id('sr_act') AND user_id = pg_temp.id('d');
PERFORM pg_temp.put('sr', pg_temp.run(format($$INSERT INTO public.seat_requests (activity_id, requester_id, driver_id, status) VALUES (%L, %L, %L, 'pending') RETURNING id::text$$,
  pg_temp.id('sr_act'), pg_temp.id('a'), pg_temp.id('d'))));
PERFORM pg_temp.as_('a');
PERFORM pg_temp.ok('cancel_pending_seat_request : la passagère annule sa demande', format($$SELECT public.cancel_pending_seat_request(%L)::text$$, pg_temp.id('sr')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('cancel_pending_seat_request : la demande est annulée', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.id('sr')), 'cancelled');

-- Partenaires récents.
PERFORM pg_temp.fc_act('rp_act', 'c', interval '-10 days', 'completed');
PERFORM pg_temp.fc_part('rp_act', 'b');
PERFORM pg_temp.fc_part('rp_act', 'sam');
PERFORM pg_temp.as_('b');
PERFORM pg_temp.eq('get_recent_partners : l''organisatrice d''une sortie passée est proposée',
  format($$SELECT count(*)::text FROM public.get_recent_partners() WHERE id = %L$$, pg_temp.id('c')), '1');
PERFORM pg_temp.eq('get_recent_partners : un compte suspendu n''est pas proposé',
  format($$SELECT count(*)::text FROM public.get_recent_partners() WHERE id = %L$$, pg_temp.id('sam')), '0');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.eq('get_recent_partners : un appelant suspendu ne reçoit rien', $$SELECT count(*)::text FROM public.get_recent_partners()$$, '0');
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.eq('get_recent_partners : un étranger à la sortie ne reçoit pas ces partenaires',
  format($$SELECT count(*)::text FROM public.get_recent_partners() WHERE id IN (%L, %L)$$, pg_temp.id('b'), pg_temp.id('c')), '0');

-- ═════ 4. Messagerie ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.fc_dm('dm_ab', 'a', 'b');
PERFORM pg_temp.as_('a');
PERFORM pg_temp.put('m_ab', pg_temp.ok('send_private_message : a écrit à b', format($$SELECT public.send_private_message(%L, 'Salut <b>B</b>')::text$$, pg_temp.id('dm_ab'))));
PERFORM pg_temp.as_('b');
PERFORM pg_temp.eq('send_private_message : b lit le message, nettoyé, signé par a',
  format($$SELECT content || '|' || (sender_id = %L)::text FROM public.messages WHERE id = %L$$, pg_temp.id('a'), pg_temp.id('m_ab')), 'Salut B|true');
PERFORM pg_temp.as_('a');
PERFORM pg_temp.put('m_tr', pg_temp.ok('share_trace_message : a partage une trace',
  format($$SELECT public.share_trace_message(%L, '{"type":"LineString","coordinates":[[-152.5,-49.5],[-152.49,-49.49]]}'::jsonb, 'Ma <b>trace</b>')::text$$, pg_temp.id('dm_ab'))));
PERFORM pg_temp.as_('b');
PERFORM pg_temp.eq('share_trace_message : la carte arrive avec son nom nettoyé',
  format($$SELECT (metadata->>'type') || '|' || (metadata->>'name') FROM public.messages WHERE id = %L$$, pg_temp.id('m_tr')), 'shared_trace|Ma trace');

-- Message réécrit : événement live ; colonnes figées.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('rtm0', pg_temp.fc_rt('conversation:' || pg_temp.get('dm_ab'))::text);
UPDATE public.messages SET content = 'Salut B, corrigé' WHERE id = pg_temp.id('m_ab');
PERFORM pg_temp.eq('broadcast_message_update : un message modifié émet un événement sur la conversation',
  format($$SELECT (pg_temp.fc_rt('conversation:' || pg_temp.get('dm_ab')) - %s)::text$$, pg_temp.get('rtm0')), '1');
UPDATE public.messages SET content = content WHERE id = pg_temp.id('m_ab');
PERFORM pg_temp.eq('broadcast_message_update : une réécriture identique n''émet rien',
  format($$SELECT (pg_temp.fc_rt('conversation:' || pg_temp.get('dm_ab')) - %s)::text$$, pg_temp.get('rtm0')), '1');
PERFORM pg_temp.ok('messages_whitelist_columns : réécriture de l''expéditeur et du type sans déverrouillage',
  format($$UPDATE public.messages SET sender_id = %L, metadata = '{"type":"forged"}'::jsonb, content = 'Texte modifié' WHERE id = %L$$, pg_temp.id('b'), pg_temp.id('m_ab')));
PERFORM pg_temp.eq('messages_whitelist_columns : expéditeur et métadonnées gardés, texte modifié',
  format($$SELECT (sender_id = %L)::text || '|' || coalesce(metadata->>'type', 'null') || '|' || content FROM public.messages WHERE id = %L$$, pg_temp.id('a'), pg_temp.id('m_ab')),
  'true|null|Texte modifié');

-- Lu / masqué par un non-membre : sans effet sur les membres.
PERFORM pg_temp.fc_dm('dm_cd', 'c', 'd');
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.ok('mark_conversation_read : un non-membre appelle sur le fil de c et d', format($$SELECT public.mark_conversation_read(%L)::text$$, pg_temp.id('dm_cd')));
PERFORM pg_temp.ok('set_conversation_hidden : un non-membre appelle sur le fil de c et d', format($$SELECT public.set_conversation_hidden(%L, true)::text$$, pg_temp.id('dm_cd')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('mark_conversation_read / set_conversation_hidden : ni lecture ni masquage posés, aucun membre ajouté',
  format($$SELECT count(*)::text || '|' || bool_and(last_read_at IS NULL AND hidden_at IS NULL)::text FROM public.conversation_members WHERE conversation_id = %L$$, pg_temp.id('dm_cd')), '2|true');

-- Suppression d'un fil : ses notifications partent avec.
PERFORM pg_temp.fc_dm('dm_del', 'c', 'mal');
INSERT INTO public.notifications (user_id, type, title, body, data) VALUES
  (pg_temp.id('c'), 'contact_request', 't', 'b', jsonb_build_object('conversation_id', pg_temp.id('dm_del'))),
  (pg_temp.id('c'), 'contact_request', 't', 'b', jsonb_build_object('conversation_id', pg_temp.id('dm_cd')));
DELETE FROM public.conversations WHERE id = pg_temp.id('dm_del');
PERFORM pg_temp.eq('cleanup_notifications_on_conversation_delete : la notification du fil supprimé disparaît',
  format($$SELECT count(*)::text FROM public.notifications WHERE data->>'conversation_id' = %L$$, pg_temp.get('dm_del')), '0');
PERFORM pg_temp.eq('cleanup_notifications_on_conversation_delete : celle d''un autre fil reste',
  format($$SELECT count(*)::text FROM public.notifications WHERE data->>'conversation_id' = %L$$, pg_temp.get('dm_cd')), '1');

-- Retirer un contact : refusé à un compte suspendu.
PERFORM pg_temp.fc_dm('dm_as', 'b', 'sam');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('remove_connection : un compte suspendu ne retire pas de contact', format($$SELECT public.remove_connection(%L)::text$$, pg_temp.id('b')), '^Operation not permitted$');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('remove_connection : le fil reste', format($$SELECT count(*)::text FROM public.conversations WHERE id = %L$$, pg_temp.id('dm_as')), '1');

-- Groupe : renommage, colonnes figées.
PERFORM pg_temp.put('grp', pg_temp.run(format($$INSERT INTO public.conversations (type, name, created_by, status, created_at, last_message_at)
  VALUES ('group', 'Groupe test', %L, 'active', now(), now()) RETURNING id::text$$, pg_temp.id('a'))));
INSERT INTO public.conversation_members (conversation_id, user_id, joined_at)
SELECT pg_temp.id('grp'), pg_temp.id(u), now() FROM unnest(ARRAY['a', 'b', 'c']) u;
PERFORM pg_temp.as_('a');
PERFORM pg_temp.ok('rename_group : le créateur renomme le groupe', format($$SELECT public.rename_group(%L, '<i>Groupe</i> renommé', '⛰')::text$$, pg_temp.id('grp')));
PERFORM pg_temp.as_('b');
PERFORM pg_temp.eq('rename_group : les membres voient le nouveau nom, nettoyé', format($$SELECT DISTINCT group_name FROM public.get_group_info(%L)$$, pg_temp.id('grp')), 'Groupe renommé');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('conversations_whitelist_columns : réécriture du créateur sans déverrouillage',
  format($$UPDATE public.conversations SET created_by = %L, icon = '🏔' WHERE id = %L$$, pg_temp.id('b'), pg_temp.id('grp')));
PERFORM pg_temp.eq('conversations_whitelist_columns : créateur gardé, icône modifiée',
  format($$SELECT (created_by = %L)::text || '|' || icon FROM public.conversations WHERE id = %L$$, pg_temp.id('a'), pg_temp.id('grp')), 'true|🏔');
PERFORM pg_temp.ok('conversation_members_whitelist_columns : réécriture de l''ajouteur sans déverrouillage',
  format($$UPDATE public.conversation_members SET added_by = %L, user_id = %L, last_read_at = now() WHERE conversation_id = %L AND user_id = %L$$,
    pg_temp.id('c'), pg_temp.id('mal'), pg_temp.id('grp'), pg_temp.id('b')));
PERFORM pg_temp.eq('conversation_members_whitelist_columns : membre et ajouteur gardés, lecture posée',
  format($$SELECT coalesce(added_by::text, 'null') || '|' || (last_read_at IS NOT NULL)::text FROM public.conversation_members WHERE conversation_id = %L AND user_id = %L$$,
    pg_temp.id('grp'), pg_temp.id('b')), 'null|true');
PERFORM pg_temp.eq('conversation_members_whitelist_columns : mal n''a pas été glissé dans le groupe',
  format($$SELECT count(*)::text FROM public.conversation_members WHERE conversation_id = %L AND user_id = %L$$, pg_temp.id('grp'), pg_temp.id('mal')), '0');

-- Canal : renommage, photo, départ, colonnes figées.
PERFORM pg_temp.as_('c');
PERFORM pg_temp.put('ch', pg_temp.ok('fixture : c crée un canal', $$SELECT conversation_id::text FROM public.create_channel('Canal couverture', -152.5, -49.5, 'Océan', 35)$$));
PERFORM pg_temp.ok('rename_channel : le créateur renomme le canal', format($$SELECT public.rename_channel(%L, '<b>Canal</b> renommé')::text$$, pg_temp.id('ch')));
PERFORM pg_temp.ok('set_channel_photo : le créateur pose une photo de son dossier',
  format($$SELECT public.set_channel_photo(%L, %L)::text$$, pg_temp.id('ch'), pg_temp.fc_url('channel-photos', 'c', 'photo.jpg')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('rename_channel : le nom est changé et nettoyé', format($$SELECT name FROM public.conversations WHERE id = %L$$, pg_temp.id('ch')), 'Canal renommé');
PERFORM pg_temp.eq('set_channel_photo : la photo est enregistrée', format($$SELECT photo_url FROM public.channels WHERE conversation_id = %L$$, pg_temp.id('ch')),
  pg_temp.fc_url('channel-photos', 'c', 'photo.jpg'));
PERFORM pg_temp.ok('channels_whitelist_columns : réécriture du créateur, du rayon et de la photo sans déverrouillage',
  format($$UPDATE public.channels SET created_by = %L, radius_km = 100, photo_url = NULL, description = 'Nouvelle description' WHERE conversation_id = %L$$, pg_temp.id('mal'), pg_temp.id('ch')));
PERFORM pg_temp.eq('channels_whitelist_columns : créateur, rayon et photo gardés, description modifiée',
  format($$SELECT (created_by = %L)::text || '|' || radius_km || '|' || (photo_url IS NOT NULL)::text || '|' || description FROM public.channels WHERE conversation_id = %L$$, pg_temp.id('c'), pg_temp.id('ch')),
  'true|35|true|Nouvelle description');
PERFORM pg_temp.as_('a');
PERFORM pg_temp.denied('leave_channel : un fil qui n''est pas un canal est refusé', format($$SELECT public.leave_channel(%L)::text$$, pg_temp.id('dm_ab')), '^Operation not permitted$');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('leave_channel : a reste membre de son DM', format($$SELECT count(*)::text FROM public.conversation_members WHERE conversation_id = %L AND user_id = %L$$, pg_temp.id('dm_ab'), pg_temp.id('a')), '1');

-- ═════ 5. Découverte, alertes, traces, favoris ═════
PERFORM pg_temp.as_('a');
PERFORM pg_temp.ok('fixture : a pose et active sa dispo',
  $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text || public.activate_dispo()::text$$);
PERFORM pg_temp.as_('b');
PERFORM pg_temp.ok('fixture : b pose et active sa dispo',
  $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text || public.activate_dispo()::text$$);
PERFORM pg_temp.ok('deactivate_dispo : b désactive sa dispo', $$SELECT public.deactivate_dispo()::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('deactivate_dispo : seule la dispo de l''appelant est désactivée',
  format($$SELECT string_agg(user_id::text || ':' || is_active::text, ',' ORDER BY (user_id = %L) DESC) FROM public.discovery_availabilities WHERE user_id IN (%L, %L)$$,
    pg_temp.id('a'), pg_temp.id('a'), pg_temp.id('b')),
  pg_temp.get('a') || ':true,' || pg_temp.get('b') || ':false');
PERFORM pg_temp.as_('c');
PERFORM pg_temp.eq('get_my_dispo : sans dispo, rien (pas celle des autres)', $$SELECT count(*)::text FROM public.get_my_dispo()$$, '0');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('discovery_availabilities_whitelist_columns : réécriture de is_active / is_demo sans déverrouillage',
  format($$UPDATE public.discovery_availabilities SET is_active = false, is_demo = true, base_label = 'Briançon' WHERE user_id = %L$$, pg_temp.id('a')));
PERFORM pg_temp.eq('discovery_availabilities_whitelist_columns : activation et démo gardées, lieu modifié',
  format($$SELECT is_active::text || '|' || is_demo::text || '|' || base_label FROM public.discovery_availabilities WHERE user_id = %L$$, pg_temp.id('a')), 'true|false|Briançon');

PERFORM pg_temp.as_('c');
PERFORM pg_temp.put('alert', pg_temp.ok('create_alert : c crée une alerte', $$SELECT public.create_alert(6.0, 44.0, 25, 'hiking', ARRAY['débutant'])::text$$));
PERFORM pg_temp.eq('create_alert : c retrouve son alerte avec son rayon et son sport',
  format($$SELECT radius_km || '|' || sport_key FROM public.activity_alerts WHERE id = %L$$, pg_temp.id('alert')), '25|hiking');

PERFORM pg_temp.put('gpx', pg_temp.ok('fixture : c enregistre une trace',
  $$SELECT (public.create_gpx_trace('Trace C', '{"type":"LineString","coordinates":[[6.6,44.9],[6.61,44.91]]}'::jsonb)).id::text$$));
PERFORM pg_temp.ok('rename_gpx_trace : c renomme sa trace', format($$SELECT public.rename_gpx_trace(%L, '  Trace renommée ')::text$$, pg_temp.id('gpx')));
PERFORM pg_temp.eq('rename_gpx_trace : le nom est changé (espaces retirés)', format($$SELECT name FROM public.gpx_traces WHERE id = %L$$, pg_temp.id('gpx')), 'Trace renommée');
PERFORM pg_temp.ok('delete_gpx_trace : c supprime sa trace', format($$SELECT public.delete_gpx_trace(%L)::text$$, pg_temp.id('gpx')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('delete_gpx_trace : la trace est supprimée', format($$SELECT count(*)::text FROM public.gpx_traces WHERE id = %L$$, pg_temp.id('gpx')), '0');

PERFORM pg_temp.fc_act('fav_act', 'd', interval '97 days');
PERFORM pg_temp.as_('a');
PERFORM pg_temp.ok('fixture : a met une sortie en favori', format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('fav_act')));
PERFORM pg_temp.as_('b');
PERFORM pg_temp.ok('remove_favorite : b retire « ce favori » (pas le sien)', format($$SELECT public.remove_favorite('activity', %L)::text$$, pg_temp.id('fav_act')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('remove_favorite : un compte suspendu est refusé', format($$SELECT public.remove_favorite('activity', %L)::text$$, pg_temp.id('fav_act')), '^Operation not permitted$');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('remove_favorite : le favori de a est intact', format($$SELECT count(*)::text FROM public.favorites WHERE owner_id = %L AND activity_id = %L$$, pg_temp.id('a'), pg_temp.id('fav_act')), '1');

-- ═════ 6. Présence et réputation ═════
PERFORM pg_temp.fc_act('rv_act', 'c', interval '-3 hours', 'completed', 'public', true);
PERFORM pg_temp.fc_part('rv_act', 'a', 'accepted', true);
PERFORM pg_temp.fc_part('rv_act', 'b', 'accepted', true);
INSERT INTO public.reputation_votes (voter_id, voted_id, activity_id, badge_key) VALUES
  (pg_temp.id('a'), pg_temp.id('b'), pg_temp.id('rv_act'), 'punctual'),
  (pg_temp.id('c'), pg_temp.id('b'), pg_temp.id('rv_act'), 'punctual');
PERFORM pg_temp.as_('a');
PERFORM pg_temp.ok('revoke_reputation_badge : a retire son vote', format($$SELECT public.revoke_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('b'), pg_temp.id('rv_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('revoke_reputation_badge : seul le vote de a disparaît (celui de c reste)',
  format($$SELECT string_agg(voter_id::text, ',') FROM public.reputation_votes WHERE activity_id = %L AND voted_id = %L$$, pg_temp.id('rv_act'), pg_temp.id('b')), pg_temp.get('c'));

-- ═════ 7. Pro ═════
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('fixture : pro s''inscrit', $$SELECT public.register_as_pro(p_display_name := 'Pro Couverture', p_company_name := 'SARL Test', p_real_name := 'Jean Test',
  p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$$);
PERFORM pg_temp.as_('pro2');
PERFORM pg_temp.ok('fixture : pro2 s''inscrit', $$SELECT public.register_as_pro(p_display_name := 'Pro Deux', p_company_name := 'SARL Deux', p_real_name := 'Paul Test',
  p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$$);
PERFORM pg_temp.as_('cand');
PERFORM pg_temp.ok('fixture : cand s''inscrit (reste en attente)', $$SELECT public.register_as_pro(p_display_name := 'Candidat', p_company_name := 'SARL Cand', p_real_name := 'Luc Test',
  p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$$);
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.ok('fixture : l''admin approuve pro', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pro')));
PERFORM pg_temp.ok('fixture : l''admin approuve pro2', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pro2')));
PERFORM pg_temp.fc_lock(false);

PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('set_pro_pin_icon : le pro choisit l''icône « eau »', $$SELECT public.set_pro_pin_icon('water')::text$$);
PERFORM pg_temp.ok('set_pro_pin_image : le pro pose une image de son dossier', format($$SELECT public.set_pro_pin_image(%L)::text$$, pg_temp.fc_url('pro-photos', 'pro', 'pin.jpg')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('set_pro_pin_icon / set_pro_pin_image : icône et image enregistrées',
  format($$SELECT pin_icon || '|' || (pin_image_url = %L)::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.fc_url('pro-photos', 'pro', 'pin.jpg'), pg_temp.id('pro')), 'water|true');

PERFORM pg_temp.as_('pro');
PERFORM pg_temp.put('off', pg_temp.ok('fixture : le pro crée une offre', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := 'Rando couverture', p_description := 'Description test',
  p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon', p_max_participants := 8, p_price_eur := 50, p_price_unit := 'person')::text$$, pg_temp.id('sport'))));
PERFORM pg_temp.put('off_del', pg_temp.ok('fixture : le pro crée une offre à supprimer', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := 'Offre à supprimer', p_description := 'd',
  p_level := 'x', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'B')::text$$, pg_temp.id('sport'))));
PERFORM pg_temp.ok('update_pro_offering : le pro modifie titre et prix', format($$SELECT public.update_pro_offering(p_offering_id := %L, p_sport_id := %L, p_title := 'Rando <b>modifiée</b>',
  p_description := 'Description test', p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon', p_max_participants := 8,
  p_price_eur := 60, p_price_unit := 'person')::text$$, pg_temp.id('off'), pg_temp.id('sport')));
PERFORM pg_temp.fc_lock(false);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('update_pro_offering : titre et prix enregistrés', format($$SELECT (title LIKE 'Rando %%modifiée%%')::text || '|' || price_eur::int FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('off')), 'true|60');
-- FIN2-1 : le titre et la description d'une offre pro gardent leur HTML (ni create_pro_offering ni
-- update_pro_offering ne nettoient, et pro_offerings n'a pas de trigger strip_html) alors que tout
-- autre texte public l'est (sorties, messages, avis, vitrine, matériel de l'offre) ; la vue
-- pro_offerings_with_coords est lue par le site sans compte.
PERFORM pg_temp.eq('update_pro_offering : le titre d''une offre est nettoyé du HTML', format($$SELECT title FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('off')), 'Rando modifiée', 'FIN2-1');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.put('off_html', pg_temp.ok('create_pro_offering : offre créée avec du HTML dans le titre et la description', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := '<b>Offre</b> balisée', p_description := '<i>Desc</i>',
  p_level := 'x', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'B')::text$$, pg_temp.id('sport'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('create_pro_offering : titre et description d''une offre nettoyés du HTML',
  format($$SELECT title || '|' || description FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('off_html')), 'Offre balisée|Desc', 'FIN2-1');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('delete_pro_offering : le pro supprime une offre sans réservation', format($$SELECT public.delete_pro_offering(%L)::text$$, pg_temp.id('off_del')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('delete_pro_offering : l''offre est supprimée', format($$SELECT count(*)::text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('off_del')), '0');

-- Photos d'offre, de vitrine, communautaires.
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.put('oph1', pg_temp.ok('add_pro_offering_photo : première photo d''offre', format($$SELECT public.add_pro_offering_photo(%L, %L)::text$$, pg_temp.id('off'), pg_temp.fc_url('pro-photos', 'pro', 'o1.jpg'))));
PERFORM pg_temp.put('oph2', pg_temp.ok('add_pro_offering_photo : seconde photo d''offre', format($$SELECT public.add_pro_offering_photo(%L, %L)::text$$, pg_temp.id('off'), pg_temp.fc_url('pro-photos', 'pro', 'o2.jpg'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('add_pro_offering_photo : les photos sont rangées dans l''ordre d''ajout',
  format($$SELECT string_agg(order_index::text, ',' ORDER BY created_at, order_index) FROM public.pro_offering_photos WHERE offering_id = %L$$, pg_temp.id('off')), '0,1');
PERFORM pg_temp.as_('pro2');
PERFORM pg_temp.denied('reorder_pro_offering_photos : un autre pro ne réordonne pas', format($$SELECT public.reorder_pro_offering_photos(%L, ARRAY[%L, %L]::uuid[])::text$$,
  pg_temp.id('off'), pg_temp.id('oph2'), pg_temp.id('oph1')), '^Operation not permitted$');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('reorder_pro_offering_photos : le pro inverse ses photos', format($$SELECT public.reorder_pro_offering_photos(%L, ARRAY[%L, %L]::uuid[])::text$$,
  pg_temp.id('off'), pg_temp.id('oph2'), pg_temp.id('oph1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('reorder_pro_offering_photos : le nouvel ordre est appliqué', format($$SELECT order_index::text FROM public.pro_offering_photos WHERE id = %L$$, pg_temp.id('oph2')), '0');
PERFORM pg_temp.ok('pro_offering_photos_whitelist_columns : réécriture de l''URL sans déverrouillage',
  format($$UPDATE public.pro_offering_photos SET photo_url = 'https://evil.example/x.jpg', order_index = 7 WHERE id = %L$$, pg_temp.id('oph1')));
PERFORM pg_temp.eq('pro_offering_photos_whitelist_columns : URL gardée, rang modifié',
  format($$SELECT (photo_url = %L)::text || '|' || order_index FROM public.pro_offering_photos WHERE id = %L$$, pg_temp.fc_url('pro-photos', 'pro', 'o1.jpg'), pg_temp.id('oph1')), 'true|7');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('remove_pro_offering_photo : le pro retire une photo d''offre', format($$SELECT public.remove_pro_offering_photo(%L)::text$$, pg_temp.id('oph1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('remove_pro_offering_photo : seule cette photo disparaît', format($$SELECT string_agg(id::text, ',') FROM public.pro_offering_photos WHERE offering_id = %L$$, pg_temp.id('off')), pg_temp.get('oph2'));

PERFORM pg_temp.as_('pro');
PERFORM pg_temp.put('ph', pg_temp.ok('fixture : le pro ajoute une photo de vitrine', format($$SELECT public.add_pro_photo(%L)::text$$, pg_temp.fc_url('pro-photos', 'pro', 'v1.jpg'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('pro_profile_photos_whitelist_columns : réécriture de l''URL et du pro sans déverrouillage',
  format($$UPDATE public.pro_profile_photos SET photo_url = 'https://evil.example/x.jpg', pro_id = %L, order_index = 4 WHERE id = %L$$, pg_temp.id('pro2'), pg_temp.id('ph')));
PERFORM pg_temp.eq('pro_profile_photos_whitelist_columns : URL et pro gardés, rang modifié',
  format($$SELECT (photo_url = %L AND pro_id = %L)::text || '|' || order_index FROM public.pro_profile_photos WHERE id = %L$$, pg_temp.fc_url('pro-photos', 'pro', 'v1.jpg'), pg_temp.id('pro'), pg_temp.id('ph')), 'true|4');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('remove_pro_photo : le pro retire sa photo de vitrine', format($$SELECT public.remove_pro_photo(%L)::text$$, pg_temp.id('ph')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('remove_pro_photo : la photo est supprimée', format($$SELECT count(*)::text FROM public.pro_profile_photos WHERE id = %L$$, pg_temp.id('ph')), '0');

PERFORM pg_temp.as_('cli');
PERFORM pg_temp.put('cph', pg_temp.ok('fixture : un membre ajoute une photo communautaire', format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pro'), pg_temp.fc_url('pro-photos', 'cli', 'c1.jpg'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('pro_community_photos_whitelist_columns : réécriture de l''auteur et de l''URL sans déverrouillage',
  format($$UPDATE public.pro_community_photos SET contributor_id = %L, photo_url = 'https://evil.example/x.jpg' WHERE id = %L$$, pg_temp.id('mal'), pg_temp.id('cph')));
PERFORM pg_temp.eq('pro_community_photos_whitelist_columns : auteur et URL gardés',
  format($$SELECT (contributor_id = %L AND photo_url = %L)::text FROM public.pro_community_photos WHERE id = %L$$, pg_temp.id('cli'), pg_temp.fc_url('pro-photos', 'cli', 'c1.jpg'), pg_temp.id('cph')), 'true');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('remove_pro_community_photo : le pro retire la photo communautaire', format($$SELECT public.remove_pro_community_photo(%L)::text$$, pg_temp.id('cph')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('remove_pro_community_photo : la photo est supprimée', format($$SELECT count(*)::text FROM public.pro_community_photos WHERE id = %L$$, pg_temp.id('cph')), '0');

-- Vitrine, offres, créneaux : colonnes figées, horodatage, approbation exigée.
PERFORM pg_temp.ok('pro_profiles_whitelist_columns : réécriture du statut et de la raison sociale sans déverrouillage',
  format($$UPDATE public.pro_profiles SET status = 'rejected', company_name = 'Volée SARL', tagline = 'Libre' WHERE user_id = %L$$, pg_temp.id('pro')));
PERFORM pg_temp.eq('pro_profiles_whitelist_columns : statut et raison sociale gardés, accroche modifiée',
  format($$SELECT status || '|' || company_name || '|' || tagline FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pro')), 'approved|SARL Test|Libre');
PERFORM pg_temp.eq('pro_profiles_touch_updated_at : la vitrine modifiée est horodatée maintenant',
  format($$SELECT (updated_at = now())::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pro')), 'true');
PERFORM pg_temp.ok('pro_offerings_whitelist_columns : réécriture du pro propriétaire sans déverrouillage',
  format($$UPDATE public.pro_offerings SET pro_id = %L, is_demo = true, updated_at = '2020-01-01', level = 'Confirmé' WHERE id = %L$$, pg_temp.id('pro2'), pg_temp.id('off')));
PERFORM pg_temp.eq('pro_offerings_whitelist_columns : propriétaire et démo gardés, niveau modifié',
  format($$SELECT (pro_id = %L)::text || '|' || is_demo::text || '|' || level FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('pro'), pg_temp.id('off')), 'true|false|Confirmé');
PERFORM pg_temp.eq('pro_offerings_touch_updated_at : updated_at ne s''antidate pas',
  format($$SELECT (updated_at = now())::text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('off')), 'true');
PERFORM pg_temp.denied('pro_offerings_require_approved : pas d''offre pour une candidature en attente, même en écriture directe',
  format($$INSERT INTO public.pro_offerings (pro_id, sport_id, title, description, level, location, location_name) VALUES (%L, %L, 'Offre directe', 'd', 'x', ST_SetSRID(ST_MakePoint(6.6, 44.9), 4326)::geography, 'B')$$,
    pg_temp.id('cand'), pg_temp.id('sport')), '^Operation not permitted$');
PERFORM pg_temp.ok('pro_offerings_require_approved : une offre directe pour un pro approuvé passe',
  format($$INSERT INTO public.pro_offerings (pro_id, sport_id, title, description, level, location, location_name) VALUES (%L, %L, 'Offre directe', 'd', 'x', ST_SetSRID(ST_MakePoint(6.6, 44.9), 4326)::geography, 'B')$$,
    pg_temp.id('pro2'), pg_temp.id('sport')));
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('fixture : le pro ouvre deux créneaux', format($$SELECT public.set_pro_availability_bulk(ARRAY[%L, %L]::date[], ARRAY['am', 'am'], true)::text$$, pg_temp.get('d1'), pg_temp.get('d2')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('pro_availabilities_whitelist_columns : déplacement d''un créneau sans déverrouillage',
  format($$UPDATE public.pro_availabilities SET day = day + 30, period = 'pm' WHERE pro_id = %L AND day = %L$$, pg_temp.id('pro'), pg_temp.get('d1')));
PERFORM pg_temp.eq('pro_availabilities_whitelist_columns : le créneau ne bouge pas',
  format($$SELECT count(*)::text FROM public.pro_availabilities WHERE pro_id = %L AND day = %L AND period = 'am'$$, pg_temp.id('pro'), pg_temp.get('d1')), '1');

-- Réservations : manuelle, annulation par le pro, colonnes figées.
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.put('mbk', pg_temp.ok('create_manual_booking : le pro saisit une réservation hors appli',
  format($$SELECT public.create_manual_booking(%L, %L, 'pm', 2, 'Jean <b>Dehors</b>', '0601020304')::text$$, pg_temp.id('off'), pg_temp.get('d2'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('create_manual_booking : réservation acceptée, sans client Junto, nom nettoyé',
  format($$SELECT status || '|' || coalesce(client_id::text, 'null') || '|' || manual_name || '|' || party_size FROM public.bookings WHERE id = %L$$, pg_temp.id('mbk')), 'accepted|null|Jean Dehors|2');
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.put('bk', pg_temp.ok('fixture : un membre réserve un créneau', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, pg_temp.id('off'), pg_temp.get('d1'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('bookings_whitelist_columns : réécriture du client et du jour sans déverrouillage',
  format($$UPDATE public.bookings SET client_id = %L, day = day + 1, party_size = 2 WHERE id = %L$$, pg_temp.id('mal'), pg_temp.id('bk')));
PERFORM pg_temp.eq('bookings_whitelist_columns : client et jour gardés, taille du groupe modifiée',
  format($$SELECT (client_id = %L)::text || '|' || (day = %L::date)::text || '|' || party_size FROM public.bookings WHERE id = %L$$, pg_temp.id('cli'), pg_temp.get('d1'), pg_temp.id('bk')), 'true|true|2');
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('cancel_booking_pro : le client n''utilise pas l''annulation côté pro', format($$SELECT public.cancel_booking_pro(%L)::text$$, pg_temp.id('bk')), '^Operation not permitted$');
PERFORM pg_temp.as_('pro2');
PERFORM pg_temp.denied('cancel_booking_pro : un autre pro n''annule pas', format($$SELECT public.cancel_booking_pro(%L)::text$$, pg_temp.id('bk')), '^Operation not permitted$');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('cancel_booking_pro : le pro annule la demande', format($$SELECT public.cancel_booking_pro(%L)::text$$, pg_temp.id('bk')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('cancel_booking_pro : la réservation passe « annulée par le pro »', format($$SELECT status FROM public.bookings WHERE id = %L$$, pg_temp.id('bk')), 'cancelled_pro');

-- Avis sur la vitrine et sur l'offre.
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.put('rv', pg_temp.ok('fixture : un membre laisse un avis sur le pro', format($$SELECT public.create_pro_review(%L, 4::smallint, 'Bien')::text$$, pg_temp.id('pro'))));
PERFORM pg_temp.ok('update_pro_review : l''auteur change sa note', format($$SELECT public.update_pro_review(%L, 2::smallint, 'Moyen <b>finalement</b>')::text$$, pg_temp.id('rv')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('update_pro_review : note et texte (nettoyé) modifiés', format($$SELECT rating || '|' || body FROM public.pro_reviews WHERE id = %L$$, pg_temp.id('rv')), '2|Moyen finalement');
PERFORM pg_temp.ok('pro_reviews_whitelist_columns : réécriture de la réponse du pro sans déverrouillage',
  format($$UPDATE public.pro_reviews SET pro_reply = 'Fausse réponse', reviewer_id = %L, updated_at = '2020-01-01', rating = 3 WHERE id = %L$$, pg_temp.id('mal'), pg_temp.id('rv')));
PERFORM pg_temp.eq('pro_reviews_whitelist_columns : réponse et auteur gardés, note modifiée',
  format($$SELECT coalesce(pro_reply, 'null') || '|' || (reviewer_id = %L)::text || '|' || rating FROM public.pro_reviews WHERE id = %L$$, pg_temp.id('cli'), pg_temp.id('rv')), 'null|true|3');
PERFORM pg_temp.eq('reviews_touch_updated_at : un avis modifié est horodaté maintenant',
  format($$SELECT (updated_at = now())::text FROM public.pro_reviews WHERE id = %L$$, pg_temp.id('rv')), 'true');
PERFORM pg_temp.denied('pro_reviews_require_approved : pas d''avis sur une candidature en attente, même en écriture directe',
  format($$INSERT INTO public.pro_reviews (pro_id, reviewer_id, rating) VALUES (%L, %L, 5)$$, pg_temp.id('cand'), pg_temp.id('cli')), '^Operation not permitted$');
PERFORM pg_temp.ok('pro_reviews_require_approved : un avis direct sur un pro approuvé passe',
  format($$INSERT INTO public.pro_reviews (pro_id, reviewer_id, rating) VALUES (%L, %L, 5)$$, pg_temp.id('pro2'), pg_temp.id('cli')));
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.ok('delete_pro_review : l''auteur supprime son avis', format($$SELECT public.delete_pro_review(%L)::text$$, pg_temp.id('rv')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('delete_pro_review : l''avis est supprimé', format($$SELECT count(*)::text FROM public.pro_reviews WHERE id = %L$$, pg_temp.id('rv')), '0');

PERFORM pg_temp.as_('cli');
PERFORM pg_temp.put('orv', pg_temp.ok('create_offering_review : un membre laisse un avis sur l''offre', format($$SELECT public.create_offering_review(%L, 5::smallint, '<b>Top</b>')::text$$, pg_temp.id('off'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('create_offering_review : avis enregistré au nom du membre, texte nettoyé',
  format($$SELECT rating || '|' || body || '|' || (reviewer_id = %L)::text FROM public.offering_reviews WHERE id = %L$$, pg_temp.id('cli'), pg_temp.id('orv')), '5|Top|true');
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.ok('update_offering_review : l''auteur change sa note', format($$SELECT public.update_offering_review(%L, 3::smallint, 'Correct')::text$$, pg_temp.id('orv')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('update_offering_review : note et texte modifiés', format($$SELECT rating || '|' || body FROM public.offering_reviews WHERE id = %L$$, pg_temp.id('orv')), '3|Correct');
PERFORM pg_temp.ok('offering_reviews_whitelist_columns : réécriture de la réponse du pro sans déverrouillage',
  format($$UPDATE public.offering_reviews SET pro_reply = 'Fausse réponse', offering_id = gen_random_uuid(), rating = 4 WHERE id = %L$$, pg_temp.id('orv')));
PERFORM pg_temp.eq('offering_reviews_whitelist_columns : réponse et offre gardées, note modifiée',
  format($$SELECT coalesce(pro_reply, 'null') || '|' || (offering_id = %L)::text || '|' || rating FROM public.offering_reviews WHERE id = %L$$, pg_temp.id('off'), pg_temp.id('orv')), 'null|true|4');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('reply_to_offering_review : le pro répond à l''avis', format($$SELECT public.reply_to_offering_review(%L, 'Merci <b>beaucoup</b>')::text$$, pg_temp.id('orv')));
PERFORM pg_temp.fc_lock(false);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('reply_to_offering_review : la réponse est enregistrée, nettoyée et datée',
  format($$SELECT pro_reply || '|' || (pro_reply_at IS NOT NULL)::text FROM public.offering_reviews WHERE id = %L$$, pg_temp.id('orv')), 'Merci beaucoup|true');
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.ok('delete_offering_review : l''auteur supprime son avis', format($$SELECT public.delete_offering_review(%L)::text$$, pg_temp.id('orv')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('delete_offering_review : l''avis est supprimé', format($$SELECT count(*)::text FROM public.offering_reviews WHERE id = %L$$, pg_temp.id('orv')), '0');

-- ═════ 8. Tâche planifiée minute (en dernier : elle garde son verrou jusqu'à la fin du bloc) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.fc_act('tr_act', 'c', interval '-1 hour');
PERFORM pg_temp.fc_part('tr_act', 'a');
PERFORM pg_temp.eq('check_activity_transitions : une sortie publiée et commencée passe « en cours »', $$SELECT pg_temp.fc_transitions('tr_act')$$, 'in_progress');
