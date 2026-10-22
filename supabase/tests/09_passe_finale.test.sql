-- Domaine 9 — passe finale avant migration (00523, 2026-10-22).
-- Bugs fonctionnels trouvés par le dernier audit : places de covoiturage qui suivent
-- les personnes, trophée d'une présence validée après la fin, jour de Paris, notifications de demande périmées, demande
-- retirée par un blocage (décision Scott F2), invitations, fil masqué, préférences.
-- Fixtures en plein Pacifique, sorties créées en `db`.

-- ───── Utilitaires locaux ─────
EXECUTE 'CREATE TEMP SEQUENCE pf_slot';
EXECUTE 'GRANT USAGE ON SEQUENCE pg_temp.pf_slot TO PUBLIC';

EXECUTE $p$CREATE FUNCTION pg_temp.pf_act(p_label text, p_creator text, p_start interval DEFAULT NULL,
    p_status text DEFAULT 'published', p_vis text DEFAULT 'public', p_rp boolean DEFAULT false,
    p_cp boolean DEFAULT NULL, p_level text DEFAULT 'Tous niveaux', p_sport text DEFAULT 'hiking') RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting,
      starts_at, duration, visibility, status, requires_presence)
    VALUES (pg_temp.id(p_creator), (SELECT id FROM public.sports WHERE key = p_sport), 'Sortie passe finale ' || p_label,
      p_level, 10, ST_SetSRID(ST_MakePoint(-141.5, -47.5), 4326)::geography,
      now() + coalesce(p_start, interval '120 days' + nextval('pg_temp.pf_slot') * interval '5 hours'),
      interval '3 hours', p_vis, p_status, p_rp)
    RETURNING id INTO v;
    INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, created_at)
    VALUES (v, pg_temp.id(p_creator), 'accepted', p_cp, now() - interval '3 days');
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.pf_part(p_act text, p_user text, p_status text DEFAULT 'accepted',
    p_cp boolean DEFAULT NULL) RETURNS void
  LANGUAGE sql AS $b$
  INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, created_at)
  VALUES (pg_temp.id(p_act), pg_temp.id(p_user), p_status, p_cp, now() - interval '2 days') $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.pf_pid(p_act text, p_user text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT id::text FROM public.participations WHERE activity_id = pg_temp.id(p_act) AND user_id = pg_temp.id(p_user) $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.pf_sr(p_act text, p_req text, p_drv text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT id::text FROM public.seat_requests WHERE activity_id = pg_temp.id(p_act)
    AND requester_id = pg_temp.id(p_req) AND driver_id = pg_temp.id(p_drv) ORDER BY created_at DESC LIMIT 1 $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.pf_seats(p_act text, p_user text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT coalesce(transport_seats::text, 'null') FROM public.participations
  WHERE activity_id = pg_temp.id(p_act) AND user_id = pg_temp.id(p_user) $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.pf_notifs(p_user text, p_type text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT count(*)::text FROM public.notifications WHERE user_id = pg_temp.id(p_user) AND type = p_type $b$$p$;

-- ═════ P1 — Les places de covoiturage suivent les personnes ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s_org', 'tos'); PERFORM pg_temp.user('s_d', 'tos'); PERFORM pg_temp.user('s_d2', 'tos');
PERFORM pg_temp.user('s_p', 'tos'); PERFORM pg_temp.user('s_q', 'tos'); PERFORM pg_temp.user('s_r', 'tos');
PERFORM pg_temp.user('s_s', 'tos'); PERFORM pg_temp.user('s_t', 'tos'); PERFORM pg_temp.user('s_u', 'tos');
PERFORM pg_temp.pf_act('s_act', 's_org');
PERFORM pg_temp.pf_part('s_act', u) FROM unnest(ARRAY['s_d', 's_d2', 's_p', 's_q', 's_r', 's_s', 's_t', 's_u']) u;
UPDATE public.users SET notification_preferences = notification_preferences || '{"driver_left": true}'::jsonb
WHERE id IN (pg_temp.id('s_s'));
PERFORM pg_temp.as_('s_d');
PERFORM pg_temp.ok('P1 s_d propose 4 places', format($$SELECT public.set_participation_transport(%L, 'car', 4::smallint, 'Gap', NULL, 44.56, 6.08, 'Gap')::text$$, pg_temp.id('s_act')));
PERFORM pg_temp.as_('s_d2');
PERFORM pg_temp.ok('P1 s_d2 propose 2 places', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint, 'Embrun', NULL, 44.56, 6.49, 'Embrun')::text$$, pg_temp.id('s_act')));
-- Demandes : s_p, s_q, s_t, s_u acceptés chez s_d ; s_r en attente chez s_d ; s_s accepté chez s_d2.
PERFORM pg_temp.as_('s_p'); PERFORM pg_temp.ok('P1 s_p demande', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('s_act'), pg_temp.id('s_d')));
PERFORM pg_temp.as_('s_q'); PERFORM pg_temp.ok('P1 s_q demande', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('s_act'), pg_temp.id('s_d')));
PERFORM pg_temp.as_('s_t'); PERFORM pg_temp.ok('P1 s_t demande', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('s_act'), pg_temp.id('s_d')));
PERFORM pg_temp.as_('s_u'); PERFORM pg_temp.ok('P1 s_u demande', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('s_act'), pg_temp.id('s_d')));
PERFORM pg_temp.as_('s_s'); PERFORM pg_temp.ok('P1 s_s demande à s_d2', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('s_act'), pg_temp.id('s_d2')));
PERFORM pg_temp.as_('s_d');
PERFORM pg_temp.ok('P1 s_d accepte s_p', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.pf_sr('s_act', 's_p', 's_d')));
PERFORM pg_temp.ok('P1 s_d accepte s_q', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.pf_sr('s_act', 's_q', 's_d')));
PERFORM pg_temp.ok('P1 s_d accepte s_t', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.pf_sr('s_act', 's_t', 's_d')));
PERFORM pg_temp.as_('s_d2');
PERFORM pg_temp.ok('P1 s_d2 accepte s_s', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.pf_sr('s_act', 's_s', 's_d2')));
PERFORM pg_temp.as_('s_r'); PERFORM pg_temp.ok('P1 s_r demande (restera en attente)', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('s_act'), pg_temp.id('s_d')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P1 fixture : 3 places prises chez s_d (4 → 1)', $$SELECT pg_temp.pf_seats('s_act', 's_d')$$, '1');

-- Un passager qui quitte la sortie libère sa place, le conducteur est prévenu.
PERFORM pg_temp.as_('s_p');
PERFORM pg_temp.ok('P1 s_p quitte la sortie', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('s_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P1 sa place acceptée est annulée', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.pf_sr('s_act', 's_p', 's_d')), 'cancelled');
PERFORM pg_temp.eq('P1 la place revient au conducteur (1 → 2)', $$SELECT pg_temp.pf_seats('s_act', 's_d')$$, '2');
PERFORM pg_temp.eq('P1 le conducteur est prévenu (seat_passenger_left)', $$SELECT pg_temp.pf_notifs('s_d', 'seat_passenger_left')$$, '1');

-- Un passager retiré par l'organisatrice libère aussi sa place.
PERFORM pg_temp.as_('s_org');
PERFORM pg_temp.ok('P1 l''organisatrice retire s_q', format($$SELECT public.remove_participant(%L)::text$$, pg_temp.pf_pid('s_act', 's_q')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P1 la place de s_q est annulée', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.pf_sr('s_act', 's_q', 's_d')), 'cancelled');
PERFORM pg_temp.eq('P1 la place revient au conducteur (2 → 3)', $$SELECT pg_temp.pf_seats('s_act', 's_d')$$, '3');

-- Une demande en attente d'un passager qui part est retirée, sans toucher aux places.
PERFORM pg_temp.as_('s_r');
PERFORM pg_temp.ok('P1 s_r quitte la sortie', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('s_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P1 la demande en attente de s_r est retirée', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.pf_sr('s_act', 's_r', 's_d')), 'cancelled');
PERFORM pg_temp.eq('P1 une demande en attente ne rend aucune place (reste 3)', $$SELECT pg_temp.pf_seats('s_act', 's_d')$$, '3');

-- Annuler soi-même sa place la rend UNE fois (plus d'incrément manuel en double).
PERFORM pg_temp.as_('s_t');
PERFORM pg_temp.ok('P1 s_t annule sa place', format($$SELECT public.cancel_accepted_seat(%L)::text$$, pg_temp.pf_sr('s_act', 's_t', 's_d')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P1 la place revient une seule fois (3 → 4)', $$SELECT pg_temp.pf_seats('s_act', 's_d')$$, '4');

-- Une place annulée par un blocage revient au conducteur.
PERFORM pg_temp.as_('s_d');
PERFORM pg_temp.ok('P1 s_d accepte s_u', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.pf_sr('s_act', 's_u', 's_d')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P1 fixture : s_u assis (4 → 3)', $$SELECT pg_temp.pf_seats('s_act', 's_d')$$, '3');
PERFORM pg_temp.as_('s_u');
PERFORM pg_temp.ok('P1 s_u bloque le conducteur', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('s_u'), pg_temp.id('s_d')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P1 le blocage annule la place', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.pf_sr('s_act', 's_u', 's_d')), 'cancelled');
PERFORM pg_temp.eq('P1 et la place revient au conducteur (3 → 4)', $$SELECT pg_temp.pf_seats('s_act', 's_d')$$, '4');

-- Un conducteur retiré libère ses passagers, qui sont prévenus.
PERFORM pg_temp.as_('s_org');
PERFORM pg_temp.ok('P1 l''organisatrice retire le conducteur s_d2', format($$SELECT public.remove_participant(%L)::text$$, pg_temp.pf_pid('s_act', 's_d2')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P1 la place de s_s chez s_d2 est annulée', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.pf_sr('s_act', 's_s', 's_d2')), 'cancelled');
PERFORM pg_temp.eq('P1 s_s est prévenue (driver_left)', $$SELECT pg_temp.pf_notifs('s_s', 'driver_left')$$, '1');
PERFORM pg_temp.eq('P1 aucune place acceptée ne reste attachée à quelqu''un parti',
  format($$SELECT count(*)::text FROM public.seat_requests sr WHERE sr.activity_id = %L AND sr.status = 'accepted'
           AND NOT EXISTS (SELECT 1 FROM public.participations p WHERE p.activity_id = sr.activity_id AND p.status = 'accepted' AND p.user_id = sr.requester_id)$$, pg_temp.id('s_act')), '0');

-- Un conducteur qui quitte la sortie : ses passagers prévenus une seule fois (plus de boucle en double).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('l_org', 'tos'); PERFORM pg_temp.user('l_d', 'tos'); PERFORM pg_temp.user('l_p', 'tos');
PERFORM pg_temp.pf_act('l_act', 'l_org');
PERFORM pg_temp.pf_part('l_act', 'l_d'); PERFORM pg_temp.pf_part('l_act', 'l_p');
PERFORM pg_temp.as_('l_d');
PERFORM pg_temp.ok('P1 l_d propose 2 places', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint, 'Gap', NULL, 44.56, 6.08, 'Gap')::text$$, pg_temp.id('l_act')));
PERFORM pg_temp.as_('l_p'); PERFORM pg_temp.ok('P1 l_p demande', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('l_act'), pg_temp.id('l_d')));
PERFORM pg_temp.as_('l_d'); PERFORM pg_temp.ok('P1 l_d accepte', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.pf_sr('l_act', 'l_p', 'l_d')));
PERFORM pg_temp.ok('P1 l_d quitte la sortie', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('l_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P1 la place de l_p est annulée', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.pf_sr('l_act', 'l_p', 'l_d')), 'cancelled');
PERFORM pg_temp.eq('P1 l_p reçoit exactement un avis driver_left', $$SELECT pg_temp.pf_notifs('l_p', 'driver_left')$$, '1');

-- ═════ P3 — Présence validée après la fin : le trophée arrive ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('aw_u', 'tos'); PERFORM pg_temp.user('aw_o', 'tos');
PERFORM pg_temp.pf_act('aw_' || i, 'aw_o', (-40 + i) * interval '1 day', 'completed', 'public', true, true) FROM generate_series(1, 5) i;
PERFORM pg_temp.pf_part('aw_' || i, 'aw_u', 'accepted', true) FROM generate_series(1, 4) i;
PERFORM pg_temp.pf_part('aw_5', 'aw_u', 'accepted', NULL);
PERFORM pg_temp.eq('P3 fixture : pas encore de trophée « rejoint »', format($$SELECT count(*)::text FROM public.user_badge_progression WHERE user_id = %L AND category = 'joined'$$, pg_temp.id('aw_u')), '0');
UPDATE public.participations SET confirmed_present = true WHERE id = pg_temp.pf_pid('aw_5', 'aw_u')::uuid;
PERFORM pg_temp.eq('P3 la 5e présence validée après la fin donne le bronze', format($$SELECT tier_key FROM public.user_badge_progression WHERE user_id = %L AND category = 'joined'$$, pg_temp.id('aw_u')), 'bronze');
PERFORM pg_temp.eq('P3 et le notifie', $$SELECT pg_temp.pf_notifs('aw_u', 'badge_unlocked')$$, '1');
-- Une sortie pas encore terminée ne déclenche rien.
PERFORM pg_temp.user('aw2_u', 'tos');
PERFORM pg_temp.pf_act('aw2_' || i, 'aw_o', (-60 + i) * interval '1 day', 'completed', 'public', true, true) FROM generate_series(1, 4) i;
PERFORM pg_temp.pf_part('aw2_' || i, 'aw2_u', 'accepted', true) FROM generate_series(1, 4) i;
PERFORM pg_temp.pf_act('aw2_run', 'aw_o', interval '-1 hour', 'in_progress', 'public', true, true);
PERFORM pg_temp.pf_part('aw2_run', 'aw2_u', 'accepted', NULL);
UPDATE public.participations SET confirmed_present = true WHERE id = pg_temp.pf_pid('aw2_run', 'aw2_u')::uuid;
PERFORM pg_temp.eq('P3 une présence sur une sortie en cours n''attribue rien maintenant', format($$SELECT count(*)::text FROM public.user_badge_progression WHERE user_id = %L$$, pg_temp.id('aw2_u')), '0');

-- ═════ P4 — Jour de Paris ═════
PERFORM pg_temp.eq('P4 le jour de référence est celui de Paris', $$SELECT (private.today_paris() = (now() AT TIME ZONE 'Europe/Paris')::date)::text$$, 'true');
PERFORM pg_temp.eq('P4 plus aucune fonction ne lit le jour UTC (current_date)',
  $$SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'private') AND p.prosrc ILIKE '%current_date%'$$, '0');

-- ═════ P5 — Clés de navigation transmises au push ═════
PERFORM pg_temp.eq('P5 by / pro_id / offering_id / booking_id dans la liste autorisée',
  $$SELECT (prosrc LIKE '%''by''%' AND prosrc LIKE '%''pro_id''%' AND prosrc LIKE '%''offering_id''%' AND prosrc LIKE '%''booking_id''%')::text
    FROM pg_proc WHERE proname = 'push_notification_to_device'$$, 'true');

-- ═════ P6 — Demande retirée : la notification périmée part avec ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('jr_org', 'tos'); PERFORM pg_temp.user('jr_x', 'tos'); PERFORM pg_temp.user('jr_y', 'tos');
PERFORM pg_temp.pf_act('jr_act', 'jr_org', NULL, 'published', 'approval');
PERFORM pg_temp.as_('jr_x');
PERFORM pg_temp.eq('P6 jr_x demande à rejoindre', format($$SELECT public.join_activity(%L)$$, pg_temp.id('jr_act')), 'pending');
PERFORM pg_temp.as_('jr_y');
PERFORM pg_temp.eq('P6 jr_y demande à rejoindre', format($$SELECT public.join_activity(%L)$$, pg_temp.id('jr_act')), 'pending');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P6 la notification porte requester_id', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'join_request' AND data->>'requester_id' = %L$$, pg_temp.id('jr_org'), pg_temp.id('jr_x')), '1');
PERFORM pg_temp.as_('jr_x');
PERFORM pg_temp.ok('P6 jr_x retire sa demande', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('jr_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P6 sa notification non lue disparaît', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'join_request' AND data->>'requester_id' = %L$$, pg_temp.id('jr_org'), pg_temp.id('jr_x')), '0');
PERFORM pg_temp.eq('P6 celle de jr_y reste', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'join_request' AND data->>'requester_id' = %L$$, pg_temp.id('jr_org'), pg_temp.id('jr_y')), '1');

-- ═════ P7 — Demande retirée par un blocage : l'organisatrice le sait, jamais qui (F2) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('bk_org', 'tos'); PERFORM pg_temp.user('bk_m', 'tos'); PERFORM pg_temp.user('bk_x', 'tos'); PERFORM pg_temp.user('bk_z', 'tos');
UPDATE public.users SET display_name = 'Membre Secret' WHERE id = pg_temp.id('bk_m');
UPDATE public.users SET display_name = 'Demandeuse X' WHERE id = pg_temp.id('bk_x');
PERFORM pg_temp.pf_act('bk_act', 'bk_org', NULL, 'published', 'approval');
PERFORM pg_temp.pf_part('bk_act', 'bk_m');
PERFORM pg_temp.as_('bk_x');
PERFORM pg_temp.eq('P7 bk_x demande à rejoindre', format($$SELECT public.join_activity(%L)$$, pg_temp.id('bk_act')), 'pending');
PERFORM pg_temp.as_('bk_m');
PERFORM pg_temp.ok('P7 un membre bloque la demandeuse', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('bk_m'), pg_temp.id('bk_x')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P7 la demande est retirée', format($$SELECT status FROM public.participations WHERE id = %L$$, pg_temp.pf_pid('bk_act', 'bk_x')), 'withdrawn');
PERFORM pg_temp.eq('P7 l''organisatrice est prévenue (join_request_blocked)', $$SELECT pg_temp.pf_notifs('bk_org', 'join_request_blocked')$$, '1');
PERFORM pg_temp.eq('P7 l''avis nomme la demandeuse, jamais le membre',
  format($$SELECT (body LIKE '%%Demandeuse X%%' AND body NOT LIKE '%%Membre Secret%%' AND data::text NOT LIKE %L)::text
           FROM public.notifications WHERE user_id = %L AND type = 'join_request_blocked'$$, '%' || pg_temp.get('bk_m') || '%', pg_temp.id('bk_org')), 'true');
PERFORM pg_temp.eq('P7 la notification de demande est retirée avec', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'join_request'$$, pg_temp.id('bk_org')), '0');
-- L'organisatrice partie prenante du blocage : refus classique, pas d'avis « blocage ».
PERFORM pg_temp.as_('bk_z');
PERFORM pg_temp.eq('P7 bk_z demande à rejoindre', format($$SELECT public.join_activity(%L)$$, pg_temp.id('bk_act')), 'pending');
PERFORM pg_temp.as_('bk_org');
PERFORM pg_temp.ok('P7 l''organisatrice bloque bk_z', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('bk_org'), pg_temp.id('bk_z')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P7 la demande de bk_z est refusée', format($$SELECT status FROM public.participations WHERE id = %L$$, pg_temp.pf_pid('bk_act', 'bk_z')), 'refused');
PERFORM pg_temp.eq('P7 aucun avis « blocage » de plus', $$SELECT pg_temp.pf_notifs('bk_org', 'join_request_blocked')$$, '1');

-- ═════ P8 — Invitations ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('iv_g', 'tos'); PERFORM pg_temp.user('iv_o', 'tos'); PERFORM pg_temp.user('iv_pub', 'tos');
PERFORM pg_temp.pf_act('iv_a' || i, 'iv_o') FROM generate_series(1, 11) i;
INSERT INTO public.participations (activity_id, user_id, status, invited_by, created_at)
SELECT pg_temp.id('iv_a' || i), pg_temp.id('iv_g'), 'invited', pg_temp.id('iv_o'), now() FROM generate_series(1, 11) i;
PERFORM pg_temp.pf_act('iv_open', 'iv_pub');
PERFORM pg_temp.as_('iv_g');
PERFORM pg_temp.eq('P8 11 invitations reçues ne bloquent pas une inscription', format($$SELECT public.join_activity(%L)$$, pg_temp.id('iv_open')), 'accepted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('iv_lo', 'tos'); PERFORM pg_temp.user('iv_t', 'tos');
PERFORM pg_temp.pf_act('iv_locked', 'iv_lo', interval '-20 minutes', 'in_progress', 'public', true);
PERFORM pg_temp.as_('iv_lo');
PERFORM pg_temp.denied('P8 pas d''invitation à une sortie verrouillée', format($$SELECT public.send_activity_invitations(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('iv_locked'), pg_temp.id('iv_t')), '^junto\.activity_locked$');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pf_act('iv_free', 'iv_lo', interval '-20 minutes', 'in_progress', 'public', false);
PERFORM pg_temp.as_('iv_lo');
PERFORM pg_temp.ok('P8 sans validation de présence, inviter reste possible', format($$SELECT public.send_activity_invitations(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('iv_free'), pg_temp.id('iv_t')));

-- ═════ P9 — Un message de covoiturage fait réapparaître un fil masqué ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('hd_o', 'tos'); PERFORM pg_temp.user('hd_d', 'tos'); PERFORM pg_temp.user('hd_p', 'tos');
PERFORM pg_temp.pf_act('hd_act', 'hd_o');
PERFORM pg_temp.pf_part('hd_act', 'hd_d'); PERFORM pg_temp.pf_part('hd_act', 'hd_p');
INSERT INTO public.conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
VALUES ('dm', LEAST(pg_temp.id('hd_d'), pg_temp.id('hd_p')), GREATEST(pg_temp.id('hd_d'), pg_temp.id('hd_p')), pg_temp.id('hd_p'), 'active', 'profile', now(), now());
UPDATE public.conversation_members SET hidden_at = now()
WHERE user_id = pg_temp.id('hd_d') AND conversation_id = (SELECT id FROM public.conversations WHERE type = 'dm'
  AND user_1 = LEAST(pg_temp.id('hd_d'), pg_temp.id('hd_p')) AND user_2 = GREATEST(pg_temp.id('hd_d'), pg_temp.id('hd_p')));
PERFORM pg_temp.eq('P9 fixture : le conducteur a masqué le fil', format($$SELECT count(*)::text FROM public.conversation_members WHERE user_id = %L AND hidden_at IS NOT NULL$$, pg_temp.id('hd_d')), '1');
PERFORM pg_temp.as_('hd_d');
PERFORM pg_temp.ok('P9 hd_d propose 2 places', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint, 'Gap', NULL, 44.56, 6.08, 'Gap')::text$$, pg_temp.id('hd_act')));
PERFORM pg_temp.as_('hd_p');
PERFORM pg_temp.ok('P9 hd_p demande une place', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('hd_act'), pg_temp.id('hd_d')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P9 la demande fait réapparaître le fil chez le conducteur', format($$SELECT count(*)::text FROM public.conversation_members WHERE user_id = %L AND hidden_at IS NOT NULL$$, pg_temp.id('hd_d')), '0');

-- ═════ P10 — Modifications de message diffusées en direct ═════
PERFORM pg_temp.eq('P10 un déclencheur diffuse les modifications et suppressions',
  $$SELECT count(*)::text FROM pg_trigger WHERE tgname = 'trg_messages_broadcast_update' AND tgrelid = 'public.messages'::regclass$$, '1');

-- ═════ P11 — « Sortie modifiée » activé par défaut ═════
PERFORM pg_temp.user('np_u', 'tos');
PERFORM pg_temp.eq('P11 un nouveau compte reçoit les modifications de sortie', format($$SELECT notification_preferences->>'activity_updated' FROM public.users WHERE id = %L$$, pg_temp.id('np_u')), 'true');

-- ═════ P12 — Adresse du projet dans la configuration, fermée par défaut (00524) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P12 l''adresse du projet est lue depuis la configuration', $$SELECT (private.project_url() ~ '^https://[a-z0-9-]+(\.[a-z0-9-]+)+$')::text$$, 'true');
PERFORM pg_temp.eq('P12 plus aucune fonction n''écrit l''adresse en dur',
  $$SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'private') AND p.prosrc ILIKE '%.supabase.co%'$$, '0');
PERFORM pg_temp.eq('P12 les 6 fonctions PostGIS ont « extensions » dans leur chemin',
  $$SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN ('get_activity_detail', 'get_activity_by_invite_token', 'register_as_pro',
      'update_pro_profile', 'handle_activity_update', 'broadcast_map_activity')
      AND 'search_path=public, extensions' = ANY (p.proconfig)$$, '6');
PERFORM pg_temp.eq('P12 aucune fonction SECURITY DEFINER sans chemin fixé',
  $$SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'private') AND p.prokind = 'f' AND p.prosecdef
      AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c WHERE c LIKE 'search_path=%')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')  -- PostGIS's own$$, '0');
PERFORM pg_temp.user('pu_u', 'tos');
PERFORM pg_temp.eq('P12 une photo pro de son propre dossier est acceptée',
  format($$SELECT private.pro_photo_url_ok(pg_temp.host() || '/storage/v1/object/public/pro-photos/' || %L || '/a.jpg', %L)::text$$, pg_temp.get('pu_u'), pg_temp.id('pu_u')), 'true');
PERFORM pg_temp.eq('P12 un hôte étranger est refusé',
  format($$SELECT private.pro_photo_url_ok('https://evil.example.com/storage/v1/object/public/pro-photos/' || %L || '/a.jpg', %L)::text$$, pg_temp.get('pu_u'), pg_temp.id('pu_u')), 'false');
PERFORM pg_temp.put('pu_url', pg_temp.host() || '/storage/v1/object/public/avatars/' || pg_temp.get('pu_u') || '/a.jpg');
DELETE FROM public.app_config WHERE name = 'project_url';
PERFORM pg_temp.eq('P12 sans adresse configurée, toute photo pro est refusée',
  format($$SELECT private.pro_photo_url_ok(%L, %L)::text$$, replace(pg_temp.get('pu_url'), '/avatars/', '/pro-photos/'), pg_temp.id('pu_u')), 'false');
PERFORM pg_temp.as_('pu_u');
PERFORM pg_temp.denied('P12 sans adresse configurée, un avatar est refusé',
  format($$UPDATE public.users SET avatar_url = %L WHERE id = %L$$, pg_temp.get('pu_url'), pg_temp.id('pu_u')), '^Operation not permitted$');
PERFORM pg_temp.as_('db');
INSERT INTO public.app_config (name, value) VALUES ('project_url', 'https://bad.example.com/');
PERFORM pg_temp.eq('P12 une adresse mal formée compte comme absente', $$SELECT coalesce(private.project_url(), 'null')$$, 'null');

-- ═════ P13 — Points de niveau du profil : les valeurs réelles de l'app comptent (00525) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('P13 « 6b » en escalade = Intermédiaire', $$SELECT private.level_tier('climbing-sport', '6b')::text$$, '1');
PERFORM pg_temp.eq('P13 « PD » en alpinisme = Intermédiaire', $$SELECT private.level_tier('mountaineering', 'PD')::text$$, '1');
PERFORM pg_temp.eq('P13 « PD » en via ferrata = Débutant (échelle par sport)', $$SELECT private.level_tier('via-ferrata', 'PD')::text$$, '0');
PERFORM pg_temp.eq('P13 « WI6 » = Expert', $$SELECT private.level_tier('ice-climbing', 'WI6')::text$$, '3');
PERFORM pg_temp.eq('P13 « Classe III » = Intermédiaire', $$SELECT private.level_tier('kayaking', 'Classe III')::text$$, '1');
PERFORM pg_temp.eq('P13 « Avancé » (majuscule) = Avancé', $$SELECT private.level_tier('hiking', 'Avancé')::text$$, '2');
PERFORM pg_temp.eq('P13 « avancé » (ancien format) = Avancé', $$SELECT private.level_tier('hiking', 'avancé')::text$$, '2');
PERFORM pg_temp.eq('P13 « Tous niveaux » = aucun palier', $$SELECT coalesce(private.level_tier('hiking', 'Tous niveaux')::text, 'null')$$, 'null');
PERFORM pg_temp.eq('P13 une cotation d''une autre échelle ne compte pas', $$SELECT coalesce(private.level_tier('hiking', '6b')::text, 'null')$$, 'null');
PERFORM pg_temp.eq('P13 la fonction n''est pas appelable par les clients',
  $$SELECT (has_function_privilege('authenticated', 'private.level_tier(text,text)', 'EXECUTE') OR has_function_privilege('anon', 'private.level_tier(text,text)', 'EXECUTE'))::text$$, 'false');
PERFORM pg_temp.user('lv_u', 'tos'); PERFORM pg_temp.user('lv_o', 'tos'); PERFORM pg_temp.user('lv_viewer', 'tos');
PERFORM pg_temp.pf_act('lv_1', 'lv_o', interval '-30 days', 'completed', 'public', true, true, '6b', 'climbing-sport');
PERFORM pg_temp.pf_act('lv_2', 'lv_o', interval '-20 days', 'completed', 'public', true, true, '6c', 'climbing-sport');
PERFORM pg_temp.pf_act('lv_3', 'lv_o', interval '-10 days', 'completed', 'public', true, true, 'Intermédiaire', 'climbing-sport');
PERFORM pg_temp.pf_part('lv_1', 'lv_u', 'accepted', true); PERFORM pg_temp.pf_part('lv_2', 'lv_u', 'accepted', true);
PERFORM pg_temp.pf_part('lv_3', 'lv_u', 'accepted', true);
PERFORM pg_temp.as_('lv_viewer');
PERFORM pg_temp.eq('P13 trois sorties validées en « 6b » / « 6c » / « Intermédiaire » → 2 points sur le profil',
  format($$SELECT dots::text FROM public.get_user_sport_levels(%L) WHERE sport_key = 'climbing-sport'$$, pg_temp.id('lv_u')), '2');
