-- Domaine 23 — Lot B de l'audit global 2026-11-04 (mig 00581).
--
--   LB1 métiers d'un pro validé : un ajout devient une demande (pending_professions),
--       validée ou refusée par un admin dans l'app ; e-mail à l'équipe, notification au pro
--   LB3 couple bloqué : « Départ confirmé » et annulation automatique sans nom du pro
--   LB4 trace_geojson_ok : étapes sans conversion, caractères invisibles refusés
--   LB5 presence_end_reminder dans l'index anti-doublon
--   LB6 rappels quotidiens : une ligne en erreur n'annule plus les autres (contrôle statique)
--   LB7 liens d'agenda : noms masqués par défaut
--
-- set_pro_professions appelle net.http_post pour l'e-mail : l'appel est mis en file dans
-- la transaction, annulée comme toujours. On compte les rate_events à la place.

-- ───── Helpers locaux ─────
EXECUTE $p$CREATE FUNCTION pg_temp.lb_d(n integer) RETURNS date
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT private.today_paris() + n $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.lb_reg_sql(p_name text, p_profession text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.register_as_pro(p_display_name := %L, p_company_name := 'SARL Lot B', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon', p_profession := %L)::text$s$, p_name, p_profession) $b$$p$;
-- État des métiers : « acquis|en attente » (lisible quel que soit le rôle courant).
EXECUTE $p$CREATE FUNCTION pg_temp.lb_prof(p_label text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT professions::text || '|' || pending_professions::text FROM public.pro_profiles WHERE user_id = pg_temp.id(p_label) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.lb_mails(p_label text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT count(*)::text FROM public.rate_events WHERE user_id = pg_temp.id(p_label) AND kind = 'pro_profession_mail' $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.lb_notif(p_label text, p_type text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT count(*)::text || coalesce(':' || string_agg(data->'params'->>'profession', ','), '')
  FROM public.notifications WHERE user_id = pg_temp.id(p_label) AND type = p_type $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.lb_bk(p_label text, p_off text, p_client text, p_dn integer, p_status text) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.bookings (offering_id, pro_id, client_id, day, period, party_size, status,
                                 created_at, last_submitted_at, price_eur, price_unit)
    SELECT o.id, o.pro_id, pg_temp.id(p_client), pg_temp.lb_d(p_dn), 'am', 1, p_status,
           now() - INTERVAL '2 days', now() - INTERVAL '2 days', 50, 'person'
    FROM public.pro_offerings o WHERE o.id = pg_temp.id(p_off) RETURNING id INTO v;
    PERFORM pg_temp.put(p_label, v::text);
    RETURN v;
  END $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.lb_blk(a text, b text) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER AS $b$ BEGIN
    INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id(a), pg_temp.id(b));
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END $b$$p$;
-- Notification d'une réservation : « variante/nom/texte sans le nom du pro ».
EXECUTE $p$CREATE FUNCTION pg_temp.lb_bn(p_label text, p_type text, p_booking text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT string_agg(coalesce(data->>'variant', 'NULL') || '/' || coalesce(data->'params'->>'name', 'NULL') || '/'
                    || (title || body NOT LIKE '%Pro Lot B%')::text, ',')
  FROM public.notifications WHERE user_id = pg_temp.id(p_label) AND type = p_type AND data->>'booking_id' = pg_temp.get(p_booking) $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('lb_pro', 'tos');      -- pro validé (canyoning)
PERFORM pg_temp.user('lb_cand', 'tos');     -- candidature en attente
PERFORM pg_temp.user('lb_cli', 'tos');      -- membre
PERFORM pg_temp.user('lb_c1', 'tos');       -- client qui bloque le pro
PERFORM pg_temp.user('lb_c2', 'tos');       -- client témoin
PERFORM pg_temp.user('lb_c3', 'tos');       -- demandeur bloqué par le pro
PERFORM pg_temp.user('lb_c4', 'tos');       -- client accepté bloqué par le pro
PERFORM pg_temp.user('lb_sam', 'tos,suspended');
PERFORM pg_temp.user('lb_adm', 'tos,admin');
PERFORM pg_temp.user('lb_adm_sus', 'tos,admin,suspended');
PERFORM pg_temp.put('lb_sport', (SELECT id::text FROM public.sports WHERE key = 'canyoning'));

PERFORM pg_temp.as_('lb_pro');
PERFORM pg_temp.ok('LB0 inscription lb_pro', pg_temp.lb_reg_sql('Pro Lot B', 'canyoning_instructor'));
PERFORM pg_temp.as_('lb_cand');
PERFORM pg_temp.ok('LB0 inscription lb_cand', pg_temp.lb_reg_sql('Candidate Lot B', 'ski_instructor'));
PERFORM pg_temp.as_('lb_adm');
PERFORM pg_temp.ok('LB0 approbation lb_pro', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('lb_pro')));
PERFORM set_config('junto.bypass_lock', 'false', true);

-- ═════ LB1 — Demandes de métier ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('LB1 colonne pending_professions illisible par un compte',
  $$SELECT has_column_privilege('authenticated', 'public.pro_profiles', 'pending_professions', 'SELECT')::text
    || '/' || has_column_privilege('anon', 'public.pro_profiles', 'pending_professions', 'SELECT')::text$$, 'false/false');
PERFORM pg_temp.eq('LB1 fonction du garde-fou fermée aux clients',
  $$SELECT (has_function_privilege('anon', 'private.pro_profiles_profession_guard()', 'EXECUTE')
    OR has_function_privilege('authenticated', 'private.pro_profiles_profession_guard()', 'EXECUTE'))::text$$, 'false');
PERFORM pg_temp.eq('LB1 aucun accès anon aux nouvelles RPC',
  $$SELECT (has_function_privilege('anon', 'public.get_my_pending_professions()', 'EXECUTE')
    OR has_function_privilege('anon', 'public.admin_get_pro_profession_requests()', 'EXECUTE')
    OR has_function_privilege('anon', 'public.admin_decide_pro_profession(uuid, text, boolean)', 'EXECUTE')
    OR has_function_privilege('anon', 'public.set_pro_professions(text[])', 'EXECUTE'))::text$$, 'false');

-- Un pro validé ajoute un métier : il part en attente, e-mail à l'équipe.
PERFORM pg_temp.as_('lb_pro');
PERFORM pg_temp.eq('LB1 ajout : la fonction renvoie la demande',
  $$SELECT public.set_pro_professions(ARRAY['canyoning_instructor', 'climbing_instructor'])::text$$, '{climbing_instructor}');
PERFORM pg_temp.eq('LB1 ajout : la page garde ses métiers, le nouveau est en attente', $$SELECT pg_temp.lb_prof('lb_pro')$$, '{canyoning_instructor}|{climbing_instructor}');
PERFORM pg_temp.eq('LB1 ajout : un e-mail à l''équipe', $$SELECT pg_temp.lb_mails('lb_pro')$$, '1');
PERFORM pg_temp.eq('LB1 le pro relit sa demande', $$SELECT public.get_my_pending_professions()::text$$, '{climbing_instructor}');
PERFORM pg_temp.ok('LB1 même liste renvoyée', $$SELECT public.set_pro_professions(ARRAY['canyoning_instructor', 'climbing_instructor'])::text$$);
PERFORM pg_temp.eq('LB1 même demande : pas de second e-mail', $$SELECT pg_temp.lb_mails('lb_pro')$$, '1');
PERFORM pg_temp.ok('LB1 le pro place la demande en tête', $$SELECT public.set_pro_professions(ARRAY['climbing_instructor', 'canyoning_instructor'])::text$$);
PERFORM pg_temp.eq('LB1 un métier en attente ne passe jamais en tête de la page', $$SELECT pg_temp.lb_prof('lb_pro') || '|' || (SELECT profession FROM public.pro_profiles WHERE user_id = pg_temp.id('lb_pro'))$$,
  '{canyoning_instructor}|{climbing_instructor}|canyoning_instructor');
PERFORM pg_temp.denied('LB1 seulement des métiers en attente : il faut en garder un acquis',
  $$SELECT public.set_pro_professions(ARRAY['climbing_instructor'])::text$$, 'junto.profession_keep_one');
PERFORM pg_temp.ok('LB1 deux nouvelles demandes', $$SELECT public.set_pro_professions(ARRAY['canyoning_instructor', 'climbing_instructor', 'ski_instructor', 'other'])::text$$);
PERFORM pg_temp.eq('LB1 nouvelle demande : un second e-mail', $$SELECT pg_temp.lb_mails('lb_pro')$$, '2');
PERFORM pg_temp.ok('LB1 le pro retire « other »', $$SELECT public.set_pro_professions(ARRAY['canyoning_instructor', 'climbing_instructor', 'ski_instructor'])::text$$);
PERFORM pg_temp.eq('LB1 demande retirée', $$SELECT pg_temp.lb_prof('lb_pro')$$, '{canyoning_instructor}|{climbing_instructor,ski_instructor}');
PERFORM pg_temp.eq('LB1 un retrait n''envoie pas d''e-mail', $$SELECT pg_temp.lb_mails('lb_pro')$$, '2');
PERFORM pg_temp.denied('LB1 métier hors liste refusé', $$SELECT public.set_pro_professions(ARRAY['canyoning_instructor', 'astronaute'])::text$$, 'Operation not permitted');
-- Chemins de contournement.
PERFORM pg_temp.denied('LB1 ancien client : nouveau métier via update_pro_profile refusé',
  $$SELECT public.update_pro_profile(p_profession := 'mountain_guide')::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('LB1 pas d''écriture directe de la demande',
  format($$UPDATE public.pro_profiles SET pending_professions = ARRAY['other'] WHERE user_id = %L RETURNING 1$$, pg_temp.id('lb_pro')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.denied('LB1 garde-fou : même une fonction ne peut pas ajouter un métier à un pro validé',
  format($$UPDATE public.pro_profiles SET professions = professions || 'mountain_guide'::text WHERE user_id = %L RETURNING 1$$, pg_temp.id('lb_pro')), 'Operation not permitted');
PERFORM pg_temp.eq('LB1 rien n''a bougé', $$SELECT pg_temp.lb_prof('lb_pro')$$, '{canyoning_instructor}|{climbing_instructor,ski_instructor}');
-- Les autres ne voient rien.
PERFORM pg_temp.as_('lb_cli');
PERFORM pg_temp.denied('LB1 un membre ne lit pas la demande d''un pro',
  format($$SELECT pending_professions::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('lb_pro')));
PERFORM pg_temp.eq('LB1 un membre sans page pro : liste vide', $$SELECT public.get_my_pending_professions()::text$$, '{}');
PERFORM pg_temp.as_('lb_sam');
PERFORM pg_temp.eq('LB1 un suspendu : liste vide', $$SELECT public.get_my_pending_professions()::text$$, '{}');
-- Candidature en attente : liste libre (revue d'un bloc).
PERFORM pg_temp.as_('lb_cand');
PERFORM pg_temp.eq('LB1 candidature en attente : aucune demande séparée',
  $$SELECT public.set_pro_professions(ARRAY['ski_instructor', 'mountain_guide'])::text$$, '{}');
PERFORM pg_temp.eq('LB1 candidature en attente : liste enregistrée telle quelle', $$SELECT pg_temp.lb_prof('lb_cand')$$, '{ski_instructor,mountain_guide}|{}');
PERFORM pg_temp.eq('LB1 candidature : pas d''e-mail de métier', $$SELECT pg_temp.lb_mails('lb_cand')$$, '0');

-- Liste admin.
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('LB1 anon : pas de liste des demandes', $$SELECT count(*)::text FROM public.admin_get_pro_profession_requests()$$);
PERFORM pg_temp.as_('lb_cli');
PERFORM pg_temp.denied('LB1 un membre : pas de liste des demandes', $$SELECT count(*)::text FROM public.admin_get_pro_profession_requests()$$, 'Operation not permitted');
PERFORM pg_temp.as_('lb_pro');
PERFORM pg_temp.denied('LB1 un pro : pas de liste des demandes', $$SELECT count(*)::text FROM public.admin_get_pro_profession_requests()$$, 'Operation not permitted');
PERFORM pg_temp.as_('lb_adm_sus');
PERFORM pg_temp.denied('LB1 un admin suspendu : pas de liste des demandes', $$SELECT count(*)::text FROM public.admin_get_pro_profession_requests()$$, 'Operation not permitted');
PERFORM pg_temp.as_('lb_adm');
PERFORM pg_temp.eq('LB1 l''admin voit la demande (acquis, demandés, identité)',
  format($$SELECT professions::text || '|' || pending_professions::text || '|' || company_name || '|' || real_name
    FROM public.admin_get_pro_profession_requests() WHERE user_id = %L$$, pg_temp.id('lb_pro')),
  '{canyoning_instructor}|{climbing_instructor,ski_instructor}|SARL Lot B|Jean Test');
PERFORM pg_temp.eq('LB1 une candidature en attente n''est pas une demande de métier',
  format($$SELECT count(*)::text FROM public.admin_get_pro_profession_requests() WHERE user_id = %L$$, pg_temp.id('lb_cand')), '0');

-- Décision.
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('LB1 anon : pas de décision', format($$SELECT public.admin_decide_pro_profession(%L, 'climbing_instructor', true)::text$$, pg_temp.id('lb_pro')));
PERFORM pg_temp.as_('lb_pro');
PERFORM pg_temp.denied('LB1 le pro ne valide pas sa propre demande',
  format($$SELECT public.admin_decide_pro_profession(%L, 'climbing_instructor', true)::text$$, pg_temp.id('lb_pro')), 'Operation not permitted');
PERFORM pg_temp.as_('lb_adm_sus');
PERFORM pg_temp.denied('LB1 un admin suspendu ne décide pas',
  format($$SELECT public.admin_decide_pro_profession(%L, 'climbing_instructor', true)::text$$, pg_temp.id('lb_pro')), 'Operation not permitted');
PERFORM pg_temp.as_('lb_adm');
PERFORM pg_temp.denied('LB1 un métier non demandé ne se valide pas',
  format($$SELECT public.admin_decide_pro_profession(%L, 'mountain_guide', true)::text$$, pg_temp.id('lb_pro')), 'Operation not permitted');
PERFORM pg_temp.denied('LB1 décision NULL refusée',
  format($$SELECT public.admin_decide_pro_profession(%L, 'climbing_instructor', NULL)::text$$, pg_temp.id('lb_pro')), 'Operation not permitted');
PERFORM pg_temp.denied('LB1 pas de décision sur une candidature en attente',
  format($$SELECT public.admin_decide_pro_profession(%L, 'mountain_guide', true)::text$$, pg_temp.id('lb_cand')), 'Operation not permitted');
PERFORM pg_temp.ok('LB1 l''admin valide climbing_instructor',
  format($$SELECT public.admin_decide_pro_profession(%L, 'climbing_instructor', true)::text$$, pg_temp.id('lb_pro')));
PERFORM pg_temp.eq('LB1 validé : ajouté en fin de liste, retiré de la demande', $$SELECT pg_temp.lb_prof('lb_pro')$$, '{canyoning_instructor,climbing_instructor}|{ski_instructor}');
PERFORM pg_temp.eq('LB1 validé : le pro est notifié avec le métier', $$SELECT pg_temp.lb_notif('lb_pro', 'pro_profession_approved')$$, '1:climbing_instructor');
PERFORM pg_temp.eq('LB1 le garde-fou se referme après la validation',
  $$SELECT coalesce(current_setting('junto.profession_grant', true), '')$$, 'false');
PERFORM pg_temp.ok('LB1 l''admin refuse ski_instructor',
  format($$SELECT public.admin_decide_pro_profession(%L, 'ski_instructor', false)::text$$, pg_temp.id('lb_pro')));
PERFORM pg_temp.eq('LB1 refusé : retiré de la demande, page inchangée', $$SELECT pg_temp.lb_prof('lb_pro')$$, '{canyoning_instructor,climbing_instructor}|{}');
PERFORM pg_temp.eq('LB1 refusé : le pro est notifié', $$SELECT pg_temp.lb_notif('lb_pro', 'pro_profession_rejected')$$, '1:ski_instructor');
PERFORM pg_temp.denied('LB1 une demande tranchée ne se retranche pas',
  format($$SELECT public.admin_decide_pro_profession(%L, 'ski_instructor', true)::text$$, pg_temp.id('lb_pro')), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('LB1 les deux décisions sont au journal admin',
  format($$SELECT string_agg(action || ':' || reason, ',' ORDER BY action) FROM public.admin_actions WHERE target_id = %L AND action LIKE '%%pro_profession'$$, pg_temp.id('lb_pro')),
  'approve_pro_profession:climbing_instructor,reject_pro_profession:ski_instructor');
PERFORM pg_temp.eq('LB1 plus de demande : la liste admin ne le montre plus',
  format($$SELECT count(*)::text FROM public.pro_profiles WHERE user_id = %L AND cardinality(pending_professions) > 0$$, pg_temp.id('lb_pro')), '0');
-- Un métier validé se retire et se réordonne librement.
PERFORM pg_temp.as_('lb_pro');
PERFORM pg_temp.ok('LB1 le pro met le métier validé en avant', $$SELECT public.set_pro_professions(ARRAY['climbing_instructor', 'canyoning_instructor'])::text$$);
PERFORM pg_temp.eq('LB1 ordre libre parmi les acquis', $$SELECT pg_temp.lb_prof('lb_pro')$$, '{climbing_instructor,canyoning_instructor}|{}');
PERFORM pg_temp.ok('LB1 le pro retire un métier', $$SELECT public.set_pro_professions(ARRAY['climbing_instructor'])::text$$);
PERFORM pg_temp.eq('LB1 retrait libre', $$SELECT pg_temp.lb_prof('lb_pro')$$, '{climbing_instructor}|{}');
PERFORM pg_temp.eq('LB1 le remettre redevient une demande',
  $$SELECT public.set_pro_professions(ARRAY['climbing_instructor', 'canyoning_instructor'])::text$$, '{canyoning_instructor}');

-- ═════ LB3 — Couple bloqué : pas de nom du pro ═════
PERFORM pg_temp.as_('lb_pro');
PERFORM pg_temp.put('lb_off', pg_temp.ok('LB3 offre du pro', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := 'Canyon Lot B', p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon',
      p_max_participants := 8, p_price_eur := 50, p_price_unit := 'person', p_min_participants := 2)::text$$, pg_temp.id('lb_sport'))));
PERFORM pg_temp.as_('db');
UPDATE public.users SET display_name = 'Pro Lot B' WHERE id = pg_temp.id('lb_pro');
PERFORM pg_temp.lb_bk('bk1', 'lb_off', 'lb_c1', 5, 'accepted');
PERFORM pg_temp.lb_bk('bk2', 'lb_off', 'lb_c2', 5, 'accepted');
PERFORM pg_temp.lb_blk('lb_c1', 'lb_pro');
PERFORM pg_temp.eq('LB3 départ confirmé (minimum atteint)',
  format($$SELECT private.mark_outing_confirmed(%L, %L, %L, 'am', NULL, 'minimum')::text$$, pg_temp.id('lb_pro'), pg_temp.id('lb_off'), pg_temp.lb_d(5)), 'true');
PERFORM pg_temp.eq('LB3 « Départ confirmé » entre bloqués : pas de nom', $$SELECT pg_temp.lb_bn('lb_c1', 'booking_confirmed', 'bk1')$$, 'NULL/NULL/true');
PERFORM pg_temp.eq('LB3 (témoin) « Départ confirmé » sans blocage : le nom', $$SELECT pg_temp.lb_bn('lb_c2', 'booking_confirmed', 'bk2')$$, 'NULL/Pro Lot B/true');
PERFORM pg_temp.lb_bk('bk3', 'lb_off', 'lb_c3', 6, 'pending');
PERFORM pg_temp.lb_bk('bk4', 'lb_off', 'lb_c4', 6, 'accepted');
PERFORM pg_temp.lb_bk('bk5', 'lb_off', 'lb_c2', 6, 'pending');
-- Blocage posé directement (le trigger de blocage retirerait la demande en attente).
INSERT INTO public.blocked_users (blocker_id, blocked_id)
SELECT pg_temp.id('lb_pro'), u FROM unnest(ARRAY[pg_temp.id('lb_c3'), pg_temp.id('lb_c4')]) u;
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.bookings SET status = 'pending' WHERE id = pg_temp.id('bk3');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('LB3 annulation automatique : 3 réservations',
  format($$SELECT private.auto_cancel_outing_bookings(%L, %L, %L, 'am', NULL, 'Canyon Lot B')::text$$, pg_temp.id('lb_pro'), pg_temp.id('lb_off'), pg_temp.lb_d(6)), '3');
PERFORM pg_temp.eq('LB3 demande déclinée entre bloqués : variante neutre, pas de nom', $$SELECT pg_temp.lb_bn('lb_c3', 'booking_declined', 'bk3')$$, 'neutral/NULL/true');
PERFORM pg_temp.eq('LB3 réservation annulée entre bloqués : pas de nom', $$SELECT pg_temp.lb_bn('lb_c4', 'booking_cancelled', 'bk4')$$, 'auto_minimum/NULL/true');
PERFORM pg_temp.eq('LB3 (témoin) demande déclinée sans blocage : le nom', $$SELECT pg_temp.lb_bn('lb_c2', 'booking_declined', 'bk5')$$, 'NULL/Pro Lot B/false');

-- ═════ LB4 — trace_geojson_ok : étapes (fonction interne, appelée par les RPC de trace) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('LB4 étape normale acceptée',
  $$SELECT public.trace_geojson_ok('{"type":"LineString","coordinates":[[6.6,44.9],[6.7,45.0]],"waypoints":[{"lng":6.65,"lat":44.95,"kind":"summit","name":"Pic"}]}'::jsonb)::text$$, 'true');
PERFORM pg_temp.eq('LB4 longitude 1e400 : refusée proprement (plus d''erreur)',
  $$SELECT public.trace_geojson_ok('{"type":"LineString","coordinates":[[6.6,44.9],[6.7,45.0]],"waypoints":[{"lng":1e400,"lat":44.95,"kind":"summit"}]}'::jsonb)::text$$, 'false');
PERFORM pg_temp.eq('LB4 latitude hors bornes refusée',
  $$SELECT public.trace_geojson_ok('{"type":"LineString","coordinates":[[6.6,44.9],[6.7,45.0]],"waypoints":[{"lng":6.6,"lat":-91,"kind":"summit"}]}'::jsonb)::text$$, 'false');
PERFORM pg_temp.eq('LB4 valeur sous-normale refusée',
  $$SELECT public.trace_geojson_ok('{"type":"LineString","coordinates":[[6.6,44.9],[6.7,45.0]],"waypoints":[{"lng":1e-400,"lat":44.9,"kind":"summit"}]}'::jsonb)::text$$, 'false');
PERFORM pg_temp.eq('LB4 nom avec caractère invisible refusé',
  format($$SELECT public.trace_geojson_ok(%L::jsonb)::text$$,
    '{"type":"LineString","coordinates":[[6.6,44.9],[6.7,45.0]],"waypoints":[{"lng":6.6,"lat":44.9,"kind":"summit","name":"Pic' || chr(8238) || 'x"}]}'), 'false');
PERFORM pg_temp.eq('LB4 nom avec espace insécable accepté',
  format($$SELECT public.trace_geojson_ok(%L::jsonb)::text$$,
    '{"type":"LineString","coordinates":[[6.6,44.9],[6.7,45.0]],"waypoints":[{"lng":6.6,"lat":44.9,"kind":"summit","name":"Pic' || chr(160) || 'Nord"}]}'), 'true');

-- ═════ LB5 — Index anti-doublon ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('LB5 presence_end_reminder dans idx_notif_presence_dedup',
  $$SELECT (position('presence_end_reminder' in indexdef) > 0)::text FROM pg_indexes WHERE indexname = 'idx_notif_presence_dedup'$$, 'true');

-- ═════ LB6 — Rappels quotidiens : chaque envoi isolé (contrôle statique) ═════
PERFORM pg_temp.eq('LB6 les quatre rappels isolent chaque ligne',
  $$SELECT count(*)::text FROM unnest(ARRAY['private.notify_booking_reminders()', 'private.notify_booking_forms_reminders()',
      'private.notify_booking_forms_missing()', 'private.notify_pending_booking_requests()']) f
    WHERE position('EXCEPTION WHEN OTHERS' in pg_get_functiondef(f::regprocedure)) > 0$$, '4');

-- ═════ LB7 — Agenda externe : noms masqués par défaut ═════
PERFORM pg_temp.eq('LB7 hide_names vaut true par défaut',
  $$SELECT column_default FROM information_schema.columns WHERE table_schema = 'private' AND table_name = 'pro_calendar_links' AND column_name = 'hide_names'$$, 'true');
