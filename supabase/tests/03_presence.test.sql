-- Domaine 3 — présence, fiabilité, réputation, badges.
-- now() est figé pendant le bloc : les situations temporelles sont construites
-- en créant les sorties (en tant que db) avec un starts_at relatif à now(), et
-- les balayages sont simulés en appelant les fermetures internes en tant que db.

-- ───── Utilitaires locaux ─────
-- Sortie créée en tant que db (créateur inscrit 'accepted'), décalage relatif à now().
EXECUTE $p$CREATE FUNCTION pg_temp.pr_act(p_label text, p_creator text, p_start interval, p_dur interval,
    p_status text, p_vis text DEFAULT 'public', p_rp boolean DEFAULT true, p_demo boolean DEFAULT false)
  RETURNS uuid LANGUAGE plpgsql SET search_path = public, extensions AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting,
      starts_at, duration, visibility, status, requires_presence, is_demo)
    VALUES (pg_temp.id(p_creator), (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test ' || p_label,
      'Tous niveaux', 10, ST_SetSRID(ST_MakePoint(6.6, 44.9), 4326)::geography,
      now() + p_start, p_dur, p_vis, p_status, p_rp, p_demo)
    RETURNING id INTO v;
    INSERT INTO public.participations (activity_id, user_id, status, created_at)
    VALUES (v, pg_temp.id(p_creator), 'accepted', now() - interval '3 days');
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.pr_part(p_act text, p_user text, p_status text DEFAULT 'accepted', p_cp boolean DEFAULT NULL)
  RETURNS uuid LANGUAGE plpgsql AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, created_at)
    VALUES (pg_temp.id(p_act), pg_temp.id(p_user), p_status, p_cp, now() - interval '3 days')
    ON CONFLICT (user_id, activity_id) DO UPDATE SET status = EXCLUDED.status, confirmed_present = EXCLUDED.confirmed_present
    RETURNING id INTO v;
    PERFORM pg_temp.put(p_act || ':' || p_user, v::text);
    RETURN v;
  END $b$$p$;

-- Fixe confirmed_present (db).
EXECUTE $p$CREATE FUNCTION pg_temp.pr_setcp(p_act text, p_user text, p_cp boolean) RETURNS void
  LANGUAGE sql AS $b$
  UPDATE public.participations SET confirmed_present = p_cp
  WHERE activity_id = pg_temp.id(p_act) AND user_id = pg_temp.id(p_user) $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.pr_cp(p_act text, p_user text) RETURNS text
  LANGUAGE sql AS $b$
  SELECT coalesce(confirmed_present::text, 'null') FROM public.participations
  WHERE activity_id = pg_temp.id(p_act) AND user_id = pg_temp.id(p_user) $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.pr_score(p_user text) RETURNS text
  LANGUAGE sql AS $b$ SELECT coalesce(reliability_score::text, 'null') FROM public.users WHERE id = pg_temp.id(p_user) $b$$p$;

-- Fait « passer le temps » : recule la sortie de p_by (db, contourne le verrou).
EXECUTE $p$CREATE FUNCTION pg_temp.pr_shift(p_act text, p_by interval) RETURNS void
  LANGUAGE plpgsql AS $b$
  BEGIN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE public.activities SET starts_at = starts_at - p_by WHERE id = pg_temp.id(p_act);
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END $b$$p$;

-- Vote inséré directement (db), déjà compté ou non.
EXECUTE $p$CREATE FUNCTION pg_temp.pr_vote(p_voter text, p_voted text, p_act text, p_key text, p_counted boolean DEFAULT true)
  RETURNS void LANGUAGE sql AS $b$
  INSERT INTO public.reputation_votes (voter_id, voted_id, activity_id, badge_key, created_at, counted_at)
  VALUES (pg_temp.id(p_voter), pg_temp.id(p_voted), pg_temp.id(p_act), p_key, now(), CASE WHEN p_counted THEN now() END) $b$$p$;

-- Passe si l'instruction réussit OU lève une erreur métier propre (junto.* / générique),
-- échoue sur une erreur brute (contrainte, etc.).
EXECUTE $p$CREATE FUNCTION pg_temp.pr_noraw(p_name text, p_sql text, p_known text DEFAULT NULL) RETURNS void
  LANGUAGE plpgsql AS $b$
  BEGIN
    BEGIN
      PERFORM pg_temp.run(p_sql);
    EXCEPTION WHEN OTHERS THEN
      PERFORM pg_temp.rec(p_name, SQLERRM ~ '^(junto\.|Operation not permitted)', 'error: ' || SQLERRM, p_known);
      RETURN;
    END;
    PERFORM pg_temp.rec(p_name, true, 'ok', p_known);
  END $b$$p$;

-- ───── Comptes ─────
PERFORM pg_temp.user('crea', 'tos');
PERFORM pg_temp.user('p1', 'tos');
PERFORM pg_temp.user('p2', 'tos');
PERFORM pg_temp.user('p3', 'tos');
PERFORM pg_temp.user('str', 'tos');
PERFORM pg_temp.user('sus', 'tos,suspended');
PERFORM pg_temp.user('susc', 'tos,suspended');
PERFORM pg_temp.user('dem', 'tos,demo');
PERFORM pg_temp.user('dem2', 'tos,demo');
PERFORM pg_temp.user('w1', 'tos');
PERFORM pg_temp.user('rl', 'tos');
PERFORM pg_temp.user('s1', 'tos');
PERFORM pg_temp.user('s2', 'tos');
PERFORM pg_temp.user('q1', 'tos');
PERFORM pg_temp.user('q2', 'tos');
PERFORM pg_temp.user('r1', 'tos');
PERFORM pg_temp.user('r2', 'tos');
PERFORM pg_temp.user('x1', 'tos');
PERFORM pg_temp.user('x2', 'tos');
PERFORM pg_temp.user('x3', 'tos');
PERFORM pg_temp.user('x4', 'tos');
PERFORM pg_temp.user('rr', 'tos');
PERFORM pg_temp.user('so', 'tos');
PERFORM pg_temp.user('lc', 'tos');
PERFORM pg_temp.user('lc2', 'tos');
PERFORM pg_temp.user('lc3', 'tos');
PERFORM pg_temp.user('lc4', 'tos');
PERFORM pg_temp.user('lc5', 'tos');
PERFORM pg_temp.user('lv', 'tos');
PERFORM pg_temp.user('lv2', 'tos');
PERFORM pg_temp.user('tv', 'tos');
PERFORM pg_temp.user('tv2', 'tos');
PERFORM pg_temp.user('pv', 'tos');

-- ───── Exposition des fonctions internes ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('close_presence_window_for non appelable par un compte',
  $$SELECT has_function_privilege('authenticated', 'public.close_presence_window_for(uuid)', 'EXECUTE')::text$$, 'false');
PERFORM pg_temp.eq('close_due_presence_windows non appelable par un compte',
  $$SELECT has_function_privilege('authenticated', 'public.close_due_presence_windows()', 'EXECUTE')::text$$, 'false');
PERFORM pg_temp.eq('recalculate_reliability_score non appelable par un compte',
  $$SELECT has_function_privilege('authenticated', 'public.recalculate_reliability_score(uuid)', 'EXECUTE')::text$$, 'false');
PERFORM pg_temp.eq('award_badge_progression non appelable par un compte',
  $$SELECT has_function_privilege('authenticated', 'public.award_badge_progression(uuid, boolean)', 'EXECUTE')::text$$, 'false');
-- transition_single_activity reste appelable : elle fait ce que fait la tâche minute ; PR-1 est fermé
-- par la garde « organisateur suspendu » de close_presence_window_for (00491).
PERFORM pg_temp.eq('check_activity_transitions non appelable par un compte',
  $$SELECT has_function_privilege('authenticated', 'public.check_activity_transitions()', 'EXECUTE')::text$$, 'false');

PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne peut pas confirmer une présence par géo',
  format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, gen_random_uuid()), 'permission denied');
PERFORM pg_temp.denied('anon ne peut pas voter',
  format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p1'), gen_random_uuid()), 'permission denied');
PERFORM pg_temp.denied('anon ne lit pas la réputation',
  format($$SELECT count(*)::text FROM public.get_user_reputation(%L)$$, pg_temp.id('p1')), 'permission denied');
PERFORM pg_temp.denied('anon ne lit pas les stats publiques',
  format($$SELECT count(*)::text FROM public.get_user_public_stats(%L)$$, pg_temp.id('p1')), 'permission denied');

-- ═════ Présence : QR (jeton) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_act('A', 'crea', interval '-5 minutes', interval '2 hours', 'in_progress');
PERFORM pg_temp.pr_part('A', 'p1');
PERFORM pg_temp.pr_part('A', 'p2');
PERFORM pg_temp.pr_part('A', 'p3');
PERFORM pg_temp.pr_part('A', 'sus');
PERFORM pg_temp.pr_part('A', 'dem2');
PERFORM pg_temp.pr_act('F', 'crea', interval '2 days', interval '2 hours', 'published');
PERFORM pg_temp.pr_part('F', 'p1');
PERFORM pg_temp.pr_act('NP', 'crea', interval '-5 minutes', interval '2 hours', 'in_progress', 'public', false);
PERFORM pg_temp.pr_part('NP', 'p1');
PERFORM pg_temp.pr_act('OLD', 'crea', interval '-8 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('OLD', 'p1');
PERFORM pg_temp.pr_act('DM', 'dem', interval '-5 minutes', interval '2 hours', 'in_progress', 'public', true, true);
PERFORM pg_temp.pr_part('DM', 'dem2');
PERFORM pg_temp.pr_act('CX', 'crea', interval '-5 minutes', interval '2 hours', 'cancelled');
PERFORM pg_temp.pr_part('CX', 'p1');
PERFORM pg_temp.pr_act('B', 'p3', interval '-5 minutes', interval '2 hours', 'in_progress');
PERFORM pg_temp.pr_part('B', 'p1');
PERFORM pg_temp.pr_act('S', 'susc', interval '-30 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('S', 's1', 'accepted', true);
PERFORM pg_temp.pr_part('S', 's2');
PERFORM pg_temp.pr_setcp('S', 'susc', true);
INSERT INTO public.presence_tokens (token, activity_id, expires_at) VALUES ('deadbeef0001', pg_temp.id('A'), now() - interval '1 minute');

PERFORM pg_temp.as_('crea');
PERFORM pg_temp.put('tokA', pg_temp.ok('le créateur génère un QR de présence',
  format($$SELECT public.create_presence_token(%L)$$, pg_temp.id('A'))));
PERFORM pg_temp.eq('le jeton fait 12 caractères', format($$SELECT char_length(%L)::text$$, pg_temp.get('tokA')), '12');
PERFORM pg_temp.eq('un second appel renvoie le même jeton encore frais',
  format($$SELECT public.create_presence_token(%L)$$, pg_temp.id('A')), pg_temp.get('tokA'));
PERFORM pg_temp.denied('pas de QR sur une sortie future (hors fenêtre)',
  format($$SELECT public.create_presence_token(%L)$$, pg_temp.id('F')), 'junto\.presence_token_window_closed');
PERFORM pg_temp.denied('pas de QR sur une sortie sans validation de présence',
  format($$SELECT public.create_presence_token(%L)$$, pg_temp.id('NP')), 'junto\.presence_unavailable');
PERFORM pg_temp.denied('pas de QR sur une sortie annulée',
  format($$SELECT public.create_presence_token(%L)$$, pg_temp.id('CX')), 'junto\.presence_unavailable');
PERFORM pg_temp.denied('pas de QR après fin + 3 h',
  format($$SELECT public.create_presence_token(%L)$$, pg_temp.id('OLD')), 'junto\.presence_token_window_closed');
PERFORM pg_temp.eq('le créateur ne lit pas presence_tokens en direct', $$SELECT count(*)::text FROM public.presence_tokens$$, '0');
PERFORM pg_temp.denied('le créateur ne peut pas insérer un jeton en direct',
  format($$INSERT INTO public.presence_tokens (token, activity_id, expires_at) VALUES ('aaaabbbbcccc', %L, now() + interval '1 day')$$, pg_temp.id('A')));
PERFORM pg_temp.as_('p1');
PERFORM pg_temp.denied('un participant ne génère pas de QR', format($$SELECT public.create_presence_token(%L)$$, pg_temp.id('A')));
PERFORM pg_temp.as_('dem');
PERFORM pg_temp.denied('pas de QR sur une sortie démo', format($$SELECT public.create_presence_token(%L)$$, pg_temp.id('DM')));
PERFORM pg_temp.as_('susc');
PERFORM pg_temp.denied('un créateur suspendu ne génère pas de QR', format($$SELECT public.create_presence_token(%L)$$, pg_temp.id('S')));

PERFORM pg_temp.as_('str');
PERFORM pg_temp.denied('un non-participant ne valide pas avec le QR',
  format($$SELECT public.confirm_presence_via_token(%L)::text$$, pg_temp.get('tokA')));
PERFORM pg_temp.as_('p1');
PERFORM pg_temp.denied('jeton inconnu refusé', $$SELECT public.confirm_presence_via_token('000000000000')::text$$, 'junto\.presence_token_invalid');
PERFORM pg_temp.denied('jeton expiré refusé', $$SELECT public.confirm_presence_via_token('deadbeef0001')::text$$, 'junto\.presence_token_invalid');
PERFORM pg_temp.eq('un participant valide sa présence par QR',
  format($$SELECT public.confirm_presence_via_token(%L)::text$$, pg_temp.get('tokA')), pg_temp.get('A'));
PERFORM pg_temp.eq('valider deux fois est idempotent',
  format($$SELECT public.confirm_presence_via_token(%L)::text$$, pg_temp.get('tokA')), pg_temp.get('A'));
PERFORM pg_temp.eq('p1 ne peut pas modifier sa présence en direct (aucune politique UPDATE)',
  format($$WITH u AS (UPDATE public.participations SET confirmed_present = false WHERE activity_id = %L AND user_id = %L RETURNING 1) SELECT count(*)::text FROM u$$, pg_temp.id('A'), pg_temp.id('p1')), '0');
PERFORM pg_temp.as_('sus');
PERFORM pg_temp.denied('un participant suspendu ne valide pas par QR',
  format($$SELECT public.confirm_presence_via_token(%L)::text$$, pg_temp.get('tokA')));
PERFORM pg_temp.as_('crea');
PERFORM pg_temp.eq('le créateur scannant son propre QR : no-op',
  format($$SELECT public.confirm_presence_via_token(%L)::text$$, pg_temp.get('tokA')), pg_temp.get('A'));

PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('présence de p1 enregistrée', format($$SELECT pg_temp.pr_cp('A', 'p1')$$), 'true');
PERFORM pg_temp.eq('règle A : la présence du créateur est validée par celle d''un participant', $$SELECT pg_temp.pr_cp('A', 'crea')$$, 'true');
PERFORM pg_temp.eq('le score de p1 est recalculé', $$SELECT pg_temp.pr_score('p1')$$, '100');
PERFORM pg_temp.eq('une notification « présence confirmée » sans push',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'presence_confirmed' AND data->>'activity_id' = %L AND (data->>'skip_push')::boolean$$,
    pg_temp.id('p1'), pg_temp.get('A')), '1');

-- ═════ Présence : géolocalisation ═════
PERFORM pg_temp.as_('p2');
PERFORM pg_temp.ok('p2 sur le point de rendez-vous : validé', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('A')));
PERFORM pg_temp.ok('géo une seconde fois : idempotent', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('A')));
PERFORM pg_temp.as_('p3');
PERFORM pg_temp.denied('à 8 km : trop loin', format($$SELECT public.confirm_presence_via_geo(%L, 6.7, 44.9)::text$$, pg_temp.id('A')), 'junto\.presence_too_far');
PERFORM pg_temp.denied('à ~200 m : trop loin (seuil 150 m)', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9018)::text$$, pg_temp.id('A')), 'junto\.presence_too_far');
PERFORM pg_temp.denied('capture 1 h avant le départ : hors fenêtre T±15 min',
  format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9, now() - interval '1 hour')::text$$, pg_temp.id('A')), 'junto\.presence_window_closed');
PERFORM pg_temp.denied('capture datée dans le futur refusée',
  format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9, now() + interval '10 minutes')::text$$, pg_temp.id('A')), 'Operation not permitted');
PERFORM pg_temp.ok('à ~100 m : validé', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9009)::text$$, pg_temp.id('A')));
PERFORM pg_temp.denied('géo sur une sortie annulée', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('CX')), 'Operation not permitted|junto\.presence_unavailable');
PERFORM pg_temp.as_('p1');
PERFORM pg_temp.denied('géo sur une sortie annulée (participant)', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('CX')), 'junto\.presence_unavailable');
PERFORM pg_temp.denied('géo sur une sortie sans validation de présence', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('NP')), 'junto\.presence_unavailable');
PERFORM pg_temp.denied('géo sur une sortie future : hors fenêtre', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('F')), 'junto\.presence_window_closed');
PERFORM pg_temp.denied('rejeu hors ligne arrivé après fin + 24 h refusé',
  format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9, now() - interval '30 hours')::text$$, pg_temp.id('S')), 'Operation not permitted|junto\.presence_window_closed');
PERFORM pg_temp.as_('str');
PERFORM pg_temp.denied('un non-participant ne valide pas par géo', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('A')));
PERFORM pg_temp.as_('sus');
PERFORM pg_temp.denied('un participant suspendu ne valide pas par géo', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('A')));
PERFORM pg_temp.as_('dem2');
PERFORM pg_temp.denied('pas de validation géo sur une sortie démo', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('DM')));
PERFORM pg_temp.as_('p3');
PERFORM pg_temp.ok('le créateur (p3 sur B) qui envoie sa position : no-op silencieux', format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9)::text$$, pg_temp.id('B')));

-- Rejeu hors ligne : sortie terminée il y a 18 h, capture faite à T+5 min.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_act('R', 'crea', interval '-20 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('R', 'p2');
PERFORM pg_temp.as_('p2');
PERFORM pg_temp.ok('rejeu hors ligne (capture à T+5 min, arrivée à fin+18 h) accepté',
  format($$SELECT public.confirm_presence_via_geo(%L, 6.6, 44.9, now() - interval '19 hours 55 minutes')::text$$, pg_temp.id('R')));

PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('présence géo de p2 enregistrée', $$SELECT pg_temp.pr_cp('A', 'p2')$$, 'true');
PERFORM pg_temp.eq('présence géo de p3 (100 m) enregistrée', $$SELECT pg_temp.pr_cp('A', 'p3')$$, 'true');
PERFORM pg_temp.eq('le créateur de B reste non validé', $$SELECT pg_temp.pr_cp('B', 'p3')$$, 'null');
PERFORM pg_temp.eq('présence rejouée enregistrée', $$SELECT pg_temp.pr_cp('R', 'p2')$$, 'true');
PERFORM pg_temp.eq('règle A sur rejeu : créateur crédité', $$SELECT pg_temp.pr_cp('R', 'crea')$$, 'true');
PERFORM pg_temp.eq('le suspendu reste non validé', $$SELECT pg_temp.pr_cp('A', 'sus')$$, 'null');

-- Témoignage par les pairs : désactivé.
PERFORM pg_temp.as_('p1');
PERFORM pg_temp.denied('peer_validate_presence désactivé',
  format($$SELECT public.peer_validate_presence(%L, %L)::text$$, pg_temp.id('p2'), pg_temp.id('A')), 'junto\.peer_review_unavailable');

-- ═════ Votes de réputation ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_act('V', 'crea', interval '-3 hours', interval '2 hours', 'completed');   -- fenêtre de vote ouverte
PERFORM pg_temp.pr_part('V', 'p1');
PERFORM pg_temp.pr_part('V', 'p2');
PERFORM pg_temp.pr_part('V', 'p3');
PERFORM pg_temp.pr_part('V', 'sus');
PERFORM pg_temp.pr_part('V', 'w1', 'withdrawn');
PERFORM pg_temp.pr_act('V2', 'crea', interval '-2 hours', interval '2 hours', 'completed');  -- fin = maintenant : pas encore ouverte
PERFORM pg_temp.pr_part('V2', 'p1');
PERFORM pg_temp.pr_part('V2', 'p2');
PERFORM pg_temp.pr_act('V3', 'crea', interval '-30 hours', interval '2 hours', 'completed'); -- fermée
PERFORM pg_temp.pr_part('V3', 'p1');
PERFORM pg_temp.pr_part('V3', 'p2');
PERFORM pg_temp.pr_act('V4', 'crea', interval '-3 hours', interval '5 hours', 'in_progress');
PERFORM pg_temp.pr_part('V4', 'p1');
PERFORM pg_temp.pr_part('V4', 'p2');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('p3'), pg_temp.id('p2'));
-- 20 votes récents de 'rl' : quota atteint.
INSERT INTO public.reputation_votes (voter_id, voted_id, activity_id, badge_key, created_at)
SELECT pg_temp.id('rl'), pg_temp.id('p1'), pg_temp.id('V'), 'rl_' || g, now() FROM generate_series(1, 20) g;

PERFORM pg_temp.as_('p2');
PERFORM pg_temp.ok('p2 déclare son niveau en randonnée', $$SELECT public.set_sport_level('hiking', 'intermédiaire')::text$$);

PERFORM pg_temp.as_('p1');
PERFORM pg_temp.ok('p1 donne « ponctuel » à p2', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.ok('p1 donne « préparé » à p2', format($$SELECT public.give_reputation_badge(%L, %L, 'prepared')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.pr_noraw('voter deux fois le même badge ne remonte pas d''erreur brute',
  format($$SELECT public.give_reputation_badge(%L, %L, 'prepared')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.denied('on ne vote pas pour soi-même', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p1'), pg_temp.id('V')));
PERFORM pg_temp.denied('on ne vote pas pour un non-participant', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('str'), pg_temp.id('V')));
PERFORM pg_temp.denied('on ne vote pas pour un participant qui s''est retiré', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('w1'), pg_temp.id('V')));
PERFORM pg_temp.denied('badge inconnu refusé', format($$SELECT public.give_reputation_badge(%L, %L, 'kudos')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.denied('badge non votable (late_canceller) refusé', format($$SELECT public.give_reputation_badge(%L, %L, 'late_canceller')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.denied('vote de niveau sans niveau déclaré refusé', format($$SELECT public.give_reputation_badge(%L, %L, 'level_right')::text$$, pg_temp.id('p3'), pg_temp.id('V')));
PERFORM pg_temp.ok('vote de niveau « juste » pour p2', format($$SELECT public.give_reputation_badge(%L, %L, 'level_right')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.ok('vote de niveau « surestimé » remplace le précédent', format($$SELECT public.give_reputation_badge(%L, %L, 'level_over')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.ok('p1 donne « conciliant » à p2', format($$SELECT public.give_reputation_badge(%L, %L, 'conciliant')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.ok('p1 retire « conciliant »', format($$SELECT public.revoke_reputation_badge(%L, %L, 'conciliant')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.denied('retrait sur soi-même refusé', format($$SELECT public.revoke_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p1'), pg_temp.id('V')));
PERFORM pg_temp.denied('vote avant fin + 15 min refusé', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p2'), pg_temp.id('V2')), 'junto\.badge_window_not_open');
PERFORM pg_temp.denied('vote après fin + 24 h refusé', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p2'), pg_temp.id('V3')), 'junto\.badge_window_closed');
PERFORM pg_temp.denied('retrait après fin + 24 h refusé', format($$SELECT public.revoke_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p2'), pg_temp.id('V3')), 'junto\.badge_window_closed');
PERFORM pg_temp.denied('vote sur une sortie en cours refusé', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p2'), pg_temp.id('V4')));
PERFORM pg_temp.denied('vote direct dans reputation_votes refusé',
  format($$INSERT INTO public.reputation_votes (voter_id, voted_id, activity_id, badge_key, counted_at) VALUES (%L, %L, %L, 'punctual', now())$$,
    pg_temp.id('p1'), pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.as_('str');
PERFORM pg_temp.denied('un non-participant ne vote pas', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p1'), pg_temp.id('V')));
PERFORM pg_temp.eq('un tiers ne lit pas les votes en direct', $$SELECT count(*)::text FROM public.reputation_votes$$, '0');
PERFORM pg_temp.as_('p2');
PERFORM pg_temp.denied('vote vers quelqu''un qui m''a bloqué refusé', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p3'), pg_temp.id('V')));
PERFORM pg_temp.as_('p3');
PERFORM pg_temp.denied('vote vers quelqu''un que j''ai bloqué refusé', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p2'), pg_temp.id('V')));
PERFORM pg_temp.as_('sus');
PERFORM pg_temp.denied('un participant suspendu ne vote pas', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p1'), pg_temp.id('V')));
PERFORM pg_temp.as_('rl');
PERFORM pg_temp.denied('quota de 20 votes / 24 h', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('p2'), pg_temp.id('V')), 'junto\.badge_rate_limit');

PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('un seul vote de niveau de p1 vers p2 (le dernier)',
  format($$SELECT string_agg(badge_key, ',') FROM public.reputation_votes WHERE voter_id = %L AND voted_id = %L AND activity_id = %L AND badge_key LIKE 'level%%'$$,
    pg_temp.id('p1'), pg_temp.id('p2'), pg_temp.id('V')), 'level_over');
PERFORM pg_temp.eq('« conciliant » retiré',
  format($$SELECT count(*)::text FROM public.reputation_votes WHERE voter_id = %L AND badge_key = 'conciliant'$$, pg_temp.id('p1')), '0');
PERFORM pg_temp.eq('les votes ne sont pas encore comptés',
  format($$SELECT count(*)::text FROM public.reputation_votes WHERE voter_id = %L AND counted_at IS NOT NULL$$, pg_temp.id('p1')), '0');
PERFORM pg_temp.as_('str');
PERFORM pg_temp.eq('un vote non compté n''apparaît pas dans la réputation',
  format($$SELECT count(*)::text FROM public.get_user_reputation(%L)$$, pg_temp.id('p2')), '0');

-- Fin + 24 h passée → la fermeture compte les votes entre présents et pose les absences.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_setcp('V', 'crea', true);
PERFORM pg_temp.pr_setcp('V', 'p1', true);
PERFORM pg_temp.pr_setcp('V', 'p2', true);
PERFORM pg_temp.pr_shift('V', interval '30 hours');
PERFORM pg_temp.ok('fermeture de la fenêtre de V', format($$SELECT public.close_presence_window_for(%L)::text$$, pg_temp.id('V')));
PERFORM pg_temp.eq('votes entre présents comptés',
  format($$SELECT count(*)::text FROM public.reputation_votes WHERE voter_id = %L AND voted_id = %L AND counted_at IS NOT NULL$$, pg_temp.id('p1'), pg_temp.id('p2')), '3');
PERFORM pg_temp.eq('votes du non-présent (rl) non comptés',
  format($$SELECT count(*)::text FROM public.reputation_votes WHERE voter_id = %L AND counted_at IS NOT NULL$$, pg_temp.id('rl')), '0');
PERFORM pg_temp.eq('3+ avec une présence : le non-validé est marqué absent', $$SELECT pg_temp.pr_cp('V', 'p3')$$, 'false');
PERFORM pg_temp.eq('le participant retiré n''est pas marqué', $$SELECT pg_temp.pr_cp('V', 'w1')$$, 'null');
PERFORM pg_temp.eq('la sortie reste terminée', format($$SELECT status FROM public.activities WHERE id = %L$$, pg_temp.id('V')), 'completed');
-- Vote négatif compté (pour les lectures).
PERFORM pg_temp.pr_vote('p1', 'p2', 'V', 'aggressive');

-- ───── Lectures de réputation ─────
PERFORM pg_temp.as_('str');
PERFORM pg_temp.eq('réputation de p2 : « ponctuel » = 1',
  format($$SELECT vote_count::text FROM public.get_user_reputation(%L) WHERE badge_key = 'punctual'$$, pg_temp.id('p2')), '1');
PERFORM pg_temp.eq('les votes de niveau ne figurent pas dans la réputation',
  format($$SELECT count(*)::text FROM public.get_user_reputation(%L) WHERE badge_key LIKE 'level%%'$$, pg_temp.id('p2')), '0');
PERFORM pg_temp.eq('votes de niveau de p2 en randonnée : 1 « surestimé »',
  format($$SELECT level_over::text || '/' || level_right::text FROM public.get_user_sport_level_votes(%L) WHERE sport_key = 'hiking'$$, pg_temp.id('p2')), '1/0');
PERFORM pg_temp.eq('get_voters_for_badge ne liste pas les auteurs d''un vote négatif',
  format($$SELECT count(*)::text FROM public.get_voters_for_badge(%L, 'aggressive')$$, pg_temp.id('p2')), '0');
PERFORM pg_temp.eq('get_voters_for_badge applique un seuil (1 seul votant : rien)',
  format($$SELECT count(*)::text FROM public.get_voters_for_badge(%L, 'punctual')$$, pg_temp.id('p2')), '0');
PERFORM pg_temp.as_('p2');
PERFORM pg_temp.eq('le visé ne voit pas qui a voté négativement contre lui',
  $$SELECT count(*)::text FROM public.reputation_votes WHERE badge_key = 'aggressive'$$, '0');
PERFORM pg_temp.as_('sus');
PERFORM pg_temp.eq('un suspendu ne lit pas la réputation', format($$SELECT count(*)::text FROM public.get_user_reputation(%L)$$, pg_temp.id('p2')), '0');
PERFORM pg_temp.eq('un suspendu ne lit pas les votants', format($$SELECT count(*)::text FROM public.get_voters_for_badge(%L, 'punctual')$$, pg_temp.id('p2')), '0');
PERFORM pg_temp.eq('un suspendu ne lit pas les badges mis en avant', format($$SELECT count(*)::text FROM public.get_top_vouched_badges(ARRAY[%L]::uuid[])$$, pg_temp.id('p2')), '0');

-- Badges mis en avant : seuil 5.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_vote(v, 'tv2', 'V', 'punctual') FROM unnest(ARRAY['crea', 'p1', 'p2', 'p3', 'str']) v;
PERFORM pg_temp.pr_vote('p1', 'tv2', 'V', 'prudent');
PERFORM pg_temp.pr_act('K' || g, 'crea', interval '-5 days', interval '2 hours', 'completed') FROM generate_series(1, 5) g;
PERFORM pg_temp.pr_vote('p1', 'tv', 'K' || g, 'punctual') FROM generate_series(1, 5) g;
PERFORM pg_temp.as_('str');
PERFORM pg_temp.eq('5 votants distincts : « ponctuel » mis en avant',
  format($$SELECT badge_key || ':' || vote_count FROM public.get_top_vouched_badges(ARRAY[%L]::uuid[])$$, pg_temp.id('tv2')), 'punctual:5');
PERFORM pg_temp.eq('le seuil compte les votants, pas les votes (1 votant × 5 sorties : rien)',
  format($$SELECT count(*)::text FROM public.get_top_vouched_badges(ARRAY[%L]::uuid[])$$, pg_temp.id('tv')), '0');
PERFORM pg_temp.eq('PR-3 : 5 personnes ont donné « ponctuel » : les votants s''affichent',
  format($$SELECT count(*)::text FROM public.get_voters_for_badge(%L, 'punctual')$$, pg_temp.id('tv2')), '5');
PERFORM pg_temp.eq('PR-11 : la réputation compte des personnes (1 personne × 5 sorties = 1)',
  format($$SELECT vote_count::text FROM public.get_user_reputation(%L) WHERE badge_key = 'punctual'$$, pg_temp.id('tv')), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('neg', 'tos');
PERFORM pg_temp.pr_vote(v, 'neg', 'V', 'aggressive') FROM unnest(ARRAY['crea', 'p1']) v;
PERFORM pg_temp.as_('neg');
PERFORM pg_temp.eq('PR-3 : sous le seuil, la personne visée ne voit pas le trait négatif (pas d''élimination)',
  format($$SELECT count(*)::text FROM public.get_user_reputation(%L) WHERE badge_key = 'aggressive'$$, pg_temp.id('neg')), '0');
PERFORM pg_temp.as_('str');

-- Rideau démo sur les lectures de vote.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_vote(v, 'dem', 'V', 'punctual') FROM unnest(ARRAY['crea', 'p1', 'p2', 'p3', 'str']) v;
PERFORM pg_temp.pr_vote('p1', 'dem', 'V', 'level_right');
PERFORM pg_temp.as_('str');
PERFORM pg_temp.eq('rideau démo : get_user_reputation', format($$SELECT count(*)::text FROM public.get_user_reputation(%L)$$, pg_temp.id('dem')), '0');
PERFORM pg_temp.eq('rideau démo : get_voters_for_badge', format($$SELECT count(*)::text FROM public.get_voters_for_badge(%L, 'punctual')$$, pg_temp.id('dem')), '0');
PERFORM pg_temp.eq('rideau démo : get_top_vouched_badges', format($$SELECT count(*)::text FROM public.get_top_vouched_badges(ARRAY[%L]::uuid[])$$, pg_temp.id('dem')), '0');
PERFORM pg_temp.eq('rideau démo : get_user_sport_level_votes', format($$SELECT count(*)::text FROM public.get_user_sport_level_votes(%L)$$, pg_temp.id('dem')), '0');

-- ═════ Fermeture de la fenêtre de présence (règles 2 / 3+) ═════
PERFORM pg_temp.as_('db');
-- 2 personnes, aucun non-créateur validé → expirée, validation isolée effacée.
PERFORM pg_temp.pr_act('C2a', 'crea', interval '-30 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('C2a', 'x1');
PERFORM pg_temp.pr_setcp('C2a', 'crea', true);
-- 2 personnes, le participant validé → rien ne change.
PERFORM pg_temp.pr_act('C2b', 'crea', interval '-30 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('C2b', 'x1', 'accepted', true);
PERFORM pg_temp.pr_setcp('C2b', 'crea', true);
-- 3+, personne validé → expirée, neutre.
PERFORM pg_temp.pr_act('C3a', 'crea', interval '-30 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('C3a', 'x1');
PERFORM pg_temp.pr_part('C3a', 'x3');
-- 3+, une présence → les autres absents.
PERFORM pg_temp.pr_act('C3b', 'crea', interval '-30 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('C3b', 'x1', 'accepted', true);
PERFORM pg_temp.pr_part('C3b', 'x2');
PERFORM pg_temp.pr_setcp('C3b', 'crea', true);
-- Solo, supprimée, sans validation, trop tôt : aucun effet.
PERFORM pg_temp.pr_act('Csolo', 'x4', interval '-30 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_act('Cdel', 'crea', interval '-30 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('Cdel', 'x1', 'accepted', true);
PERFORM pg_temp.pr_part('Cdel', 'x3');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET deleted_at = now() WHERE id = pg_temp.id('Cdel');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.pr_act('Cnp', 'crea', interval '-30 hours', interval '2 hours', 'completed', 'public', false);
PERFORM pg_temp.pr_part('Cnp', 'x1', 'accepted', true);
PERFORM pg_temp.pr_part('Cnp', 'x3');
PERFORM pg_temp.pr_act('Cearly', 'crea', interval '-5 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('Cearly', 'x1', 'accepted', true);
PERFORM pg_temp.pr_part('Cearly', 'x3');

PERFORM public.close_presence_window_for(pg_temp.id(l)) FROM unnest(ARRAY['C2a', 'C2b', 'C3a', 'C3b', 'Csolo', 'Cdel', 'Cnp', 'Cearly']) l;
PERFORM pg_temp.eq('2 personnes sans preuve : sortie expirée', format($$SELECT status FROM public.activities WHERE id = %L$$, pg_temp.id('C2a')), 'expired');
PERFORM pg_temp.eq('2 personnes sans preuve : validation isolée du créateur effacée', $$SELECT pg_temp.pr_cp('C2a', 'crea')$$, 'null');
PERFORM pg_temp.eq('2 personnes sans preuve : pas d''absence posée', $$SELECT pg_temp.pr_cp('C2a', 'x1')$$, 'null');
PERFORM pg_temp.eq('2 personnes validées : reste terminée', format($$SELECT status FROM public.activities WHERE id = %L$$, pg_temp.id('C2b')), 'completed');
PERFORM pg_temp.eq('2 personnes validées : présence conservée', $$SELECT pg_temp.pr_cp('C2b', 'x1')$$, 'true');
PERFORM pg_temp.eq('3+ sans aucune preuve : sortie expirée', format($$SELECT status FROM public.activities WHERE id = %L$$, pg_temp.id('C3a')), 'expired');
PERFORM pg_temp.eq('3+ sans aucune preuve : aucune absence', $$SELECT pg_temp.pr_cp('C3a', 'x3')$$, 'null');
PERFORM pg_temp.eq('3+ avec preuve : absence posée', $$SELECT pg_temp.pr_cp('C3b', 'x2')$$, 'false');
PERFORM pg_temp.eq('l''absent voit son score recalculé (1 absence → 50)', $$SELECT pg_temp.pr_score('x2')$$, '50');
PERFORM pg_temp.eq('solo : rien', $$SELECT pg_temp.pr_cp('Csolo', 'x4')$$, 'null');
PERFORM pg_temp.eq('sortie supprimée : aucune absence', $$SELECT pg_temp.pr_cp('Cdel', 'x3')$$, 'null');
PERFORM pg_temp.eq('sortie sans validation de présence : aucune absence', $$SELECT pg_temp.pr_cp('Cnp', 'x3')$$, 'null');
PERFORM pg_temp.eq('avant fin + 24 h : aucune absence', $$SELECT pg_temp.pr_cp('Cearly', 'x3')$$, 'null');

-- PR-1 : créateur suspendu, n'importe qui déclenche la fermeture.
PERFORM pg_temp.as_('str');
PERFORM pg_temp.ok('un tiers appelle transition_single_activity sur la sortie du suspendu',
  format($$SELECT coalesce(public.transition_single_activity(%L), 'null')$$, pg_temp.id('S')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('créateur suspendu : aucune absence posée sur ses participants', $$SELECT pg_temp.pr_cp('S', 's2')$$, 'null');
-- H2 (00495) : réactivé plus tard, l'organisateur ne fait pas tomber d'absences après coup.
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = NULL WHERE id = pg_temp.id('susc');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.pr_shift('S', interval '2 days');
PERFORM public.close_due_presence_windows();
PERFORM pg_temp.eq('organisateur réactivé après coup : toujours aucune absence', $$SELECT pg_temp.pr_cp('S', 's2')$$, 'null');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = now() WHERE id = pg_temp.id('susc');
PERFORM set_config('junto.bypass_lock', 'false', true);

-- PR-2 : tout le monde présent → le balayage ne compte jamais les votes.
PERFORM pg_temp.pr_act('P2', 'crea', interval '-3 hours', interval '2 hours', 'completed');
PERFORM pg_temp.pr_part('P2', 'q1', 'accepted', true);
PERFORM pg_temp.pr_part('P2', 'q2', 'accepted', true);
PERFORM pg_temp.pr_setcp('P2', 'crea', true);
-- BR-2 : sortie sans validation de présence → votes jamais comptés.
PERFORM pg_temp.pr_act('NPV', 'crea', interval '-3 hours', interval '2 hours', 'completed', 'public', false);
PERFORM pg_temp.pr_part('NPV', 'r1');
PERFORM pg_temp.pr_part('NPV', 'r2');
PERFORM pg_temp.as_('q1');
PERFORM pg_temp.ok('q1 vote pour q2', format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('q2'), pg_temp.id('P2')));
PERFORM pg_temp.as_('r1');
PERFORM pg_temp.ok('r1 vote pour r2 (sortie sans présence)', format($$SELECT public.give_reputation_badge(%L, %L, 'prudent')::text$$, pg_temp.id('r2'), pg_temp.id('NPV')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_shift('P2', interval '30 hours');
PERFORM pg_temp.pr_shift('NPV', interval '30 hours');
PERFORM public.close_due_presence_windows();
PERFORM pg_temp.eq('sortie où tous sont présents : le balayage compte les votes',
  format($$SELECT (counted_at IS NOT NULL)::text FROM public.reputation_votes WHERE voter_id = %L$$, pg_temp.id('q1')), 'true');
PERFORM public.close_presence_window_for(pg_temp.id('P2'));
PERFORM pg_temp.eq('la fermeture directe, elle, compte ces votes',
  format($$SELECT (counted_at IS NOT NULL)::text FROM public.reputation_votes WHERE voter_id = %L$$, pg_temp.id('q1')), 'true');
PERFORM public.close_presence_window_for(pg_temp.id('NPV'));
-- BR-2 : les votes d'une sortie sans validation de présence ne sont pas comptés (00495, décision Scott
-- en attente : ne plus les solliciter, ou les compter malgré le risque de réputation fabriquée).
PERFORM pg_temp.eq('sortie sans validation de présence : votes non comptés (pas de réputation fabriquée)',
  format($$SELECT (counted_at IS NULL)::text FROM public.reputation_votes WHERE voter_id = %L$$, pg_temp.id('r1')), 'true');

-- ═════ Score de fiabilité ═════
-- rr : 2 présences + 1 absence → (1+2)/(1+3) = 75.
PERFORM pg_temp.pr_act('RR' || g, 'crea', interval '-10 days' - g * interval '1 day', interval '2 hours', 'completed') FROM generate_series(1, 3) g;
PERFORM pg_temp.pr_part('RR1', 'rr', 'accepted', true);
PERFORM pg_temp.pr_part('RR2', 'rr', 'accepted', true);
PERFORM pg_temp.pr_part('RR3', 'rr', 'accepted', false);
PERFORM public.recalculate_reliability_score(pg_temp.id('rr'));
PERFORM pg_temp.eq('2 présences + 1 absence → 75', $$SELECT pg_temp.pr_score('rr')$$, '75');
-- so : validation sur sa sortie solo ignorée + 1 absence ailleurs → 50 (pas 66,7).
PERFORM pg_temp.pr_act('SO', 'so', interval '-10 days', interval '2 hours', 'completed');
PERFORM pg_temp.pr_setcp('SO', 'so', true);
PERFORM pg_temp.pr_part('RR1', 'so', 'accepted', false);
PERFORM public.recalculate_reliability_score(pg_temp.id('so'));
PERFORM pg_temp.eq('la validation d''une sortie solo ne compte pas', $$SELECT pg_temp.pr_score('so')$$, '50');

-- ───── Statistiques, trophées, niveaux par sport ─────
PERFORM pg_temp.as_('str');
PERFORM pg_temp.eq('stats publiques : les absences ne comptent pas comme sorties',
  format($$SELECT total_activities::text FROM public.get_user_public_stats(%L)$$, pg_temp.id('rr')), '2');
PERFORM pg_temp.eq('stats publiques : palier de fiabilité', format($$SELECT reliability_tier FROM public.get_user_public_stats(%L)$$, pg_temp.id('rr')),
  (SELECT public.reliability_tier(75)));
PERFORM pg_temp.eq('le score brut n''est pas renvoyé par get_user_public_stats',
  format($$SELECT coalesce(reliability_score::text, 'null') FROM public.get_user_public_stats(%L)$$, pg_temp.id('rr')), 'null');
PERFORM pg_temp.eq('trophées : les absences ne comptent pas comme sorties rejointes',
  format($$SELECT count::text FROM public.get_user_trophies(%L) WHERE category = 'joined'$$, pg_temp.id('rr')), '2');
PERFORM pg_temp.eq('niveaux par sport : 1 point en randonnée',
  format($$SELECT dots::text FROM public.get_user_sport_levels(%L) WHERE sport_key = 'hiking'$$, pg_temp.id('rr')), '1');
PERFORM pg_temp.eq('rideau démo : stats publiques', format($$SELECT count(*)::text FROM public.get_user_public_stats(%L)$$, pg_temp.id('dem')), '0');
PERFORM pg_temp.eq('rideau démo : trophées', format($$SELECT count(*)::text FROM public.get_user_trophies(%L)$$, pg_temp.id('dem')), '0');
PERFORM pg_temp.eq('compte suspendu : les stats ne le révèlent pas', format($$SELECT count(*)::text FROM public.get_user_public_stats(%L)$$, pg_temp.id('sus')), '0', 'DX-3');
PERFORM pg_temp.as_('sus');
PERFORM pg_temp.eq('un suspendu ne lit pas les trophées', format($$SELECT count(*)::text FROM public.get_user_trophies(%L)$$, pg_temp.id('rr')), '0');

-- DX-4 : date exacte d'une sortie privée révélée.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_act('PRIV', 'crea', interval '-10 days', interval '2 hours', 'completed', 'private_link');
PERFORM pg_temp.pr_part('PRIV', 'pv', 'accepted', true);
PERFORM pg_temp.put('privAt', (SELECT starts_at::text FROM public.activities WHERE id = pg_temp.id('PRIV')));
PERFORM pg_temp.as_('str');
PERFORM pg_temp.eq('les niveaux par sport ne révèlent pas la date exacte d''une sortie privée',
  format($$SELECT count(*)::text FROM public.get_user_sport_levels(%L) WHERE last_at = %L::timestamptz OR first_at = %L::timestamptz$$,
    pg_temp.id('pv'), pg_temp.get('privAt'), pg_temp.get('privAt')), '0', 'DX-4');

-- DX-1 : absences lisibles par un inconnu.
PERFORM pg_temp.eq('un inconnu voit les participants d''une sortie publique',
  format($$SELECT (count(*) > 0)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('V')), 'true');
PERFORM pg_temp.eq('un inconnu ne voit pas les absences (confirmed_present = false)',
  format($$SELECT count(*)::text FROM public.get_activity_participants(%L) WHERE confirmed_present = false$$, pg_temp.id('V')), '0');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.participations SET confirmed_present = false WHERE activity_id = pg_temp.id('V') AND user_id = pg_temp.id('p3');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('crea');
PERFORM pg_temp.eq('DX-1 : l''organisateur voit l''absence', format($$SELECT count(*)::text FROM public.get_activity_participants(%L) WHERE user_id = %L AND confirmed_present = false$$, pg_temp.id('V'), pg_temp.id('p3')), '1');
PERFORM pg_temp.as_('p3');
PERFORM pg_temp.eq('DX-1 : la personne voit sa propre absence', format($$SELECT count(*)::text FROM public.get_activity_participants(%L) WHERE user_id = %L AND confirmed_present = false$$, pg_temp.id('V'), pg_temp.id('p3')), '1');
PERFORM pg_temp.as_('p1');
PERFORM pg_temp.eq('DX-1 : une co-participante ne voit pas l''absence', format($$SELECT count(*)::text FROM public.get_activity_participants(%L) WHERE confirmed_present = false$$, pg_temp.id('V')), '0');
PERFORM pg_temp.as_('str');
PERFORM pg_temp.eq('DX-1 : un inconnu ne reçoit aucune coche (une absence ne se déduit pas)', format($$SELECT count(*)::text FROM public.get_activity_participants(%L) WHERE confirmed_present IS NOT NULL$$, pg_temp.id('V')), '0');
PERFORM pg_temp.as_('str');
PERFORM pg_temp.eq('la vue public_participants ne montre rien d''autrui',
  format($$SELECT count(*)::text FROM public.public_participants WHERE activity_id = %L$$, pg_temp.id('V')), '0');

-- ═════ Niveau déclaré par sport ═════
PERFORM pg_temp.as_('lv');
PERFORM pg_temp.denied('niveau inconnu refusé', $$SELECT public.set_sport_level('hiking', 'god')::text$$);
PERFORM pg_temp.denied('sport inconnu refusé', $$SELECT public.set_sport_level('no_such_sport', 'débutant')::text$$);
PERFORM pg_temp.ok('premier niveau déclaré', $$SELECT public.set_sport_level('hiking', 'débutant')::text$$);
PERFORM pg_temp.ok('même niveau : no-op', $$SELECT public.set_sport_level('hiking', 'débutant')::text$$);
PERFORM pg_temp.denied('saut de deux niveaux refusé', $$SELECT public.set_sport_level('hiking', 'avancé')::text$$);
PERFORM pg_temp.denied('montée sans votes « juste » refusée', $$SELECT public.set_sport_level('hiking', 'intermédiaire')::text$$, 'junto\.level_up_locked');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('niveau enregistré', format($$SELECT levels_per_sport->>'hiking' FROM public.users WHERE id = %L$$, pg_temp.id('lv')), 'débutant');
PERFORM pg_temp.eq('sport ajouté aux sports du profil', format($$SELECT (sports ? 'hiking')::text FROM public.users WHERE id = %L$$, pg_temp.id('lv')), 'true');
PERFORM pg_temp.as_('lv2');
PERFORM pg_temp.ok('lv2 déclare débutant', $$SELECT public.set_sport_level('hiking', 'débutant')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_vote(v, 'lv2', 'V', 'level_right') FROM unnest(ARRAY['crea', 'p1', 'p2']) v;
PERFORM pg_temp.as_('lv2');
PERFORM pg_temp.ok('3 votes « juste » : montée autorisée', $$SELECT public.set_sport_level('hiking', 'intermédiaire')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('les votes de niveau sont remis à zéro après changement',
  format($$SELECT count(*)::text FROM public.reputation_votes WHERE voted_id = %L$$, pg_temp.id('lv2')), '0');
PERFORM pg_temp.as_('lv2');
PERFORM pg_temp.ok('descente d''un niveau toujours possible', $$SELECT public.set_sport_level('hiking', 'débutant')::text$$);
PERFORM pg_temp.as_('sus');
PERFORM pg_temp.denied('un suspendu ne change pas son niveau', $$SELECT public.set_sport_level('hiking', 'débutant')::text$$);

-- ═════ Annulation tardive ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_act('L', 'crea', interval '6 hours', interval '2 hours', 'published');
PERFORM pg_temp.pr_act('L3', 'crea', interval '6 hours', interval '2 hours', 'published', 'approval');
PERFORM pg_temp.pr_act('L4', 'crea', interval '3 days', interval '2 hours', 'published');
PERFORM pg_temp.pr_act('L5', 'crea', interval '6 hours', interval '2 hours', 'published', 'public', false);

PERFORM pg_temp.as_('lc');
PERFORM pg_temp.eq('lc rejoint L', format($$SELECT public.join_activity(%L)$$, pg_temp.id('L')), 'accepted');
PERFORM pg_temp.ok('lc quitte L à moins de 12 h', format($$SELECT public.leave_activity(%L, 'imprévu')::text$$, pg_temp.id('L')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('départ tardif : pénalité (score 50)', $$SELECT pg_temp.pr_score('lc')$$, '50');
PERFORM pg_temp.eq('le créateur est notifié du départ tardif',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'participant_left_late' AND data->>'activity_id' = %L$$, pg_temp.id('crea'), pg_temp.get('L')), '1');
PERFORM pg_temp.put('L:lc', (SELECT id::text FROM public.participations WHERE activity_id = pg_temp.id('L') AND user_id = pg_temp.id('lc')));

PERFORM pg_temp.as_('crea');
PERFORM pg_temp.eq('le créateur ne lit pas directement les participations d''autrui (RLS) — l''app passe par get_late_leavers',
  format($$SELECT count(*)::text FROM public.participations WHERE activity_id = %L AND status = 'withdrawn'$$, pg_temp.id('L')), '0');
PERFORM pg_temp.eq('le créateur voit ses départs tardifs via get_late_leavers (PR-6)',
  format($$SELECT (count(*) > 0)::text FROM public.get_late_leavers(%L)$$, pg_temp.id('L')), 'true');
PERFORM pg_temp.as_('p1');
PERFORM pg_temp.denied('un non-créateur ne lève pas la pénalité', format($$SELECT public.waive_late_cancel_penalty(%L)::text$$, pg_temp.id('L:lc')));
PERFORM pg_temp.as_('crea');
PERFORM pg_temp.ok('le créateur lève la pénalité', format($$SELECT public.waive_late_cancel_penalty(%L)::text$$, pg_temp.id('L:lc')));
PERFORM pg_temp.ok('lever deux fois : idempotent', format($$SELECT public.waive_late_cancel_penalty(%L)::text$$, pg_temp.id('L:lc')));
PERFORM pg_temp.eq('la vue du créateur montre la pénalité levée',
  format($$SELECT penalty_waived::text FROM public.activity_participants WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('L'), pg_temp.id('lc')), 'true');
PERFORM pg_temp.denied('pas de levée sur une participation active',
  format($$SELECT public.waive_late_cancel_penalty(%L)::text$$, (SELECT pg_temp.id('A:p1'))));
PERFORM pg_temp.denied('le créateur ne peut pas quitter sa propre sortie', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('L')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('pénalité levée : score revenu à 100', $$SELECT pg_temp.pr_score('lc')$$, '100');

PERFORM pg_temp.as_('lc4');
PERFORM pg_temp.ok('lc4 rejoint L4 (dans 3 jours)', format($$SELECT public.join_activity(%L)$$, pg_temp.id('L4')));
PERFORM pg_temp.ok('lc4 quitte tôt', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('L4')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('départ anticipé : pas de pénalité', $$SELECT pg_temp.pr_score('lc4')$$, '100');
PERFORM pg_temp.as_('crea');
PERFORM pg_temp.denied('pas de levée sur un départ anticipé',
  format($$SELECT public.waive_late_cancel_penalty(%L)::text$$, (SELECT participation_id FROM public.activity_participants WHERE activity_id = pg_temp.id('L4') AND user_id = pg_temp.id('lc4'))));

PERFORM pg_temp.as_('lc5');
PERFORM pg_temp.ok('lc5 rejoint L5 (sans présence)', format($$SELECT public.join_activity(%L)$$, pg_temp.id('L5')));
PERFORM pg_temp.ok('lc5 quitte tard', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('L5')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('sortie sans validation de présence : pas de pénalité', $$SELECT pg_temp.pr_score('lc5')$$, '100');

PERFORM pg_temp.as_('p1');
PERFORM pg_temp.denied('quitter une sortie terminée refusé', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('V')));
PERFORM pg_temp.as_('str');
PERFORM pg_temp.denied('quitter une sortie sans y être refusé', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('L')));
PERFORM pg_temp.as_('sus');
PERFORM pg_temp.denied('un suspendu ne quitte pas', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('A')));

-- PR-4 : se réinscrire efface la pénalité.
PERFORM pg_temp.as_('lc2');
PERFORM pg_temp.ok('lc2 rejoint L', format($$SELECT public.join_activity(%L)$$, pg_temp.id('L')));
PERFORM pg_temp.ok('lc2 quitte tard', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('L')));
-- DB-PR-1 : join_activity teste `v_existing IS NOT NULL` sur un RECORD, faux dès qu'un champ
-- (refused_at) est NULL → la ligne existante est ignorée et l'INSERT heurte la contrainte UNIQUE.
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.participations SET left_at = left_at - interval '20 minutes' WHERE activity_id = pg_temp.id('L') AND user_id = pg_temp.id('lc2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('lc2');
PERFORM pg_temp.eq('lc2 se réinscrit après un retrait',
  format($$SELECT public.join_activity(%L)$$, pg_temp.id('L')), 'accepted');
PERFORM pg_temp.as_('db');
-- Réinscription simulée telle que join_activity l'écrit (status accepted, left_at NULL).
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.participations SET status = 'accepted', left_at = NULL, created_at = now()
WHERE activity_id = pg_temp.id('L') AND user_id = pg_temp.id('lc2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM public.recalculate_reliability_score(pg_temp.id('lc2'));
PERFORM pg_temp.eq('la réinscription n''efface pas la pénalité d''annulation tardive', $$SELECT pg_temp.pr_score('lc2')$$, '50');

-- DB-PR-1 (suite) : accepter une invitation passe par join_activity → même défaut.
PERFORM pg_temp.as_('db');
INSERT INTO public.participations (activity_id, user_id, status, invited_by) VALUES (pg_temp.id('L4'), pg_temp.id('p2'), 'invited', pg_temp.id('crea'));
PERFORM pg_temp.as_('p2');
PERFORM pg_temp.eq('un invité accepte son invitation via join_activity',
  format($$SELECT public.join_activity(%L)$$, pg_temp.id('L4')), 'accepted');

-- PR-5 : retirer une demande en attente est pénalisé.
PERFORM pg_temp.as_('lc3');
PERFORM pg_temp.eq('lc3 demande à rejoindre L3', format($$SELECT public.join_activity(%L)$$, pg_temp.id('L3')), 'pending');
PERFORM pg_temp.ok('lc3 retire sa demande à moins de 12 h', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('L3')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('retirer une demande en attente n''est pas pénalisé', $$SELECT pg_temp.pr_score('lc3')$$, '100');

-- ═════ Transitions de statut à la demande ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.pr_act('T1', 'crea', interval '-10 minutes', interval '2 hours', 'published');
PERFORM pg_temp.pr_part('T1', 'p1');
PERFORM pg_temp.pr_act('T2', 'crea', interval '-3 hours', interval '2 hours', 'in_progress');
PERFORM pg_temp.pr_part('T2', 'p1');
PERFORM pg_temp.pr_act('T3', 'crea', interval '-3 hours', interval '2 hours', 'in_progress');
PERFORM pg_temp.pr_act('T4', 'crea', interval '-3 hours', interval '2 hours', 'published');
PERFORM pg_temp.pr_act('T5', 'crea', interval '-10 minutes', interval '2 hours', 'published');
PERFORM pg_temp.pr_part('T5', 'p1');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET deleted_at = now() WHERE id = pg_temp.id('T5');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('p1');
PERFORM pg_temp.eq('publiée et commencée → en cours', format($$SELECT public.transition_single_activity(%L)$$, pg_temp.id('T1')), 'in_progress');
PERFORM pg_temp.eq('en cours et finie → terminée', format($$SELECT public.transition_single_activity(%L)$$, pg_temp.id('T2')), 'completed');
PERFORM pg_temp.eq('en cours, finie, solo → expirée', format($$SELECT public.transition_single_activity(%L)$$, pg_temp.id('T3')), 'expired');
PERFORM pg_temp.eq('publiée depuis 3 h sans participant → expirée', format($$SELECT public.transition_single_activity(%L)$$, pg_temp.id('T4')), 'expired');
PERFORM pg_temp.eq('sortie supprimée : aucune transition', format($$SELECT public.transition_single_activity(%L)$$, pg_temp.id('T5')), 'published');
PERFORM pg_temp.as_('sus');
PERFORM pg_temp.eq('un suspendu ne déclenche rien', format($$SELECT coalesce(public.transition_single_activity(%L), 'null')$$, pg_temp.id('T1')), 'null');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('fenêtre de vote ouverte : invitation à évaluer envoyée',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'rate_participants' AND data->>'activity_id' = %L$$, pg_temp.id('p1'), pg_temp.get('T2')), '1');
PERFORM pg_temp.as_('p1');
PERFORM pg_temp.denied('pas d''écriture directe dans user_badge_progression',
  format($$INSERT INTO public.user_badge_progression (user_id, category, tier_key) VALUES (%L, 'joined', 'gold')$$, pg_temp.id('p1')));


-- ═════ Phase A2 (mig 00478) : registre des annulations tardives, levée, avis tardif, partenaires récents ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('a2_rc', 'tos');
PERFORM pg_temp.user('a2_r1', 'tos');
PERFORM pg_temp.user('a2_r2', 'tos');
PERFORM pg_temp.user('a2_r3', 'tos');
PERFORM pg_temp.user('a2_r4', 'tos');
PERFORM pg_temp.user('a2_x', 'tos');
PERFORM pg_temp.as_('a2_rc');
PERFORM pg_temp.put('a2_act', pg_temp.ok('A2 : sortie qui démarre dans 2 h', $q$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie A2', 'x', 'Tous niveaux', 8, 6.6, 44.9, NULL, NULL, now() + interval '2 hours')::text$q$));

-- 1. Le registre survit à la suppression de la ligne (refus d'une nouvelle invitation, cascade de blocage).
PERFORM pg_temp.as_('a2_r1');
PERFORM pg_temp.ok('A2 : r1 rejoint', format($q$SELECT public.join_activity(%L)$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.ok('A2 : r1 part tard', format($q$SELECT public.leave_activity(%L)::text$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.as_('db');
DELETE FROM public.participations WHERE activity_id = pg_temp.id('a2_act') AND user_id = pg_temp.id('a2_r1');
PERFORM public.recalculate_reliability_score(pg_temp.id('a2_r1'));
PERFORM pg_temp.eq('A2 : la pénalité survit à la suppression de la ligne (PR-4)', format($q$SELECT reliability_score::int::text FROM public.users WHERE id = %L$q$, pg_temp.id('a2_r1')), '50');

-- 2. Levée possible après réinscription, et liste des départs tardifs visible par l'organisateur.
PERFORM pg_temp.as_('a2_r2');
PERFORM pg_temp.ok('A2 : r2 rejoint', format($q$SELECT public.join_activity(%L)$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.ok('A2 : r2 part tard', format($q$SELECT public.leave_activity(%L)::text$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.participations SET left_at = left_at - interval '20 minutes' WHERE activity_id = pg_temp.id('a2_act') AND user_id = pg_temp.id('a2_r2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('a2_r2');
PERFORM pg_temp.ok('A2 : r2 revient après le délai', format($q$SELECT public.join_activity(%L)$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.as_('a2_rc');
PERFORM pg_temp.eq('A2 : l''organisateur voit le départ tardif de r2 (PR-6)', format($q$SELECT count(*)::text FROM public.get_late_leavers(%L) WHERE user_id = %L$q$, pg_temp.id('a2_act'), pg_temp.id('a2_r2')), '1');
PERFORM pg_temp.ok('A2 : l''organisateur lève la pénalité après réinscription (PR-6)', format($q$SELECT public.waive_late_cancel_penalty((SELECT participation_id FROM public.get_late_leavers(%L) WHERE user_id = %L))::text$q$, pg_temp.id('a2_act'), pg_temp.id('a2_r2')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A2 : pénalité levée → score intact', format($q$SELECT reliability_score::int::text FROM public.users WHERE id = %L$q$, pg_temp.id('a2_r2')), '100');
PERFORM pg_temp.as_('a2_x');
PERFORM pg_temp.eq('A2 : un tiers ne voit pas les départs tardifs', format($q$SELECT count(*)::text FROM public.get_late_leavers(%L)$q$, pg_temp.id('a2_act')), '0');
PERFORM pg_temp.denied('A2 : un tiers ne lève pas une pénalité', format($q$SELECT public.waive_late_cancel_penalty((SELECT id FROM public.participations WHERE activity_id = %L AND user_id = %L))::text$q$, pg_temp.id('a2_act'), pg_temp.id('a2_r2')));
PERFORM pg_temp.denied('A2 : le registre n''est pas lisible par un client', $q$SELECT count(*)::text FROM public.late_cancels$q$);

-- 3. Un départ anticipé ne masque pas l'avis de départ tardif.
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET notification_preferences = coalesce(notification_preferences, '{}'::jsonb) || '{"participant_left": true, "participant_joined": true}'::jsonb WHERE id = pg_temp.id('a2_rc');
UPDATE public.activities SET starts_at = now() + interval '2 days' WHERE id = pg_temp.id('a2_act');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('a2_r3');
PERFORM pg_temp.ok('A2 : r3 rejoint', format($q$SELECT public.join_activity(%L)$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.ok('A2 : r3 part tôt', format($q$SELECT public.leave_activity(%L)::text$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.participations SET left_at = left_at - interval '20 minutes' WHERE activity_id = pg_temp.id('a2_act') AND user_id = pg_temp.id('a2_r3');
UPDATE public.activities SET starts_at = now() + interval '2 hours' WHERE id = pg_temp.id('a2_act');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('a2_r3');
PERFORM pg_temp.ok('A2 : r3 revient', format($q$SELECT public.join_activity(%L)$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.ok('A2 : r3 repart, tard cette fois', format($q$SELECT public.leave_activity(%L)::text$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('A2 : l''avis de départ tardif est bien envoyé (AB-1)', format($q$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'participant_left_late' AND data->>'activity_id' = %L AND data->>'participation_id' = (SELECT id::text FROM public.participations WHERE activity_id = %L AND user_id = %L)$q$, pg_temp.id('a2_rc'), pg_temp.id('a2_act'), pg_temp.id('a2_act'), pg_temp.id('a2_r3')), '1');

-- 4. Pas de double comptage : départ tardif, retour, puis verdict de présence.
PERFORM pg_temp.as_('a2_r4');
PERFORM pg_temp.ok('A2 : r4 rejoint', format($q$SELECT public.join_activity(%L)$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.ok('A2 : r4 part tard', format($q$SELECT public.leave_activity(%L)::text$q$, pg_temp.id('a2_act')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.participations SET status = 'accepted', left_at = NULL, confirmed_present = true WHERE activity_id = pg_temp.id('a2_act') AND user_id = pg_temp.id('a2_r4');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM public.recalculate_reliability_score(pg_temp.id('a2_r4'));
PERFORM pg_temp.eq('A2 : présent après un retour → pas de pénalité comptée en double', format($q$SELECT reliability_score::int::text FROM public.users WHERE id = %L$q$, pg_temp.id('a2_r4')), '100');

-- 5. Partenaires récents (DB-MS-1).
PERFORM pg_temp.as_('a2_rc');
PERFORM pg_temp.ok('A2 : la liste des partenaires récents se charge (DB-MS-1)', $q$SELECT count(*)::text FROM public.get_recent_partners()$q$);
