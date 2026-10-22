-- Domaine 12 — correctifs de l'audit par attaques réelles (2026-10-23).
-- Chaque bloc reprend l'attaque qui avait réussi et vérifie qu'elle est refusée,
-- puis que le chemin légitime voisin marche toujours.

-- ═════ C1 — Un admin suspendu perd tous ses pouvoirs, y compris par les tables (00527) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c1_alice', 'tos'); PERFORM pg_temp.user('c1_bob', 'tos');
PERFORM pg_temp.user('c1_adm', 'tos,admin'); PERFORM pg_temp.user('c1_sadm', 'tos,admin,suspended');
INSERT INTO public.reports (reporter_id, target_type, target_id, reason, status)
VALUES (pg_temp.id('c1_alice'), 'user', pg_temp.id('c1_bob'), 'motif de test', 'pending');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('c1_alice'), pg_temp.id('c1_bob'));
PERFORM pg_temp.as_('c1_sadm');
PERFORM pg_temp.eq('C1 un admin suspendu ne lit pas les signalements', format($$SELECT count(*)::text FROM public.reports WHERE reporter_id = %L$$, pg_temp.id('c1_alice')), '0');
PERFORM pg_temp.eq('C1 un admin suspendu ne lit pas les blocages des autres', format($$SELECT count(*)::text FROM public.blocked_users WHERE blocker_id = %L$$, pg_temp.id('c1_alice')), '0');
PERFORM pg_temp.eq('C1 un admin suspendu ne lit pas le journal d''administration', $$SELECT count(*)::text FROM public.admin_actions$$, '0');
PERFORM pg_temp.eq('C1 un admin suspendu ne modifie pas le catalogue des sports', $$UPDATE public.sports SET icon = icon WHERE key = 'hiking'$$, '0');
PERFORM pg_temp.as_('c1_adm');
PERFORM pg_temp.eq('C1 un admin actif lit les signalements', format($$SELECT count(*)::text FROM public.reports WHERE reporter_id = %L$$, pg_temp.id('c1_alice')), '1');
PERFORM pg_temp.eq('C1 un admin actif lit les blocages (modération)', format($$SELECT count(*)::text FROM public.blocked_users WHERE blocker_id = %L$$, pg_temp.id('c1_alice')), '1');
PERFORM pg_temp.eq('C1 un admin actif modifie le catalogue des sports', $$UPDATE public.sports SET icon = icon WHERE key = 'hiking'$$, '1');
PERFORM pg_temp.eq('C1 même un admin actif ne réécrit pas un signalement directement (seulement par moderate_report)',
  format($$UPDATE public.reports SET status = 'dismissed', reason = 'réécrit' WHERE reporter_id = %L$$, pg_temp.id('c1_alice')), '0');

-- ═════ C2 — Les compteurs publics comptent toutes les sorties terminées (00528, Scott) ═════
-- Une absence ne se devine plus en comparant les compteurs avant / après une sortie.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c2_org', 'tos'); PERFORM pg_temp.user('c2_pres', 'tos'); PERFORM pg_temp.user('c2_abs', 'tos'); PERFORM pg_temp.user('c2_vue', 'tos');
PERFORM pg_temp.put('c2_act', pg_temp.run(format($q$INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting, starts_at, duration, visibility, status, requires_presence)
  VALUES (%L, (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie C2', 'Tous niveaux', 8,
          ST_SetSRID(ST_MakePoint(-138.5, -45.5), 4326)::geography, now() - interval '3 days', interval '3 hours', 'public', 'completed', true)
  RETURNING id::text$q$, pg_temp.id('c2_org'))));
INSERT INTO public.participations (activity_id, user_id, status, confirmed_present, created_at) VALUES
  (pg_temp.id('c2_act'), pg_temp.id('c2_org'), 'accepted', NULL, now() - interval '4 days'),
  (pg_temp.id('c2_act'), pg_temp.id('c2_pres'), 'accepted', true, now() - interval '4 days'),
  (pg_temp.id('c2_act'), pg_temp.id('c2_abs'), 'accepted', false, now() - interval '4 days');
PERFORM pg_temp.as_('c2_vue');
PERFORM pg_temp.eq('C2 le présent et l''absent ont le même nombre de sorties publiques',
  format($$SELECT (SELECT completed_activities FROM public.get_user_public_stats(%L))::text || '|' || (SELECT completed_activities FROM public.get_user_public_stats(%L))::text$$, pg_temp.id('c2_pres'), pg_temp.id('c2_abs')), '1|1');
PERFORM pg_temp.eq('C2 l''absent a bien un niveau dans ce sport',
  format($$SELECT count(*)::text FROM public.get_user_sport_levels(%L) WHERE sport_key = 'hiking'$$, pg_temp.id('c2_abs')), '1');
PERFORM pg_temp.eq('C2 la sortie de l''organisateur compte même sans présence validée',
  format($$SELECT (public.get_user_award_aggregates(%L)->>'created')$$, pg_temp.id('c2_org')), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C2 plus de déclencheur de trophée à la présence tardive',
  $$SELECT count(*)::text FROM pg_trigger WHERE tgname = 'trg_participations_late_presence_award'$$, '0');

-- ═════ C3 — Valider sa présence puis partir ne compte plus comme présent (00529) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c3_org', 'tos'); PERFORM pg_temp.user('c3_u', 'tos');
PERFORM pg_temp.put('c3_act', pg_temp.run(format($q$INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting, starts_at, duration, visibility, status, requires_presence)
  VALUES (%L, (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie C3', 'Tous niveaux', 8,
          ST_SetSRID(ST_MakePoint(-137.5, -44.5), 4326)::geography, now() + interval '2 hours', interval '3 hours', 'public', 'published', true)
  RETURNING id::text$q$, pg_temp.id('c3_org'))));
INSERT INTO public.participations (activity_id, user_id, status, created_at) VALUES (pg_temp.id('c3_act'), pg_temp.id('c3_org'), 'accepted', now() - interval '1 day');
PERFORM pg_temp.as_('c3_u');
PERFORM pg_temp.eq('C3 la participante rejoint la sortie', format($$SELECT public.join_activity(%L)$$, pg_temp.id('c3_act')), 'accepted');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET starts_at = now() - interval '10 minutes', status = 'in_progress' WHERE id = pg_temp.id('c3_act');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('c3_org');
PERFORM pg_temp.put('c3_tok', pg_temp.ok('C3 l''organisatrice affiche son QR', format($$SELECT public.create_presence_token(%L)::text$$, pg_temp.id('c3_act'))));
PERFORM pg_temp.as_('c3_u');
PERFORM pg_temp.ok('C3 la participante scanne le QR', format($$SELECT public.confirm_presence_via_token(%L)::text$$, pg_temp.get('c3_tok')));
PERFORM pg_temp.ok('C3 puis elle quitte la sortie', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('c3_act')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C3 le départ tardif est enregistré', format($$SELECT count(*)::text FROM public.late_cancels WHERE user_id = %L$$, pg_temp.id('c3_u')), '1');
PERFORM pg_temp.eq('C3 sa fiabilité baisse : la présence validée avant de partir ne compte plus',
  format($$SELECT (reliability_score < 100)::text FROM public.users WHERE id = %L$$, pg_temp.id('c3_u')), 'true');

-- ═════ C4 — Celui qui signale ne lit pas l'issue ni la note de l'admin (00530) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c4_rep', 'tos'); PERFORM pg_temp.user('c4_cible', 'tos'); PERFORM pg_temp.user('c4_adm', 'tos,admin');
PERFORM pg_temp.as_('c4_rep');
PERFORM pg_temp.put('c4_r', pg_temp.ok('C4 signalement créé', format($$SELECT public.create_report('user', %L, 'harcèlement')::text$$, pg_temp.id('c4_cible'))));
PERFORM pg_temp.as_('c4_adm');
PERFORM pg_temp.ok('C4 l''admin sanctionne avec une note privée', format($$SELECT public.moderate_report(%L, 'actioned', 'Suspendu : récidive', %L)::text$$, pg_temp.get('c4_r'), pg_temp.id('c4_cible')));
PERFORM pg_temp.eq('C4 l''admin relit le signalement', format($$SELECT status FROM public.reports WHERE id = %L$$, pg_temp.get('c4_r')), 'actioned');
PERFORM pg_temp.as_('c4_rep');
PERFORM pg_temp.eq('C4 celui qui a signalé ne voit ni l''issue ni la note', format($$SELECT count(*)::text FROM public.reports WHERE id = %L$$, pg_temp.get('c4_r')), '0');

-- ═════ C5 — Un compte suspendu ne bloque plus, n'envoie plus de fichiers, ne modifie plus son profil (00531) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c5_sus', 'tos,suspended'); PERFORM pg_temp.user('c5_ok', 'tos'); PERFORM pg_temp.user('c5_autre', 'tos');
PERFORM pg_temp.as_('c5_sus');
PERFORM pg_temp.denied('C5 un suspendu ne bloque plus personne',
  format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('c5_sus'), pg_temp.id('c5_autre')), 'row-level security');
PERFORM pg_temp.denied('C5 un suspendu n''envoie plus d''avatar',
  format($$INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('avatars', %L, %L)$$, pg_temp.get('c5_sus') || '/a.jpg', pg_temp.id('c5_sus')), 'row-level security');
PERFORM pg_temp.denied('C5 un suspendu n''envoie plus de photo pro',
  format($$INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('pro-photos', %L, %L)$$, pg_temp.get('c5_sus') || '/p.jpg', pg_temp.id('c5_sus')), 'row-level security');
PERFORM pg_temp.denied('C5 un suspendu n''envoie plus de photo de discussion',
  format($$INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('channel-photos', %L, %L)$$, pg_temp.get('c5_sus') || '/channels/c.jpg', pg_temp.id('c5_sus')), 'row-level security');
PERFORM pg_temp.eq('C5 un suspendu ne modifie plus son profil', format($$UPDATE public.users SET bio = 'encore là' WHERE id = %L$$, pg_temp.id('c5_sus')), '0');
PERFORM pg_temp.as_('c5_ok');
PERFORM pg_temp.eq('C5 un compte actif bloque toujours', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('c5_ok'), pg_temp.id('c5_autre')), '1');
PERFORM pg_temp.eq('C5 un compte actif envoie toujours son avatar',
  format($$INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('avatars', %L, %L)$$, pg_temp.get('c5_ok') || '/a.jpg', pg_temp.id('c5_ok')), '1');
PERFORM pg_temp.eq('C5 un compte actif modifie toujours son profil', format($$UPDATE public.users SET bio = 'ok' WHERE id = %L$$, pg_temp.id('c5_ok')), '1');

-- ═════ C6 — Les caractères invisibles et d'inversion du sens disparaissent (00532) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c6_u', 'tos');
PERFORM pg_temp.as_('c6_u');
PERFORM pg_temp.ok('C6 un nom avec inversion du sens et espaces invisibles est accepté…',
  format($$UPDATE public.users SET display_name = %L WHERE id = %L$$, E'Ol‮ga​ (orga)﻿', pg_temp.id('c6_u')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C6 … mais enregistré sans aucun caractère invisible',
  format($$SELECT display_name FROM public.users WHERE id = %L$$, pg_temp.id('c6_u')), 'Olga (orga)');
PERFORM pg_temp.eq('C6 le texte des notifications est nettoyé aussi',
  $$SELECT public.sanitize_notif_text(E'Ad​min ‮eton')$$, 'Admin eton');
PERFORM pg_temp.eq('C6 un texte normal (accents, emoji) est intact',
  $$SELECT private.strip_invisible('Élodie 🏔️ – sortie à l''Alpe')$$, 'Élodie 🏔️ – sortie à l''Alpe');
PERFORM pg_temp.eq('C6 un emoji composé (liant U+200D) reste intact', $$SELECT (private.strip_invisible(E'famille \U0001F468‍\U0001F469‍\U0001F467') = E'famille \U0001F468‍\U0001F469‍\U0001F467')::text$$, 'true');

-- ═════ C7 — Les adresses de prise en charge ne survivent pas à la demande (00533) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c7_org', 'tos'); PERFORM pg_temp.user('c7_d', 'tos'); PERFORM pg_temp.user('c7_p', 'tos'); PERFORM pg_temp.user('c7_q', 'tos');
PERFORM pg_temp.put('c7_act', pg_temp.run(format($q$INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting, starts_at, duration, visibility, status)
  VALUES (%L, (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie C7', 'Tous niveaux', 8,
          ST_SetSRID(ST_MakePoint(-136.5, -43.5), 4326)::geography, now() + interval '160 days', interval '3 hours', 'public', 'published')
  RETURNING id::text$q$, pg_temp.id('c7_org'))));
INSERT INTO public.participations (activity_id, user_id, status, created_at)
SELECT pg_temp.id('c7_act'), pg_temp.id(u), 'accepted', now() - interval '1 day' FROM unnest(ARRAY['c7_org', 'c7_d', 'c7_p', 'c7_q']) u;
PERFORM pg_temp.as_('c7_d');
PERFORM pg_temp.ok('C7 le conducteur propose 3 places', format($$SELECT public.set_participation_transport(%L, 'car', 3::smallint, 'Gap', NULL, 44.56, 6.08, 'Gap')::text$$, pg_temp.id('c7_act')));
PERFORM pg_temp.as_('c7_p');
PERFORM pg_temp.ok('C7 p demande une place depuis chez elle', format($$SELECT public.request_seat(%L, %L, '7 impasse des Lilas')::text$$, pg_temp.id('c7_act'), pg_temp.id('c7_d')));
PERFORM pg_temp.as_('c7_q');
PERFORM pg_temp.ok('C7 q demande une place depuis chez lui', format($$SELECT public.request_seat(%L, %L, '9 chemin du Moulin')::text$$, pg_temp.id('c7_act'), pg_temp.id('c7_d')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('c7_srp', (SELECT id::text FROM public.seat_requests WHERE requester_id = pg_temp.id('c7_p')));
PERFORM pg_temp.put('c7_srq', (SELECT id::text FROM public.seat_requests WHERE requester_id = pg_temp.id('c7_q')));
PERFORM pg_temp.as_('c7_d');
PERFORM pg_temp.ok('C7 le conducteur refuse p', format($$SELECT public.decline_seat_request(%L)::text$$, pg_temp.get('c7_srp')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C7 la demande refusée ne garde pas l''adresse', format($$SELECT coalesce(pickup_from, 'effacée') FROM public.seat_requests WHERE id = %L$$, pg_temp.get('c7_srp')), 'effacée');
PERFORM pg_temp.eq('C7 la demande en cours garde la sienne', format($$SELECT pickup_from FROM public.seat_requests WHERE id = %L$$, pg_temp.get('c7_srq')), '9 chemin du Moulin');
PERFORM pg_temp.as_('c7_q');
PERFORM pg_temp.ok('C7 q bloque le conducteur', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('c7_q'), pg_temp.id('c7_d')));
PERFORM pg_temp.as_('c7_d');
PERFORM pg_temp.eq('C7 bloqué par le passager, le conducteur ne lit plus sa demande', format($$SELECT count(*)::text FROM public.seat_requests WHERE id = %L$$, pg_temp.get('c7_srq')), '0');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C7 et l''adresse est effacée de la demande annulée par le blocage', format($$SELECT coalesce(pickup_from, 'effacée') FROM public.seat_requests WHERE id = %L$$, pg_temp.get('c7_srq')), 'effacée');

-- ═════ C8 — Aucune information sur une sortie qu'on ne peut pas voir (00535) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c8_org', 'tos'); PERFORM pg_temp.user('c8_eve', 'tos'); PERFORM pg_temp.user('c8_p', 'tos');
PERFORM pg_temp.put('c8_priv', pg_temp.run(format($q$INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting, starts_at, duration, visibility, status, requires_presence)
  VALUES (%L, (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie privée C8', 'Tous niveaux', 8,
          ST_SetSRID(ST_MakePoint(-135.5, -42.5), 4326)::geography, now() - interval '20 minutes', interval '3 hours', 'private_link', 'in_progress', true)
  RETURNING id::text$q$, pg_temp.id('c8_org'))));
INSERT INTO public.participations (activity_id, user_id, status, created_at) VALUES
  (pg_temp.id('c8_priv'), pg_temp.id('c8_org'), 'accepted', now() - interval '1 day'),
  (pg_temp.id('c8_priv'), pg_temp.id('c8_p'), 'accepted', now() - interval '1 day');
PERFORM pg_temp.as_('c8_eve');
PERFORM pg_temp.denied('C8 géo : une inconnue obtient le refus générique, pas une fenêtre horaire',
  format($$SELECT public.confirm_presence_via_geo(%L, 0, 0, now() - interval '60 minutes')::text$$, pg_temp.id('c8_priv')), '^Operation not permitted$');
PERFORM pg_temp.denied('C8 géo : même réponse pour un identifiant inventé',
  format($$SELECT public.confirm_presence_via_geo(%L, 0, 0, now() - interval '60 minutes')::text$$, gen_random_uuid()), '^Operation not permitted$');
PERFORM pg_temp.eq('C8 statut : rien pour une sortie privée qu''on ne voit pas',
  format($$SELECT coalesce(public.transition_single_activity(%L), 'rien')$$, pg_temp.id('c8_priv')), 'rien');
PERFORM pg_temp.denied('C8 signalement : refus générique sur une sortie privée qu''on ne voit pas',
  format($$SELECT public.create_report('activity', %L, 'contenu inapproprié dans cette sortie')::text$$, pg_temp.id('c8_priv')), '^Operation not permitted$');
PERFORM pg_temp.as_('c8_p');
PERFORM pg_temp.eq('C8 statut : la participante obtient le statut', format($$SELECT public.transition_single_activity(%L)$$, pg_temp.id('c8_priv')), 'in_progress');
PERFORM pg_temp.denied('C8 géo : des coordonnées hors limites sont refusées (plus de bouclage)',
  format($$SELECT public.confirm_presence_via_geo(%L, 330, 400)::text$$, pg_temp.id('c8_priv')), '^junto\.presence_too_far$');
PERFORM pg_temp.ok('C8 signalement : la participante peut signaler la sortie', format($$SELECT public.create_report('activity', %L, 'contenu inapproprié dans cette sortie')::text$$, pg_temp.id('c8_priv')));

-- ═════ C9 — La sortie d'un organisateur suspendu ne montre plus ses participants aux inconnus (00536) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c9_org', 'tos'); PERFORM pg_temp.user('c9_p', 'tos'); PERFORM pg_temp.user('c9_eve', 'tos');
PERFORM pg_temp.put('c9_act', pg_temp.run(format($q$INSERT INTO public.activities (creator_id, sport_id, title, level, max_participants, location_meeting, starts_at, duration, visibility, status)
  VALUES (%L, (SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie C9', 'Tous niveaux', 8,
          ST_SetSRID(ST_MakePoint(-134.5, -41.5), 4326)::geography, now() + interval '170 days', interval '3 hours', 'public', 'published')
  RETURNING id::text$q$, pg_temp.id('c9_org'))));
INSERT INTO public.participations (activity_id, user_id, status, created_at) VALUES
  (pg_temp.id('c9_act'), pg_temp.id('c9_org'), 'accepted', now() - interval '1 day'),
  (pg_temp.id('c9_act'), pg_temp.id('c9_p'), 'accepted', now() - interval '1 day');
PERFORM pg_temp.as_('c9_eve');
PERFORM pg_temp.eq('C9 avant : une inconnue voit les participants d''une sortie publique', format($$SELECT count(*)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('c9_act')), '2');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = now() WHERE id = pg_temp.id('c9_org');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('c9_eve');
PERFORM pg_temp.eq('C9 organisateur suspendu : plus aucun participant visible pour une inconnue', format($$SELECT count(*)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('c9_act')), '0');
PERFORM pg_temp.as_('c9_p');
PERFORM pg_temp.denied('C9 organisateur suspendu : affectations de places refusées (sortie gelée)', format($$SELECT count(*)::text FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('c9_act')), '^Operation not permitted$');

-- ═════ C10 — La modération des discussions tient (00537) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c10_a', 'tos'); PERFORM pg_temp.user('c10_b', 'tos'); PERFORM pg_temp.user('c10_c', 'tos'); PERFORM pg_temp.user('c10_adm', 'tos,admin');
-- Discussion ouverte 1 : le créateur la quitte.
PERFORM pg_temp.as_('c10_a');
PERFORM pg_temp.put('c10_ch', pg_temp.ok('C10 a crée une discussion ouverte', $$SELECT conversation_id::text FROM public.create_channel('Canal C10', -133, -40, 'Océan', 35, NULL, NULL, NULL, true)$$));
PERFORM pg_temp.as_('c10_b');
PERFORM pg_temp.ok('C10 b rejoint', format($$SELECT public.join_channel(%L)::text$$, pg_temp.get('c10_ch')));
PERFORM pg_temp.put('c10_m1', pg_temp.ok('C10 b écrit', format($$SELECT public.send_message(%L, 'message de b')::text$$, pg_temp.get('c10_ch'))));
PERFORM pg_temp.put('c10_m2', pg_temp.ok('C10 b écrit encore', format($$SELECT public.send_message(%L, 'second message de b')::text$$, pg_temp.get('c10_ch'))));
PERFORM pg_temp.as_('c10_a');
PERFORM pg_temp.ok('C10 le créateur, membre, efface un message (modération normale)', format($$SELECT public.delete_message(%L)::text$$, pg_temp.get('c10_m1')));
PERFORM pg_temp.ok('C10 le créateur quitte sa discussion', format($$SELECT public.leave_channel(%L)::text$$, pg_temp.get('c10_ch')));
PERFORM pg_temp.denied('C10 parti, il n''efface plus les messages des autres', format($$SELECT public.delete_message(%L)::text$$, pg_temp.get('c10_m2')), '^Operation not permitted$');
PERFORM pg_temp.denied('C10 parti, il ne bannit plus personne', format($$SELECT public.remove_channel_member(%L, %L)::text$$, pg_temp.get('c10_ch'), pg_temp.id('c10_b')), '^Operation not permitted$');
PERFORM pg_temp.denied('C10 parti, il ne renomme plus', format($$SELECT public.rename_channel(%L, 'Renommé')::text$$, pg_temp.get('c10_ch')), '^Operation not permitted$');
PERFORM pg_temp.denied('C10 parti, il ne ferme plus', format($$SELECT public.close_channel(%L)::text$$, pg_temp.get('c10_ch')), '^Operation not permitted$');
-- Discussion ouverte 2 : fermée par un admin, le créateur (toujours membre) n'efface plus rien.
PERFORM pg_temp.as_('c10_a');
PERFORM pg_temp.put('c10_ch2', pg_temp.ok('C10 a crée une seconde discussion', $$SELECT conversation_id::text FROM public.create_channel('Canal C10 bis', -132, -40, 'Océan', 35, NULL, NULL, NULL, true)$$));
PERFORM pg_temp.as_('c10_b');
PERFORM pg_temp.ok('C10 b rejoint la seconde', format($$SELECT public.join_channel(%L)::text$$, pg_temp.get('c10_ch2')));
PERFORM pg_temp.put('c10_m3', pg_temp.ok('C10 b y écrit', format($$SELECT public.send_message(%L, 'message signalé')::text$$, pg_temp.get('c10_ch2'))));
PERFORM pg_temp.as_('c10_adm');
PERFORM pg_temp.ok('C10 un admin ferme la discussion signalée', format($$SELECT public.admin_remove_content('channel', %L, 'signalement confirmé')::text$$, pg_temp.get('c10_ch2')));
PERFORM pg_temp.as_('c10_a');
PERFORM pg_temp.denied('C10 fermée par l''admin : le créateur n''efface plus les messages', format($$SELECT public.delete_message(%L)::text$$, pg_temp.get('c10_m3')), '^Operation not permitted$');
PERFORM pg_temp.as_('c10_b');
PERFORM pg_temp.denied('C10 fermée par l''admin : l''auteur n''efface plus son propre message', format($$SELECT public.delete_message(%L)::text$$, pg_temp.get('c10_m3')), '^Operation not permitted$');
-- Groupe retiré par la modération : l'auteur signalé ne fait pas disparaître ses messages.
PERFORM pg_temp.as_('db');
INSERT INTO public.conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at) VALUES
  ('dm', LEAST(pg_temp.id('c10_a'), pg_temp.id('c10_b')), GREATEST(pg_temp.id('c10_a'), pg_temp.id('c10_b')), pg_temp.id('c10_a'), 'active', 'profile', now(), now()),
  ('dm', LEAST(pg_temp.id('c10_a'), pg_temp.id('c10_c')), GREATEST(pg_temp.id('c10_a'), pg_temp.id('c10_c')), pg_temp.id('c10_a'), 'active', 'profile', now(), now());
PERFORM pg_temp.as_('c10_a');
PERFORM pg_temp.put('c10_g', pg_temp.ok('C10 a crée un groupe', format($$SELECT public.create_group('Groupe C10', NULL, ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('c10_b'), pg_temp.id('c10_c'))));
PERFORM pg_temp.as_('c10_b');
PERFORM pg_temp.put('c10_gm', pg_temp.ok('C10 b écrit dans le groupe', format($$SELECT public.send_message(%L, 'contenu abusif')::text$$, pg_temp.get('c10_g'))));
PERFORM pg_temp.put('c10_gm2', pg_temp.ok('C10 b écrit un autre message', format($$SELECT public.send_message(%L, 'message ordinaire')::text$$, pg_temp.get('c10_g'))));
PERFORM pg_temp.ok('C10 dans un groupe normal, b efface son propre message', format($$SELECT public.delete_message(%L)::text$$, pg_temp.get('c10_gm2')));
PERFORM pg_temp.as_('c10_adm');
PERFORM pg_temp.ok('C10 un admin retire le groupe', format($$SELECT public.admin_remove_content('group', %L, 'signalement confirmé')::text$$, pg_temp.get('c10_g')));
PERFORM pg_temp.as_('c10_b');
PERFORM pg_temp.denied('C10 groupe retiré : l''auteur ne fait plus disparaître ses messages', format($$SELECT public.delete_message(%L)::text$$, pg_temp.get('c10_gm')), '^Operation not permitted$');

-- ═════ C11 — Chaque renommage d'une vitrine approuvée parvient à l'admin (00538) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c11_pro', 'tos'); PERFORM pg_temp.user('c11_adm', 'tos,admin');
PERFORM pg_temp.as_('c11_pro');
PERFORM pg_temp.ok('C11 le pro s''inscrit', $$SELECT public.register_as_pro(p_display_name := 'Guide Alpha', p_company_name := 'SARL Test', p_real_name := 'Jean Test', p_primary_lng := -131.5, p_primary_lat := -39.5, p_primary_location_name := 'Océan')::text$$);
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_profiles SET status = 'approved' WHERE user_id = pg_temp.id('c11_pro');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('c11_pro');
PERFORM pg_temp.ok('C11 premier renommage', $$SELECT public.update_pro_profile(p_display_name := 'Guide Beta')::text$$);
PERFORM pg_temp.ok('C11 second renommage le même jour', $$SELECT public.update_pro_profile(p_display_name := 'Nom Problématique')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C11 l''admin a un seul avis, qui montre le nom ACTUEL',
  format($$SELECT string_agg(body, ' / ') FROM public.notifications WHERE user_id = %L AND type = 'pro_renamed' AND data->>'pro_id' = %L$$, pg_temp.id('c11_adm'), pg_temp.get('c11_pro')),
  'Guide Alpha → Nom Problématique');
PERFORM pg_temp.as_('c11_pro');
PERFORM pg_temp.ok('C11 retour au nom du matin', $$SELECT public.update_pro_profile(p_display_name := 'Guide Alpha')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C11 revenu au nom du matin : plus rien à signaler',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'pro_renamed' AND data->>'pro_id' = %L$$, pg_temp.id('c11_adm'), pg_temp.get('c11_pro')), '0');

-- ═════ C12 — Déplacer sa sortie retire ses demandes qui chevauchent (00539) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c12_x', 'tos'); PERFORM pg_temp.user('c12_bob', 'tos');
PERFORM pg_temp.as_('c12_bob');
PERFORM pg_temp.put('c12_b', pg_temp.ok('C12 Bob publie une sortie sur demande à J+30', $q$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie Bob', 'x', 'Tous niveaux', 8, 6.6, 44.9, NULL, NULL, now() + interval '30 days', '3 hours', 'approval')::text$q$));
PERFORM pg_temp.as_('c12_x');
PERFORM pg_temp.put('c12_a', pg_temp.ok('C12 X publie sa sortie à J+35', $q$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie X', 'x', 'Tous niveaux', 8, 6.6, 44.9, NULL, NULL, now() + interval '35 days', '3 hours', 'public')::text$q$));
PERFORM pg_temp.eq('C12 X demande à rejoindre Bob', format($$SELECT public.join_activity(%L)$$, pg_temp.get('c12_b')), 'pending');
PERFORM pg_temp.ok('C12 X déplace sa sortie sur le créneau de Bob', format($$SELECT public.update_activity(%L, p_starts_at => now() + interval '30 days 1 hour')::text$$, pg_temp.get('c12_a')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C12 la demande de X chez Bob est retirée',
  format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.get('c12_b'), pg_temp.id('c12_x')), 'withdrawn');

-- ═════ C13 — Bloquer l'organisateur retire sa propre demande, pas un refus (00541) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c13_org', 'tos'); PERFORM pg_temp.user('c13_req', 'tos');
PERFORM pg_temp.as_('c13_org');
PERFORM pg_temp.put('c13_a', pg_temp.ok('C13 l''organisatrice publie une sortie sur demande', $q$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie C13', 'x', 'Tous niveaux', 8, 6.6, 44.9, NULL, NULL, now() + interval '50 days', '3 hours', 'approval')::text$q$));
PERFORM pg_temp.as_('c13_req');
PERFORM pg_temp.eq('C13 la personne demande à rejoindre', format($$SELECT public.join_activity(%L)$$, pg_temp.get('c13_a')), 'pending');
PERFORM pg_temp.ok('C13 la personne bloque l''organisatrice', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L) RETURNING 'ok'$$, pg_temp.id('c13_req'), pg_temp.id('c13_org')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C13 sa demande est retirée, pas refusée',
  format($$SELECT status || '|' || (refused_at IS NULL)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.get('c13_a'), pg_temp.id('c13_req')), 'withdrawn|true');

-- ═════ C14 — Un jeton push ne change de compte que depuis le même appareil (00542) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c14_v', 'tos'); PERFORM pg_temp.user('c14_m', 'tos'); PERFORM pg_temp.user('c14_w', 'tos');
PERFORM pg_temp.as_('c14_v');
PERFORM pg_temp.ok('C14 la victime enregistre son téléphone', $$SELECT public.register_push_token('ExponentPushToken[c14-victime-0000000000]', 'device-victime')::text$$);
PERFORM pg_temp.as_('c14_m');
PERFORM pg_temp.ok('C14 un autre compte présente le même jeton depuis un autre appareil', $$SELECT public.register_push_token('ExponentPushToken[c14-victime-0000000000]', 'device-autre')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C14 le jeton reste à la victime',
  $$SELECT string_agg(u.display_name, ',') FROM public.push_tokens t JOIN public.users u ON u.id = t.user_id WHERE t.token = 'ExponentPushToken[c14-victime-0000000000]'$$,
  (SELECT display_name FROM public.users WHERE id = pg_temp.id('c14_v')));
PERFORM pg_temp.as_('c14_w');
PERFORM pg_temp.ok('C14 changement de compte sur le même téléphone', $$SELECT public.register_push_token('ExponentPushToken[c14-victime-0000000000]', 'device-victime')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('C14 le même appareil reprend le jeton pour le nouveau compte',
  $$SELECT string_agg(u.display_name, ',') FROM public.push_tokens t JOIN public.users u ON u.id = t.user_id WHERE t.token = 'ExponentPushToken[c14-victime-0000000000]'$$,
  (SELECT display_name FROM public.users WHERE id = pg_temp.id('c14_w')));

-- ═════ C15 — « Tu y étais ? » : présence auto-déclarée sans validation (00543) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('c15_org', 'tos'); PERFORM pg_temp.user('c15_p', 'tos'); PERFORM pg_temp.user('c15_x', 'tos');
PERFORM pg_temp.as_('c15_org');
PERFORM pg_temp.put('c15_a', pg_temp.ok('C15 l''organisatrice publie une sortie', $q$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie C15', 'x', 'Tous niveaux', 8, 6.6, 44.9, NULL, NULL, now() + interval '60 days', '2 hours', 'public')::text$q$));
PERFORM pg_temp.put('c15_v', pg_temp.ok('C15 et une sortie avec validation de présence', $q$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie C15 validée', 'x', 'Tous niveaux', 8, 6.6, 44.9, NULL, NULL, now() + interval '61 days', '2 hours', 'public')::text$q$));
PERFORM pg_temp.as_('c15_p');
PERFORM pg_temp.eq('C15 p rejoint la sortie', format($$SELECT public.join_activity(%L)$$, pg_temp.get('c15_a')), 'accepted');
PERFORM pg_temp.eq('C15 p rejoint la sortie validée', format($$SELECT public.join_activity(%L)$$, pg_temp.get('c15_v')), 'accepted');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET starts_at = now() - interval '5 hours', requires_presence = false, status = 'completed' WHERE id = pg_temp.get('c15_a')::uuid;
UPDATE public.activities SET starts_at = now() - interval '5 hours', requires_presence = true, status = 'completed' WHERE id = pg_temp.get('c15_v')::uuid;
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('C15 la fin de la sortie pose la question à chaque participant (organisatrice comprise)',
  format($$SELECT count(*)::text FROM public.notifications WHERE type = 'presence_self_declare' AND data->>'activity_id' = %L$$, pg_temp.get('c15_a')), '2');
PERFORM pg_temp.eq('C15 pas de question sur une sortie avec validation',
  format($$SELECT count(*)::text FROM public.notifications WHERE type = 'presence_self_declare' AND data->>'activity_id' = %L$$, pg_temp.get('c15_v')), '0');
PERFORM pg_temp.as_('c15_x');
PERFORM pg_temp.eq('C15 sans réponse, la sortie compte',
  format($$SELECT joined_activities::text FROM public.get_user_public_stats(%L)$$, pg_temp.id('c15_p')), '2');
PERFORM pg_temp.denied('C15 un non-participant ne déclare rien', format($$SELECT public.declare_my_presence(%L, true)::text$$, pg_temp.get('c15_a')), '^Operation not permitted$');
PERFORM pg_temp.as_('c15_p');
PERFORM pg_temp.denied('C15 refusé sur une sortie avec validation', format($$SELECT public.declare_my_presence(%L, false)::text$$, pg_temp.get('c15_v')), '^Operation not permitted$');
PERFORM pg_temp.ok('C15 p répond « non »', format($$SELECT public.declare_my_presence(%L, false)::text$$, pg_temp.get('c15_a')));
PERFORM pg_temp.eq('C15 p lit sa propre réponse', format($$SELECT self_presence FROM public.participations WHERE activity_id = %L AND user_id = auth.uid()$$, pg_temp.get('c15_a')), 'no');
PERFORM pg_temp.as_('c15_x');
PERFORM pg_temp.eq('C15 « non » : la sortie ne compte plus',
  format($$SELECT joined_activities::text FROM public.get_user_public_stats(%L)$$, pg_temp.id('c15_p')), '1');
PERFORM pg_temp.eq('C15 « non » : retirée des trophées par sport',
  format($$SELECT coalesce(sum(count), 0)::text FROM public.get_user_trophies(%L) WHERE category = 'sport'$$, pg_temp.id('c15_p')), '1');
PERFORM pg_temp.as_('c15_p');
PERFORM pg_temp.ok('C15 p change d''avis : « oui »', format($$SELECT public.declare_my_presence(%L, true)::text$$, pg_temp.get('c15_a')));
PERFORM pg_temp.as_('c15_x');
PERFORM pg_temp.eq('C15 « oui » : la sortie compte', format($$SELECT joined_activities::text FROM public.get_user_public_stats(%L)$$, pg_temp.id('c15_p')), '2');
PERFORM pg_temp.as_('c15_org');
PERFORM pg_temp.ok('C15 l''organisatrice dit que la sortie n''a pas eu lieu pour elle', format($$SELECT public.declare_my_presence(%L, false)::text$$, pg_temp.get('c15_a')));
PERFORM pg_temp.as_('c15_x');
PERFORM pg_temp.eq('C15 sa sortie créée ne compte plus',
  format($$SELECT count::text FROM public.get_user_trophies(%L) WHERE category = 'created'$$, pg_temp.id('c15_org')), '1');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET starts_at = now() - interval '60 hours' WHERE id = pg_temp.get('c15_a')::uuid;
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('c15_p');
PERFORM pg_temp.denied('C15 après 48 h, la réponse est figée', format($$SELECT public.declare_my_presence(%L, false)::text$$, pg_temp.get('c15_a')), 'junto\.presence_declare_closed');
PERFORM pg_temp.denied('C15 les votes restent fermés sur une sortie sans validation',
  format($$SELECT public.give_reputation_badge(%L, %L, 'punctual')::text$$, pg_temp.id('c15_org'), pg_temp.get('c15_a')), 'junto\.votes_need_presence|Operation not permitted');
