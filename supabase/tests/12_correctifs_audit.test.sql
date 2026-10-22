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
