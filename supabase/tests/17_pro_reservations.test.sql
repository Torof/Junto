-- Domaine 17 — Pro : réservations « sur demande » (demi-journée, journée, plusieurs jours).
--
-- Chaînes d'autorisation : docs/SECURITY.md « Réservations pro (booking) » (migs 00416-00422,
-- 00443, 00565-00568, 00574-00577). Les bases (refus simple, annulation, avis) sont dans
-- 06_pro ; ici chaque étape de chaque chaîne, les plages de plusieurs jours, la capacité,
-- les conversations, les crons et les trous connus de l'audit 2026-11.
--
-- Non testable ici (une seule transaction, pas de concurrence) :
--   BOOKINGS-2 — inversion d'ordre des verrous accept_booking / cancel_outing / cron (interblocage) ;
--   BOOKINGS-3 — create_manual_booking vérifie les dates fixes avant de verrouiller la plage.
--
-- Calendrier (T = aujourd'hui à Paris) :
--   T+1 / T+2 / T+3  fixtures des crons (insérées directement)
--   T+5   capacité demi-journée          T+6   créneau occupé (agenda importé) le matin
--   T+7   date fixe S1 (matin → après-midi)  T+8/T+9  offre à la journée
--   T+10..T+21  offre sur 3 jours (T+14 pm occupé, date fixe S2 à T+17 matin, T+21 pm fermé)
--   T+22..T+28  plafonds, délai anti-spam, réactivation   T+35  acceptation (blocage, suspension)
--   T+40  annulation de sortie   T+45  fiches participants   T+50  BOOKINGS-4   T+60/61  manuelles

-- ───── Helpers locaux ─────
EXECUTE $p$CREATE FUNCTION pg_temp.d(n int) RETURNS date
  LANGUAGE sql AS $b$ SELECT pg_temp.get('T')::date + n $b$$p$;
-- create_booking(offre, T+n, période, groupe, message)
EXECUTE $p$CREATE FUNCTION pg_temp.bk(p_off text, n int, p_period text, p_party int, p_msg text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format('SELECT public.create_booking(%L, %L, %L, %s, %L)::text',
    pg_temp.id(p_off), pg_temp.d(n), p_period, coalesce(p_party::text, 'NULL'), p_msg) $b$$p$;
-- create_manual_booking(offre, T+n, période, groupe, nom, téléphone)
EXECUTE $p$CREATE FUNCTION pg_temp.man(p_off text, n int, p_period text, p_party int, p_name text DEFAULT 'Client Dehors', p_phone text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format('SELECT public.create_manual_booking(%L, %L, %L, %s, %L, %L)::text',
    pg_temp.id(p_off), pg_temp.d(n), p_period, p_party, p_name, p_phone) $b$$p$;
-- public.<fn>(id de la réservation)
EXECUTE $p$CREATE FUNCTION pg_temp.call(p_fn text, p_label text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format('SELECT public.%s(%L)::text', p_fn, pg_temp.id(p_label)) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pinfo(p_label text, p_info text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format('SELECT public.set_booking_participant_info(%L, %L::jsonb)::text', pg_temp.id(p_label), p_info) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.outmsg(p_off text, n int, p_period text, p_content text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format('SELECT public.message_outing_clients(%L, %L, %L, %L)::text', pg_temp.id(p_off), pg_temp.d(n), p_period, p_content) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.cout(p_off text, n int, p_period text, p_reason text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format('SELECT public.cancel_outing(%L, %L, %L, %L)::text', pg_temp.id(p_off), pg_temp.d(n), p_period, p_reason) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.off_sql(p_title text, p_max int, p_min int DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_pro_offering(p_sport_id := %L, p_title := %L, p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon',
      p_max_participants := %s, p_price_eur := 50, p_price_unit := 'person', p_min_participants := %s)::text$s$,
    pg_temp.id('rs_sport'), p_title, coalesce(p_max::text, 'NULL'), coalesce(p_min::text, 'NULL')) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.reg_sql(p_name text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.register_as_pro(p_display_name := %L, p_company_name := 'SARL Test', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$s$, p_name) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.unlock() RETURNS void
  LANGUAGE sql AS $b$ SELECT set_config('junto.bypass_lock', 'false', true) $b$$p$;
-- Réservation insérée directement (comme 'db') : fixtures datées dans le passé / pour les crons.
EXECUTE $p$CREATE FUNCTION pg_temp.ins(p_label text, p_off text, p_client text, n int, p_period text, p_party int,
    p_status text, p_end int DEFAULT NULL, p_info jsonb DEFAULT NULL, p_age interval DEFAULT '0', p_manual text DEFAULT NULL) RETURNS uuid
  LANGUAGE plpgsql AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.bookings (offering_id, pro_id, client_id, manual_name, day, period, end_day, party_size, status,
                                 participant_info, created_at, last_submitted_at)
    SELECT o.id, o.pro_id, pg_temp.id(p_client), CASE WHEN p_client IS NULL THEN coalesce(p_manual, 'Client Dehors') END,
           pg_temp.d(n), p_period, pg_temp.d(p_end), p_party, p_status, p_info, now() - p_age, now() - p_age
    FROM public.pro_offerings o WHERE o.id = pg_temp.id(p_off)
    RETURNING id INTO v;
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;
-- Notifications d'un compte, d'un type, (optionnellement) d'une réservation.
EXECUTE $p$CREATE FUNCTION pg_temp.nf(p_user text, p_type text, p_bk text DEFAULT NULL) RETURNS SETOF public.notifications
  LANGUAGE sql AS $b$ SELECT * FROM public.notifications WHERE user_id = pg_temp.id(p_user) AND type = p_type
    AND (p_bk IS NULL OR data->>'booking_id' = pg_temp.get(p_bk)) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.dn(p_label text) RETURNS text
  LANGUAGE sql AS $b$ SELECT display_name FROM public.users WHERE id = pg_temp.id(p_label) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.dm(a text, b text) RETURNS uuid
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT id FROM public.conversations WHERE type = 'dm'
    AND user_1 = LEAST(pg_temp.id(a), pg_temp.id(b)) AND user_2 = GREATEST(pg_temp.id(a), pg_temp.id(b)) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.susp(p_label text, p_on boolean) RETURNS void
  LANGUAGE plpgsql AS $b$ BEGIN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE public.users SET suspended_at = CASE WHEN p_on THEN now() END WHERE id = pg_temp.id(p_label);
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.blk(a text, b text, p_on boolean) RETURNS void
  LANGUAGE plpgsql AS $b$ BEGIN
    IF p_on THEN INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id(a), pg_temp.id(b));
    ELSE DELETE FROM public.blocked_users WHERE blocker_id = pg_temp.id(a) AND blocked_id = pg_temp.id(b); END IF;
    PERFORM set_config('junto.bypass_lock', 'false', true);  -- le trigger de blocage le laisse levé
  END $b$$p$;
-- Créneaux ouverts par le pro principal (jour T+n, période).
EXECUTE $p$CREATE FUNCTION pg_temp.slots() RETURNS TABLE(n int, p text)
  LANGUAGE sql AS $b$
    SELECT v.n, w.p FROM (VALUES (5),(6),(7),(8),(27),(28),(29),(30),(31),(35),(40),(45),(50)) v(n), (VALUES ('am'),('pm')) w(p)
    UNION ALL SELECT g.n, w.p FROM generate_series(10, 20) g(n), (VALUES ('am'),('pm')) w(p)
    UNION ALL SELECT v.n, 'am' FROM (VALUES (9),(21),(22),(23),(24),(25),(26)) v(n) $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('T', private.today_paris()::text);
PERFORM pg_temp.put('rs_sport', (SELECT id::text FROM public.sports WHERE key = 'hiking'));
PERFORM pg_temp.user('rs_pro', 'tos');    -- pro principal
PERFORM pg_temp.user('rs_pro2', 'tos');   -- autre pro (propriété croisée, cron des demandes en attente)
PERFORM pg_temp.user('rs_pro3', 'tos');   -- pro suspendu ensuite
PERFORM pg_temp.user('rs_pro4', 'tos');   -- pro dont la vitrine repasse « en attente »
PERFORM pg_temp.user('rs_demo', 'tos');   -- pro de démonstration
PERFORM pg_temp.user('rs_adm', 'tos,admin');
PERFORM pg_temp.user('rs_sus', 'tos,suspended');
PERFORM pg_temp.user('rs_blk', 'tos');    -- bloqué par le pro
PERFORM pg_temp.user('rs_blk2', 'tos');   -- bloque le pro
FOR i IN 1..5 LOOP PERFORM pg_temp.user('rs_cli' || CASE WHEN i = 1 THEN '' ELSE i::text END, 'tos'); END LOOP;
PERFORM pg_temp.user('rs_cap', 'tos');
PERFORM pg_temp.user('rs_cap2', 'tos');
PERFORM pg_temp.user('rs_cool', 'tos');
PERFORM pg_temp.user('rs_soc', 'tos');
PERFORM pg_temp.user('rs_o1', 'tos');
PERFORM pg_temp.user('rs_o2', 'tos');
PERFORM pg_temp.user('rs_o3', 'tos');
PERFORM pg_temp.user('rs_form', 'tos');
FOR i IN 1..4 LOOP PERFORM pg_temp.user('rs_cr' || i, 'tos'); END LOOP;

PERFORM pg_temp.as_('rs_pro');  PERFORM pg_temp.ok('F0 pro s''inscrit', pg_temp.reg_sql('Résa Pro'));
PERFORM pg_temp.as_('rs_pro2'); PERFORM pg_temp.ok('F0 pro2 s''inscrit', pg_temp.reg_sql('Résa Pro Deux'));
PERFORM pg_temp.as_('rs_pro3'); PERFORM pg_temp.ok('F0 pro3 s''inscrit', pg_temp.reg_sql('Résa Pro Trois'));
PERFORM pg_temp.as_('rs_pro4'); PERFORM pg_temp.ok('F0 pro4 s''inscrit', pg_temp.reg_sql('Résa Pro Quatre'));
PERFORM pg_temp.as_('rs_demo'); PERFORM pg_temp.ok('F0 pro démo s''inscrit', pg_temp.reg_sql('Résa Pro Démo'));
PERFORM pg_temp.as_('rs_adm');
PERFORM pg_temp.ok('F0 approbation pro',  format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('rs_pro')));
PERFORM pg_temp.ok('F0 approbation pro2', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('rs_pro2')));
PERFORM pg_temp.ok('F0 approbation pro3', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('rs_pro3')));
PERFORM pg_temp.ok('F0 approbation pro4', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('rs_pro4')));
PERFORM pg_temp.ok('F0 approbation pro démo', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('rs_demo')));
PERFORM pg_temp.unlock();
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET is_demo = true WHERE user_id = pg_temp.id('rs_demo');
PERFORM pg_temp.unlock();

PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.put('off_h', pg_temp.ok('F0 offre demi-journée (max 6)', pg_temp.off_sql('Demi-journée', 6)));
PERFORM pg_temp.put('off_d', pg_temp.ok('F0 offre à la journée (max 6)', pg_temp.off_sql('Journée', 6)));
PERFORM pg_temp.put('off_m', pg_temp.ok('F0 offre sur 3 jours (max 6, min 4)', pg_temp.off_sql('Trois jours', 6, 4)));
PERFORM pg_temp.put('off_r', pg_temp.ok('F0 offre sur 2 jours (réactivation)', pg_temp.off_sql('Deux jours', 6)));
PERFORM pg_temp.put('off_c', pg_temp.ok('F0 offre demi-journée avec minimum 3', pg_temp.off_sql('Minimum trois', 6, 3)));
PERFORM pg_temp.ok('F0 fiche participant sur l''offre demi-journée',
  format($$SELECT public.set_offering_details(%L, NULL, NULL, ARRAY['shoe_size'], ARRAY['Allergies ?'])::text$$, pg_temp.id('off_h')));
PERFORM pg_temp.ok('F0 le pro ouvre son agenda',
  $$SELECT public.set_pro_availability_bulk((SELECT array_agg(pg_temp.d(n) ORDER BY n, p) FROM pg_temp.slots()),
                                            (SELECT array_agg(p ORDER BY n, p) FROM pg_temp.slots()), true)::text$$);
PERFORM pg_temp.put('S1', pg_temp.ok('F0 date fixe S1 (T+7 matin → après-midi)',
  format($$SELECT public.create_pro_session(%L, %L, 'am', %L, 'pm', 4)::text$$, pg_temp.id('off_h'), pg_temp.d(7), pg_temp.d(7))));
PERFORM pg_temp.put('S2', pg_temp.ok('F0 date fixe S2 (T+17 matin)',
  format($$SELECT public.create_pro_session(%L, %L, 'am', %L, 'am', 4)::text$$, pg_temp.id('off_h'), pg_temp.d(17), pg_temp.d(17))));
PERFORM pg_temp.as_('rs_pro2');
PERFORM pg_temp.put('off2', pg_temp.ok('F0 pro2 : offre sans maximum', pg_temp.off_sql('Sans maximum', NULL)));
PERFORM pg_temp.ok('F0 pro2 ouvre T+5 matin', format($$SELECT public.set_pro_availability(%L, 'am', true)::text$$, pg_temp.d(5)));
PERFORM pg_temp.as_('rs_pro3');
PERFORM pg_temp.put('off3', pg_temp.ok('F0 pro3 : offre', pg_temp.off_sql('Offre pro3', 6)));
PERFORM pg_temp.ok('F0 pro3 ouvre T+5 matin', format($$SELECT public.set_pro_availability(%L, 'am', true)::text$$, pg_temp.d(5)));
PERFORM pg_temp.as_('rs_pro4');
PERFORM pg_temp.put('off4', pg_temp.ok('F0 pro4 : offre', pg_temp.off_sql('Offre pro4', 6)));
PERFORM pg_temp.ok('F0 pro4 ouvre T+5 matin', format($$SELECT public.set_pro_availability(%L, 'am', true)::text$$, pg_temp.d(5)));
PERFORM pg_temp.as_('rs_demo');
PERFORM pg_temp.put('offdemo', pg_temp.ok('F0 pro démo : offre', pg_temp.off_sql('Offre démo', 6)));
PERFORM pg_temp.ok('F0 pro démo ouvre T+5 matin', format($$SELECT public.set_pro_availability(%L, 'am', true)::text$$, pg_temp.d(5)));
PERFORM pg_temp.as_('db');
INSERT INTO private.pro_busy_slots (pro_id, day, period) VALUES
  (pg_temp.id('rs_pro'), pg_temp.d(6), 'am'), (pg_temp.id('rs_pro'), pg_temp.d(14), 'pm');
PERFORM pg_temp.blk('rs_pro', 'rs_blk', true);
PERFORM pg_temp.blk('rs_blk2', 'rs_pro', true);

-- ═════ R1 — Sans compte, et fonctions internes ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('R1 anon : create_booking', pg_temp.bk('off_h', 5, 'pm', 1));
PERFORM pg_temp.denied('R1 anon : accept_booking', format($$SELECT public.accept_booking(%L)::text$$, gen_random_uuid()));
PERFORM pg_temp.denied('R1 anon : decline_booking', format($$SELECT public.decline_booking(%L)::text$$, gen_random_uuid()));
PERFORM pg_temp.denied('R1 anon : cancel_booking', format($$SELECT public.cancel_booking(%L)::text$$, gen_random_uuid()));
PERFORM pg_temp.denied('R1 anon : cancel_booking_pro', format($$SELECT public.cancel_booking_pro(%L)::text$$, gen_random_uuid()));
PERFORM pg_temp.denied('R1 anon : create_manual_booking', pg_temp.man('off_h', 60, 'am', 1));
PERFORM pg_temp.denied('R1 anon : set_offering_request_length', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('off_h')));
PERFORM pg_temp.denied('R1 anon : set_booking_participant_info', format($$SELECT public.set_booking_participant_info(%L, '[]'::jsonb)::text$$, gen_random_uuid()));
PERFORM pg_temp.denied('R1 anon : get_pro_availability', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('rs_pro')));
PERFORM pg_temp.denied('R1 anon : get_pro_agenda', $$SELECT count(*)::text FROM public.get_pro_agenda(current_date, current_date + 30)$$);
PERFORM pg_temp.denied('R1 anon : get_my_bookings', $$SELECT count(*)::text FROM public.get_my_bookings()$$);
PERFORM pg_temp.denied('R1 anon : open_booking_conversation', format($$SELECT public.open_booking_conversation(%L)::text$$, gen_random_uuid()));
PERFORM pg_temp.denied('R1 anon : message_outing_clients', pg_temp.outmsg('off_h', 5, 'am', 'x'));
PERFORM pg_temp.denied('R1 anon : cancel_outing', pg_temp.cout('off_h', 5, 'am'));
PERFORM pg_temp.denied('R1 anon : confirm_outing', format($$SELECT public.confirm_outing(%L, %L, 'am')::text$$, pg_temp.id('off_m'), pg_temp.d(10)));
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R1 le pro n''appelle pas private.booking_dm', format($$SELECT private.booking_dm(%L, %L)::text$$, pg_temp.id('rs_pro'), pg_temp.id('rs_cli')), 'permission denied');
PERFORM pg_temp.denied('R1 le pro n''appelle pas private.post_booking_dm', format($$SELECT private.post_booking_dm(%L, %L, 'x')::text$$, gen_random_uuid(), pg_temp.id('rs_pro')), 'permission denied');
PERFORM pg_temp.denied('R1 le pro n''appelle pas private.mark_outing_confirmed',
  format($$SELECT private.mark_outing_confirmed(%L, %L, %L, 'am', NULL, 'pro')::text$$, pg_temp.id('rs_pro'), pg_temp.id('off_m'), pg_temp.d(10)), 'permission denied');
PERFORM pg_temp.denied('R1 le pro ne lit pas private.half_taken', format($$SELECT private.half_taken(%L, %L, 'am')::text$$, pg_temp.id('rs_pro'), pg_temp.d(5)), 'permission denied');
PERFORM pg_temp.denied('R1 le pro ne lit pas private.pro_busy_slots', $$SELECT count(*)::text FROM private.pro_busy_slots$$, 'permission denied');
PERFORM pg_temp.denied('R1 le pro ne lit pas private.outing_confirmations', $$SELECT count(*)::text FROM private.outing_confirmations$$, 'permission denied');
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R1 un membre ne lance pas notify_booking_reminders', $$SELECT private.notify_booking_reminders()::text$$, 'permission denied');
PERFORM pg_temp.denied('R1 un membre ne lance pas notify_pending_booking_requests', $$SELECT private.notify_pending_booking_requests()::text$$, 'permission denied');
PERFORM pg_temp.denied('R1 un membre ne lance pas notify_booking_forms_reminders', $$SELECT private.notify_booking_forms_reminders()::text$$, 'permission denied');
PERFORM pg_temp.denied('R1 un membre ne lance pas notify_booking_forms_missing', $$SELECT private.notify_booking_forms_missing()::text$$, 'permission denied');
PERFORM pg_temp.denied('R1 un membre ne lance pas auto_cancel_short_outings', $$SELECT private.auto_cancel_short_outings()::text$$, 'permission denied');
PERFORM pg_temp.denied('R1 un membre n''écrit pas de créneau occupé', format($$INSERT INTO private.pro_busy_slots (pro_id, day, period) VALUES (%L, %L, 'pm')$$, pg_temp.id('rs_pro'), pg_temp.d(5)), 'permission denied');

-- ═════ R2 — set_offering_request_length ═════
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R2 un membre ne règle pas la durée d''une offre', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('off_h')), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro2');
PERFORM pg_temp.denied('R2 un autre pro ne règle pas la durée de l''offre', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('off_h')), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R2 durée 0 refusée', format($$SELECT public.set_offering_request_length(%L, 0)::text$$, pg_temp.id('off_r')), 'junto.offering_request_days');
PERFORM pg_temp.denied('R2 durée négative refusée', format($$SELECT public.set_offering_request_length(%L, -1)::text$$, pg_temp.id('off_r')), 'junto.offering_request_days');
PERFORM pg_temp.denied('R2 durée 15 refusée', format($$SELECT public.set_offering_request_length(%L, 15)::text$$, pg_temp.id('off_r')), 'junto.offering_request_days');
PERFORM pg_temp.denied('R2 offre inconnue refusée', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, gen_random_uuid()), 'Operation not permitted');
PERFORM pg_temp.ok('R2 durée 14 permise', format($$SELECT public.set_offering_request_length(%L, 14)::text$$, pg_temp.id('off_r')));
PERFORM pg_temp.eq('R2 durée 14 enregistrée', format($$SELECT request_days::text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('off_r')), '14');
PERFORM pg_temp.ok('R2 retour à la demi-journée (NULL)', format($$SELECT public.set_offering_request_length(%L, NULL)::text$$, pg_temp.id('off_r')));
PERFORM pg_temp.eq('R2 NULL enregistré', format($$SELECT coalesce(request_days::text, 'NULL') FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('off_r')), 'NULL');
PERFORM pg_temp.ok('R2 durée 2 sur l''offre de réactivation', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('off_r')));
PERFORM pg_temp.ok('R2 durée 1 (journée)', format($$SELECT public.set_offering_request_length(%L, 1)::text$$, pg_temp.id('off_d')));
PERFORM pg_temp.ok('R2 durée 3 jours', format($$SELECT public.set_offering_request_length(%L, 3)::text$$, pg_temp.id('off_m')));
PERFORM pg_temp.denied('R2 pas d''écriture directe de la durée', format($$WITH u AS (UPDATE public.pro_offerings SET request_days = 5 WHERE id = %L RETURNING 1) SELECT count(*)::text FROM u$$, pg_temp.id('off_m')), 'permission denied');
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.eq('R2 la durée est lisible des membres (pro_offerings_with_coords)',
  format($$SELECT request_days::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('off_m')), '3');

-- ═════ R3 — create_booking : la chaîne (offre à la demi-journée) ═════
PERFORM pg_temp.as_('rs_sus');
PERFORM pg_temp.denied('R3 un suspendu ne réserve pas', pg_temp.bk('off_h', 5, 'pm', 1), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R3 le pro ne réserve pas sa propre offre', pg_temp.bk('off_h', 5, 'pm', 1), 'Operation not permitted');
PERFORM pg_temp.as_('rs_blk');
PERFORM pg_temp.denied('R3 bloqué par le pro : refus', pg_temp.bk('off_h', 5, 'pm', 1), 'Operation not permitted');
PERFORM pg_temp.as_('rs_blk2');
PERFORM pg_temp.denied('R3 qui a bloqué le pro : refus', pg_temp.bk('off_h', 5, 'pm', 1), 'Operation not permitted');
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R3 offre inconnue refusée', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, gen_random_uuid(), pg_temp.d(5)), 'Operation not permitted');
PERFORM pg_temp.denied('R3 période inconnue refusée', pg_temp.bk('off_h', 5, 'night', 1), 'Operation not permitted');
PERFORM pg_temp.denied('R3 période absente refusée', pg_temp.bk('off_h', 5, NULL, 1), 'Operation not permitted');
PERFORM pg_temp.denied('R3 jour passé refusé', pg_temp.bk('off_h', -1, 'am', 1), 'junto.booking_date');
PERFORM pg_temp.denied('R3 jour absent refusé', pg_temp.bk('off_h', NULL, 'am', 1), 'junto.booking_date');
PERFORM pg_temp.denied('R3 au-delà de 6 mois refusé', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, pg_temp.id('off_h'),
  (pg_temp.get('T')::date + interval '6 months' + interval '1 day')::date), 'junto.booking_date');
PERFORM pg_temp.denied('R3 groupe de 0 refusé', pg_temp.bk('off_h', 5, 'pm', 0), 'junto.booking_party_size');
PERFORM pg_temp.denied('R3 groupe absent refusé', pg_temp.bk('off_h', 5, 'pm', NULL), 'junto.booking_party_size');
PERFORM pg_temp.denied('R3 groupe au-delà du maximum (7 > 6) refusé', pg_temp.bk('off_h', 5, 'pm', 7), 'junto.booking_party_size');
PERFORM pg_temp.denied('R3 offre sans maximum : 51 refusé (plafond 50)', pg_temp.bk('off2', 5, 'am', 51), 'junto.booking_party_size');
PERFORM pg_temp.denied('R3 demi-journée non ouverte refusée', pg_temp.bk('off_h', 9, 'pm', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R3 demi-journée occupée dans l''agenda importé refusée', pg_temp.bk('off_h', 6, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R3 demi-journée d''une date fixe refusée', pg_temp.bk('off_h', 7, 'pm', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R3 date fixe : une autre offre du pro est refusée aussi', pg_temp.bk('off_d', 7, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R3 message de plus de 500 caractères refusé', pg_temp.bk('off_h', 5, 'am', 1, repeat('x', 501)), 'junto.booking_message');
PERFORM pg_temp.as_('rs_cli2');
PERFORM pg_temp.ok('R3 offre sans maximum : groupe de 50 permis', pg_temp.bk('off2', 5, 'am', 50));
PERFORM pg_temp.as_('rs_cli3');
PERFORM pg_temp.ok('R3 l''après-midi d''un matin occupé reste réservable', pg_temp.bk('off_h', 6, 'pm', 1));

-- Capacité : seules les réservations ACCEPTÉES comptent, toutes offres du pro confondues.
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.put('bk_c1', pg_temp.ok('R3 le client demande 4 places (T+5 matin)', pg_temp.bk('off_h', 5, 'am', 4, '<b>MSG-SECRET-42</b> bonjour')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R3 la demande est en attente, en demi-journée (end_day NULL)',
  format($$SELECT status || '/' || period || '/' || coalesce(end_day::text, 'NULL') FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_c1')), 'pending/am/NULL');
PERFORM pg_temp.eq('R3 le pro reçoit une notification booking_request', $$SELECT count(*)::text FROM pg_temp.nf('rs_pro', 'booking_request', 'bk_c1')$$, '1');
PERFORM pg_temp.eq('R3 le message du client n''est jamais dans la notification',
  $$SELECT count(*)::text FROM pg_temp.nf('rs_pro', 'booking_request', 'bk_c1') WHERE title || body || data::text LIKE '%MSG-SECRET%'$$, '0');
PERFORM pg_temp.eq('R3 la notification nomme le client et le groupe',
  $$SELECT (body LIKE pg_temp.dn('rs_cli') || '%' AND data->'params'->>'count' = '4')::text FROM pg_temp.nf('rs_pro', 'booking_request', 'bk_c1')$$, 'true');
PERFORM pg_temp.eq('R3 demi-journée : pas de variante', $$SELECT coalesce(data->>'variant', 'NULL') FROM pg_temp.nf('rs_pro', 'booking_request', 'bk_c1')$$, 'NULL');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.ok('R3 le pro accepte les 4 places', pg_temp.call('accept_booking', 'bk_c1'));
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R3 redemander un créneau déjà accepté refusé', pg_temp.bk('off_h', 5, 'am', 1), 'junto.booking_already');
PERFORM pg_temp.as_('rs_cli2');
PERFORM pg_temp.denied('R3 3 places de plus sur 6 (4 acceptées) : complet', pg_temp.bk('off_h', 5, 'am', 3), 'junto.booking_full');
PERFORM pg_temp.put('bk_c2', pg_temp.ok('R3 2 places restantes : demande permise', pg_temp.bk('off_h', 5, 'am', 2)));
PERFORM pg_temp.denied('R3 double demande en attente refusée', pg_temp.bk('off_h', 5, 'am', 1), 'junto.booking_already');
PERFORM pg_temp.as_('rs_cli3');
PERFORM pg_temp.put('bk_c3', pg_temp.ok('R3 une demande en attente ne bloque pas les autres', pg_temp.bk('off_h', 5, 'am', 2)));
PERFORM pg_temp.as_('rs_cli4');
PERFORM pg_temp.denied('R3 les places comptent toutes offres confondues (journée sur un matin à 4/6)', pg_temp.bk('off_d', 5, 'am', 3), 'junto.booking_full');

-- Démo, pro non approuvé, pro suspendu.
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R3 rideau démo : un membre ne réserve pas un pro de démo', pg_temp.bk('offdemo', 5, 'am', 1), 'Operation not permitted');
PERFORM pg_temp.as_('db');
UPDATE public.app_config SET value = 'false' WHERE name = 'demo_mode';
PERFORM pg_temp.as_('rs_adm');
PERFORM pg_temp.denied('R3 rideau démo : mode démo éteint, l''admin non plus', pg_temp.bk('offdemo', 5, 'am', 1), 'Operation not permitted');
PERFORM pg_temp.as_('db');
UPDATE public.app_config SET value = 'true' WHERE name = 'demo_mode';
PERFORM pg_temp.as_('rs_adm');
PERFORM pg_temp.ok('R3 rideau démo : mode démo allumé, l''admin réserve', pg_temp.bk('offdemo', 5, 'am', 1));
PERFORM pg_temp.as_('rs_cli3');
PERFORM pg_temp.put('bk_p3', pg_temp.ok('R3 demande chez pro3 (avant sa suspension)', pg_temp.bk('off3', 5, 'am', 1)));
PERFORM pg_temp.as_('rs_cli4');
PERFORM pg_temp.put('bk_p4', pg_temp.ok('R3 demande chez pro4 (avant le retrait de son approbation)', pg_temp.bk('off4', 5, 'am', 1)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.susp('rs_pro3', true);
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET status = 'pending' WHERE user_id = pg_temp.id('rs_pro4');
PERFORM pg_temp.unlock();
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R3 offre d''un pro suspendu refusée', pg_temp.bk('off3', 5, 'am', 1), 'Operation not permitted');
PERFORM pg_temp.denied('R3 offre d''un pro non approuvé refusée', pg_temp.bk('off4', 5, 'am', 1), 'Operation not permitted');

-- ═════ R4 — Plafonds, délai anti-spam, réactivation ═════
-- 5 demandes en attente : une demande passée en attente ne compte pas (00523).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ins('cap_past', 'off_h', 'rs_cap', -1, 'am', 1, 'pending');
PERFORM pg_temp.as_('rs_cap');
FOR i IN 22..25 LOOP PERFORM pg_temp.ok('R4 demande en attente n°' || (i - 21), pg_temp.bk('off_h', i, 'am', 1)); END LOOP;
PERFORM pg_temp.ok('R4 5e demande en attente permise (la demande passée ne compte pas)', pg_temp.bk('off_h', 26, 'am', 1));
PERFORM pg_temp.denied('R4 6e demande en attente refusée', pg_temp.bk('off_h', 27, 'am', 1), 'junto.booking_pending_cap');
-- 10 demandes par 24 h glissantes, tous statuts.
PERFORM pg_temp.as_('db');
FOR i IN 11..20 LOOP PERFORM pg_temp.ins('cap2_' || i, 'off_h', 'rs_cap2', -i, 'am', 1, 'declined'); END LOOP;
PERFORM pg_temp.as_('rs_cap2');
PERFORM pg_temp.denied('R4 11e demande en 24 h refusée', pg_temp.bk('off_h', 27, 'pm', 1), 'junto.booking_daily_cap');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.bookings SET created_at = now() - interval '25 hours' WHERE id = pg_temp.id('cap2_11');
PERFORM pg_temp.unlock();
PERFORM pg_temp.as_('rs_cap2');
PERFORM pg_temp.ok('R4 une demande de plus de 24 h ne compte plus', pg_temp.bk('off_h', 27, 'pm', 1));
-- Délai d'1 h et 5 soumissions par créneau ; la réactivation réutilise la ligne.
PERFORM pg_temp.as_('rs_cool');
PERFORM pg_temp.put('bk_cool', pg_temp.ok('R4 demande (T+27 matin)', pg_temp.bk('off_h', 27, 'am', 1)));
PERFORM pg_temp.ok('R4 le client annule sa demande en attente', pg_temp.call('cancel_booking', 'bk_cool'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R4 une demande en attente annulée ne notifie pas le pro', $$SELECT count(*)::text FROM pg_temp.nf('rs_pro', 'booking_cancelled', 'bk_cool')$$, '0');
PERFORM pg_temp.as_('rs_cool');
PERFORM pg_temp.denied('R4 redemander dans l''heure : délai anti-spam', pg_temp.bk('off_h', 27, 'am', 1), 'junto.booking_cooldown');
PERFORM pg_temp.as_('db');
UPDATE public.bookings SET last_submitted_at = now() - interval '3 hours', submitted_count = 0 WHERE id = pg_temp.id('bk_cool');
PERFORM pg_temp.eq('R4 sans bypass, le trigger fige last_submitted_at et submitted_count',
  format($$SELECT (last_submitted_at = now())::text || '/' || submitted_count FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_cool')), 'true/1');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.bookings SET last_submitted_at = now() - interval '2 hours' WHERE id = pg_temp.id('bk_cool');
PERFORM pg_temp.unlock();
PERFORM pg_temp.as_('rs_cool');
PERFORM pg_temp.eq('R4 après le délai : la même ligne est réactivée', pg_temp.bk('off_h', 27, 'am', 2), pg_temp.get('bk_cool'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R4 réactivation : en attente, 2 soumissions, nouveau groupe',
  format($$SELECT status || '/' || submitted_count || '/' || party_size FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_cool')), 'pending/2/2');
PERFORM pg_temp.as_('rs_cool');
PERFORM pg_temp.ok('R4 le client annule encore', pg_temp.call('cancel_booking', 'bk_cool'));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.bookings SET last_submitted_at = now() - interval '2 hours', submitted_count = 5 WHERE id = pg_temp.id('bk_cool');
PERFORM pg_temp.unlock();
PERFORM pg_temp.as_('rs_cool');
PERFORM pg_temp.denied('R4 5 soumissions sur ce créneau : plus jamais', pg_temp.bk('off_h', 27, 'am', 1), 'junto.booking_cooldown');
-- Réactivation d'une demande sur plusieurs jours : end_day recalculé, session_id remis à NULL.
PERFORM pg_temp.put('bk_r', pg_temp.ok('R4 demande sur 2 jours (T+28)', pg_temp.bk('off_r', 28, 'am', 1)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R4 end_day = départ + 1', format($$SELECT end_day::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_r')), pg_temp.d(29)::text);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.ok('R4 le pro refuse', pg_temp.call('decline_booking', 'bk_r'));
PERFORM pg_temp.ok('R4 le pro passe l''offre à 3 jours', format($$SELECT public.set_offering_request_length(%L, 3)::text$$, pg_temp.id('off_r')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R4 les réservations existantes gardent leur plage', format($$SELECT end_day::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_r')), pg_temp.d(29)::text);
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.bookings SET last_submitted_at = now() - interval '2 hours', session_id = pg_temp.id('S1') WHERE id = pg_temp.id('bk_r');
PERFORM pg_temp.unlock();
PERFORM pg_temp.as_('rs_cool');
PERFORM pg_temp.eq('R4 la demande refusée est réactivée (même ligne)', pg_temp.bk('off_r', 28, 'am', 1), pg_temp.get('bk_r'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R4 réactivation : end_day recalculé (3 jours) et session_id remis à NULL',
  format($$SELECT end_day::text || '/' || coalesce(session_id::text, 'NULL') FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_r')), pg_temp.d(30)::text || '/NULL');

-- ═════ R5 — Plusieurs jours et journée : la plage est celle de la base ═════
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R5 3 jours : un départ l''après-midi est refusé', pg_temp.bk('off_m', 10, 'pm', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.put('bk_A', pg_temp.ok('R5 3 jours : demande de 4 places au départ de T+10', pg_temp.bk('off_m', 10, 'am', 4)));
PERFORM pg_temp.denied('R5 une demi-journée occupée dans la plage (T+14 pm) refuse la demande', pg_temp.bk('off_m', 13, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R5 une date fixe dans la plage (T+17 matin) refuse la demande', pg_temp.bk('off_m', 16, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R5 la dernière demi-journée fermée (T+21 pm) refuse la demande', pg_temp.bk('off_m', 19, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R5 journée : un départ l''après-midi est refusé', pg_temp.bk('off_d', 8, 'pm', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R5 journée : l''après-midi fermé refuse la journée', pg_temp.bk('off_d', 9, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.put('bk_D', pg_temp.ok('R5 journée : demande de 2 places (T+8)', pg_temp.bk('off_d', 8, 'am', 2)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R5 3 jours : départ matin, fin calculée à T+12',
  format($$SELECT day::text || '/' || period || '/' || end_day::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_A')),
  pg_temp.d(10)::text || '/am/' || pg_temp.d(12)::text);
PERFORM pg_temp.eq('R5 journée : fin = le jour même', format($$SELECT end_day::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_D')), pg_temp.d(8)::text);
PERFORM pg_temp.eq('R5 notif 3 jours : variante multi, 3 jours, « du … au … »',
  format($$SELECT (data->>'variant' = 'multi' AND data->'params'->>'days' = '3' AND body LIKE %L)::text FROM pg_temp.nf('rs_pro', 'booking_request', 'bk_A')$$,
    '%du ' || to_char(pg_temp.d(10), 'DD/MM') || ' au ' || to_char(pg_temp.d(12), 'DD/MM') || '%'), 'true');
PERFORM pg_temp.eq('R5 notif journée : variante day, « journée »',
  $$SELECT (data->>'variant' = 'day' AND body LIKE '%, journée%')::text FROM pg_temp.nf('rs_pro', 'booking_request', 'bk_D')$$, 'true');
-- end_day : aucune écriture client, figé par le trigger whitelist.
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R5 le client ne modifie pas end_day', format($$WITH u AS (UPDATE public.bookings SET end_day = %L WHERE id = %L RETURNING 1) SELECT count(*)::text FROM u$$, pg_temp.d(20), pg_temp.id('bk_A')), 'permission denied');
PERFORM pg_temp.denied('R5 le client ne lit pas end_day dans la table', format($$SELECT end_day::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_A')), 'permission denied');
PERFORM pg_temp.as_('db');
UPDATE public.bookings SET end_day = pg_temp.d(13), day = pg_temp.d(11) WHERE id = pg_temp.id('bk_A');
PERFORM pg_temp.eq('R5 sans bypass, le trigger fige day et end_day',
  format($$SELECT day::text || '/' || end_day::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_A')), pg_temp.d(10)::text || '/' || pg_temp.d(12)::text);
PERFORM pg_temp.denied('R5 la table refuse une plage de plus de 14 jours', format($$UPDATE public.bookings SET end_day = day + 14 WHERE id = %L AND set_config('junto.bypass_lock', 'true', true) = 'true'$$, pg_temp.id('bk_A')), 'bookings_end_day_range|violates');

-- ═════ R6 — accept_booking ═════
-- bk_F : demande en attente sur une demi-journée couverte par bk_A (pending ne bloque pas).
PERFORM pg_temp.as_('rs_cli3');
PERFORM pg_temp.put('bk_F', pg_temp.ok('R6 demande de 3 places à T+11 (bk_A encore en attente)', pg_temp.bk('off_h', 11, 'am', 3)));
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R6 le client n''accepte pas', pg_temp.call('accept_booking', 'bk_A'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro2');
PERFORM pg_temp.denied('R6 un autre pro n''accepte pas', pg_temp.call('accept_booking', 'bk_A'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro3');
PERFORM pg_temp.denied('R6 un pro suspendu n''accepte pas', pg_temp.call('accept_booking', 'bk_p3'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro4');
PERFORM pg_temp.denied('R6 un pro non approuvé n''accepte pas', pg_temp.call('accept_booking', 'bk_p4'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R6 réservation inconnue refusée', format($$SELECT public.accept_booking(%L)::text$$, gen_random_uuid()), 'Operation not permitted');
PERFORM pg_temp.put('conv_cli', pg_temp.ok('R6 le pro accepte les 3 jours', pg_temp.call('accept_booking', 'bk_A')));
PERFORM pg_temp.ok('R6 le pro accepte la journée', pg_temp.call('accept_booking', 'bk_D'));
PERFORM pg_temp.denied('R6 la plage de bk_A (T+10..T+12, 4/6) rend bk_F (3 places à T+11) inacceptable', pg_temp.call('accept_booking', 'bk_F'), 'junto.booking_full');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R6 accept renvoie le DM du client et du pro', $$SELECT pg_temp.dm('rs_cli', 'rs_pro')::text$$, pg_temp.get('conv_cli'));
PERFORM pg_temp.eq('R6 DM actif, étiqueté booking',
  $$SELECT status || '/' || initiated_from FROM public.conversations WHERE id = pg_temp.dm('rs_cli', 'rs_pro')$$, 'active/booking');
PERFORM pg_temp.eq('R6 message de confirmation posté par le pro avec la plage',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = pg_temp.dm('rs_cli', 'rs_pro') AND sender_id = pg_temp.id('rs_pro')
    AND metadata->>'type' = 'booking_accepted' AND metadata->>'booking_id' = pg_temp.get('bk_A') AND content LIKE %L$$,
    '%du ' || to_char(pg_temp.d(10), 'DD/MM') || ' au ' || to_char(pg_temp.d(12), 'DD/MM') || '%'), '1');
PERFORM pg_temp.eq('R6 notif booking_accepted : demi-journée sans variante', $$SELECT coalesce(data->>'variant', 'NULL') FROM pg_temp.nf('rs_cli', 'booking_accepted', 'bk_c1')$$, 'NULL');
PERFORM pg_temp.eq('R6 notif booking_accepted : 3 jours = multi', $$SELECT data->>'variant' || '/' || (data->'params'->>'days') FROM pg_temp.nf('rs_cli', 'booking_accepted', 'bk_A')$$, 'multi/3');
PERFORM pg_temp.eq('R6 notif booking_accepted : journée = day', $$SELECT data->>'variant' FROM pg_temp.nf('rs_cli', 'booking_accepted', 'bk_D')$$, 'day');
PERFORM pg_temp.eq('R6 notif booking_accepted : le DM est joint', $$SELECT data->>'conversation_id' FROM pg_temp.nf('rs_cli', 'booking_accepted', 'bk_A')$$, pg_temp.get('conv_cli'));
PERFORM pg_temp.eq('R6 minimum (4) atteint : sortie confirmée une fois',
  format($$SELECT count(*)::text FROM private.outing_confirmations WHERE offering_id = %L AND day = %L AND period = 'am' AND session_id IS NULL AND reason = 'minimum'$$, pg_temp.id('off_m'), pg_temp.d(10)), '1');
PERFORM pg_temp.eq('R6 « Départ confirmé » au client', $$SELECT count(*)::text FROM pg_temp.nf('rs_cli', 'booking_confirmed', 'bk_A')$$, '1');
-- Un 2e groupe sur la même sortie : pas de seconde confirmation.
PERFORM pg_temp.as_('rs_cli4');
PERFORM pg_temp.put('bk_A4', pg_temp.ok('R6 2 places de plus sur la sortie de 3 jours', pg_temp.bk('off_m', 10, 'am', 2)));
PERFORM pg_temp.as_('rs_cli5');
PERFORM pg_temp.put('bk_A5', pg_temp.ok('R6 une demande en attente sur la même sortie', pg_temp.bk('off_m', 10, 'am', 1)));
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.ok('R6 le pro accepte le 2e groupe', pg_temp.call('accept_booking', 'bk_A4'));
PERFORM pg_temp.denied('R6 sortie pleine (6/6) : la demande en attente ne passe plus', pg_temp.call('accept_booking', 'bk_A5'), 'junto.booking_full');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R6 sortie déjà confirmée : pas de second « Départ confirmé »', $$SELECT count(*)::text FROM pg_temp.nf('rs_cli', 'booking_confirmed')$$, '1');
PERFORM pg_temp.eq('R6 le 2e groupe n''est pas reconfirmé', $$SELECT count(*)::text FROM pg_temp.nf('rs_cli4', 'booking_confirmed', 'bk_A4')$$, '0');
-- La plage compte pour les nouvelles demandes, jusqu'à l'après-midi du dernier jour.
PERFORM pg_temp.as_('rs_cli2');
PERFORM pg_temp.denied('R6 plage acceptée : l''après-midi du dernier jour est plein', pg_temp.bk('off_h', 12, 'pm', 1), 'junto.booking_full');
PERFORM pg_temp.put('bk_E', pg_temp.ok('R6 le lendemain de la plage est libre', pg_temp.bk('off_h', 13, 'am', 3)));
PERFORM pg_temp.as_('rs_cli4');
PERFORM pg_temp.denied('R6 journée chevauchant la plage : complet', pg_temp.bk('off_d', 12, 'am', 1), 'junto.booking_full');
-- Jour passé, client suspendu, blocage, date fixe apparue entre-temps.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ins('bk_past', 'off_h', 'rs_cli5', -1, 'am', 1, 'pending');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R6 demande d''un jour passé : refus', pg_temp.call('accept_booking', 'bk_past'), 'junto.booking_date');
PERFORM pg_temp.as_('rs_cli5');
PERFORM pg_temp.put('bk_s', pg_temp.ok('R6 demande (T+35 matin)', pg_temp.bk('off_h', 35, 'am', 1)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.susp('rs_cli5', true);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R6 client suspendu : refus', pg_temp.call('accept_booking', 'bk_s'), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.susp('rs_cli5', false);
PERFORM pg_temp.blk('rs_pro', 'rs_cli5', true);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R6 le pro a bloqué le client : refus', pg_temp.call('accept_booking', 'bk_s'), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.blk('rs_pro', 'rs_cli5', false);
PERFORM pg_temp.blk('rs_cli5', 'rs_pro', true);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R6 le client a bloqué le pro : refus', pg_temp.call('accept_booking', 'bk_s'), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.blk('rs_cli5', 'rs_pro', false);
INSERT INTO public.pro_sessions (pro_id, offering_id, start_day, start_period, end_day, end_period, max_participants)
VALUES (pg_temp.id('rs_pro'), pg_temp.id('off_c'), pg_temp.d(35), 'am', pg_temp.d(35), 'pm', 4);
PERFORM pg_temp.put('S35', (SELECT id::text FROM public.pro_sessions WHERE pro_id = pg_temp.id('rs_pro') AND start_day = pg_temp.d(35)));
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R6 une date fixe posée sur le créneau entre-temps : refus', pg_temp.call('accept_booking', 'bk_s'), 'junto.booking_slot_unavailable');
PERFORM pg_temp.as_('db');
UPDATE public.pro_sessions SET status = 'cancelled' WHERE id = pg_temp.id('S35');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.ok('R6 date annulée : l''acceptation passe', pg_temp.call('accept_booking', 'bk_s'));

-- ═════ R7 — Refus et annulations (compléments de 06_pro) ═════
PERFORM pg_temp.as_('rs_pro3');
PERFORM pg_temp.denied('R7 un pro suspendu ne refuse pas', pg_temp.call('decline_booking', 'bk_p3'), 'Operation not permitted');
PERFORM pg_temp.denied('R7 un pro suspendu n''annule pas', pg_temp.call('cancel_booking_pro', 'bk_p3'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro4');
PERFORM pg_temp.ok('R7 un pro dont l''approbation est retirée garde l''annulation', pg_temp.call('cancel_booking_pro', 'bk_p4'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R7 annuler une demande en attente ne notifie pas le client', $$SELECT count(*)::text FROM pg_temp.nf('rs_cli4', 'booking_cancelled', 'bk_p4')$$, '0');
PERFORM pg_temp.as_('rs_pro2');
PERFORM pg_temp.denied('R7 un autre pro ne refuse pas', pg_temp.call('decline_booking', 'bk_E'), 'Operation not permitted');
PERFORM pg_temp.denied('R7 un autre pro n''annule pas', pg_temp.call('cancel_booking_pro', 'bk_E'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_cli2');
PERFORM pg_temp.denied('R7 le client ne refuse pas sa propre demande', pg_temp.call('decline_booking', 'bk_E'), 'Operation not permitted');
PERFORM pg_temp.denied('R7 le client n''utilise pas l''annulation pro', pg_temp.call('cancel_booking_pro', 'bk_E'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.ok('R7 le pro refuse une demande sur 3 jours', pg_temp.call('decline_booking', 'bk_A5'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R7 le client est notifié du refus (jour de départ)',
  format($$SELECT count(*)::text FROM pg_temp.nf('rs_cli5', 'booking_declined', 'bk_A5') WHERE body LIKE %L$$, '%' || to_char(pg_temp.d(10), 'DD/MM') || '%'), '1');
PERFORM pg_temp.ins('bk_past_acc', 'off_h', 'rs_cli5', -3, 'am', 1, 'accepted');
PERFORM pg_temp.as_('rs_cli5');
PERFORM pg_temp.denied('R7 le client n''annule pas une sortie passée', pg_temp.call('cancel_booking', 'bk_past_acc'), 'junto.booking_date');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R7 le pro n''annule pas une sortie passée', pg_temp.call('cancel_booking_pro', 'bk_past_acc'), 'junto.booking_date');
-- BOOKINGS-4 (corrigé 00578) : blocage après acceptation, puis annulation par le client — le pro est
-- prévenu (variante client_gone), sans le nom, dans les deux sens du blocage.
PERFORM pg_temp.as_('rs_cli4');
PERFORM pg_temp.put('bk_b4a', pg_temp.ok('R7 demande (T+50 matin)', pg_temp.bk('off_h', 50, 'am', 1)));
PERFORM pg_temp.as_('rs_cli2');
PERFORM pg_temp.put('bk_b4b', pg_temp.ok('R7 demande (T+50 après-midi)', pg_temp.bk('off_h', 50, 'pm', 1)));
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.ok('R7 acceptation T+50 matin', pg_temp.call('accept_booking', 'bk_b4a'));
PERFORM pg_temp.ok('R7 acceptation T+50 après-midi', pg_temp.call('accept_booking', 'bk_b4b'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.blk('rs_pro', 'rs_cli4', true);
PERFORM pg_temp.blk('rs_cli2', 'rs_pro', true);
PERFORM pg_temp.as_('rs_cli4');
PERFORM pg_temp.ok('R7 bloqué par le pro, le client annule quand même', pg_temp.call('cancel_booking', 'bk_b4a'));
PERFORM pg_temp.as_('rs_cli2');
PERFORM pg_temp.ok('R7 ayant bloqué le pro, le client annule quand même', pg_temp.call('cancel_booking', 'bk_b4b'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R7 BOOKINGS-4 : le pro a bloqué le client, sa notification ne le nomme pas',
  $$SELECT count(*)::text FROM pg_temp.nf('rs_pro', 'booking_cancelled', 'bk_b4a') WHERE title || body || data::text LIKE '%' || pg_temp.dn('rs_cli4') || '%'$$, '0');
PERFORM pg_temp.eq('R7 BOOKINGS-4 : le client a bloqué le pro, la notification ne le nomme pas',
  $$SELECT count(*)::text FROM pg_temp.nf('rs_pro', 'booking_cancelled', 'bk_b4b') WHERE title || body || data::text LIKE '%' || pg_temp.dn('rs_cli2') || '%'$$, '0');
PERFORM pg_temp.eq('R7 BOOKINGS-4 : le pro est quand même prévenu, variante client_gone (les deux sens)',
  $$SELECT string_agg(coalesce(data->>'variant', 'NULL'), ',') FROM (SELECT * FROM pg_temp.nf('rs_pro', 'booking_cancelled', 'bk_b4a')
    UNION ALL SELECT * FROM pg_temp.nf('rs_pro', 'booking_cancelled', 'bk_b4b')) n$$, 'client_gone,client_gone');
PERFORM pg_temp.blk('rs_pro', 'rs_cli4', false);
PERFORM pg_temp.blk('rs_cli2', 'rs_pro', false);

-- ═════ R8 — create_manual_booking ═════
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.put('bk_man_m', pg_temp.ok('R8 3 jours : saisie demandée l''après-midi', pg_temp.man('off_m', 60, 'pm', 2, 'Groupe Dehors')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R8 3 jours : départ forcé le matin, même plage qu''un client',
  format($$SELECT period || '/' || end_day::text || '/' || status FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_man_m')), 'am/' || pg_temp.d(62)::text || '/accepted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R8 3 jours : une date fixe dans la plage refuse la saisie', pg_temp.man('off_m', 16, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.put('bk_man_s', pg_temp.ok('R8 au départ d''une date fixe : inscription à cette date', pg_temp.man('off_h', 7, 'am', 2)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R8 rattachée à la date, sans plage propre',
  format($$SELECT session_id::text || '/' || coalesce(end_day::text, 'NULL') FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_man_s')), pg_temp.get('S1') || '/NULL');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R8 date fixe : une demi-journée autre que le départ est refusée', pg_temp.man('off_h', 7, 'pm', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R8 date fixe : une autre offre est refusée', pg_temp.man('off_d', 7, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('R8 date fixe : au-delà de ses places (2 + 3 > 4)', pg_temp.man('off_h', 7, 'am', 3), 'junto.booking_full');
PERFORM pg_temp.ok('R8 saisie sur une demi-journée non ouverte permise (son agenda)', pg_temp.man('off_h', 9, 'pm', 1));
PERFORM pg_temp.put('bk_man_cap', pg_temp.ok('R8 saisie de 5 personnes (T+45 après-midi)', pg_temp.man('off_h', 45, 'pm', 5)));
PERFORM pg_temp.as_('rs_form');
PERFORM pg_temp.denied('R8 une réservation manuelle compte dans les places', pg_temp.bk('off_h', 45, 'pm', 2), 'junto.booking_full');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.put('bk_man_c', pg_temp.ok('R8 saisie de 3 personnes sur une offre à minimum 3', pg_temp.man('off_c', 61, 'am', 3)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R8 minimum atteint par une saisie manuelle : sortie confirmée',
  format($$SELECT count(*)::text FROM private.outing_confirmations WHERE offering_id = %L AND day = %L AND period = 'am'$$, pg_temp.id('off_c'), pg_temp.d(61)), '1');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R8 nom de plus de 80 caractères refusé', pg_temp.man('off_h', 60, 'am', 1, repeat('x', 81)), 'junto.booking_manual_name');
PERFORM pg_temp.denied('R8 téléphone trop court refusé', pg_temp.man('off_h', 60, 'am', 1, 'Nom', 'ab'), 'junto.booking_manual_name');
PERFORM pg_temp.denied('R8 groupe au-delà du maximum refusé', pg_temp.man('off_h', 60, 'am', 7), 'junto.booking_party_size');
PERFORM pg_temp.denied('R8 jour passé refusé', pg_temp.man('off_h', -1, 'am', 1), 'junto.booking_date');
PERFORM pg_temp.denied('R8 période inconnue refusée', pg_temp.man('off_h', 60, 'night', 1), 'Operation not permitted');
PERFORM pg_temp.denied('R8 une réservation manuelle ne s''accepte pas', pg_temp.call('accept_booking', 'bk_man_m'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro3');
PERFORM pg_temp.denied('R8 un pro suspendu ne saisit pas', pg_temp.man('off3', 60, 'am', 1), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro4');
PERFORM pg_temp.denied('R8 un pro non approuvé ne saisit pas', pg_temp.man('off4', 60, 'am', 1), 'Operation not permitted');

-- ═════ R9 — open_booking_conversation ═════
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R9 le client n''ouvre pas par cette voie', pg_temp.call('open_booking_conversation', 'bk_A'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro2');
PERFORM pg_temp.denied('R9 un autre pro n''ouvre pas', pg_temp.call('open_booking_conversation', 'bk_A'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro3');
PERFORM pg_temp.denied('R9 un pro suspendu n''ouvre pas', pg_temp.call('open_booking_conversation', 'bk_p3'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R9 réservation manuelle : pas de fil', pg_temp.call('open_booking_conversation', 'bk_man_m'), 'Operation not permitted');
PERFORM pg_temp.denied('R9 réservation annulée : pas de fil', pg_temp.call('open_booking_conversation', 'bk_cool'), 'Operation not permitted');
PERFORM pg_temp.denied('R9 réservation refusée : pas de fil', pg_temp.call('open_booking_conversation', 'bk_A5'), 'Operation not permitted');
PERFORM pg_temp.denied('R9 réservation inconnue : refus', format($$SELECT public.open_booking_conversation(%L)::text$$, gen_random_uuid()), 'Operation not permitted');
PERFORM pg_temp.put('conv_c3', pg_temp.ok('R9 le pro ouvre le fil dès la demande', pg_temp.call('open_booking_conversation', 'bk_c3')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R9 c''est le DM de la paire', $$SELECT pg_temp.dm('rs_cli3', 'rs_pro')::text$$, pg_temp.get('conv_c3'));
PERFORM pg_temp.eq('R9 DM actif, étiqueté booking, sans message seed',
  $$SELECT c.status || '/' || c.initiated_from || '/' || (SELECT count(*) FROM public.messages m WHERE m.conversation_id = c.id)
    FROM public.conversations c WHERE c.id = pg_temp.dm('rs_cli3', 'rs_pro')$$, 'active/booking/0');
-- Une demande de contact sociale en attente est reprise en fil logistique, purgée.
INSERT INTO public.conversations (type, user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message)
VALUES ('dm', LEAST(pg_temp.id('rs_soc'), pg_temp.id('rs_pro')), GREATEST(pg_temp.id('rs_soc'), pg_temp.id('rs_pro')),
        pg_temp.id('rs_soc'), 'pending_request', 'profile', pg_temp.id('rs_soc'), 'Salut, on se connaît ?');
PERFORM pg_temp.as_('rs_soc');
PERFORM pg_temp.put('bk_soc', pg_temp.ok('R9 demande d''un membre qui a une demande de contact en attente', pg_temp.bk('off_h', 35, 'pm', 1)));
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.eq('R9 le fil existant est réutilisé', pg_temp.call('open_booking_conversation', 'bk_soc'), (SELECT pg_temp.dm('rs_soc', 'rs_pro')::text));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R9 réactivé en logistique : actif, booking, demande sociale purgée',
  $$SELECT status || '/' || initiated_from || '/' || coalesce(request_message, 'NULL') || '/' || coalesce(request_sender_id::text, 'NULL')
    FROM public.conversations WHERE id = pg_temp.dm('rs_soc', 'rs_pro')$$, 'active/booking/NULL/NULL');
PERFORM pg_temp.susp('rs_cli3', true);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R9 client suspendu : refus', pg_temp.call('open_booking_conversation', 'bk_c3'), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.susp('rs_cli3', false);
PERFORM pg_temp.blk('rs_pro', 'rs_cli3', true);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R9 le pro a bloqué le client : refus', pg_temp.call('open_booking_conversation', 'bk_c3'), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.blk('rs_pro', 'rs_cli3', false);
PERFORM pg_temp.blk('rs_cli3', 'rs_pro', true);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R9 le client a bloqué le pro : refus', pg_temp.call('open_booking_conversation', 'bk_c3'), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.blk('rs_cli3', 'rs_pro', false);
-- BOOKINGS-1 (corrigé 00578) : pas de fil rouvert plus de 7 jours après la fin de la sortie.
PERFORM pg_temp.ins('bk_old', 'off_h', 'rs_cli3', -10, 'am', 1, 'accepted');
PERFORM pg_temp.ins('bk_multi_old', 'off_m', 'rs_cli3', -12, 'am', 1, 'accepted', -10);
PERFORM pg_temp.ins('bk_multi_recent', 'off_m', 'rs_cli5', -9, 'am', 1, 'accepted', -5);
PERFORM pg_temp.ins('bk_pend_past', 'off_h', 'rs_cli4', -1, 'pm', 1, 'pending');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R9 BOOKINGS-1 : sortie finie il y a 10 jours, pas de fil', pg_temp.call('open_booking_conversation', 'bk_old'), 'junto\.outing_closed');
PERFORM pg_temp.denied('R9 BOOKINGS-1 : plage finie il y a 10 jours, pas de fil', pg_temp.call('open_booking_conversation', 'bk_multi_old'), 'junto\.outing_closed');
PERFORM pg_temp.denied('R9 BOOKINGS-1 : demande en attente d''un jour passé, pas de fil', pg_temp.call('open_booking_conversation', 'bk_pend_past'), 'junto\.outing_closed');
PERFORM pg_temp.ok('R9 sortie finie il y a 3 jours : le pro peut encore écrire', pg_temp.call('open_booking_conversation', 'bk_past_acc'));
PERFORM pg_temp.ok('R9 plage partie il y a 9 jours mais finie il y a 5 : permis (compte la fin)', pg_temp.call('open_booking_conversation', 'bk_multi_recent'));

-- ═════ R10 — get_pro_availability ═════
PERFORM pg_temp.as_('db');
INSERT INTO public.pro_availabilities (pro_id, day, period) VALUES (pg_temp.id('rs_pro'), pg_temp.d(-2), 'am');
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.eq('R10 agrégat anonyme : jour, période, places prises — rien d''autre',
  $$SELECT pg_get_function_result('public.get_pro_availability(uuid)'::regprocedure)$$, 'TABLE(day date, period text, taken integer)');
PERFORM pg_temp.eq('R10 T+5 matin : 4 prises (les demandes en attente ne comptent pas)',
  format($$SELECT taken::text FROM public.get_pro_availability(%L) WHERE day = %L AND period = 'am'$$, pg_temp.id('rs_pro'), pg_temp.d(5)), '4');
PERFORM pg_temp.eq('R10 milieu de la plage de 3 jours (T+11 pm) : 6 prises',
  format($$SELECT taken::text FROM public.get_pro_availability(%L) WHERE day = %L AND period = 'pm'$$, pg_temp.id('rs_pro'), pg_temp.d(11)), '6');
PERFORM pg_temp.eq('R10 dernier après-midi de la plage (T+12 pm) : 6 prises',
  format($$SELECT taken::text FROM public.get_pro_availability(%L) WHERE day = %L AND period = 'pm'$$, pg_temp.id('rs_pro'), pg_temp.d(12)), '6');
PERFORM pg_temp.eq('R10 le lendemain de la plage (T+13 am) : 0',
  format($$SELECT taken::text FROM public.get_pro_availability(%L) WHERE day = %L AND period = 'am'$$, pg_temp.id('rs_pro'), pg_temp.d(13)), '0');
PERFORM pg_temp.eq('R10 demi-journée occupée (agenda importé) masquée, l''autre visible',
  format($$SELECT string_agg(period, ',' ORDER BY period) FROM public.get_pro_availability(%L) WHERE day = %L$$, pg_temp.id('rs_pro'), pg_temp.d(6)), 'pm');
PERFORM pg_temp.eq('R10 demi-journées d''une date fixe masquées (S1)',
  format($$SELECT count(*)::text FROM public.get_pro_availability(%L) WHERE day = %L$$, pg_temp.id('rs_pro'), pg_temp.d(7)), '0');
PERFORM pg_temp.eq('R10 date fixe S2 : seul l''après-midi reste',
  format($$SELECT string_agg(period, ',' ORDER BY period) FROM public.get_pro_availability(%L) WHERE day = %L$$, pg_temp.id('rs_pro'), pg_temp.d(17)), 'pm');
PERFORM pg_temp.eq('R10 une date fixe annulée rend le créneau',
  format($$SELECT count(*)::text FROM public.get_pro_availability(%L) WHERE day = %L$$, pg_temp.id('rs_pro'), pg_temp.d(35)), '2');
PERFORM pg_temp.eq('R10 jours passés jamais renvoyés',
  format($$SELECT count(*)::text FROM public.get_pro_availability(%L) WHERE day < %L$$, pg_temp.id('rs_pro'), pg_temp.d(0)), '0');
PERFORM pg_temp.eq('R10 rideau démo : rien pour un membre', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('rs_demo')), '0');
PERFORM pg_temp.eq('R10 pro suspendu : rien', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('rs_pro3')), '0');
PERFORM pg_temp.eq('R10 pro non approuvé : rien', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('rs_pro4')), '0');
PERFORM pg_temp.as_('rs_adm');
PERFORM pg_temp.eq('R10 rideau démo : l''admin en mode démo voit', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('rs_demo')), '1');
PERFORM pg_temp.as_('rs_blk');
PERFORM pg_temp.eq('R10 bloqué par le pro : rien', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('rs_pro')), '0');
PERFORM pg_temp.as_('rs_blk2');
PERFORM pg_temp.eq('R10 qui a bloqué le pro : rien', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('rs_pro')), '0');
PERFORM pg_temp.as_('rs_sus');
PERFORM pg_temp.eq('R10 suspendu : rien', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('rs_pro')), '0');

-- ═════ R11 — get_pro_agenda ═════
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.eq('R11 une plage s''affiche quand un de ses jours est dans la fenêtre',
  format($$SELECT count(*)::text FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.d(11), pg_temp.d(11), pg_temp.id('bk_A')), '1');
PERFORM pg_temp.eq('R11 et disparaît après sa fin',
  format($$SELECT count(*)::text FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.d(13), pg_temp.d(13), pg_temp.id('bk_A')), '0');
PERFORM pg_temp.eq('R11 3 jours acceptés : fin, minimum, confirmée',
  format($$SELECT end_day::text || '/' || min_participants || '/' || confirmed FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.d(10), pg_temp.d(10), pg_temp.id('bk_A')),
  pg_temp.d(12)::text || '/4/true');
PERFORM pg_temp.eq('R11 demi-journée acceptée sans minimum : non confirmée',
  format($$SELECT coalesce(end_day::text, 'NULL') || '/' || coalesce(min_participants::text, 'NULL') || '/' || confirmed FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.d(5), pg_temp.d(5), pg_temp.id('bk_c1')),
  'NULL/NULL/false');
PERFORM pg_temp.eq('R11 demande en attente : confirmed NULL',
  format($$SELECT status || '/' || coalesce(confirmed::text, 'NULL') FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.d(13), pg_temp.d(13), pg_temp.id('bk_E')), 'pending/NULL');
PERFORM pg_temp.eq('R11 les réservations refusées / annulées n''y sont pas',
  format($$SELECT count(*)::text FROM public.get_pro_agenda(%L, %L) WHERE id IN (%L, %L)$$, pg_temp.d(0), pg_temp.d(60), pg_temp.id('bk_A5'), pg_temp.id('bk_cool')), '0');
PERFORM pg_temp.eq('R11 une saisie manuelle porte son nom et est marquée manuelle',
  format($$SELECT client_name || '/' || is_manual FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.d(60), pg_temp.d(60), pg_temp.id('bk_man_m')), 'Groupe Dehors/true');
PERFORM pg_temp.eq('R11 les demi-journées occupées sont des lignes « busy »',
  format($$SELECT count(*)::text FROM public.get_pro_agenda(%L, %L) WHERE kind = 'busy' AND day = %L$$, pg_temp.d(0), pg_temp.d(30), pg_temp.d(6)), '1');
PERFORM pg_temp.as_('rs_pro2');
PERFORM pg_temp.eq('R11 un autre pro ne voit rien de cet agenda',
  format($$SELECT count(*)::text FROM public.get_pro_agenda(%L, %L) WHERE id = %L OR client_id = %L$$, pg_temp.d(0), pg_temp.d(60), pg_temp.id('bk_A'), pg_temp.id('rs_cli')), '0');
PERFORM pg_temp.as_('rs_pro4');
PERFORM pg_temp.denied('R11 un pro non approuvé n''ouvre pas d''agenda', $$SELECT count(*)::text FROM public.get_pro_agenda(current_date, current_date + 30)$$, 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R11 fenêtre inversée refusée', format($$SELECT count(*)::text FROM public.get_pro_agenda(%L, %L)$$, pg_temp.d(10), pg_temp.d(5)), 'Operation not permitted');
-- Expiration paresseuse des demandes passées + notification du client.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ins('bk_exp', 'off_h', 'rs_cli4', -2, 'am', 1, 'pending');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.ok('R11 le pro ouvre son agenda', format($$SELECT count(*)::text FROM public.get_pro_agenda(%L, %L)$$, pg_temp.d(0), pg_temp.d(1)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R11 la demande passée est expirée', format($$SELECT status FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_exp')), 'expired');
PERFORM pg_temp.eq('R11 le client est prévenu de l''expiration', $$SELECT count(*)::text FROM pg_temp.nf('rs_cli4', 'booking_expired', 'bk_exp')$$, '1');

-- ═════ R12 — get_my_bookings ═════
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.eq('R12 3 jours : fin, après-midi, minimum, total de la sortie, confirmée',
  format($$SELECT end_day::text || '/' || end_period || '/' || min_participants || '/' || outing_total || '/' || confirmed FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_A')),
  pg_temp.d(12)::text || '/pm/4/6/true');
PERFORM pg_temp.eq('R12 demi-journée : pas de fin, pas de minimum, total 4, non confirmée',
  format($$SELECT coalesce(end_day::text, 'NULL') || '/' || coalesce(end_period, 'NULL') || '/' || coalesce(min_participants::text, 'NULL') || '/' || outing_total || '/' || confirmed
    FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_c1')), 'NULL/NULL/NULL/4/false');
PERFORM pg_temp.eq('R12 journée : fin le jour même, l''après-midi',
  format($$SELECT end_day::text || '/' || end_period FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_D')), pg_temp.d(8)::text || '/pm');
PERFORM pg_temp.eq('R12 le DM de la réservation est joint',
  format($$SELECT conversation_id::text FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_A')), pg_temp.get('conv_cli'));
PERFORM pg_temp.eq('R12 aucune colonne sur les autres clients',
  $$SELECT (pg_get_function_result('public.get_my_bookings()'::regprocedure) !~* 'client')::text$$, 'true');
PERFORM pg_temp.as_('rs_cli2');
PERFORM pg_temp.eq('R12 demande en attente : ni minimum, ni total, ni confirmation',
  format($$SELECT coalesce(min_participants::text, 'NULL') || '/' || coalesce(outing_total::text, 'NULL') || '/' || coalesce(confirmed::text, 'NULL') FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_E')), 'NULL/NULL/NULL');
PERFORM pg_temp.as_('rs_cli5');
PERFORM pg_temp.eq('R12 demande refusée sur une sortie à minimum : rien de la sortie',
  format($$SELECT coalesce(min_participants::text, 'NULL') || '/' || coalesce(outing_total::text, 'NULL') || '/' || coalesce(confirmed::text, 'NULL') FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_A5')), 'NULL/NULL/NULL');
PERFORM pg_temp.as_('rs_cli4');
PERFORM pg_temp.eq('R12 un co-participant ne voit pas la réservation de l''autre', format($$SELECT count(*)::text FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_A')), '0');
PERFORM pg_temp.eq('R12 il voit le même total de sortie', format($$SELECT outing_total::text FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_A4')), '6');

-- ═════ R13 — message_outing_clients (« Écrire à tous ») ═════
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R13 un membre n''écrit pas aux clients', pg_temp.outmsg('off_m', 10, 'am', 'x'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro2');
PERFORM pg_temp.denied('R13 un autre pro n''écrit pas aux clients de l''offre', pg_temp.outmsg('off_m', 10, 'am', 'x'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro3');
PERFORM pg_temp.denied('R13 un pro suspendu n''écrit pas', pg_temp.outmsg('off3', 5, 'am', 'x'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R13 période inconnue refusée', pg_temp.outmsg('off_m', 10, 'night', 'x'), 'Operation not permitted');
PERFORM pg_temp.denied('R13 jour absent refusé', pg_temp.outmsg('off_m', NULL, 'am', 'x'), 'Operation not permitted');
PERFORM pg_temp.denied('R13 message vide refusé', pg_temp.outmsg('off_m', 10, 'am', '   '), 'Operation not permitted');
PERFORM pg_temp.denied('R13 message vide après nettoyage HTML refusé', pg_temp.outmsg('off_m', 10, 'am', '<b></b>'), 'Operation not permitted');
PERFORM pg_temp.denied('R13 message de plus de 2000 caractères refusé', pg_temp.outmsg('off_m', 10, 'am', repeat('x', 2001)), 'Operation not permitted');
PERFORM pg_temp.eq('R13 envoi aux 2 clients acceptés (pas à la demande refusée)', pg_temp.outmsg('off_m', 10, 'am', '<i>RDV</i> 8 h au parking'), '2');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R13 le message nettoyé est dans le DM du client, signé du pro',
  $$SELECT count(*)::text FROM public.messages WHERE conversation_id = pg_temp.dm('rs_cli', 'rs_pro') AND sender_id = pg_temp.id('rs_pro') AND content = 'RDV 8 h au parking'$$, '1');
PERFORM pg_temp.eq('R13 rien pour le client dont la demande a été refusée',
  $$SELECT count(*)::text FROM public.messages WHERE content = 'RDV 8 h au parking' AND conversation_id IS NOT DISTINCT FROM pg_temp.dm('rs_cli5', 'rs_pro')$$, '0');
PERFORM pg_temp.susp('rs_cli4', true);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.eq('R13 client suspendu sauté', pg_temp.outmsg('off_m', 10, 'am', 'Message 2'), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.susp('rs_cli4', false);
PERFORM pg_temp.blk('rs_cli4', 'rs_pro', true);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.eq('R13 client qui a bloqué le pro sauté', pg_temp.outmsg('off_m', 10, 'am', 'Message 3'), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.blk('rs_cli4', 'rs_pro', false);
PERFORM pg_temp.blk('rs_pro', 'rs_cli4', true);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.eq('R13 client bloqué par le pro sauté', pg_temp.outmsg('off_m', 10, 'am', 'Message 4'), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.blk('rs_pro', 'rs_cli4', false);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R13 BOOKINGS-1 : sortie finie il y a 10 jours, plus d''envoi', pg_temp.outmsg('off_h', -10, 'am', 'Promo -20 % ce week-end'), 'junto.outing_closed');
PERFORM pg_temp.eq('R13 sortie finie il y a 3 jours : un merci passe encore', pg_temp.outmsg('off_h', -3, 'am', 'Merci pour la sortie'), '1');
PERFORM pg_temp.as_('db');
INSERT INTO public.rate_events (user_id, kind) SELECT pg_temp.id('rs_pro'), 'outing_broadcast' FROM generate_series(1, 20);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R13 plus de 20 envois par jour refusés', pg_temp.outmsg('off_m', 10, 'am', 'Encore'), 'junto.too_many_actions');

-- ═════ R14 — cancel_outing ═════
PERFORM pg_temp.as_('rs_o1');
PERFORM pg_temp.put('bk_o1', pg_temp.ok('R14 client 1 (T+40 matin)', pg_temp.bk('off_h', 40, 'am', 1)));
PERFORM pg_temp.put('bk_o5', pg_temp.ok('R14 client 1 (T+40 après-midi)', pg_temp.bk('off_h', 40, 'pm', 1)));
PERFORM pg_temp.as_('rs_o2');
PERFORM pg_temp.put('bk_o2', pg_temp.ok('R14 client 2 en attente (T+40 matin)', pg_temp.bk('off_h', 40, 'am', 1)));
PERFORM pg_temp.as_('rs_o3');
PERFORM pg_temp.put('bk_o4', pg_temp.ok('R14 client 3 (T+40 matin)', pg_temp.bk('off_h', 40, 'am', 1)));
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.ok('R14 acceptation client 1 matin', pg_temp.call('accept_booking', 'bk_o1'));
PERFORM pg_temp.ok('R14 acceptation client 1 après-midi', pg_temp.call('accept_booking', 'bk_o5'));
PERFORM pg_temp.ok('R14 acceptation client 3', pg_temp.call('accept_booking', 'bk_o4'));
PERFORM pg_temp.put('bk_o3', pg_temp.ok('R14 saisie manuelle sur la sortie', pg_temp.man('off_h', 40, 'am', 1, 'Paul Dehors')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.blk('rs_pro', 'rs_o3', true);
PERFORM pg_temp.put('m_o1', (SELECT count(*)::text FROM public.messages WHERE conversation_id = pg_temp.dm('rs_o1', 'rs_pro')));
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R14 un membre n''annule pas une sortie', pg_temp.cout('off_h', 40, 'am'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro2');
PERFORM pg_temp.denied('R14 un autre pro n''annule pas la sortie', pg_temp.cout('off_h', 40, 'am'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro3');
PERFORM pg_temp.denied('R14 un pro suspendu n''annule pas de sortie', pg_temp.cout('off3', 5, 'am'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro4');
-- 00578 (T-REVOKED-CANCEL) : comme cancel_pro_session / cancel_booking_pro, un pro dont la vitrine
-- n'est plus approuvée annule encore (ses clients doivent être prévenus) ; seule la suspension bloque.
PERFORM pg_temp.ok('R14 un pro non approuvé annule encore une sortie', pg_temp.cout('off4', 5, 'am'));
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R14 période inconnue refusée', pg_temp.cout('off_h', 40, 'night'), 'Operation not permitted');
PERFORM pg_temp.denied('R14 offre inconnue refusée', format($$SELECT public.cancel_outing(%L, %L, 'am')::text$$, gen_random_uuid(), pg_temp.d(40)), 'Operation not permitted');
PERFORM pg_temp.denied('R14 sortie passée refusée', pg_temp.cout('off_h', -1, 'am'), 'junto.booking_date');
PERFORM pg_temp.denied('R14 motif de plus de 300 caractères refusé', pg_temp.cout('off_h', 40, 'am', repeat('x', 301)), 'junto.outing_reason');
PERFORM pg_temp.eq('R14 annulation avec motif : 4 réservations touchées', pg_temp.cout('off_h', 40, 'am', '<b>Météo</b> REASON-XYZ'), '4');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R14 acceptées → cancelled_pro, en attente → declined, manuelle → cancelled_pro',
  $$SELECT string_agg(status, ',' ORDER BY k) FROM (VALUES (1, 'bk_o1'), (2, 'bk_o2'), (3, 'bk_o3'), (4, 'bk_o4')) v(k, l)
    JOIN public.bookings b ON b.id = pg_temp.id(l)$$, 'cancelled_pro,declined,cancelled_pro,cancelled_pro');
PERFORM pg_temp.eq('R14 le motif nettoyé va dans le DM du client accepté',
  $$SELECT count(*)::text FROM public.messages WHERE conversation_id = pg_temp.dm('rs_o1', 'rs_pro') AND sender_id = pg_temp.id('rs_pro') AND content = 'Météo REASON-XYZ'$$, '1');
-- 00578 (T-OUTING-PENDING) : le motif ne va qu'aux clients ACCEPTÉS — une demande en attente n'ouvre jamais de fil.
PERFORM pg_temp.eq('R14 mais pas dans le DM du client en attente',
  $$SELECT count(*)::text FROM public.messages WHERE conversation_id = pg_temp.dm('rs_o2', 'rs_pro') AND content LIKE '%REASON-XYZ%'$$, '0');
PERFORM pg_temp.eq('R14 pas de DM pour un client bloqué',
  $$SELECT count(*)::text FROM public.messages WHERE conversation_id = pg_temp.dm('rs_o3', 'rs_pro') AND content LIKE '%REASON-XYZ%'$$, '0');
PERFORM pg_temp.eq('R14 notif client accepté : by_pro_message avec le fil',
  $$SELECT data->>'variant' || '/' || (data->>'conversation_id' = pg_temp.dm('rs_o1', 'rs_pro')::text) FROM pg_temp.nf('rs_o1', 'booking_cancelled', 'bk_o1')$$, 'by_pro_message/true');
PERFORM pg_temp.eq('R14 notif client bloqué : by_pro, sans fil',
  $$SELECT data->>'variant' || '/' || coalesce(data->>'conversation_id', 'NULL') FROM pg_temp.nf('rs_o3', 'booking_cancelled', 'bk_o4')$$, 'by_pro/NULL');
PERFORM pg_temp.eq('R14 notif client en attente : booking_declined', $$SELECT count(*)::text FROM pg_temp.nf('rs_o2', 'booking_declined', 'bk_o2')$$, '1');
PERFORM pg_temp.eq('R14 le motif n''est dans AUCUNE notification',
  $$SELECT count(*)::text FROM public.notifications WHERE title || body || coalesce(data::text, '') LIKE '%REASON-XYZ%'$$, '0');
PERFORM pg_temp.blk('rs_pro', 'rs_o3', false);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.eq('R14 annulation sans motif', pg_temp.cout('off_h', 40, 'pm'), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R14 sans motif : notif by_pro sans fil',
  $$SELECT data->>'variant' || '/' || coalesce(data->>'conversation_id', 'NULL') FROM pg_temp.nf('rs_o1', 'booking_cancelled', 'bk_o5')$$, 'by_pro/NULL');
PERFORM pg_temp.eq('R14 sans motif : aucun message de plus dans le DM',
  $$SELECT count(*)::text FROM public.messages WHERE conversation_id = pg_temp.dm('rs_o1', 'rs_pro')$$, (pg_temp.get('m_o1')::int + 1)::text);
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.eq('R14 annuler une sortie confirmée (minimum atteint en manuel)', pg_temp.cout('off_c', 61, 'am'), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R14 la confirmation de la sortie est effacée',
  format($$SELECT count(*)::text FROM private.outing_confirmations WHERE offering_id = %L AND day = %L$$, pg_temp.id('off_c'), pg_temp.d(61)), '0');
PERFORM pg_temp.eq('R14 la saisie manuelle est annulée', format($$SELECT status FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_man_c')), 'cancelled_pro');

-- ═════ R15 — set_booking_participant_info ═════
PERFORM pg_temp.as_('rs_form');
PERFORM pg_temp.put('bk_f', pg_temp.ok('R15 demande de 2 places (T+45 matin)', pg_temp.bk('off_h', 45, 'am', 2)));
PERFORM pg_temp.denied('R15 fiche d''une demande en attente refusée', pg_temp.pinfo('bk_f', '[{"shoe_size":"42"}]'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.ok('R15 le pro accepte', pg_temp.call('accept_booking', 'bk_f'));
PERFORM pg_temp.as_('rs_form');
PERFORM pg_temp.ok('R15 le client remplit les 2 fiches', pg_temp.pinfo('bk_f', '[{"shoe_size":"42","custom":{"Allergies ?":"non"}},{"shoe_size":"38"}]'));
PERFORM pg_temp.denied('R15 plus de fiches que le groupe refusé', pg_temp.pinfo('bk_f', '[{},{},{}]'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 champ du catalogue non demandé refusé', pg_temp.pinfo('bk_f', '[{"weight":"70"}]'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 clé hors catalogue refusée', pg_temp.pinfo('bk_f', '[{"iban":"FR76"}]'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 « custom » qui n''est pas un objet refusé', pg_temp.pinfo('bk_f', '[{"custom":"non"}]'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 question libre inconnue refusée', pg_temp.pinfo('bk_f', '[{"custom":{"Autre ?":"x"}}]'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 valeur non texte refusée', pg_temp.pinfo('bk_f', '[{"shoe_size":42}]'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 réponse libre non texte refusée', pg_temp.pinfo('bk_f', '[{"custom":{"Allergies ?":true}}]'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 valeur de 31 caractères refusée', pg_temp.pinfo('bk_f', '[{"shoe_size":"' || repeat('x', 31) || '"}]'), 'Operation not permitted');
PERFORM pg_temp.ok('R15 valeur de 30 caractères permise', pg_temp.pinfo('bk_f', '[{"shoe_size":"' || repeat('x', 30) || '"}]'));
PERFORM pg_temp.denied('R15 réponse libre de 121 caractères refusée', pg_temp.pinfo('bk_f', '[{"custom":{"Allergies ?":"' || repeat('x', 121) || '"}}]'), 'Operation not permitted');
PERFORM pg_temp.ok('R15 réponse libre de 120 caractères permise', pg_temp.pinfo('bk_f', '[{"custom":{"Allergies ?":"' || repeat('x', 120) || '"}}]'));
PERFORM pg_temp.denied('R15 un objet au lieu d''un tableau refusé', pg_temp.pinfo('bk_f', '{"shoe_size":"42"}'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 JSON null refusé', pg_temp.pinfo('bk_f', 'null'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 NULL refusé', format($$SELECT public.set_booking_participant_info(%L, NULL)::text$$, pg_temp.id('bk_f')), 'Operation not permitted');
PERFORM pg_temp.denied('R15 une entrée qui n''est pas un objet refusée', pg_temp.pinfo('bk_f', '[1]'), 'Operation not permitted');
PERFORM pg_temp.ok('R15 caractères de contrôle et balises retirés', pg_temp.pinfo('bk_f', '[{"shoe_size":"<b>4\u00072</b>"}]'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R15 valeur stockée nettoyée', format($$SELECT participant_info->0->>'shoe_size' FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_f')), '42');
PERFORM pg_temp.as_('rs_form');
PERFORM pg_temp.ok('R15 CLIENT-1 : un tableau vide est accepté (vide la fiche)', pg_temp.pinfo('bk_f', '[]'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R15 CLIENT-1 : le tableau vide est stocké (fiche effacée)', format($$SELECT coalesce(participant_info::text, 'NULL') FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_f')), 'NULL');
PERFORM pg_temp.as_('rs_form');
PERFORM pg_temp.denied('R15 le client ne remplit pas une réservation manuelle', pg_temp.pinfo('bk_man_cap', '[{"shoe_size":"40"}]'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_cli');
PERFORM pg_temp.denied('R15 un tiers ne remplit pas la fiche', pg_temp.pinfo('bk_f', '[{"shoe_size":"40"}]'), 'Operation not permitted');
PERFORM pg_temp.denied('R15 offre sans fiche : refus', pg_temp.pinfo('bk_D', '[{"shoe_size":"40"}]'), 'Operation not permitted');
PERFORM pg_temp.as_('rs_pro');
PERFORM pg_temp.denied('R15 le pro ne remplit pas la fiche d''un client Junto', pg_temp.pinfo('bk_f', '[{"shoe_size":"40"}]'), 'Operation not permitted');
PERFORM pg_temp.ok('R15 le pro remplit la fiche d''une réservation manuelle', pg_temp.pinfo('bk_man_cap', '[{"shoe_size":"40"}]'));
PERFORM pg_temp.as_('rs_cli5');
PERFORM pg_temp.denied('R15 sortie passée : fiche figée', pg_temp.pinfo('bk_past_acc', '[{"shoe_size":"40"}]'), 'junto.booking_date');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.susp('rs_form', true);
PERFORM pg_temp.as_('rs_form');
PERFORM pg_temp.denied('R15 un suspendu ne remplit pas', pg_temp.pinfo('bk_f', '[{"shoe_size":"40"}]'), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.susp('rs_form', false);

-- ═════ R16 — Crons (copies pg_temp sans la garde horaire de Paris) ═════
PERFORM pg_temp.as_('db');
-- J+1 : rappel la veille (18 h).
PERFORM pg_temp.ins('cr1', 'off_h', 'rs_cr1', 1, 'am', 2, 'accepted');
PERFORM pg_temp.ins('cr2', 'off_d', 'rs_cr2', 1, 'am', 1, 'accepted', 1);
PERFORM pg_temp.ins('cr3', 'off_h', 'rs_cr3', 1, 'pm', 1, 'pending');
PERFORM pg_temp.ins('cr4', 'off_h', NULL, 1, 'pm', 1, 'accepted', NULL, NULL, '0', 'Jean Manuel');
PERFORM pg_temp.ins('cr5', 'off_h', 'rs_cr2', 1, 'pm', 1, 'accepted', NULL, '[{"shoe_size":"40"}]');
-- J+3 : rappel des fiches au client (18 h).
PERFORM pg_temp.ins('cr6', 'off_h', 'rs_cr1', 3, 'am', 2, 'accepted');
PERFORM pg_temp.ins('cr7', 'off_h', 'rs_cr2', 3, 'am', 1, 'accepted', NULL, '[{"shoe_size":"40"}]');
PERFORM pg_temp.ins('cr8', 'off_h', 'rs_cr3', 3, 'pm', 2, 'accepted');
PERFORM pg_temp.ins('cr9', 'off_d', 'rs_cr4', 3, 'am', 1, 'accepted', 3);
-- J+2 : fiches manquantes / minimum côté pro (9 h).
PERFORM pg_temp.ins('cr10', 'off_h', 'rs_cr1', 2, 'am', 3, 'accepted', NULL, '[{"shoe_size":"42"}]');
PERFORM pg_temp.ins('cr11', 'off_h', NULL, 2, 'am', 2, 'accepted', NULL, NULL, '0', 'Marcel Dehors');
PERFORM pg_temp.ins('cr12', 'off_m', 'rs_cr2', 2, 'am', 2, 'accepted', 4);
PERFORM pg_temp.ins('cr13', 'off_c', 'rs_cr3', 2, 'am', 1, 'accepted');
INSERT INTO private.outing_confirmations (pro_id, offering_id, day, period, session_id, reason)
VALUES (pg_temp.id('rs_pro'), pg_temp.id('off_c'), pg_temp.d(2), 'am', NULL, 'pro');
PERFORM pg_temp.ins('cr14', 'off_h', 'rs_cr4', 2, 'pm', 1, 'accepted', NULL, '[{"shoe_size":"40"}]');
-- Demandes en attente depuis plus de 24 h (9 h), chez pro2.
PERFORM pg_temp.ins('cr15', 'off2', 'rs_cr1', 30, 'am', 1, 'pending', NULL, NULL, '25 hours');
PERFORM pg_temp.ins('cr16', 'off2', 'rs_cr2', 30, 'pm', 1, 'pending', NULL, NULL, '25 hours');
PERFORM pg_temp.ins('cr17', 'off2', 'rs_cr3', -1, 'am', 1, 'pending', NULL, NULL, '25 hours');
PERFORM pg_temp.ins('cr18', 'off2', 'rs_cr4', 30, 'am', 1, 'pending');
-- CLIENT-1 : le client envoie deux fiches vides.
PERFORM pg_temp.as_('rs_cr3');
PERFORM pg_temp.ok('R16 le client envoie deux fiches vides', pg_temp.pinfo('cr8', '[{},{}]'));

PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('R16 garde horaire de notify_booking_reminders (18 h) présente',
  $$SELECT (position('<> 18 THEN RETURN' in pg_get_functiondef('private.notify_booking_reminders()'::regprocedure)) > 0)::text$$, 'true');
PERFORM pg_temp.eq('R16 garde horaire de notify_booking_forms_reminders (18 h) présente',
  $$SELECT (position('<> 18 THEN RETURN' in pg_get_functiondef('private.notify_booking_forms_reminders()'::regprocedure)) > 0)::text$$, 'true');
PERFORM pg_temp.eq('R16 garde horaire de notify_pending_booking_requests (9 h) présente',
  $$SELECT (position('<> 9 THEN RETURN' in pg_get_functiondef('private.notify_pending_booking_requests()'::regprocedure)) > 0)::text$$, 'true');
PERFORM pg_temp.eq('R16 garde horaire de notify_booking_forms_missing (9 h) présente',
  $$SELECT (position('<> 9 THEN RETURN' in pg_get_functiondef('private.notify_booking_forms_missing()'::regprocedure)) > 0)::text$$, 'true');
EXECUTE replace(replace(pg_get_functiondef('private.notify_booking_reminders()'::regprocedure), '<> 18 THEN RETURN', '< 0 THEN RETURN'),
  'private.notify_booking_reminders', 'pg_temp.notify_booking_reminders');
EXECUTE replace(replace(pg_get_functiondef('private.notify_booking_forms_reminders()'::regprocedure), '<> 18 THEN RETURN', '< 0 THEN RETURN'),
  'private.notify_booking_forms_reminders', 'pg_temp.notify_booking_forms_reminders');
EXECUTE replace(replace(pg_get_functiondef('private.notify_pending_booking_requests()'::regprocedure), '<> 9 THEN RETURN', '< 0 THEN RETURN'),
  'private.notify_pending_booking_requests', 'pg_temp.notify_pending_booking_requests');
EXECUTE replace(replace(pg_get_functiondef('private.notify_booking_forms_missing()'::regprocedure), '<> 9 THEN RETURN', '< 0 THEN RETURN'),
  'private.notify_booking_forms_missing', 'pg_temp.notify_booking_forms_missing');

PERFORM pg_temp.ok('R16 rappel J-1 lancé', $$SELECT pg_temp.notify_booking_reminders()::text$$);
PERFORM pg_temp.eq('R16 J-1 : fiches incomplètes → variante forms',
  $$SELECT data->>'variant' || '/' || (body LIKE '%fiches participants%') FROM pg_temp.nf('rs_cr1', 'booking_reminder', 'cr1')$$, 'forms/true');
PERFORM pg_temp.eq('R16 J-1 : offre sans fiche → rappel simple', $$SELECT coalesce(data->>'variant', 'NULL') FROM pg_temp.nf('rs_cr2', 'booking_reminder', 'cr2')$$, 'NULL');
PERFORM pg_temp.eq('R16 J-1 : fiches complètes → rappel simple', $$SELECT coalesce(data->>'variant', 'NULL') FROM pg_temp.nf('rs_cr2', 'booking_reminder', 'cr5')$$, 'NULL');
PERFORM pg_temp.eq('R16 J-1 : pas de rappel pour une demande en attente', $$SELECT count(*)::text FROM pg_temp.nf('rs_cr3', 'booking_reminder')$$, '0');
PERFORM pg_temp.eq('R16 J-1 : pas de rappel pour une réservation manuelle',
  $$SELECT count(*)::text FROM public.notifications WHERE type = 'booking_reminder' AND data->>'booking_id' = pg_temp.get('cr4')$$, '0');

PERFORM pg_temp.ok('R16 rappel des fiches J-3 lancé', $$SELECT pg_temp.notify_booking_forms_reminders()::text$$);
PERFORM pg_temp.eq('R16 J-3 : fiche vide → rappel', $$SELECT count(*)::text FROM pg_temp.nf('rs_cr1', 'booking_forms_reminder', 'cr6')$$, '1');
PERFORM pg_temp.eq('R16 J-3 : fiche complète → rien', $$SELECT count(*)::text FROM pg_temp.nf('rs_cr2', 'booking_forms_reminder', 'cr7')$$, '0');
PERFORM pg_temp.eq('R16 J-3 : offre sans fiche → rien', $$SELECT count(*)::text FROM pg_temp.nf('rs_cr4', 'booking_forms_reminder', 'cr9')$$, '0');
PERFORM pg_temp.eq('R16 CLIENT-1 : des fiches {} ne comptent pas comme remplies (rappel envoyé)',
  $$SELECT count(*)::text FROM pg_temp.nf('rs_cr3', 'booking_forms_reminder', 'cr8')$$, '1');

PERFORM pg_temp.ok('R16 rappel des demandes en attente lancé', $$SELECT pg_temp.notify_pending_booking_requests()::text$$);
PERFORM pg_temp.eq('R16 pro2 : un seul push, 2 demandes de plus de 24 h à venir',
  $$SELECT count(*)::text || '/' || max(data->'params'->>'count') || '/' || max(body) FROM pg_temp.nf('rs_pro2', 'booking_requests_waiting')$$,
  '1/2/2 demandes attendent ta réponse.');
PERFORM pg_temp.eq('R16 pro : demandes récentes seulement → rien', $$SELECT count(*)::text FROM pg_temp.nf('rs_pro', 'booking_requests_waiting')$$, '0');

PERFORM pg_temp.ok('R16 fiches manquantes J-2 lancé', $$SELECT pg_temp.notify_booking_forms_missing()::text$$);
PERFORM pg_temp.eq('R16 J-2 : un push pour la sortie, 4 fiches manquantes sur 5 (manuelle comprise)',
  format($$SELECT count(*)::text || '/' || max(data->'params'->>'count') || '/' || max(data->'params'->>'total') || '/' || coalesce(max(data->>'variant'), 'NULL') || '/' || bool_and(body LIKE '%%4 fiches participants manquantes sur 5%%')
    FROM pg_temp.nf('rs_pro', 'booking_forms_missing') WHERE data->>'offering_id' = %L AND data->'params'->>'date' = %L AND data->'params'->>'period' = 'am'$$,
    pg_temp.id('off_h'), pg_temp.d(2)::text), '1/4/5/NULL/true');
PERFORM pg_temp.eq('R16 J-2 : aucun nom de client dans le push pro',
  format($$SELECT count(*)::text FROM pg_temp.nf('rs_pro', 'booking_forms_missing') WHERE data->>'offering_id' = %L
    AND (title || body || data::text LIKE '%%Marcel%%' OR title || body || data::text LIKE '%%' || pg_temp.dn('rs_cr1') || '%%')$$, pg_temp.id('off_h')), '0');
-- 00578 (SESSIONS-2) : off_m n'a pas choisi l'annulation automatique → variante « minimum », sans « annulée demain ».
PERFORM pg_temp.eq('R16 J-2 : minimum de l''offre non atteint (2/4), sans annulation auto → variante minimum',
  format($$SELECT data->>'variant' || '/' || (body LIKE '%%2/4 inscrits%%') FROM pg_temp.nf('rs_pro', 'booking_forms_missing') WHERE data->>'offering_id' = %L$$, pg_temp.id('off_m')), 'minimum/true');
PERFORM pg_temp.eq('R16 J-2 : sortie confirmée par le pro → rien malgré le minimum',
  format($$SELECT count(*)::text FROM pg_temp.nf('rs_pro', 'booking_forms_missing') WHERE data->>'offering_id' = %L$$, pg_temp.id('off_c')), '0');
PERFORM pg_temp.eq('R16 J-2 : fiches complètes et pas de minimum → rien',
  format($$SELECT count(*)::text FROM pg_temp.nf('rs_pro', 'booking_forms_missing') WHERE data->>'offering_id' = %L AND data->'params'->>'period' = 'pm'$$, pg_temp.id('off_h')), '0');
