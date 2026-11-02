-- Domaine 21 — fonctions récentes sans test dédié (2026-11-02).
-- 00532 nettoyage des messages et des avis · 00533 adresses de prise en charge · 00535 qui voit
-- quelle sortie · 00541 effets d'un blocage · 00549 textes serveur « askandgo » (push + suppression
-- de compte) · 00570-00571 étapes d'une trace (bibliothèque, sortie, partage) · 00572-00573 rappel
-- de fin de sortie longue.
--
-- Les appels HTTP (push) sont seulement mis en file dans net.http_request_queue : la transaction est
-- toujours annulée, rien ne part. On lit la file, on n'appelle jamais net.* soi-même.

-- ───── Helpers locaux ─────
-- Sortie insérée directement (en 'db') : dates libres, statut libre.
EXECUTE $p$CREATE FUNCTION pg_temp.dv_act(p_creator text, p_title text, p_starts timestamptz, p_duration interval,
    p_visibility text, p_status text, p_presence boolean DEFAULT false, p_lng float8 DEFAULT -137.5) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid;
  BEGIN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting, starts_at, duration, visibility, status, requires_presence)
    VALUES (pg_temp.id(p_creator), (SELECT id FROM public.sports WHERE key = 'hiking'), p_title, 'Tous niveaux', 8,
            extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, -44.5), 4326)::extensions.geography, p_starts, p_duration, p_visibility, p_status, p_presence)
    RETURNING id INTO v;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    RETURN v;
  END $b$$p$;
-- Participation insérée directement.
EXECUTE $p$CREATE FUNCTION pg_temp.dv_part(p_act uuid, p_user text, p_status text, p_present boolean DEFAULT NULL) RETURNS void
  LANGUAGE sql SECURITY DEFINER AS $b$
  INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, created_at)
  VALUES (p_act, pg_temp.id(p_user), p_status, p_present, now() - interval '2 days') $b$$p$;
-- Fil DM actif entre deux comptes (fixture, comme ms_connect de 04).
EXECUTE $p$CREATE FUNCTION pg_temp.dv_connect(a text, b text) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
    VALUES ('dm', LEAST(pg_temp.id(a), pg_temp.id(b)), GREATEST(pg_temp.id(a), pg_temp.id(b)), pg_temp.id(a),
            'active', 'profile', now(), now())
    RETURNING id INTO v;
    PERFORM pg_temp.put('dm_' || a || '_' || b, v::text);
    RETURN v;
  END $b$$p$;
-- Nombre de notifications d'un type pour un compte et une sortie.
EXECUTE $p$CREATE FUNCTION pg_temp.dv_notifs(p_user text, p_type text, p_act text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT count(*)::text FROM public.notifications
  WHERE user_id = pg_temp.id(p_user) AND type = p_type AND data->>'activity_id' = pg_temp.get(p_act) $b$$p$;
-- Corps (jsonb) du push en file qui contient un marqueur.
EXECUTE $p$CREATE FUNCTION pg_temp.dv_push(p_mark text) RETURNS jsonb
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT convert_from(body, 'UTF8')::jsonb FROM net.http_request_queue
  WHERE convert_from(body, 'UTF8') LIKE '%' || p_mark || '%' ORDER BY id DESC LIMIT 1 $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.user('org', 'tos');      -- organisatrice
PERFORM pg_temp.user('bob', 'tos');
PERFORM pg_temp.user('cat', 'tos');
PERFORM pg_temp.user('dan', 'tos');
PERFORM pg_temp.user('eve', 'tos');      -- inconnue
PERFORM pg_temp.user('sus', 'tos,suspended');
PERFORM pg_temp.user('pro', 'tos');
PERFORM pg_temp.user('adm', 'tos,admin');
PERFORM pg_temp.as_('db');
UPDATE public.users SET display_name = 'Bob Test' WHERE id = pg_temp.id('bob');
UPDATE public.users SET display_name = 'Orga Test' WHERE id = pg_temp.id('org');
PERFORM pg_temp.put('sport', (SELECT id::text FROM public.sports WHERE key = 'hiking'));

-- ═════ 00532 — Messages et avis : HTML et caractères invisibles retirés ═════
-- Déclencheurs messages_strip_html (INSERT, UPDATE OF content) et pro_reviews / offering_reviews_strip_html.
PERFORM pg_temp.dv_connect('bob', 'cat');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.put('m_inv', pg_temp.ok('bob envoie un message avec HTML, inversion du sens et espace invisible',
  format($$SELECT public.send_message(%L, E'Salut <b>Cat</b> ‮esrever​ fin﻿')::text$$, pg_temp.id('dm_bob_cat'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le message est enregistré sans HTML ni caractère invisible',
  format($$SELECT content FROM public.messages WHERE id = %L$$, pg_temp.get('m_inv')), 'Salut Cat esrever fin');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob modifie son message en y glissant un U+2066 (isolat) et une balise',
  format($$SELECT public.edit_message(%L, E'Corrigé ⁦<i>ici</i>⁩')::text$$, pg_temp.get('m_inv')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la modification est nettoyée elle aussi (déclencheur sur UPDATE OF content)',
  format($$SELECT content FROM public.messages WHERE id = %L$$, pg_temp.get('m_inv')), 'Corrigé ici');
PERFORM pg_temp.eq('un écrivain direct (hors RPC) passe aussi par le nettoyage',
  format($$INSERT INTO public.messages (conversation_id, sender_id, content) VALUES (%L, %L, E'<u>Ok</u>­‏!') RETURNING content$$,
    pg_temp.id('dm_bob_cat'), pg_temp.id('cat')), 'Ok!');
PERFORM pg_temp.eq('accents, emoji et liant U+200D d''un emoji composé restent intacts',
  format($$INSERT INTO public.messages (conversation_id, sender_id, content) VALUES (%L, %L, E'Été 🏔️ \U0001F468‍\U0001F469') RETURNING (content = E'Été 🏔️ \U0001F468‍\U0001F469')::text$$,
    pg_temp.id('dm_bob_cat'), pg_temp.id('cat')), 'true');

-- Avis : pro approuvé + offre.
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('le pro s''inscrit', $$SELECT public.register_as_pro(p_display_name := 'Guide Divers', p_company_name := 'SARL Test', p_real_name := 'Jean Test',
  p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$$);
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.ok('l''admin approuve le pro', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pro')));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.put('off', pg_temp.ok('le pro crée une offre', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := 'Rando divers',
  p_description := 'Description test', p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon',
  p_max_participants := 8, p_price_eur := 50, p_price_unit := 'person')::text$$, pg_temp.id('sport'))));
-- Depuis l'exigence de réservation (junto.review_requires_booking), on écrit les avis en 'db' :
-- ce sont les déclencheurs (tout écrivain confondu) qui sont testés ici, les RPC d'avis le sont en 06/16.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('rv_pro', pg_temp.ok('un avis sur le pro avec HTML et inversion du sens',
  format($$INSERT INTO public.pro_reviews (pro_id, reviewer_id, rating, body) VALUES (%L, %L, 4, E'<b>Super</b> gu\u202Eide\u200B !') RETURNING id::text$$, pg_temp.id('pro'), pg_temp.id('bob'))));
PERFORM pg_temp.put('rv_off', pg_temp.ok('un avis sur l''offre avec caractères invisibles',
  format($$INSERT INTO public.offering_reviews (offering_id, reviewer_id, rating, body) VALUES (%L, %L, 5, E'Top\u2060 <i>sortie</i>\u200E') RETURNING id::text$$, pg_temp.get('off'), pg_temp.id('bob'))));
PERFORM pg_temp.eq('avis sur le pro : texte nettoyé',
  format($$SELECT body FROM public.pro_reviews WHERE id = %L$$, pg_temp.get('rv_pro')), 'Super guide !');
PERFORM pg_temp.eq('avis sur l''offre : texte nettoyé',
  format($$SELECT body FROM public.offering_reviews WHERE id = %L$$, pg_temp.get('rv_off')), 'Top sortie');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('le pro répond à l''avis avec une balise et un U+202D (RPC)',
  format($$SELECT public.reply_to_pro_review(%L, E'Merci <b>Bob</b>\u202D')::text$$, pg_temp.get('rv_pro')));
PERFORM pg_temp.ok('le pro répond à l''avis d''offre avec un BOM (RPC)',
  format($$SELECT public.reply_to_offering_review(%L, E'\uFEFFÀ bientôt')::text$$, pg_temp.get('rv_off')));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('réponse du pro (avis sur le pro) nettoyée',
  format($$SELECT pro_reply FROM public.pro_reviews WHERE id = %L$$, pg_temp.get('rv_pro')), 'Merci Bob');
PERFORM pg_temp.eq('réponse du pro (avis sur l''offre) nettoyée',
  format($$SELECT pro_reply FROM public.offering_reviews WHERE id = %L$$, pg_temp.get('rv_off')), 'À bientôt');

-- ═════ 00533 — Les adresses de prise en charge ne survivent pas à la demande ═════
-- private.seat_request_purge_details (BEFORE UPDATE OF status) + fin de sortie
-- (on_activity_finished_expire_seat_requests) pour les demandes acceptées.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('sr_act', pg_temp.dv_act('org', 'Sortie covoit', now() + interval '170 days', interval '3 hours', 'public', 'published', false, -137.6)::text);
PERFORM pg_temp.dv_part(pg_temp.id('sr_act'), 'org', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('sr_act'), 'dan', 'accepted');   -- conducteur
PERFORM pg_temp.dv_part(pg_temp.id('sr_act'), 'bob', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('sr_act'), 'cat', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('sr_act'), 'eve', 'accepted');
PERFORM pg_temp.as_('dan');
PERFORM pg_temp.ok('le conducteur propose 3 places', format($$SELECT public.set_participation_transport(%L, 'car', 3::smallint, 'Gap', NULL, 44.56, 6.08, 'Gap')::text$$, pg_temp.id('sr_act')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob demande une place (adresse, message, heure)',
  format($$SELECT public.request_seat(%1$L, %2$L, '1 rue des Écrins', 'Je serai devant', (SELECT starts_at - interval '1 hour' FROM public.activities WHERE id = %1$L))::text$$, pg_temp.id('sr_act'), pg_temp.id('dan')));
PERFORM pg_temp.as_('cat');
PERFORM pg_temp.ok('cat demande une place', format($$SELECT public.request_seat(%1$L, %2$L, '2 rue du Pelvoux', 'Merci', (SELECT starts_at - interval '1 hour' FROM public.activities WHERE id = %1$L))::text$$, pg_temp.id('sr_act'), pg_temp.id('dan')));
PERFORM pg_temp.as_('eve');
PERFORM pg_temp.ok('eve demande une place', format($$SELECT public.request_seat(%1$L, %2$L, '3 place du Temple', 'Coucou', (SELECT starts_at - interval '1 hour' FROM public.activities WHERE id = %1$L))::text$$, pg_temp.id('sr_act'), pg_temp.id('dan')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('sr_bob', (SELECT id::text FROM public.seat_requests WHERE requester_id = pg_temp.id('bob') AND activity_id = pg_temp.id('sr_act')));
PERFORM pg_temp.put('sr_cat', (SELECT id::text FROM public.seat_requests WHERE requester_id = pg_temp.id('cat') AND activity_id = pg_temp.id('sr_act')));
PERFORM pg_temp.put('sr_eve', (SELECT id::text FROM public.seat_requests WHERE requester_id = pg_temp.id('eve') AND activity_id = pg_temp.id('sr_act')));
PERFORM pg_temp.as_('dan');
PERFORM pg_temp.ok('le conducteur accepte bob', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.get('sr_bob')));
PERFORM pg_temp.as_('cat');
PERFORM pg_temp.ok('cat retire sa demande en attente', format($$SELECT public.cancel_pending_seat_request(%L)::text$$, pg_temp.get('sr_cat')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('demande retirée : adresse, message et heure effacés',
  format($$SELECT status || '|' || (pickup_from IS NULL AND message IS NULL AND requested_pickup_at IS NULL)::text FROM public.seat_requests WHERE id = %L$$, pg_temp.get('sr_cat')), 'cancelled|true');
PERFORM pg_temp.eq('demande acceptée : les détails restent tant que la sortie n''est pas finie',
  format($$SELECT status || '|' || pickup_from || '|' || message || '|' || (requested_pickup_at IS NOT NULL)::text FROM public.seat_requests WHERE id = %L$$, pg_temp.get('sr_bob')),
  'accepted|1 rue des Écrins|Je serai devant|true');
PERFORM pg_temp.ok('une écriture du statut à l''identique…', format($$UPDATE public.seat_requests SET status = status WHERE id = %L$$, pg_temp.get('sr_bob')));
PERFORM pg_temp.eq('… n''efface rien (seul un changement de statut purge)',
  format($$SELECT coalesce(pickup_from, 'effacée') FROM public.seat_requests WHERE id = %L$$, pg_temp.get('sr_bob')), '1 rue des Écrins');
PERFORM pg_temp.eq('le déclencheur n''est pas appelable par un client',
  $$SELECT (has_function_privilege('authenticated', 'private.seat_request_purge_details()', 'EXECUTE')
         OR has_function_privilege('anon', 'private.seat_request_purge_details()', 'EXECUTE'))::text$$, 'false');
-- La sortie se termine.
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET status = 'completed' WHERE id = pg_temp.id('sr_act');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('fin de sortie : la demande encore en attente expire et perd ses détails',
  format($$SELECT status || '|' || (pickup_from IS NULL AND message IS NULL AND requested_pickup_at IS NULL)::text FROM public.seat_requests WHERE id = %L$$, pg_temp.get('sr_eve')), 'expired|true');
PERFORM pg_temp.eq('fin de sortie : la demande acceptée reste acceptée mais perd ses détails',
  format($$SELECT status || '|' || (pickup_from IS NULL AND message IS NULL AND requested_pickup_at IS NULL)::text FROM public.seat_requests WHERE id = %L$$, pg_temp.get('sr_bob')), 'accepted|true');

-- ═════ 00535 — private.can_see_activity : les règles de lecture d'une sortie ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('cs_pub', pg_temp.dv_act('org', 'Publique CS', now() + interval '171 days', interval '3 hours', 'public', 'published', false, -137.7)::text);
PERFORM pg_temp.put('cs_appr', pg_temp.dv_act('org', 'Sur demande CS', now() + interval '171 days', interval '3 hours', 'approval', 'published', false, -137.7)::text);
PERFORM pg_temp.put('cs_done', pg_temp.dv_act('org', 'Publique finie CS', now() - interval '3 days', interval '3 hours', 'public', 'completed', false, -137.7)::text);
PERFORM pg_temp.put('cs_del', pg_temp.dv_act('org', 'Publique supprimée CS', now() + interval '171 days', interval '3 hours', 'public', 'published', false, -137.7)::text);
PERFORM pg_temp.put('cs_priv', pg_temp.dv_act('org', 'Privée CS', now() + interval '171 days', interval '3 hours', 'private_link', 'published', false, -137.7)::text);
PERFORM pg_temp.put('cs_susp', pg_temp.dv_act('sus', 'Publique d''un suspendu', now() + interval '171 days', interval '3 hours', 'public', 'published', false, -137.7)::text);
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET deleted_at = now() WHERE id = pg_temp.id('cs_del');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.dv_part(pg_temp.id('cs_priv'), 'bob', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('cs_priv'), 'cat', 'pending');
PERFORM pg_temp.dv_part(pg_temp.id('cs_priv'), 'dan', 'invited');
PERFORM pg_temp.dv_part(pg_temp.id('cs_done'), 'bob', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('cs_appr'), 'cat', 'refused');
PERFORM pg_temp.eq('l''organisatrice voit sa sortie privée', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_priv'), pg_temp.id('org')), 'true');
PERFORM pg_temp.eq('un participant accepté voit la sortie privée', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_priv'), pg_temp.id('bob')), 'true');
PERFORM pg_temp.eq('une demande en attente voit la sortie privée', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_priv'), pg_temp.id('cat')), 'true');
PERFORM pg_temp.eq('une personne invitée voit la sortie privée', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_priv'), pg_temp.id('dan')), 'true');
PERFORM pg_temp.eq('une inconnue ne voit pas la sortie privée', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_priv'), pg_temp.id('eve')), 'false');
PERFORM pg_temp.eq('une inconnue voit une sortie publique publiée', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_pub'), pg_temp.id('eve')), 'true');
PERFORM pg_temp.eq('une inconnue voit une sortie sur demande publiée', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_appr'), pg_temp.id('eve')), 'true');
PERFORM pg_temp.eq('une demande refusée ne rouvre pas la sortie… mais elle reste publique : visible', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_appr'), pg_temp.id('cat')), 'true');
PERFORM pg_temp.eq('une sortie publique terminée n''est plus visible d''une inconnue', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_done'), pg_temp.id('eve')), 'false');
PERFORM pg_temp.eq('… mais l''est toujours pour qui y a participé', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_done'), pg_temp.id('bob')), 'true');
PERFORM pg_temp.eq('une sortie publique supprimée n''est plus visible d''une inconnue', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_del'), pg_temp.id('eve')), 'false');
PERFORM pg_temp.eq('la sortie publique d''un compte suspendu n''est pas visible', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_susp'), pg_temp.id('eve')), 'false');
PERFORM pg_temp.eq('un identifiant inventé : non', format($$SELECT private.can_see_activity(%L, %L)::text$$, gen_random_uuid(), pg_temp.id('eve')), 'false');
-- Accès privé par partage de l'organisatrice (private_activity_access).
PERFORM pg_temp.dv_connect('org', 'eve');
PERFORM pg_temp.as_('org');
PERFORM pg_temp.ok('l''organisatrice partage sa sortie privée avec eve', format($$SELECT public.share_activity_message(%L, %L)::text$$, pg_temp.id('dm_org_eve'), pg_temp.id('cs_priv')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('partagée par l''organisatrice, la sortie privée devient visible pour eve', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_priv'), pg_temp.id('eve')), 'true');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('un client n''appelle pas can_see_activity (oracle)', format($$SELECT private.can_see_activity(%L, %L)::text$$, pg_temp.id('cs_priv'), pg_temp.id('org')), 'permission denied');

-- ═════ 00541 (+ 00522-00523) — cascade_block_cleanup : effets d'un blocage ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('b_org', 'tos'); PERFORM pg_temp.user('b_req', 'tos'); PERFORM pg_temp.user('b_req2', 'tos');
PERFORM pg_temp.user('b_mem', 'tos'); PERFORM pg_temp.user('b_req3', 'tos'); PERFORM pg_temp.user('b_drv', 'tos');
UPDATE public.users SET display_name = 'Membre Bloqué' WHERE id = pg_temp.id('b_mem');
UPDATE public.users SET display_name = 'Demandeuse Trois' WHERE id = pg_temp.id('b_req3');
PERFORM pg_temp.put('bk1', pg_temp.dv_act('b_org', 'Sortie bloc 1', now() + interval '172 days', interval '3 hours', 'approval', 'published', false, -137.8)::text);
PERFORM pg_temp.put('bk2', pg_temp.dv_act('b_org', 'Sortie bloc 2', now() + interval '173 days', interval '3 hours', 'approval', 'published', false, -137.8)::text);
PERFORM pg_temp.put('bk3', pg_temp.dv_act('b_drv', 'Sortie bloc 3 (autre orga)', now() + interval '174 days', interval '3 hours', 'approval', 'published', false, -137.8)::text);
PERFORM pg_temp.dv_part(pg_temp.id('bk1'), 'b_org', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('bk1'), 'b_mem', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('bk1'), 'b_req', 'pending');
PERFORM pg_temp.dv_part(pg_temp.id('bk1'), 'b_req2', 'pending');
PERFORM pg_temp.dv_part(pg_temp.id('bk1'), 'b_req3', 'pending');
PERFORM pg_temp.dv_part(pg_temp.id('bk2'), 'b_org', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('bk2'), 'b_req', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('bk3'), 'b_drv', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('bk3'), 'b_req', 'pending');
-- 1. L'organisatrice bloque une demandeuse : demande refusée (sa décision), l'acceptée ailleurs reste.
PERFORM pg_temp.as_('b_org');
PERFORM pg_temp.ok('l''organisatrice bloque une demandeuse', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('b_org'), pg_temp.id('b_req')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('sa demande en attente est refusée (avec la date du refus)',
  format($$SELECT status || '|' || (refused_at IS NOT NULL)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('bk1'), pg_temp.id('b_req')), 'refused|true');
PERFORM pg_temp.eq('sa place déjà acceptée sur une autre sortie de l''organisatrice n''est pas touchée',
  format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('bk2'), pg_temp.id('b_req')), 'accepted');
PERFORM pg_temp.eq('sa demande chez un autre organisateur n''est pas touchée',
  format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('bk3'), pg_temp.id('b_req')), 'pending');
PERFORM pg_temp.eq('partie au blocage, l''organisatrice ne reçoit pas d''avis « demande retirée »',
  $$SELECT pg_temp.dv_notifs('b_org', 'join_request_blocked', 'bk1')$$, '0');
-- 2. La demandeuse bloque l'organisatrice : retrait, pas un refus (00541).
PERFORM pg_temp.as_('b_req2');
PERFORM pg_temp.ok('une demandeuse bloque l''organisatrice', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('b_req2'), pg_temp.id('b_org')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('sa demande est retirée, sans date de refus',
  format($$SELECT status || '|' || (refused_at IS NULL)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('bk1'), pg_temp.id('b_req2')), 'withdrawn|true');
-- 3. Une demandeuse bloque un membre accepté : retrait + avis à l'organisatrice, sans dire qui.
PERFORM pg_temp.as_('b_req3');
PERFORM pg_temp.ok('une demandeuse bloque un membre accepté', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('b_req3'), pg_temp.id('b_mem')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('sa demande est retirée',
  format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('bk1'), pg_temp.id('b_req3')), 'withdrawn');
PERFORM pg_temp.eq('l''organisatrice reçoit un avis « demande retirée »', $$SELECT pg_temp.dv_notifs('b_org', 'join_request_blocked', 'bk1')$$, '1');
PERFORM pg_temp.eq('l''avis ne nomme pas le membre bloqué',
  format($$SELECT (body NOT LIKE '%%' || coalesce((SELECT display_name FROM public.users WHERE id = %L), '§§') || '%%' AND data::text NOT LIKE '%%' || %L || '%%')::text
           FROM public.notifications WHERE user_id = %L AND type = 'join_request_blocked'$$, pg_temp.id('b_mem'), pg_temp.get('b_mem'), pg_temp.id('b_org')), 'true');
PERFORM pg_temp.eq('le membre accepté garde sa place', format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('bk1'), pg_temp.id('b_mem')), 'accepted');
-- 4. Covoiturage : demandes en attente et acceptées annulées dans les deux sens.
PERFORM pg_temp.dv_part(pg_temp.id('bk3'), 'b_mem', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('bk3'), 'b_req2', 'accepted');
PERFORM pg_temp.as_('b_drv');
PERFORM pg_temp.ok('le conducteur propose des places', format($$SELECT public.set_participation_transport(%L, 'car', 3::smallint, 'Gap', NULL, 44.56, 6.08, 'Gap')::text$$, pg_temp.id('bk3')));
PERFORM pg_temp.as_('b_mem');
PERFORM pg_temp.ok('un passager demande une place', format($$SELECT public.request_seat(%L, %L, '5 rue A')::text$$, pg_temp.id('bk3'), pg_temp.id('b_drv')));
PERFORM pg_temp.as_('b_req2');
PERFORM pg_temp.ok('une passagère demande une place', format($$SELECT public.request_seat(%L, %L, '6 rue B')::text$$, pg_temp.id('bk3'), pg_temp.id('b_drv')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('bs_mem', (SELECT id::text FROM public.seat_requests WHERE requester_id = pg_temp.id('b_mem') AND activity_id = pg_temp.id('bk3')));
PERFORM pg_temp.put('bs_req2', (SELECT id::text FROM public.seat_requests WHERE requester_id = pg_temp.id('b_req2') AND activity_id = pg_temp.id('bk3')));
PERFORM pg_temp.as_('b_drv');
PERFORM pg_temp.ok('le conducteur accepte la passagère', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.get('bs_req2')));
PERFORM pg_temp.ok('le conducteur bloque le passager en attente', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('b_drv'), pg_temp.id('b_mem')));
PERFORM pg_temp.as_('b_req2');
PERFORM pg_temp.ok('la passagère acceptée bloque le conducteur', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('b_req2'), pg_temp.id('b_drv')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('conducteur → passager : la demande en attente est annulée',
  format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.get('bs_mem')), 'cancelled');
PERFORM pg_temp.eq('passagère → conducteur : la place acceptée est annulée',
  format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.get('bs_req2')), 'cancelled');

-- ═════ 00549 — Textes serveur : « askandgo » (push de message, suppression de compte) ═════
-- request_seat laisse junto.skip_message_push actif pour la fin de la transaction : on le remet.
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.skip_message_push', 'false', true);
PERFORM pg_temp.eq('prérequis : secret push et adresse du projet présents (sinon aucun push en file)',
  $$SELECT (EXISTS (SELECT 1 FROM public.app_config WHERE name = 'push_webhook_secret') AND private.project_url() IS NOT NULL)::text$$, 'true');
PERFORM pg_temp.dv_connect('org', 'bob');
-- Message système (sans auteur) dans un DM.
PERFORM pg_temp.ok('un message système (sans auteur) dans un DM',
  format($$INSERT INTO public.messages (conversation_id, sender_id, content) VALUES (%L, NULL, 'Note DVMARK1')$$, pg_temp.id('dm_org_bob')));
PERFORM pg_temp.eq('push sans auteur : titre « askandgo »', $$SELECT pg_temp.dv_push('DVMARK1')->>'title'$$, 'askandgo');
PERFORM pg_temp.eq('push sans auteur : nom « askandgo » dans les paramètres traduits, variante dm',
  $$SELECT (pg_temp.dv_push('DVMARK1')->'data'->'params'->>'name') || '|' || (pg_temp.dv_push('DVMARK1')->'data'->>'variant')$$, 'askandgo|dm');
PERFORM pg_temp.eq('push : les deux membres du DM sont destinataires',
  format($$SELECT (SELECT array_agg(x ORDER BY x) FROM jsonb_array_elements_text(pg_temp.dv_push('DVMARK1')->'user_ids') x) = (SELECT array_agg(x ORDER BY x) FROM unnest(ARRAY[%L, %L]) x)$$,
    pg_temp.get('org'), pg_temp.get('bob'))::text, 'true');
PERFORM pg_temp.eq('aucun texte serveur de push ne dit plus « Junto »',
  $$SELECT count(*)::text FROM net.http_request_queue WHERE convert_from(body, 'UTF8') LIKE '%DVMARK%' AND convert_from(body, 'UTF8') LIKE '%Junto%'$$, '0');
-- Auteur nommé dans un DM.
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob écrit à l''organisatrice', format($$SELECT public.send_message(%L, 'Salut DVMARK2')::text$$, pg_temp.id('dm_org_bob')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('push d''un auteur nommé : son nom en titre, seule l''organisatrice destinataire',
  format($$SELECT (pg_temp.dv_push('DVMARK2')->>'title') || '|' || (pg_temp.dv_push('DVMARK2')->'user_ids')::text$$), 'Bob Test|["' || pg_temp.get('org') || '"]');
-- Fil d'une sortie : « askandgo · titre » pour un message système.
PERFORM pg_temp.put('ps_act', pg_temp.dv_act('org', 'Sortie push', now() + interval '175 days', interval '3 hours', 'public', 'published', false, -137.9)::text);
PERFORM pg_temp.dv_part(pg_temp.id('ps_act'), 'org', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('ps_act'), 'bob', 'accepted');
PERFORM pg_temp.put('ps_conv', (SELECT id::text FROM public.conversations WHERE activity_id = pg_temp.id('ps_act')));
PERFORM pg_temp.ok('un message système dans le fil de la sortie',
  format($$INSERT INTO public.messages (conversation_id, sender_id, content) VALUES (%L, NULL, 'Info DVMARK3')$$, pg_temp.get('ps_conv')));
PERFORM pg_temp.eq('push du fil sans auteur : « askandgo · titre », activity_id présent',
  format($$SELECT (pg_temp.dv_push('DVMARK3')->>'title') || '|' || (pg_temp.dv_push('DVMARK3')->'data'->>'activity_id' = %L)::text$$, pg_temp.get('ps_act')),
  'askandgo · Sortie push|true');
-- Suppression du compte d'une organisatrice : l'avis aux participants dit askandgo.
PERFORM pg_temp.user('gone', 'tos');
PERFORM pg_temp.put('gone_act', pg_temp.dv_act('gone', 'Sortie orpheline', now() + interval '176 days', interval '3 hours', 'public', 'published', false, -137.9)::text);
PERFORM pg_temp.dv_part(pg_temp.id('gone_act'), 'gone', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('gone_act'), 'cat', 'accepted');
PERFORM pg_temp.ok('l''organisatrice efface son compte (fonction delete-account, rôle service)', format($$SELECT public.delete_account_as(%L)::text$$, pg_temp.id('gone')));
PERFORM pg_temp.eq('le participant est prévenu : « l''organisateur a quitté askandgo »',
  format($$SELECT body FROM public.notifications WHERE user_id = %L AND type = 'activity_cancelled' AND data->>'activity_id' = %L$$, pg_temp.id('cat'), pg_temp.get('gone_act')),
  '« Sortie orpheline » — l''organisateur a quitté askandgo');
PERFORM pg_temp.eq('aucune fonction ne garde le nom Junto dans un texte destiné aux comptes (push / suppression)',
  $$SELECT count(*)::text FROM pg_proc WHERE proname IN ('broadcast_and_push_message', 'delete_own_account') AND prosrc ~ '''[^'']*Junto'$$, '0');

-- ═════ 00570-00571 — Étapes d'une trace (waypoints) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('wp_line', '{"type":"LineString","coordinates":[[6.6,44.9,1200],[6.61,44.91,1300]]}');
PERFORM pg_temp.put('wp_two', '[{"lng":6.605,"lat":44.905,"kind":"refuge","name":"Refuge des Bans"},{"lng":6.61,"lat":44.91,"kind":"water"}]');
-- Bibliothèque : création avec et sans étapes.
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.put('gpx', pg_temp.ok('bob enregistre une trace dans sa bibliothèque',
  format($$SELECT id::text FROM public.create_gpx_trace('Boucle', %L::jsonb)$$, pg_temp.get('wp_line'))));
PERFORM pg_temp.put('gpx_wp', pg_temp.ok('une trace importée avec ses étapes est acceptée',
  format($$SELECT id::text FROM public.create_gpx_trace('Boucle étapes', (%L::jsonb || jsonb_build_object('waypoints', %L::jsonb)))$$, pg_temp.get('wp_line'), pg_temp.get('wp_two'))));
PERFORM pg_temp.denied('une trace avec un membre inconnu (properties) est refusée depuis 00570',
  format($$SELECT id::text FROM public.create_gpx_trace('Boucle props', (%L::jsonb || '{"properties":{"a":1}}'::jsonb))$$, pg_temp.get('wp_line')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('une trace avec une étape invalide est refusée à la création',
  format($$SELECT id::text FROM public.create_gpx_trace('Boucle bad', (%L::jsonb || '{"waypoints":[{"lng":6.6,"lat":44.9,"kind":"bar"}]}'::jsonb))$$, pg_temp.get('wp_line')), 'junto\.trace_geojson_invalid');
-- set_gpx_trace_waypoints : chaîne d'autorisation.
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne modifie pas les étapes', format($$SELECT public.set_gpx_trace_waypoints(%L, %L::jsonb)::text$$, pg_temp.get('gpx'), pg_temp.get('wp_two')), 'permission denied');
PERFORM pg_temp.as_('sus');
PERFORM pg_temp.denied('un compte suspendu ne modifie pas d''étapes', format($$SELECT public.set_gpx_trace_waypoints(%L, %L::jsonb)::text$$, pg_temp.get('gpx'), pg_temp.get('wp_two')), '^Operation not permitted$');
PERFORM pg_temp.as_('cat');
PERFORM pg_temp.denied('on ne modifie pas les étapes de la trace d''autrui', format($$SELECT public.set_gpx_trace_waypoints(%L, %L::jsonb)::text$$, pg_temp.get('gpx'), pg_temp.get('wp_two')), '^Operation not permitted$');
PERFORM pg_temp.denied('même réponse pour une trace inexistante', format($$SELECT public.set_gpx_trace_waypoints(%L, %L::jsonb)::text$$, gen_random_uuid(), pg_temp.get('wp_two')), '^Operation not permitted$');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la trace de bob est intacte après ces refus',
  format($$SELECT (geojson ? 'waypoints')::text FROM public.gpx_traces WHERE id = %L$$, pg_temp.get('gpx')), 'false');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob ajoute deux étapes à sa trace', format($$SELECT public.set_gpx_trace_waypoints(%L, %L::jsonb)::text$$, pg_temp.get('gpx'), pg_temp.get('wp_two')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('les étapes sont enregistrées dans le GeoJSON',
  format($$SELECT jsonb_array_length(geojson->'waypoints') || '|' || (geojson->'waypoints'->0->>'name') FROM public.gpx_traces WHERE id = %L$$, pg_temp.get('gpx')), '2|Refuge des Bans');
PERFORM pg_temp.eq('la ligne elle-même ne change pas',
  format($$SELECT (geojson->'coordinates' = (%L::jsonb)->'coordinates' AND geojson->>'type' = 'LineString')::text FROM public.gpx_traces WHERE id = %L$$, pg_temp.get('wp_line'), pg_temp.get('gpx')), 'true');
-- Validation (chaque refus = junto.trace_geojson_invalid).
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('étapes : un objet au lieu d''une liste est refusé',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '{"lng":6.6,"lat":44.9,"kind":"water"}'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : un élément qui n''est pas un objet est refusé',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[1]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : 31 étapes sont refusées',
  format($$SELECT public.set_gpx_trace_waypoints(%L, (SELECT jsonb_agg(jsonb_build_object('lng', 6.6, 'lat', 44.9, 'kind', 'other')) FROM generate_series(1, 31)))::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.ok('étapes : 30 étapes sont acceptées',
  format($$SELECT public.set_gpx_trace_waypoints(%L, (SELECT jsonb_agg(jsonb_build_object('lng', 6.6, 'lat', 44.9, 'kind', 'other')) FROM generate_series(1, 30)))::text$$, pg_temp.get('gpx')));
PERFORM pg_temp.denied('étapes : un type inconnu est refusé',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"lng":6.6,"lat":44.9,"kind":"bar"}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : une étape sans type est refusée',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"lng":6.6,"lat":44.9}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : une longitude hors bornes est refusée',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"lng":181,"lat":44.9,"kind":"water"}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : une latitude hors bornes est refusée',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"lng":6.6,"lat":-90.5,"kind":"water"}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : une coordonnée en texte est refusée',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"lng":"6.6","lat":44.9,"kind":"water"}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : un champ en plus est refusé',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"lng":6.6,"lat":44.9,"kind":"water","ele":1200}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : un nom vide est refusé',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"lng":6.6,"lat":44.9,"kind":"water","name":""}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : un nom de 61 caractères est refusé',
  format($$SELECT public.set_gpx_trace_waypoints(%L, jsonb_build_array(jsonb_build_object('lng', 6.6, 'lat', 44.9, 'kind', 'water', 'name', repeat('é', 61))))::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.ok('étapes : un nom de 60 caractères est accepté',
  format($$SELECT public.set_gpx_trace_waypoints(%L, jsonb_build_array(jsonb_build_object('lng', 6.6, 'lat', 44.9, 'kind', 'water', 'name', repeat('é', 60))))::text$$, pg_temp.get('gpx')));
PERFORM pg_temp.denied('étapes : un nom avec < > est refusé',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"lng":6.6,"lat":44.9,"kind":"water","name":"<b>Source</b>"}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : un nom avec un caractère de contrôle est refusé',
  format($$SELECT public.set_gpx_trace_waypoints(%L, jsonb_build_array(jsonb_build_object('lng', 6.6, 'lat', 44.9, 'kind', 'water', 'name', 'Sou' || chr(10) || 'rce')))::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.denied('étapes : un nom qui n''est pas du texte est refusé',
  format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"lng":6.6,"lat":44.9,"kind":"water","name":5}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('après les refus, la dernière version acceptée reste en place (1 étape, nom de 60 car.)',
  format($$SELECT jsonb_array_length(geojson->'waypoints') || '|' || char_length(geojson->'waypoints'->0->>'name') FROM public.gpx_traces WHERE id = %L$$, pg_temp.get('gpx')), '1|60');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('une liste vide retire les étapes', format($$SELECT public.set_gpx_trace_waypoints(%L, '[]'::jsonb)::text$$, pg_temp.get('gpx')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('plus de membre waypoints après une liste vide', format($$SELECT (geojson ? 'waypoints')::text FROM public.gpx_traces WHERE id = %L$$, pg_temp.get('gpx')), 'false');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('NULL retire aussi les étapes', format($$SELECT public.set_gpx_trace_waypoints(%L, NULL)::text$$, pg_temp.get('gpx_wp')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('plus de membre waypoints après NULL', format($$SELECT (geojson ? 'waypoints')::text FROM public.gpx_traces WHERE id = %L$$, pg_temp.get('gpx_wp')), 'false');
-- Fréquence : 60 modifications par heure.
PERFORM pg_temp.user('wp_rate', 'tos');
PERFORM pg_temp.as_('wp_rate');
PERFORM pg_temp.put('gpx_rate', pg_temp.ok('wp_rate enregistre une trace', format($$SELECT id::text FROM public.create_gpx_trace('Boucle', %L::jsonb)$$, pg_temp.get('wp_line'))));
PERFORM pg_temp.as_('db');
INSERT INTO public.rate_events (user_id, kind) SELECT pg_temp.id('wp_rate'), 'gpx_waypoints' FROM generate_series(1, 59);
PERFORM pg_temp.as_('wp_rate');
PERFORM pg_temp.ok('la 60e modification de l''heure passe', format($$SELECT public.set_gpx_trace_waypoints(%L, %L::jsonb)::text$$, pg_temp.get('gpx_rate'), pg_temp.get('wp_two')));
PERFORM pg_temp.denied('la 61e modification de l''heure est refusée', format($$SELECT public.set_gpx_trace_waypoints(%L, %L::jsonb)::text$$, pg_temp.get('gpx_rate'), pg_temp.get('wp_two')), 'junto\.too_many_actions');
-- 00483 (même famille) : un appel refusé pour validation devrait compter dans la fréquence, sinon
-- le chemin en échec (validation de la trace stockée, jusqu'à 10 000 points) est gratuit et illimité.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('wp_n0', (SELECT count(*)::text FROM public.rate_events WHERE user_id = pg_temp.id('bob') AND kind = 'gpx_waypoints'));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('(fixture) bob envoie des étapes invalides', format($$SELECT public.set_gpx_trace_waypoints(%L, '[{"kind":"bar"}]'::jsonb)::text$$, pg_temp.get('gpx')), 'junto\.trace_geojson_invalid');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('un appel refusé pour validation compte quand même dans la fréquence',
  $$SELECT (count(*) = pg_temp.get('wp_n0')::int + 1)::text FROM public.rate_events WHERE user_id = pg_temp.id('bob') AND kind = 'gpx_waypoints'$$, 'true', 'DB-WP-1');

-- Sortie : création avec étapes, mise à jour de la trace (étapes seules = pas de notification).
PERFORM pg_temp.as_('org');
PERFORM pg_temp.put('wp_act', pg_temp.ok('créer une sortie avec une trace et ses étapes',
  format($$SELECT public.create_activity(p_sport_id := %L, p_title := 'Sortie étapes', p_description := 'x', p_level := 'Tous niveaux', p_max_participants := 6,
     p_meeting_lng := -138.1, p_meeting_lat := -44.6, p_end_lng := NULL, p_end_lat := NULL, p_starts_at := now() + interval '177 days', p_duration := '5 hours',
     p_visibility := 'public', p_trace_geojson := (%L::jsonb || jsonb_build_object('waypoints', %L::jsonb)))::text$$, pg_temp.get('sport'), pg_temp.get('wp_line'), pg_temp.get('wp_two'))));
PERFORM pg_temp.denied('créer une sortie avec une étape invalide est refusé',
  format($$SELECT public.create_activity(p_sport_id := %L, p_title := 'Sortie étapes bad', p_description := 'x', p_level := 'Tous niveaux', p_max_participants := 6,
     p_meeting_lng := -138.1, p_meeting_lat := -44.6, p_end_lng := NULL, p_end_lat := NULL, p_starts_at := now() + interval '178 days', p_duration := '5 hours',
     p_visibility := 'public', p_trace_geojson := (%L::jsonb || '{"waypoints":[{"lng":6.6,"lat":44.9,"kind":"water","name":"<x>"}]}'::jsonb))::text$$, pg_temp.get('sport'), pg_temp.get('wp_line')),
  'junto\.trace_geojson_invalid');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('les étapes sont enregistrées avec la sortie',
  format($$SELECT jsonb_array_length(trace_geojson->'waypoints')::text FROM public.activities WHERE id = %L$$, pg_temp.get('wp_act')), '2');
PERFORM pg_temp.dv_part(pg_temp.id('wp_act'), 'cat', 'accepted');
PERFORM pg_temp.as_('org');
PERFORM pg_temp.eq('changer seulement les étapes de la trace : enregistré',
  format($$SELECT coalesce(public.update_activity_trace(%L, (%L::jsonb || '{"waypoints":[{"lng":6.6,"lat":44.9,"kind":"summit","name":"Sommet"}]}'::jsonb)), 'enregistré')$$, pg_temp.get('wp_act'), pg_temp.get('wp_line')), 'enregistré');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('… et les participants ne reçoivent pas « Itinéraire modifié » (même ligne)', $$SELECT pg_temp.dv_notifs('cat', 'activity_updated', 'wp_act')$$, '0');
PERFORM pg_temp.as_('org');
PERFORM pg_temp.eq('une étape invalide dans la mise à jour est signalée, pas enregistrée',
  format($$SELECT public.update_activity_trace(%L, (%L::jsonb || '{"waypoints":[{"lng":6.6,"lat":44.9,"kind":"bar"}]}'::jsonb))$$, pg_temp.get('wp_act'), pg_temp.get('wp_line')), 'junto.trace_geojson_invalid');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la sortie garde l''étape « Sommet »',
  format($$SELECT trace_geojson->'waypoints'->0->>'name' FROM public.activities WHERE id = %L$$, pg_temp.get('wp_act')), 'Sommet');
PERFORM pg_temp.as_('org');
PERFORM pg_temp.eq('changer la ligne elle-même : enregistré',
  format($$SELECT coalesce(public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[6.6,44.9],[6.62,44.92]]}'::jsonb), 'enregistré')$$, pg_temp.get('wp_act')), 'enregistré');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('… et là les participants sont prévenus', $$SELECT pg_temp.dv_notifs('cat', 'activity_updated', 'wp_act')$$, '1');
-- Partage dans une conversation : les étapes suivent la trace.
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.put('wp_msg', pg_temp.ok('bob partage une trace avec ses étapes',
  format($$SELECT public.share_trace_message(%L, (%L::jsonb || jsonb_build_object('waypoints', %L::jsonb)), 'Avec étapes')::text$$, pg_temp.id('dm_bob_cat'), pg_temp.get('wp_line'), pg_temp.get('wp_two'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le message partagé porte les étapes',
  format($$SELECT jsonb_array_length(metadata->'trace_geojson'->'waypoints')::text FROM public.messages WHERE id = %L$$, pg_temp.get('wp_msg')), '2');
PERFORM pg_temp.as_('cat');
PERFORM pg_temp.denied('partager une trace avec une étape invalide est refusé',
  format($$SELECT public.share_trace_message(%L, (%L::jsonb || '{"waypoints":[{"lng":6.6,"lat":44.9,"kind":"water","name":5}]}'::jsonb), 'x')::text$$, pg_temp.id('dm_bob_cat'), pg_temp.get('wp_line')),
  'junto\.trace_geojson_invalid');

-- ═════ 00572-00573 — Rappel de fin de sortie longue (≥ 12 h) ═════
-- Les portes horaires sont relatives à la sortie (dernière heure avant la fin) : on place la sortie
-- dans cette fenêtre, la vraie fonction est appelée telle quelle (pas de copie).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('pe_org', 'tos'); PERFORM pg_temp.user('pe_a', 'tos'); PERFORM pg_temp.user('pe_b', 'tos');
PERFORM pg_temp.user('pe_ok', 'tos'); PERFORM pg_temp.user('pe_wait', 'tos');
-- Sortie principale : 24 h, fin dans 30 min.
PERFORM pg_temp.put('pe1', pg_temp.dv_act('pe_org', 'Traversée', now() - interval '23 hours 30 minutes', interval '24 hours', 'public', 'in_progress', true, -138.2)::text);
PERFORM pg_temp.dv_part(pg_temp.id('pe1'), 'pe_org', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('pe1'), 'pe_a', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('pe1'), 'pe_b', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('pe1'), 'pe_ok', 'accepted', true);
PERFORM pg_temp.dv_part(pg_temp.id('pe1'), 'pe_wait', 'pending');
PERFORM pg_temp.eq('le rappel n''est pas appelable par un client',
  $$SELECT (has_function_privilege('authenticated', 'public.notify_presence_end_reminder(uuid)', 'EXECUTE')
         OR has_function_privilege('anon', 'public.notify_presence_end_reminder(uuid)', 'EXECUTE'))::text$$, 'false');
PERFORM pg_temp.ok('dernière heure d''une sortie de 24 h : le rappel tourne', format($$SELECT public.notify_presence_end_reminder(%L)::text$$, pg_temp.id('pe1')));
PERFORM pg_temp.eq('participant sans présence validée : « valide ta présence »', $$SELECT pg_temp.dv_notifs('pe_a', 'presence_end_reminder', 'pe1')$$, '1');
PERFORM pg_temp.eq('second participant sans présence : rappelé aussi', $$SELECT pg_temp.dv_notifs('pe_b', 'presence_end_reminder', 'pe1')$$, '1');
PERFORM pg_temp.eq('présence déjà validée : pas de rappel', $$SELECT pg_temp.dv_notifs('pe_ok', 'presence_end_reminder', 'pe1')$$, '0');
PERFORM pg_temp.eq('demande en attente : pas de rappel', $$SELECT pg_temp.dv_notifs('pe_wait', 'presence_end_reminder', 'pe1')$$, '0');
PERFORM pg_temp.eq('l''organisatrice : « affiche ton QR », variante creator, 2 manquants',
  format($$SELECT title || '|' || (data->>'variant') || '|' || (data->'params'->>'count') FROM public.notifications WHERE user_id = %L AND type = 'presence_end_reminder'$$, pg_temp.id('pe_org')),
  'Fin de sortie : affiche ton QR|creator|2');
PERFORM pg_temp.eq('00573 : pluriel « n''ont pas encore validé leur présence »',
  format($$SELECT body FROM public.notifications WHERE user_id = %L AND type = 'presence_end_reminder'$$, pg_temp.id('pe_org')),
  '2 participants n''ont pas encore validé leur présence sur « Traversée ».');
PERFORM pg_temp.eq('le texte du participant cite la sortie et la fenêtre de 3 h',
  format($$SELECT title || '|' || body FROM public.notifications WHERE user_id = %L AND type = 'presence_end_reminder'$$, pg_temp.id('pe_a')),
  'Fin de sortie : valide ta présence|Scanne le QR de l''organisateur — valable jusqu''à 3 h après la fin de « Traversée ».');
PERFORM pg_temp.ok('un second passage du rappel', format($$SELECT public.notify_presence_end_reminder(%L)::text$$, pg_temp.id('pe1')));
PERFORM pg_temp.eq('une seule notification par personne et par sortie',
  format($$SELECT count(*)::text FROM public.notifications WHERE type = 'presence_end_reminder' AND data->>'activity_id' = %L$$, pg_temp.get('pe1')), '3');
-- Singulier (00573) : un seul manquant.
PERFORM pg_temp.put('pe2', pg_temp.dv_act('pe_org', 'Bivouac', now() - interval '12 hours 20 minutes', interval '13 hours', 'public', 'in_progress', true, -138.2)::text);
PERFORM pg_temp.dv_part(pg_temp.id('pe2'), 'pe_org', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('pe2'), 'pe_a', 'accepted');
PERFORM pg_temp.ok('sortie de 13 h, un seul manquant', format($$SELECT public.notify_presence_end_reminder(%L)::text$$, pg_temp.id('pe2')));
PERFORM pg_temp.eq('00573 : singulier « n''a pas encore validé sa présence »',
  format($$SELECT body FROM public.notifications WHERE user_id = %L AND type = 'presence_end_reminder' AND data->>'activity_id' = %L$$, pg_temp.id('pe_org'), pg_temp.get('pe2')),
  '1 participant n''a pas encore validé sa présence sur « Bivouac ».');
-- Portes : rien en dehors des conditions.
PERFORM pg_temp.put('pe_short', pg_temp.dv_act('pe_org', 'Courte', now() - interval '11 hours 30 minutes', interval '11 hours 59 minutes', 'public', 'in_progress', true, -138.2)::text);
PERFORM pg_temp.put('pe_early', pg_temp.dv_act('pe_org', 'Trop tôt', now() - interval '10 hours', interval '12 hours', 'public', 'in_progress', true, -138.2)::text);
PERFORM pg_temp.put('pe_over', pg_temp.dv_act('pe_org', 'Déjà finie', now() - interval '12 hours 5 minutes', interval '12 hours', 'public', 'in_progress', true, -138.2)::text);
PERFORM pg_temp.put('pe_nopres', pg_temp.dv_act('pe_org', 'Sans présence', now() - interval '11 hours 30 minutes', interval '12 hours', 'public', 'in_progress', false, -138.2)::text);
PERFORM pg_temp.put('pe_pub', pg_temp.dv_act('pe_org', 'Pas en cours', now() - interval '11 hours 30 minutes', interval '12 hours', 'public', 'published', true, -138.2)::text);
PERFORM pg_temp.put('pe_all', pg_temp.dv_act('pe_org', 'Tous validés', now() - interval '11 hours 30 minutes', interval '12 hours', 'public', 'in_progress', true, -138.2)::text);
PERFORM pg_temp.dv_part(pg_temp.id(x), 'pe_org', 'accepted') FROM unnest(ARRAY['pe_short', 'pe_early', 'pe_over', 'pe_nopres', 'pe_pub', 'pe_all']) x;
PERFORM pg_temp.dv_part(pg_temp.id(x), 'pe_b', 'accepted') FROM unnest(ARRAY['pe_short', 'pe_early', 'pe_over', 'pe_nopres', 'pe_pub']) x;
PERFORM pg_temp.dv_part(pg_temp.id('pe_all'), 'pe_ok', 'accepted', true);
PERFORM pg_temp.ok('le rappel tourne sur les 6 sorties hors conditions',
  $$SELECT count(*)::text FROM (SELECT public.notify_presence_end_reminder(pg_temp.id(x)) FROM unnest(ARRAY['pe_short', 'pe_early', 'pe_over', 'pe_nopres', 'pe_pub', 'pe_all']) x) z$$);
PERFORM pg_temp.eq('sortie de moins de 12 h : pas de rappel', $$SELECT pg_temp.dv_notifs('pe_b', 'presence_end_reminder', 'pe_short')$$, '0');
PERFORM pg_temp.eq('avant la dernière heure : pas de rappel', $$SELECT pg_temp.dv_notifs('pe_b', 'presence_end_reminder', 'pe_early')$$, '0');
PERFORM pg_temp.eq('après la fin : pas de rappel', $$SELECT pg_temp.dv_notifs('pe_b', 'presence_end_reminder', 'pe_over')$$, '0');
PERFORM pg_temp.eq('sortie sans présence demandée : pas de rappel', $$SELECT pg_temp.dv_notifs('pe_b', 'presence_end_reminder', 'pe_nopres')$$, '0');
PERFORM pg_temp.eq('sortie pas en cours : pas de rappel', $$SELECT pg_temp.dv_notifs('pe_b', 'presence_end_reminder', 'pe_pub')$$, '0');
-- (Pas de cas « organisatrice seule » : la porte « ≥ 2 acceptés » y coïncide avec « personne à rappeler »,
-- le test ne prouverait rien.)
PERFORM pg_temp.eq('tout le monde a validé : l''organisatrice n''est pas relancée', $$SELECT pg_temp.dv_notifs('pe_org', 'presence_end_reminder', 'pe_all')$$, '0');
PERFORM pg_temp.eq('un identifiant inventé : rien, sans erreur', format($$SELECT coalesce(public.notify_presence_end_reminder(%L)::text, 'rien')$$, gen_random_uuid()), '');
-- Le balayage minute l'appelle (sortie en cours, organisatrice non suspendue).
PERFORM pg_temp.put('pe_sweep', pg_temp.dv_act('pe_org', 'Balayée', now() - interval '13 hours 30 minutes', interval '14 hours', 'public', 'in_progress', true, -138.2)::text);
PERFORM pg_temp.dv_part(pg_temp.id('pe_sweep'), 'pe_org', 'accepted');
PERFORM pg_temp.dv_part(pg_temp.id('pe_sweep'), 'pe_b', 'accepted');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.ok('le balayage minute tourne sans erreur', $$SELECT public.transition_statuses_only()::text$$);
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('le balayage envoie le rappel de fin au participant', $$SELECT pg_temp.dv_notifs('pe_b', 'presence_end_reminder', 'pe_sweep')$$, '1');
PERFORM pg_temp.eq('… et à l''organisatrice', $$SELECT pg_temp.dv_notifs('pe_org', 'presence_end_reminder', 'pe_sweep')$$, '1');
