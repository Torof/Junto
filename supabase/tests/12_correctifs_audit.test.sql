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
