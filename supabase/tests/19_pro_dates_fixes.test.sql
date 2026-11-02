-- Domaine 19 — Pro : dates fixes (00575-00576) et minimum de participants (00577).
--
-- Chaînes testées : docs/SECURITY.md → « Réservations pro » → « Dates fixes (00575-00576…) »
-- et « Plusieurs jours « sur demande » + minimum (00577…) ». Chaque étape de chaque chaîne
-- a au moins un contrôle ; l'ordre des sections suit l'ordre des chaînes.
--
-- Jours : pg_temp.dd(n) = aujourd'hui (heure de Paris) + n. Les dates « commencées » ou
-- « finies » sont insérées directement (en 'db') : aucune RPC ne permet d'en créer.
-- Les fixtures des crons sont aussi insérées en 'db' (dates, résas, confirmations), pour que
-- les correctifs SESSIONS-2a (une résa acceptée / une date postée après le rappel J-2 vaut
-- « maintenue ») ne changent pas le sens de ces contrôles une fois livrés.
--
-- Trous de l'audit 2026-11 — SESSIONS-1/2/4/6 corrigés en 00578 (contrôles désormais ordinaires) :
--   SESSIONS-1 / GRANTS-1  la confirmation « minimum » ne retombe jamais (annulation, baisse du minimum)
--   SESSIONS-2             (a) acceptée / ajoutée / postée après le rappel J-2 = maintenue (raison pro) ;
--                          (b) l'annulation auto devient un choix : pro_offerings.auto_cancel (défaut false)
--   SESSIONS-4             inscription instantanée : groupe ≤ 6, ≤ 3 inscriptions actives à venir par pro
--   SESSIONS-5             create_manual_booking ne relit pas le statut de la date sous le verrou.
--                          C'est une COURSE (deux appareils du même pro) : non reproductible ici en
--                          séquentiel — le contrôle séquentiel ci-dessous passe déjà (date annulée
--                          avant l'appel → pas de rattachement).
--   SESSIONS-6             admin_suspend_user ignore les dates, les confirmations et les plages commencées
--   SESSIONS-3             ordre des verrous (join FOR SHARE puis verrou consultatif, cancel/update/cron
--                          l'inverse ; accept_booking ligne puis créneaux, cron/cancel_outing l'inverse) :
--                          interblocage possible entre deux sessions concurrentes. Non testable dans un
--                          bloc unique — documenté ici seulement.

DECLARE v_lbl text;  -- bloc local : variable de boucle
BEGIN

-- ───── Helpers locaux ─────
EXECUTE $p$CREATE FUNCTION pg_temp.dd(n integer) RETURNS date
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT private.today_paris() + n $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_reg_sql(p_name text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.register_as_pro(p_display_name := %L, p_company_name := 'SARL Test', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$s$, p_name) $b$$p$;
-- Offre : max, minimum (NULL = pas de minimum), 50 €/personne.
EXECUTE $p$CREATE FUNCTION pg_temp.df_off_sql(p_title text, p_max integer, p_min integer) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_pro_offering(p_sport_id := %L, p_title := %L, p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon',
      p_max_participants := %L, p_price_eur := 50, p_price_unit := 'person', p_min_participants := %L)::text$s$,
      pg_temp.id('df_sport'), p_title, p_max, p_min) $b$$p$;
-- Appel create_pro_session (jours relatifs).
EXECUTE $p$CREATE FUNCTION pg_temp.df_new(p_off text, p_sn integer, p_sp text, p_en integer, p_ep text, p_max integer, p_min integer DEFAULT NULL, p_meeting text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_pro_session(%L, %L, %L, %L, %L, %L, %L, %L)::text$s$,
      pg_temp.id(p_off), pg_temp.dd(p_sn), p_sp, pg_temp.dd(p_en), p_ep, p_max, p_min, p_meeting) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_upd(p_sess text, p_sn integer, p_sp text, p_en integer, p_ep text, p_max integer, p_min integer DEFAULT NULL, p_meeting text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.update_pro_session(%L, %L, %L, %L, %L, %L, %L, %L)::text$s$,
      pg_temp.id(p_sess), pg_temp.dd(p_sn), p_sp, pg_temp.dd(p_en), p_ep, p_max, p_min, p_meeting) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_join(p_sess text, p_party integer, p_msg text DEFAULT NULL) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.join_pro_session(%L, %L, %L)::text$s$, pg_temp.id(p_sess), p_party, p_msg) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_req(p_off text, p_dn integer, p_period text, p_party integer) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_booking(%L, %L, %L, %L)::text$s$, pg_temp.id(p_off), pg_temp.dd(p_dn), p_period, p_party) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_manual(p_off text, p_dn integer, p_period text, p_party integer) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_manual_booking(%L, %L, %L, %L, 'Client tel')::text$s$, pg_temp.id(p_off), pg_temp.dd(p_dn), p_period, p_party) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_confirm(p_off text, p_dn integer, p_period text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.confirm_outing(%L, %L, %L)::text$s$, pg_temp.id(p_off), pg_temp.dd(p_dn), p_period) $b$$p$;
-- Ouvre les créneaux matin + après-midi des jours [a, b] (le pro courant).
EXECUTE $p$CREATE FUNCTION pg_temp.df_open_sql(a integer, b integer) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.set_pro_availability_bulk(x.ds, x.ps, true)::text FROM (
      SELECT array_agg(pg_temp.dd(i) ORDER BY i, p) ds, array_agg(p ORDER BY i, p) ps
      FROM generate_series(%s, %s) i CROSS JOIN (VALUES ('am'), ('pm')) v(p)) x$s$, a, b) $b$$p$;
-- Fixtures directes (en 'db').
EXECUTE $p$CREATE FUNCTION pg_temp.df_ss(p_label text, p_off text, p_sn integer, p_sp text, p_en integer, p_ep text,
    p_max integer, p_min integer DEFAULT NULL, p_status text DEFAULT 'scheduled') RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.pro_sessions (pro_id, offering_id, start_day, start_period, end_day, end_period, max_participants, min_participants, status)
    SELECT o.pro_id, o.id, pg_temp.dd(p_sn), p_sp, pg_temp.dd(p_en), p_ep, p_max, p_min, p_status
    FROM public.pro_offerings o WHERE o.id = pg_temp.id(p_off) RETURNING id INTO v;
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;
-- Résa directe ; client NULL = résa manuelle ; créée il y a 2 jours (hors plafond 24 h).
EXECUTE $p$CREATE FUNCTION pg_temp.df_bk(p_label text, p_off text, p_client text, p_dn integer, p_period text, p_party integer,
    p_status text, p_sess text DEFAULT NULL, p_end_dn integer DEFAULT NULL, p_recent boolean DEFAULT false) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid; t timestamptz := CASE WHEN p_recent THEN now() ELSE now() - INTERVAL '2 days' END;
  BEGIN
    INSERT INTO public.bookings (offering_id, pro_id, client_id, manual_name, day, period, end_day, party_size, status, session_id,
                                 created_at, last_submitted_at, price_eur, price_unit)
    SELECT o.id, o.pro_id, pg_temp.id(p_client), CASE WHEN p_client IS NULL THEN 'Client manuel' END,
           pg_temp.dd(p_dn), p_period, CASE WHEN p_end_dn IS NOT NULL THEN pg_temp.dd(p_end_dn) END,
           p_party, p_status, pg_temp.id(p_sess), t, t, 50, 'person'
    FROM public.pro_offerings o WHERE o.id = pg_temp.id(p_off) RETURNING id INTO v;
    IF p_label IS NOT NULL THEN PERFORM pg_temp.put(p_label, v::text); END IF;
    RETURN v;
  END $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_oc(p_off text, p_dn integer, p_period text, p_sess text, p_reason text) RETURNS void
  LANGUAGE sql SECURITY DEFINER AS $b$
  INSERT INTO private.outing_confirmations (pro_id, offering_id, day, period, session_id, reason)
  SELECT o.pro_id, o.id, pg_temp.dd(p_dn), p_period, pg_temp.id(p_sess), p_reason FROM public.pro_offerings o WHERE o.id = pg_temp.id(p_off) $b$$p$;
-- Lectures d'état (lisibles quel que soit le rôle courant).
EXECUTE $p$CREATE FUNCTION pg_temp.df_bst(p_label text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT status FROM public.bookings WHERE id = pg_temp.id(p_label) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_sst(p_label text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT status FROM public.pro_sessions WHERE id = pg_temp.id(p_label) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_conf(p_off text, p_dn integer, p_period text, p_sess text DEFAULT NULL) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT private.outing_confirmed(pg_temp.id(p_off), pg_temp.dd(p_dn), p_period, pg_temp.id(p_sess))::text $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_reason(p_off text, p_dn integer, p_period text, p_sess text DEFAULT NULL) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT coalesce((SELECT c.reason FROM private.outing_confirmations c
    WHERE (p_sess IS NOT NULL AND c.session_id = pg_temp.id(p_sess))
       OR (p_sess IS NULL AND c.session_id IS NULL AND c.offering_id = pg_temp.id(p_off)
           AND c.day = pg_temp.dd(p_dn) AND c.period = p_period) LIMIT 1), 'none') $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_n(p_user text, p_type text, p_booking text DEFAULT NULL) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT count(*)::text FROM public.notifications
    WHERE user_id = pg_temp.id(p_user) AND type = p_type
      AND (p_booking IS NULL OR data->>'booking_id' = pg_temp.get(p_booking)) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.df_dm(p_a text, p_b text) RETURNS uuid
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT id FROM public.conversations WHERE type = 'dm'
    AND user_1 = LEAST(pg_temp.id(p_a), pg_temp.id(p_b)) AND user_2 = GREATEST(pg_temp.id(p_a), pg_temp.id(p_b)) $b$$p$;
-- Opt-in d'annulation auto (SESSIONS-2b, 00578) posé en base ; la RPC set_offering_auto_cancel est testée en DF11b.
EXECUTE $p$CREATE FUNCTION pg_temp.df_optin(p_off text) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  BEGIN
    BEGIN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      EXECUTE 'UPDATE public.pro_offerings SET auto_cancel = true WHERE id = $1' USING pg_temp.id(p_off);
    EXCEPTION WHEN undefined_column THEN NULL;
    END;
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('df_sport', (SELECT id::text FROM public.sports WHERE key = 'hiking'));
PERFORM pg_temp.user('df_adm', 'tos,admin');
PERFORM pg_temp.user('df_pro', 'tos');    -- pro principal (dates, inscriptions, effets)
PERFORM pg_temp.user('df_pro2', 'tos');   -- autre pro (propriété croisée, puis révoqué)
PERFORM pg_temp.user('df_pro3', 'tos');   -- plafond 100 dates, limite 30 en lecture
PERFORM pg_temp.user('df_pro4', 'tos');   -- crons
PERFORM pg_temp.user('df_pro5', 'tos');   -- minimum
PERFORM pg_temp.user('df_pro6', 'tos');   -- suspendu (SESSIONS-6)
PERFORM pg_temp.user('df_demo', 'tos,demo');
PERFORM pg_temp.user('df_cand', 'tos');   -- candidature en attente
PERFORM pg_temp.user('df_sus', 'tos,suspended');
FOREACH v_lbl IN ARRAY ARRAY['df_cA','df_cB','df_cC','df_cD','df_cE','df_cF','df_cG','df_cH','df_cP1','df_cP2','df_cP3',
    'df_cQ','df_cS','df_cCap','df_blk1','df_blk2','df_m1','df_m2','df_m3','df_m4','df_m5','df_m6','df_m7','df_m8',
    'df_k1','df_k2','df_k3','df_k4','df_k5','df_k6','df_k7','df_k8','df_k9','df_k10','df_k11','df_k12','df_k13','df_k14','df_k15'] LOOP
  PERFORM pg_temp.user(v_lbl, 'tos');
END LOOP;

FOREACH v_lbl IN ARRAY ARRAY['df_pro','df_pro2','df_pro3','df_pro4','df_pro5','df_pro6','df_demo','df_cand'] LOOP
  PERFORM pg_temp.as_(v_lbl);
  PERFORM pg_temp.ok('DF0 inscription pro ' || v_lbl, pg_temp.df_reg_sql('Pro ' || v_lbl));
  IF v_lbl <> 'df_cand' THEN
    PERFORM pg_temp.as_('df_adm');
    PERFORM pg_temp.ok('DF0 approbation ' || v_lbl, format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id(v_lbl)));
  END IF;
END LOOP;

PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.put('off_a', pg_temp.ok('DF0 offre A', pg_temp.df_off_sql('Rando A', 8, NULL)));
PERFORM pg_temp.put('off_b', pg_temp.ok('DF0 offre B', pg_temp.df_off_sql('Rando B', 10, NULL)));
PERFORM pg_temp.put('off_m', pg_temp.ok('DF0 offre sur plusieurs jours', pg_temp.df_off_sql('Trek M', 8, NULL)));
PERFORM pg_temp.ok('DF0 offre M : 3 jours sur demande', format($$SELECT public.set_offering_request_length(%L, 3)::text$$, pg_temp.id('off_m')));
PERFORM pg_temp.ok('DF0 pro ouvre ses créneaux J+2..J+62', pg_temp.df_open_sql(2, 62));
PERFORM pg_temp.as_('df_pro2');
PERFORM pg_temp.put('off_2', pg_temp.ok('DF0 offre du pro2', pg_temp.df_off_sql('Rando 2', 8, NULL)));
PERFORM pg_temp.as_('df_pro3');
PERFORM pg_temp.put('off_3', pg_temp.ok('DF0 offre du pro3', pg_temp.df_off_sql('Rando 3', 8, NULL)));
PERFORM pg_temp.as_('df_demo');
PERFORM pg_temp.put('off_demo', pg_temp.ok('DF0 offre du pro démo', pg_temp.df_off_sql('Rando démo', 8, NULL)));
PERFORM pg_temp.put('s_demo', pg_temp.ok('DF0 date du pro démo', pg_temp.df_new('off_demo', 20, 'am', 20, 'am', 6)));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET is_demo = true WHERE user_id = pg_temp.id('df_demo');
UPDATE public.app_config SET value = 'true' WHERE name = 'demo_mode';
PERFORM set_config('junto.bypass_lock', 'false', true);

-- ═════ DF1 — get_session_conflicts ═════
-- Demandes en attente de clients : A (J+10 matin), M sur 3 jours (J+12 → J+14).
PERFORM pg_temp.as_('df_cP1');
PERFORM pg_temp.put('bk_p1_10', pg_temp.ok('DF1 demande en attente J+10 matin', pg_temp.df_req('off_a', 10, 'am', 2)));
PERFORM pg_temp.as_('df_cP2');
PERFORM pg_temp.put('bk_p2_12', pg_temp.ok('DF1 demande sur 3 jours J+12 → J+14', pg_temp.df_req('off_m', 12, 'am', 1)));
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.eq('DF1 le pro voit la demande de la plage',
  format($$SELECT string_agg(booking_id::text, ',') FROM public.get_session_conflicts(%L, 'am', %L, 'pm')$$, pg_temp.dd(10), pg_temp.dd(10)), pg_temp.get('bk_p1_10'));
PERFORM pg_temp.eq('DF1 une plage qui ne touche que le dernier jour d''une demande sur plusieurs jours la voit',
  format($$SELECT string_agg(booking_id::text, ',') FROM public.get_session_conflicts(%L, 'pm', %L, 'pm')$$, pg_temp.dd(14), pg_temp.dd(14)), pg_temp.get('bk_p2_12'));
PERFORM pg_temp.eq('DF1 hors plage : rien',
  format($$SELECT count(*)::text FROM public.get_session_conflicts(%L, 'pm', %L, 'pm')$$, pg_temp.dd(10), pg_temp.dd(11)), '0');
PERFORM pg_temp.denied('DF1 période invalide refusée',
  format($$SELECT count(*)::text FROM public.get_session_conflicts(%L, 'soir', %L, 'pm')$$, pg_temp.dd(10), pg_temp.dd(10)), 'junto.session_dates');
PERFORM pg_temp.denied('DF1 plage de plus de 14 jours refusée',
  format($$SELECT count(*)::text FROM public.get_session_conflicts(%L, 'am', %L, 'pm')$$, pg_temp.dd(10), pg_temp.dd(24)), 'junto.session_dates');
PERFORM pg_temp.as_('df_pro2');
PERFORM pg_temp.eq('DF1 un autre pro ne voit pas ces demandes',
  format($$SELECT count(*)::text FROM public.get_session_conflicts(%L, 'am', %L, 'pm')$$, pg_temp.dd(10), pg_temp.dd(14)), '0');
PERFORM pg_temp.as_('df_cand');
PERFORM pg_temp.denied('DF1 candidat non approuvé refusé',
  format($$SELECT count(*)::text FROM public.get_session_conflicts(%L, 'am', %L, 'pm')$$, pg_temp.dd(10), pg_temp.dd(10)), 'Operation not permitted');
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF1 un membre non pro refusé',
  format($$SELECT count(*)::text FROM public.get_session_conflicts(%L, 'am', %L, 'pm')$$, pg_temp.dd(10), pg_temp.dd(10)), 'Operation not permitted');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('DF1 anon refusé',
  format($$SELECT count(*)::text FROM public.get_session_conflicts(%L, 'am', %L, 'pm')$$, pg_temp.dd(10), pg_temp.dd(10)));

-- ═════ DF2 — create_pro_session ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('DF2 anon ne crée pas de date', pg_temp.df_new('off_a', 20, 'am', 20, 'pm', 6));
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF2 un membre non pro ne crée pas de date', pg_temp.df_new('off_a', 20, 'am', 20, 'pm', 6), 'Operation not permitted');
PERFORM pg_temp.as_('df_cand');
PERFORM pg_temp.denied('DF2 un candidat non approuvé ne crée pas de date', pg_temp.df_new('off_a', 20, 'am', 20, 'pm', 6), 'Operation not permitted');
PERFORM pg_temp.as_('df_pro2');
PERFORM pg_temp.denied('DF2 date sur l''offre d''un autre pro refusée', pg_temp.df_new('off_a', 20, 'am', 20, 'pm', 6), 'Operation not permitted');
PERFORM pg_temp.denied('DF2 date sur une offre inexistante refusée',
  format($$SELECT public.create_pro_session(%L, %L, 'am', %L, 'pm', 6)::text$$, gen_random_uuid(), pg_temp.dd(20), pg_temp.dd(20)), 'Operation not permitted');

PERFORM pg_temp.as_('df_pro');
-- Dates.
PERFORM pg_temp.denied('DF2 fin avant début refusée', pg_temp.df_new('off_a', 21, 'am', 20, 'pm', 6), 'junto.session_dates');
PERFORM pg_temp.denied('DF2 même jour après-midi → matin refusé', pg_temp.df_new('off_a', 20, 'pm', 20, 'am', 6), 'junto.session_dates');
PERFORM pg_temp.denied('DF2 période invalide refusée', pg_temp.df_new('off_a', 20, 'soir', 20, 'pm', 6), 'junto.session_dates');
PERFORM pg_temp.denied('DF2 jour manquant refusé',
  format($$SELECT public.create_pro_session(%L, NULL, 'am', %L, 'pm', 6)::text$$, pg_temp.id('off_a'), pg_temp.dd(20)), 'junto.session_dates');
PERFORM pg_temp.denied('DF2 plus de 14 jours refusé (15 jours calendaires)', pg_temp.df_new('off_a', 120, 'am', 134, 'pm', 6), 'junto.session_dates');
PERFORM pg_temp.denied('DF2 date déjà commencée refusée', pg_temp.df_new('off_a', -1, 'am', 1, 'pm', 6), 'junto.session_dates');
PERFORM pg_temp.denied('DF2 départ au-delà de 12 mois refusé', pg_temp.df_new('off_a', 400, 'am', 400, 'pm', 6), 'junto.session_dates');
-- Places / minimum.
PERFORM pg_temp.denied('DF2 0 place refusé', pg_temp.df_new('off_a', 120, 'am', 120, 'pm', 0), 'junto.session_places');
PERFORM pg_temp.denied('DF2 plus de 50 places refusé', pg_temp.df_new('off_a', 120, 'am', 120, 'pm', 51), 'junto.session_places');
PERFORM pg_temp.denied('DF2 places manquantes refusé', pg_temp.df_new('off_a', 120, 'am', 120, 'pm', NULL), 'junto.session_places');
PERFORM pg_temp.denied('DF2 minimum 0 refusé', pg_temp.df_new('off_a', 120, 'am', 120, 'pm', 6, 0), 'junto.session_places');
PERFORM pg_temp.denied('DF2 minimum > places refusé', pg_temp.df_new('off_a', 120, 'am', 120, 'pm', 6, 7), 'junto.session_places');
-- Point de RDV.
PERFORM pg_temp.denied('DF2 RDV de 121 caractères refusé', pg_temp.df_new('off_a', 120, 'am', 120, 'pm', 6, NULL, repeat('a', 121)), 'junto.session_meeting');
PERFORM pg_temp.put('s_meet', pg_temp.ok('DF2 RDV de 120 caractères + invisibles accepté (les invisibles ne comptent pas)',
  pg_temp.df_new('off_a', 120, 'am', 120, 'pm', 6, NULL, repeat('a', 120) || repeat(E'\u200B', 10))));
PERFORM pg_temp.eq('DF2 RDV : invisibles retirés à l''enregistrement',
  format($$SELECT char_length(meeting_point)::text FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(200), pg_temp.id('s_meet')), '120');
-- La date principale : RDV avec HTML, caractère de contrôle et espace insécable de largeur nulle.
PERFORM pg_temp.put('sA', pg_temp.ok('DF2 le pro crée une date (J+20 journée, 6 places)',
  pg_temp.df_new('off_a', 20, 'am', 20, 'pm', 6, NULL, E'<b>Parking</b>\u200B du\x07 col')));
PERFORM pg_temp.eq('DF2 RDV nettoyé (HTML, contrôle → espace, invisibles retirés)',
  format($$SELECT meeting_point FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('sA')), 'Parking du  col');
PERFORM pg_temp.put('sB', pg_temp.ok('DF2 date adjacente (finit l''après-midi, la suivante part le lendemain matin)',
  pg_temp.df_new('off_a', 21, 'am', 21, 'am', 4)));
PERFORM pg_temp.put('s_long', pg_temp.ok('DF2 14 jours pile acceptés', pg_temp.df_new('off_b', 100, 'am', 113, 'pm', 6, 6)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF2 champs imposés : pro = appelant, statut scheduled',
  format($$SELECT (pro_id = %L)::text || '/' || status FROM public.pro_sessions WHERE id = %L$$, pg_temp.id('df_pro'), pg_temp.id('sA')), 'true/scheduled');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.put('sB2', pg_temp.ok('DF2 RDV réduit à rien après nettoyage → NULL', pg_temp.df_new('off_a', 121, 'am', 121, 'am', 4, NULL, '<b></b>')));
PERFORM pg_temp.eq('DF2 RDV vide enregistré NULL',
  format($$SELECT coalesce(meeting_point, 'NULL') FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(200), pg_temp.id('sB2')), 'NULL');
-- Conflits.
PERFORM pg_temp.denied('DF2 chevauchement avec une autre date refusé', pg_temp.df_new('off_b', 20, 'pm', 21, 'am', 6), 'junto.session_conflict');
PERFORM pg_temp.denied('DF2 même demi-journée sur une autre offre refusée', pg_temp.df_new('off_b', 21, 'am', 21, 'am', 6), 'junto.session_conflict');
PERFORM pg_temp.as_('df_pro2');
PERFORM pg_temp.put('s2', pg_temp.ok('DF2 un autre pro peut poster aux mêmes jours (pas de conflit entre pros)', pg_temp.df_new('off_2', 20, 'am', 20, 'pm', 6)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_bk('bk_acc25', 'off_a', 'df_cH', 25, 'am', 2, 'accepted');
PERFORM pg_temp.df_bk('bk_multi27', 'off_m', 'df_cH', 27, 'am', 1, 'accepted', NULL, 29);
INSERT INTO private.pro_busy_slots (pro_id, day, period) VALUES (pg_temp.id('df_pro'), pg_temp.dd(31), 'pm');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF2 résa sur demande acceptée sur la plage → conflit', pg_temp.df_new('off_a', 24, 'am', 25, 'am', 6), 'junto.session_conflict');
PERFORM pg_temp.denied('DF2 résa acceptée sur plusieurs jours : son dernier jour → conflit', pg_temp.df_new('off_a', 29, 'pm', 29, 'pm', 6), 'junto.session_conflict');
PERFORM pg_temp.denied('DF2 créneau occupé dans l''agenda importé → conflit', pg_temp.df_new('off_a', 31, 'am', 31, 'pm', 6), 'junto.session_conflict');
PERFORM pg_temp.put('sC', pg_temp.ok('DF2 date J+33 (annulée ensuite)', pg_temp.df_new('off_a', 33, 'am', 33, 'am', 6)));
PERFORM pg_temp.ok('DF2 annulation de cette date', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('sC')));
PERFORM pg_temp.put('sC2', pg_temp.ok('DF2 une date annulée ne bloque plus la demi-journée', pg_temp.df_new('off_a', 33, 'am', 33, 'am', 6)));
-- Demandes en attente sur la plage → déclinées + notifiées (option A).
PERFORM pg_temp.as_('df_cP1');
PERFORM pg_temp.put('bk_p1_35', pg_temp.ok('DF2 demande sur 3 jours J+35 → J+37 (client P1)', pg_temp.df_req('off_m', 35, 'am', 1)));
PERFORM pg_temp.as_('df_cP2');
PERFORM pg_temp.put('bk_p2_37', pg_temp.ok('DF2 demande sur 3 jours J+37 → J+39 (client P2)', pg_temp.df_req('off_m', 37, 'am', 1)));
PERFORM pg_temp.as_('df_cP3');
PERFORM pg_temp.put('bk_p3_40', pg_temp.ok('DF2 demande hors plage J+40 (client P3)', pg_temp.df_req('off_a', 40, 'am', 1)));
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.eq('DF2 get_session_conflicts annonce les 2 demandes de la plage',
  format($$SELECT count(*)::text FROM public.get_session_conflicts(%L, 'am', %L, 'am')$$, pg_temp.dd(35), pg_temp.dd(37)), '2');
PERFORM pg_temp.put('sD', pg_temp.ok('DF2 date J+35 → J+37 matin sur l''offre M', pg_temp.df_new('off_m', 35, 'am', 37, 'am', 6)));
PERFORM pg_temp.eq('DF2 la demande de la plage est déclinée', $$SELECT pg_temp.df_bst('bk_p1_35')$$, 'declined');
PERFORM pg_temp.eq('DF2 la demande sur plusieurs jours qui chevauche la fin est déclinée', $$SELECT pg_temp.df_bst('bk_p2_37')$$, 'declined');
PERFORM pg_temp.eq('DF2 la demande hors plage reste en attente', $$SELECT pg_temp.df_bst('bk_p3_40')$$, 'pending');
PERFORM pg_temp.eq('DF2 le client décliné est notifié (booking_declined)', $$SELECT pg_temp.df_n('df_cP1', 'booking_declined', 'bk_p1_35')$$, '1');
PERFORM pg_temp.eq('DF2 le client hors plage n''est pas notifié', $$SELECT pg_temp.df_n('df_cP3', 'booking_declined')$$, '0');
-- Limite de fréquence (30 / jour) : remplie artificiellement.
PERFORM pg_temp.as_('db');
INSERT INTO public.rate_events (user_id, kind) SELECT pg_temp.id('df_pro'), 'pro_session_create' FROM generate_series(1, 30);
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF2 limite de 30 créations par jour', pg_temp.df_new('off_a', 130, 'am', 130, 'am', 6), 'junto.too_many_actions');
PERFORM pg_temp.as_('db');
DELETE FROM public.rate_events WHERE user_id = pg_temp.id('df_pro') AND kind = 'pro_session_create';
-- Plafond de 100 dates à venir (pro3).
PERFORM pg_temp.df_ss('s3_' || i, 'off_3', 10 + i, 'am', 10 + i, 'am', 6) FROM generate_series(1, 100) i;
PERFORM pg_temp.df_ss('s3_past', 'off_3', -5, 'am', -5, 'am', 6);
PERFORM pg_temp.as_('df_pro3');
PERFORM pg_temp.denied('DF2 plafond de 100 dates à venir', pg_temp.df_new('off_3', 150, 'am', 150, 'am', 6), 'junto.session_cap');
PERFORM pg_temp.as_('db');
UPDATE public.pro_sessions SET status = 'cancelled' WHERE id = pg_temp.id('s3_1');
PERFORM pg_temp.as_('df_pro3');
PERFORM pg_temp.ok('DF2 une date annulée libère une place sous le plafond (une date passée ne compte pas)', pg_temp.df_new('off_3', 150, 'am', 150, 'am', 6));
PERFORM pg_temp.as_('df_pro');
-- Pro suspendu : voir DF12.

-- ═════ DF3 — Accès directs : table pro_sessions, confirmations, colonnes figées ═════
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF3 un membre ne lit pas pro_sessions', $$SELECT count(*)::text FROM public.pro_sessions$$, 'permission denied');
PERFORM pg_temp.denied('DF3 un membre n''insère pas de date',
  format($$INSERT INTO public.pro_sessions (pro_id, offering_id, start_day, start_period, end_day, end_period, max_participants) VALUES (%L, %L, %L, 'am', %L, 'am', 5)$$,
    pg_temp.id('df_pro'), pg_temp.id('off_a'), pg_temp.dd(70), pg_temp.dd(70)), 'permission denied');
PERFORM pg_temp.denied('DF3 un membre ne lit pas les confirmations', $$SELECT count(*)::text FROM private.outing_confirmations$$, 'permission denied');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF3 le pro ne lit pas sa table directement', $$SELECT count(*)::text FROM public.pro_sessions$$, 'permission denied');
PERFORM pg_temp.denied('DF3 le pro ne modifie pas sa date directement',
  format($$UPDATE public.pro_sessions SET max_participants = 50 WHERE id = %L$$, pg_temp.id('sA')), 'permission denied');
PERFORM pg_temp.denied('DF3 le pro ne supprime pas sa date directement',
  format($$DELETE FROM public.pro_sessions WHERE id = %L$$, pg_temp.id('sA')), 'permission denied');
PERFORM pg_temp.denied('DF3 le pro n''insère pas de date directement',
  format($$INSERT INTO public.pro_sessions (pro_id, offering_id, start_day, start_period, end_day, end_period, max_participants) VALUES (%L, %L, %L, 'am', %L, 'am', 5)$$,
    pg_temp.id('df_pro'), pg_temp.id('off_a'), pg_temp.dd(70), pg_temp.dd(70)), 'permission denied');
PERFORM pg_temp.denied('DF3 le pro ne lit pas les confirmations', $$SELECT count(*)::text FROM private.outing_confirmations$$, 'permission denied');
PERFORM pg_temp.denied('DF3 le pro n''écrit pas de confirmation',
  format($$INSERT INTO private.outing_confirmations (pro_id, offering_id, day, period, reason) VALUES (%L, %L, %L, 'am', 'pro')$$,
    pg_temp.id('df_pro'), pg_temp.id('off_a'), pg_temp.dd(70)), 'permission denied');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('DF3 anon ne lit pas pro_sessions', $$SELECT count(*)::text FROM public.pro_sessions$$, 'permission denied');
PERFORM pg_temp.denied('DF3 anon ne lit pas les confirmations', $$SELECT count(*)::text FROM private.outing_confirmations$$, 'permission denied');
PERFORM pg_temp.denied('DF3 anon ne lit pas les dates d''une offre', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('off_a')));
PERFORM pg_temp.denied('DF3 anon ne s''inscrit pas', pg_temp.df_join('sA', 1));
PERFORM pg_temp.denied('DF3 anon ne lit pas get_my_sessions', format($$SELECT count(*)::text FROM public.get_my_sessions(%L, %L)$$, pg_temp.dd(0), pg_temp.dd(30)));
PERFORM pg_temp.denied('DF3 anon ne modifie pas de date', pg_temp.df_upd('sA', 20, 'am', 20, 'pm', 6));
PERFORM pg_temp.denied('DF3 anon n''annule pas de date', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('sA')));
PERFORM pg_temp.denied('DF3 anon ne maintient pas de sortie', pg_temp.df_confirm('off_a', 20, 'am'));

-- ═════ DF4 — join_pro_session ═════
-- Refus d'accès.
PERFORM pg_temp.as_('df_sus');
PERFORM pg_temp.denied('DF4 un suspendu ne s''inscrit pas', pg_temp.df_join('sA', 1), 'Operation not permitted');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF4 le pro ne s''inscrit pas à sa propre date', pg_temp.df_join('sA', 1), 'Operation not permitted');
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF4 date inexistante refusée', format($$SELECT public.join_pro_session(%L, 1)::text$$, gen_random_uuid()), 'Operation not permitted');
PERFORM pg_temp.denied('DF4 rideau démo : date d''un pro démo refusée à un membre', pg_temp.df_join('s_demo', 1), 'Operation not permitted');
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('df_blk1'), pg_temp.id('df_pro'));
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('df_pro'), pg_temp.id('df_blk2'));
PERFORM pg_temp.as_('df_blk1');
PERFORM pg_temp.denied('DF4 le client qui a bloqué le pro ne s''inscrit pas', pg_temp.df_join('sA', 1), 'Operation not permitted');
PERFORM pg_temp.as_('df_blk2');
PERFORM pg_temp.denied('DF4 le client bloqué par le pro ne s''inscrit pas', pg_temp.df_join('sA', 1), 'Operation not permitted');
-- Dates fermées.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_ss('sX', 'off_a', -1, 'am', 1, 'pm', 6);          -- en cours (hier → demain)
PERFORM pg_temp.df_ss('sY', 'off_a', -3, 'am', -2, 'pm', 6);         -- finie
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF4 date annulée refusée', pg_temp.df_join('sC', 1), 'junto.session_closed');
PERFORM pg_temp.denied('DF4 date commencée refusée', pg_temp.df_join('sX', 1), 'junto.session_closed');
-- Taille du groupe, message.
PERFORM pg_temp.denied('DF4 groupe de 0 refusé', pg_temp.df_join('sB', 0), 'junto.booking_party_size');
PERFORM pg_temp.denied('DF4 groupe au-delà des places refusé', pg_temp.df_join('sB', 5), 'junto.booking_party_size');
PERFORM pg_temp.denied('DF4 groupe manquant refusé', pg_temp.df_join('sB', NULL), 'junto.booking_party_size');
PERFORM pg_temp.denied('DF4 message de 501 caractères refusé', pg_temp.df_join('sA', 1, repeat('m', 501)), 'junto.booking_message');
-- Plafond quotidien : 10 résas créées dans les 24 h.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_bk(NULL, 'off_b', 'df_cCap', 70 + i, 'am', 1, 'cancelled', NULL, NULL, true) FROM generate_series(1, 10) i;
PERFORM pg_temp.as_('df_cCap');
PERFORM pg_temp.denied('DF4 plafond de 10 résas par 24 h', pg_temp.df_join('sA', 1), 'junto.booking_daily_cap');
-- Inscription nominale (B, avec message).
PERFORM pg_temp.as_('df_cB');
PERFORM pg_temp.put('bk_B_sA', pg_temp.ok('DF4 le client B s''inscrit à 2 avec un message', pg_temp.df_join('sA', 2, '<b>Salut</b> Secret42')));
PERFORM pg_temp.denied('DF4 déjà inscrit : refusé', pg_temp.df_join('sA', 1), 'junto.booking_already');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF4 inscription = résa acceptée de la date, départ de la date, prix figé',
  format($$SELECT status || '/' || (session_id = %L)::text || '/' || (day = %L)::text || '/' || period || '/' || coalesce(end_day::text, 'NULL') || '/' || price_eur::int
    FROM public.bookings WHERE id = %L$$, pg_temp.id('sA'), pg_temp.dd(20), pg_temp.id('bk_B_sA')), 'accepted/true/true/am/NULL/50');
PERFORM pg_temp.eq('DF4 le message est nettoyé du HTML', format($$SELECT message FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_B_sA')), 'Salut Secret42');
PERFORM pg_temp.eq('DF4 DM logistique ouvert avec un message « inscription » du pro',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L AND sender_id = %L
    AND metadata->>'type' = 'booking_accepted' AND metadata->>'booking_id' = %L$$, pg_temp.df_dm('df_pro', 'df_cB'), pg_temp.id('df_pro'), pg_temp.get('bk_B_sA')), '1');
PERFORM pg_temp.eq('DF4 le DM est actif et marqué « booking »',
  format($$SELECT status || '/' || initiated_from FROM public.conversations WHERE id = %L$$, pg_temp.df_dm('df_pro', 'df_cB')), 'active/booking');
PERFORM pg_temp.eq('DF4 le pro reçoit session_joined', $$SELECT pg_temp.df_n('df_pro', 'session_joined', 'bk_B_sA')$$, '1');
PERFORM pg_temp.eq('DF4 le message du client n''est jamais dans la notification',
  $$SELECT count(*)::text FROM public.notifications WHERE user_id = pg_temp.id('df_pro') AND type = 'session_joined'
    AND (body LIKE '%Secret42%' OR data::text LIKE '%Secret42%')$$, '0');
-- Complet (sB : 4 places).
PERFORM pg_temp.as_('df_cC');
PERFORM pg_temp.put('bk_C_sB', pg_temp.ok('DF4 C prend 3 places sur 4', pg_temp.df_join('sB', 3)));
PERFORM pg_temp.as_('df_cD');
PERFORM pg_temp.denied('DF4 D à 2 : complet', pg_temp.df_join('sB', 2), 'junto.booking_full');
PERFORM pg_temp.put('bk_D_sB', pg_temp.ok('DF4 D à 1 : dernière place', pg_temp.df_join('sB', 1)));
-- Annulation puis réinscription : cooldown 1 h, plafond 5 soumissions.
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.put('bk_A_sA', pg_temp.ok('DF4 A s''inscrit', pg_temp.df_join('sA', 1)));
PERFORM pg_temp.ok('DF4 A annule', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk_A_sA')));
PERFORM pg_temp.denied('DF4 réinscription immédiate : cooldown', pg_temp.df_join('sA', 1), 'junto.booking_cooldown');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.bookings SET last_submitted_at = now() - INTERVAL '2 hours' WHERE id = pg_temp.id('bk_A_sA');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.eq('DF4 après le cooldown, la même ligne est réactivée', pg_temp.df_join('sA', 1), pg_temp.get('bk_A_sA'));
PERFORM pg_temp.eq('DF4 réactivation : acceptée, 2 soumissions', format($$SELECT pg_temp.df_bst('bk_A_sA') || '/' || (SELECT submitted_count FROM public.bookings WHERE id = %L)$$, pg_temp.id('bk_A_sA')), 'accepted/2');
PERFORM pg_temp.ok('DF4 A annule de nouveau', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk_A_sA')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.bookings SET last_submitted_at = now() - INTERVAL '2 hours', submitted_count = 5 WHERE id = pg_temp.id('bk_A_sA');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF4 5 soumissions atteintes : refusé', pg_temp.df_join('sA', 1), 'junto.booking_cooldown');
-- Une demande déclinée par la date (même offre, même départ) est la ligne réactivée.
-- 00578 (T-COOLDOWN) : une ligne fermée par le PRO (déclinée, annulée par le pro, expirée) n'est pas une
-- resoumission du client : pas de délai d'1 h, et elle ne compte pas dans le plafond de 5 soumissions.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('p1_cnt', (SELECT submitted_count::text FROM public.bookings WHERE id = pg_temp.id('bk_p1_35')));
PERFORM pg_temp.eq('DF4 (fixture) la demande déclinée date de moins d''1 h',
  $$SELECT (last_submitted_at > now() - INTERVAL '1 hour')::text FROM public.bookings WHERE id = pg_temp.id('bk_p1_35')$$, 'true');
PERFORM pg_temp.as_('df_cP1');
PERFORM pg_temp.eq('DF4 demande déclinée par le pro il y a moins d''1 h : pas de délai, l''ancienne demande devient l''inscription',
  pg_temp.df_join('sD', 1), pg_temp.get('bk_p1_35'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF4 réactivation d''une ligne déclinée : pas comptée comme soumission',
  $$SELECT submitted_count::text FROM public.bookings WHERE id = pg_temp.id('bk_p1_35')$$, pg_temp.get('p1_cnt'));
PERFORM pg_temp.as_('df_cP1');
PERFORM pg_temp.denied('DF4 déjà inscrit : refusé', pg_temp.df_join('sD', 1), 'junto.booking_already');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF4 réactivée : rattachée à la date, plage « sur demande » effacée',
  format($$SELECT status || '/' || (session_id = %L)::text || '/' || coalesce(end_day::text, 'NULL') FROM public.bookings WHERE id = %L$$, pg_temp.id('sD'), pg_temp.id('bk_p1_35')), 'accepted/true/NULL');
-- SESSIONS-4 : partage des places.
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.put('sQ', pg_temp.ok('DF4 date de 10 places', pg_temp.df_new('off_b', 60, 'am', 60, 'am', 10)));
PERFORM pg_temp.put('sR1', pg_temp.ok('DF4 date R1', pg_temp.df_new('off_b', 61, 'am', 61, 'am', 2)));
PERFORM pg_temp.put('sR2', pg_temp.ok('DF4 date R2', pg_temp.df_new('off_b', 61, 'pm', 61, 'pm', 2)));
PERFORM pg_temp.put('sR3', pg_temp.ok('DF4 date R3', pg_temp.df_new('off_b', 62, 'am', 62, 'am', 2)));
PERFORM pg_temp.put('sR4', pg_temp.ok('DF4 date R4', pg_temp.df_new('off_b', 62, 'pm', 62, 'pm', 2)));
PERFORM pg_temp.as_('df_cQ');
PERFORM pg_temp.denied('DF4 un groupe de 7 sur une date de 10 est refusé (00580 CLIENT-4 : message propre)', pg_temp.df_join('sQ', 7), 'junto.session_group_cap');
PERFORM pg_temp.ok('DF4 un groupe de 6 sur une date de 10 passe', pg_temp.df_join('sQ', 6));
PERFORM pg_temp.as_('df_cS');
PERFORM pg_temp.ok('DF4 inscription active n°1 chez ce pro', pg_temp.df_join('sR1', 1));
PERFORM pg_temp.ok('DF4 inscription active n°2 chez ce pro', pg_temp.df_join('sR2', 1));
PERFORM pg_temp.ok('DF4 inscription active n°3 chez ce pro', pg_temp.df_join('sR3', 1));
PERFORM pg_temp.denied('DF4 une 4e inscription active à venir chez le même pro est refusée', pg_temp.df_join('sR4', 1), 'junto.session_signup_cap');

-- ═════ DF5 — get_offering_sessions ═════
PERFORM pg_temp.as_('df_cB');
PERFORM pg_temp.eq('DF5 un membre voit la date, ses places prises et sa propre inscription',
  format($$SELECT taken || '/' || (my_booking_id = %L)::text || '/' || meeting_point FROM public.get_offering_sessions(%L) WHERE id = %L$$,
    pg_temp.id('bk_B_sA'), pg_temp.id('off_a'), pg_temp.id('sA')), '2/true/Parking du  col');
PERFORM pg_temp.eq('DF5 une date commencée n''est plus listée',
  format($$SELECT count(*)::text FROM public.get_offering_sessions(%L) WHERE id = %L$$, pg_temp.id('off_a'), pg_temp.id('sX')), '0');
PERFORM pg_temp.eq('DF5 une date annulée n''est pas listée',
  format($$SELECT count(*)::text FROM public.get_offering_sessions(%L) WHERE id = %L$$, pg_temp.id('off_a'), pg_temp.id('sC')), '0');
PERFORM pg_temp.as_('df_cC');
PERFORM pg_temp.eq('DF5 my_booking_id = seulement l''inscription de l''appelant',
  format($$SELECT coalesce(my_booking_id::text, 'NULL') FROM public.get_offering_sessions(%L) WHERE id = %L$$, pg_temp.id('off_a'), pg_temp.id('sA')), 'NULL');
PERFORM pg_temp.eq('DF5 les places prises comptent toutes les inscriptions acceptées (agrégat)',
  format($$SELECT taken::text FROM public.get_offering_sessions(%L) WHERE id = %L$$, pg_temp.id('off_a'), pg_temp.id('sB')), '4');
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.eq('DF5 une inscription annulée n''est pas « la mienne »',
  format($$SELECT coalesce(my_booking_id::text, 'NULL') FROM public.get_offering_sessions(%L) WHERE id = %L$$, pg_temp.id('off_a'), pg_temp.id('sA')), 'NULL');
PERFORM pg_temp.eq('DF5 au plus 30 dates', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('off_3')), '30');
PERFORM pg_temp.eq('DF5 rideau démo : rien pour un membre', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('off_demo')), '0');
PERFORM pg_temp.as_('df_adm');
PERFORM pg_temp.eq('DF5 rideau démo : l''admin en mode démo voit la date', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('off_demo')), '1');
PERFORM pg_temp.as_('df_sus');
PERFORM pg_temp.eq('DF5 un suspendu ne voit rien', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('off_a')), '0');
PERFORM pg_temp.as_('df_blk1');
PERFORM pg_temp.eq('DF5 le client qui a bloqué le pro ne voit rien', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('off_a')), '0');
PERFORM pg_temp.as_('df_blk2');
PERFORM pg_temp.eq('DF5 le client bloqué par le pro ne voit rien', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('off_a')), '0');
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.eq('DF5 offre inexistante : rien', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, gen_random_uuid()), '0');

-- ═════ DF6 — get_my_sessions ═════
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.eq('DF6 le pro voit sa date, ses places prises (acceptées seulement), non confirmée (pas de minimum)',
  format($$SELECT taken || '/' || confirmed FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('sA')), '2/false');
PERFORM pg_temp.eq('DF6 une date en cours est listée', format($$SELECT count(*)::text FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('sX')), '1');
PERFORM pg_temp.eq('DF6 une date annulée n''est pas listée', format($$SELECT count(*)::text FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('sC')), '0');
PERFORM pg_temp.eq('DF6 les dates d''un autre pro ne sont pas listées', format($$SELECT count(*)::text FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('s2')), '0');
PERFORM pg_temp.denied('DF6 fenêtre de plus de 13 mois refusée', format($$SELECT count(*)::text FROM public.get_my_sessions(%L, %L)$$, pg_temp.dd(0), pg_temp.dd(420)), 'Operation not permitted');
PERFORM pg_temp.denied('DF6 fenêtre inversée refusée', format($$SELECT count(*)::text FROM public.get_my_sessions(%L, %L)$$, pg_temp.dd(10), pg_temp.dd(0)), 'Operation not permitted');
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF6 un membre non pro refusé', format($$SELECT count(*)::text FROM public.get_my_sessions(%L, %L)$$, pg_temp.dd(0), pg_temp.dd(60)), 'Operation not permitted');

-- ═════ DF7 — update_pro_session ═════
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.put('sE', pg_temp.ok('DF7 date sans inscrit J+56', pg_temp.df_new('off_b', 56, 'am', 56, 'am', 6)));
PERFORM pg_temp.as_('df_cP3');
PERFORM pg_temp.put('bk_p3_57', pg_temp.ok('DF7 demande en attente J+57 après-midi', pg_temp.df_req('off_a', 57, 'pm', 1)));
PERFORM pg_temp.as_('df_pro2');
PERFORM pg_temp.denied('DF7 un autre pro ne modifie pas la date', pg_temp.df_upd('sE', 57, 'am', 57, 'pm', 6), 'Operation not permitted');
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF7 un membre ne modifie pas la date', pg_temp.df_upd('sE', 57, 'am', 57, 'pm', 6), 'Operation not permitted');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF7 date annulée : refusé', pg_temp.df_upd('sC', 33, 'am', 33, 'am', 6), 'Operation not permitted');
PERFORM pg_temp.denied('DF7 date commencée : refusé', pg_temp.df_upd('sX', -1, 'am', 1, 'pm', 8), 'junto.session_closed');
PERFORM pg_temp.denied('DF7 mêmes contrôles qu''à la création : dates', pg_temp.df_upd('sE', 57, 'pm', 57, 'am', 6), 'junto.session_dates');
PERFORM pg_temp.denied('DF7 mêmes contrôles : places', pg_temp.df_upd('sE', 56, 'am', 56, 'am', 6, 7), 'junto.session_places');
PERFORM pg_temp.denied('DF7 mêmes contrôles : RDV', pg_temp.df_upd('sE', 56, 'am', 56, 'am', 6, NULL, repeat('a', 121)), 'junto.session_meeting');
PERFORM pg_temp.denied('DF7 déplacement sur une autre date : conflit', pg_temp.df_upd('sE', 20, 'pm', 20, 'pm', 6), 'junto.session_conflict');
PERFORM pg_temp.ok('DF7 déplacement sans inscrit permis (la date ne se gêne pas elle-même)', pg_temp.df_upd('sE', 56, 'am', 57, 'pm', 6));
PERFORM pg_temp.eq('DF7 la demande en attente de la nouvelle plage est déclinée', $$SELECT pg_temp.df_bst('bk_p3_57')$$, 'declined');
PERFORM pg_temp.eq('DF7 et notifiée', $$SELECT pg_temp.df_n('df_cP3', 'booking_declined', 'bk_p3_57')$$, '1');
PERFORM pg_temp.eq('DF7 la date a bougé', format($$SELECT end_day::text || '/' || end_period FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('sE')), pg_temp.dd(57)::text || '/pm');
PERFORM pg_temp.denied('DF7 avec des inscrits, les jours ne bougent plus', pg_temp.df_upd('sA', 22, 'am', 22, 'pm', 6), 'junto.session_has_clients');
PERFORM pg_temp.denied('DF7 places sous le nombre d''inscrits refusé', pg_temp.df_upd('sA', 20, 'am', 20, 'pm', 1), 'junto.session_places');
PERFORM pg_temp.ok('DF7 avec des inscrits, places et RDV restent modifiables', pg_temp.df_upd('sA', 20, 'am', 20, 'pm', 5, NULL, 'Parking du col'));
PERFORM pg_temp.eq('DF7 modifications enregistrées', format($$SELECT max_participants || '/' || meeting_point FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('sA')), '5/Parking du col');

-- ═════ DF8 — Effets sur le « sur demande » ═════
PERFORM pg_temp.as_('df_cE');
PERFORM pg_temp.denied('DF8 create_booking sur le départ d''une date refusé', pg_temp.df_req('off_a', 20, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('DF8 create_booking sur une autre demi-journée de la date refusé (autre offre)', pg_temp.df_req('off_b', 20, 'pm', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('DF8 demande sur plusieurs jours qui traverse une date refusée', pg_temp.df_req('off_m', 18, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('DF8 offre sur plusieurs jours : départ l''après-midi refusé', pg_temp.df_req('off_m', 8, 'pm', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.eq('DF8 get_pro_availability masque les demi-journées d''une date',
  format($$SELECT count(*)::text FROM public.get_pro_availability(%L) WHERE day = %L$$, pg_temp.id('df_pro'), pg_temp.dd(20)), '0');
PERFORM pg_temp.eq('DF8 get_pro_availability garde la veille', format($$SELECT count(*)::text FROM public.get_pro_availability(%L) WHERE day = %L$$, pg_temp.id('df_pro'), pg_temp.dd(19)), '2');
PERFORM pg_temp.eq('DF8 get_pro_availability : une résa sur plusieurs jours compte sur toute sa plage',
  format($$SELECT taken::text FROM public.get_pro_availability(%L) WHERE day = %L AND period = 'pm'$$, pg_temp.id('df_pro'), pg_temp.dd(28)), '1');
-- accept_booking : une demande en attente glissée dans une date (insérée directement).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_bk('bk_inside', 'off_b', 'df_cE', 20, 'pm', 1, 'pending');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF8 accept_booking dans une date refusé', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk_inside')), 'junto.booking_slot_unavailable');
-- create_manual_booking.
PERFORM pg_temp.put('bk_man_sA', pg_temp.ok('DF8 résa manuelle au départ de la date, même offre', pg_temp.df_manual('off_a', 20, 'am', 1)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF8 elle est rattachée à la date, sans plage propre',
  format($$SELECT (session_id = %L)::text || '/' || coalesce(end_day::text, 'NULL') || '/' || status FROM public.bookings WHERE id = %L$$, pg_temp.id('sA'), pg_temp.id('bk_man_sA')), 'true/NULL/accepted');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.eq('DF8 les places prises comptent la résa manuelle', format($$SELECT taken::text FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('sA')), '3');
PERFORM pg_temp.denied('DF8 manuelle au-delà des places restantes : complet', pg_temp.df_manual('off_a', 20, 'am', 3), 'junto.booking_full');
PERFORM pg_temp.denied('DF8 manuelle sur une autre demi-journée de la date refusée', pg_temp.df_manual('off_a', 20, 'pm', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('DF8 manuelle au départ mais sur une autre offre refusée', pg_temp.df_manual('off_b', 20, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('DF8 manuelle sur plusieurs jours qui traverse une date refusée', pg_temp.df_manual('off_m', 18, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('DF8 manuelle sur une date commencée refusée', pg_temp.df_manual('off_a', 0, 'pm', 1), 'junto.booking_slot_unavailable');
-- SESSIONS-5 (course) : en séquentiel, une date annulée avant l'appel n'est jamais rattachée.
PERFORM pg_temp.put('sJ', pg_temp.ok('DF8 date J+50', pg_temp.df_new('off_a', 50, 'am', 50, 'am', 6)));
PERFORM pg_temp.as_('db');
UPDATE public.pro_sessions SET status = 'cancelled' WHERE id = pg_temp.id('sJ');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.put('bk_man_sJ', pg_temp.ok('DF8 manuelle au départ d''une date annulée : acceptée comme résa simple', pg_temp.df_manual('off_a', 50, 'am', 1)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF8 elle n''est pas rattachée à la date annulée', format($$SELECT coalesce(session_id::text, 'NULL') FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_man_sJ')), 'NULL');
-- cancel_outing sur la demi-journée de départ annule la date.
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.put('sF', pg_temp.ok('DF8 date J+45 journée', pg_temp.df_new('off_a', 45, 'am', 45, 'pm', 6)));
PERFORM pg_temp.put('sG', pg_temp.ok('DF8 date J+46 journée', pg_temp.df_new('off_a', 46, 'am', 46, 'pm', 6)));
PERFORM pg_temp.as_('df_cE');
PERFORM pg_temp.put('bk_E_sF', pg_temp.ok('DF8 E s''inscrit à J+45', pg_temp.df_join('sF', 1)));
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.eq('DF8 cancel_outing au départ : une résa annulée', format($$SELECT public.cancel_outing(%L, %L, 'am')::text$$, pg_temp.id('off_a'), pg_temp.dd(45)), '1');
PERFORM pg_temp.eq('DF8 la date est annulée', $$SELECT pg_temp.df_sst('sF')$$, 'cancelled');
PERFORM pg_temp.eq('DF8 l''inscription est annulée par le pro', $$SELECT pg_temp.df_bst('bk_E_sF')$$, 'cancelled_pro');
PERFORM pg_temp.ok('DF8 cancel_outing sur l''après-midi d''une date (pas son départ)', format($$SELECT public.cancel_outing(%L, %L, 'pm')::text$$, pg_temp.id('off_a'), pg_temp.dd(46)));
PERFORM pg_temp.eq('DF8 la date reste programmée', $$SELECT pg_temp.df_sst('sG')$$, 'scheduled');

-- ═════ DF9 — cancel_pro_session ═════
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.put('sH', pg_temp.ok('DF9 date J+47', pg_temp.df_new('off_a', 47, 'am', 47, 'am', 5)));
PERFORM pg_temp.put('sI', pg_temp.ok('DF9 date J+48', pg_temp.df_new('off_a', 48, 'am', 48, 'am', 5)));
PERFORM pg_temp.put('sJ2', pg_temp.ok('DF9 date J+49', pg_temp.df_new('off_a', 49, 'am', 49, 'am', 5)));
PERFORM pg_temp.as_('df_cF');
PERFORM pg_temp.put('bk_F_sH', pg_temp.ok('DF9 F s''inscrit', pg_temp.df_join('sH', 1)));
PERFORM pg_temp.as_('df_cG');
PERFORM pg_temp.put('bk_G_sH', pg_temp.ok('DF9 G s''inscrit', pg_temp.df_join('sH', 1)));
PERFORM pg_temp.as_('df_cH');
PERFORM pg_temp.put('bk_H_sI', pg_temp.ok('DF9 H s''inscrit', pg_temp.df_join('sI', 1)));
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('df_pro'), pg_temp.id('df_cG'));
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF9 un membre n''annule pas la date', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('sH')), 'Operation not permitted');
PERFORM pg_temp.as_('df_pro2');
PERFORM pg_temp.denied('DF9 un autre pro n''annule pas la date', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('sH')), 'Operation not permitted');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF9 motif de 301 caractères refusé', format($$SELECT public.cancel_pro_session(%L, %L)::text$$, pg_temp.id('sJ2'), repeat('r', 301)), 'junto.outing_reason');
PERFORM pg_temp.denied('DF9 date finie refusée', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('sY')), 'junto.booking_date');
PERFORM pg_temp.eq('DF9 annulation avec motif : 2 inscriptions annulées', format($$SELECT public.cancel_pro_session(%L, '<i>Météo</i> pourrie')::text$$, pg_temp.id('sH')), '2');
PERFORM pg_temp.denied('DF9 date déjà annulée refusée', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('sH')), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF9 la date est annulée', $$SELECT pg_temp.df_sst('sH')$$, 'cancelled');
PERFORM pg_temp.eq('DF9 les inscriptions passent en cancelled_pro', $$SELECT pg_temp.df_bst('bk_F_sH') || '/' || pg_temp.df_bst('bk_G_sH')$$, 'cancelled_pro/cancelled_pro');
PERFORM pg_temp.eq('DF9 le motif (nettoyé) est dans le DM du client',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L AND sender_id = %L AND content = 'Météo pourrie'$$,
    pg_temp.df_dm('df_pro', 'df_cF'), pg_temp.id('df_pro')), '1');
PERFORM pg_temp.eq('DF9 notification by_pro_message, sans le motif',
  $$SELECT string_agg(data->>'variant', ',') || '/' || bool_and(body NOT LIKE '%Météo%' AND data::text NOT LIKE '%Météo%')::text
    FROM public.notifications WHERE user_id = pg_temp.id('df_cF') AND type = 'booking_cancelled' AND data->>'booking_id' = pg_temp.get('bk_F_sH')$$, 'by_pro_message/true');
PERFORM pg_temp.eq('DF9 client bloqué : pas de motif en DM',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L AND content = 'Météo pourrie'$$, pg_temp.df_dm('df_pro', 'df_cG')), '0');
-- 00580 (BOOKINGS-R4) : bloqués → avis neutre, sans variante ni nom du pro.
PERFORM pg_temp.eq('DF9 client bloqué : notification neutre quand même (sans variante, sans nom)',
  $$SELECT string_agg(coalesce(data->>'variant', 'NULL') || '/' || coalesce(data->'params'->>'name', 'NULL'), ',') FROM public.notifications WHERE user_id = pg_temp.id('df_cG') AND type = 'booking_cancelled' AND data->>'booking_id' = pg_temp.get('bk_G_sH')$$, 'NULL/NULL');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.eq('DF9 annulation sans motif', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('sI')), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF9 sans motif : notification by_pro, aucun message ajouté au DM',
  format($$SELECT (SELECT string_agg(data->>'variant', ',') FROM public.notifications WHERE user_id = pg_temp.id('df_cH') AND type = 'booking_cancelled' AND data->>'booking_id' = pg_temp.get('bk_H_sI'))
    || '/' || (SELECT count(*) FROM public.messages WHERE conversation_id = %L AND metadata IS NULL)$$, pg_temp.df_dm('df_pro', 'df_cH')), 'by_pro/0');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.ok('DF9 une date en cours peut encore être annulée', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('sX')));
-- Pro révoqué (tier retiré) : il perd la création, garde l'annulation ; ses dates disparaissent pour les autres.
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET tier = 'free' WHERE id = pg_temp.id('df_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.eq('DF9 pro révoqué : ses dates ne sont plus listées', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('off_2')), '0');
PERFORM pg_temp.denied('DF9 pro révoqué : on ne s''inscrit plus à ses dates', pg_temp.df_join('s2', 1), 'Operation not permitted');
PERFORM pg_temp.as_('df_pro2');
PERFORM pg_temp.eq('DF9 pro révoqué : il voit encore ses propres dates', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('off_2')), '1');
PERFORM pg_temp.denied('DF9 pro révoqué : création refusée', pg_temp.df_new('off_2', 30, 'am', 30, 'am', 6), 'Operation not permitted');
PERFORM pg_temp.denied('DF9 pro révoqué : modification refusée', pg_temp.df_upd('s2', 20, 'am', 20, 'pm', 5), 'Operation not permitted');
PERFORM pg_temp.denied('DF9 pro révoqué : get_my_sessions refusé', format($$SELECT count(*)::text FROM public.get_my_sessions(%L, %L)$$, pg_temp.dd(0), pg_temp.dd(60)), 'Operation not permitted');
PERFORM pg_temp.ok('DF9 pro révoqué : il peut annuler sa date', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('s2')));

-- ═════ DF10 — Minimum : « Départ confirmé », confirm_outing, lectures ═════
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.put('o5d', pg_temp.ok('DF10 offre pour les dates (pas de minimum)', pg_temp.df_off_sql('Dates 5', 8, NULL)));
PERFORM pg_temp.put('o5min', pg_temp.ok('DF10 offre sur demande minimum 2', pg_temp.df_off_sql('Min 2', 8, 2)));
PERFORM pg_temp.put('o5min3', pg_temp.ok('DF10 offre sur demande minimum 3', pg_temp.df_off_sql('Min 3', 8, 3)));
PERFORM pg_temp.put('o5nomin', pg_temp.ok('DF10 offre sur demande sans minimum', pg_temp.df_off_sql('Sans min', 8, NULL)));
PERFORM pg_temp.ok('DF10 pro5 ouvre ses créneaux J+1..J+30', pg_temp.df_open_sql(1, 30));
-- Date : minimum 3 atteint par les inscriptions.
PERFORM pg_temp.put('sM', pg_temp.ok('DF10 date J+15, 6 places, minimum 3', pg_temp.df_new('o5d', 15, 'am', 15, 'am', 6, 3)));
PERFORM pg_temp.as_('df_m1');
PERFORM pg_temp.put('bk_m1_sM', pg_temp.ok('DF10 m1 s''inscrit à 2', pg_temp.df_join('sM', 2)));
PERFORM pg_temp.eq('DF10 sous le minimum : pas confirmée', $$SELECT pg_temp.df_conf('o5d', 15, 'am', 'sM')$$, 'false');
PERFORM pg_temp.eq('DF10 sous le minimum : pas de « Départ confirmé »', $$SELECT pg_temp.df_n('df_m1', 'booking_confirmed')$$, '0');
PERFORM pg_temp.as_('df_m2');
PERFORM pg_temp.put('bk_m2_sM', pg_temp.ok('DF10 m2 s''inscrit à 1 : minimum atteint', pg_temp.df_join('sM', 1)));
PERFORM pg_temp.eq('DF10 minimum atteint : confirmée (raison minimum)', $$SELECT pg_temp.df_reason('o5d', 15, 'am', 'sM')$$, 'minimum');
PERFORM pg_temp.eq('DF10 « Départ confirmé » à chaque inscrit', $$SELECT pg_temp.df_n('df_m1', 'booking_confirmed', 'bk_m1_sM') || '/' || pg_temp.df_n('df_m2', 'booking_confirmed', 'bk_m2_sM')$$, '1/1');
PERFORM pg_temp.as_('df_m3');
PERFORM pg_temp.put('bk_m3_sM', pg_temp.ok('DF10 m3 s''inscrit après la confirmation', pg_temp.df_join('sM', 1)));
PERFORM pg_temp.eq('DF10 « Départ confirmé » une seule fois (pas de second envoi)',
  $$SELECT pg_temp.df_n('df_m1', 'booking_confirmed') || '/' || pg_temp.df_n('df_m3', 'booking_confirmed')$$, '1/0');
PERFORM pg_temp.as_('df_m1');
PERFORM pg_temp.eq('DF10 get_my_bookings : minimum / total / confirmée',
  format($$SELECT min_participants || '/' || outing_total || '/' || confirmed FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_m1_sM')), '3/4/true');
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.eq('DF10 get_my_sessions : confirmée', format($$SELECT taken || '/' || confirmed FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('sM')), '4/true');
-- Sur demande : minimum atteint par accept_booking.
PERFORM pg_temp.as_('df_m1');
PERFORM pg_temp.put('bk_m1_16', pg_temp.ok('DF10 m1 demande J+16 (min 2)', pg_temp.df_req('o5min', 16, 'am', 1)));
PERFORM pg_temp.as_('df_m2');
PERFORM pg_temp.put('bk_m2_16', pg_temp.ok('DF10 m2 demande J+16', pg_temp.df_req('o5min', 16, 'am', 1)));
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.ok('DF10 le pro accepte m1', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk_m1_16')));
PERFORM pg_temp.eq('DF10 1/2 : pas confirmée', $$SELECT pg_temp.df_conf('o5min', 16, 'am')$$, 'false');
PERFORM pg_temp.as_('df_m1');
PERFORM pg_temp.eq('DF10 get_my_bookings sur demande : 2 / 1 / false',
  format($$SELECT min_participants || '/' || outing_total || '/' || confirmed FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_m1_16')), '2/1/false');
PERFORM pg_temp.as_('df_m2');
PERFORM pg_temp.eq('DF10 get_my_bookings : en attente → minimum / total / confirmée vides',
  format($$SELECT coalesce(min_participants::text, 'NULL') || '/' || coalesce(outing_total::text, 'NULL') || '/' || coalesce(confirmed::text, 'NULL') FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_m2_16')), 'NULL/NULL/NULL');
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.ok('DF10 le pro accepte m2 : minimum atteint', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk_m2_16')));
PERFORM pg_temp.eq('DF10 sur demande : confirmée (raison minimum)', $$SELECT pg_temp.df_reason('o5min', 16, 'am')$$, 'minimum');
PERFORM pg_temp.eq('DF10 sur demande : « Départ confirmé » aux deux clients',
  $$SELECT pg_temp.df_n('df_m1', 'booking_confirmed', 'bk_m1_16') || '/' || pg_temp.df_n('df_m2', 'booking_confirmed', 'bk_m2_16')$$, '1/1');
-- Sur demande : minimum atteint par une résa manuelle.
PERFORM pg_temp.as_('df_m3');
PERFORM pg_temp.put('bk_m3_17', pg_temp.ok('DF10 m3 demande J+17 (min 3)', pg_temp.df_req('o5min3', 17, 'am', 1)));
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.ok('DF10 le pro accepte m3', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk_m3_17')));
PERFORM pg_temp.ok('DF10 le pro ajoute 2 personnes en manuel : minimum atteint', pg_temp.df_manual('o5min3', 17, 'am', 2));
PERFORM pg_temp.eq('DF10 manuelle : confirmée (raison minimum)', $$SELECT pg_temp.df_reason('o5min3', 17, 'am')$$, 'minimum');
PERFORM pg_temp.eq('DF10 manuelle : « Départ confirmé » au client de l''app', $$SELECT pg_temp.df_n('df_m3', 'booking_confirmed', 'bk_m3_17')$$, '1');
-- confirm_outing (« Maintenir la sortie »).
PERFORM pg_temp.as_('df_m4');
PERFORM pg_temp.put('bk_m4_18', pg_temp.ok('DF10 m4 demande J+18 (sans minimum)', pg_temp.df_req('o5nomin', 18, 'am', 1)));
PERFORM pg_temp.as_('df_m5');
PERFORM pg_temp.put('bk_m5_19', pg_temp.ok('DF10 m5 demande J+19 (min 2)', pg_temp.df_req('o5min', 19, 'am', 1)));
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.ok('DF10 accepte m4', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk_m4_18')));
PERFORM pg_temp.ok('DF10 accepte m5', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk_m5_19')));
PERFORM pg_temp.eq('DF10 maintenir une sortie sans minimum : false', pg_temp.df_confirm('o5nomin', 18, 'am'), 'false');
PERFORM pg_temp.eq('DF10 sans minimum : rien enregistré', $$SELECT pg_temp.df_reason('o5nomin', 18, 'am')$$, 'none');
PERFORM pg_temp.denied('DF10 maintenir une sortie sans inscrit refusé', pg_temp.df_confirm('o5min', 22, 'am'), 'Operation not permitted');
PERFORM pg_temp.denied('DF10 maintenir une sortie commencée refusé', pg_temp.df_confirm('o5min', -1, 'am'), 'junto.session_closed');
PERFORM pg_temp.denied('DF10 période invalide refusée', pg_temp.df_confirm('o5min', 19, 'soir'), 'Operation not permitted');
PERFORM pg_temp.denied('DF10 l''offre d''un autre pro refusée', pg_temp.df_confirm('off_a', 20, 'am'), 'Operation not permitted');
PERFORM pg_temp.eq('DF10 maintenir 1/2 : true', pg_temp.df_confirm('o5min', 19, 'am'), 'true');
PERFORM pg_temp.eq('DF10 raison pro', $$SELECT pg_temp.df_reason('o5min', 19, 'am')$$, 'pro');
PERFORM pg_temp.eq('DF10 « Départ confirmé » au client', $$SELECT pg_temp.df_n('df_m5', 'booking_confirmed', 'bk_m5_19')$$, '1');
PERFORM pg_temp.eq('DF10 maintenir deux fois : false', pg_temp.df_confirm('o5min', 19, 'am'), 'false');
PERFORM pg_temp.eq('DF10 pas de second « Départ confirmé »', $$SELECT pg_temp.df_n('df_m5', 'booking_confirmed')$$, '1');
PERFORM pg_temp.as_('df_m5');
PERFORM pg_temp.eq('DF10 le client lit « confirmée »', format($$SELECT confirmed::text FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_m5_19')), 'true');
PERFORM pg_temp.denied('DF10 un client ne maintient pas une sortie', pg_temp.df_confirm('o5min', 19, 'am'), 'Operation not permitted');
PERFORM pg_temp.as_('df_cand');
PERFORM pg_temp.denied('DF10 un candidat ne maintient pas une sortie', pg_temp.df_confirm('o5min', 19, 'am'), 'Operation not permitted');
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.ok('DF10 cancel_outing sur la sortie maintenue', format($$SELECT public.cancel_outing(%L, %L, 'am')::text$$, pg_temp.id('o5min'), pg_temp.dd(19)));
PERFORM pg_temp.eq('DF10 cancel_outing retire la confirmation', $$SELECT pg_temp.df_reason('o5min', 19, 'am')$$, 'none');
-- Maintenir une date fixe.
PERFORM pg_temp.put('sN', pg_temp.ok('DF10 date J+23 minimum 4', pg_temp.df_new('o5d', 23, 'am', 23, 'am', 6, 4)));
PERFORM pg_temp.as_('df_m4');
PERFORM pg_temp.put('bk_m4_sN', pg_temp.ok('DF10 m4 s''inscrit', pg_temp.df_join('sN', 1)));
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.eq('DF10 maintenir une date fixe : true', pg_temp.df_confirm('o5d', 23, 'am'), 'true');
PERFORM pg_temp.eq('DF10 la confirmation vise la date', $$SELECT pg_temp.df_reason('o5d', 23, 'am', 'sN')$$, 'pro');
PERFORM pg_temp.eq('DF10 get_my_sessions : confirmée', format($$SELECT confirmed::text FROM public.get_my_sessions(%L, %L) WHERE id = %L$$, pg_temp.dd(0), pg_temp.dd(60), pg_temp.id('sN')), 'true');
-- Une confirmation « pro » (Maintenir) reste après une annulation client.
PERFORM pg_temp.put('sP', pg_temp.ok('DF10 date J+27 minimum 3', pg_temp.df_new('o5d', 27, 'am', 27, 'am', 6, 3)));
PERFORM pg_temp.as_('df_m8');
PERFORM pg_temp.put('bk_m8_sP', pg_temp.ok('DF10 m8 s''inscrit', pg_temp.df_join('sP', 1)));
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.eq('DF10 le pro maintient', pg_temp.df_confirm('o5d', 27, 'am'), 'true');
PERFORM pg_temp.as_('df_m8');
PERFORM pg_temp.ok('DF10 m8 annule', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk_m8_sP')));
PERFORM pg_temp.eq('DF10 la confirmation « pro » reste', $$SELECT pg_temp.df_reason('o5d', 27, 'am', 'sP')$$, 'pro');
PERFORM pg_temp.eq('DF10 get_my_bookings : rien pour une inscription annulée',
  format($$SELECT coalesce(min_participants::text, 'NULL') || '/' || coalesce(confirmed::text, 'NULL') FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_m8_sP')), 'NULL/NULL');
-- SESSIONS-1 (corrigé 00578) : la confirmation « minimum » retombe ; baisser le minimum confirme.
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.put('sK', pg_temp.ok('DF10 date J+26 minimum 3', pg_temp.df_new('o5d', 26, 'am', 26, 'am', 6, 3)));
PERFORM pg_temp.put('sL', pg_temp.ok('DF10 date J+25 minimum 5', pg_temp.df_new('o5d', 25, 'am', 25, 'am', 6, 5)));
PERFORM pg_temp.as_('df_m6');
PERFORM pg_temp.put('bk_m6_sK', pg_temp.ok('DF10 m6 s''inscrit à 3', pg_temp.df_join('sK', 3)));
PERFORM pg_temp.eq('DF10 confirmée par le minimum', $$SELECT pg_temp.df_conf('o5d', 26, 'am', 'sK')$$, 'true');
PERFORM pg_temp.ok('DF10 m6 annule', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk_m6_sK')));
PERFORM pg_temp.eq('DF10 sous le minimum après annulation : plus confirmée', $$SELECT pg_temp.df_conf('o5d', 26, 'am', 'sK')$$, 'false');
PERFORM pg_temp.as_('df_m7');
PERFORM pg_temp.put('bk_m7_sK', pg_temp.ok('DF10 m7 s''inscrit à 1', pg_temp.df_join('sK', 1)));
PERFORM pg_temp.eq('DF10 m7 ne lit pas « confirmée » (1/3)',
  format($$SELECT outing_total || '/' || confirmed FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_m7_sK')), '1/false');
PERFORM pg_temp.as_('df_m5');
PERFORM pg_temp.put('bk_m5_sL', pg_temp.ok('DF10 m5 s''inscrit à 2 (minimum 5)', pg_temp.df_join('sL', 2)));
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.ok('DF10 le pro baisse le minimum à 2', pg_temp.df_upd('sL', 25, 'am', 25, 'am', 6, 2));
PERFORM pg_temp.eq('DF10 minimum baissé sous le total : confirmée', $$SELECT pg_temp.df_conf('o5d', 25, 'am', 'sL')$$, 'true');
PERFORM pg_temp.eq('DF10 minimum baissé : « Départ confirmé » au client', $$SELECT pg_temp.df_n('df_m5', 'booking_confirmed', 'bk_m5_sL')$$, '1');
-- SESSIONS-2a (corrigé 00578) : après le rappel J-2 (ici : pour demain), accepter / ajouter / poster = maintenir.
PERFORM pg_temp.as_('df_m6');
PERFORM pg_temp.put('bk_m6_d1', pg_temp.ok('DF10 m6 demande pour demain (min 3)', pg_temp.df_req('o5min3', 1, 'am', 1)));
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.ok('DF10 le pro accepte pour demain', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk_m6_d1')));
PERFORM pg_temp.eq('DF10 acceptée après le rappel J-2 : maintenue (raison pro)', $$SELECT pg_temp.df_reason('o5min3', 1, 'am')$$, 'pro');
PERFORM pg_temp.ok('DF10 le pro ajoute un manuel pour demain (min 2)', pg_temp.df_manual('o5min', 1, 'am', 1));
PERFORM pg_temp.eq('DF10 manuelle après le rappel J-2 : maintenue (raison pro)', $$SELECT pg_temp.df_reason('o5min', 1, 'am')$$, 'pro');
PERFORM pg_temp.put('s_d1', pg_temp.ok('DF10 le pro poste une date pour demain après-midi (min 3)', pg_temp.df_new('o5d', 1, 'pm', 1, 'pm', 6, 3)));
PERFORM pg_temp.eq('DF10 date postée après le rappel J-2 : maintenue (raison pro)', $$SELECT pg_temp.df_reason('o5d', 1, 'pm', 's_d1')$$, 'pro');
-- T-SESSION-CONF (00578) : une date annulée perd ses confirmations.
PERFORM pg_temp.put('sCx', pg_temp.ok('DF10 date J+28 minimum 3', pg_temp.df_new('o5d', 28, 'am', 28, 'am', 6, 3)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_bk('bk_m4_sCx', 'o5d', 'df_m4', 28, 'am', 1, 'accepted', 'sCx');
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.eq('DF10 le pro maintient la date J+28 (1/3)', pg_temp.df_confirm('o5d', 28, 'am'), 'true');
PERFORM pg_temp.eq('DF10 date J+28 confirmée (raison pro)', $$SELECT pg_temp.df_reason('o5d', 28, 'am', 'sCx')$$, 'pro');
PERFORM pg_temp.ok('DF10 le pro annule la date J+28', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('sCx')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF10 T-SESSION-CONF date annulée : plus aucune confirmation',
  $$SELECT count(*)::text FROM private.outing_confirmations WHERE session_id = pg_temp.id('sCx')$$, '0');

-- ═════ DF11 — Crons : annulation auto J-1, rappel J-2 (minimum) ═════
-- Copies pg_temp des fonctions vivantes, porte horaire (9 h Paris) neutralisée.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF11 porte horaire de l''annulation auto trouvée telle quelle',
  $$SELECT (strpos(pg_get_functiondef('private.auto_cancel_short_outings()'::regprocedure), '<> 9 THEN RETURN 0') > 0)::text$$, 'true');
PERFORM pg_temp.eq('DF11 porte horaire du rappel J-2 trouvée telle quelle',
  $$SELECT (strpos(pg_get_functiondef('private.notify_booking_forms_missing()'::regprocedure), '<> 9 THEN RETURN;') > 0)::text$$, 'true');
EXECUTE replace(replace(pg_get_functiondef('private.auto_cancel_short_outings()'::regprocedure),
  '<> 9 THEN RETURN 0', '< 0 THEN RETURN 0'), 'private.auto_cancel_short_outings', 'pg_temp.acs');
EXECUTE replace(replace(pg_get_functiondef('private.notify_booking_forms_missing()'::regprocedure),
  '<> 9 THEN RETURN;', '< 0 THEN RETURN;'), 'private.notify_booking_forms_missing', 'pg_temp.nbf');

PERFORM pg_temp.as_('df_pro4');
PERFORM pg_temp.put('o4a', pg_temp.ok('DF11 offre des dates', pg_temp.df_off_sql('Dates 4', 8, NULL)));
PERFORM pg_temp.put('o4b', pg_temp.ok('DF11 sur demande min 3 (annulée)', pg_temp.df_off_sql('Min3 annulée', 8, 3)));
PERFORM pg_temp.put('o4c', pg_temp.ok('DF11 sur demande sans minimum', pg_temp.df_off_sql('Sans min', 8, NULL)));
PERFORM pg_temp.put('o4d', pg_temp.ok('DF11 sur demande min 2 atteint', pg_temp.df_off_sql('Min2 atteint', 8, 2)));
PERFORM pg_temp.put('o4e', pg_temp.ok('DF11 sur demande min 3 sans opt-in', pg_temp.df_off_sql('Min3 sans opt-in', 8, 3)));
PERFORM pg_temp.put('o4f', pg_temp.ok('DF11 sur demande min 3, attente seulement', pg_temp.df_off_sql('Min3 attente', 8, 3)));
PERFORM pg_temp.put('o4g', pg_temp.ok('DF11 sur demande min 3 avec fiches', pg_temp.df_off_sql('Min3 fiches', 8, 3)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_optin(o) FROM unnest(ARRAY['o4a','o4b','o4c','o4d','o4f','o4g']) o;
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_offerings SET participant_fields = '{"std": ["weight"], "custom": []}'::jsonb WHERE id = pg_temp.id('o4g');
PERFORM set_config('junto.bypass_lock', 'false', true);
-- Dates (insérées) : T1 demain matin 2/3 → annulée ; T2 demain après-midi 2/2 ; T3 demain 1/3 maintenue ;
-- T4 après-demain 1/3 ; T5 demain sans minimum ; T7 après-demain 1/3 maintenue.
PERFORM pg_temp.df_ss('T1', 'o4a', 1, 'am', 1, 'am', 8, 3);
PERFORM pg_temp.df_bk('bk_k1_T1', 'o4a', 'df_k1', 1, 'am', 1, 'accepted', 'T1');
PERFORM pg_temp.df_bk('bk_man_T1', 'o4a', NULL, 1, 'am', 1, 'accepted', 'T1');
PERFORM pg_temp.df_ss('T2', 'o4a', 1, 'pm', 1, 'pm', 8, 2);
PERFORM pg_temp.df_bk('bk_k2_T2', 'o4a', 'df_k2', 1, 'pm', 2, 'accepted', 'T2');
PERFORM pg_temp.df_ss('T3', 'o4a', 1, 'am', 1, 'am', 8, 3);
PERFORM pg_temp.df_bk('bk_k3_T3', 'o4a', 'df_k3', 1, 'am', 1, 'accepted', 'T3');
PERFORM pg_temp.df_oc('o4a', 1, 'am', 'T3', 'pro');
PERFORM pg_temp.df_ss('T4', 'o4a', 2, 'am', 2, 'am', 8, 3);
PERFORM pg_temp.df_bk('bk_k4_T4', 'o4a', 'df_k4', 2, 'am', 1, 'accepted', 'T4');
PERFORM pg_temp.df_ss('T5', 'o4a', 1, 'am', 1, 'am', 8, NULL);
PERFORM pg_temp.df_bk('bk_k5_T5', 'o4a', 'df_k5', 1, 'am', 1, 'accepted', 'T5');
PERFORM pg_temp.df_ss('T7', 'o4a', 2, 'pm', 2, 'pm', 8, 3);
PERFORM pg_temp.df_bk('bk_k8_T7', 'o4a', 'df_k8', 2, 'pm', 1, 'accepted', 'T7');
PERFORM pg_temp.df_oc('o4a', 2, 'pm', 'T7', 'pro');
-- T6 (SESSIONS-1, puis SESSIONS-B 00580) : demain après-midi, minimum 3 ; k6 s'inscrit à 3 puis annule,
-- k7 s'inscrit à 1. Après le rappel J-2, le « Départ confirmé » déjà annoncé tient : la date reste.
PERFORM pg_temp.df_ss('T6', 'o4a', 1, 'pm', 1, 'pm', 6, 3);
PERFORM pg_temp.as_('df_k6');
PERFORM pg_temp.put('bk_k6_T6', pg_temp.ok('DF11 k6 s''inscrit à 3 (minimum atteint)', pg_temp.df_join('T6', 3)));
PERFORM pg_temp.ok('DF11 k6 annule', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk_k6_T6')));
PERFORM pg_temp.as_('df_k7');
PERFORM pg_temp.put('bk_k7_T6', pg_temp.ok('DF11 k7 s''inscrit à 1', pg_temp.df_join('T6', 1)));
-- Sur demande (insérées) : demain matin.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_bk('bk_k9_b', 'o4b', 'df_k9', 1, 'am', 1, 'accepted');
PERFORM pg_temp.df_bk('bk_k10_b', 'o4b', 'df_k10', 1, 'am', 1, 'pending');
PERFORM pg_temp.df_bk('bk_k9_c', 'o4c', 'df_k9', 1, 'am', 1, 'accepted');
PERFORM pg_temp.df_bk('bk_k9_d', 'o4d', 'df_k9', 1, 'am', 2, 'accepted');
PERFORM pg_temp.df_bk('bk_k9_e', 'o4e', 'df_k9', 1, 'am', 1, 'accepted');
PERFORM pg_temp.df_bk('bk_k10_f', 'o4f', 'df_k10', 1, 'am', 1, 'pending');
PERFORM pg_temp.df_bk('bk_k11_g', 'o4g', 'df_k11', 2, 'am', 1, 'accepted');

PERFORM pg_temp.as_('df_k1');
PERFORM pg_temp.denied('DF11 un client n''exécute pas l''annulation auto', $$SELECT private.auto_cancel_short_outings()::text$$, 'permission denied');
PERFORM pg_temp.denied('DF11 un client n''exécute pas le rappel J-2', $$SELECT private.notify_booking_forms_missing()::text$$, 'permission denied');
PERFORM pg_temp.as_('df_pro4');
PERFORM pg_temp.denied('DF11 le pro n''exécute pas l''annulation auto', $$SELECT private.auto_cancel_short_outings()::text$$, 'permission denied');

PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('DF11 annulation auto (copie sans porte horaire)', $$SELECT pg_temp.acs()::text$$);
-- Dates.
PERFORM pg_temp.eq('DF11 date de demain sous le minimum : annulée', $$SELECT pg_temp.df_sst('T1')$$, 'cancelled');
PERFORM pg_temp.eq('DF11 ses inscriptions (app et manuelle) : cancelled_pro', $$SELECT pg_temp.df_bst('bk_k1_T1') || '/' || pg_temp.df_bst('bk_man_T1')$$, 'cancelled_pro/cancelled_pro');
PERFORM pg_temp.eq('DF11 client notifié : booking_cancelled, variante auto_minimum',
  $$SELECT string_agg((data->>'variant') || '/' || (data->>'by'), ',') FROM public.notifications
    WHERE user_id = pg_temp.id('df_k1') AND type = 'booking_cancelled' AND data->>'booking_id' = pg_temp.get('bk_k1_T1')$$, 'auto_minimum/auto');
PERFORM pg_temp.eq('DF11 rien dans les DM (ce n''est pas le pro qui écrit)',
  $$SELECT count(*)::text FROM public.messages m JOIN public.conversations c ON c.id = m.conversation_id
    WHERE c.type = 'dm' AND pg_temp.id('df_k1') IN (c.user_1, c.user_2)$$, '0');
PERFORM pg_temp.eq('DF11 pro notifié : outing_auto_cancelled (2/3)',
  $$SELECT string_agg((data->'params'->>'total') || '/' || (data->'params'->>'min'), ',') FROM public.notifications
    WHERE user_id = pg_temp.id('df_pro4') AND type = 'outing_auto_cancelled' AND data->>'offering_id' = pg_temp.get('o4a') AND data->'params'->>'period' = 'am'$$, '2/3');
PERFORM pg_temp.eq('DF11 minimum atteint : la date reste', $$SELECT pg_temp.df_sst('T2') || '/' || pg_temp.df_bst('bk_k2_T2')$$, 'scheduled/accepted');
PERFORM pg_temp.eq('DF11 date maintenue par le pro : reste', $$SELECT pg_temp.df_sst('T3') || '/' || pg_temp.df_bst('bk_k3_T3')$$, 'scheduled/accepted');
PERFORM pg_temp.eq('DF11 seulement demain : la date d''après-demain reste', $$SELECT pg_temp.df_sst('T4') || '/' || pg_temp.df_bst('bk_k4_T4')$$, 'scheduled/accepted');
PERFORM pg_temp.eq('DF11 date sans minimum : reste', $$SELECT pg_temp.df_sst('T5') || '/' || pg_temp.df_bst('bk_k5_T5')$$, 'scheduled/accepted');
PERFORM pg_temp.eq('DF11 SESSIONS-B : annulation après le rappel J-2 → la confirmation « minimum » tient, la date reste',
  $$SELECT pg_temp.df_sst('T6') || '/' || pg_temp.df_reason('o4a', 1, 'pm', 'T6')$$, 'scheduled/minimum');
-- Sur demande.
PERFORM pg_temp.eq('DF11 sur demande sous le minimum : acceptée → cancelled_pro, en attente → declined',
  $$SELECT pg_temp.df_bst('bk_k9_b') || '/' || pg_temp.df_bst('bk_k10_b')$$, 'cancelled_pro/declined');
PERFORM pg_temp.eq('DF11 l''accepté reçoit auto_minimum',
  $$SELECT string_agg(data->>'variant', ',') FROM public.notifications WHERE user_id = pg_temp.id('df_k9') AND type = 'booking_cancelled' AND data->>'booking_id' = pg_temp.get('bk_k9_b')$$, 'auto_minimum');
PERFORM pg_temp.eq('DF11 l''attente reçoit booking_declined', $$SELECT pg_temp.df_n('df_k10', 'booking_declined', 'bk_k10_b')$$, '1');
PERFORM pg_temp.eq('DF11 pro notifié pour la sortie sur demande',
  $$SELECT count(*)::text FROM public.notifications WHERE user_id = pg_temp.id('df_pro4') AND type = 'outing_auto_cancelled' AND data->>'offering_id' = pg_temp.get('o4b')$$, '1');
PERFORM pg_temp.eq('DF11 sur demande sans minimum : reste', $$SELECT pg_temp.df_bst('bk_k9_c')$$, 'accepted');
PERFORM pg_temp.eq('DF11 sur demande minimum atteint : reste', $$SELECT pg_temp.df_bst('bk_k9_d')$$, 'accepted');
PERFORM pg_temp.eq('DF11 sur demande en attente seulement : rien ne bouge', $$SELECT pg_temp.df_bst('bk_k10_f')$$, 'pending');
PERFORM pg_temp.eq('DF11 SESSIONS-2b : la colonne d''opt-in pro_offerings.auto_cancel existe',
  $$SELECT count(*)::text FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pro_offerings' AND column_name = 'auto_cancel'$$, '1');
PERFORM pg_temp.eq('DF11 SESSIONS-2b : sans opt-in, une offre avec minimum n''est pas annulée', $$SELECT pg_temp.df_bst('bk_k9_e')$$, 'accepted');

-- Rappel J-2 : partie minimum.
-- 00578 (SESSIONS-2) : offre SANS opt-in (o4e) sous le minimum à J+2 → variante « minimum » (pas « annulée demain »).
PERFORM pg_temp.df_bk('bk_k15_e2', 'o4e', 'df_k15', 2, 'am', 1, 'accepted');
PERFORM pg_temp.ok('DF11 rappel J-2 (copie sans porte horaire)', $$SELECT pg_temp.nbf()::text$$);
PERFORM pg_temp.eq('DF11 sans opt-in, J+2 sous le minimum : variante minimum, sans annonce d''annulation',
  $$SELECT string_agg((data->>'variant') || '/' || (data->'params'->>'total') || '/' || (data->'params'->>'min') || '/' || (body NOT LIKE '%annulée%')::text, ',') FROM public.notifications
    WHERE user_id = pg_temp.id('df_pro4') AND type = 'booking_forms_missing' AND data->>'offering_id' = pg_temp.get('o4e')$$, 'minimum/1/3/true');
-- Offres avec opt-in (pg_temp.df_optin) : variantes *_auto.
PERFORM pg_temp.eq('DF11 opt-in, date J+2 sous le minimum : variante minimum_auto, 1/3',
  $$SELECT string_agg((data->>'variant') || '/' || (data->'params'->>'total') || '/' || (data->'params'->>'min'), ',') FROM public.notifications
    WHERE user_id = pg_temp.id('df_pro4') AND type = 'booking_forms_missing' AND data->>'offering_id' = pg_temp.get('o4a') AND data->'params'->>'period' = 'am'$$, 'minimum_auto/1/3');
PERFORM pg_temp.eq('DF11 date J+2 maintenue : pas signalée',
  $$SELECT count(*)::text FROM public.notifications
    WHERE user_id = pg_temp.id('df_pro4') AND type = 'booking_forms_missing' AND data->>'offering_id' = pg_temp.get('o4a') AND data->'params'->>'period' = 'pm'$$, '0');
PERFORM pg_temp.eq('DF11 opt-in, sur demande J+2 : fiches manquantes ET minimum → variante both_auto',
  $$SELECT string_agg((data->>'variant') || '/' || (data->'params'->>'count') || '/' || (data->'params'->>'total') || '/' || (data->'params'->>'min'), ',') FROM public.notifications
    WHERE user_id = pg_temp.id('df_pro4') AND type = 'booking_forms_missing' AND data->>'offering_id' = pg_temp.get('o4g')$$, 'both_auto/1/1/3');

-- ═════ DF12 — Pro suspendu (SESSIONS-6) ═════
PERFORM pg_temp.as_('df_pro6');
PERFORM pg_temp.put('o6', pg_temp.ok('DF12 offre du pro6', pg_temp.df_off_sql('Rando 6', 8, 3)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_ss('U1', 'o6', 30, 'am', 30, 'am', 6, 3);
PERFORM pg_temp.df_bk('bk_k12_U1', 'o6', 'df_k12', 30, 'am', 1, 'accepted', 'U1');
PERFORM pg_temp.df_oc('o6', 30, 'am', 'U1', 'pro');
PERFORM pg_temp.df_ss('U2', 'o6', -1, 'am', 1, 'pm', 6, NULL);
PERFORM pg_temp.df_bk('bk_k13_multi', 'o6', 'df_k13', -1, 'am', 1, 'accepted', NULL, 1);
PERFORM pg_temp.df_bk('bk_k14_31', 'o6', 'df_k14', 31, 'am', 1, 'accepted');
PERFORM pg_temp.as_('df_adm');
PERFORM pg_temp.ok('DF12 l''admin suspend le pro6', format($$SELECT public.admin_suspend_user(%L, 'test')::text$$, pg_temp.id('df_pro6')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF12 résa future sur demande : cancelled_pro', $$SELECT pg_temp.df_bst('bk_k14_31')$$, 'cancelled_pro');
PERFORM pg_temp.eq('DF12 inscription future à une date : cancelled_pro', $$SELECT pg_temp.df_bst('bk_k12_U1')$$, 'cancelled_pro');
PERFORM pg_temp.eq('DF12 sa date à venir est annulée', $$SELECT pg_temp.df_sst('U1')$$, 'cancelled');
PERFORM pg_temp.eq('DF12 sa date en cours est annulée', $$SELECT pg_temp.df_sst('U2')$$, 'cancelled');
PERFORM pg_temp.eq('DF12 ses confirmations sont retirées',
  $$SELECT count(*)::text FROM private.outing_confirmations WHERE pro_id = pg_temp.id('df_pro6')$$, '0');
PERFORM pg_temp.eq('DF12 une résa sur plusieurs jours commencée hier est annulée', $$SELECT pg_temp.df_bst('bk_k13_multi')$$, 'cancelled_pro');
PERFORM pg_temp.as_('df_pro6');
PERFORM pg_temp.denied('DF12 pro suspendu : création refusée', pg_temp.df_new('o6', 40, 'am', 40, 'am', 6), 'Operation not permitted');
PERFORM pg_temp.denied('DF12 pro suspendu : modification refusée', pg_temp.df_upd('U1', 30, 'am', 30, 'am', 5), 'Operation not permitted');
PERFORM pg_temp.denied('DF12 pro suspendu : annulation refusée', format($$SELECT public.cancel_pro_session(%L)::text$$, pg_temp.id('U2')), 'Operation not permitted');
PERFORM pg_temp.denied('DF12 pro suspendu : get_my_sessions refusé', format($$SELECT count(*)::text FROM public.get_my_sessions(%L, %L)$$, pg_temp.dd(0), pg_temp.dd(60)), 'Operation not permitted');
PERFORM pg_temp.denied('DF12 pro suspendu : get_session_conflicts refusé',
  format($$SELECT count(*)::text FROM public.get_session_conflicts(%L, 'am', %L, 'pm')$$, pg_temp.dd(30), pg_temp.dd(30)), 'Operation not permitted');
PERFORM pg_temp.denied('DF12 pro suspendu : maintenir refusé', pg_temp.df_confirm('o6', 30, 'am'), 'Operation not permitted');
PERFORM pg_temp.as_('df_k15');
PERFORM pg_temp.eq('DF12 les dates d''un pro suspendu ne sont plus listées', format($$SELECT count(*)::text FROM public.get_offering_sessions(%L)$$, pg_temp.id('o6')), '0');
PERFORM pg_temp.denied('DF12 on ne s''inscrit pas chez un pro suspendu', pg_temp.df_join('U2', 1), 'Operation not permitted');

-- ═════ DF11b — set_offering_auto_cancel (00578, SESSIONS-2b) ═════
-- Chaîne : auth, assert_approved_pro (suspension incluse), valeur non nulle, offre du pro.
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('DF11b anon ne règle pas l''annulation auto', format($$SELECT public.set_offering_auto_cancel(%L, true)::text$$, pg_temp.id('o4e')));
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF11b un membre ne règle pas l''annulation auto', format($$SELECT public.set_offering_auto_cancel(%L, true)::text$$, pg_temp.id('o4e')), '^Operation not permitted$');
PERFORM pg_temp.as_('df_cand');
PERFORM pg_temp.denied('DF11b un candidat ne règle pas l''annulation auto', format($$SELECT public.set_offering_auto_cancel(%L, true)::text$$, pg_temp.id('o4e')), '^Operation not permitted$');
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.denied('DF11b l''offre d''un autre pro : refusé', format($$SELECT public.set_offering_auto_cancel(%L, true)::text$$, pg_temp.id('o4e')), '^Operation not permitted$');
PERFORM pg_temp.as_('df_pro6');
PERFORM pg_temp.denied('DF11b un pro suspendu : refusé', format($$SELECT public.set_offering_auto_cancel(%L, true)::text$$, pg_temp.id('o6')), '^Operation not permitted$');
PERFORM pg_temp.as_('df_pro4');
PERFORM pg_temp.denied('DF11b offre inexistante : même erreur', format($$SELECT public.set_offering_auto_cancel(%L, true)::text$$, gen_random_uuid()), '^Operation not permitted$');
PERFORM pg_temp.denied('DF11b NULL refusé', format($$SELECT public.set_offering_auto_cancel(%L, NULL)::text$$, pg_temp.id('o4e')), '^Operation not permitted$');
PERFORM pg_temp.denied('DF11b pas d''écriture directe de la colonne',
  format($$UPDATE public.pro_offerings SET auto_cancel = true WHERE id = %L RETURNING 1$$, pg_temp.id('o4e')));
PERFORM pg_temp.eq('DF11b par défaut : pas d''annulation auto', format($$SELECT auto_cancel::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o4e')), 'false');
PERFORM pg_temp.ok('DF11b le pro active l''annulation auto', format($$SELECT public.set_offering_auto_cancel(%L, true)::text$$, pg_temp.id('o4e')));
PERFORM pg_temp.eq('DF11b le choix est relu (vue des offres)', format($$SELECT auto_cancel::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o4e')), 'true');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('DF11b annulation auto relancée (copie sans porte horaire)', $$SELECT pg_temp.acs()::text$$);
PERFORM pg_temp.eq('DF11b opt-in posé par la RPC : la sortie de demain sous le minimum est annulée', $$SELECT pg_temp.df_bst('bk_k9_e')$$, 'cancelled_pro');
PERFORM pg_temp.as_('df_pro4');
PERFORM pg_temp.ok('DF11b le pro désactive l''annulation auto', format($$SELECT public.set_offering_auto_cancel(%L, false)::text$$, pg_temp.id('o4e')));
PERFORM pg_temp.eq('DF11b désactivée', format($$SELECT auto_cancel::text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('o4e')), 'false');

-- ═════ DF14 — Plusieurs jours « sur demande » (00577) ═════
-- set_offering_request_length.
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('DF14 anon ne règle pas la durée d''une offre', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('off_b')));
PERFORM pg_temp.as_('df_cA');
PERFORM pg_temp.denied('DF14 un membre ne règle pas la durée', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('off_b')), 'Operation not permitted');
PERFORM pg_temp.as_('df_cand');
PERFORM pg_temp.denied('DF14 un candidat ne règle pas la durée', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('off_b')), 'Operation not permitted');
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.denied('DF14 l''offre d''un autre pro refusée', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('off_b')), 'Operation not permitted');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF14 durée 0 refusée', format($$SELECT public.set_offering_request_length(%L, 0)::text$$, pg_temp.id('off_b')), 'junto.offering_request_days');
PERFORM pg_temp.denied('DF14 durée 15 refusée', format($$SELECT public.set_offering_request_length(%L, 15)::text$$, pg_temp.id('off_b')), 'junto.offering_request_days');
PERFORM pg_temp.put('off_day', pg_temp.ok('DF14 offre à la journée', pg_temp.df_off_sql('Journée', 8, NULL)));
PERFORM pg_temp.ok('DF14 durée 1 = à la journée', format($$SELECT public.set_offering_request_length(%L, 1)::text$$, pg_temp.id('off_day')));
PERFORM pg_temp.ok('DF14 NULL = demi-journée', format($$SELECT public.set_offering_request_length(%L, NULL)::text$$, pg_temp.id('off_b')));
PERFORM pg_temp.as_('df_pro6');
PERFORM pg_temp.denied('DF14 pro suspendu refusé', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('o6')), 'Operation not permitted');
-- create_booking : plage calculée par la base, variantes de notification.
PERFORM pg_temp.as_('df_cE');
PERFORM pg_temp.put('bk_E_day', pg_temp.ok('DF14 demande à la journée', pg_temp.df_req('off_day', 9, 'am', 1)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF14 journée : end_day = le jour même (calculé par la base)', format($$SELECT end_day::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_E_day')), pg_temp.dd(9)::text);
PERFORM pg_temp.eq('DF14 notif booking_request variante day',
  $$SELECT string_agg(data->>'variant', ',') FROM public.notifications WHERE user_id = pg_temp.id('df_pro') AND type = 'booking_request' AND data->>'booking_id' = pg_temp.get('bk_E_day')$$, 'day');
PERFORM pg_temp.eq('DF14 sur 3 jours : end_day = départ + 2', format($$SELECT end_day::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_p2_12')), pg_temp.dd(14)::text);
PERFORM pg_temp.eq('DF14 notif booking_request variante multi (3 jours)',
  $$SELECT string_agg((data->>'variant') || '/' || (data->'params'->>'days'), ',') FROM public.notifications WHERE user_id = pg_temp.id('df_pro') AND type = 'booking_request' AND data->>'booking_id' = pg_temp.get('bk_p2_12')$$, 'multi/3');
PERFORM pg_temp.as_('df_cP2');
PERFORM pg_temp.eq('DF14 get_my_bookings : fin de plage (jour, après-midi)',
  format($$SELECT end_day::text || '/' || end_period FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk_p2_12')), pg_temp.dd(14)::text || '/pm');
-- Chaque demi-journée de la plage : ouverte, libre dans l'agenda importé, places suffisantes.
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.ok('DF14 le pro ferme J+5 après-midi', format($$SELECT public.set_pro_availability_bulk(ARRAY[%L]::date[], ARRAY['pm'], false)::text$$, pg_temp.dd(5)));
PERFORM pg_temp.as_('df_cE');
PERFORM pg_temp.denied('DF14 une demi-journée fermée au milieu de la plage refusée', pg_temp.df_req('off_m', 4, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('DF14 une demi-journée occupée (agenda importé) dans la plage refusée', pg_temp.df_req('off_m', 30, 'am', 1), 'junto.booking_slot_unavailable');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_bk('bk_full43', 'off_a', 'df_cF', 43, 'pm', 8, 'accepted');
PERFORM pg_temp.as_('df_cE');
PERFORM pg_temp.denied('DF14 places épuisées sur une demi-journée plus loin dans la plage : complet', pg_temp.df_req('off_m', 42, 'am', 1), 'junto.booking_full');
-- accept_booking : places sur chaque demi-journée de la plage.
PERFORM pg_temp.as_('df_cD');
PERFORM pg_temp.put('bk_D_52', pg_temp.ok('DF14 D demande J+52 → J+54', pg_temp.df_req('off_m', 52, 'am', 1)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.df_bk('bk_full53', 'off_a', 'df_cF', 53, 'pm', 8, 'accepted');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF14 accept : une demi-journée pleine dans la plage refuse', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk_D_52')), 'junto.booking_full');
PERFORM pg_temp.as_('db');
UPDATE public.bookings SET status = 'cancelled' WHERE id = pg_temp.id('bk_full53');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.ok('DF14 accept une fois la place libérée', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk_D_52')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF14 notif booking_accepted variante multi',
  $$SELECT string_agg((data->>'variant') || '/' || (data->'params'->>'days'), ',') FROM public.notifications WHERE user_id = pg_temp.id('df_cD') AND type = 'booking_accepted' AND data->>'booking_id' = pg_temp.get('bk_D_52')$$, 'multi/3');
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.denied('DF14 une date ne peut plus se poser sur la plage acceptée (dernier jour)', pg_temp.df_new('off_a', 54, 'pm', 54, 'pm', 6), 'junto.session_conflict');
-- Ligne réactivée par create_booking : session_id remis à NULL.
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.bookings SET last_submitted_at = now() - INTERVAL '2 hours' WHERE id = pg_temp.id('bk_E_sF');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('df_cE');
PERFORM pg_temp.eq('DF14 l''ancienne inscription d''une date annulée est réactivée en demande', pg_temp.df_req('off_a', 45, 'am', 1), pg_temp.get('bk_E_sF'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF14 réactivée : en attente, détachée de la date',
  format($$SELECT status || '/' || coalesce(session_id::text, 'NULL') || '/' || coalesce(end_day::text, 'NULL') FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_E_sF')), 'pending/NULL/NULL');
-- create_manual_booking sur une offre de plusieurs jours : départ forcé le matin, même plage.
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.put('bk_man_m', pg_temp.ok('DF14 manuelle sur l''offre de 3 jours (demandée l''après-midi)', pg_temp.df_manual('off_m', 6, 'pm', 1)));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF14 manuelle : départ le matin, fin à J+2',
  format($$SELECT period || '/' || end_day::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk_man_m')), 'am/' || pg_temp.dd(8)::text);
-- get_pro_agenda.
PERFORM pg_temp.as_('df_pro');
PERFORM pg_temp.eq('DF14 agenda : une plage est visible si un de ses jours est dans la fenêtre',
  format($$SELECT end_day::text FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.dd(13), pg_temp.dd(13), pg_temp.id('bk_p2_12')), pg_temp.dd(14)::text);
PERFORM pg_temp.eq('DF14 agenda : une inscription porte sa date',
  format($$SELECT (session_id = %L)::text FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.id('sA'), pg_temp.dd(20), pg_temp.dd(20), pg_temp.id('bk_B_sA')), 'true');
PERFORM pg_temp.as_('df_pro5');
PERFORM pg_temp.eq('DF14 agenda : minimum et confirmation de la sortie sur demande',
  format($$SELECT min_participants || '/' || confirmed FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.dd(16), pg_temp.dd(16), pg_temp.id('bk_m1_16')), '2/true');
PERFORM pg_temp.eq('DF14 agenda : pas de minimum sur une inscription à une date (il vient de get_my_sessions)',
  format($$SELECT coalesce(min_participants::text, 'NULL') FROM public.get_pro_agenda(%L, %L) WHERE id = %L$$, pg_temp.dd(15), pg_temp.dd(15), pg_temp.id('bk_m1_sM')), 'NULL');

-- ═════ DF13 — Fonctions internes : jamais exécutables par un client ═════
PERFORM pg_temp.as_('df_cA');
FOREACH v_lbl IN ARRAY ARRAY[
  format($$SELECT private.session_started(%L, 'am')::text$$, pg_temp.dd(5)),
  format($$SELECT private.half_idx(%L, 'am')::text$$, pg_temp.dd(5)),
  format($$SELECT private.session_at(%L, %L, 'am')::text$$, pg_temp.id('df_pro'), pg_temp.dd(20)),
  format($$SELECT private.session_check(%L, %L, 'am', %L, 'am', 5, NULL, NULL, NULL)::text$$, pg_temp.id('df_pro'), pg_temp.dd(90), pg_temp.dd(90)),
  format($$SELECT private.decline_pending_in_range(%L, 0, 100000)::text$$, pg_temp.id('df_pro')),
  format($$SELECT private.cancel_session_bookings(%L, %L, NULL)::text$$, pg_temp.id('df_pro'), pg_temp.id('sA')),
  format($$SELECT private.half_taken(%L, %L, 'am')::text$$, pg_temp.id('df_pro'), pg_temp.dd(20)),
  format($$SELECT private.outing_total(%L, %L, 'am', NULL)::text$$, pg_temp.id('off_a'), pg_temp.dd(20)),
  format($$SELECT private.outing_min(%L, NULL)::text$$, pg_temp.id('off_a')),
  format($$SELECT private.outing_confirmed(%L, %L, 'am', NULL)::text$$, pg_temp.id('off_a'), pg_temp.dd(20)),
  format($$SELECT private.mark_outing_confirmed(%L, %L, %L, 'am', %L, 'pro')::text$$, pg_temp.id('df_pro'), pg_temp.id('off_a'), pg_temp.dd(20), pg_temp.id('sA')),
  format($$SELECT private.auto_cancel_outing_bookings(%L, %L, %L, 'am', NULL, 'x')::text$$, pg_temp.id('df_pro'), pg_temp.id('off_a'), pg_temp.dd(20)),
  format($$SELECT private.notify_outing_auto_cancelled(%L, %L, %L, 'am', 'x', 1, 3)::text$$, pg_temp.id('df_pro'), pg_temp.id('off_a'), pg_temp.dd(20)),
  format($$SELECT private.booking_end_idx(%L, 'am', NULL)::text$$, pg_temp.dd(20)),
  format($$SELECT private.booking_when(%L, 'am', NULL)::text$$, pg_temp.dd(20))
] LOOP
  PERFORM pg_temp.denied('DF13 interne refusée au client : ' || substring(v_lbl FROM 'private\.[a-z_]+'), v_lbl, 'permission denied');
END LOOP;
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DF13 rien n''a été confirmé par ces tentatives', $$SELECT pg_temp.df_conf('off_a', 20, 'am', 'sA')$$, 'false');

END;
