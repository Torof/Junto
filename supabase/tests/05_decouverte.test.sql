-- Domaine 5 — Découverte (dispos), carte (vues), recherche, traces GPX, favoris, alertes, rideau démo.

-- ───── Utilitaires locaux ─────
EXECUTE $p$CREATE FUNCTION pg_temp.dc_trace(p_shift float8 DEFAULT 0) RETURNS jsonb
  LANGUAGE sql AS $b$ SELECT jsonb_build_object('type', 'LineString', 'coordinates',
    jsonb_build_array(jsonb_build_array(6.08 + p_shift, 44.56, 900), jsonb_build_array(6.10 + p_shift, 44.58, 1200), jsonb_build_array(6.12 + p_shift, 44.59, 1500))) $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.dc_act(p_label text, p_creator uuid, p_vis text DEFAULT 'public', p_demo boolean DEFAULT false) RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.activities (creator_id, sport_id, title, description, level, max_participants,
      location_meeting, starts_at, duration, visibility, is_demo, trace_geojson)
    VALUES (p_creator, (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test ' || p_label,
      'Description secrète ' || p_label, 'Tous niveaux', 6,
      ST_SetSRID(ST_MakePoint(6.08, 44.56), 4326)::geography, now() + interval '3 days', interval '2 hours',
      p_vis, p_demo, pg_temp.dc_trace())
    RETURNING id INTO v;
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.dc_dispo(p_user uuid, p_demo boolean, p_ws timestamptz, p_we timestamptz, p_active boolean DEFAULT true) RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.discovery_availabilities (user_id, sport_keys, base, base_label, radius_km, transport_modes,
      window_start, window_end, is_active, is_demo)
    VALUES (p_user, ARRAY['hiking'], ST_SetSRID(ST_MakePoint(6.081, 44.561), 4326)::geography, 'Gap', 15, ARRAY['car'],
      p_ws, p_we, p_active, p_demo)
    RETURNING id INTO v;
    RETURN v;
  END $b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.dc_pro(p_user uuid, p_demo boolean, p_label text) RETURNS uuid
  LANGUAGE plpgsql SET search_path = public, extensions AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.pro_profiles (user_id, display_name, primary_lng, primary_lat, primary_location, primary_location_name, status, is_demo)
    VALUES (p_user, 'Pro ' || p_label, 6.08, 44.56, ST_SetSRID(ST_MakePoint(6.08, 44.56), 4326)::geography, 'Gap', 'approved', p_demo);
    INSERT INTO public.pro_offerings (pro_id, sport_id, title, description, level, location, location_name, is_demo)
    VALUES (p_user, (SELECT id FROM public.sports WHERE key = 'hiking'), 'Offre test ' || p_label, 'Desc', 'Tous niveaux',
      ST_SetSRID(ST_MakePoint(6.08, 44.56), 4326)::geography, 'Gap', p_demo)
    RETURNING id INTO v;
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;

-- Appels répétés (invoker : garde le rôle et le JWT courants).
EXECUTE $p$CREATE FUNCTION pg_temp.dc_trace_spam(p_act uuid, p_n int) RETURNS int
  LANGUAGE plpgsql AS $b$
  BEGIN
    FOR i IN 1..p_n LOOP PERFORM public.update_activity_trace(p_act, pg_temp.dc_trace(i * 0.001)); END LOOP;
    RETURN p_n;
  END $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.dc_stats_spam(p_n int) RETURNS int
  LANGUAGE plpgsql AS $b$
  BEGIN
    FOR i IN 1..p_n LOOP PERFORM * FROM public.compute_trace_stats(pg_temp.dc_trace(i * 0.001)); END LOOP;
    RETURN p_n;
  END $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.dc_gpx_fill(p_n int) RETURNS int
  LANGUAGE plpgsql AS $b$
  BEGIN
    FOR i IN 1..p_n LOOP PERFORM public.create_gpx_trace('Trace ' || i, pg_temp.dc_trace(i * 0.001)); END LOOP;
    RETURN p_n;
  END $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.dc_alert_fill(p_n int) RETURNS int
  LANGUAGE plpgsql AS $b$
  BEGIN
    FOR i IN 1..p_n LOOP PERFORM public.create_alert(6.08, 44.56, 20); END LOOP;
    RETURN p_n;
  END $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.dc_demo_mode(p_on boolean) RETURNS void
  LANGUAGE plpgsql AS $b$
  BEGIN
    UPDATE public.app_config SET value = p_on::text WHERE name = 'demo_mode';
    IF NOT FOUND THEN INSERT INTO public.app_config (name, value) VALUES ('demo_mode', p_on::text); END IF;
  END $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.user('alice', 'tos');
PERFORM pg_temp.user('bob', 'tos');
PERFORM pg_temp.user('carol', 'tos');
PERFORM pg_temp.user('eve', 'tos');
PERFORM pg_temp.user('sam', 'tos,suspended');
PERFORM pg_temp.user('demo1', 'tos,demo');
PERFORM pg_temp.user('adm', 'tos,admin');
PERFORM pg_temp.user('pro1', 'tos');
PERFORM pg_temp.user('past1', 'tos');
PERFORM pg_temp.user('past2', 'tos');

PERFORM pg_temp.dc_demo_mode(false);
PERFORM pg_temp.dc_act('a_pub', pg_temp.id('bob'));
PERFORM pg_temp.dc_act('a_priv', pg_temp.id('bob'), 'private_link');
PERFORM pg_temp.dc_act('a_sus', pg_temp.id('sam'));
PERFORM pg_temp.dc_act('a_demo', pg_temp.id('demo1'), 'public', true);
PERFORM pg_temp.dc_act('a_blk', pg_temp.id('eve'));
PERFORM pg_temp.dc_act('a_alice', pg_temp.id('alice'));
PERFORM pg_temp.dc_act('a_del', pg_temp.id('bob'));
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET deleted_at = now() WHERE id = pg_temp.id('a_del');
PERFORM set_config('junto.bypass_lock', 'false', true);

INSERT INTO public.participations (activity_id, user_id, status) VALUES
  (pg_temp.id('a_pub'), pg_temp.id('alice'), 'accepted'),
  (pg_temp.id('a_pub'), pg_temp.id('carol'), 'pending'),
  (pg_temp.id('a_pub'), pg_temp.id('demo1'), 'accepted'),
  (pg_temp.id('a_priv'), pg_temp.id('carol'), 'accepted');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('alice'), pg_temp.id('eve'));

PERFORM pg_temp.dc_pro(pg_temp.id('pro1'), false, 'o_pub');
PERFORM pg_temp.dc_pro(pg_temp.id('demo1'), true, 'o_demo');
PERFORM pg_temp.dc_pro(pg_temp.id('sam'), false, 'o_sus');
INSERT INTO public.offering_reviews (offering_id, reviewer_id, rating, body) VALUES
  (pg_temp.id('o_pub'), pg_temp.id('alice'), 5, 'Bien'),
  (pg_temp.id('o_pub'), pg_temp.id('sam'), 1, 'Avis d''un suspendu'),
  (pg_temp.id('o_demo'), pg_temp.id('alice'), 4, 'Démo');
INSERT INTO public.pro_reviews (pro_id, reviewer_id, rating, body) VALUES
  (pg_temp.id('pro1'), pg_temp.id('alice'), 5, 'Bien'),
  (pg_temp.id('demo1'), pg_temp.id('alice'), 4, 'Démo');

-- Dispos posées directement (démo, suspendu, bloqué, expirée).
PERFORM pg_temp.dc_dispo(pg_temp.id('demo1'), true, now() + interval '1 hour', now() + interval '7 days');
PERFORM pg_temp.dc_dispo(pg_temp.id('sam'), false, now() + interval '1 hour', now() + interval '7 days');
PERFORM pg_temp.dc_dispo(pg_temp.id('eve'), false, now() + interval '1 hour', now() + interval '7 days');
PERFORM pg_temp.dc_dispo(pg_temp.id('past2'), false, now() - interval '20 hours', now() - interval '2 hours');

-- ───── Visiteur sans compte : vues carte ─────
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('anon voit une sortie publique sur la carte',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_pub')), '1');
PERFORM pg_temp.eq('anon ne voit pas une sortie privée',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_priv')), '0');
PERFORM pg_temp.eq('anon ne voit pas la sortie d''un créateur suspendu',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_sus')), '0');
PERFORM pg_temp.eq('anon ne voit pas une sortie démo',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_demo')), '0');
PERFORM pg_temp.eq('anon ne voit pas une sortie supprimée',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_del')), '0');
PERFORM pg_temp.eq('anon : aucune ligne dans la table activities',
  format($$SELECT count(*)::text FROM public.activities WHERE id = %L$$, pg_temp.id('a_pub')), '0');
PERFORM pg_temp.denied('anon : my_activities refusée (00547 : aucun droit sans compte)', $$SELECT count(*)::text FROM public.my_activities$$);
PERFORM pg_temp.denied('anon : my_joined_activities refusée (00547 : aucun droit sans compte)', $$SELECT count(*)::text FROM public.my_joined_activities$$);
PERFORM pg_temp.denied('anon : my_pending_activities refusée (00547 : aucun droit sans compte)', $$SELECT count(*)::text FROM public.my_pending_activities$$);
PERFORM pg_temp.denied('anon : aucune participation lisible (00547 : aucun droit sans compte)',
  format($$SELECT count(*)::text FROM public.participations WHERE activity_id = %L$$, pg_temp.id('a_pub')));
PERFORM pg_temp.denied('anon ne lit pas activity_participants', $$SELECT count(*)::text FROM public.activity_participants$$);
PERFORM pg_temp.denied('anon ne lit pas offering_reviews_with_profiles', $$SELECT count(*)::text FROM public.offering_reviews_with_profiles$$);
PERFORM pg_temp.denied('anon ne lit pas offering_review_stats', $$SELECT count(*)::text FROM public.offering_review_stats$$);
PERFORM pg_temp.denied('anon ne lit pas pro_reviews_with_profiles', $$SELECT count(*)::text FROM public.pro_reviews_with_profiles$$);
PERFORM pg_temp.denied('anon ne lit pas pro_review_stats', $$SELECT count(*)::text FROM public.pro_review_stats$$);
PERFORM pg_temp.eq('anon voit une offre pro publique',
  format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o_pub')), '1');
PERFORM pg_temp.eq('anon ne voit pas une offre démo',
  format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o_demo')), '0');
PERFORM pg_temp.eq('anon ne voit pas l''offre d''un pro suspendu',
  format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o_sus')), '0');
PERFORM pg_temp.denied('anon : table pro_offerings refusée (00547 : aucun droit sans compte)',
  format($$SELECT count(*)::text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('o_pub')));
PERFORM pg_temp.denied('anon : avis d''offre démo invisibles (table) (00547 : aucun droit sans compte)',
  format($$SELECT count(*)::text FROM public.offering_reviews WHERE offering_id = %L$$, pg_temp.id('o_demo')));
PERFORM pg_temp.denied('anon ne lit pas les dispos', $$SELECT count(*)::text FROM public.discovery_availabilities$$);
PERFORM pg_temp.denied('anon ne lit pas les traces GPX', $$SELECT count(*)::text FROM public.gpx_traces$$);
PERFORM pg_temp.denied('anon ne lit pas les favoris', $$SELECT count(*)::text FROM public.favorites$$);
PERFORM pg_temp.denied('anon : aucune alerte lisible (00547 : aucun droit sans compte)', $$SELECT count(*)::text FROM public.activity_alerts$$);
PERFORM pg_temp.denied('anon ne peut pas poser de dispo',
  $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$);
PERFORM pg_temp.denied('anon ne lit pas les cartes découverte', $$SELECT count(*)::text FROM public.get_discovery_cards()$$);
PERFORM pg_temp.denied('anon ne compte pas les dispos',
  $$SELECT public.get_discovery_count(ARRAY['hiking'], 6.08, 44.56, 50, now(), now() + interval '7 days')::text$$);
PERFORM pg_temp.denied('anon ne lit pas une zone de dispo', format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('bob')));
PERFORM pg_temp.denied('anon ne crée pas d''alerte', $$SELECT public.create_alert(6.08, 44.56, 20)::text$$);
PERFORM pg_temp.denied('anon ne crée pas de trace GPX', format($$SELECT (public.create_gpx_trace('x', %L::jsonb)).id::text$$, pg_temp.dc_trace()));
PERFORM pg_temp.denied('anon ne calcule pas de stats de trace', format($$SELECT distance_km::text FROM public.compute_trace_stats(%L::jsonb)$$, pg_temp.dc_trace()));
PERFORM pg_temp.denied('anon ne met pas de favori', format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_pub')));

-- ───── Utilisateurs : vues carte et tables de base ─────
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('alice voit la sortie publique de bob',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_pub')), '1');
PERFORM pg_temp.eq('le compteur de participants ne compte que les acceptés',
  format($$SELECT participant_count::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_pub')), '2');
PERFORM pg_temp.eq('alice ne voit pas la sortie privée de bob (vue)',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_priv')), '0');
PERFORM pg_temp.eq('alice ne voit pas la sortie privée de bob (table)',
  format($$SELECT count(*)::text FROM public.activities WHERE id = %L$$, pg_temp.id('a_priv')), '0');
PERFORM pg_temp.eq('créateur suspendu : sortie masquée (vue)',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_sus')), '0');
PERFORM pg_temp.eq('créateur suspendu : sortie masquée (table)',
  format($$SELECT count(*)::text FROM public.activities WHERE id = %L$$, pg_temp.id('a_sus')), '0');
PERFORM pg_temp.eq('créateur bloqué : sortie masquée (vue)',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_blk')), '0');
PERFORM pg_temp.eq('créateur bloqué : sortie masquée (table)',
  format($$SELECT count(*)::text FROM public.activities WHERE id = %L$$, pg_temp.id('a_blk')), '0');
PERFORM pg_temp.eq('rideau démo : sortie démo masquée (vue)',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_demo')), '0');
PERFORM pg_temp.eq('rideau démo : sortie démo masquée (table)',
  format($$SELECT count(*)::text FROM public.activities WHERE id = %L$$, pg_temp.id('a_demo')), '0');
PERFORM pg_temp.eq('my_activities ne montre que mes sorties',
  format($$SELECT string_agg(id::text, ',') FROM public.my_activities WHERE id IN (%L, %L, %L)$$, pg_temp.id('a_pub'), pg_temp.id('a_alice'), pg_temp.id('a_priv')),
  pg_temp.get('a_alice'));
PERFORM pg_temp.eq('my_joined_activities montre la sortie rejointe',
  format($$SELECT count(*)::text FROM public.my_joined_activities WHERE id = %L$$, pg_temp.id('a_pub')), '1');
PERFORM pg_temp.eq('activity_participants : rien pour un non-créateur',
  format($$SELECT count(*)::text FROM public.activity_participants WHERE activity_id = %L$$, pg_temp.id('a_pub')), '0');
PERFORM pg_temp.eq('offre pro publique visible', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o_pub')), '1');
PERFORM pg_temp.eq('rideau démo : offre démo masquée (vue)', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o_demo')), '0');
PERFORM pg_temp.eq('rideau démo : offre démo masquée (table)', format($$SELECT count(*)::text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('o_demo')), '0');
PERFORM pg_temp.eq('pro suspendu : offre masquée (vue)', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o_sus')), '0');
PERFORM pg_temp.eq('pro suspendu : offre masquée (table)', format($$SELECT count(*)::text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('o_sus')), '0');
PERFORM pg_temp.eq('avis d''offre : l''avis d''un suspendu est exclu des stats',
  format($$SELECT review_count::text FROM public.offering_review_stats WHERE offering_id = %L$$, pg_temp.id('o_pub')), '1');
PERFORM pg_temp.eq('avis d''offre : liste sans l''avis du suspendu',
  format($$SELECT count(*)::text FROM public.offering_reviews_with_profiles WHERE offering_id = %L$$, pg_temp.id('o_pub')), '1');
PERFORM pg_temp.eq('rideau démo : avis d''offre démo masqués (vue)',
  format($$SELECT count(*)::text FROM public.offering_reviews_with_profiles WHERE offering_id = %L$$, pg_temp.id('o_demo')), '0');
PERFORM pg_temp.eq('rideau démo : stats d''offre démo masquées',
  format($$SELECT count(*)::text FROM public.offering_review_stats WHERE offering_id = %L$$, pg_temp.id('o_demo')), '0');
PERFORM pg_temp.eq('rideau démo : avis d''offre démo masqués (table)',
  format($$SELECT count(*)::text FROM public.offering_reviews WHERE offering_id = %L$$, pg_temp.id('o_demo')), '0');
PERFORM pg_temp.eq('avis pro visibles', format($$SELECT count(*)::text FROM public.pro_reviews_with_profiles WHERE pro_id = %L$$, pg_temp.id('pro1')), '1');
PERFORM pg_temp.eq('stats pro visibles', format($$SELECT review_count::text FROM public.pro_review_stats WHERE pro_id = %L$$, pg_temp.id('pro1')), '1');
PERFORM pg_temp.eq('rideau démo : avis pro démo masqués (vue)', format($$SELECT count(*)::text FROM public.pro_reviews_with_profiles WHERE pro_id = %L$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.eq('rideau démo : stats pro démo masquées', format($$SELECT count(*)::text FROM public.pro_review_stats WHERE pro_id = %L$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.eq('rideau démo : avis pro démo masqués (table)', format($$SELECT count(*)::text FROM public.pro_reviews WHERE pro_id = %L$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.denied('alice ne peut pas activer le mode démo',
  $$WITH u AS (UPDATE public.app_config SET value = 'true' WHERE name = 'demo_mode' RETURNING 1) SELECT count(*)::text FROM u$$, 'permission denied');
PERFORM pg_temp.eq('alice n''a pas accès au contenu démo', $$SELECT public.demo_content_visible()::text$$, 'false');

PERFORM pg_temp.as_('carol');
PERFORM pg_temp.eq('participante acceptée : voit la sortie privée',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_priv')), '1');
PERFORM pg_temp.eq('my_pending_activities montre la demande en attente',
  format($$SELECT count(*)::text FROM public.my_pending_activities WHERE id = %L$$, pg_temp.id('a_pub')), '1');

PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('le créateur voit sa sortie privée',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_priv')), '1');
PERFORM pg_temp.eq('bob (non bloqueur) voit la sortie d''eve',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_blk')), '1');
PERFORM pg_temp.eq('activity_participants : le créateur voit acceptés + en attente, sans le compte démo',
  format($$SELECT count(*)::text FROM public.activity_participants WHERE activity_id = %L$$, pg_temp.id('a_pub')), '2');
PERFORM pg_temp.eq('my_activities ne liste pas les sorties d''autrui',
  format($$SELECT count(*)::text FROM public.my_activities WHERE id = %L$$, pg_temp.id('a_alice')), '0');

PERFORM pg_temp.as_('sam');
PERFORM pg_temp.eq('un compte suspendu ne voit plus la carte',
  format($$SELECT count(*)::text FROM public.activities WHERE id = %L$$, pg_temp.id('a_pub')), '0');

-- ───── Dispos : composition ─────
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.put('d_alice', pg_temp.ok('alice pose sa dispo',
  $$SELECT public.upsert_dispo(ARRAY['hiking','climbing-sport'], '{"hiking":"T3"}'::jsonb, 6.0801, 44.5601, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '7 days', ARRAY['nature'], 'Hello')::text$$));
PERFORM pg_temp.eq('une dispo neuve est inactive', $$SELECT is_active::text FROM public.get_my_dispo()$$, 'false');
PERFORM pg_temp.ok('alice active sa dispo', $$SELECT public.activate_dispo()::text$$);
PERFORM pg_temp.eq('get_my_dispo renvoie la dispo active', $$SELECT is_active::text FROM public.get_my_dispo()$$, 'true');
PERFORM pg_temp.eq('re-poser met à jour la même dispo',
  $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.0801, 44.5601, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '7 days')::text$$,
  pg_temp.get('d_alice'));
PERFORM pg_temp.denied('4 sports refusés', $$SELECT public.upsert_dispo(ARRAY['hiking','running','cycling','kayaking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto.dispo_sports');
PERFORM pg_temp.denied('sport inconnu refusé', $$SELECT public.upsert_dispo(ARRAY['curling-lunaire'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto.dispo_sports');
PERFORM pg_temp.denied('niveaux non-objet refusés', $$SELECT public.upsert_dispo(ARRAY['hiking'], '[1,2]'::jsonb, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto.dispo_levels');
PERFORM pg_temp.denied('niveau pour un sport non choisi refusé', $$SELECT public.upsert_dispo(ARRAY['hiking'], '{"running":"x"}'::jsonb, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto.dispo_levels');
PERFORM pg_temp.denied('intention inconnue refusée', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days', ARRAY['hack'])::text$$, 'junto.dispo_intent');
PERFORM pg_temp.denied('présentation trop longue refusée', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days', NULL, repeat('a', 1700))::text$$, 'junto.dispo_about');
PERFORM pg_temp.denied('rayon hors liste refusé', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 7, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto.dispo_radius');
PERFORM pg_temp.denied('mode de transport inconnu refusé', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['jetpack'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto.dispo_transport');
PERFORM pg_temp.denied('fenêtre au-delà de 4 semaines refusée', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '40 days')::text$$, 'junto.dispo_window');
PERFORM pg_temp.denied('fenêtre inversée refusée', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '2 days', now() + interval '1 day')::text$$, 'junto.dispo_window');
PERFORM pg_temp.denied('latitude invalide refusée', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 95, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto.dispo_place');
PERFORM pg_temp.denied('libellé de lieu vide refusé', $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, '<b></b>', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'junto.dispo_place');
PERFORM pg_temp.denied('pas d''écriture directe dans les dispos',
  format($$INSERT INTO public.discovery_availabilities (user_id, sport_keys, base, base_label, transport_modes, window_start, window_end) VALUES (%L, ARRAY['hiking'], 'POINT(6 44)', 'x', ARRAY['car'], now(), now() + interval '1 day')$$, pg_temp.id('alice')));
PERFORM pg_temp.denied('tentative de se marquer démo / modifier sa dispo en direct',
  format($$UPDATE public.discovery_availabilities SET is_demo = true, radius_km = 50 WHERE user_id = %L$$, pg_temp.id('alice')), 'permission denied');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la dispo n''est pas modifiable en direct',
  format($$SELECT (is_demo::text || '/' || radius_km::text) FROM public.discovery_availabilities WHERE user_id = %L$$, pg_temp.id('alice')), 'false/15');

PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob pose et active sa dispo',
  $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.083217, 44.561234, 'Gap centre', 15, ARRAY['car','bike'], now() + interval '1 hour', now() + interval '7 days')::text$$);
PERFORM pg_temp.ok('bob active', $$SELECT public.activate_dispo()::text$$);
PERFORM pg_temp.eq('bob ne lit pas la dispo d''alice',
  format($$SELECT count(*)::text FROM public.discovery_availabilities WHERE user_id = %L$$, pg_temp.id('alice')), '0');

PERFORM pg_temp.as_('carol');
PERFORM pg_temp.denied('activer sans dispo composée est refusé', $$SELECT public.activate_dispo()::text$$, 'Operation not permitted');
PERFORM pg_temp.eq('sans dispo active, aucune carte découverte', $$SELECT count(*)::text FROM public.get_discovery_cards()$$, '0');
PERFORM pg_temp.eq('sans dispo active, aucune zone', format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('bob')), '0');
PERFORM pg_temp.eq('sans dispo active, rien à inviter', format($$SELECT count(*)::text FROM public.get_invitable_activities_for_dispo(%L)$$, pg_temp.id('bob')), '0');

PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne pose pas de dispo',
  $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '2 days')::text$$, 'Operation not permitted');
PERFORM pg_temp.eq('un compte suspendu ne voit aucune carte', $$SELECT count(*)::text FROM public.get_discovery_cards()$$, '0');
PERFORM pg_temp.eq('un compte suspendu compte 0',
  $$SELECT public.get_discovery_count(ARRAY['hiking'], 6.08, 44.56, 50, now(), now() + interval '7 days')::text$$, '0');

-- ───── Dispos : correspondances ─────
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('alice voit bob dans ses correspondances',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('bob')), '1');
PERFORM pg_temp.eq('rideau démo : dispo démo absente des cartes',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.eq('dispo d''un suspendu absente des cartes',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('sam')), '0');
PERFORM pg_temp.eq('dispo d''un compte bloqué absente des cartes',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('eve')), '0');
PERFORM pg_temp.eq('le compteur trouve des correspondances',
  $$SELECT (public.get_discovery_count(ARRAY['hiking'], 6.0801, 44.5601, 15, now() + interval '1 hour', now() + interval '7 days') <> 0)::text$$, 'true');
PERFORM pg_temp.eq('zone de bob visible (correspondance)', format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('bob')), '1');
PERFORM pg_temp.eq('zone démo invisible', format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.eq('zone d''un bloqué invisible', format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('eve')), '0');
PERFORM pg_temp.eq('zone d''un suspendu invisible', format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('sam')), '0');
PERFORM pg_temp.eq('ma propre zone ne passe pas par get_dispo_zone', format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('alice')), '0');
PERFORM pg_temp.eq('sorties invitables pour bob',
  format($$SELECT string_agg(id::text, ',') FROM public.get_invitable_activities_for_dispo(%L)$$, pg_temp.id('bob')), pg_temp.get('a_alice'));
PERFORM pg_temp.eq('rien à inviter pour un compte démo', format($$SELECT count(*)::text FROM public.get_invitable_activities_for_dispo(%L)$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.denied('pas d''invitation vers un compte démo',
  format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('demo1'), pg_temp.id('a_alice')), 'Operation not permitted');
PERFORM pg_temp.denied('pas d''invitation vers un compte bloqué',
  format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('eve'), pg_temp.id('a_alice')), 'Operation not permitted');
PERFORM pg_temp.denied('pas d''invitation à la sortie d''un autre',
  format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('bob'), pg_temp.id('a_pub')), 'Operation not permitted');
PERFORM pg_temp.denied('pas d''invitation à soi-même',
  format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('alice'), pg_temp.id('a_alice')), 'Operation not permitted');
PERFORM pg_temp.ok('alice invite bob à sa sortie',
  format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('bob'), pg_temp.id('a_alice')));
PERFORM pg_temp.denied('pas de deuxième invitation en attente',
  format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('bob'), pg_temp.id('a_alice')), 'Operation not permitted');
PERFORM pg_temp.eq('la carte de bob indique la demande envoyée',
  format($$SELECT contact_state FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('bob')), 'pending');

PERFORM pg_temp.as_('eve');
PERFORM pg_temp.eq('blocage bidirectionnel : eve ne voit pas alice',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('alice')), '0');
PERFORM pg_temp.eq('blocage bidirectionnel : eve ne voit pas la zone d''alice',
  format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('alice')), '0');

PERFORM pg_temp.as_('carol');
PERFORM pg_temp.denied('sans dispo, pas d''invitation découverte',
  format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('bob'), pg_temp.id('a_priv')), 'Operation not permitted');

PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob désactive sa dispo', $$SELECT public.deactivate_dispo()::text$$);
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('dispo désactivée : plus dans les cartes',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('bob')), '0');
PERFORM pg_temp.eq('dispo désactivée : plus de zone', format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('bob')), '0');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob réactive', $$SELECT public.activate_dispo()::text$$);

-- ───── Rideau démo : admin, mode démo éteint puis allumé ─────
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.ok('l''admin pose et active une dispo',
  $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() + interval '1 hour', now() + interval '7 days')::text || public.activate_dispo()::text$$);
PERFORM pg_temp.eq('mode démo éteint : l''admin ne voit pas la sortie démo',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_demo')), '0');
PERFORM pg_temp.eq('mode démo éteint : l''admin ne voit pas la dispo démo',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.eq('mode démo éteint : l''admin ne voit pas l''offre démo',
  format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o_demo')), '0');
PERFORM pg_temp.denied('mode démo éteint : l''admin ne met pas une sortie démo en favori',
  format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_demo')), 'Operation not permitted');

PERFORM pg_temp.as_('db');
PERFORM pg_temp.dc_demo_mode(true);
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.eq('mode démo : l''admin voit la sortie démo (vue)',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_demo')), '1');
PERFORM pg_temp.eq('mode démo : l''admin voit la sortie démo (table)',
  format($$SELECT count(*)::text FROM public.activities WHERE id = %L$$, pg_temp.id('a_demo')), '1');
PERFORM pg_temp.eq('mode démo : l''admin voit la dispo démo',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('demo1')), '1');
PERFORM pg_temp.eq('mode démo : l''admin voit la zone démo', format($$SELECT count(*)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('demo1')), '1');
PERFORM pg_temp.eq('mode démo : l''admin voit l''offre démo',
  format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('o_demo')), '1');
PERFORM pg_temp.eq('mode démo : l''admin voit les avis démo',
  format($$SELECT count(*)::text FROM public.offering_reviews_with_profiles WHERE offering_id = %L$$, pg_temp.id('o_demo')), '1');
PERFORM pg_temp.eq('mode démo : l''admin voit les avis pro démo',
  format($$SELECT count(*)::text FROM public.pro_reviews_with_profiles WHERE pro_id = %L$$, pg_temp.id('demo1')), '1');
PERFORM pg_temp.ok('mode démo : l''admin met la sortie démo en favori',
  format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_demo')));
PERFORM pg_temp.denied('même en mode démo, pas d''invitation réelle vers un compte démo',
  format($$SELECT public.send_discovery_invite(%L, %L)::text$$, pg_temp.id('demo1'), pg_temp.id('a_pub')), 'Operation not permitted');

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('mode démo allumé : un utilisateur normal ne voit toujours pas la sortie démo',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_demo')), '0');
PERFORM pg_temp.eq('mode démo allumé : un utilisateur normal ne voit pas la dispo démo',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('demo1')), '0');
PERFORM pg_temp.eq('mode démo allumé : un utilisateur normal ne voit pas l''offre démo',
  format($$SELECT count(*)::text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('o_demo')), '0');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('mode démo allumé : anon ne voit pas la sortie démo',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('a_demo')), '0');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.dc_demo_mode(false);

-- ───── Alertes ─────
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice crée une alerte', $$SELECT public.create_alert(6.08, 44.56, 20, 'hiking', ARRAY['débutant'], current_date, current_date + 7)::text$$);
PERFORM pg_temp.denied('niveau d''alerte inconnu refusé', $$SELECT public.create_alert(6.08, 44.56, 20, 'hiking', ARRAY['dieu'])::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('période d''alerte inversée refusée', $$SELECT public.create_alert(6.08, 44.56, 20, NULL, NULL, current_date + 5, current_date + 1)::text$$, 'junto.alert_date_invalid');
PERFORM pg_temp.denied('période d''alerte passée refusée', $$SELECT public.create_alert(6.08, 44.56, 20, NULL, NULL, NULL, current_date - 1)::text$$, 'junto.alert_date_invalid');
PERFORM pg_temp.denied('rayon d''alerte hors bornes refusé', $$SELECT public.create_alert(6.08, 44.56, 1)::text$$);
PERFORM pg_temp.denied('pas d''écriture directe dans les alertes',
  format($$INSERT INTO public.activity_alerts (user_id, location, radius_km) VALUES (%L, 'POINT(6 44)', 20)$$, pg_temp.id('alice')));
PERFORM pg_temp.denied('plafond de 10 alertes', $$SELECT pg_temp.dc_alert_fill(10)::text$$, 'junto.alert_limit_reached');
PERFORM pg_temp.eq('alice lit ses alertes', $$SELECT (count(*) >= 1)::text FROM public.activity_alerts$$, 'true');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('bob ne lit pas les alertes d''alice',
  format($$SELECT count(*)::text FROM public.activity_alerts WHERE user_id = %L$$, pg_temp.id('alice')), '0');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne crée pas d''alerte', $$SELECT public.create_alert(6.08, 44.56, 20)::text$$, 'Operation not permitted');

-- ───── Bibliothèque GPX ─────
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.put('gpx1', pg_temp.ok('alice enregistre une trace', format($$SELECT (public.create_gpx_trace('Ma trace', %L::jsonb)).id::text$$, pg_temp.dc_trace())));
PERFORM pg_temp.eq('la distance est calculée', format($$SELECT (distance_km > 0)::text FROM public.gpx_traces WHERE id = %L$$, pg_temp.id('gpx1')), 'true');
PERFORM pg_temp.denied('nom de trace vide refusé', format($$SELECT (public.create_gpx_trace('   ', %L::jsonb)).id::text$$, pg_temp.dc_trace()), 'junto.trace_name_invalid');
PERFORM pg_temp.denied('trace non LineString refusée', $$SELECT (public.create_gpx_trace('x', '{"type":"Point","coordinates":[6,44]}'::jsonb)).id::text$$, 'junto.trace_geojson_invalid');
PERFORM pg_temp.denied('trace hors coordonnées refusée', $$SELECT (public.create_gpx_trace('x', '{"type":"LineString","coordinates":[[6,44],[6,200]]}'::jsonb)).id::text$$, 'junto.trace_geojson_invalid');
PERFORM pg_temp.ok('alice renomme sa trace', format($$SELECT public.rename_gpx_trace(%L, 'Nouveau nom')::text$$, pg_temp.id('gpx1')));
PERFORM pg_temp.denied('pas d''écriture directe dans gpx_traces',
  format($$INSERT INTO public.gpx_traces (user_id, name, geojson, distance_km) VALUES (%L, 'x', '{}'::jsonb, 1)$$, pg_temp.id('alice')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('bob ne voit pas les traces d''alice', format($$SELECT count(*)::text FROM public.gpx_traces WHERE id = %L$$, pg_temp.id('gpx1')), '0');
PERFORM pg_temp.denied('bob ne renomme pas la trace d''alice', format($$SELECT public.rename_gpx_trace(%L, 'pwn')::text$$, pg_temp.id('gpx1')), 'Operation not permitted');
PERFORM pg_temp.denied('bob ne supprime pas la trace d''alice', format($$SELECT public.delete_gpx_trace(%L)::text$$, pg_temp.id('gpx1')), 'Operation not permitted');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('alice voit sa trace renommée', format($$SELECT name FROM public.gpx_traces WHERE id = %L$$, pg_temp.id('gpx1')), 'Nouveau nom');
PERFORM pg_temp.ok('alice supprime sa trace', format($$SELECT public.delete_gpx_trace(%L)::text$$, pg_temp.id('gpx1')));
PERFORM pg_temp.denied('plafond de 50 traces', $$SELECT pg_temp.dc_gpx_fill(51)::text$$, 'junto.trace_quota_reached');
PERFORM pg_temp.eq('calcul de stats de trace', format($$SELECT (distance_km > 0 AND elevation_gain_m > 0)::text FROM public.compute_trace_stats(%L::jsonb)$$, pg_temp.dc_trace()), 'true');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('ts_before', (SELECT count(*)::text FROM public.rate_events WHERE user_id = pg_temp.id('alice') AND kind = 'trace_stats'));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('stats : forme invalide = aucune statistique (00482)', $$SELECT coalesce(distance_km::text, 'null') FROM public.compute_trace_stats('{"type":"Polygon","coordinates":[]}'::jsonb)$$, 'null');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('stats : une trace invalide est quand même comptée (00482)',
  format($$SELECT (count(*) - %s)::text FROM public.rate_events WHERE user_id = %L AND kind = 'trace_stats'$$, pg_temp.get('ts_before'), pg_temp.id('alice')), '1');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne calcule pas de stats', format($$SELECT distance_km::text FROM public.compute_trace_stats(%L::jsonb)$$, pg_temp.dc_trace()), 'Operation not permitted');
PERFORM pg_temp.denied('un compte suspendu n''enregistre pas de trace', format($$SELECT (public.create_gpx_trace('x', %L::jsonb)).id::text$$, pg_temp.dc_trace()), 'Operation not permitted');

-- ───── Validateur de trace (00484) ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('validateur : objet vide refusé sans erreur', $$SELECT public.trace_geojson_ok('{}'::jsonb)::text$$, 'false');
PERFORM pg_temp.eq('validateur : LineString sans coordonnées refusée', $$SELECT public.trace_geojson_ok('{"type":"LineString"}'::jsonb)::text$$, 'false');
PERFORM pg_temp.eq('validateur : coordonnées sans type refusées', $$SELECT public.trace_geojson_ok('{"coordinates":[[6,44],[6.1,44.1]]}'::jsonb)::text$$, 'false');
PERFORM pg_temp.eq('validateur : type nul refusé', $$SELECT public.trace_geojson_ok('{"type":null,"coordinates":[[6,44],[6.1,44.1]]}'::jsonb)::text$$, 'false');
PERFORM pg_temp.eq('validateur : altitude infinitésimale refusée', $$SELECT public.trace_geojson_ok('{"type":"LineString","coordinates":[[6,44,1e-400],[6.1,44.1]]}'::jsonb)::text$$, 'false');
PERFORM pg_temp.eq('validateur : trace normale acceptée (zéros compris)', $$SELECT public.trace_geojson_ok('{"type":"LineString","coordinates":[[0,0,0],[6.1,44.1,1200.5]]}'::jsonb)::text$$, 'true');

-- ───── Trace d'une sortie ─────
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice change la trace de sa sortie', format($$SELECT public.update_activity_trace(%L, %L::jsonb)::text$$, pg_temp.id('a_alice'), pg_temp.dc_trace(0.01)));
PERFORM pg_temp.eq('trace Polygon refusée', format($$SELECT public.update_activity_trace(%L, '{"type":"Polygon","coordinates":[]}'::jsonb)::text$$, pg_temp.id('a_alice')), 'junto.trace_geojson_invalid');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('une trace refusée laisse la trace précédente en place (00483)',
  format($$SELECT (trace_geojson->>'type')::text FROM public.activities WHERE id = %L$$, pg_temp.id('a_alice')), 'LineString');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('trace de plus de 10 000 points refusée',
  format($$SELECT public.update_activity_trace(%L, jsonb_build_object('type','LineString','coordinates',(SELECT jsonb_agg(jsonb_build_array(6, 44)) FROM generate_series(1, 10001))))::text$$, pg_temp.id('a_alice')), 'junto.trace_geojson_invalid');
PERFORM pg_temp.eq('trace avec latitude impossible refusée',
  format($$SELECT public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[6,44],[6,200]]}'::jsonb)::text$$, pg_temp.id('a_alice')), 'junto.trace_geojson_invalid');
PERFORM pg_temp.eq('trace avec point non numérique refusée',
  format($$SELECT public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[6,44],["a","b"]]}'::jsonb)::text$$, pg_temp.id('a_alice')), 'junto.trace_geojson_invalid');
PERFORM pg_temp.denied('alice ne change pas la trace de la sortie de bob',
  format($$SELECT public.update_activity_trace(%L, %L::jsonb)::text$$, pg_temp.id('a_pub'), pg_temp.dc_trace()), 'Operation not permitted');
PERFORM pg_temp.ok('alice efface la trace', format($$SELECT public.update_activity_trace(%L, NULL)::text$$, pg_temp.id('a_alice')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la trace est effacée', format($$SELECT (trace_geojson IS NULL)::text FROM public.activities WHERE id = %L$$, pg_temp.id('a_alice')), 'true');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('une trace refusée est quand même comptée (00483)',
  format($$SELECT (count(*) >= 4)::text FROM public.rate_events WHERE user_id = %L AND kind = 'activity_trace'$$, pg_temp.id('alice')), 'true');
PERFORM pg_temp.as_('alice');

-- ───── Favoris ─────
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('favori sur une sortie publique', format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_pub')));
PERFORM pg_temp.ok('favori idempotent', format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_pub')));
PERFORM pg_temp.ok('favori sur une offre', format($$SELECT public.add_favorite('offering', %L)::text$$, pg_temp.id('o_pub')));
PERFORM pg_temp.ok('favori sur un pro', format($$SELECT public.add_favorite('pro', %L)::text$$, pg_temp.id('pro1')));
PERFORM pg_temp.denied('pas de favori sur une sortie démo', format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_demo')), 'Operation not permitted');
PERFORM pg_temp.denied('pas de favori sur une sortie privée étrangère', format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_priv')), 'Operation not permitted');
PERFORM pg_temp.denied('pas de favori sur la sortie d''un suspendu', format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_sus')), 'Operation not permitted');
PERFORM pg_temp.denied('pas de favori sur la sortie d''un bloqué', format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_blk')), 'Operation not permitted');
PERFORM pg_temp.denied('pas de favori sur une offre démo', format($$SELECT public.add_favorite('offering', %L)::text$$, pg_temp.id('o_demo')), 'Operation not permitted');
PERFORM pg_temp.denied('pas de favori sur un pro démo', format($$SELECT public.add_favorite('pro', %L)::text$$, pg_temp.id('demo1')), 'Operation not permitted');
PERFORM pg_temp.denied('type de favori inconnu refusé', format($$SELECT public.add_favorite('user', %L)::text$$, pg_temp.id('bob')), 'Operation not permitted');
PERFORM pg_temp.eq('get_favorites liste 3 favoris', $$SELECT count(*)::text FROM public.get_favorites()$$, '3');
PERFORM pg_temp.ok('retrait d''un favori', format($$SELECT public.remove_favorite('activity', %L)::text$$, pg_temp.id('a_pub')));
PERFORM pg_temp.eq('get_favorites après retrait', $$SELECT count(*)::text FROM public.get_favorites()$$, '2');
PERFORM pg_temp.denied('pas d''écriture directe dans favorites',
  format($$INSERT INTO public.favorites (owner_id, activity_id) VALUES (%L, %L)$$, pg_temp.id('alice'), pg_temp.id('a_demo')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('bob ne voit pas les favoris d''alice', format($$SELECT count(*)::text FROM public.favorites WHERE owner_id = %L$$, pg_temp.id('alice')), '0');
PERFORM pg_temp.eq('get_favorites de bob vide', $$SELECT count(*)::text FROM public.get_favorites()$$, '0');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne met pas de favori', format($$SELECT public.add_favorite('activity', %L)::text$$, pg_temp.id('a_pub')), 'Operation not permitted');

-- ───── Trous connus (doivent échouer tant qu'ils ne sont pas corrigés) ─────
-- DB-DC-1 (trouvé par ces tests) : get_invitable_activities_for_dispo plante pour tout appelant
-- (« column reference "id" is ambiguous » : `FROM users WHERE id = v_user_id` contre la colonne
-- de sortie `id` de RETURNS TABLE) — le sélecteur « Inviter » de la Découverte est mort.
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('DC-1 : la zone d''une autre dispo est renvoyée arrondie (~1 km)',
  format($$SELECT (base_lng = round(base_lng::numeric, 2)::float8 AND base_lat = round(base_lat::numeric, 2)::float8)::text FROM public.get_dispo_zone(%L)$$, pg_temp.id('bob')),
  'true');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('DX-2 : la base de dispo est arrondie dès l''enregistrement',
  format($$SELECT (ST_X(base::geometry) = round(ST_X(base::geometry)::numeric, 2)::float8)::text FROM public.discovery_availabilities WHERE user_id = %L$$, pg_temp.id('bob')),
  'true');
PERFORM pg_temp.as_('carol');
PERFORM pg_temp.denied('DC-2 : le compteur refuse un rayon hors liste (sondage à 1 km)',
  $$SELECT public.get_discovery_count(ARRAY['hiking'], 6.083217, 44.561234, 1, now(), now() + interval '7 days')::text$$, 'junto\.dispo_radius');
-- 00520 (C1) : « peu importe » n'est plus un annuaire national — les zones doivent se croiser
-- (le rayon de l'autre doit contenir le point). Depuis l'autre bout du monde : personne.
PERFORM pg_temp.eq('C1 : « peu importe » depuis l''autre bout du monde ne trouve personne',
  $$SELECT public.get_discovery_count(ARRAY['hiking'], -120.5, -40.2, NULL, now(), now() + interval '7 days')::text$$, '0');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('DC-1 : la distance d''une carte Découverte est en km entiers (cartes présentes)',
  $$SELECT (count(*) > 0 AND bool_and(distance_km = round(distance_km) AND distance_km >= 1))::text FROM public.get_discovery_cards()$$, 'true');
PERFORM pg_temp.denied('DC-3 : changer 30 fois la trace d''une sortie est limité',
  format($$SELECT pg_temp.dc_trace_spam(%L, 30)::text$$, pg_temp.id('a_alice')), 'junto\.too_many_actions');
PERFORM pg_temp.denied('DC-3 : 700 calculs de stats de trace d''affilée sont limités',
  $$SELECT pg_temp.dc_stats_spam(700)::text$$, 'junto\.too_many_actions');
PERFORM pg_temp.as_('anon');
-- DC-4 fermé comme choix assumé (Scott 2026-10-21) : un lien partagé ouvre la page complète d'une
-- sortie PUBLIQUE sans compte (c'est ce qui donne envie). Une sortie privée reste fermée.
PERFORM pg_temp.eq('DC-4 (choix) : un lien partagé montre la sortie publique sans compte',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L AND description IS NOT NULL$$, pg_temp.id('a_pub')), '1');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('DC-6 : create_alert refuse un sport inconnu',
  $$SELECT public.create_alert(6.08, 44.56, 20, 'sport-inexistant')::text$$, '^Operation not permitted$');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.denied('DC-7 : un compte ne peut pas avoir deux dispos',
  format($$SELECT pg_temp.dc_dispo(%L, false, now() + interval '1 hour', now() + interval '2 days', false)::text$$, pg_temp.id('alice')), 'duplicate|violates');
PERFORM pg_temp.as_('past1');
PERFORM pg_temp.ok('past1 pose une dispo qui chevauche une dispo expirée',
  $$SELECT public.upsert_dispo(ARRAY['hiking'], NULL, 6.08, 44.56, 'Gap', 15, ARRAY['car'], now() - interval '23 hours', now() + interval '2 days')::text || public.activate_dispo()::text$$);
PERFORM pg_temp.eq('BR-5 : une dispo expirée n''est plus proposée',
  format($$SELECT count(*)::text FROM public.get_discovery_cards() WHERE user_id = %L$$, pg_temp.id('past2')), '0');
PERFORM pg_temp.as_('anon');
-- PV-1 (statistiques PostGIS) : hors d'atteinte par l'API, vérifié par `npm run test:api`.
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('AB-14 : la recherche de canaux borne la longueur de la requête',
  $$SELECT count(*)::text FROM public.search_channels(repeat('a', 5000))$$, '^Operation not permitted$');
