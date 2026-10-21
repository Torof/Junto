-- Domaine 6 — Pro : vitrine, offres, photos, disponibilités, réservations, avis.
--
-- NB : plusieurs fonctions (approve_pro, reject_pro, resubmit, update_pro_profile,
-- unregister_as_pro, reply_to_*) posent junto.bypass_lock = true pour la fin de
-- la transaction (inoffensif via PostgREST : une requête = une transaction).
-- Ici tout tourne dans UNE transaction : on remet le drapeau à false après coup.

-- ───── Helpers locaux ─────
EXECUTE $p$CREATE FUNCTION pg_temp.po_url(p_label text, p_file text) RETURNS text
  LANGUAGE sql AS $b$ SELECT 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/' || pg_temp.id(p_label)::text || '/' || p_file $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.po_unlock() RETURNS void
  LANGUAGE sql AS $b$ SELECT set_config('junto.bypass_lock', 'false', true) $b$$p$;
-- Inscription standard (nom, raison sociale, identité, coordonnées).
EXECUTE $p$CREATE FUNCTION pg_temp.po_register_sql(p_name text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.register_as_pro(p_display_name := %L, p_company_name := 'SARL Test', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$s$, p_name) $b$$p$;
-- Création d'offre standard (max 8 participants, 50 €/personne).
EXECUTE $p$CREATE FUNCTION pg_temp.po_offering_sql(p_title text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_pro_offering(p_sport_id := %L, p_title := %L, p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon',
      p_max_participants := 8, p_price_eur := 50, p_price_unit := 'person')::text$s$, pg_temp.id('sport'), p_title) $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.user('pro', 'tos');      -- pro approuvé principal
PERFORM pg_temp.user('pro2', 'tos');     -- second pro approuvé (propriété croisée, suspendu en fin de fichier)
PERFORM pg_temp.user('cand', 'tos');     -- candidature en attente
PERFORM pg_temp.user('rej', 'tos');      -- candidature refusée puis renvoyée
PERFORM pg_temp.user('cli', 'tos');
PERFORM pg_temp.user('cli2', 'tos');
PERFORM pg_temp.user('cli3', 'tos');
PERFORM pg_temp.user('har', 'tos');      -- harceleur bloqué par le pro
PERFORM pg_temp.user('sam', 'tos,suspended');
PERFORM pg_temp.user('adm', 'tos,admin');
PERFORM pg_temp.put('sport', (SELECT id::text FROM public.sports WHERE key = 'hiking'));
PERFORM pg_temp.put('d1', (current_date + 7)::text);
PERFORM pg_temp.put('d2', (current_date + 8)::text);
PERFORM pg_temp.put('d3', (current_date + 9)::text);

-- ═════ Inscription / candidature ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne peut pas s''inscrire comme pro', pg_temp.po_register_sql('Anon Pro'));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un suspendu ne peut pas s''inscrire comme pro', pg_temp.po_register_sql('Sam Pro'));

PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('pro s''inscrit', pg_temp.po_register_sql('<b>Guide</b> Pro'));
PERFORM pg_temp.denied('double inscription refusée', pg_temp.po_register_sql('Guide Pro bis'));
PERFORM pg_temp.eq('le nom affiché est nettoyé du HTML', $$SELECT display_name FROM public.get_my_pro_application()$$, 'Guide Pro');
PERFORM pg_temp.eq('la candidature démarre en attente', $$SELECT status FROM public.get_my_pro_application()$$, 'pending');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('l''inscription ne donne pas le tier pro', format($$SELECT (tier = 'pro')::text FROM public.users WHERE id = %L$$, pg_temp.id('pro')), 'false');

PERFORM pg_temp.as_('pro2');
PERFORM pg_temp.ok('pro2 s''inscrit', pg_temp.po_register_sql('Pro Deux'));
PERFORM pg_temp.as_('cand');
PERFORM pg_temp.denied('raison sociale trop courte refusée',
  $$SELECT public.register_as_pro(p_display_name := 'X', p_company_name := 'A', p_real_name := 'Jean Test', p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'B')::text$$);
PERFORM pg_temp.denied('inscription sans coordonnées refusée',
  $$SELECT public.register_as_pro(p_display_name := 'X', p_company_name := 'SARL X', p_real_name := 'Jean Test', p_primary_location_name := 'B')::text$$);
PERFORM pg_temp.ok('cand s''inscrit', pg_temp.po_register_sql('Candidat'));
PERFORM pg_temp.as_('rej');
PERFORM pg_temp.ok('rej s''inscrit', pg_temp.po_register_sql('Rejeté'));

PERFORM pg_temp.as_('cli');
PERFORM pg_temp.eq('un non-pro n''a pas de candidature', $$SELECT count(*)::text FROM public.get_my_pro_application()$$, '0');

-- ═════ Validation admin ═════
PERFORM pg_temp.denied('un non-admin ne peut pas approuver', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pro')));
PERFORM pg_temp.denied('un non-admin ne peut pas refuser', format($$SELECT public.reject_pro(%L, 'non')::text$$, pg_temp.id('pro')));
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.denied('un candidat ne peut pas s''approuver lui-même', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pro')));

PERFORM pg_temp.as_('adm');
PERFORM pg_temp.ok('l''admin approuve pro', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pro')));
PERFORM pg_temp.ok('l''admin approuve pro2', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pro2')));
PERFORM pg_temp.denied('approuver deux fois est refusé', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pro')));
PERFORM pg_temp.denied('approuver un compte sans candidature est refusé', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('cli')));
PERFORM pg_temp.ok('l''admin refuse rej avec un motif', format($$SELECT public.reject_pro(%L, 'Pièce manquante')::text$$, pg_temp.id('rej')));
PERFORM pg_temp.denied('refuser une candidature déjà refusée est refusé', format($$SELECT public.reject_pro(%L, 'x')::text$$, pg_temp.id('rej')));
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('l''approbation donne le tier pro', format($$SELECT tier::text FROM public.users WHERE id = %L$$, pg_temp.id('pro')), 'pro');
PERFORM pg_temp.eq('le pro est notifié de l''approbation', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'pro_approved'$$, pg_temp.id('pro')), '1');

PERFORM pg_temp.as_('rej');
PERFORM pg_temp.eq('le candidat refusé lit son motif', $$SELECT rejection_reason FROM public.get_my_pro_application()$$, 'Pièce manquante');
PERFORM pg_temp.ok('le candidat refusé renvoie sa demande', $$SELECT public.resubmit_pro_application()::text$$);
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.eq('la demande renvoyée repasse en attente', $$SELECT status FROM public.get_my_pro_application()$$, 'pending');
PERFORM pg_temp.denied('renvoyer une demande en attente est refusé', $$SELECT public.resubmit_pro_application()::text$$);
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('renvoyer sans candidature est refusé', $$SELECT public.resubmit_pro_application()::text$$);

-- ═════ Vitrine : lecture de pro_profiles ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne lit pas pro_profiles', $$SELECT count(*)::text FROM public.pro_profiles$$);
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.eq('un membre voit un pro approuvé', format($$SELECT count(*)::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pro')), '1');
PERFORM pg_temp.eq('un membre ne voit pas une candidature en attente', format($$SELECT count(*)::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('cand')), '0');
PERFORM pg_temp.as_('cand');
PERFORM pg_temp.eq('le candidat voit sa propre ligne', format($$SELECT count(*)::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('cand')), '1');
PERFORM pg_temp.as_('adm');
PERFORM pg_temp.eq('l''admin voit une candidature en attente', format($$SELECT count(*)::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('cand')), '1');
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('un membre ne peut pas modifier la vitrine d''un pro', format($$WITH u AS (UPDATE public.pro_profiles SET display_name = 'pwned' WHERE user_id = %L RETURNING 1) SELECT count(*)::text FROM u$$, pg_temp.id('pro')), 'permission denied');
PERFORM pg_temp.denied('un membre ne peut pas créer de vitrine directement', format($$INSERT INTO public.pro_profiles (user_id, display_name, company_name, real_name, status) VALUES (%L, 'x', 'SARL x', 'x x', 'approved')$$, pg_temp.id('cli')));

-- ═════ update_pro_profile ═════
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.denied('approuvé : changer la raison sociale est gelé', $$SELECT public.update_pro_profile(p_company_name := 'Autre SARL')::text$$, 'junto.pro_identity_locked');
PERFORM pg_temp.denied('approuvé : changer l''identité est gelé', $$SELECT public.update_pro_profile(p_real_name := 'Autre Nom')::text$$, 'junto.pro_identity_locked');
PERFORM pg_temp.ok('approuvé : renvoyer la même raison sociale est permis', $$SELECT public.update_pro_profile(p_company_name := 'SARL Test', p_tagline := '<i>Le</i> meilleur')::text$$);
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.eq('la tagline est nettoyée du HTML', $$SELECT tagline FROM public.get_my_pro_application()$$, 'Le meilleur');
PERFORM pg_temp.ok('vider la tagline via p_clear', $$SELECT public.update_pro_profile(p_clear := ARRAY['tagline'])::text$$);
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.eq('la tagline est vidée', $$SELECT coalesce(tagline, 'null') FROM public.get_my_pro_application()$$, 'null');
PERFORM pg_temp.denied('p_clear refuse une colonne hors liste blanche', $$SELECT public.update_pro_profile(p_clear := ARRAY['display_name'])::text$$);
PERFORM pg_temp.denied('p_clear refuse plus de 7 entrées', $$SELECT public.update_pro_profile(p_clear := ARRAY['tagline','tagline','tagline','tagline','tagline','tagline','tagline','tagline'])::text$$);
PERFORM pg_temp.denied('approuvé : déplacement de l''enseigne sous cooldown', $$SELECT public.update_pro_profile(p_primary_lng := 6.0, p_primary_lat := 45.0, p_primary_location_name := 'Ailleurs')::text$$, 'junto.pro_location_cooldown');
PERFORM pg_temp.denied('déplacement sans nom de lieu refusé', $$SELECT public.update_pro_profile(p_primary_lng := 6.0, p_primary_lat := 45.0)::text$$);
PERFORM pg_temp.denied('site web en javascript: refusé', $$SELECT public.update_pro_profile(p_website := 'javascript:alert(1)')::text$$, '.');
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.as_('cand');
PERFORM pg_temp.ok('en attente : la raison sociale reste modifiable', $$SELECT public.update_pro_profile(p_company_name := 'Nouvelle SARL')::text$$);
PERFORM pg_temp.ok('en attente : déplacer l''enseigne n''a pas de cooldown', $$SELECT public.update_pro_profile(p_primary_lng := 6.0, p_primary_lat := 45.0, p_primary_location_name := 'Gap')::text$$);
PERFORM pg_temp.ok('en attente : second déplacement permis', $$SELECT public.update_pro_profile(p_primary_lng := 6.1, p_primary_lat := 45.1, p_primary_location_name := 'Embrun')::text$$);
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('un non-pro ne peut pas modifier de vitrine', $$SELECT public.update_pro_profile(p_tagline := 'x')::text$$);
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un suspendu ne peut pas modifier de vitrine', $$SELECT public.update_pro_profile(p_tagline := 'x')::text$$);

-- ═════ Pin (icône, image) ═════
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('icône de pin valide', $$SELECT public.set_pro_pin_icon('mountain')::text$$);
PERFORM pg_temp.denied('icône de pin hors liste refusée', $$SELECT public.set_pro_pin_icon('skull')::text$$);
PERFORM pg_temp.ok('image de pin dans son dossier', format($$SELECT public.set_pro_pin_image(%L)::text$$, pg_temp.po_url('pro', 'pin.jpg')));
PERFORM pg_temp.denied('image de pin hors stockage refusée', $$SELECT public.set_pro_pin_image('https://evil.example/pin.jpg')::text$$);
PERFORM pg_temp.denied('image de pin dans le dossier d''un autre refusée', format($$SELECT public.set_pro_pin_image(%L)::text$$, pg_temp.po_url('pro2', 'pin.jpg')));
PERFORM pg_temp.denied('image de pin : remontée « .. » vers le dossier d''un autre refusée',
  format($$SELECT public.set_pro_pin_image(%L)::text$$, pg_temp.po_url('pro', '../' || pg_temp.id('pro2')::text || '/pin.jpg')), 'Operation not permitted');
PERFORM pg_temp.as_('cand');
PERFORM pg_temp.denied('en attente : pas d''icône de pin', $$SELECT public.set_pro_pin_icon('water')::text$$);
PERFORM pg_temp.denied('en attente : pas d''image de pin', format($$SELECT public.set_pro_pin_image(%L)::text$$, pg_temp.po_url('cand', 'pin.jpg')));

-- ═════ Offres ═════
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.put('off', pg_temp.ok('le pro approuvé crée une offre', pg_temp.po_offering_sql('Rando test')));
PERFORM pg_temp.put('off_del', pg_temp.ok('le pro crée une seconde offre', pg_temp.po_offering_sql('Offre à supprimer')));
PERFORM pg_temp.denied('titre trop court refusé', pg_temp.po_offering_sql('ab'));
PERFORM pg_temp.denied('prix sans unité refusé', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := 'Prix', p_description := 'd', p_level := 'x',
  p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'B', p_price_eur := 10)::text$$, pg_temp.id('sport')));
PERFORM pg_temp.denied('min > max refusé', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := 'MinMax', p_description := 'd', p_level := 'x',
  p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'B', p_max_participants := 2, p_min_participants := 5)::text$$, pg_temp.id('sport')));
PERFORM pg_temp.denied('création d''offre directe dans la table refusée', format($$INSERT INTO public.pro_offerings (pro_id, sport_id, title, description, level, location_name) VALUES (%L, %L, 'x', 'x', 'x', 'x')$$, pg_temp.id('pro'), pg_temp.id('sport')));
PERFORM pg_temp.denied('modification directe d''une offre sans effet', format($$WITH u AS (UPDATE public.pro_offerings SET price_eur = 1 WHERE id = %L RETURNING 1) SELECT count(*)::text FROM u$$, pg_temp.id('off')), 'permission denied');
PERFORM pg_temp.denied('suppression directe d''une offre sans effet', format($$WITH u AS (DELETE FROM public.pro_offerings WHERE id = %L RETURNING 1) SELECT count(*)::text FROM u$$, pg_temp.id('off')), 'permission denied');
PERFORM pg_temp.ok('le pro règle matériel et fiche participant', format($$SELECT public.set_offering_details(%L, ARRAY['Baudrier'], ARRAY['<b>Chaussures</b>'], ARRAY['shoe_size'], ARRAY['Allergies ?'])::text$$, pg_temp.id('off')));
PERFORM pg_temp.eq('le matériel requis est nettoyé du HTML', format($$SELECT equipment_required->>0 FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('off')), 'Chaussures');
PERFORM pg_temp.denied('champ participant hors catalogue refusé', format($$SELECT public.set_offering_details(%L, NULL, NULL, ARRAY['iban'], NULL)::text$$, pg_temp.id('off')));
PERFORM pg_temp.denied('plus de 3 questions libres refusé', format($$SELECT public.set_offering_details(%L, NULL, NULL, NULL, ARRAY['a','b','c','d'])::text$$, pg_temp.id('off')));

PERFORM pg_temp.as_('pro2');
PERFORM pg_temp.put('off2', pg_temp.ok('pro2 crée une offre', pg_temp.po_offering_sql('Offre pro2')));
PERFORM pg_temp.denied('pro2 ne modifie pas l''offre de pro', format($$SELECT public.update_pro_offering(p_offering_id := %L, p_sport_id := %L, p_title := 'Volée', p_description := 'd', p_level := 'x',
  p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'B')::text$$, pg_temp.id('off'), pg_temp.id('sport')));
PERFORM pg_temp.denied('pro2 ne supprime pas l''offre de pro', format($$SELECT public.delete_pro_offering(%L)::text$$, pg_temp.id('off')));
PERFORM pg_temp.denied('pro2 ne règle pas les détails de l''offre de pro', format($$SELECT public.set_offering_details(%L, NULL, NULL, NULL, NULL)::text$$, pg_temp.id('off')));
-- Plafond de 12 offres par pro.
FOR i IN 2..12 LOOP
  PERFORM public.create_pro_offering(p_sport_id := pg_temp.id('sport'), p_title := 'Offre cap ' || i, p_description := 'd',
    p_level := 'x', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'B');
END LOOP;
PERFORM pg_temp.denied('13e offre refusée (plafond 12)', pg_temp.po_offering_sql('Offre de trop'), 'junto.offering_cap');

PERFORM pg_temp.as_('cand');
PERFORM pg_temp.denied('un candidat en attente ne crée pas d''offre', pg_temp.po_offering_sql('Offre candidat'));
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('un membre ne crée pas d''offre', pg_temp.po_offering_sql('Offre membre'));
PERFORM pg_temp.eq('un membre voit l''offre d''un pro approuvé', format($$SELECT count(*)::text FROM public.pro_offerings WHERE id = %L$$, pg_temp.id('off')), '1');

PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('le pro supprime une offre sans réservation', format($$SELECT public.delete_pro_offering(%L)::text$$, pg_temp.id('off_del')));

-- ═════ Photos de vitrine et d'offre ═════
PERFORM pg_temp.put('ph1', pg_temp.ok('le pro ajoute une photo de vitrine', format($$SELECT public.add_pro_photo(%L)::text$$, pg_temp.po_url('pro', 'a.jpg'))));
PERFORM pg_temp.put('ph2', pg_temp.ok('le pro ajoute une seconde photo', format($$SELECT public.add_pro_photo(%L)::text$$, pg_temp.po_url('pro', 'b.jpg'))));
PERFORM pg_temp.denied('photo hors stockage refusée', $$SELECT public.add_pro_photo('https://evil.example/a.jpg')::text$$);
PERFORM pg_temp.denied('photo dans le dossier d''un autre refusée', format($$SELECT public.add_pro_photo(%L)::text$$, pg_temp.po_url('pro2', 'a.jpg')));
PERFORM pg_temp.ok('le pro réordonne ses photos', format($$SELECT public.reorder_pro_photos(ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('ph2'), pg_temp.id('ph1')));
PERFORM pg_temp.eq('le nouvel ordre est appliqué', format($$SELECT order_index::text FROM public.pro_profile_photos WHERE id = %L$$, pg_temp.id('ph2')), '0');
PERFORM pg_temp.denied('réordonner une liste incomplète refusé', format($$SELECT public.reorder_pro_photos(ARRAY[%L]::uuid[])::text$$, pg_temp.id('ph1')));
PERFORM pg_temp.denied('photo de vitrine insérée directement refusée', format($$INSERT INTO public.pro_profile_photos (pro_id, photo_url, order_index) VALUES (%L, 'https://evil.example/x.jpg', 9)$$, pg_temp.id('pro')));
PERFORM pg_temp.put('oph1', pg_temp.ok('le pro ajoute une photo d''offre', format($$SELECT public.add_pro_offering_photo(%L, %L)::text$$, pg_temp.id('off'), pg_temp.po_url('pro', 'o1.jpg'))));
PERFORM pg_temp.ok('le pro réordonne les photos d''offre', format($$SELECT public.reorder_pro_offering_photos(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('off'), pg_temp.id('oph1')));

PERFORM pg_temp.as_('pro2');
PERFORM pg_temp.denied('pro2 ne réordonne pas avec la photo de pro', format($$SELECT public.reorder_pro_photos(ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('ph1'), pg_temp.id('ph2')));
PERFORM pg_temp.denied('pro2 ne retire pas la photo de pro', format($$SELECT public.remove_pro_photo(%L)::text$$, pg_temp.id('ph1')));
PERFORM pg_temp.denied('pro2 n''ajoute pas de photo à l''offre de pro', format($$SELECT public.add_pro_offering_photo(%L, %L)::text$$, pg_temp.id('off'), pg_temp.po_url('pro2', 'x.jpg')));
PERFORM pg_temp.denied('pro2 ne retire pas la photo d''offre de pro', format($$SELECT public.remove_pro_offering_photo(%L)::text$$, pg_temp.id('oph1')));
PERFORM pg_temp.as_('cand');
PERFORM pg_temp.denied('un candidat en attente n''ajoute pas de photo de vitrine', format($$SELECT public.add_pro_photo(%L)::text$$, pg_temp.po_url('cand', 'a.jpg')));
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('le pro retire sa photo', format($$SELECT public.remove_pro_photo(%L)::text$$, pg_temp.id('ph2')));
PERFORM pg_temp.denied('photo : remontée « .. » vers le dossier d''un autre refusée',
  format($$SELECT public.add_pro_photo(%L)::text$$, pg_temp.po_url('pro', '../' || pg_temp.id('pro2')::text || '/a.jpg')), 'Operation not permitted');
PERFORM pg_temp.ok('le pro retire sa photo d''offre', format($$SELECT public.remove_pro_offering_photo(%L)::text$$, pg_temp.id('oph1')));

-- ═════ Blocage : le pro bloque le harceleur ═════
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('pro'), pg_temp.id('har'));

-- ═════ Photos communautaires ═════
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.put('cph', pg_temp.ok('un membre ajoute une photo communautaire', format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pro'), pg_temp.po_url('cli', 'c1.jpg'))));
PERFORM pg_temp.denied('photo communautaire hors de son propre dossier refusée', format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pro'), pg_temp.po_url('pro', 'a.jpg')));
PERFORM pg_temp.denied('photo communautaire sur une candidature en attente refusée', format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('cand'), pg_temp.po_url('cli', 'c2.jpg')));
PERFORM pg_temp.denied('photo communautaire liée à l''offre d''un autre pro refusée', format($$SELECT public.add_pro_community_photo(%L, %L, NULL, %L)::text$$, pg_temp.id('pro'), pg_temp.po_url('cli', 'c3.jpg'), pg_temp.id('off2')));
FOR i IN 2..5 LOOP
  PERFORM public.add_pro_community_photo(pg_temp.id('pro'), pg_temp.po_url('cli', 'cc' || i || '.jpg'));
END LOOP;
PERFORM pg_temp.denied('6e photo communautaire refusée (plafond 5)', format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pro'), pg_temp.po_url('cli', 'c6.jpg')), 'junto.photo_limit');
PERFORM pg_temp.denied('insertion directe de photo communautaire refusée', format($$INSERT INTO public.pro_community_photos (pro_id, contributor_id, photo_url) VALUES (%L, %L, 'https://evil.example/x.jpg')$$, pg_temp.id('pro'), pg_temp.id('cli')));
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.eq('un autre membre voit la photo communautaire', format($$SELECT count(*)::text FROM public.pro_community_photos WHERE id = %L$$, pg_temp.id('cph')), '1');
PERFORM pg_temp.denied('un tiers ne retire pas la photo communautaire', format($$SELECT public.remove_pro_community_photo(%L)::text$$, pg_temp.id('cph')));
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('le pro retire une photo communautaire de sa page', format($$SELECT public.remove_pro_community_photo(%L)::text$$, pg_temp.id('cph')));
PERFORM pg_temp.as_('har');
PERFORM pg_temp.denied('un membre bloqué par le pro ne poste pas de photo sur sa page',
  format($$SELECT public.add_pro_community_photo(%L, %L)::text$$, pg_temp.id('pro'), pg_temp.po_url('har', 'h.jpg')), 'Operation not permitted');

-- ═════ Disponibilités ═════
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('le pro ouvre un créneau', format($$SELECT public.set_pro_availability(%L, 'am', true)::text$$, pg_temp.get('d1')));
PERFORM pg_temp.ok('le pro ouvre des créneaux en masse', format($$SELECT public.set_pro_availability_bulk(ARRAY[%L, %L, %L]::date[], ARRAY['am','pm','am'], true)::text$$, pg_temp.get('d2'), pg_temp.get('d2'), pg_temp.get('d3')));
PERFORM pg_temp.denied('créneau passé refusé', format($$SELECT public.set_pro_availability(%L, 'am', true)::text$$, (current_date - 1)::text), 'junto.booking_date');
PERFORM pg_temp.denied('créneau à plus de 6 mois refusé', format($$SELECT public.set_pro_availability(%L, 'am', true)::text$$, (current_date + 200)::text), 'junto.booking_date');
PERFORM pg_temp.denied('période inconnue refusée', format($$SELECT public.set_pro_availability(%L, 'night', true)::text$$, pg_temp.get('d1')));
PERFORM pg_temp.denied('masse : longueurs différentes refusées', format($$SELECT public.set_pro_availability_bulk(ARRAY[%L]::date[], ARRAY['am','pm'], true)::text$$, pg_temp.get('d1')));
PERFORM pg_temp.denied('masse : plus de 200 créneaux refusés',
  $$SELECT public.set_pro_availability_bulk((SELECT array_agg(current_date + 1) FROM generate_series(1, 201)), (SELECT array_agg('am'::text) FROM generate_series(1, 201)), true)::text$$);
PERFORM pg_temp.eq('le pro voit ses créneaux', $$SELECT count(*)::text FROM public.pro_availabilities$$, '4');
PERFORM pg_temp.as_('cand');
PERFORM pg_temp.denied('un candidat en attente n''ouvre pas de créneau', format($$SELECT public.set_pro_availability(%L, 'am', true)::text$$, pg_temp.get('d1')));
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('un membre n''ouvre pas de créneau', format($$SELECT public.set_pro_availability(%L, 'am', true)::text$$, pg_temp.get('d1')));
PERFORM pg_temp.denied('créneau inséré directement refusé', format($$INSERT INTO public.pro_availabilities (pro_id, day, period) VALUES (%L, %L, 'pm')$$, pg_temp.id('pro'), pg_temp.get('d1')));
PERFORM pg_temp.eq('un membre ne lit pas les créneaux bruts du pro', format($$SELECT count(*)::text FROM public.pro_availabilities WHERE pro_id = %L$$, pg_temp.id('pro')), '0');
PERFORM pg_temp.eq('un membre lit les créneaux publics du pro', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('pro')), '4');
PERFORM pg_temp.eq('pas de créneaux publics pour une candidature en attente', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('cand')), '0');
PERFORM pg_temp.as_('har');
PERFORM pg_temp.eq('un membre bloqué ne voit pas les créneaux', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('pro')), '0');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.eq('un suspendu ne voit pas les créneaux', format($$SELECT count(*)::text FROM public.get_pro_availability(%L)$$, pg_temp.id('pro')), '0');

-- ═════ Réservations ═════
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.put('bk1', pg_temp.ok('un membre réserve un créneau ouvert', format($$SELECT public.create_booking(%L, %L, 'am', 2, '<b>Bonjour</b>')::text$$, pg_temp.id('off'), pg_temp.get('d1'))));
PERFORM pg_temp.denied('double demande sur le même créneau refusée', format($$SELECT public.create_booking(%L, %L, 'am', 2)::text$$, pg_temp.id('off'), pg_temp.get('d1')), 'junto.booking_already');
PERFORM pg_temp.denied('créneau non ouvert refusé', format($$SELECT public.create_booking(%L, %L, 'pm', 2)::text$$, pg_temp.id('off'), pg_temp.get('d1')), 'junto.booking_slot_unavailable');
PERFORM pg_temp.denied('groupe de 0 refusé', format($$SELECT public.create_booking(%L, %L, 'pm', 0)::text$$, pg_temp.id('off'), pg_temp.get('d2')), 'junto.booking_party_size');
PERFORM pg_temp.denied('groupe au-delà du maximum de l''offre refusé', format($$SELECT public.create_booking(%L, %L, 'pm', 9)::text$$, pg_temp.id('off'), pg_temp.get('d2')), 'junto.booking_party_size');
PERFORM pg_temp.denied('jour passé refusé', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, pg_temp.id('off'), (current_date - 1)::text), 'junto.booking_date');
PERFORM pg_temp.denied('réserver l''offre d''un candidat non approuvé refusé (offre inexistante)', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, gen_random_uuid(), pg_temp.get('d1')));
PERFORM pg_temp.denied('réservation insérée directement refusée', format($$INSERT INTO public.bookings (offering_id, pro_id, client_id, day, period, party_size, status) VALUES (%L, %L, %L, %L, 'pm', 1, 'accepted')$$, pg_temp.id('off'), pg_temp.id('pro'), pg_temp.id('cli'), pg_temp.get('d2')));
PERFORM pg_temp.denied('participant_info illisible directement dans la table', format($$SELECT participant_info::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk1')), 'permission denied');
PERFORM pg_temp.eq('le client voit sa demande', format($$SELECT count(*)::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk1')), '1');
PERFORM pg_temp.eq('le message de demande est nettoyé du HTML', format($$SELECT message FROM public.bookings WHERE id = %L$$, pg_temp.id('bk1')), 'Bonjour');
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.denied('le pro ne réserve pas sa propre offre', format($$SELECT public.create_booking(%L, %L, 'pm', 1)::text$$, pg_temp.id('off'), pg_temp.get('d2')));
PERFORM pg_temp.eq('le pro voit la demande', format($$SELECT count(*)::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk1')), '1');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un suspendu ne réserve pas', format($$SELECT public.create_booking(%L, %L, 'pm', 1)::text$$, pg_temp.id('off'), pg_temp.get('d2')));
PERFORM pg_temp.as_('har');
PERFORM pg_temp.denied('un membre bloqué ne réserve pas', format($$SELECT public.create_booking(%L, %L, 'pm', 1)::text$$, pg_temp.id('off'), pg_temp.get('d2')));
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.eq('un tiers ne voit pas la demande', format($$SELECT count(*)::text FROM public.bookings WHERE id = %L$$, pg_temp.id('bk1')), '0');
PERFORM pg_temp.denied('un tiers n''accepte pas la demande', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.denied('un tiers n''annule pas la demande', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('le client n''accepte pas sa propre demande', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.denied('fiche participant avant acceptation refusée', format($$SELECT public.set_booking_participant_info(%L, '[{"shoe_size":"42"}]'::jsonb)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.as_('pro2');
PERFORM pg_temp.denied('un autre pro n''accepte pas la demande', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.denied('un autre pro ne refuse pas la demande', format($$SELECT public.decline_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le pro est notifié de la demande', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'booking_request'$$, pg_temp.id('pro')), '1');

PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('le pro accepte la demande', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.denied('accepter deux fois refusé', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.denied('refuser une réservation acceptée refusé', format($$SELECT public.decline_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le client est notifié de l''acceptation', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'booking_accepted'$$, pg_temp.id('cli')), '1');

PERFORM pg_temp.as_('cli');
PERFORM pg_temp.ok('le client remplit la fiche participant', format($$SELECT public.set_booking_participant_info(%L, '[{"shoe_size":"<b>42</b>","custom":{"Allergies ?":"non"}}]'::jsonb)::text$$, pg_temp.id('bk1')));
-- DB-PO-1 : get_my_bookings plante à chaque appel (« column reference "status" is ambiguous » :
-- `status` non qualifié dans l'UPDATE d'expiration, en conflit avec la colonne de sortie `status`).
PERFORM pg_temp.eq('le client relit ses réservations via get_my_bookings', format($$SELECT count(*)::text FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk1')), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la fiche est stockée nettoyée', format($$SELECT participant_info->0->>'shoe_size' FROM public.bookings WHERE id = %L$$, pg_temp.id('bk1')), '42');
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('fiche : clé hors liste refusée', format($$SELECT public.set_booking_participant_info(%L, '[{"iban":"FR76"}]'::jsonb)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.denied('fiche : question libre inconnue refusée', format($$SELECT public.set_booking_participant_info(%L, '[{"custom":{"Code carte ?":"1234"}}]'::jsonb)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.denied('fiche : plus de participants que le groupe refusé', format($$SELECT public.set_booking_participant_info(%L, '[{},{},{}]'::jsonb)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.denied('un tiers ne remplit pas la fiche', format($$SELECT public.set_booking_participant_info(%L, '[{"shoe_size":"40"}]'::jsonb)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.denied('le pro ne remplit pas la fiche d''un client Junto', format($$SELECT public.set_booking_participant_info(%L, '[{"shoe_size":"40"}]'::jsonb)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.eq('le pro lit la fiche via son agenda', format($$SELECT participant_info->0->>'shoe_size' FROM public.get_pro_agenda(current_date, current_date + 30) WHERE id = %L$$, pg_temp.id('bk1')), '42');
PERFORM pg_temp.denied('agenda sur plus de 12 mois refusé', $$SELECT count(*)::text FROM public.get_pro_agenda(current_date, current_date + 400)$$);
PERFORM pg_temp.denied('suppression d''une offre avec réservation vivante refusée', format($$SELECT public.delete_pro_offering(%L)::text$$, pg_temp.id('off')), 'junto.offering_has_bookings');
PERFORM pg_temp.denied('désinscription avec réservation vivante refusée', $$SELECT public.unregister_as_pro()::text$$, 'junto.offering_has_bookings');
-- PO-5 : le pro change le prix après acceptation ; la réservation du client devrait garder le prix accepté.
PERFORM pg_temp.ok('le pro modifie son offre', format($$SELECT public.update_pro_offering(p_offering_id := %L, p_sport_id := %L, p_title := 'Rando test', p_description := 'Description test', p_level := 'Tous niveaux',
  p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon', p_max_participants := 8, p_price_eur := 500, p_price_unit := 'person')::text$$, pg_temp.id('off'), pg_temp.id('sport')));
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.eq('après acceptation, le client garde le prix accepté', format($$SELECT price_eur::int::text FROM public.get_my_bookings() WHERE id = %L$$, pg_temp.id('bk1')), '50');
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.denied('un membre n''ouvre pas d''agenda pro', $$SELECT count(*)::text FROM public.get_pro_agenda(current_date, current_date + 30)$$);
PERFORM pg_temp.eq('get_my_bookings ne montre pas les réservations des autres', $$SELECT count(*)::text FROM public.get_my_bookings()$$, '0');

-- Refus, annulation pro.
PERFORM pg_temp.put('bk2', pg_temp.ok('cli2 réserve un autre créneau', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, pg_temp.id('off'), pg_temp.get('d2'))));
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.put('bk3', pg_temp.ok('cli réserve un second créneau', format($$SELECT public.create_booking(%L, %L, 'pm', 1)::text$$, pg_temp.id('off'), pg_temp.get('d2'))));
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.ok('le pro refuse une demande', format($$SELECT public.decline_booking(%L)::text$$, pg_temp.id('bk2')));
PERFORM pg_temp.ok('le pro annule une demande', format($$SELECT public.cancel_booking_pro(%L)::text$$, pg_temp.id('bk3')));
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.denied('annuler une demande refusée est refusé', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk2')));
-- DB-PO-2 : redemander un créneau refusé doit passer par la branche de réactivation (délai anti-spam d'1 h),
-- pas buter sur un doublon et répondre « déjà réservé ».
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.denied('redemander aussitôt un créneau refusé applique le délai anti-spam', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, pg_temp.id('off'), pg_temp.get('d2')), 'junto.booking_cooldown');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('cli2 est notifié du refus', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'booking_declined'$$, pg_temp.id('cli2')), '1');

-- Annulation client d'une réservation acceptée : la fiche participant est effacée.
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.ok('le client annule sa réservation acceptée', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.denied('annuler deux fois refusé', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la fiche participant est effacée hors « accepted »', format($$SELECT coalesce(participant_info::text, 'null') FROM public.bookings WHERE id = %L$$, pg_temp.id('bk1')), 'null');
PERFORM pg_temp.eq('le pro est notifié de l''annulation', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'booking_cancelled'$$, pg_temp.id('pro')), '1');

-- Réservations manuelles.
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.put('mbk', pg_temp.ok('le pro saisit une réservation manuelle', format($$SELECT public.create_manual_booking(%L, %L, 'am', 3, 'Jean Dehors', '0601020304')::text$$, pg_temp.id('off'), pg_temp.get('d3'))));
PERFORM pg_temp.denied('réservation manuelle sans nom refusée', format($$SELECT public.create_manual_booking(%L, %L, 'am', 3, '  ')::text$$, pg_temp.id('off'), pg_temp.get('d3')), 'junto.booking_manual_name');
PERFORM pg_temp.denied('réservation manuelle sur l''offre d''un autre pro refusée', format($$SELECT public.create_manual_booking(%L, %L, 'am', 1, 'X')::text$$, pg_temp.id('off2'), pg_temp.get('d3')));
PERFORM pg_temp.ok('le pro remplit la fiche d''une réservation manuelle', format($$SELECT public.set_booking_participant_info(%L, '[{"shoe_size":"41"}]'::jsonb)::text$$, pg_temp.id('mbk')));
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('un membre ne saisit pas de réservation manuelle', format($$SELECT public.create_manual_booking(%L, %L, 'am', 1, 'X')::text$$, pg_temp.id('off'), pg_temp.get('d3')));
PERFORM pg_temp.denied('un membre n''annule pas une réservation manuelle (B2)', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('mbk')));
PERFORM pg_temp.eq('un membre ne voit pas le téléphone d''une réservation manuelle', format($$SELECT count(*)::text FROM public.bookings WHERE id = %L$$, pg_temp.id('mbk')), '0');

-- PO-6 : un client suspendu ne devrait plus rien lire via get_my_bookings.
PERFORM pg_temp.put('bk4', pg_temp.ok('cli réserve encore un créneau', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, pg_temp.id('off'), pg_temp.get('d3'))));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = now() WHERE id = pg_temp.id('cli3');
PERFORM pg_temp.po_unlock();
-- cli3 n'a pas de réservation : on suspend cli lui-même le temps de la vérification.
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = now() WHERE id = pg_temp.id('cli');
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.eq('un suspendu ne lit plus ses réservations par la table', $$SELECT count(*)::text FROM public.bookings$$, '0');
PERFORM pg_temp.eq('un suspendu ne lit plus ses réservations via get_my_bookings', $$SELECT count(*)::text FROM public.get_my_bookings()$$, '0');
PERFORM pg_temp.denied('un suspendu n''annule pas lui-même', format($$SELECT public.cancel_booking(%L)::text$$, pg_temp.id('bk4')));
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.denied('le pro n''accepte pas la demande d''un client suspendu', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk4')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = NULL WHERE id IN (pg_temp.id('cli'), pg_temp.id('cli3'));
PERFORM pg_temp.po_unlock();

-- ═════ Avis sur la vitrine ═════
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.put('rv1', pg_temp.ok('un membre laisse un avis sur le pro', format($$SELECT public.create_pro_review(%L, 4::smallint, '<b>Super</b> guide')::text$$, pg_temp.id('pro'))));
PERFORM pg_temp.eq('le corps de l''avis est nettoyé du HTML', format($$SELECT body FROM public.pro_reviews WHERE id = %L$$, pg_temp.id('rv1')), 'Super guide');
PERFORM pg_temp.denied('un second avis sur le même pro refusé', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pro')), 'junto.review_duplicate');
PERFORM pg_temp.denied('note hors 1..5 refusée', format($$SELECT public.create_pro_review(%L, 6::smallint)::text$$, pg_temp.id('pro2')));
PERFORM pg_temp.denied('avis sur une candidature en attente refusé', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('cand')));
PERFORM pg_temp.denied('avis inséré directement refusé', format($$INSERT INTO public.pro_reviews (pro_id, reviewer_id, rating) VALUES (%L, %L, 5)$$, pg_temp.id('pro2'), pg_temp.id('cli')));
PERFORM pg_temp.denied('le relecteur ne s''écrit pas une réponse du pro', format($$WITH u AS (UPDATE public.pro_reviews SET pro_reply = 'faux' WHERE id = %L RETURNING 1) SELECT count(*)::text FROM u$$, pg_temp.id('rv1')), 'permission denied');
PERFORM pg_temp.ok('l''auteur modifie son avis', format($$SELECT public.update_pro_review(%L, 3::smallint, 'Bien')::text$$, pg_temp.id('rv1')));
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.denied('pas d''auto-avis', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pro')));
PERFORM pg_temp.denied('le pro ne modifie pas l''avis reçu', format($$SELECT public.update_pro_review(%L, 5::smallint)::text$$, pg_temp.id('rv1')));
PERFORM pg_temp.denied('le pro ne supprime pas l''avis reçu', format($$SELECT public.delete_pro_review(%L)::text$$, pg_temp.id('rv1')));
PERFORM pg_temp.ok('le pro répond à l''avis', format($$SELECT public.reply_to_pro_review(%L, 'Merci !')::text$$, pg_temp.id('rv1')));
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un suspendu ne laisse pas d''avis', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pro2')));
PERFORM pg_temp.as_('pro2');
PERFORM pg_temp.denied('un autre pro ne répond pas à l''avis', format($$SELECT public.reply_to_pro_review(%L, 'x')::text$$, pg_temp.id('rv1')));
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.denied('un tiers ne modifie pas l''avis', format($$SELECT public.update_pro_review(%L, 1::smallint)::text$$, pg_temp.id('rv1')));
PERFORM pg_temp.denied('un tiers ne supprime pas l''avis', format($$SELECT public.delete_pro_review(%L)::text$$, pg_temp.id('rv1')));
PERFORM pg_temp.denied('un membre ne répond pas à la place du pro', format($$SELECT public.reply_to_pro_review(%L, 'x')::text$$, pg_temp.id('rv1')));
PERFORM pg_temp.eq('un autre membre lit l''avis', format($$SELECT count(*)::text FROM public.pro_reviews WHERE id = %L$$, pg_temp.id('rv1')), '1');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne lit pas les avis via la vue', $$SELECT count(*)::text FROM public.pro_reviews_with_profiles$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le pro est notifié du nouvel avis', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'review_received'$$, pg_temp.id('pro')), '1');
PERFORM pg_temp.eq('l''auteur est notifié de la réponse', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'review_reply'$$, pg_temp.id('cli')), '1');
-- PO-11 : l'auteur réécrit son avis après la réponse ; le pro devrait en être informé.
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.ok('l''auteur réécrit son avis après la réponse', format($$SELECT public.update_pro_review(%L, 1::smallint, 'Nul')::text$$, pg_temp.id('rv1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le pro est informé d''un avis réécrit après sa réponse',
  format($$SELECT (count(*) > 1)::text FROM public.notifications WHERE user_id = %L AND data->>'review_id' = %L$$, pg_temp.id('pro'), pg_temp.id('rv1')), 'true');
-- PO-2 : réponse / effacement / réponse → une seule notification à l'auteur.
PERFORM pg_temp.as_('pro');
PERFORM public.reply_to_pro_review(pg_temp.id('rv1'), NULL);
PERFORM public.reply_to_pro_review(pg_temp.id('rv1'), 'Merci encore');
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('effacer puis réécrire la réponse ne renotifie pas l''auteur',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'review_reply'$$, pg_temp.id('cli')), '1');
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.ok('l''auteur supprime son avis', format($$SELECT public.delete_pro_review(%L)::text$$, pg_temp.id('rv1')));

-- PO-1 : publier / supprimer en boucle → une seule notification au pro.
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.put('rv2', pg_temp.ok('cli2 laisse un avis sur pro2', format($$SELECT public.create_pro_review(%L, 1::smallint, 'Bof')::text$$, pg_temp.id('pro2'))));
PERFORM public.delete_pro_review(pg_temp.id('rv2'));
PERFORM public.create_pro_review(pg_temp.id('pro2'), 1::smallint, 'Bof encore');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('publier / supprimer en boucle ne renotifie pas le pro',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'review_received'$$, pg_temp.id('pro2')), '1');
-- 00505 : un avis sur la page et un avis sur une offre, le même jour, font deux notifications.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('n0', (SELECT count(*)::text FROM public.notifications WHERE user_id = pg_temp.id('pro2') AND type = 'review_received'));
PERFORM public.notify_review_received(pg_temp.id('pro2'), 'Cli', 4::smallint, 'Offre A',
  jsonb_build_object('offering_id', gen_random_uuid(), 'review_id', gen_random_uuid(), 'reviewer_id', pg_temp.id('cli')));
PERFORM pg_temp.eq('avis sur une offre après un avis sur la page : le pro est bien prévenu',
  format($$SELECT (count(*) - %s)::text FROM public.notifications WHERE user_id = %L AND type = 'review_received'$$, pg_temp.get('n0'), pg_temp.id('pro2')), '1');
-- PO-4 : un membre bloqué par le pro ne devrait pas pouvoir publier d'avis.
PERFORM pg_temp.as_('har');
PERFORM pg_temp.denied('un membre bloqué par le pro ne laisse pas d''avis', format($$SELECT public.create_pro_review(%L, 1::smallint, 'Harcèlement')::text$$, pg_temp.id('pro')), 'Operation not permitted');

-- ═════ Avis sur une offre ═════
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.put('orv', pg_temp.ok('un membre laisse un avis sur une offre', format($$SELECT public.create_offering_review(%L, 5::smallint, 'Top')::text$$, pg_temp.id('off'))));
PERFORM pg_temp.denied('second avis sur la même offre refusé', format($$SELECT public.create_offering_review(%L, 4::smallint)::text$$, pg_temp.id('off')), 'junto.review_duplicate');
PERFORM pg_temp.put('orv2', pg_temp.ok('un membre laisse un avis sur l''offre de pro2', format($$SELECT public.create_offering_review(%L, 4::smallint, 'Bien')::text$$, pg_temp.id('off2'))));
PERFORM pg_temp.ok('l''auteur modifie son avis d''offre', format($$SELECT public.update_offering_review(%L, 4::smallint, 'Très bien')::text$$, pg_temp.id('orv')));
PERFORM pg_temp.as_('pro');
PERFORM pg_temp.denied('pas d''auto-avis sur sa propre offre', format($$SELECT public.create_offering_review(%L, 5::smallint)::text$$, pg_temp.id('off')));
PERFORM pg_temp.ok('le pro répond à l''avis d''offre', format($$SELECT public.reply_to_offering_review(%L, 'Merci')::text$$, pg_temp.id('orv')));
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.denied('le pro ne répond pas à l''avis d''une offre d''un autre pro', format($$SELECT public.reply_to_offering_review(%L, 'x')::text$$, pg_temp.id('orv2')));
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.denied('un tiers ne modifie pas l''avis d''offre', format($$SELECT public.update_offering_review(%L, 1::smallint)::text$$, pg_temp.id('orv')));
PERFORM pg_temp.denied('un tiers ne supprime pas l''avis d''offre', format($$SELECT public.delete_offering_review(%L)::text$$, pg_temp.id('orv')));
PERFORM pg_temp.denied('avis d''offre inséré directement refusé', format($$INSERT INTO public.offering_reviews (offering_id, reviewer_id, rating) VALUES (%L, %L, 5)$$, pg_temp.id('off2'), pg_temp.id('cli2')));
PERFORM pg_temp.as_('har');
PERFORM pg_temp.denied('un membre bloqué par le pro ne laisse pas d''avis sur son offre', format($$SELECT public.create_offering_review(%L, 1::smallint)::text$$, pg_temp.id('off')), 'Operation not permitted');
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.ok('l''auteur supprime son avis d''offre', format($$SELECT public.delete_offering_review(%L)::text$$, pg_temp.id('orv')));

-- ═════ Désinscription ═════
PERFORM pg_temp.as_('cli');
PERFORM pg_temp.denied('désinscription sans vitrine refusée', $$SELECT public.unregister_as_pro()::text$$);
PERFORM pg_temp.as_('rej');
PERFORM pg_temp.ok('un candidat se désinscrit', $$SELECT public.unregister_as_pro()::text$$);
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.eq('la candidature a disparu', $$SELECT count(*)::text FROM public.get_my_pro_application()$$, '0');

-- ═════ Trous connus sur la lecture ═════
-- L16 : l'identité civile d'un pro ne doit pas être lisible par un autre membre.
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.denied('un membre ne lit pas l''identité civile d''un pro', format($$SELECT real_name FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pro')), 'permission denied', 'L16');

-- B8 : un pro dont la vitrine n'est plus approuvée ne doit plus exposer ni modifier ses offres.
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET status = 'pending' WHERE user_id = pg_temp.id('pro');
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.eq('les offres d''un pro non approuvé sont masquées', format($$SELECT count(*)::text FROM public.pro_offerings WHERE pro_id = %L$$, pg_temp.id('pro')), '0');
PERFORM pg_temp.denied('réserver l''offre d''un pro non approuvé est refusé', format($$SELECT public.create_booking(%L, %L, 'am', 1)::text$$, pg_temp.id('off'), pg_temp.get('d2')));
PERFORM pg_temp.as_('pro');
-- B8 (00501) : un pro en attente prépare ses offres (création et modification permises), elles
-- restent invisibles aux autres tant qu'il n'est pas approuvé.
PERFORM pg_temp.ok('un pro non approuvé prépare ses offres (invisibles aux autres)', format($$SELECT public.update_pro_offering(p_offering_id := %L, p_sport_id := %L, p_title := 'Encore là', p_description := 'd', p_level := 'x',
  p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'B')::text$$, pg_temp.id('off'), pg_temp.id('sport')));
PERFORM pg_temp.denied('un pro non approuvé n''accepte pas de réservation', format($$SELECT public.accept_booking(%L)::text$$, pg_temp.id('bk4')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET status = 'approved' WHERE user_id = pg_temp.id('pro');
PERFORM pg_temp.po_unlock();

-- Suspension de pro2 : sa vitrine, ses offres et ses avis disparaissent.
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = now() WHERE id = pg_temp.id('pro2');
PERFORM pg_temp.po_unlock();
PERFORM pg_temp.as_('cli2');
PERFORM pg_temp.eq('la vitrine d''un pro suspendu est masquée', format($$SELECT count(*)::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pro2')), '0');
PERFORM pg_temp.eq('les offres d''un pro suspendu sont masquées', format($$SELECT count(*)::text FROM public.pro_offerings WHERE pro_id = %L$$, pg_temp.id('pro2')), '0');
PERFORM pg_temp.eq('les avis de vitrine d''un pro suspendu sont masqués', format($$SELECT count(*)::text FROM public.pro_reviews WHERE pro_id = %L$$, pg_temp.id('pro2')), '0');
PERFORM pg_temp.eq('les avis d''offre d''un pro suspendu sont masqués', format($$SELECT count(*)::text FROM public.offering_reviews WHERE offering_id = %L$$, pg_temp.id('off2')), '0');  -- PO-9 : ne se reproduit pas, la sous-requête de la policy passe par la RLS de pro_offerings
PERFORM pg_temp.denied('pas d''avis sur un pro suspendu', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pro2')));
PERFORM pg_temp.as_('pro2');
PERFORM pg_temp.denied('un pro suspendu ne crée pas d''offre', pg_temp.po_offering_sql('Offre suspendue'));
PERFORM pg_temp.denied('un pro suspendu n''ouvre pas d''agenda', $$SELECT count(*)::text FROM public.get_pro_agenda(current_date, current_date + 30)$$);
