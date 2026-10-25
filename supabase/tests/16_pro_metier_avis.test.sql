-- Domaine 16 — métier du pro, sortie mise en avant, avis réservés à qui a réservé (mig 00554).

-- ───── Fixtures : deux pros approuvés avec une offre chacun, un client, un admin ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('pm_pro', 'tos');
PERFORM pg_temp.user('pm_pro2', 'tos');
PERFORM pg_temp.user('pm_cli', 'tos');
PERFORM pg_temp.user('pm_adm', 'tos,admin');
PERFORM pg_temp.put('pm_sport', (SELECT id::text FROM public.sports WHERE key = 'canyoning'));

PERFORM pg_temp.as_('pm_pro');
PERFORM pg_temp.ok('PM0 inscription pro avec un métier',
  $$SELECT public.register_as_pro(p_display_name := 'Vertige Canyon', p_company_name := 'SARL Vertige', p_real_name := 'Jean Test',
      p_primary_lng := 6.55, p_primary_lat := 44.79, p_primary_location_name := 'L''Argentière', p_profession := 'canyoning_instructor')::text$$);
PERFORM pg_temp.as_('pm_pro2');
PERFORM pg_temp.denied('PM0 inscription avec un métier hors liste refusée',
  $$SELECT public.register_as_pro(p_display_name := 'X', p_company_name := 'SARL X', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon', p_profession := 'astronaute')::text$$, 'junto.pro_profession_invalid');
PERFORM pg_temp.ok('PM0 inscription sans métier (nullable)',
  $$SELECT public.register_as_pro(p_display_name := 'Bureau des Guides', p_company_name := 'SARL Guides', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$$);
PERFORM pg_temp.as_('pm_adm');
PERFORM pg_temp.ok('PM0 admin approuve pro', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pm_pro')));
PERFORM pg_temp.ok('PM0 admin approuve pro2', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('pm_pro2')));
PERFORM pg_temp.as_('pm_pro');
PERFORM pg_temp.put('pm_off', pg_temp.ok('PM0 pro crée une offre', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := 'Initiation Fournel', p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.55, p_location_lat := 44.79, p_location_name := 'Fournel',
      p_max_participants := 6, p_price_eur := 55, p_price_unit := 'person')::text$$, pg_temp.id('pm_sport'))));
PERFORM pg_temp.as_('pm_pro2');
PERFORM pg_temp.put('pm_off2', pg_temp.ok('PM0 pro2 crée une offre', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := 'Rif Bel', p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Rif Bel',
      p_max_participants := 4, p_price_eur := 85, p_price_unit := 'person')::text$$, pg_temp.id('pm_sport'))));

-- ═════ PM1 — Le métier ═════
PERFORM pg_temp.as_('pm_cli');
PERFORM pg_temp.eq('PM1 le métier est lisible par un autre membre',
  format($$SELECT profession FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pm_pro')), 'canyoning_instructor');
PERFORM pg_temp.as_('pm_pro2');
PERFORM pg_temp.ok('PM1 le pro renseigne son métier après coup', $$SELECT public.update_pro_profile(p_profession := 'school_office')::text$$);
PERFORM pg_temp.denied('PM1 métier hors liste refusé à la modification', $$SELECT public.update_pro_profile(p_profession := 'sorcier')::text$$, 'junto.pro_profession_invalid');
PERFORM pg_temp.eq('PM1 le pro relit son métier', $$SELECT profession FROM public.get_my_pro_application()$$, 'school_office');
PERFORM pg_temp.ok('PM1 le pro vide son métier', $$SELECT public.update_pro_profile(p_clear := ARRAY['profession'])::text$$);
PERFORM pg_temp.eq('PM1 métier vidé', $$SELECT coalesce(profession, 'NULL') FROM public.get_my_pro_application()$$, 'NULL');
PERFORM pg_temp.denied('PM1 pas d''écriture directe du métier',
  format($$UPDATE public.pro_profiles SET profession = 'mountain_guide' WHERE user_id = %L RETURNING 1$$, pg_temp.id('pm_pro2')));

-- ═════ PM2 — La sortie mise en avant ═════
PERFORM pg_temp.as_('pm_pro');
PERFORM pg_temp.ok('PM2 le pro met en avant sa propre offre', format($$SELECT public.update_pro_profile(p_featured_offering_id := %L)::text$$, pg_temp.id('pm_off')));
PERFORM pg_temp.denied('PM2 l''offre d''un autre pro est refusée (erreur générique)', format($$SELECT public.update_pro_profile(p_featured_offering_id := %L)::text$$, pg_temp.id('pm_off2')), 'Operation not permitted');
PERFORM pg_temp.denied('PM2 une offre inexistante est refusée de la même façon', format($$SELECT public.update_pro_profile(p_featured_offering_id := %L)::text$$, gen_random_uuid()), 'Operation not permitted');
PERFORM pg_temp.as_('pm_cli');
PERFORM pg_temp.eq('PM2 la sortie mise en avant est lisible par un autre membre',
  format($$SELECT featured_offering_id::text FROM public.pro_profiles WHERE user_id = %L$$, pg_temp.id('pm_pro')), pg_temp.get('pm_off'));
PERFORM pg_temp.as_('pm_pro');
PERFORM pg_temp.ok('PM2 le pro retire la mise en avant', $$SELECT public.update_pro_profile(p_clear := ARRAY['featured_offering_id'])::text$$);
PERFORM pg_temp.eq('PM2 plus de mise en avant', $$SELECT coalesce(featured_offering_id::text, 'NULL') FROM public.get_my_pro_application()$$, 'NULL');
PERFORM pg_temp.ok('PM2 remise en avant', format($$SELECT public.update_pro_profile(p_featured_offering_id := %L)::text$$, pg_temp.id('pm_off')));
PERFORM pg_temp.as_('pm_pro2');
PERFORM pg_temp.put('pm_off2b', pg_temp.ok('PM2 pro2 crée une seconde offre', format($$SELECT public.create_pro_offering(p_sport_id := %L, p_title := 'Éphémère', p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'X',
      p_max_participants := 4, p_price_eur := 10, p_price_unit := 'person')::text$$, pg_temp.id('pm_sport'))));
PERFORM pg_temp.ok('PM2 pro2 la met en avant', format($$SELECT public.update_pro_profile(p_featured_offering_id := %L)::text$$, pg_temp.id('pm_off2b')));
PERFORM pg_temp.ok('PM2 pro2 supprime cette offre', format($$SELECT public.delete_pro_offering(%L)::text$$, pg_temp.id('pm_off2b')));
PERFORM pg_temp.eq('PM2 la mise en avant retombe à NULL avec l''offre', $$SELECT coalesce(featured_offering_id::text, 'NULL') FROM public.get_my_pro_application()$$, 'NULL');

-- ═════ PM3 — Avis réservés à qui a réservé ═════
PERFORM pg_temp.as_('pm_cli');
PERFORM pg_temp.denied('PM3 sans réservation, pas d''avis sur le pro', format($$SELECT public.create_pro_review(%L, 5::smallint, 'Top')::text$$, pg_temp.id('pm_pro')), 'junto.review_requires_booking');
PERFORM pg_temp.denied('PM3 sans réservation, pas d''avis sur l''offre', format($$SELECT public.create_offering_review(%L, 5::smallint, 'Top')::text$$, pg_temp.id('pm_off')), 'junto.review_requires_booking');
-- Une réservation en attente, puis acceptée mais à venir : toujours pas.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('pm_bk_future', gen_random_uuid()::text);
INSERT INTO public.bookings (id, offering_id, pro_id, client_id, day, period, party_size, status)
VALUES (pg_temp.id('pm_bk_future'), pg_temp.id('pm_off'), pg_temp.id('pm_pro'), pg_temp.id('pm_cli'), current_date + 10, 'am', 2, 'pending');
PERFORM pg_temp.as_('pm_cli');
PERFORM pg_temp.denied('PM3 réservation en attente : pas d''avis', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pm_pro')), 'junto.review_requires_booking');
PERFORM pg_temp.as_('db');
UPDATE public.bookings SET status = 'accepted' WHERE id = pg_temp.id('pm_bk_future');
PERFORM pg_temp.as_('pm_cli');
PERFORM pg_temp.denied('PM3 réservation acceptée mais à venir : pas d''avis', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pm_pro')), 'junto.review_requires_booking');
-- Une réservation acceptée et passée : oui, sur le pro et sur l'offre.
PERFORM pg_temp.as_('db');
INSERT INTO public.bookings (offering_id, pro_id, client_id, day, period, party_size, status)
VALUES (pg_temp.id('pm_off'), pg_temp.id('pm_pro'), pg_temp.id('pm_cli'), current_date - 7, 'am', 2, 'accepted');
PERFORM pg_temp.as_('pm_cli');
PERFORM pg_temp.ok('PM3 sortie faite : avis sur le pro', format($$SELECT public.create_pro_review(%L, 5::smallint, 'Pédagogues')::text$$, pg_temp.id('pm_pro')));
PERFORM pg_temp.ok('PM3 sortie faite : avis sur l''offre', format($$SELECT public.create_offering_review(%L, 5::smallint, 'Top')::text$$, pg_temp.id('pm_off')));
PERFORM pg_temp.denied('PM3 la sortie chez pro ne donne pas d''avis sur pro2', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pm_pro2')), 'junto.review_requires_booking');
PERFORM pg_temp.denied('PM3 ni sur l''offre de pro2', format($$SELECT public.create_offering_review(%L, 5::smallint)::text$$, pg_temp.id('pm_off2')), 'junto.review_requires_booking');
-- Une réservation annulée ne compte pas.
PERFORM pg_temp.as_('db');
INSERT INTO public.bookings (offering_id, pro_id, client_id, day, period, party_size, status)
VALUES (pg_temp.id('pm_off2'), pg_temp.id('pm_pro2'), pg_temp.id('pm_cli'), current_date - 3, 'pm', 1, 'cancelled');
PERFORM pg_temp.as_('pm_cli');
PERFORM pg_temp.denied('PM3 une réservation annulée ne donne pas d''avis', format($$SELECT public.create_pro_review(%L, 5::smallint)::text$$, pg_temp.id('pm_pro2')), 'junto.review_requires_booking');

-- ═════ PM4 — Sans compte ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('PM4 anon : pas d''inscription pro', $$SELECT public.register_as_pro(p_display_name := 'X', p_company_name := 'SARL X', p_real_name := 'Jean Test', p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'B', p_profession := 'other')::text$$);
PERFORM pg_temp.denied('PM4 anon : pas de modification pro', $$SELECT public.update_pro_profile(p_profession := 'other')::text$$);
PERFORM pg_temp.denied('PM4 anon : pas de lecture de sa candidature', $$SELECT count(*)::text FROM public.get_my_pro_application()$$);
