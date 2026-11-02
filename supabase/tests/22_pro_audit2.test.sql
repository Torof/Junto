-- Domaine 22 — Pro : seconde passe de l'audit 2026-11 (mig 00580, docs/AUDIT_PRO_2026-11.md, round 2).
--
-- Un contrôle (au moins) par correctif, dans l'ordre de la migration :
--   PA1  SESSIONS-A  « Maintenir » l'emporte sur « minimum atteint » (accept / manuelle après J-2, confirm_outing)
--   PA2  SESSIONS-B  après le rappel J-2, un départ ne retire plus un « Départ confirmé » déjà annoncé
--   PA3  SESSIONS-C  retiré d'une date par le pro : pas de réinscription à CETTE date
--   PA4  SESSIONS-D  une date déplacée repart de zéro (maintenue si elle tombe après le rappel J-2)
--   PA5  CLIENT-4    groupe > 6 sur une date : message propre (junto.session_group_cap)
--   PA6  BOOKINGS-R3 caractères invisibles retirés avant les contrôles (message, nom de saisie manuelle)
--   PA7  BOOKINGS-R4 blocage : demandes en attente retirées en silence, avis sans nom (annulations, rappels)
--   PA8  VITRINE-5   une sortie en cours (plage ou date) bloque la suppression d'offre et la désinscription
--   PA9  CLIENT-1/3  photo communautaire : le fichier doit exister (envoyé par l'appelant) ;
--                    junto.photo_requires_booking ; can_add_community_photo
--   PA10 VITRINE-6   moderate_report peut suspendre l'auteur d'une photo communautaire signalée
--   PA11 VITRINE-7   community_photo_orphans (service seulement)
--   PA12 BOOKINGS-R1 / R2 — ordre des verrous (dates avant créneaux ; verrou de la sortie avant la ligne).
--        Ce sont des COURSES (deux transactions concurrentes) : non reproductibles dans un bloc unique.
--        Contrôle statique seulement, sur la définition vivante.
--   GRANTS-2 (anon sans droit sur les tables de public) : voir 00_socle. Listes de fonctions : 13_sweep_trous.
--
-- Jours : pg_temp.pa_d(n) = aujourd'hui (heure de Paris) + n. « Après le rappel J-2 » = sortie demain
-- (J+1) ; « avant » = J+10 et au-delà. Les dates commencées et les fixtures des crons sont insérées en 'db'.

DECLARE v_lbl text;  -- bloc local : variable de boucle
BEGIN

-- ───── Helpers locaux ─────
EXECUTE $p$CREATE FUNCTION pg_temp.pa_d(n integer) RETURNS date
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT private.today_paris() + n $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_reg_sql(p_name text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.register_as_pro(p_display_name := %L, p_company_name := 'SARL Test', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$s$, p_name) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_off_sql(p_title text, p_max integer, p_min integer) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_pro_offering(p_sport_id := %L, p_title := %L, p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon',
      p_max_participants := %L, p_price_eur := 50, p_price_unit := 'person', p_min_participants := %L)::text$s$,
      pg_temp.id('pa_sport'), p_title, p_max, p_min) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_open_sql(a integer, b integer) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.set_pro_availability_bulk(x.ds, x.ps, true)::text FROM (
      SELECT array_agg(pg_temp.pa_d(i) ORDER BY i, p) ds, array_agg(p ORDER BY i, p) ps
      FROM generate_series(%s, %s) i CROSS JOIN (VALUES ('am'), ('pm')) v(p)) x$s$, a, b) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_new(p_off text, p_sn integer, p_sp text, p_en integer, p_ep text, p_max integer, p_min integer DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_pro_session(%L, %L, %L, %L, %L, %L, %L)::text$s$,
      pg_temp.id(p_off), pg_temp.pa_d(p_sn), p_sp, pg_temp.pa_d(p_en), p_ep, p_max, p_min) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_upd(p_sess text, p_sn integer, p_sp text, p_en integer, p_ep text, p_max integer, p_min integer DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.update_pro_session(%L, %L, %L, %L, %L, %L, %L)::text$s$,
      pg_temp.id(p_sess), pg_temp.pa_d(p_sn), p_sp, pg_temp.pa_d(p_en), p_ep, p_max, p_min) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_join(p_sess text, p_party integer, p_msg text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.join_pro_session(%L, %L, %L)::text$s$, pg_temp.id(p_sess), p_party, p_msg) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_req(p_off text, p_dn integer, p_period text, p_party integer, p_msg text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_booking(%L, %L, %L, %L, %L)::text$s$, pg_temp.id(p_off), pg_temp.pa_d(p_dn), p_period, p_party, p_msg) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_manual(p_off text, p_dn integer, p_period text, p_party integer, p_name text DEFAULT 'Client tel') RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_manual_booking(%L, %L, %L, %L, %L)::text$s$, pg_temp.id(p_off), pg_temp.pa_d(p_dn), p_period, p_party, p_name) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_confirm(p_off text, p_dn integer, p_period text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.confirm_outing(%L, %L, %L)::text$s$, pg_temp.id(p_off), pg_temp.pa_d(p_dn), p_period) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_call(p_fn text, p_label text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format('SELECT public.%s(%L)::text', p_fn, pg_temp.id(p_label)) $b$$p$;
-- Fixtures directes (en 'db').
EXECUTE $p$CREATE FUNCTION pg_temp.pa_ss(p_label text, p_off text, p_sn integer, p_sp text, p_en integer, p_ep text,
    p_max integer, p_min integer DEFAULT NULL) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.pro_sessions (pro_id, offering_id, start_day, start_period, end_day, end_period, max_participants, min_participants, status)
    SELECT o.pro_id, o.id, pg_temp.pa_d(p_sn), p_sp, pg_temp.pa_d(p_en), p_ep, p_max, p_min, 'scheduled'
    FROM public.pro_offerings o WHERE o.id = pg_temp.id(p_off) RETURNING id INTO v;
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;
-- Résa directe (créée il y a 2 jours : hors plafond 24 h) ; p_sess = date fixe, p_end_dn = fin d'une plage.
EXECUTE $p$CREATE FUNCTION pg_temp.pa_bk(p_label text, p_off text, p_client text, p_dn integer, p_period text, p_party integer,
    p_status text, p_sess text DEFAULT NULL, p_end_dn integer DEFAULT NULL) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.bookings (offering_id, pro_id, client_id, day, period, end_day, party_size, status, session_id,
                                 created_at, last_submitted_at, price_eur, price_unit)
    SELECT o.id, o.pro_id, pg_temp.id(p_client), pg_temp.pa_d(p_dn), p_period,
           CASE WHEN p_end_dn IS NOT NULL THEN pg_temp.pa_d(p_end_dn) END,
           p_party, p_status, pg_temp.id(p_sess), now() - INTERVAL '2 days', now() - INTERVAL '2 days', 50, 'person'
    FROM public.pro_offerings o WHERE o.id = pg_temp.id(p_off) RETURNING id INTO v;
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_oc(p_off text, p_dn integer, p_period text, p_sess text, p_reason text) RETURNS void
  LANGUAGE sql SECURITY DEFINER AS $b$
  INSERT INTO private.outing_confirmations (pro_id, offering_id, day, period, session_id, reason)
  SELECT o.pro_id, o.id, pg_temp.pa_d(p_dn), p_period, pg_temp.id(p_sess), p_reason FROM public.pro_offerings o WHERE o.id = pg_temp.id(p_off) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_blk(a text, b text) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER AS $b$ BEGIN
    INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id(a), pg_temp.id(b));
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END $b$$p$;
-- Fichier du bucket pro-photos sous <dossier>/community/<pro>/<fichier>, envoyé par p_owner (défaut : le
-- titulaire du dossier), daté p_at. Renvoie son nom (chemin dans le bucket).
EXECUTE $p$CREATE FUNCTION pg_temp.pa_file(p_folder text, p_pro text, p_file text, p_owner text DEFAULT NULL,
    p_at timestamptz DEFAULT now()) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  INSERT INTO storage.objects (bucket_id, name, owner_id, created_at)
  VALUES ('pro-photos', pg_temp.id(p_folder)::text || '/community/' || pg_temp.id(p_pro)::text || '/' || p_file,
          pg_temp.id(coalesce(p_owner, p_folder))::text, p_at)
  RETURNING name $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_url(p_folder text, p_pro text, p_file text) RETURNS text
  LANGUAGE sql AS $b$ SELECT pg_temp.host() || '/storage/v1/object/public/pro-photos/' || pg_temp.id(p_folder)::text
    || '/community/' || pg_temp.id(p_pro)::text || '/' || p_file $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_photo(p_pro text, p_url text, p_offering text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.add_pro_community_photo(%L, %L, NULL, %L)::text$s$, pg_temp.id(p_pro), p_url, pg_temp.id(p_offering)) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_can(p_pro text, p_offering text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.can_add_community_photo(%L, %L)::text$s$, pg_temp.id(p_pro), pg_temp.id(p_offering)) $b$$p$;
-- Lectures d'état (lisibles quel que soit le rôle courant).
EXECUTE $p$CREATE FUNCTION pg_temp.pa_bst(p_label text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT status FROM public.bookings WHERE id = pg_temp.id(p_label) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_conf(p_off text, p_dn integer, p_period text, p_sess text DEFAULT NULL) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT private.outing_confirmed(pg_temp.id(p_off), pg_temp.pa_d(p_dn), p_period, pg_temp.id(p_sess))::text $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_reason(p_off text, p_dn integer, p_period text, p_sess text DEFAULT NULL) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT coalesce((SELECT string_agg(c.reason, ',') FROM private.outing_confirmations c
    WHERE (p_sess IS NOT NULL AND c.session_id = pg_temp.id(p_sess))
       OR (p_sess IS NULL AND c.session_id IS NULL AND c.offering_id = pg_temp.id(p_off)
           AND c.day = pg_temp.pa_d(p_dn) AND c.period = p_period)), 'none') $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pa_n(p_user text, p_type text, p_booking text DEFAULT NULL) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT count(*)::text FROM public.notifications
    WHERE user_id = pg_temp.id(p_user) AND type = p_type
      AND (p_booking IS NULL OR data->>'booking_id' = pg_temp.get(p_booking)) $b$$p$;
-- Avis d'annulation reçu par un client : « variante présente / nom présent / nom du pro absent du texte ».
EXECUTE $p$CREATE FUNCTION pg_temp.pa_neutral(p_user text, p_booking text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT string_agg((data ? 'variant')::text || '/' || (data->'params' ? 'name')::text || '/'
      || (title || body || data::text NOT LIKE '%Guide Zorglub%')::text, ',')
    FROM public.notifications WHERE user_id = pg_temp.id(p_user) AND type = 'booking_cancelled' AND data->>'booking_id' = pg_temp.get(p_booking) $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('pa_sport', (SELECT id::text FROM public.sports WHERE key = 'hiking'));
PERFORM pg_temp.user('pa_adm', 'tos,admin');
PERFORM pg_temp.user('pa_pro', 'tos');    -- minimum, dates, inscriptions (PA1-PA6)
PERFORM pg_temp.user('pa_pro2', 'tos');   -- blocage (PA7)
PERFORM pg_temp.user('pa_pro3', 'tos');   -- plage en cours (PA8)
PERFORM pg_temp.user('pa_pro4', 'tos');   -- date en cours (PA8)
PERFORM pg_temp.user('pa_pro5', 'tos');   -- photos communautaires (PA9-PA11)
PERFORM pg_temp.user('pa_pro6', 'tos');   -- date déplacée (PA4)
PERFORM pg_temp.user('pa_sus', 'tos,suspended');
FOREACH v_lbl IN ARRAY ARRAY['pa_c1','pa_c2','pa_c3','pa_c4','pa_c5','pa_c6','pa_c7','pa_c8','pa_c9',
    'pa_b1','pa_b2','pa_b3','pa_b4','pa_b5','pa_b6','pa_b7','pa_v1','pa_v2',
    'pa_p1','pa_p2','pa_p3','pa_p4','pa_p5'] LOOP
  PERFORM pg_temp.user(v_lbl, 'tos');
END LOOP;
FOREACH v_lbl IN ARRAY ARRAY['pa_pro','pa_pro2','pa_pro3','pa_pro4','pa_pro5','pa_pro6'] LOOP
  PERFORM pg_temp.as_(v_lbl);
  PERFORM pg_temp.ok('PA0 inscription pro ' || v_lbl, pg_temp.pa_reg_sql('Pro ' || v_lbl));
  PERFORM pg_temp.as_('pa_adm');
  PERFORM pg_temp.ok('PA0 approbation ' || v_lbl, format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id(v_lbl)));
END LOOP;
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
-- Nom affiché reconnaissable du pro de PA7 (cherché ensuite dans les avis).
UPDATE public.users SET display_name = 'Guide Zorglub' WHERE id = pg_temp.id('pa_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);

PERFORM pg_temp.as_('pa_pro');
PERFORM pg_temp.put('oA', pg_temp.ok('PA0 offre sur demande minimum 2 (A)', pg_temp.pa_off_sql('Min 2 A', 8, 2)));
PERFORM pg_temp.put('oB', pg_temp.ok('PA0 offre sur demande minimum 2 (B, manuelles)', pg_temp.pa_off_sql('Min 2 B', 8, 2)));
PERFORM pg_temp.put('oD', pg_temp.ok('PA0 offre des dates fixes', pg_temp.pa_off_sql('Dates D', 12, NULL)));
PERFORM pg_temp.ok('PA0 le pro ouvre ses créneaux J+1..J+9', pg_temp.pa_open_sql(1, 9));

-- ═════ PA1 — SESSIONS-A : « Maintenir » l'emporte sur « minimum atteint » ═════
-- accept_booking après le rappel J-2 (sortie demain) qui ATTEINT le minimum : la confirmation enregistrée
-- était « minimum » (la seconde, « pro », tombait sur ON CONFLICT DO NOTHING) — elle devient « pro ».
PERFORM pg_temp.as_('pa_c1');
PERFORM pg_temp.put('bk_c1', pg_temp.ok('PA1 c1 demande pour demain, groupe de 2 (minimum 2)', pg_temp.pa_req('oA', 1, 'am', 2)));
PERFORM pg_temp.as_('pa_pro');
PERFORM pg_temp.ok('PA1 le pro accepte : minimum atteint après le rappel J-2', pg_temp.pa_call('accept_booking', 'bk_c1'));
PERFORM pg_temp.eq('PA1 SESSIONS-A acceptée après J-2 en atteignant le minimum : raison pro (une seule confirmation)',
  $$SELECT pg_temp.pa_reason('oA', 1, 'am')$$, 'pro');
PERFORM pg_temp.eq('PA1 un seul « Départ confirmé » au client', $$SELECT pg_temp.pa_n('pa_c1', 'booking_confirmed', 'bk_c1')$$, '1');
PERFORM pg_temp.as_('pa_c1');
PERFORM pg_temp.ok('PA1 le client annule ensuite', pg_temp.pa_call('cancel_booking', 'bk_c1'));
PERFORM pg_temp.eq('PA1 SESSIONS-A la sortie reste confirmée après l''annulation', $$SELECT pg_temp.pa_conf('oA', 1, 'am')$$, 'true');
-- create_manual_booking après le rappel J-2 qui atteint le minimum.
PERFORM pg_temp.as_('pa_pro');
PERFORM pg_temp.ok('PA1 le pro ajoute 2 personnes en manuel pour demain après-midi (minimum 2)', pg_temp.pa_manual('oB', 1, 'pm', 2));
PERFORM pg_temp.eq('PA1 SESSIONS-A manuelle après J-2 qui atteint le minimum : raison pro', $$SELECT pg_temp.pa_reason('oB', 1, 'pm')$$, 'pro');
-- confirm_outing sur une date fixe déjà confirmée par le minimum (avant le rappel J-2).
PERFORM pg_temp.put('sMin', pg_temp.ok('PA1 date J+10, minimum 2', pg_temp.pa_new('oD', 10, 'am', 10, 'am', 8, 2)));
PERFORM pg_temp.as_('pa_c2');
PERFORM pg_temp.put('bk_c2', pg_temp.ok('PA1 c2 s''inscrit à 2 : minimum atteint', pg_temp.pa_join('sMin', 2)));
PERFORM pg_temp.eq('PA1 (contrôle) confirmée par le minimum', $$SELECT pg_temp.pa_reason('oD', 10, 'am', 'sMin')$$, 'minimum');
PERFORM pg_temp.as_('pa_pro');
PERFORM pg_temp.eq('PA1 SESSIONS-A maintenir une date déjà confirmée par le minimum : true', pg_temp.pa_confirm('oD', 10, 'am'), 'true');
PERFORM pg_temp.eq('PA1 SESSIONS-A la raison devient pro', $$SELECT pg_temp.pa_reason('oD', 10, 'am', 'sMin')$$, 'pro');
PERFORM pg_temp.eq('PA1 pas de second « Départ confirmé » (déjà annoncé)', $$SELECT pg_temp.pa_n('pa_c2', 'booking_confirmed', 'bk_c2')$$, '1');
PERFORM pg_temp.eq('PA1 maintenir une seconde fois : false', pg_temp.pa_confirm('oD', 10, 'am'), 'false');
PERFORM pg_temp.as_('pa_c2');
PERFORM pg_temp.ok('PA1 c2 annule (la date retombe sous le minimum, avant le rappel J-2)', pg_temp.pa_call('cancel_booking', 'bk_c2'));
PERFORM pg_temp.eq('PA1 SESSIONS-A la confirmation pro reste', $$SELECT pg_temp.pa_reason('oD', 10, 'am', 'sMin')$$, 'pro');

-- ═════ PA2 — SESSIONS-B : après le rappel J-2, un départ ne retire plus la confirmation ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pa_ss('sB1', 'oD', 1, 'pm', 1, 'pm', 8, 2);     -- demain : après le rappel J-2
PERFORM pg_temp.pa_bk('bk_b1a', 'oD', 'pa_c3', 1, 'pm', 1, 'accepted', 'sB1');
PERFORM pg_temp.pa_bk('bk_b1b', 'oD', 'pa_c4', 1, 'pm', 1, 'accepted', 'sB1');
PERFORM pg_temp.pa_oc('oD', 1, 'pm', 'sB1', 'minimum');
PERFORM pg_temp.pa_ss('sB2', 'oD', 12, 'am', 12, 'am', 8, 2);   -- J+12 : avant le rappel
PERFORM pg_temp.pa_bk('bk_b2a', 'oD', 'pa_c5', 12, 'am', 1, 'accepted', 'sB2');
PERFORM pg_temp.pa_bk('bk_b2b', 'oD', 'pa_c6', 12, 'am', 1, 'accepted', 'sB2');
PERFORM pg_temp.pa_oc('oD', 12, 'am', 'sB2', 'minimum');
PERFORM pg_temp.as_('pa_c3');
PERFORM pg_temp.ok('PA2 demain : c3 annule (1/2, sous le minimum)', pg_temp.pa_call('cancel_booking', 'bk_b1a'));
PERFORM pg_temp.eq('PA2 SESSIONS-B après le rappel J-2 : la confirmation « minimum » tient', $$SELECT pg_temp.pa_reason('oD', 1, 'pm', 'sB1')$$, 'minimum');
PERFORM pg_temp.as_('pa_c5');
PERFORM pg_temp.ok('PA2 J+12 : c5 annule (1/2, sous le minimum)', pg_temp.pa_call('cancel_booking', 'bk_b2a'));
PERFORM pg_temp.eq('PA2 avant le rappel J-2 : la confirmation « minimum » retombe (inchangé)', $$SELECT pg_temp.pa_reason('oD', 12, 'am', 'sB2')$$, 'none');

-- ═════ PA3 — SESSIONS-C : retiré d'une date par le pro, pas de réinscription à cette date ═════
PERFORM pg_temp.as_('pa_pro');
PERFORM pg_temp.put('sC1', pg_temp.ok('PA3 date J+14', pg_temp.pa_new('oD', 14, 'am', 14, 'am', 8)));
PERFORM pg_temp.put('sC2', pg_temp.ok('PA3 autre date de la même offre J+15', pg_temp.pa_new('oD', 15, 'am', 15, 'am', 8)));
PERFORM pg_temp.as_('pa_c7');
PERFORM pg_temp.put('bk_c7', pg_temp.ok('PA3 c7 s''inscrit à J+14', pg_temp.pa_join('sC1', 1)));
PERFORM pg_temp.as_('pa_pro');
PERFORM pg_temp.ok('PA3 le pro retire c7 de la date', pg_temp.pa_call('cancel_booking_pro', 'bk_c7'));
PERFORM pg_temp.eq('PA3 (contrôle) inscription cancelled_pro', $$SELECT pg_temp.pa_bst('bk_c7')$$, 'cancelled_pro');
PERFORM pg_temp.as_('pa_c7');
PERFORM pg_temp.denied('PA3 SESSIONS-C réinscription à la même date refusée', pg_temp.pa_join('sC1', 1), '^Operation not permitted$');
PERFORM pg_temp.eq('PA3 la ligne reste cancelled_pro', $$SELECT pg_temp.pa_bst('bk_c7')$$, 'cancelled_pro');
PERFORM pg_temp.ok('PA3 une autre date de la même offre reste ouverte', pg_temp.pa_join('sC2', 1));

-- ═════ PA4 — SESSIONS-D : une date déplacée repart de zéro ═════
PERFORM pg_temp.as_('pa_pro6');
PERFORM pg_temp.put('o6', pg_temp.ok('PA4 offre du pro6', pg_temp.pa_off_sql('Dates 6', 8, NULL)));
PERFORM pg_temp.put('sD', pg_temp.ok('PA4 date postée pour demain après-midi (minimum 3)', pg_temp.pa_new('o6', 1, 'pm', 1, 'pm', 6, 3)));
PERFORM pg_temp.eq('PA4 (contrôle) postée après le rappel J-2 : maintenue (raison pro)', $$SELECT pg_temp.pa_reason('o6', 1, 'pm', 'sD')$$, 'pro');
PERFORM pg_temp.ok('PA4 la date est déplacée à J+40', pg_temp.pa_upd('sD', 40, 'am', 40, 'am', 6, 3));
PERFORM pg_temp.eq('PA4 SESSIONS-D déplacée loin : plus aucune confirmation', $$SELECT pg_temp.pa_reason('o6', 40, 'am', 'sD')$$, 'none');
PERFORM pg_temp.ok('PA4 la date revient à demain matin', pg_temp.pa_upd('sD', 1, 'am', 1, 'am', 6, 3));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PA4 SESSIONS-D déplacée dans la fenêtre J-2 : maintenue (pro), au nouveau jour / demi-journée',
  $$SELECT string_agg(reason || '/' || (day = pg_temp.pa_d(1))::text || '/' || period, ',') FROM private.outing_confirmations WHERE session_id = pg_temp.id('sD')$$, 'pro/true/am');

-- ═════ PA5 — CLIENT-4 : groupe > 6 sur une date ═════
PERFORM pg_temp.as_('pa_pro');
PERFORM pg_temp.put('sQ', pg_temp.ok('PA5 date J+16 de 12 places', pg_temp.pa_new('oD', 16, 'am', 16, 'am', 12)));
PERFORM pg_temp.as_('pa_c8');
PERFORM pg_temp.denied('PA5 CLIENT-4 groupe de 7 sur 12 places : junto.session_group_cap', pg_temp.pa_join('sQ', 7), '^junto\.session_group_cap$');
PERFORM pg_temp.denied('PA5 CLIENT-4 groupe au-delà des places : junto.booking_party_size', pg_temp.pa_join('sQ', 13), '^junto\.booking_party_size$');
PERFORM pg_temp.ok('PA5 (contrôle) un groupe de 6 passe', pg_temp.pa_join('sQ', 6));

-- ═════ PA6 — BOOKINGS-R3 : caractères invisibles retirés avant les contrôles ═════
PERFORM pg_temp.as_('pa_c9');
PERFORM pg_temp.put('bk_r3', pg_temp.ok('PA6 BOOKINGS-R3 create_booking avec un message invisible (U+200B) accepté', pg_temp.pa_req('oA', 5, 'am', 1, chr(8203))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PA6 BOOKINGS-R3 message invisible enregistré NULL', $$SELECT coalesce(message, 'NULL') FROM public.bookings WHERE id = pg_temp.id('bk_r3')$$, 'NULL');
PERFORM pg_temp.as_('pa_pro');
PERFORM pg_temp.denied('PA6 BOOKINGS-R3 saisie manuelle au nom invisible refusée', pg_temp.pa_manual('oB', 6, 'am', 1, chr(8203)), '^junto\.booking_manual_name$');
PERFORM pg_temp.denied('PA6 BOOKINGS-R3 nom réduit à rien (HTML + invisibles + espaces) refusé', pg_temp.pa_manual('oB', 6, 'am', 1, '<b></b>' || chr(8203) || ' ' || chr(65279)), '^junto\.booking_manual_name$');
PERFORM pg_temp.as_('pa_c9');
PERFORM pg_temp.put('bk_r3j', pg_temp.ok('PA6 BOOKINGS-R3 join_pro_session avec un message invisible accepté', pg_temp.pa_join('sQ', 1, chr(8203) || ' ')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PA6 BOOKINGS-R3 message d''inscription invisible enregistré NULL', $$SELECT coalesce(message, 'NULL') FROM public.bookings WHERE id = pg_temp.id('bk_r3j')$$, 'NULL');

-- ═════ PA7 — BOOKINGS-R4 : blocage entre un client et un pro ═════
PERFORM pg_temp.as_('pa_pro2');
PERFORM pg_temp.put('o2', pg_temp.ok('PA7 offre du pro2', pg_temp.pa_off_sql('Rando 2', 8, NULL)));
PERFORM pg_temp.put('o2f', pg_temp.ok('PA7 offre du pro2 avec fiches participants', pg_temp.pa_off_sql('Rando 2 fiches', 8, NULL)));
PERFORM pg_temp.ok('PA7 le pro2 ouvre ses créneaux J+1..J+9', pg_temp.pa_open_sql(1, 9));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_offerings SET participant_fields = '{"std": ["weight"], "custom": []}'::jsonb WHERE id = pg_temp.id('o2f');
PERFORM set_config('junto.bypass_lock', 'false', true);
-- Demandes en attente : retirées en silence par le blocage.
PERFORM pg_temp.as_('pa_b1');
PERFORM pg_temp.put('bk_b1', pg_temp.ok('PA7 b1 demande J+5', pg_temp.pa_req('o2', 5, 'am', 1)));
PERFORM pg_temp.as_('pa_b2');
PERFORM pg_temp.put('bk_b2', pg_temp.ok('PA7 b2 demande J+6', pg_temp.pa_req('o2', 6, 'am', 1)));
PERFORM pg_temp.as_('pa_b3');
PERFORM pg_temp.put('bk_b3', pg_temp.ok('PA7 b3 demande J+7', pg_temp.pa_req('o2', 7, 'am', 1)));
PERFORM pg_temp.as_('pa_b4');
PERFORM pg_temp.put('bk_b4', pg_temp.ok('PA7 b4 demande J+8', pg_temp.pa_req('o2', 8, 'am', 1)));
PERFORM pg_temp.as_('pa_pro2');
PERFORM pg_temp.ok('PA7 le pro2 accepte b3', pg_temp.pa_call('accept_booking', 'bk_b3'));
PERFORM pg_temp.ok('PA7 le pro2 accepte b4', pg_temp.pa_call('accept_booking', 'bk_b4'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pa_blk('pa_pro2', 'pa_b1');   -- le pro bloque un demandeur
PERFORM pg_temp.pa_blk('pa_b2', 'pa_pro2');   -- un demandeur bloque le pro
PERFORM pg_temp.pa_blk('pa_b3', 'pa_pro2');   -- un client accepté bloque le pro
PERFORM pg_temp.pa_blk('pa_pro2', 'pa_b4');   -- le pro bloque un client accepté
PERFORM pg_temp.eq('PA7 BOOKINGS-R4 le pro bloque : la demande en attente est déclinée', $$SELECT pg_temp.pa_bst('bk_b1')$$, 'declined');
PERFORM pg_temp.eq('PA7 BOOKINGS-R4 le client bloque : sa demande en attente est retirée (cancelled)', $$SELECT pg_temp.pa_bst('bk_b2')$$, 'cancelled');
PERFORM pg_temp.eq('PA7 BOOKINGS-R4 retraits silencieux : aucune notification',
  $$SELECT pg_temp.pa_n('pa_b1', 'booking_declined', 'bk_b1') || '/' || pg_temp.pa_n('pa_pro2', 'booking_cancelled', 'bk_b2')$$, '0/0');
PERFORM pg_temp.eq('PA7 BOOKINGS-R4 les réservations acceptées restent (logistique)', $$SELECT pg_temp.pa_bst('bk_b3') || '/' || pg_temp.pa_bst('bk_b4')$$, 'accepted/accepted');
-- Annulations par le pro entre bloqués : avis neutre (pas de variante, pas de nom).
PERFORM pg_temp.as_('pa_pro2');
PERFORM pg_temp.ok('PA7 le pro2 annule la réservation de b3 (qui l''a bloqué)', pg_temp.pa_call('cancel_booking_pro', 'bk_b3'));
PERFORM pg_temp.eq('PA7 BOOKINGS-R4 cancel_booking_pro : avis sans variante, sans nom, nom du pro absent', $$SELECT pg_temp.pa_neutral('pa_b3', 'bk_b3')$$, 'false/false/true');
PERFORM pg_temp.eq('PA7 BOOKINGS-R4 cancel_outing sur la sortie de b4 (bloqué par le pro) : 1 réservation', format($$SELECT public.cancel_outing(%L, %L, 'am')::text$$, pg_temp.id('o2'), pg_temp.pa_d(8)), '1');
PERFORM pg_temp.eq('PA7 BOOKINGS-R4 cancel_outing : avis sans variante, sans nom, nom du pro absent', $$SELECT pg_temp.pa_neutral('pa_b4', 'bk_b4')$$, 'false/false/true');
-- Rappels de la veille (J-1) et des fiches (J-3) : copies sans la porte horaire de 18 h (Paris).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pa_bk('bk_b5', 'o2', 'pa_b5', 1, 'am', 1, 'accepted');     -- bloque le pro
PERFORM pg_temp.pa_bk('bk_b6', 'o2', 'pa_b6', 1, 'pm', 1, 'accepted');     -- témoin, sans blocage
PERFORM pg_temp.pa_bk('bk_b7', 'o2f', 'pa_b7', 3, 'am', 1, 'accepted');    -- bloqué par le pro, fiche vide
PERFORM pg_temp.pa_blk('pa_b5', 'pa_pro2');
PERFORM pg_temp.pa_blk('pa_pro2', 'pa_b7');
PERFORM pg_temp.eq('PA7 porte horaire de notify_booking_reminders trouvée telle quelle',
  $$SELECT (position('<> 18 THEN RETURN' in pg_get_functiondef('private.notify_booking_reminders()'::regprocedure)) > 0)::text$$, 'true');
PERFORM pg_temp.eq('PA7 porte horaire de notify_booking_forms_reminders trouvée telle quelle',
  $$SELECT (position('<> 18 THEN RETURN' in pg_get_functiondef('private.notify_booking_forms_reminders()'::regprocedure)) > 0)::text$$, 'true');
EXECUTE replace(replace(pg_get_functiondef('private.notify_booking_reminders()'::regprocedure), '<> 18 THEN RETURN', '< 0 THEN RETURN'),
  'private.notify_booking_reminders', 'pg_temp.pa_nbr');
EXECUTE replace(replace(pg_get_functiondef('private.notify_booking_forms_reminders()'::regprocedure), '<> 18 THEN RETURN', '< 0 THEN RETURN'),
  'private.notify_booking_forms_reminders', 'pg_temp.pa_nbfr');
PERFORM pg_temp.ok('PA7 rappel J-1 (copie sans porte horaire)', $$SELECT pg_temp.pa_nbr()::text$$);
PERFORM pg_temp.ok('PA7 rappel des fiches J-3 (copie sans porte horaire)', $$SELECT pg_temp.pa_nbfr()::text$$);
PERFORM pg_temp.eq('PA7 BOOKINGS-R4 rappel J-1 entre bloqués : variante plain, nom vide, nom du pro absent',
  $$SELECT string_agg((data->>'variant') || '/' || (data->'params'->>'name') || '/' || (title || body NOT LIKE '%Guide Zorglub%')::text, ',')
    FROM public.notifications WHERE user_id = pg_temp.id('pa_b5') AND type = 'booking_reminder' AND data->>'booking_id' = pg_temp.get('bk_b5')$$, 'plain//true');
PERFORM pg_temp.eq('PA7 (témoin) rappel J-1 sans blocage : pas de variante, le nom du pro',
  $$SELECT string_agg(coalesce(data->>'variant', 'NULL') || '/' || (data->'params'->>'name'), ',')
    FROM public.notifications WHERE user_id = pg_temp.id('pa_b6') AND type = 'booking_reminder' AND data->>'booking_id' = pg_temp.get('bk_b6')$$, 'NULL/Guide Zorglub');
PERFORM pg_temp.eq('PA7 BOOKINGS-R4 rappel des fiches J-3 entre bloqués : variante plain, nom vide, texte sans nom',
  $$SELECT string_agg((data->>'variant') || '/' || (data->'params'->>'name') || '/' || (body LIKE 'Remplis les infos%' AND body NOT LIKE '%Guide Zorglub%')::text, ',')
    FROM public.notifications WHERE user_id = pg_temp.id('pa_b7') AND type = 'booking_forms_reminder' AND data->>'booking_id' = pg_temp.get('bk_b7')$$, 'plain//true');

-- ═════ PA8 — VITRINE-5 : une sortie en cours bloque suppression d'offre et désinscription ═════
PERFORM pg_temp.as_('pa_pro3');
PERFORM pg_temp.put('o3', pg_temp.ok('PA8 offre du pro3', pg_temp.pa_off_sql('Trek 3', 8, NULL)));
PERFORM pg_temp.as_('pa_pro4');
PERFORM pg_temp.put('o4', pg_temp.ok('PA8 offre du pro4', pg_temp.pa_off_sql('Trek 4', 8, NULL)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pa_bk('bk_v1', 'o3', 'pa_v1', -1, 'am', 1, 'accepted', NULL, 1);   -- plage hier → demain
PERFORM pg_temp.pa_ss('sV', 'o4', -1, 'am', 1, 'pm', 8);                             -- date hier → demain
PERFORM pg_temp.pa_bk('bk_v2', 'o4', 'pa_v2', -1, 'am', 1, 'accepted', 'sV');
PERFORM pg_temp.as_('pa_pro3');
PERFORM pg_temp.denied('PA8 VITRINE-5 plage en cours : suppression de l''offre refusée',
  format($$SELECT public.delete_pro_offering(%L)::text$$, pg_temp.id('o3')), '^junto\.offering_has_bookings$');
PERFORM pg_temp.denied('PA8 VITRINE-5 plage en cours : désinscription pro refusée', $$SELECT public.unregister_as_pro()::text$$, '^junto\.offering_has_bookings$');
PERFORM pg_temp.as_('pa_pro4');
PERFORM pg_temp.denied('PA8 VITRINE-5 date fixe en cours : suppression de l''offre refusée',
  format($$SELECT public.delete_pro_offering(%L)::text$$, pg_temp.id('o4')), '^junto\.offering_has_bookings$');
PERFORM pg_temp.denied('PA8 VITRINE-5 date fixe en cours : désinscription pro refusée', $$SELECT public.unregister_as_pro()::text$$, '^junto\.offering_has_bookings$');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PA8 offres et vitrines toujours là',
  $$SELECT (SELECT count(*) FROM public.pro_offerings WHERE id IN (pg_temp.id('o3'), pg_temp.id('o4')))::text || '/'
    || (SELECT count(*) FROM public.pro_profiles WHERE user_id IN (pg_temp.id('pa_pro3'), pg_temp.id('pa_pro4')))::text$$, '2/2');

-- ═════ PA9 — CLIENT-1 / CLIENT-3 : photos communautaires ═════
PERFORM pg_temp.as_('pa_pro5');
PERFORM pg_temp.put('o5', pg_temp.ok('PA9 offre du pro5', pg_temp.pa_off_sql('Canyon 5', 8, NULL)));
PERFORM pg_temp.put('o5b', pg_temp.ok('PA9 seconde offre du pro5 (jamais réservée)', pg_temp.pa_off_sql('Canyon 5 bis', 8, NULL)));
PERFORM pg_temp.as_('db');
-- Sorties finies chez pro5 : p1 (contributeur), p3 (modération, PA10), p4 (bloqué par le pro), pa_sus (suspendu).
PERFORM pg_temp.pa_bk('bk_p1', 'o5', 'pa_p1', -8, 'am', 1, 'accepted');
PERFORM pg_temp.pa_bk('bk_p3', 'o5', 'pa_p3', -8, 'pm', 1, 'accepted');
PERFORM pg_temp.pa_bk('bk_p4', 'o5', 'pa_p4', -9, 'am', 1, 'accepted');
PERFORM pg_temp.pa_bk('bk_sus', 'o5', 'pa_sus', -9, 'pm', 1, 'accepted');
PERFORM pg_temp.pa_blk('pa_pro5', 'pa_p4');
-- Fichiers : « ok » envoyé par p1 (daté de 2000 : sert aussi PA11), « autre » dans le dossier de p1 mais
-- envoyé par p2, celui de p2 (sans sortie), celui de p3.
PERFORM pg_temp.put('f_ok', pg_temp.pa_file('pa_p1', 'pa_pro5', 'ok.jpg', NULL, '2000-01-01 00:00+00'));
PERFORM pg_temp.pa_file('pa_p1', 'pa_pro5', 'autre.jpg', 'pa_p2');
PERFORM pg_temp.pa_file('pa_p2', 'pa_pro5', 'p2.jpg');
PERFORM pg_temp.pa_file('pa_p3', 'pa_pro5', 'p3.jpg');
-- add_pro_community_photo.
PERFORM pg_temp.as_('pa_p1');
PERFORM pg_temp.denied('PA9 CLIENT-1 URL valide dans le bon dossier mais aucun fichier : refusé',
  pg_temp.pa_photo('pa_pro5', pg_temp.pa_url('pa_p1', 'pa_pro5', 'absent.jpg')), '^Operation not permitted$');
PERFORM pg_temp.denied('PA9 CLIENT-1 fichier présent mais envoyé par un autre compte : refusé',
  pg_temp.pa_photo('pa_pro5', pg_temp.pa_url('pa_p1', 'pa_pro5', 'autre.jpg')), '^Operation not permitted$');
PERFORM pg_temp.put('cp_ok', pg_temp.ok('PA9 CLIENT-1 fichier présent, envoyé par l''appelant : photo ajoutée',
  pg_temp.pa_photo('pa_pro5', pg_temp.pa_url('pa_p1', 'pa_pro5', 'ok.jpg'))));
PERFORM pg_temp.as_('pa_p2');
PERFORM pg_temp.denied('PA9 CLIENT-3 sans sortie finie chez ce pro : junto.photo_requires_booking',
  pg_temp.pa_photo('pa_pro5', pg_temp.pa_url('pa_p2', 'pa_pro5', 'p2.jpg')), '^junto\.photo_requires_booking$');
-- can_add_community_photo.
PERFORM pg_temp.as_('pa_p1');
PERFORM pg_temp.eq('PA9 can_add : sortie acceptée finie → true', pg_temp.pa_can('pa_pro5'), 'true');
PERFORM pg_temp.eq('PA9 can_add : avec l''offre réservée → true', pg_temp.pa_can('pa_pro5', 'o5'), 'true');
PERFORM pg_temp.eq('PA9 can_add : avec une offre jamais réservée → false', pg_temp.pa_can('pa_pro5', 'o5b'), 'false');
PERFORM pg_temp.as_('pa_p2');
PERFORM pg_temp.eq('PA9 can_add : sans réservation → false', pg_temp.pa_can('pa_pro5'), 'false');
PERFORM pg_temp.as_('pa_pro5');
PERFORM pg_temp.eq('PA9 can_add : sa propre page → false', pg_temp.pa_can('pa_pro5'), 'false');
PERFORM pg_temp.as_('pa_p4');
PERFORM pg_temp.eq('PA9 can_add : bloqué par le pro (sortie finie) → false', pg_temp.pa_can('pa_pro5'), 'false');
PERFORM pg_temp.as_('pa_sus');
PERFORM pg_temp.eq('PA9 can_add : appelant suspendu (sortie finie) → false', pg_temp.pa_can('pa_pro5'), 'false');
PERFORM pg_temp.as_('pa_p1');
PERFORM pg_temp.eq('PA9 can_add : pro inexistant → false', format($$SELECT public.can_add_community_photo(%L)::text$$, gen_random_uuid()), 'false');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('PA9 can_add : anon ne l''exécute pas', pg_temp.pa_can('pa_pro5'), 'permission denied');

-- ═════ PA10 — VITRINE-6 : suspendre l'auteur d'une photo communautaire signalée ═════
PERFORM pg_temp.as_('pa_p3');
PERFORM pg_temp.put('cp_p3', pg_temp.ok('PA10 p3 ajoute une photo communautaire', pg_temp.pa_photo('pa_pro5', pg_temp.pa_url('pa_p3', 'pa_pro5', 'p3.jpg'))));
PERFORM pg_temp.as_('pa_p2');
PERFORM pg_temp.ok('PA10 p2 signale la photo', format($$SELECT public.create_report('pro_community_photo', %L, 'Photo sans rapport avec la sortie')::text$$, pg_temp.id('cp_p3')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('rep_p3', (SELECT id::text FROM public.reports WHERE target_type = 'pro_community_photo' AND target_id = pg_temp.id('cp_p3')));
PERFORM pg_temp.as_('pa_adm');
PERFORM pg_temp.denied('PA10 VITRINE-6 suspendre un autre compte que l''auteur depuis ce signalement : refusé',
  format($$SELECT public.moderate_report(%L, 'actioned', 'Hors sujet', %L)::text$$, pg_temp.id('rep_p3'), pg_temp.id('pa_p2')), '^Operation not permitted$');
PERFORM pg_temp.ok('PA10 VITRINE-6 suspendre l''auteur de la photo signalée : accepté',
  format($$SELECT public.moderate_report(%L, 'actioned', 'Hors sujet', %L)::text$$, pg_temp.id('rep_p3'), pg_temp.id('pa_p3')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PA10 l''auteur est suspendu, l''autre compte non, le signalement traité',
  $$SELECT (SELECT (suspended_at IS NOT NULL)::text FROM public.users WHERE id = pg_temp.id('pa_p3')) || '/'
    || (SELECT (suspended_at IS NOT NULL)::text FROM public.users WHERE id = pg_temp.id('pa_p2')) || '/'
    || (SELECT status FROM public.reports WHERE id = pg_temp.id('rep_p3'))$$, 'true/false/actioned');

-- ═════ PA11 — VITRINE-7 : fichiers communautaires orphelins ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('f_orph', pg_temp.pa_file('pa_p1', 'pa_pro5', 'orphelin.jpg', NULL, '2000-01-01 00:00+00'));
PERFORM pg_temp.put('f_fresh', pg_temp.pa_file('pa_p1', 'pa_pro5', 'frais.jpg'));
PERFORM pg_temp.eq('PA11 VITRINE-7 un fichier communautaire orphelin de plus d''1 h est listé',
  $$SELECT (pg_temp.get('f_orph') IN (SELECT x FROM public.community_photo_orphans(100) x))::text$$, 'true');
PERFORM pg_temp.eq('PA11 VITRINE-7 un fichier vers lequel pointe une photo n''est pas listé',
  $$SELECT (pg_temp.get('f_ok') IN (SELECT x FROM public.community_photo_orphans(100) x))::text$$, 'false');
PERFORM pg_temp.eq('PA11 VITRINE-7 un fichier récent (envoi peut-être en cours) n''est pas listé',
  $$SELECT (pg_temp.get('f_fresh') IN (SELECT x FROM public.community_photo_orphans(100) x))::text$$, 'false');
PERFORM pg_temp.eq('PA11 VITRINE-7 hors du sous-dossier community/ : jamais listé',
  $$SELECT count(*)::text FROM public.community_photo_orphans(100) x WHERE (storage.foldername(x))[2] IS DISTINCT FROM 'community'$$, '0');
PERFORM pg_temp.as_('pa_p1');
PERFORM pg_temp.denied('PA11 un compte n''exécute pas community_photo_orphans', $$SELECT count(*)::text FROM public.community_photo_orphans(100)$$, 'permission denied');
PERFORM pg_temp.denied('PA11 un compte n''exécute pas private.trigger_storage_cleanup', $$SELECT private.trigger_storage_cleanup()::text$$, 'permission denied');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('PA11 anon n''exécute pas community_photo_orphans', $$SELECT count(*)::text FROM public.community_photo_orphans(100)$$, 'permission denied');

-- ═════ PA12 — BOOKINGS-R1 / R2 : ordre des verrous (courses — contrôle statique) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PA12 BOOKINGS-R1 cancel_outing prend le verrou de la date avant celui du créneau',
  $$SELECT (position('_session' in d) > 0 AND position('_session' in d) < position('_slot' in d))::text
    FROM pg_get_functiondef('public.cancel_outing(uuid, date, text, text)'::regprocedure) d$$, 'true');
PERFORM pg_temp.eq('PA12 BOOKINGS-R1 admin_suspend_user ferme les dates avant de parcourir les réservations',
  $$SELECT (position('UPDATE pro_sessions' in d) > 0 AND position('UPDATE pro_sessions' in d) < position('FOR v_bk IN' in d))::text
    FROM pg_get_functiondef('public.admin_suspend_user(uuid, text)'::regprocedure) d$$, 'true');
PERFORM pg_temp.eq('PA12 BOOKINGS-R2 cancel_booking prend le verrou de la sortie avant de verrouiller la ligne',
  $$SELECT (position('pg_advisory_xact_lock' in d) > 0 AND position('pg_advisory_xact_lock' in d) < position('FOR UPDATE' in d))::text
    FROM pg_get_functiondef('public.cancel_booking(uuid)'::regprocedure) d$$, 'true');
PERFORM pg_temp.eq('PA12 BOOKINGS-R2 cancel_booking_pro prend le verrou de la sortie avant de verrouiller la ligne',
  $$SELECT (position('pg_advisory_xact_lock' in d) > 0 AND position('pg_advisory_xact_lock' in d) < position('FOR UPDATE' in d))::text
    FROM pg_get_functiondef('public.cancel_booking_pro(uuid)'::regprocedure) d$$, 'true');

END;
