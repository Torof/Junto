-- Domaine 20 — Vitrine pro : ajouts récents (mig 00538, 00540, 00554-00562, 00577).
--
--   PV1 renommage d'une vitrine approuvée → avis aux admins (00538)
--   PV2 HTML et caractères invisibles retirés des offres (00540)
--   PV3 demande pro : e-mail à l'équipe (00561, trigger) + fiche admin complète
--   PV4 plusieurs métiers (00562 set_pro_professions + trigger de synchro)
--   PV5 couvertures choisies par le pro (00562 set_pro_cover / set_offering_cover)
--   PV6 durée des demandes sur plusieurs jours (00577 set_offering_request_length)
--   PV7 pro_offerings_with_coords : ce que voient un visiteur et un membre
--   PV8 photos communautaires (VITRINE-1 corrigé 00578 : sortie finie, dossier community/<pro>/,
--       jamais sur sa propre page, signalement + retrait admin, fichiers non réécrivables)
--   PV9 avis pendant une sortie pas encore finie (VITRINE-3 corrigé 00578)
--
-- Déjà couvert ailleurs, pas répété ici : métier unique, sortie mise en avant,
-- avis réservés à qui a réservé (16), photos de vitrine/d'offre, avis, réponses (06).
-- VITRINE-2 (retrait par un admin du contenu d'une vitrine : galerie, couverture,
-- textes d'offre) est un lot ultérieur : pas de test ici.
-- notify_pro_application appelle net.http_post : on ne l'appelle jamais
-- directement. Les inscriptions / renvois de demande le déclenchent comme
-- partout ailleurs (l'appel HTTP est mis en file dans la transaction, annulée).

-- ───── Helpers locaux ─────
EXECUTE $p$CREATE FUNCTION pg_temp.pv_url(p_label text, p_file text) RETURNS text
  LANGUAGE sql AS $b$ SELECT pg_temp.host() || '/storage/v1/object/public/pro-photos/' || pg_temp.id(p_label)::text || '/' || p_file $b$$p$;
-- 00578 (VITRINE-1) : une photo communautaire vit dans <contributeur>/community/<pro>/.
EXECUTE $p$CREATE FUNCTION pg_temp.pv_cm(p_label text, p_file text) RETURNS text
  LANGUAGE sql AS $b$ SELECT pg_temp.pv_url(p_label, 'community/' || pg_temp.id('pv_pro')::text || '/' || p_file) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pv_register_sql(p_name text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.register_as_pro(p_display_name := %L, p_company_name := 'SARL Vitrine', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$s$, p_name) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pv_offering_sql(p_title text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_pro_offering(p_sport_id := %L, p_title := %L, p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon',
      p_max_participants := 8, p_price_eur := 50, p_price_unit := 'person')::text$s$, pg_temp.id('pv_sport'), p_title) $b$$p$;
-- Aujourd'hui + n jours (Europe/Paris), utilisable sous un rôle client.
EXECUTE $p$CREATE FUNCTION pg_temp.d(p_days int) RETURNS date
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT private.today_paris() + p_days $b$$p$;
-- Avis « pro_renamed » reçus par un admin pour un pro : nombre, ou « ancien→nouveau ».
EXECUTE $p$CREATE FUNCTION pg_temp.pv_renamed(p_admin text, p_pro text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT count(*)::text || coalesce(':' || string_agg((data->'params'->>'old') || '→' || (data->'params'->>'new'), ','), '')
  FROM public.notifications WHERE user_id = pg_temp.id(p_admin) AND type = 'pro_renamed' AND data->>'pro_id' = pg_temp.id(p_pro)::text $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.pv_mails(p_label text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT count(*)::text FROM public.rate_events WHERE user_id = pg_temp.id(p_label) AND kind = 'pro_application_mail' $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('pv_pro', 'tos');      -- pro approuvé principal
PERFORM pg_temp.user('pv_pro2', 'tos');     -- second pro approuvé (propriété croisée, états de visibilité)
PERFORM pg_temp.user('pv_cand', 'tos');     -- candidature en attente
PERFORM pg_temp.user('pv_new', 'tos');      -- candidature suivie pour l'e-mail de demande
PERFORM pg_temp.user('pv_cli', 'tos');      -- membre sans réservation
PERFORM pg_temp.user('pv_cli2', 'tos');     -- sortie faite (réservation acceptée passée)
PERFORM pg_temp.user('pv_cli3', 'tos');     -- réservation acceptée à venir
PERFORM pg_temp.user('pv_cli4', 'tos');     -- demande sur plusieurs jours en cours
PERFORM pg_temp.user('pv_cli5', 'tos');     -- date fixe en cours
PERFORM pg_temp.user('pv_cli6', 'tos');     -- demande sur plusieurs jours finie hier
PERFORM pg_temp.user('pv_cli7', 'tos');     -- date fixe finie
PERFORM pg_temp.user('pv_sam', 'tos,suspended');
PERFORM pg_temp.user('pv_adm', 'tos,admin');
PERFORM pg_temp.user('pv_adm_sus', 'tos,admin,suspended');
PERFORM pg_temp.put('pv_sport', (SELECT id::text FROM public.sports WHERE key = 'canyoning'));

PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV0 inscription pv_pro', pg_temp.pv_register_sql('Vitrine Alpha'));
PERFORM pg_temp.as_('pv_pro2');
PERFORM pg_temp.ok('PV0 inscription pv_pro2 avec un métier',
  $$SELECT public.register_as_pro(p_display_name := 'Vitrine Deux', p_company_name := 'SARL Deux', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Gap', p_profession := 'mountain_leader')::text$$);
PERFORM pg_temp.as_('pv_cand');
PERFORM pg_temp.ok('PV0 inscription pv_cand', pg_temp.pv_register_sql('Vitrine Candidate'));
PERFORM pg_temp.as_('pv_adm');
PERFORM pg_temp.ok('PV0 approbation pv_pro', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pv_pro')));
PERFORM pg_temp.ok('PV0 approbation pv_pro2', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pv_pro2')));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.put('pv_off', pg_temp.ok('PV0 pv_pro crée une offre', pg_temp.pv_offering_sql('Canyon du Fournel')));
PERFORM pg_temp.put('pv_offb', pg_temp.ok('PV0 pv_pro crée une seconde offre', pg_temp.pv_offering_sql('Canyon du Rif Bel')));
PERFORM pg_temp.as_('pv_pro2');
PERFORM pg_temp.put('pv_off2', pg_temp.ok('PV0 pv_pro2 crée une offre', pg_temp.pv_offering_sql('Rando des lacs')));

-- ═════ PV1 — Renommer une vitrine approuvée prévient les admins (00538) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV1 fonction de trigger fermée aux clients',
  $$SELECT (has_function_privilege('anon', 'private.notify_pro_renamed()', 'EXECUTE') OR has_function_privilege('authenticated', 'private.notify_pro_renamed()', 'EXECUTE'))::text$$, 'false');
PERFORM pg_temp.eq('PV1 aucun avis avant renommage', $$SELECT pg_temp.pv_renamed('pv_adm', 'pv_pro')$$, '0');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV1 le pro change d''accroche (pas de renommage)', $$SELECT public.update_pro_profile(p_tagline := 'Canyons des Écrins')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV1 changer l''accroche ne prévient personne', $$SELECT pg_temp.pv_renamed('pv_adm', 'pv_pro')$$, '0');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV1 le pro renomme sa vitrine', $$SELECT public.update_pro_profile(p_display_name := 'Vitrine Beta')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV1 l''admin reçoit « ancien → nouveau »', $$SELECT pg_temp.pv_renamed('pv_adm', 'pv_pro')$$, '1:Vitrine Alpha→Vitrine Beta');
PERFORM pg_temp.eq('PV1 un admin suspendu ne reçoit rien', $$SELECT pg_temp.pv_renamed('pv_adm_sus', 'pv_pro')$$, '0');
PERFORM pg_temp.eq('PV1 un membre ne reçoit rien', $$SELECT pg_temp.pv_renamed('pv_cli', 'pv_pro')$$, '0');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV1 second renommage dans la journée', $$SELECT public.update_pro_profile(p_display_name := '<b>Vitrine</b> Gamma')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV1 toujours un seul avis, remplacé : premier nom du jour → nom actuel (sans HTML)',
  $$SELECT pg_temp.pv_renamed('pv_adm', 'pv_pro')$$, '1:Vitrine Alpha→Vitrine Gamma');
PERFORM pg_temp.eq('PV1 l''avis remplacé est de nouveau non lu',
  format($$SELECT (read_at IS NULL)::text FROM public.notifications WHERE user_id = %L AND type = 'pro_renamed' AND data->>'pro_id' = %L$$, pg_temp.id('pv_adm'), pg_temp.id('pv_pro')), 'true');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV1 retour au nom du matin', $$SELECT public.update_pro_profile(p_display_name := 'Vitrine Alpha')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV1 retour au nom du matin : l''avis disparaît', $$SELECT pg_temp.pv_renamed('pv_adm', 'pv_pro')$$, '0');
PERFORM pg_temp.as_('pv_cand');
PERFORM pg_temp.ok('PV1 une candidature en attente se renomme', $$SELECT public.update_pro_profile(p_display_name := 'Candidate Bis')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV1 candidature en attente : pas d''avis de renommage', $$SELECT pg_temp.pv_renamed('pv_adm', 'pv_cand')$$, '0');

-- ═════ PV2 — Offres : HTML et caractères invisibles retirés (00540) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV2 fonction de trigger fermée aux clients',
  $$SELECT (has_function_privilege('anon', 'public.strip_html_offerings()', 'EXECUTE') OR has_function_privilege('authenticated', 'public.strip_html_offerings()', 'EXECUTE'))::text$$, 'false');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.put('pv_off_html', pg_temp.ok('PV2 création d''une offre avec du HTML et un caractère invisible',
  format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := %L, p_description := '<script>alert(1)</script>Belle sortie',
      p_level := '<i>Facile</i>', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := '<u>Fournel</u>',
      p_schedule_text := '<p>9h-12h</p>')::text$$, pg_temp.id('pv_sport'), '<b>Canyon</b> ' || chr(8203) || 'de test')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV2 titre, description, niveau, lieu, horaires nettoyés',
  format($$SELECT title || '|' || description || '|' || level || '|' || location_name || '|' || schedule_text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('pv_off_html')),
  'Canyon de test|alert(1)Belle sortie|Facile|Fournel|9h-12h');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV2 modification avec du HTML',
  format($$SELECT public.update_pro_offering(p_offering_id := %L, p_sport_id := %L, p_title := '<h1>Canyon</h1> modifié', p_description := 'Texte <img src=x onerror=alert(1)>propre',
      p_level := 'Sportif', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Fournel')::text$$, pg_temp.id('pv_off_html'), pg_temp.id('pv_sport')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV2 modification nettoyée',
  format($$SELECT title || '|' || description FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('pv_off_html')), 'Canyon modifié|Texte propre');
-- Le trigger nettoie aussi une écriture qui ne passe par aucune fonction (reprise, migration).
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_offerings SET title = '<marquee>Brut</marquee>' || chr(65279), level = 'Tous' || chr(8206) || ' niveaux' WHERE id = pg_temp.id('pv_off_html');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('PV2 écriture directe en base nettoyée aussi',
  format($$SELECT title || '|' || level FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('pv_off_html')), 'Brut|Tous niveaux');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('PV2 le visiteur lit le titre nettoyé',
  format($$SELECT title FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off_html')), 'Brut');

-- ═════ PV3 — Demande pro : e-mail à l'équipe + fiche admin (00561) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV3 le trigger d''e-mail n''est exécutable par aucun client',
  $$SELECT (has_function_privilege('anon', 'public.notify_pro_application()', 'EXECUTE') OR has_function_privilege('authenticated', 'public.notify_pro_application()', 'EXECUTE'))::text$$, 'false');
PERFORM pg_temp.eq('PV3 la fiche admin n''est pas exécutable par anon',
  $$SELECT has_function_privilege('anon', 'public.admin_get_pending_pro_applications()', 'EXECUTE')::text$$, 'false');
PERFORM pg_temp.eq('PV3 avant toute demande : aucun e-mail compté', $$SELECT pg_temp.pv_mails('pv_new')$$, '0');
PERFORM pg_temp.as_('pv_new');
PERFORM pg_temp.ok('PV3 pv_new dépose une demande', pg_temp.pv_register_sql('Nouvelle Vitrine'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV3 nouvelle demande : un e-mail (compté pour le plafond)', $$SELECT pg_temp.pv_mails('pv_new')$$, '1');
PERFORM pg_temp.as_('pv_new');
PERFORM pg_temp.ok('PV3 la candidate complète sa demande en attente', $$SELECT public.update_pro_profile(p_tagline := 'Guide de canyon')::text$$);
PERFORM pg_temp.denied('PV3 la candidate ne lit pas le compteur d''e-mails', $$SELECT count(*)::text FROM public.rate_events$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV3 modifier une demande en attente ne renvoie pas d''e-mail', $$SELECT pg_temp.pv_mails('pv_new')$$, '1');
PERFORM pg_temp.as_('pv_adm');
PERFORM pg_temp.ok('PV3 l''admin refuse la demande', format($$SELECT public.reject_pro(%L, 'Pièce manquante')::text$$, pg_temp.id('pv_new')));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV3 un refus n''envoie pas d''e-mail à l''équipe', $$SELECT pg_temp.pv_mails('pv_new')$$, '1');
PERFORM pg_temp.as_('pv_new');
PERFORM pg_temp.ok('PV3 la candidate renvoie sa demande', $$SELECT public.resubmit_pro_application()::text$$);
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV3 demande renvoyée : un nouvel e-mail', $$SELECT pg_temp.pv_mails('pv_new')$$, '2');
-- Plafond : 3 e-mails par compte et par 24 h (le 3e est posé en base).
INSERT INTO public.rate_events (user_id, kind) VALUES (pg_temp.id('pv_new'), 'pro_application_mail');
PERFORM pg_temp.as_('pv_adm');
PERFORM pg_temp.ok('PV3 nouveau refus', format($$SELECT public.reject_pro(%L, 'Toujours incomplet')::text$$, pg_temp.id('pv_new')));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('pv_new');
PERFORM pg_temp.ok('PV3 nouveau renvoi au-delà du plafond', $$SELECT public.resubmit_pro_application()::text$$);
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV3 plafond atteint : pas de 4e e-mail', $$SELECT pg_temp.pv_mails('pv_new')$$, '3');
PERFORM pg_temp.eq('PV3 plafond atteint : la demande passe quand même en attente',
  format($$SELECT status FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_new')), 'pending');
-- Fiche admin complète.
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('PV3 anon : pas de fiche admin', $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications()$$);
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.denied('PV3 un membre : pas de fiche admin', $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications()$$, 'Operation not permitted');
PERFORM pg_temp.as_('pv_new');
PERFORM pg_temp.denied('PV3 la candidate : pas de fiche admin', $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications()$$, 'Operation not permitted');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.denied('PV3 un pro approuvé : pas de fiche admin', $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications()$$, 'Operation not permitted');
PERFORM pg_temp.as_('pv_adm_sus');
PERFORM pg_temp.denied('PV3 un admin suspendu : pas de fiche admin', $$SELECT count(*)::text FROM public.admin_get_pending_pro_applications()$$, 'Operation not permitted');
PERFORM pg_temp.as_('pv_adm');
PERFORM pg_temp.eq('PV3 l''admin voit toute la demande (identité, contacts, accroche, historique)',
  format($$SELECT real_name || '|' || company_name || '|' || tagline || '|' || prior_review_count || '|' || last_review_action || '|' || (account_created_at IS NOT NULL)::text
    FROM public.admin_get_pending_pro_applications() WHERE user_id = %L$$, pg_temp.id('pv_new')),
  'Jean Test|SARL Vitrine|Guide de canyon|2|reject_pro|true');
PERFORM pg_temp.eq('PV3 la fiche admin ne liste que les demandes en attente',
  format($$SELECT count(*)::text FROM public.admin_get_pending_pro_applications() WHERE user_id IN (%L, %L)$$, pg_temp.id('pv_pro'), pg_temp.id('pv_pro2')), '0');
PERFORM pg_temp.ok('PV3 l''admin approuve pv_new', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pv_new')));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV3 une approbation n''envoie pas d''e-mail à l''équipe', $$SELECT pg_temp.pv_mails('pv_new')$$, '3');

-- ═════ PV4 — Plusieurs métiers (00562) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV4 inscription avec un métier : liste = ce métier',
  format($$SELECT professions::text || '|' || profession FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro2')), '{mountain_leader}|mountain_leader');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('PV4 anon : pas de métiers', $$SELECT public.set_pro_professions(ARRAY['other'])::text$$);
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.denied('PV4 un non-pro : pas de métiers', $$SELECT public.set_pro_professions(ARRAY['other'])::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('pv_sam');
PERFORM pg_temp.denied('PV4 un suspendu : pas de métiers', $$SELECT public.set_pro_professions(ARRAY['other'])::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('pv_cand');
PERFORM pg_temp.ok('PV4 une candidature en attente choisit ses métiers (doublon)',
  $$SELECT public.set_pro_professions(ARRAY['canyoning_instructor', 'climbing_instructor', 'canyoning_instructor'])::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV4 doublon retiré, ordre gardé, le premier est le métier mis en avant',
  format($$SELECT professions::text || '|' || profession FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_cand')), '{canyoning_instructor,climbing_instructor}|canyoning_instructor');
PERFORM pg_temp.as_('pv_adm');
PERFORM pg_temp.eq('PV4 la fiche admin montre les métiers',
  format($$SELECT professions::text FROM public.admin_get_pending_pro_applications() WHERE user_id = %L$$, pg_temp.id('pv_cand')), '{canyoning_instructor,climbing_instructor}');
PERFORM pg_temp.as_('pv_cand');
PERFORM pg_temp.denied('PV4 un métier hors liste refuse toute la liste', $$SELECT public.set_pro_professions(ARRAY['mountain_guide', 'astronaute'])::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('PV4 la casse compte (liste fermée)', $$SELECT public.set_pro_professions(ARRAY['Mountain_guide'])::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV4 liste refusée : rien ne change',
  format($$SELECT professions::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_cand')), '{canyoning_instructor,climbing_instructor}');
PERFORM pg_temp.as_('pv_cand');
PERFORM pg_temp.ok('PV4 liste vide', $$SELECT public.set_pro_professions(ARRAY[]::text[])::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV4 liste vide : plus de métier', format($$SELECT professions::text || '|' || coalesce(profession, 'null') FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_cand')), '{}|null');
PERFORM pg_temp.as_('pv_cand');
PERFORM pg_temp.ok('PV4 NULL vaut liste vide', $$SELECT public.set_pro_professions(NULL)::text$$);
PERFORM pg_temp.ok('PV4 les 13 métiers à la fois',
  $$SELECT public.set_pro_professions(ARRAY['mountain_guide', 'mountain_leader', 'climbing_instructor', 'canyoning_instructor', 'paragliding_instructor',
      'ski_instructor', 'mtb_instructor', 'whitewater_instructor', 'diving_instructor', 'surf_instructor', 'wellness_instructor', 'school_office', 'other'])::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV4 13 métiers enregistrés', format($$SELECT cardinality(professions)::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_cand')), '13');
-- Pro approuvé + synchro avec l'ancien champ unique (builds publiés).
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV4 le pro approuvé choisit deux métiers', $$SELECT public.set_pro_professions(ARRAY['ski_instructor', 'mountain_guide'])::text$$);
PERFORM pg_temp.denied('PV4 pas d''écriture directe des métiers',
  format($$UPDATE public.pro_profiles SET professions = ARRAY['other'] WHERE user_id = %L RETURNING 1$$, pg_temp.id('pv_pro')));
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.eq('PV4 les métiers sont lisibles par un autre membre',
  format($$SELECT professions::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro')), '{ski_instructor,mountain_guide}');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV4 ancien client : nouveau métier unique via update_pro_profile', $$SELECT public.update_pro_profile(p_profession := 'climbing_instructor')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV4 synchro : le nouveau métier passe en tête, les autres restent',
  format($$SELECT professions::text || '|' || profession FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro')), '{climbing_instructor,ski_instructor,mountain_guide}|climbing_instructor');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV4 ancien client : un métier déjà dans la liste', $$SELECT public.update_pro_profile(p_profession := 'mountain_guide')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV4 synchro : déplacé en tête, sans doublon',
  format($$SELECT professions::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro')), '{mountain_guide,climbing_instructor,ski_instructor}');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV4 ancien client : vider le métier', $$SELECT public.update_pro_profile(p_clear := ARRAY['profession'])::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV4 synchro : vider le métier vide la liste',
  format($$SELECT professions::text || '|' || coalesce(profession, 'null') FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro')), '{}|null');

-- ═════ PV5 — Couvertures choisies par le pro (00562) ═════
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.put('pv_ph_a', pg_temp.ok('PV5 photo de vitrine A', format($$SELECT public.add_pro_photo(%L)::text$$, pg_temp.pv_url('pv_pro', 'a.jpg'))));
PERFORM pg_temp.put('pv_ph_b', pg_temp.ok('PV5 photo de vitrine B', format($$SELECT public.add_pro_photo(%L)::text$$, pg_temp.pv_url('pv_pro', 'b.jpg'))));
PERFORM pg_temp.ok('PV5 le pro choisit la photo A en couverture', format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_pro', 'a.jpg')));
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.eq('PV5 la couverture est lisible par un autre membre',
  format($$SELECT cover_url FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro')), pg_temp.pv_url('pv_pro', 'a.jpg'));
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.denied('PV5 couverture dans le dossier d''un autre pro refusée', format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_pro2', 'a.jpg')), 'Operation not permitted');
PERFORM pg_temp.denied('PV5 couverture hors stockage refusée', $$SELECT public.set_pro_cover('https://evil.example/a.jpg')::text$$, 'Operation not permitted');
PERFORM pg_temp.denied('PV5 couverture : remontée « .. » refusée',
  format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_pro', '../' || pg_temp.id('pv_pro2')::text || '/a.jpg')), 'Operation not permitted');
PERFORM pg_temp.denied('PV5 couverture : remontée encodée %2e%2e refusée',
  format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_pro', '%2e%2e/' || pg_temp.id('pv_pro2')::text || '/a.jpg')), 'Operation not permitted');
PERFORM pg_temp.denied('PV5 pas d''écriture directe de la couverture',
  format($$UPDATE public.pro_profiles SET cover_url = 'https://evil.example/x.jpg' WHERE user_id = %L RETURNING 1$$, pg_temp.id('pv_pro')));
PERFORM pg_temp.denied('PV5 VITRINE-4 une image hors galerie (même dans son dossier) refusée en couverture',
  format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_pro', 'hors-galerie.jpg')), 'Operation not permitted');
-- 00578 (VITRINE-4) : ou un fichier de son propre dossier cover/ (couverture prise du téléphone).
PERFORM pg_temp.ok('PV5 VITRINE-4 un fichier de son dossier cover/ accepté en couverture',
  format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_pro', 'cover/tel.jpg')));
PERFORM pg_temp.eq('PV5 la couverture est le fichier du dossier cover/',
  format($$SELECT cover_url FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro')), pg_temp.pv_url('pv_pro', 'cover/tel.jpg'));
PERFORM pg_temp.denied('PV5 VITRINE-4 le dossier cover/ d''un autre pro refusé',
  format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_pro2', 'cover/tel.jpg')), 'Operation not permitted');
PERFORM pg_temp.ok('PV5 la couverture A est remise', format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_pro', 'a.jpg')));
PERFORM pg_temp.as_('pv_cand');
PERFORM pg_temp.denied('PV5 une candidature en attente n''a pas de couverture', format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_cand', 'a.jpg')), 'Operation not permitted');
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.denied('PV5 un non-pro n''a pas de couverture', format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_cli', 'a.jpg')), 'Operation not permitted');
PERFORM pg_temp.as_('pv_sam');
PERFORM pg_temp.denied('PV5 un suspendu n''a pas de couverture', $$SELECT public.set_pro_cover(NULL)::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('PV5 anon : pas de couverture', $$SELECT public.set_pro_cover(NULL)::text$$);
PERFORM pg_temp.denied('PV5 anon : pas de couverture d''offre', format($$SELECT public.set_offering_cover(%L, NULL)::text$$, pg_temp.id('pv_off')));
-- Supprimer une photo de galerie vide la couverture seulement si c'était elle.
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV5 le pro retire la photo B (pas la couverture)', format($$SELECT public.remove_pro_photo(%L)::text$$, pg_temp.id('pv_ph_b')));
PERFORM pg_temp.eq('PV5 la couverture reste', format($$SELECT cover_url FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro')), pg_temp.pv_url('pv_pro', 'a.jpg'));
PERFORM pg_temp.ok('PV5 le pro retire la photo A (la couverture)', format($$SELECT public.remove_pro_photo(%L)::text$$, pg_temp.id('pv_ph_a')));
PERFORM pg_temp.eq('PV5 la couverture est vidée avec sa photo', format($$SELECT coalesce(cover_url, 'null') FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro')), 'null');
PERFORM pg_temp.put('pv_ph_c', pg_temp.ok('PV5 photo de vitrine C', format($$SELECT public.add_pro_photo(%L)::text$$, pg_temp.pv_url('pv_pro', 'c.jpg'))));
PERFORM pg_temp.ok('PV5 couverture C', format($$SELECT public.set_pro_cover(%L)::text$$, pg_temp.pv_url('pv_pro', 'c.jpg')));
PERFORM pg_temp.ok('PV5 NULL retire la couverture', $$SELECT public.set_pro_cover(NULL)::text$$);
PERFORM pg_temp.eq('PV5 couverture retirée', format($$SELECT coalesce(cover_url, 'null') FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pv_pro')), 'null');
-- Couverture d'une offre.
PERFORM pg_temp.put('pv_oph1', pg_temp.ok('PV5 photo de l''offre', format($$SELECT public.add_pro_offering_photo(%L, %L)::text$$, pg_temp.id('pv_off'), pg_temp.pv_url('pv_pro', 'o1.jpg'))));
PERFORM pg_temp.put('pv_ophb', pg_temp.ok('PV5 photo de la seconde offre', format($$SELECT public.add_pro_offering_photo(%L, %L)::text$$, pg_temp.id('pv_offb'), pg_temp.pv_url('pv_pro', 'ob.jpg'))));
PERFORM pg_temp.ok('PV5 le pro choisit la couverture de son offre', format($$SELECT public.set_offering_cover(%L, %L)::text$$, pg_temp.id('pv_off'), pg_temp.pv_url('pv_pro', 'o1.jpg')));
PERFORM pg_temp.denied('PV5 couverture d''offre dans le dossier d''un autre refusée', format($$SELECT public.set_offering_cover(%L, %L)::text$$, pg_temp.id('pv_off'), pg_temp.pv_url('pv_pro2', 'o1.jpg')), 'Operation not permitted');
PERFORM pg_temp.denied('PV5 couverture sur l''offre d''un autre pro refusée', format($$SELECT public.set_offering_cover(%L, %L)::text$$, pg_temp.id('pv_off2'), pg_temp.pv_url('pv_pro', 'o1.jpg')), 'Operation not permitted');
PERFORM pg_temp.denied('PV5 couverture sur une offre inexistante refusée (même erreur)', format($$SELECT public.set_offering_cover(%L, NULL)::text$$, gen_random_uuid()), 'Operation not permitted');
PERFORM pg_temp.denied('PV5 pas d''écriture directe de la couverture d''offre',
  format($$UPDATE public.pro_offerings SET cover_url = 'https://evil.example/x.jpg' WHERE id = %L RETURNING 1$$, pg_temp.id('pv_off')));
PERFORM pg_temp.denied('PV5 VITRINE-4 la photo d''une AUTRE offre refusée en couverture',
  format($$SELECT public.set_offering_cover(%L, %L)::text$$, pg_temp.id('pv_off'), pg_temp.pv_url('pv_pro', 'ob.jpg')), 'Operation not permitted');
PERFORM pg_temp.denied('PV5 VITRINE-4 une image hors galerie refusée en couverture d''offre',
  format($$SELECT public.set_offering_cover(%L, %L)::text$$, pg_temp.id('pv_off'), pg_temp.pv_url('pv_pro', 'hors-galerie.jpg')), 'Operation not permitted');
-- 00578 (VITRINE-4) : ou un fichier de offering/<cette offre>/cover/.
PERFORM pg_temp.ok('PV5 VITRINE-4 un fichier de offering/<offre>/cover/ accepté en couverture d''offre',
  format($$SELECT public.set_offering_cover(%L, %L)::text$$, pg_temp.id('pv_off'), pg_temp.pv_url('pv_pro', 'offering/' || pg_temp.get('pv_off') || '/cover/tel.jpg')));
PERFORM pg_temp.eq('PV5 la couverture d''offre est le fichier du dossier cover/',
  format($$SELECT cover_url FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('pv_off')), pg_temp.pv_url('pv_pro', 'offering/' || pg_temp.get('pv_off') || '/cover/tel.jpg'));
PERFORM pg_temp.denied('PV5 VITRINE-4 le dossier cover/ d''une AUTRE offre refusé',
  format($$SELECT public.set_offering_cover(%L, %L)::text$$, pg_temp.id('pv_off'), pg_temp.pv_url('pv_pro', 'offering/' || pg_temp.get('pv_offb') || '/cover/tel.jpg')), 'Operation not permitted');
PERFORM pg_temp.ok('PV5 remise de la bonne couverture d''offre', format($$SELECT public.set_offering_cover(%L, %L)::text$$, pg_temp.id('pv_off'), pg_temp.pv_url('pv_pro', 'o1.jpg')));
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('PV5 l''image de l''offre (visiteur) = la couverture choisie',
  format($$SELECT image_url FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off')), pg_temp.pv_url('pv_pro', 'o1.jpg'));
PERFORM pg_temp.eq('PV5 une offre sans couverture choisie n''a pas d''image (pas de « première photo »)',
  format($$SELECT coalesce(image_url, 'null') FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_offb')), 'null');
PERFORM pg_temp.as_('pv_pro2');
PERFORM pg_temp.denied('PV5 pv_pro2 ne change pas la couverture de l''offre de pv_pro', format($$SELECT public.set_offering_cover(%L, NULL)::text$$, pg_temp.id('pv_off')), 'Operation not permitted');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV5 la photo de couverture de l''offre est retirée', format($$SELECT public.remove_pro_offering_photo(%L)::text$$, pg_temp.id('pv_oph1')));
PERFORM pg_temp.eq('PV5 la couverture de l''offre est vidée avec sa photo',
  format($$SELECT coalesce(cover_url, 'null') FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('pv_off')), 'null');

-- ═════ PV6 — Demandes sur plusieurs jours : set_offering_request_length (00577) ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('PV6 anon : refusé', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('pv_off')));
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.denied('PV6 un non-pro : refusé', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('pv_off')), 'Operation not permitted');
PERFORM pg_temp.as_('pv_cand');
PERFORM pg_temp.denied('PV6 une candidature en attente : refusé', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('pv_off')), 'Operation not permitted');
PERFORM pg_temp.as_('pv_pro2');
PERFORM pg_temp.denied('PV6 l''offre d''un autre pro : refusé', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('pv_off')), 'Operation not permitted');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.denied('PV6 offre inexistante : même erreur', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, gen_random_uuid()), 'Operation not permitted');
PERFORM pg_temp.denied('PV6 0 jour refusé', format($$SELECT public.set_offering_request_length(%L, 0)::text$$, pg_temp.id('pv_off')), 'junto.offering_request_days');
PERFORM pg_temp.denied('PV6 -1 jour refusé', format($$SELECT public.set_offering_request_length(%L, -1)::text$$, pg_temp.id('pv_off')), 'junto.offering_request_days');
PERFORM pg_temp.denied('PV6 15 jours refusé', format($$SELECT public.set_offering_request_length(%L, 15)::text$$, pg_temp.id('pv_off')), 'junto.offering_request_days');
PERFORM pg_temp.ok('PV6 14 jours accepté', format($$SELECT public.set_offering_request_length(%L, 14)::text$$, pg_temp.id('pv_off')));
PERFORM pg_temp.ok('PV6 1 jour (la journée) accepté', format($$SELECT public.set_offering_request_length(%L, 1)::text$$, pg_temp.id('pv_off')));
PERFORM pg_temp.denied('PV6 pas d''écriture directe de la durée',
  format($$UPDATE public.pro_offerings SET request_days = 5 WHERE id = %L RETURNING 1$$, pg_temp.id('pv_off')));
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('PV6 le visiteur lit la durée des demandes', format($$SELECT request_days::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off')), '1');
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.eq('PV6 un membre lit la durée des demandes', format($$SELECT request_days::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off')), '1');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV6 NULL = retour aux demi-journées', format($$SELECT public.set_offering_request_length(%L, NULL)::text$$, pg_temp.id('pv_off')));
PERFORM pg_temp.eq('PV6 durée retirée', format($$SELECT coalesce(request_days::text, 'null') FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off')), 'null');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = now() WHERE id = pg_temp.id('pv_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('pv_pro2');
PERFORM pg_temp.denied('PV6 un pro suspendu : refusé', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('pv_off2')), 'Operation not permitted');

-- ═════ PV7 — pro_offerings_with_coords : ce qui est montré ═════
-- (pv_pro2 est suspendu à ce stade.)
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('PV7 visiteur : l''offre d''un pro approuvé est visible', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off')), '1');
PERFORM pg_temp.eq('PV7 visiteur : l''offre d''un pro suspendu est cachée', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off2')), '0');
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.eq('PV7 membre : l''offre d''un pro approuvé est visible', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off')), '1');
PERFORM pg_temp.eq('PV7 membre : l''offre d''un pro suspendu est cachée', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off2')), '0');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = NULL WHERE id = pg_temp.id('pv_pro2');
-- Vitrine plus approuvée (posé en base : « refusée », sans déclencher l'e-mail de demande).
UPDATE public.pro_profiles SET status = 'rejected' WHERE user_id = pg_temp.id('pv_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('PV7 visiteur : l''offre d''un pro non approuvé est cachée', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off2')), '0');
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.eq('PV7 membre : l''offre d''un pro non approuvé est cachée', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off2')), '0');
PERFORM pg_temp.as_('pv_pro2');
PERFORM pg_temp.eq('PV7 le pro non approuvé voit encore sa propre offre', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off2')), '1');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET status = 'approved', is_demo = true WHERE user_id = pg_temp.id('pv_pro2');
UPDATE public.pro_offerings SET is_demo = true WHERE pro_id = pg_temp.id('pv_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('PV7 visiteur : une offre démo est cachée', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off2')), '0');
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.eq('PV7 membre : une offre démo est cachée', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off2')), '0');
PERFORM pg_temp.as_('pv_cli2');
PERFORM pg_temp.denied('PV7 pas de photo communautaire sur une vitrine démo',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro2'), pg_temp.pv_url('pv_cli2', 'community/' || pg_temp.get('pv_pro2') || '/demo.jpg')), 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET is_demo = false WHERE user_id = pg_temp.id('pv_pro2');
UPDATE public.pro_offerings SET is_demo = false WHERE pro_id = pg_temp.id('pv_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('PV7 retour à la normale : l''offre de pv_pro2 réapparaît', format($$SELECT count(*)::text FROM public.pro_offerings_with_coords WHERE id = %L$$, pg_temp.id('pv_off2')), '1');
PERFORM pg_temp.eq('PV7 la vue ne montre pas l''identité légale du pro',
  $$SELECT count(*)::text FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pro_offerings_with_coords'
      AND column_name IN ('real_name', 'company_name', 'email', 'phone', 'rejection_reason')$$, '0');

-- ═════ PV8 — Photos communautaires ═════
-- Réservations posées en base (T = aujourd'hui) : qui a fait une sortie, qui n'a pas fini.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('pv_sess_now', gen_random_uuid()::text);
PERFORM pg_temp.put('pv_sess_done', gen_random_uuid()::text);
INSERT INTO public.pro_sessions (id, pro_id, offering_id, start_day, start_period, end_day, end_period, max_participants, status) VALUES
  (pg_temp.id('pv_sess_now'),  pg_temp.id('pv_pro'), pg_temp.id('pv_off'), pg_temp.d(-1), 'am', pg_temp.d(1), 'pm', 8, 'scheduled'),
  (pg_temp.id('pv_sess_done'), pg_temp.id('pv_pro'), pg_temp.id('pv_off'), pg_temp.d(-4), 'am', pg_temp.d(-2), 'pm', 8, 'scheduled');
INSERT INTO public.bookings (offering_id, pro_id, client_id, day, period, end_day, party_size, status, session_id) VALUES
  (pg_temp.id('pv_off'), pg_temp.id('pv_pro'), pg_temp.id('pv_cli2'), pg_temp.d(-5), 'am', NULL,         2, 'accepted', NULL),
  (pg_temp.id('pv_off'), pg_temp.id('pv_pro'), pg_temp.id('pv_cli3'), pg_temp.d(5),  'am', NULL,         2, 'accepted', NULL),
  (pg_temp.id('pv_off'), pg_temp.id('pv_pro'), pg_temp.id('pv_cli4'), pg_temp.d(-1), 'am', pg_temp.d(1), 2, 'accepted', NULL),
  (pg_temp.id('pv_off'), pg_temp.id('pv_pro'), pg_temp.id('pv_cli5'), pg_temp.d(-1), 'am', NULL,         1, 'accepted', pg_temp.id('pv_sess_now')),
  (pg_temp.id('pv_off'), pg_temp.id('pv_pro'), pg_temp.id('pv_cli6'), pg_temp.d(-4), 'am', pg_temp.d(-1), 2, 'accepted', NULL),
  (pg_temp.id('pv_off'), pg_temp.id('pv_pro'), pg_temp.id('pv_cli7'), pg_temp.d(-4), 'am', NULL,         1, 'accepted', pg_temp.id('pv_sess_done'));

-- Chaîne (00578, VITRINE-1) : auth, suspension, pro non suspendu, pas sa propre page, pas bloqué par le
-- pro, pro approuvé non démo, fichier dans <moi>/community/<pro>/, réservation acceptée et sortie finie
-- (avec cette offre si précisée), avis à soi, offre de ce pro, plafond 5.
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('PV8 anon : pas de photo communautaire', format($$SELECT public.add_pro_community_photo(%L, 'https://x/y.jpg')::text$$, pg_temp.id('pv_pro')));
PERFORM pg_temp.as_('pv_sam');
PERFORM pg_temp.denied('PV8 un suspendu : pas de photo communautaire',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_sam', 's.jpg')), 'Operation not permitted');
PERFORM pg_temp.as_('pv_cli2');
PERFORM pg_temp.put('pv_cp1', pg_temp.ok('PV8 sortie faite : photo communautaire acceptée',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli2', 'p1.jpg'))));
PERFORM pg_temp.put('pv_cp2', pg_temp.ok('PV8 sortie faite : photo rattachée à l''offre réservée',
  format($$SELECT public.add_pro_community_photo(%L, %L, NULL, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli2', 'p2.jpg'), pg_temp.id('pv_off'))));
PERFORM pg_temp.put('pv_rv2', pg_temp.ok('PV8 sortie faite : avis sur le pro', format($$SELECT public.create_pro_review(%L, 5::smallint, 'Super sortie')::text$$, pg_temp.id('pv_pro'))));
PERFORM pg_temp.ok('PV8 photo rattachée à son propre avis',
  format($$SELECT public.add_pro_community_photo(%L, %L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli2', 'p3.jpg'), pg_temp.id('pv_rv2')));
PERFORM pg_temp.denied('PV8 photo hors de son propre dossier refusée',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli3', 'p.jpg')), 'Operation not permitted');
PERFORM pg_temp.denied('PV8 photo de son dossier mais hors community/<pro>/ refusée',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_url('pv_cli2', 'p5.jpg')), 'Operation not permitted');
PERFORM pg_temp.denied('PV8 photo sous community/<un autre pro>/ refusée',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_url('pv_cli2', 'community/' || pg_temp.get('pv_pro2') || '/p6.jpg')), 'Operation not permitted');
PERFORM pg_temp.as_('pv_cli6');
PERFORM pg_temp.denied('PV8 photo rattachée à l''avis d''un autre refusée',
  format($$SELECT public.add_pro_community_photo(%L, %L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli6', 'p.jpg'), pg_temp.id('pv_rv2')), 'Operation not permitted');
PERFORM pg_temp.denied('PV8 un tiers ne retire pas la photo d''un autre', format($$SELECT public.remove_pro_community_photo(%L)::text$$, pg_temp.id('pv_cp1')), 'Operation not permitted');
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.denied('PV8 VITRINE-1 le pro ne poste pas de photo communautaire sur sa propre vitrine',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_pro', 'self.jpg')), '^Operation not permitted$');

-- VITRINE-1 (corrigé 00578) : il faut une sortie FAITE avec ce pro (et avec cette offre si elle est précisée).
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.denied('PV8 VITRINE-1 sans réservation : pas de photo communautaire',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli', 'p.jpg')), 'junto\.review_requires_booking');
PERFORM pg_temp.as_('pv_cli3');
PERFORM pg_temp.denied('PV8 VITRINE-1 réservation acceptée à venir : pas de photo',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli3', 'p.jpg')), 'junto\.review_requires_booking');
PERFORM pg_temp.as_('pv_cli4');
PERFORM pg_temp.denied('PV8 VITRINE-1 demande sur plusieurs jours en cours : pas de photo',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli4', 'p.jpg')), 'junto\.review_requires_booking');
PERFORM pg_temp.as_('pv_cli5');
PERFORM pg_temp.denied('PV8 VITRINE-1 date fixe en cours : pas de photo',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli5', 'p.jpg')), 'junto\.review_requires_booking');
PERFORM pg_temp.as_('pv_cli2');
PERFORM pg_temp.denied('PV8 VITRINE-1 photo rattachée à une offre jamais réservée refusée',
  format($$SELECT public.add_pro_community_photo(%L, %L, NULL, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli2', 'p4.jpg'), pg_temp.id('pv_offb')), 'junto\.review_requires_booking');
PERFORM pg_temp.as_('pv_cli7');
PERFORM pg_temp.ok('PV8 date fixe finie : photo acceptée',
  format($$SELECT public.add_pro_community_photo(%L, %L, NULL, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli7', 'p.jpg'), pg_temp.id('pv_off')));
PERFORM pg_temp.as_('pv_cli6');
PERFORM pg_temp.ok('PV8 plusieurs jours finis hier : photo acceptée',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pv_pro'), pg_temp.pv_cm('pv_cli6', 'p.jpg')));
-- Signalement et retrait par un admin.
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.ok('PV8 VITRINE-1 une photo communautaire se signale',
  format($$SELECT public.create_report('pro_community_photo', %L, 'Photo sans rapport avec la sortie')::text$$, pg_temp.id('pv_cp1')));
PERFORM pg_temp.as_('pv_adm');
PERFORM pg_temp.ok('PV8 VITRINE-1 l''admin retire une photo communautaire',
  format($$SELECT public.admin_remove_content('pro_community_photo', %L, 'Contenu inapproprié')::text$$, pg_temp.id('pv_cp1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV8 VITRINE-1 la photo retirée par l''admin a disparu',
  format($$SELECT count(*)::text FROM public.pro_community_photos WHERE id = %L$$, pg_temp.id('pv_cp1')), '0');
PERFORM pg_temp.as_('pv_cli2');
PERFORM pg_temp.ok('PV8 le contributeur retire sa propre photo', format($$SELECT public.remove_pro_community_photo(%L)::text$$, pg_temp.id('pv_cp2')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV8 photo retirée', format($$SELECT count(*)::text FROM public.pro_community_photos WHERE id = %L$$, pg_temp.id('pv_cp2')), '0');
PERFORM pg_temp.as_('pv_cli');
PERFORM pg_temp.denied('PV8 signaler une photo communautaire inexistante : refusé',
  format($$SELECT public.create_report('pro_community_photo', %L, 'Photo sans rapport avec la sortie')::text$$, gen_random_uuid()), '^Operation not permitted$');
-- 00578 (VITRINE-1) : stockage — un contributeur ne réécrit ni ne supprime-et-remplace un fichier de
-- son sous-dossier community/ (les politiques UPDATE / DELETE du bucket l'excluent).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV8 stockage : pro_photos_update_own exclut le sous-dossier community/',
  $$SELECT (qual ~ 'foldername\(name\)\)\[2\] IS DISTINCT FROM ''community''')::text FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'pro_photos_update_own' AND cmd = 'UPDATE'$$, 'true');
PERFORM pg_temp.eq('PV8 stockage : pro_photos_delete_own exclut le sous-dossier community/',
  $$SELECT (qual ~ 'foldername\(name\)\)\[2\] IS DISTINCT FROM ''community''')::text FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'pro_photos_delete_own' AND cmd = 'DELETE'$$, 'true');
PERFORM pg_temp.eq('PV8 stockage : aucune autre politique UPDATE / DELETE sur pro-photos',
  $$SELECT string_agg(policyname, ',' ORDER BY policyname) FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND cmd IN ('UPDATE', 'DELETE', 'ALL')
      AND (qual ~ 'pro-photos' OR with_check ~ 'pro-photos')$$, 'pro_photos_delete_own,pro_photos_update_own');

-- ═════ PV9 — Avis : la sortie doit être FINIE (VITRINE-3) ═════
PERFORM pg_temp.as_('pv_cli4');
PERFORM pg_temp.denied('PV9 VITRINE-3 plusieurs jours en cours : pas d''avis sur le pro',
  format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pv_pro')), 'junto.review_requires_booking');
PERFORM pg_temp.denied('PV9 VITRINE-3 plusieurs jours en cours : pas d''avis sur l''offre',
  format($$SELECT public.create_offering_review(%L, 5::smallint)::text$$, pg_temp.id('pv_off')), 'junto.review_requires_booking');
PERFORM pg_temp.as_('pv_cli5');
PERFORM pg_temp.denied('PV9 VITRINE-3 date fixe en cours : pas d''avis sur le pro',
  format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pv_pro')), 'junto.review_requires_booking');
PERFORM pg_temp.denied('PV9 VITRINE-3 date fixe en cours : pas d''avis sur l''offre',
  format($$SELECT public.create_offering_review(%L, 5::smallint)::text$$, pg_temp.id('pv_off')), 'junto.review_requires_booking');
PERFORM pg_temp.as_('pv_cli3');
PERFORM pg_temp.denied('PV9 réservation à venir : pas d''avis', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pv_pro')), 'junto.review_requires_booking');
PERFORM pg_temp.as_('pv_cli6');
PERFORM pg_temp.ok('PV9 plusieurs jours finis hier : avis sur le pro', format($$SELECT public.create_pro_review(%L, 4::smallint)::text$$, pg_temp.id('pv_pro')));
PERFORM pg_temp.ok('PV9 plusieurs jours finis hier : avis sur l''offre', format($$SELECT public.create_offering_review(%L, 4::smallint)::text$$, pg_temp.id('pv_off')));
PERFORM pg_temp.as_('pv_cli7');
PERFORM pg_temp.ok('PV9 date fixe finie : avis sur le pro', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pv_pro')));
PERFORM pg_temp.put('pv_orv7', pg_temp.ok('PV9 date fixe finie : avis sur l''offre', format($$SELECT public.create_offering_review(%L, 5::smallint, '<b>Top</b>')::text$$, pg_temp.id('pv_off'))));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('PV9 corps de l''avis nettoyé du HTML', format($$SELECT body FROM public.offering_reviews WHERE id = %L$$, pg_temp.id('pv_orv7')), 'Top');
PERFORM pg_temp.as_('pv_cli7');
PERFORM pg_temp.denied('PV9 un second avis sur la même offre refusé', format($$SELECT public.create_offering_review(%L, 3::smallint)::text$$, pg_temp.id('pv_off')), 'junto.review_duplicate');
PERFORM pg_temp.ok('PV9 l''auteur modifie son avis d''offre', format($$SELECT public.update_offering_review(%L, 4::smallint, 'Très bien')::text$$, pg_temp.id('pv_orv7')));
PERFORM pg_temp.as_('pv_pro');
PERFORM pg_temp.ok('PV9 le pro répond à l''avis d''offre', format($$SELECT public.reply_to_offering_review(%L, 'Merci !')::text$$, pg_temp.id('pv_orv7')));
PERFORM pg_temp.denied('PV9 le pro ne modifie pas l''avis reçu', format($$SELECT public.update_offering_review(%L, 1::smallint)::text$$, pg_temp.id('pv_orv7')));
PERFORM pg_temp.denied('PV9 le pro ne supprime pas l''avis reçu', format($$SELECT public.delete_offering_review(%L)::text$$, pg_temp.id('pv_orv7')));
PERFORM pg_temp.as_('pv_pro2');
PERFORM pg_temp.denied('PV9 un autre pro ne répond pas à l''avis', format($$SELECT public.reply_to_offering_review(%L, 'x')::text$$, pg_temp.id('pv_orv7')));
PERFORM pg_temp.as_('pv_sam');
PERFORM pg_temp.denied('PV9 un suspendu ne laisse pas d''avis', format($$SELECT public.create_offering_review(%L, 5::smallint)::text$$, pg_temp.id('pv_off')));
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('PV9 anon ne laisse pas d''avis', format($$SELECT public.create_offering_review(%L, 5::smallint)::text$$, pg_temp.id('pv_off')));
PERFORM pg_temp.as_('pv_cli7');
PERFORM pg_temp.ok('PV9 l''auteur supprime son avis d''offre', format($$SELECT public.delete_offering_review(%L)::text$$, pg_temp.id('pv_orv7')));
