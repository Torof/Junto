-- Domaine 13 — trous trouvés par le sweep de couverture (2026-10-23).
-- Comportements qui n'étaient vérifiés par aucun test : chacun pourrait régresser
-- sans bruit. Pas de nouveau comportement ici, seulement des gardes.

EXECUTE $p$CREATE FUNCTION pg_temp.sw_rt(p_topic text) RETURNS int
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT count(*)::int FROM realtime.messages WHERE topic = p_topic $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.sw_push(p_user text) RETURNS int
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT count(*)::int FROM net.http_request_queue WHERE convert_from(body, 'UTF8') LIKE '%' || pg_temp.get(p_user) || '%' $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.sw_act(p_label text, p_key text, p_days int, p_visibility text DEFAULT 'public', p_presence boolean DEFAULT true,
    p_lng double precision DEFAULT 6.6, p_lat double precision DEFAULT 44.9) RETURNS uuid
  LANGUAGE plpgsql AS $b$
  DECLARE v uuid;
  BEGIN
    PERFORM pg_temp.as_(p_label);
    v := public.create_activity(p_sport_id := (SELECT id FROM public.sports WHERE key = 'hiking'), p_title := 'Sortie ' || p_key,
      p_description := 'x', p_level := 'Tous niveaux', p_max_participants := 8, p_meeting_lng := p_lng, p_meeting_lat := p_lat,
      p_end_lng := NULL, p_end_lat := NULL, p_starts_at := now() + make_interval(days => p_days), p_duration := '2 hours',
      p_visibility := p_visibility, p_requires_presence := p_presence);
    PERFORM pg_temp.put(p_key, v::text);
    RETURN v;
  END $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.sw_notifs(p_user text, p_type text, p_act text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT count(*)::text FROM public.notifications
  WHERE user_id = pg_temp.id(p_user) AND type = p_type AND (p_act IS NULL OR data->>'activity_id' = pg_temp.get(p_act)) $b$$p$;

-- ═════ S1 — Quitter ou être retiré d'une sortie ferme son fil ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s1_org', 'tos'); PERFORM pg_temp.user('s1_carl', 'tos'); PERFORM pg_temp.user('s1_dave', 'tos');
PERFORM pg_temp.sw_act('s1_org', 's1_a', 20);
PERFORM pg_temp.as_('s1_carl');
PERFORM pg_temp.eq('S1 carl rejoint', format($$SELECT public.join_activity(%L)$$, pg_temp.get('s1_a')), 'accepted');
PERFORM pg_temp.ok('S1 carl écrit dans le fil', format($$SELECT public.send_wall_message(%L, 'bonjour')::text$$, pg_temp.get('s1_a')));
PERFORM pg_temp.eq('S1 témoin : membre, carl lit le fil', format($$SELECT count(*)::text FROM public.get_wall_messages(%L)$$, pg_temp.get('s1_a')), '1');
PERFORM pg_temp.as_('s1_dave');
PERFORM pg_temp.eq('S1 dave rejoint', format($$SELECT public.join_activity(%L)$$, pg_temp.get('s1_a')), 'accepted');
PERFORM pg_temp.as_('s1_carl');
PERFORM pg_temp.ok('S1 carl quitte la sortie', format($$SELECT public.leave_activity(%L, 'empêchement')::text$$, pg_temp.get('s1_a')));
PERFORM pg_temp.eq('S1 parti : carl ne lit plus le fil', format($$SELECT count(*)::text FROM public.get_wall_messages(%L)$$, pg_temp.get('s1_a')), '0');
PERFORM pg_temp.denied('S1 parti : carl n''écrit plus dans le fil', format($$SELECT public.send_wall_message(%L, 'encore là')::text$$, pg_temp.get('s1_a')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('s1_dpid', (SELECT id::text FROM public.participations WHERE activity_id = pg_temp.get('s1_a')::uuid AND user_id = pg_temp.id('s1_dave')));
PERFORM pg_temp.as_('s1_org');
PERFORM pg_temp.ok('S1 l''organisatrice retire dave', format($$SELECT public.remove_participant(%L)::text$$, pg_temp.get('s1_dpid')));
PERFORM pg_temp.as_('s1_dave');
PERFORM pg_temp.eq('S1 retiré : dave ne lit plus le fil', format($$SELECT count(*)::text FROM public.get_wall_messages(%L)$$, pg_temp.get('s1_a')), '0');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('S1 aucun des deux n''est encore membre du fil',
  format($$SELECT count(*)::text FROM public.conversation_members cm JOIN public.conversations c ON c.id = cm.conversation_id
           WHERE c.activity_id = %L AND cm.user_id IN (%L, %L)$$, pg_temp.get('s1_a'), pg_temp.id('s1_carl'), pg_temp.id('s1_dave')), '0');
PERFORM pg_temp.as_('s1_carl');
PERFORM pg_temp.as_('db');
PERFORM realtime.send('{}'::jsonb, 'wall', 'activity:' || pg_temp.get('s1_a'), true);
PERFORM set_config('realtime.topic', 'activity:' || pg_temp.get('s1_a'), true);
PERFORM pg_temp.as_('s1_org');
PERFORM pg_temp.eq('S1 témoin : l''organisatrice écoute le direct de la sortie',
  format($$SELECT (count(*) > 0)::text FROM realtime.messages WHERE topic = 'activity:' || %L$$, pg_temp.get('s1_a')), 'true');
PERFORM pg_temp.as_('s1_carl');
PERFORM pg_temp.eq('S1 carl n''écoute plus le direct de la sortie',
  format($$SELECT count(*)::text FROM realtime.messages WHERE topic = 'activity:' || %L$$, pg_temp.get('s1_a')), '0');

-- ═════ S2 — Liste exacte des fonctions appelables (une ligne GRANT de trop = alerte) ═════
-- Référence figée le 2026-10-23. Une fonction ajoutée exprès pour l'app se rajoute ici ;
-- une fonction interne qui apparaît ici (ex. delete_account_as) est une faille.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('sw_auth', $ref$ARRAY[
  'public.update_pro_profile(p_display_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text, p_company_name text, p_real_name text, p_clear text[], p_profession text, p_featured_offering_id uuid)',
  'public.get_group_info(p_conversation_id uuid)',
  'public.rename_group(p_conversation_id uuid, p_name text, p_icon text)',
  'public.get_activity_by_invite_token(p_token uuid)',
  'public.delete_message(p_message_id uuid)',
  'public.confirm_presence_via_geo(p_activity_id uuid, p_lng double precision, p_lat double precision, p_captured_at timestamp with time zone, p_skip_push boolean)',
  'public.cancel_booking(p_booking_id uuid)',
  'public.set_pro_availability_bulk(p_days date[], p_periods text[], p_available boolean)',
  'public.get_favorites()',
  'public.consume_trace_elevation_quota()',
  'public.decline_contact_request(p_conversation_id uuid)',
  'public.admin_set_demo_mode(p_on boolean)',
  'public.set_pro_pin_image(p_pin_image_url text)',
  'public.admin_resolve_user(p_user_id uuid)',
  'public.register_as_pro(p_display_name text, p_company_name text, p_real_name text, p_tagline text, p_description text, p_website text, p_email text, p_phone text, p_instagram text, p_facebook text, p_primary_lng double precision, p_primary_lat double precision, p_primary_location_name text, p_profession text)',
  'public.set_offering_details(p_offering_id uuid, p_equipment_provided text[], p_equipment_required text[], p_participant_std text[], p_participant_custom text[])',
  'public.get_conversation_peer(p_conversation_id uuid)',
  'public.reject_pro(p_user_id uuid, p_reason text)',
  'private.message_author_visible(p_conversation_id uuid, p_sender_id uuid, p_viewer_id uuid)',
  'public.remove_missing_gear(p_activity_id uuid, p_name text)',
  'public.get_invitable_activities_for_dispo(p_target_user_id uuid)',
  'public.set_sport_level(p_sport_key text, p_new_level text)',
  'public.create_pro_offering(p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer)',
  'public.get_discovery_cards()',
  'public.resubmit_pro_application()',
  'public.cancel_activity(p_activity_id uuid, p_reason text)',
  'public.get_activity_seat_assignments(p_activity_id uuid)',
  'public.moderate_report(p_report_id uuid, p_action text, p_admin_note text, p_suspend_user_id uuid)',
  'public.join_channel(p_conversation_id uuid)',
  'public.admin_pro_owner(p_pro_id uuid)',
  'public.consume_snap_trail_quota()',
  'public.set_participation_transport(p_activity_id uuid, p_transport_type text, p_transport_seats smallint, p_transport_from_name text, p_transport_departs_at timestamp with time zone, p_transport_from_lat double precision, p_transport_from_lng double precision, p_transport_from_locality text)',
  'public.get_discovery_count(p_sport_keys text[], p_base_lng double precision, p_base_lat double precision, p_radius_km integer, p_window_start timestamp with time zone, p_window_end timestamp with time zone)',
  'public.decline_seat_request(p_request_id uuid)',
  'public.remove_participant(p_participation_id uuid)',
  'public.revoke_contact_qr_tokens(p_token text)',
  'public.cancel_pending_seat_request(p_request_id uuid)',
  'public.remove_channel_member(p_conversation_id uuid, p_user_id uuid)',
  'public.revoke_push_token_for_device(p_device_id text)',
  'public.add_pro_photo(p_photo_url text)',
  'public.accept_participation(p_participation_id uuid)',
  'public.create_offering_review(p_offering_id uuid, p_rating smallint, p_body text)',
  'public.reorder_pro_photos(p_photo_ids uuid[])',
  'public.share_activity_message(p_conversation_id uuid, p_activity_id uuid)',
  'public.mark_tutorial_seen()',
  'public.register_push_token(p_token text, p_device_id text)',
  'public.search_channels(p_query text, p_sport_key text, p_near_lng double precision, p_near_lat double precision)',
  'public.add_missing_gear(p_activity_id uuid, p_name text, p_quantity integer)',
  'public.set_pro_pin_icon(p_pin_icon text)',
  'public.accept_activity_invitation(p_activity_id uuid)',
  'public.get_activity_detail(p_activity_id uuid)',
  'public.get_conversation_state_with(p_other_user_id uuid)',
  'public.delete_offering_review(p_review_id uuid)',
  'public.leave_group(p_conversation_id uuid)',
  'public.get_user_sport_level_votes(p_user_id uuid)',
  'public.admin_unsuspend_user(p_user_id uuid, p_reason text)',
  'public.get_voters_for_badge(p_user_id uuid, p_badge_key text)',
  'public.create_gpx_trace(p_name text, p_geojson jsonb)',
  'public.close_channel(p_conversation_id uuid)',
  'public.refuse_participation(p_participation_id uuid)',
  'public.get_my_invitations()',
  'public.get_activity_participants(p_activity_id uuid)',
  'public.get_user_trophies(p_user_id uuid)',
  'public.create_alert(p_lng double precision, p_lat double precision, p_radius_km integer, p_sport_key text, p_levels text[], p_starts_on date, p_ends_on date)',
  'public.demo_content_visible()',
  'public.get_my_pro_application()',
  'public.add_group_member(p_conversation_id uuid, p_user_id uuid)',
  'private.blocked_either_way(p_a uuid, p_b uuid)',
  'public.consume_trace_elevation_points(p_points integer)',
  'public.deactivate_dispo()',
  'public.create_manual_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_name text, p_phone text)',
  'public.request_seat(p_activity_id uuid, p_driver_id uuid, p_pickup_from text, p_message text, p_requested_pickup_at timestamp with time zone)',
  'public.upsert_dispo(p_sport_keys text[], p_levels jsonb, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_transport_modes text[], p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_intent text[], p_about text)',
  'public.set_channel_photo(p_conversation_id uuid, p_photo_url text)',
  'public.create_contact_qr_token()',
  'public.give_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text)',
  'public.remove_pro_photo(p_photo_id uuid)',
  'public.mark_conversation_read(p_conversation_id uuid)',
  'public.activate_dispo()',
  'public.confirm_age_adult()',
  'public.compute_trace_stats(p_geojson jsonb)',
  'public.admin_suspend_user(p_user_id uuid, p_reason text)',
  'public.leave_activity(p_activity_id uuid, p_reason text)',
  'public.accept_tos()',
  'public.rename_channel(p_conversation_id uuid, p_name text)',
  'public.get_user_public_stats(p_user_id uuid)',
  'public.send_activity_invitations(p_activity_id uuid, p_user_ids uuid[], p_message text)',
  'public.add_pro_offering_photo(p_offering_id uuid, p_photo_url text)',
  'public.cancel_booking_pro(p_booking_id uuid)',
  'public.get_recent_partners()',
  'public.get_user_award_aggregates(p_user_id uuid)',
  'public.create_channel(p_name text, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_sport_key text, p_description text, p_photo_url text, p_force boolean)',
  'public.create_report(p_target_type text, p_target_id uuid, p_reason text)',
  'public.approve_pro(p_user_id uuid)',
  'public.send_discovery_invite(p_target_user_id uuid, p_activity_id uuid)',
  'public.confirm_presence_via_token(p_token text, p_skip_push boolean)',
  'private.strip_invisible(p text)',
  'public.get_wall_messages(p_activity_id uuid)',
  'public.unregister_as_pro()',
  'public.revoke_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text)',
  'public.get_my_dispo()',
  'public.get_contacts()',
  'public.set_pro_availability(p_day date, p_period text, p_available boolean)',
  'public.update_offering_review(p_review_id uuid, p_rating smallint, p_body text)',
  'public.update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb)',
  'public.remove_pro_community_photo(p_photo_id uuid)',
  'public.create_pro_review(p_pro_id uuid, p_rating smallint, p_body text)',
  'public.get_user_reputation(p_user_id uuid)',
  'public.reliability_tier(p_score double precision)',
  'public.get_transport_summary(p_activity_id uuid)',
  'public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text)',
  'public.accept_seat_request(p_request_id uuid)',
  'public.get_own_invite_token(p_activity_id uuid)',
  'public.get_my_active_presence_activities()',
  'public.update_pro_offering(p_offering_id uuid, p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text, p_max_participants integer, p_schedule_text text, p_distance_km numeric, p_elevation_gain_m integer, p_price_eur numeric, p_price_unit text, p_min_participants integer)',
  'public.remove_connection(p_other_user_id uuid)',
  'public.ensure_user_row()',
  'public.update_pro_review(p_review_id uuid, p_rating smallint, p_body text)',
  'public.send_contact_request(p_target_user_id uuid, p_message text, p_source text)',
  'public.remove_favorite(p_kind text, p_id uuid)',
  'public.declare_my_presence(p_activity_id uuid, p_present boolean)',
  'public.leave_channel(p_conversation_id uuid)',
  'public.join_activity(p_activity_id uuid)',
  'public.send_wall_message(p_activity_id uuid, p_content text)',
  'public.create_group(p_name text, p_icon text, p_member_ids uuid[])',
  'public.get_late_leavers(p_activity_id uuid)',
  'private.user_is_suspended(p_user_id uuid)',
  'public.create_activity(p_sport_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_end_lng double precision, p_end_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_requires_presence boolean, p_objective_lng double precision, p_objective_lat double precision, p_objective_name text, p_distance_km numeric, p_elevation_gain_m integer, p_meeting_name text, p_trace_geojson jsonb, p_level_max text, p_meeting_locality text)',
  'public.get_channel_members(p_conversation_id uuid)',
  'public.set_activity_gear(p_activity_id uuid, p_items jsonb)',
  'public.create_presence_token(p_activity_id uuid)',
  'public.get_dispo_zone(p_user_id uuid)',
  'public.accept_contact_request(p_conversation_id uuid)',
  'public.accept_booking(p_booking_id uuid)',
  'public.remove_pro_offering_photo(p_photo_id uuid)',
  'public.add_favorite(p_kind text, p_id uuid)',
  'public.reorder_pro_offering_photos(p_offering_id uuid, p_photo_ids uuid[])',
  'public.get_pro_agenda(p_from date, p_to date)',
  'public.get_my_bookings()',
  'public.get_pending_contact_requests()',
  'public.set_booking_participant_info(p_booking_id uuid, p_info jsonb)',
  'public.share_trace_message(p_conversation_id uuid, p_trace_geojson jsonb, p_name text)',
  'public.reply_to_pro_review(p_review_id uuid, p_reply text)',
  'public.connect_via_qr_token(p_token text, p_expected_owner uuid)',
  'public.admin_get_pending_pro_applications()',
  'public.get_channel(p_conversation_id uuid)',
  'public.rename_gpx_trace(p_id uuid, p_name text)',
  'public.cancel_accepted_seat(p_request_id uuid)',
  'public.get_pro_availability(p_pro_id uuid)',
  'public.send_private_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid)',
  'public.add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid, p_offering_id uuid)',
  'public.reply_to_offering_review(p_review_id uuid, p_reply text)',
  'public.get_my_conversations()',
  'public.admin_remove_content(p_target_type text, p_target_id uuid, p_reason text)',
  'public.delete_gpx_trace(p_id uuid)',
  'public.delete_pro_review(p_review_id uuid)',
  'public.delete_pro_offering(p_offering_id uuid)',
  'public.edit_message(p_message_id uuid, p_content text)',
  'public.update_activity(p_activity_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_starts_at timestamp with time zone, p_duration text, p_visibility text, p_level_max text, p_meeting_locality text)',
  'private.is_active_admin(p_uid uuid)',
  'private.is_conversation_member(p_conversation_id uuid, p_user_id uuid)',
  'private.demo_channel_hidden(p_conversation_id uuid)',
  'public.set_message_reaction(p_message_id uuid, p_emoji text)',
  'public.get_channel_preview(p_conversation_id uuid)',
  'public.send_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid)',
  'public.waive_late_cancel_penalty(p_participation_id uuid)',
  'public.transition_single_activity(p_activity_id uuid)',
  'public.decline_booking(p_booking_id uuid)',
  'public.get_user_sport_levels(p_user_id uuid)',
  'public.get_activity_peer_review_state(p_activity_id uuid)',
  'public.decline_activity_invitation(p_activity_id uuid)',
  'public.set_conversation_hidden(p_conversation_id uuid, p_hidden boolean)']$ref$);
PERFORM pg_temp.put('sw_anon', $ref$ARRAY[
  'private.message_author_visible(p_conversation_id uuid, p_sender_id uuid, p_viewer_id uuid)',
  'public.demo_content_visible()',
  'private.user_is_suspended(p_user_id uuid)',
  'private.is_conversation_member(p_conversation_id uuid, p_user_id uuid)']$ref$);
PERFORM pg_temp.eq('S2 aucune fonction appelable par un compte en dehors de la liste',
  format($q$SELECT coalesce(string_agg(s, ', '), '') FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS s FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('public', 'private') AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE') EXCEPT SELECT unnest(%s)) x$q$, pg_temp.get('sw_auth')), '');
PERFORM pg_temp.eq('S2 toutes les fonctions de la liste restent appelables par un compte',
  format($q$SELECT coalesce(string_agg(s, ', '), '') FROM (SELECT unnest(%s) AS s EXCEPT SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('public', 'private') AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE')) x$q$, pg_temp.get('sw_auth')), '');
PERFORM pg_temp.eq('S2 aucune fonction appelable sans compte en dehors de la liste',
  format($q$SELECT coalesce(string_agg(s, ', '), '') FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS s FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('public', 'private') AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
    AND has_function_privilege('anon', p.oid, 'EXECUTE') EXCEPT SELECT unnest(%s)) x$q$, pg_temp.get('sw_anon')), '');
PERFORM pg_temp.eq('S2 delete_account_as reste réservée au service', $q$SELECT (has_function_privilege('authenticated', 'public.delete_account_as(uuid)', 'EXECUTE')
  OR has_function_privilege('anon', 'public.delete_account_as(uuid)', 'EXECUTE'))::text$q$, 'false');

-- ═════ S3 — Le bloqué ne voit pas qui l'a bloqué et ne peut pas lever le blocage ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s3_alice', 'tos'); PERFORM pg_temp.user('s3_bob', 'tos');
PERFORM pg_temp.as_('s3_alice');
PERFORM pg_temp.ok('S3 alice bloque bob', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('s3_alice'), pg_temp.id('s3_bob')));
PERFORM pg_temp.eq('S3 témoin : alice voit son blocage', format($$SELECT count(*)::text FROM public.blocked_users WHERE blocked_id = %L$$, pg_temp.id('s3_bob')), '1');
PERFORM pg_temp.as_('s3_bob');
PERFORM pg_temp.eq('S3 bob ne voit pas qu''alice l''a bloqué', format($$SELECT count(*)::text FROM public.blocked_users WHERE blocked_id = %L$$, pg_temp.id('s3_bob')), '0');
PERFORM pg_temp.eq('S3 bob ne supprime pas le blocage d''alice', format($$DELETE FROM public.blocked_users WHERE blocker_id = %L$$, pg_temp.id('s3_alice')), '0');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('S3 le blocage est toujours là', format($$SELECT count(*)::text FROM public.blocked_users WHERE blocker_id = %L AND blocked_id = %L$$, pg_temp.id('s3_alice'), pg_temp.id('s3_bob')), '1');

-- ═════ S4 — Écoute en direct : on n'écoute que ses propres sujets ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s4_alice', 'tos'); PERFORM pg_temp.user('s4_bob', 'tos'); PERFORM pg_temp.user('s4_carl', 'tos');
PERFORM realtime.send('{}'::jsonb, 'inbox', 'user:' || pg_temp.get('s4_alice'), true);
PERFORM pg_temp.as_('s4_alice');
PERFORM pg_temp.put('s4_ch', pg_temp.ok('S4 alice ouvre une discussion', $$SELECT conversation_id::text FROM public.create_channel('Canal S4', -141, -41, 'Océan', 35, NULL, NULL, NULL, true)$$));
PERFORM pg_temp.as_('s4_carl');
PERFORM pg_temp.ok('S4 carl rejoint la discussion', format($$SELECT public.join_channel(%L)::text$$, pg_temp.get('s4_ch')));
PERFORM pg_temp.as_('db');
PERFORM realtime.send('{}'::jsonb, 'new', 'conversation:' || pg_temp.get('s4_ch'), true);
PERFORM pg_temp.as_('s4_alice');
PERFORM set_config('realtime.topic', 'user:' || pg_temp.get('s4_alice'), true);
PERFORM pg_temp.eq('S4 témoin : alice écoute son propre sujet', format($$SELECT count(*)::text FROM realtime.messages WHERE topic = 'user:' || %L$$, pg_temp.get('s4_alice')), '1');
PERFORM pg_temp.as_('s4_bob');
PERFORM set_config('realtime.topic', 'user:' || pg_temp.get('s4_alice'), true);
PERFORM pg_temp.eq('S4 bob n''écoute pas le sujet d''alice', format($$SELECT count(*)::text FROM realtime.messages WHERE topic = 'user:' || %L$$, pg_temp.get('s4_alice')), '0');
PERFORM pg_temp.as_('s4_carl');
PERFORM set_config('realtime.topic', 'conversation:' || pg_temp.get('s4_ch'), true);
PERFORM pg_temp.eq('S4 témoin : un membre écoute la discussion', format($$SELECT count(*)::text FROM realtime.messages WHERE topic = 'conversation:' || %L$$, pg_temp.get('s4_ch')), '1');
PERFORM pg_temp.as_('s4_bob');
PERFORM set_config('realtime.topic', 'conversation:' || pg_temp.get('s4_ch'), true);
PERFORM pg_temp.eq('S4 un non-membre n''écoute pas la discussion', format($$SELECT count(*)::text FROM realtime.messages WHERE topic = 'conversation:' || %L$$, pg_temp.get('s4_ch')), '0');

-- ═════ S5 — Celui qui a bloqué l'expéditeur ne reçoit ni push ni signal ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s5_own', 'tos'); PERFORM pg_temp.user('s5_bob', 'tos'); PERFORM pg_temp.user('s5_dave', 'tos');
PERFORM pg_temp.as_('s5_own');
PERFORM pg_temp.put('s5_ch', pg_temp.ok('S5 ouverture d''une discussion', $$SELECT conversation_id::text FROM public.create_channel('Canal S5', -142, -42, 'Océan', 35, NULL, NULL, NULL, true)$$));
PERFORM pg_temp.as_('s5_bob'); PERFORM pg_temp.ok('S5 bob rejoint', format($$SELECT public.join_channel(%L)::text$$, pg_temp.get('s5_ch')));
PERFORM pg_temp.as_('s5_dave'); PERFORM pg_temp.ok('S5 dave rejoint', format($$SELECT public.join_channel(%L)::text$$, pg_temp.get('s5_ch')));
PERFORM pg_temp.as_('s5_bob');
PERFORM pg_temp.ok('S5 bob bloque dave', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('s5_bob'), pg_temp.id('s5_dave')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('s5_p_bob', pg_temp.sw_push('s5_bob')::text); PERFORM pg_temp.put('s5_p_own', pg_temp.sw_push('s5_own')::text);
PERFORM pg_temp.put('s5_r_bob', pg_temp.sw_rt('user:' || pg_temp.get('s5_bob'))::text); PERFORM pg_temp.put('s5_r_own', pg_temp.sw_rt('user:' || pg_temp.get('s5_own'))::text);
PERFORM pg_temp.as_('s5_dave');
PERFORM pg_temp.ok('S5 dave écrit', format($$SELECT public.send_message(%L, 'message de dave')::text$$, pg_temp.get('s5_ch')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('S5 témoin : l''animatrice reçoit push et signal',
  format($$SELECT ((pg_temp.sw_push('s5_own') > %s) AND (pg_temp.sw_rt('user:' || pg_temp.get('s5_own')) > %s))::text$$, pg_temp.get('s5_p_own'), pg_temp.get('s5_r_own')), 'true');
PERFORM pg_temp.eq('S5 bob, qui a bloqué dave, ne reçoit rien',
  format($$SELECT ((pg_temp.sw_push('s5_bob') - %s) + (pg_temp.sw_rt('user:' || pg_temp.get('s5_bob')) - %s))::text$$, pg_temp.get('s5_p_bob'), pg_temp.get('s5_r_bob')), '0');

-- ═════ S6 — Alertes de sorties ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s6_al', 'tos'); PERFORM pg_temp.user('s6_c1', 'tos'); PERFORM pg_temp.user('s6_c2', 'tos'); PERFORM pg_temp.user('s6_blk', 'tos');
PERFORM pg_temp.as_('s6_al');
PERFORM pg_temp.ok('S6 alerte sur une zone', $$SELECT public.create_alert(-143.0, -43.0, 20)::text$$);
PERFORM pg_temp.ok('S6 l''abonnée bloque un organisateur', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('s6_al'), pg_temp.id('s6_blk')));
PERFORM pg_temp.sw_act('s6_c1', 's6_pub', 20, 'public', true, -143.0, -43.0);
PERFORM pg_temp.eq('S6 une sortie publique dans la zone prévient l''abonnée', $$SELECT pg_temp.sw_notifs('s6_al', 'alert_match', 's6_pub')$$, '1');
PERFORM pg_temp.sw_act('s6_c1', 's6_priv', 21, 'private_link', true, -143.0, -43.0);
PERFORM pg_temp.eq('S6 une sortie privée ne prévient personne', $$SELECT pg_temp.sw_notifs('s6_al', 'alert_match', 's6_priv')$$, '0');
PERFORM pg_temp.sw_act('s6_blk', 's6_b', 22, 'public', true, -143.0, -43.0);
PERFORM pg_temp.eq('S6 la sortie d''un organisateur bloqué ne prévient pas', $$SELECT pg_temp.sw_notifs('s6_al', 'alert_match', 's6_b')$$, '0');
PERFORM pg_temp.sw_act('s6_c1', 's6_far', 23, 'public', true, -150.0, -43.0);
PERFORM pg_temp.eq('S6 hors du rayon : rien', $$SELECT pg_temp.sw_notifs('s6_al', 'alert_match', 's6_far')$$, '0');
PERFORM pg_temp.sw_act('s6_al', 's6_own', 24, 'public', true, -143.0, -43.0);
PERFORM pg_temp.eq('S6 sa propre sortie ne la prévient pas', $$SELECT pg_temp.sw_notifs('s6_al', 'alert_match', 's6_own')$$, '0');
PERFORM pg_temp.sw_act('s6_c2', 's6_p2', 25, 'approval', true, -143.0, -43.0);
PERFORM pg_temp.sw_act('s6_c2', 's6_p3', 26, 'public', true, -143.0, -43.0);
PERFORM pg_temp.sw_act('s6_c2', 's6_p4', 27, 'public', true, -143.0, -43.0);
PERFORM pg_temp.eq('S6 au plus 3 alertes par jour', $$SELECT pg_temp.sw_notifs('s6_al', 'alert_match', NULL)$$, '3');

-- ═════ S7 — Couper un type de notification dans les réglages ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s7_org', 'tos'); PERFORM pg_temp.user('s7_off', 'tos'); PERFORM pg_temp.user('s7_on', 'tos');
PERFORM pg_temp.sw_act('s7_org', 's7_a', 20);
PERFORM pg_temp.as_('s7_off');
PERFORM pg_temp.eq('S7 rejoint', format($$SELECT public.join_activity(%L)$$, pg_temp.get('s7_a')), 'accepted');
PERFORM pg_temp.ok('S7 coupe « activité modifiée » dans ses réglages', format($$UPDATE public.users SET notification_preferences = '{"activity_updated": false}'::jsonb WHERE id = %L$$, pg_temp.id('s7_off')));
PERFORM pg_temp.as_('s7_on');
PERFORM pg_temp.eq('S7 témoin rejoint', format($$SELECT public.join_activity(%L)$$, pg_temp.get('s7_a')), 'accepted');
PERFORM pg_temp.as_('s7_org');
PERFORM pg_temp.ok('S7 l''organisatrice modifie le titre', format($$SELECT public.update_activity(%L, p_title => 'Titre modifié S7')::text$$, pg_temp.get('s7_a')));
PERFORM pg_temp.eq('S7 témoin : prévenu', $$SELECT pg_temp.sw_notifs('s7_on', 'activity_updated', 's7_a')$$, '1');
PERFORM pg_temp.eq('S7 qui a coupé ce type n''est pas prévenu', $$SELECT pg_temp.sw_notifs('s7_off', 'activity_updated', 's7_a')$$, '0');

-- ═════ S8 — Les rappels de présence du balayage minute partent vraiment ═════
-- Appel direct de transition_statuses_only : une erreur d'exécution (fonction renommée,
-- colonne disparue) casse ce test au lieu d'être avalée en WARNING par la tâche minute.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s8_o1', 'tos'); PERFORM pg_temp.user('s8_p1', 'tos');
PERFORM pg_temp.user('s8_o2', 'tos'); PERFORM pg_temp.user('s8_p2', 'tos');
PERFORM pg_temp.user('s8_o3', 'tos'); PERFORM pg_temp.user('s8_p3', 'tos');
PERFORM pg_temp.sw_act('s8_o1', 's8_soon', 30); PERFORM pg_temp.sw_act('s8_o2', 's8_mid', 31); PERFORM pg_temp.sw_act('s8_o3', 's8_done', 32);
PERFORM pg_temp.as_('s8_p1'); PERFORM pg_temp.eq('S8 p1 rejoint', format($$SELECT public.join_activity(%L)$$, pg_temp.get('s8_soon')), 'accepted');
PERFORM pg_temp.as_('s8_p2'); PERFORM pg_temp.eq('S8 p2 rejoint', format($$SELECT public.join_activity(%L)$$, pg_temp.get('s8_mid')), 'accepted');
PERFORM pg_temp.as_('s8_p3'); PERFORM pg_temp.eq('S8 p3 rejoint', format($$SELECT public.join_activity(%L)$$, pg_temp.get('s8_done')), 'accepted');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET starts_at = now() + interval '5 minutes' WHERE id = pg_temp.get('s8_soon')::uuid;
UPDATE public.activities SET starts_at = now() - interval '2 hours', duration = '3 hours', status = 'in_progress' WHERE id = pg_temp.get('s8_mid')::uuid;
UPDATE public.activities SET starts_at = now() - interval '3 hours 10 minutes', duration = '2 hours', status = 'completed' WHERE id = pg_temp.get('s8_done')::uuid;
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.ok('S8 le balayage tourne sans erreur', $$SELECT public.transition_statuses_only()::text$$);
PERFORM pg_temp.eq('S8 T-2h : rappel au participant', $$SELECT pg_temp.sw_notifs('s8_p1', 'presence_pre_warning', 's8_soon')$$, '1');
PERFORM pg_temp.eq('S8 T-10 min : rappel au participant', $$SELECT pg_temp.sw_notifs('s8_p1', 'presence_pre_warning_10min', 's8_soon')$$, '1');
PERFORM pg_temp.eq('S8 T-10 min : rappel QR à l''organisatrice', $$SELECT pg_temp.sw_notifs('s8_o1', 'qr_create_reminder', 's8_soon')$$, '1');
PERFORM pg_temp.eq('S8 mi-sortie : rappel de valider', $$SELECT pg_temp.sw_notifs('s8_p2', 'presence_validate_warning', 's8_mid')$$, '1');
PERFORM pg_temp.eq('S8 fin + 1 h : présence non validée', $$SELECT pg_temp.sw_notifs('s8_p3', 'presence_validate_overdue', 's8_done')$$, '1');
PERFORM pg_temp.eq('S8 fin + 15 min : invitation à évaluer', $$SELECT pg_temp.sw_notifs('s8_p3', 'rate_participants', 's8_done')$$, '1');

-- ═════ S9 — Toute fonction qui utilise PostGIS a « extensions » dans son chemin ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('S9 aucune fonction PostGIS sans extensions dans son search_path',
  $q$SELECT coalesce(string_agg(n.nspname || '.' || p.proname, ', '), '') FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'private') AND p.prosrc ~ '\mST_[A-Za-z]|::geograph|::geometr'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
       AND coalesce(array_to_string(p.proconfig, ','), '') !~ 'extensions'$q$, '');

-- ═════ S10 — Colonnes figées des vues lisibles par d'autres comptes ═════
PERFORM pg_temp.eq('S10 public_profiles : colonnes exactes (pas d''e-mail, pas de réglages)',
  $q$SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'public_profiles'$q$,
  'avatar_url,bio,created_at,display_name,id,is_demo,levels_per_sport,reliability_score,reliability_tier,sports');
PERFORM pg_temp.eq('S10 activities_with_coords (lisible sans compte) : colonnes exactes',
  $q$SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'activities_with_coords'$q$,
  'created_at,creator_avatar,creator_id,creator_name,deleted_at,description,distance_km,duration,elevation_gain_m,end_lat,end_lng,id,lat,level,level_max,lng,max_participants,meeting_lat,meeting_lng,meeting_locality,meeting_name,objective_lat,objective_lng,objective_name,participant_count,requires_presence,sport_category,sport_icon,sport_id,sport_key,starts_at,status,title,trace_geojson,updated_at,visibility');
PERFORM pg_temp.eq('S10 pro_offerings_with_coords : colonnes exactes',
  $q$SELECT string_agg(column_name, ',' ORDER BY column_name) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pro_offerings_with_coords'$q$,
  'created_at,description,distance_km,duration,elevation_gain_m,equipment_provided,equipment_required,id,image_url,lat,level,lng,location_name,max_participants,min_participants,participant_fields,price_eur,price_unit,pro_id,pro_name,schedule_text,sport_category,sport_icon,sport_id,sport_key,title,updated_at');

-- ═════ S11 — Stockage : on ne renomme pas le fichier d'un autre ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s11_a', 'tos'); PERFORM pg_temp.user('s11_b', 'tos');
INSERT INTO storage.objects (bucket_id, name, owner, owner_id) VALUES
  ('avatars', pg_temp.get('s11_b') || '/photo.jpg', pg_temp.id('s11_b'), pg_temp.get('s11_b'));
PERFORM pg_temp.as_('s11_a');
PERFORM pg_temp.eq('S11 alice ne renomme pas la photo de bob',
  format($$UPDATE storage.objects SET name = %L WHERE bucket_id = 'avatars' AND name = %L$$, pg_temp.get('s11_a') || '/vol.jpg', pg_temp.get('s11_b') || '/photo.jpg'), '0');
PERFORM pg_temp.as_('s11_b');
PERFORM pg_temp.eq('S11 témoin : bob modifie la sienne',
  format($$UPDATE storage.objects SET metadata = '{}'::jsonb WHERE bucket_id = 'avatars' AND name = %L$$, pg_temp.get('s11_b') || '/photo.jpg'), '1');

-- ═════ S12 — Le garde « compte finalisé » reste posé sur ses tables ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('S12 tables qui exigent un compte finalisé',
  $q$SELECT string_agg(tgrelid::regclass::text, ',' ORDER BY tgrelid::regclass::text) FROM pg_trigger WHERE tgfoid = 'private.require_onboarded_actor'::regproc$q$,
  'activities,bookings,contact_qr_tokens,conversation_members,conversations,discovery_availabilities,gpx_traces,messages,participations,pro_profiles,reputation_votes,seat_requests');

-- ═════ S13 — Alertes : chacun supprime les siennes en direct, pas celles des autres (voulu) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('s13_a', 'tos'); PERFORM pg_temp.user('s13_b', 'tos');
PERFORM pg_temp.as_('s13_a');
PERFORM pg_temp.ok('S13 a crée deux alertes', $$SELECT public.create_alert(-146.0, -46.0, 20)::text || public.create_alert(-147.0, -47.0, 20)::text$$);
PERFORM pg_temp.as_('s13_b');
PERFORM pg_temp.eq('S13 b ne supprime pas les alertes de a', format($$DELETE FROM public.activity_alerts WHERE user_id = %L$$, pg_temp.id('s13_a')), '0');
PERFORM pg_temp.as_('s13_a');
PERFORM pg_temp.eq('S13 a supprime une de ses alertes', $$DELETE FROM public.activity_alerts WHERE ctid = (SELECT ctid FROM public.activity_alerts LIMIT 1)$$, '1');
