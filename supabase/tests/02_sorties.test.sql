-- Domaine 2 — sorties et logistique (cycle de vie, participations, invitations,
-- covoiturage, matériel, alertes, accès direct aux tables et vues).
--
-- Fixtures : les sorties sont créées par create_activity (coordonnées en plein
-- Atlantique pour ne réveiller aucune alerte réelle), puis ajustées en `db`
-- (bypass_lock) quand il faut une date passée ou un statut terminé.

EXECUTE $p$CREATE FUNCTION pg_temp.sorties_ca(p_vis text, p_max int, p_when text DEFAULT '2 days') RETURNS text
  LANGUAGE sql AS $b$
  SELECT format($q$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test', 'description', 'Tous niveaux', %s, -30.0, 40.0, NULL, NULL, now() + interval %L, '3 hours', %L)::text$q$,
    coalesce(p_max::text, 'NULL'), p_when, p_vis)
$b$$p$;

-- Accès (en tant que db) à l'identifiant d'une participation.
EXECUTE $p$CREATE FUNCTION pg_temp.sorties_pid(p_act text, p_user text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT id::text FROM public.participations WHERE activity_id = pg_temp.id(p_act) AND user_id = pg_temp.id(p_user)
$b$$p$;

EXECUTE $p$CREATE FUNCTION pg_temp.sorties_sr(p_act text, p_req text, p_drv text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$
  SELECT id::text FROM public.seat_requests WHERE activity_id = pg_temp.id(p_act) AND requester_id = pg_temp.id(p_req) AND driver_id = pg_temp.id(p_drv)
$b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.user('alice', 'tos');   -- organisatrice principale
PERFORM pg_temp.user('bob', 'tos');
PERFORM pg_temp.user('carl', 'tos');    -- organisateur des sorties « datées »
PERFORM pg_temp.user('dave', 'tos');    -- conducteur
PERFORM pg_temp.user('gina', 'tos');    -- seconde conductrice
PERFORM pg_temp.user('erin', 'tos');    -- passagère
PERFORM pg_temp.user('hank', 'tos');    -- passager
PERFORM pg_temp.user('ivy', 'tos');     -- passagère (contact refusé)
PERFORM pg_temp.user('gus', 'tos');
PERFORM pg_temp.user('frank', 'tos');   -- inconnu
PERFORM pg_temp.user('bad', 'tos');     -- bloqué par alice
PERFORM pg_temp.user('ivan', 'tos');    -- contact d'alice
PERFORM pg_temp.user('jude', 'tos');    -- contact d'alice
PERFORM pg_temp.user('kim', 'tos');
PERFORM pg_temp.user('olga', 'tos');    -- organisatrice bientôt suspendue
PERFORM pg_temp.user('loop', 'tos');
PERFORM pg_temp.user('pry', 'tos');     -- curieux (sortie privée)
PERFORM pg_temp.user('spam', 'tos');
PERFORM pg_temp.user('sam', 'tos,suspended');
PERFORM pg_temp.user('demo1', 'tos,demo');

-- ═════ create_activity ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne crée pas de sortie', pg_temp.sorties_ca('public', 5));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne crée pas de sortie', pg_temp.sorties_ca('public', 5));

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.put('pub',   pg_temp.ok('alice crée une sortie publique (max 3)', pg_temp.sorties_ca('public', 3)));
PERFORM pg_temp.put('appr',  pg_temp.ok('alice crée une sortie sur validation', pg_temp.sorties_ca('approval', 5)));
PERFORM pg_temp.put('priv',  pg_temp.ok('alice crée une sortie privée par lien', pg_temp.sorties_ca('private_link', 6)));
PERFORM pg_temp.put('car',   pg_temp.ok('alice crée une sortie covoiturage', pg_temp.sorties_ca('public', 12)));
PERFORM pg_temp.put('cxl',   pg_temp.ok('alice crée une sortie à annuler', pg_temp.sorties_ca('public', 5)));
PERFORM pg_temp.put('open',  pg_temp.ok('alice crée une sortie ouverte (sans max)', pg_temp.sorties_ca('public', NULL)));
PERFORM pg_temp.eq('la créatrice est participante acceptée', format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('pub'), pg_temp.id('alice')), 'accepted');
PERFORM pg_temp.denied('date passée refusée',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test', 'x', 'Tous niveaux', 5, -30.0, 40.0, NULL, NULL, now() - interval '1 hour')::text$$, 'junto.date_in_past');
PERFORM pg_temp.denied('date à plus de 6 mois refusée',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test', 'x', 'Tous niveaux', 5, -30.0, 40.0, NULL, NULL, now() + interval '7 months')::text$$, 'junto.date_too_far');
PERFORM pg_temp.denied('max_participants hors bornes refusé',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test', 'x', 'Tous niveaux', 1, -30.0, 40.0, NULL, NULL, now() + interval '2 days')::text$$, 'junto.participants_range');
PERFORM pg_temp.denied('titre trop court refusé',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), '  ab ', 'x', 'Tous niveaux', 5, -30.0, 40.0, NULL, NULL, now() + interval '2 days')::text$$, 'junto.title_too_short');
PERFORM pg_temp.denied('visibilité inconnue refusée',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test', 'x', 'Tous niveaux', 5, -30.0, 40.0, NULL, NULL, now() + interval '2 days', '2 hours', 'secret')::text$$);
PERFORM pg_temp.denied('trace GeoJSON invalide refusée',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test', 'x', 'Tous niveaux', 5, -30.0, 40.0, NULL, NULL, now() + interval '2 days', '2 hours', 'public', true, NULL, NULL, NULL, NULL, NULL, NULL, '{"type":"Point","coordinates":[1,2]}'::jsonb)::text$$, 'junto.trace_geojson_invalid');
PERFORM pg_temp.denied('niveau démesuré refusé (AC-3)',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test', 'x', repeat('n', 5000), 5, -30.0, 40.0, NULL, NULL, now() + interval '2 days', '2 hours', 'private_link')::text$$, '.', 'AC-3');

-- Limite journalière (10 / jour).
PERFORM pg_temp.as_('spam');
DECLARE i int;
BEGIN
  FOR i IN 1..10 LOOP
    EXECUTE pg_temp.sorties_ca('private_link', 5);
  END LOOP;
EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.put('spam_err', SQLERRM);
END;
PERFORM pg_temp.eq('10 sorties créées dans la journée sans erreur', $$SELECT coalesce(pg_temp.get('spam_err'), 'none')$$, 'none');
PERFORM pg_temp.denied('la 11e sortie du jour est refusée', pg_temp.sorties_ca('private_link', 5), 'junto.limit_daily');

-- ═════ join_activity ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne rejoint pas', format($$SELECT public.join_activity(%L)$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne rejoint pas', format($$SELECT public.join_activity(%L)$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('la créatrice ne rejoint pas sa propre sortie', format($$SELECT public.join_activity(%L)$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('bob rejoint la sortie publique', format($$SELECT public.join_activity(%L)$$, pg_temp.id('pub')), 'accepted');
-- DB-AC-1 : `IF v_existing IS NOT NULL` sur un RECORD est faux dès qu'un champ est NULL (refused_at) :
-- la branche « ligne existante » n'est jamais prise → INSERT → violation d'unicité brute.
PERFORM pg_temp.denied('bob ne rejoint pas deux fois (erreur codée)', format($$SELECT public.join_activity(%L)$$, pg_temp.id('pub')), 'junto.already_joined', 'DB-AC-1');
PERFORM pg_temp.as_('carl');
PERFORM pg_temp.eq('carl rejoint (sortie pleine à 3)', format($$SELECT public.join_activity(%L)$$, pg_temp.id('pub')), 'accepted');
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('sortie pleine : frank refusé', format($$SELECT public.join_activity(%L)$$, pg_temp.id('pub')), 'junto.activity_full');

-- Blocage : alice bloque « bad ».
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('alice'), pg_temp.id('bad'));
PERFORM pg_temp.as_('bad');
PERFORM pg_temp.denied('une personne bloquée par l''organisatrice ne rejoint pas', format($$SELECT public.join_activity(%L)$$, pg_temp.id('open')));
PERFORM pg_temp.eq('blocage unidirectionnel : la personne bloquée voit encore la sortie sur la carte',
  format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('open')), '1');

-- Sortie privée par lien : rejoindre avec le seul identifiant (IX-1 / AC-8).
PERFORM pg_temp.as_('pry');
PERFORM pg_temp.denied('rejoindre une sortie privée par son seul identifiant est refusé',
  format($$SELECT public.join_activity(%L)$$, pg_temp.id('priv')), 'Operation not permitted', 'IX-1');

-- Boucle inscription / désinscription (AB-1).
PERFORM pg_temp.as_('loop');
DECLARE i int;
BEGIN
  FOR i IN 1..12 LOOP
    PERFORM public.join_activity(pg_temp.id('open'));
    PERFORM public.leave_activity(pg_temp.id('open'), 'motif');
  END LOOP;
EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.put('ab1_err', SQLERRM);
END;
PERFORM pg_temp.eq('12 inscriptions / désinscriptions en boucle sont freinées par une limite',
  $$SELECT (coalesce(pg_temp.get('ab1_err'), '') ~ 'junto\.')::text$$, 'true', 'AB-1');

-- ═════ Rideau démo ═════
PERFORM pg_temp.as_('demo1');
PERFORM pg_temp.put('demo', pg_temp.ok('fixture : sortie du compte démo', pg_temp.sorties_ca('public', 5)));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET is_demo = true WHERE id = pg_temp.id('demo');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.eq('sortie démo absente de la vue carte', format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('demo')), '0');
PERFORM pg_temp.eq('sortie démo illisible en direct', format($$SELECT count(*)::text FROM public.activities WHERE id = %L$$, pg_temp.id('demo')), '0');
PERFORM pg_temp.eq('sortie démo absente du détail', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('demo')), '0');
PERFORM pg_temp.eq('participants d''une sortie démo non listés', format($$SELECT count(*)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('demo')), '0');
PERFORM pg_temp.denied('résumé transport d''une sortie démo refusé', format($$SELECT count(*)::text FROM public.get_transport_summary(%L)$$, pg_temp.id('demo')));
PERFORM pg_temp.denied('on ne rejoint pas une sortie démo', format($$SELECT public.join_activity(%L)$$, pg_temp.id('demo')));
PERFORM pg_temp.as_('demo1');
PERFORM pg_temp.denied('pas d''invitation réelle depuis une sortie démo',
  format($$SELECT public.send_activity_invitations(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('demo'), pg_temp.id('frank')));

-- ═════ Lectures : détail, participants, vues ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne lit pas le détail', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('pub')));
PERFORM pg_temp.denied('anon ne lit pas les participants', format($$SELECT count(*)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('pub')));
PERFORM pg_temp.eq('anon ne voit pas une sortie privée dans la vue carte', format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('priv')), '0');
PERFORM pg_temp.eq('anon ne lit pas la table activities', $$SELECT count(*)::text FROM public.activities$$, '0');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne lit pas le détail', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('pub')));
PERFORM pg_temp.eq('un compte suspendu ne lit pas les participants', format($$SELECT count(*)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('pub')), '0');
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.eq('un inconnu lit le détail d''une sortie publique', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('pub')), '1');
PERFORM pg_temp.eq('un inconnu ne lit pas le détail d''une sortie privée', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('priv')), '0');
PERFORM pg_temp.eq('un inconnu ne liste pas les participants d''une sortie privée', format($$SELECT count(*)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('priv')), '0');
PERFORM pg_temp.eq('sortie privée absente de la vue carte pour un inconnu', format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('priv')), '0');
PERFORM pg_temp.eq('sortie publique présente dans la vue carte', format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('pub')), '1');
PERFORM pg_temp.eq('un inconnu ne voit pas les sorties d''alice dans my_activities', format($$SELECT count(*)::text FROM public.my_activities WHERE id = %L$$, pg_temp.id('pub')), '0');
PERFORM pg_temp.eq('un inconnu ne lit pas les participations des autres', format($$SELECT count(*)::text FROM public.participations WHERE activity_id = %L$$, pg_temp.id('pub')), '0');
PERFORM pg_temp.eq('le jeton d''invitation n''est pas lisible par un inconnu',
  format($$SELECT count(*)::text FROM public.activities WHERE id = %L AND invite_token IS NOT NULL$$, pg_temp.id('pub')), '0', 'AC-8');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('alice voit sa sortie privée dans le détail', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('priv')), '1');
PERFORM pg_temp.eq('alice voit sa sortie dans my_activities', format($$SELECT count(*)::text FROM public.my_activities WHERE id = %L$$, pg_temp.id('pub')), '1');
PERFORM pg_temp.eq('alice voit les 3 participants', format($$SELECT count(*)::text FROM public.get_activity_participants(%L)$$, pg_temp.id('pub')), '3');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('bob voit la sortie dans my_joined_activities', format($$SELECT count(*)::text FROM public.my_joined_activities WHERE id = %L$$, pg_temp.id('pub')), '1');
-- Blocage côté lecteur : frank bloque alice → il ne voit plus le détail.
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('frank'), pg_temp.id('alice'));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.eq('qui a bloqué l''organisatrice ne voit plus sa sortie', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('pub')), '0');
PERFORM pg_temp.as_('db');
DELETE FROM public.blocked_users WHERE blocker_id = pg_temp.id('frank') AND blocked_id = pg_temp.id('alice');

-- ═════ Jeton d'invitation ═════
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.put('tok', pg_temp.ok('alice récupère le jeton de sa sortie privée', format($$SELECT public.get_own_invite_token(%L)::text$$, pg_temp.id('priv'))));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu ne récupère pas le jeton', format($$SELECT public.get_own_invite_token(%L)::text$$, pg_temp.id('priv')));
PERFORM pg_temp.eq('le jeton ouvre la sortie privée', format($$SELECT id::text FROM public.get_activity_by_invite_token(%L)$$, pg_temp.id('tok')), pg_temp.get('priv'));
PERFORM pg_temp.eq('un jeton inconnu n''ouvre rien', format($$SELECT count(*)::text FROM public.get_activity_by_invite_token(%L)$$, gen_random_uuid()), '0');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne résout pas un jeton', format($$SELECT count(*)::text FROM public.get_activity_by_invite_token(%L)$$, pg_temp.id('tok')));
PERFORM pg_temp.denied('anon ne récupère pas de jeton', format($$SELECT public.get_own_invite_token(%L)::text$$, pg_temp.id('priv')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne résout pas un jeton', format($$SELECT count(*)::text FROM public.get_activity_by_invite_token(%L)$$, pg_temp.id('tok')));

-- ═════ update_activity ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne modifie pas', format($$SELECT public.update_activity(%L, 'Titre pirate')::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne modifie pas', format($$SELECT public.update_activity(%L, 'Titre pirate')::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('un participant ne modifie pas la sortie d''autrui', format($$SELECT public.update_activity(%L, 'Titre pirate')::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice modifie le titre', format($$SELECT public.update_activity(%L, 'Nouveau titre')::text$$, pg_temp.id('pub')));
PERFORM pg_temp.denied('titre trop court refusé à la modification', format($$SELECT public.update_activity(%L, 'ab')::text$$, pg_temp.id('pub')), 'junto.title_too_short');
PERFORM pg_temp.denied('participants hors bornes refusés à la modification', format($$SELECT public.update_activity(%L, p_max_participants => 60)::text$$, pg_temp.id('cxl')), 'junto.participants_range');
PERFORM pg_temp.denied('date passée refusée à la modification', format($$SELECT public.update_activity(%L, p_starts_at => now() - interval '1 day')::text$$, pg_temp.id('cxl')), 'junto.date_in_past');
PERFORM pg_temp.denied('date à plus de 6 mois refusée à la modification', format($$SELECT public.update_activity(%L, p_starts_at => now() + interval '8 months')::text$$, pg_temp.id('cxl')), 'junto.date_too_far');
PERFORM pg_temp.denied('visibilité inconnue refusée à la modification', format($$SELECT public.update_activity(%L, p_visibility => 'secret')::text$$, pg_temp.id('cxl')));
-- Champs gelés dès qu'un participant a rejoint.
PERFORM pg_temp.ok('alice tente de déplacer la date après inscriptions', format($$SELECT public.update_activity(%L, p_starts_at => now() + interval '5 days', p_max_participants => 10, p_visibility => 'private_link')::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('date gelée après inscription', format($$SELECT (starts_at = now() + interval '2 days')::text FROM public.activities WHERE id = %L$$, pg_temp.id('pub')), 'true');
PERFORM pg_temp.eq('capacité gelée après inscription', format($$SELECT max_participants::text FROM public.activities WHERE id = %L$$, pg_temp.id('pub')), '3');
PERFORM pg_temp.eq('visibilité gelée après inscription', format($$SELECT visibility FROM public.activities WHERE id = %L$$, pg_temp.id('pub')), 'public');
-- AC-10 : modifications en boucle (une notification par participant à chaque fois).
PERFORM pg_temp.as_('alice');
DECLARE i int;
BEGIN
  FOR i IN 1..30 LOOP
    PERFORM public.update_activity(pg_temp.id('pub'), 'Titre numero ' || i);
  END LOOP;
EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.put('ac10_err', SQLERRM);
END;
PERFORM pg_temp.eq('30 modifications en boucle sont freinées', $$SELECT (pg_temp.get('ac10_err') IS NOT NULL)::text$$, 'true', 'AC-10');

-- ═════ update_activity_trace ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne change pas la trace', format($$SELECT public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[6,44],[6.1,44.1]]}'::jsonb)::text$$, pg_temp.id('cxl')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne change pas la trace', format($$SELECT public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[6,44],[6.1,44.1]]}'::jsonb)::text$$, pg_temp.id('cxl')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('un participant ne change pas la trace d''autrui', format($$SELECT public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[6,44],[6.1,44.1]]}'::jsonb)::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice pose une trace valide', format($$SELECT public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[6,44],[6.1,44.1]]}'::jsonb)::text$$, pg_temp.id('cxl')));
PERFORM pg_temp.denied('trace invalide refusée', format($$SELECT public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[600,44]]}'::jsonb)::text$$, pg_temp.id('cxl')), 'junto.trace_geojson_invalid');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la distance est déduite de la trace', format($$SELECT (distance_km > 0)::text FROM public.activities WHERE id = %L$$, pg_temp.id('cxl')), 'true');

-- ═════ Validation : accept / refuse / remove ═════
PERFORM pg_temp.as_('carl');
PERFORM pg_temp.eq('carl demande à rejoindre la sortie sur validation', format($$SELECT public.join_activity(%L)$$, pg_temp.id('appr')), 'pending');
PERFORM pg_temp.as_('gus');
PERFORM pg_temp.eq('gus demande aussi', format($$SELECT public.join_activity(%L)$$, pg_temp.id('appr')), 'pending');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('p_carl', pg_temp.sorties_pid('appr', 'carl'));
PERFORM pg_temp.put('p_gus', pg_temp.sorties_pid('appr', 'gus'));
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon n''accepte pas une demande', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu n''accepte pas une demande', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu n''accepte pas la demande d''autrui', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.denied('un inconnu ne refuse pas la demande d''autrui', format($$SELECT public.refuse_participation(%L)::text$$, pg_temp.id('p_gus')));
PERFORM pg_temp.as_('carl');
PERFORM pg_temp.denied('on ne s''accepte pas soi-même', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice accepte carl', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.denied('on n''accepte pas deux fois', format($$SELECT public.accept_participation(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.ok('alice refuse gus', format($$SELECT public.refuse_participation(%L)::text$$, pg_temp.id('p_gus')));
PERFORM pg_temp.as_('gus');
PERFORM pg_temp.denied('refusé : pas de nouvelle demande avant 24 h', format($$SELECT public.join_activity(%L)$$, pg_temp.id('appr')), 'junto.refuse_cooldown');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('carl est accepté', format($$SELECT status FROM public.participations WHERE id = %L$$, pg_temp.id('p_carl')), 'accepted');
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu ne retire pas un participant', format($$SELECT public.remove_participant(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne retire pas un participant', format($$SELECT public.remove_participant(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne retire pas un participant', format($$SELECT public.remove_participant(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('la créatrice ne se retire pas elle-même', format($$SELECT public.remove_participant(%L)::text$$, pg_temp.sorties_pid('appr', 'alice')));
PERFORM pg_temp.ok('alice retire carl', format($$SELECT public.remove_participant(%L)::text$$, pg_temp.id('p_carl')));
PERFORM pg_temp.as_('carl');
PERFORM pg_temp.denied('un participant retiré ne revient pas', format($$SELECT public.join_activity(%L)$$, pg_temp.id('appr')));

-- ═════ leave_activity ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne quitte rien', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne quitte pas', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un non-participant ne quitte pas', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('la créatrice ne quitte pas sa sortie', format($$SELECT public.leave_activity(%L)::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob quitte la sortie', format($$SELECT public.leave_activity(%L, 'empêchement')::text$$, pg_temp.id('pub')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('bob est marqué parti', format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('pub'), pg_temp.id('bob')), 'withdrawn');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('un participant parti peut revenir', format($$SELECT public.join_activity(%L)$$, pg_temp.id('pub')), 'accepted', 'DB-AC-1');

-- ═════ Invitations ═════
PERFORM pg_temp.as_('db');
INSERT INTO public.conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
VALUES (least(pg_temp.id('alice'), pg_temp.id('ivan')), greatest(pg_temp.id('alice'), pg_temp.id('ivan')), pg_temp.id('alice'), 'active', 'profile', now(), now()),
       (least(pg_temp.id('alice'), pg_temp.id('jude')), greatest(pg_temp.id('alice'), pg_temp.id('jude')), pg_temp.id('alice'), 'active', 'profile', now(), now());
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon n''invite pas', format($$SELECT public.send_activity_invitations(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('priv'), pg_temp.id('ivan')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu n''invite pas', format($$SELECT public.send_activity_invitations(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('priv'), pg_temp.id('ivan')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu n''invite pas sur la sortie d''autrui', format($$SELECT public.send_activity_invitations(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('priv'), pg_temp.id('ivan')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('plus de 20 invités d''un coup refusé',
  format($$SELECT public.send_activity_invitations(%L, (SELECT array_agg(gen_random_uuid()) FROM generate_series(1, 21)))::text$$, pg_temp.id('priv')), 'junto.invite_cap');
PERFORM pg_temp.ok('alice invite ivan et jude', format($$SELECT public.send_activity_invitations(%L, ARRAY[%L, %L]::uuid[], 'viens !')::text$$, pg_temp.id('priv'), pg_temp.id('ivan'), pg_temp.id('jude')));
PERFORM pg_temp.ok('alice tente d''inviter un inconnu (non contact)', format($$SELECT public.send_activity_invitations(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('priv'), pg_temp.id('kim')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('ivan est invité', format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('priv'), pg_temp.id('ivan')), 'invited');
PERFORM pg_temp.eq('un non-contact n''est pas invité', format($$SELECT count(*)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('priv'), pg_temp.id('kim')), '0');
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('accepter sans invitation est refusé', format($$SELECT public.accept_activity_invitation(%L)::text$$, pg_temp.id('priv')));
PERFORM pg_temp.as_('ivan');
PERFORM pg_temp.ok('ivan accepte l''invitation', format($$SELECT public.accept_activity_invitation(%L)::text$$, pg_temp.id('priv')));
PERFORM pg_temp.denied('on n''accepte pas deux fois une invitation', format($$SELECT public.accept_activity_invitation(%L)::text$$, pg_temp.id('priv')));
PERFORM pg_temp.as_('jude');
PERFORM pg_temp.ok('jude décline l''invitation', format($$SELECT public.decline_activity_invitation(%L)::text$$, pg_temp.id('priv')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('ivan est accepté', format($$SELECT status FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('priv'), pg_temp.id('ivan')), 'accepted');
PERFORM pg_temp.eq('l''invitation déclinée disparaît', format($$SELECT count(*)::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('priv'), pg_temp.id('jude')), '0');
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu n''accepte pas d''invitation', format($$SELECT public.accept_activity_invitation(%L)::text$$, pg_temp.id('priv')));
PERFORM pg_temp.denied('un compte suspendu ne décline pas', format($$SELECT public.decline_activity_invitation(%L)::text$$, pg_temp.id('priv')));
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon n''accepte pas d''invitation', format($$SELECT public.accept_activity_invitation(%L)::text$$, pg_temp.id('priv')));

-- invite_users_to_activity (partage par demande de contact)
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne partage pas une sortie', format($$SELECT public.invite_users_to_activity(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('pub'), pg_temp.id('kim')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne partage pas une sortie', format($$SELECT public.invite_users_to_activity(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('pub'), pg_temp.id('kim')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu ne partage pas une sortie privée', format($$SELECT public.invite_users_to_activity(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('priv'), pg_temp.id('kim')));
PERFORM pg_temp.eq('un inconnu partage une sortie publique (demande de contact)', format($$SELECT public.invite_users_to_activity(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('pub'), pg_temp.id('kim')), '1');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le partage crée une demande en attente, pas une conversation active',
  format($$SELECT status FROM public.conversations WHERE user_1 = least(%L::uuid, %L::uuid) AND user_2 = greatest(%L::uuid, %L::uuid)$$,
    pg_temp.id('frank'), pg_temp.id('kim'), pg_temp.id('frank'), pg_temp.id('kim')), 'pending_request');

-- ═════ cancel_activity ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon n''annule pas', format($$SELECT public.cancel_activity(%L, 'météo')::text$$, pg_temp.id('cxl')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu n''annule pas', format($$SELECT public.cancel_activity(%L, 'météo')::text$$, pg_temp.id('cxl')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('un tiers n''annule pas la sortie d''autrui', format($$SELECT public.cancel_activity(%L, 'météo')::text$$, pg_temp.id('cxl')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('motif d''annulation trop court refusé', format($$SELECT public.cancel_activity(%L, 'x')::text$$, pg_temp.id('cxl')), 'junto.cancel_reason_invalid');
PERFORM pg_temp.ok('alice annule sa sortie', format($$SELECT public.cancel_activity(%L, 'mauvaise météo')::text$$, pg_temp.id('cxl')));
PERFORM pg_temp.denied('on n''annule pas deux fois', format($$SELECT public.cancel_activity(%L, 'mauvaise météo')::text$$, pg_temp.id('cxl')));
PERFORM pg_temp.denied('une sortie annulée ne se modifie plus', format($$SELECT public.update_activity(%L, 'Retour en grâce')::text$$, pg_temp.id('cxl')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la sortie est annulée', format($$SELECT status FROM public.activities WHERE id = %L$$, pg_temp.id('cxl')), 'cancelled');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('on ne rejoint pas une sortie annulée', format($$SELECT public.join_activity(%L)$$, pg_temp.id('cxl')));

-- ═════ Covoiturage ═════
PERFORM pg_temp.as_('dave');  PERFORM pg_temp.ok('dave rejoint la sortie covoiturage', format($$SELECT public.join_activity(%L)$$, pg_temp.id('car')));
PERFORM pg_temp.as_('gina');  PERFORM pg_temp.ok('gina rejoint la sortie covoiturage', format($$SELECT public.join_activity(%L)$$, pg_temp.id('car')));
PERFORM pg_temp.as_('erin');  PERFORM pg_temp.ok('erin rejoint la sortie covoiturage', format($$SELECT public.join_activity(%L)$$, pg_temp.id('car')));
PERFORM pg_temp.as_('hank');  PERFORM pg_temp.ok('hank rejoint la sortie covoiturage', format($$SELECT public.join_activity(%L)$$, pg_temp.id('car')));
PERFORM pg_temp.as_('ivy');   PERFORM pg_temp.ok('ivy rejoint la sortie covoiturage', format($$SELECT public.join_activity(%L)$$, pg_temp.id('car')));

-- set_participation_transport
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne déclare pas de transport', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint)::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne déclare pas de transport', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint)::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un non-participant ne déclare pas de transport', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint)::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.denied('type de transport inconnu refusé', format($$SELECT public.set_participation_transport(%L, 'rocket')::text$$, pg_temp.id('car')));
PERFORM pg_temp.denied('heure de départ hors fenêtre refusée', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint, 'Gap', now() + interval '10 days')::text$$, pg_temp.id('car')));
PERFORM pg_temp.denied('latitude de départ hors bornes refusée', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint, 'Gap', NULL, 123.0, 6.0)::text$$, pg_temp.id('car')));
PERFORM pg_temp.ok('dave propose 2 places depuis Gap', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint, 'Gap', NULL, 44.56, 6.08)::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('gina');
PERFORM pg_temp.ok('gina propose 2 places', format($$SELECT public.set_participation_transport(%L, 'car', 2::smallint, 'Embrun', NULL, 44.56, 6.49)::text$$, pg_temp.id('car')));

-- get_transport_summary
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne lit pas le résumé transport', format($$SELECT count(*)::text FROM public.get_transport_summary(%L)$$, pg_temp.id('car')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne lit pas le résumé transport', format($$SELECT count(*)::text FROM public.get_transport_summary(%L)$$, pg_temp.id('car')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu ne lit pas le résumé transport d''une sortie privée', format($$SELECT count(*)::text FROM public.get_transport_summary(%L)$$, pg_temp.id('priv')));
PERFORM pg_temp.as_('hank');
PERFORM pg_temp.eq('un participant lit le résumé : 4 places en voiture', format($$SELECT total_seats::text FROM public.get_transport_summary(%L) WHERE transport_type = 'car'$$, pg_temp.id('car')), '4');
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.eq('les coordonnées de départ d''un conducteur ne sont pas lisibles par un inconnu',
  format($$SELECT count(*)::text FROM public.get_activity_participants(%L) WHERE transport_from_lat IS NOT NULL$$, pg_temp.id('car')), '0', 'AC-2');

-- request_seat
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne demande pas de place', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('dave')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne demande pas de place', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('dave')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un non-participant ne demande pas de place', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('dave')));
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.denied('on ne se demande pas une place à soi-même', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('dave')));
PERFORM pg_temp.as_('erin');
PERFORM pg_temp.denied('pas de place chez un participant sans voiture', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('hank')), 'junto.no_seats_available');
PERFORM pg_temp.denied('heure de prise en charge hors fenêtre refusée', format($$SELECT public.request_seat(%L, %L, 'Gap', NULL, now() + interval '20 days')::text$$, pg_temp.id('car'), pg_temp.id('dave')), 'junto.pickup_out_of_window');
PERFORM pg_temp.ok('erin demande une place à dave', format($$SELECT public.request_seat(%L, %L, 'Gap gare', 'note privée pour dave')::text$$, pg_temp.id('car'), pg_temp.id('dave')));
-- DB-AC-2 : même piège `v_existing IS NOT NULL` sur un RECORD (colonnes NULL) → la branche
-- « demande existante » est morte : erreur générique au lieu du code, et pas de renvoi possible.
PERFORM pg_temp.denied('pas de seconde demande en attente au même conducteur (erreur codée)', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('dave')), 'junto.seat_already_requested', 'DB-AC-2');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('sr_erin', pg_temp.sorties_sr('car', 'erin', 'dave'));
PERFORM pg_temp.eq('la demande est en attente', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.id('sr_erin')), 'pending');

-- accept_seat_request
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon n''accepte pas de demande de place', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu n''accepte pas de demande de place', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu n''accepte pas la demande d''autrui', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.denied('un inconnu ne décline pas la demande d''autrui', format($$SELECT public.decline_seat_request(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('erin');
PERFORM pg_temp.denied('la passagère n''accepte pas sa propre demande', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('l''organisatrice n''accepte pas à la place du conducteur', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.ok('dave accepte erin', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.denied('on n''accepte pas deux fois', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('une place de moins chez dave', format($$SELECT transport_seats::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('car'), pg_temp.id('dave')), '1');

-- Un conducteur avec passager ne peut pas abandonner sa voiture.
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.denied('un conducteur avec passager ne passe pas à vélo', format($$SELECT public.set_participation_transport(%L, 'bike')::text$$, pg_temp.id('car')));

-- get_activity_seat_assignments
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne lit pas les affectations', format($$SELECT count(*)::text FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('car')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne lit pas les affectations', format($$SELECT count(*)::text FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('car')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu ne lit pas les affectations', format($$SELECT count(*)::text FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('car')));
PERFORM pg_temp.eq('un inconnu ne lit pas les demandes de place en direct', format($$SELECT count(*)::text FROM public.seat_requests WHERE activity_id = %L$$, pg_temp.id('car')), '0');
PERFORM pg_temp.as_('hank');
PERFORM pg_temp.eq('un participant voit l''affectation erin → dave', format($$SELECT count(*)::text FROM public.get_activity_seat_assignments(%L)$$, pg_temp.id('car')), '1');
PERFORM pg_temp.eq('la note privée d''une demande de place n''est pas lisible par les co-participants',
  format($$SELECT count(*)::text FROM public.seat_requests WHERE id = %L AND message IS NOT NULL$$, pg_temp.id('sr_erin')), '0', 'AC-6');

-- BR-3 : une passagère tient deux places.
PERFORM pg_temp.as_('erin');
PERFORM pg_temp.ok('erin demande aussi une place à gina', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('gina')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('sr_erin_gina', pg_temp.sorties_sr('car', 'erin', 'gina'));
PERFORM pg_temp.as_('gina');
PERFORM pg_temp.denied('une passagère déjà placée ne prend pas une seconde place', format($$SELECT public.accept_seat_request(%L)::text$$, pg_temp.id('sr_erin_gina')), '.', 'BR-3');

-- decline + AC-4 : renvoi immédiat d'une demande refusée.
PERFORM pg_temp.as_('hank');
PERFORM pg_temp.ok('hank demande une place à dave', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('dave')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('sr_hank', pg_temp.sorties_sr('car', 'hank', 'dave'));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne décline pas', format($$SELECT public.decline_seat_request(%L)::text$$, pg_temp.id('sr_hank')));
PERFORM pg_temp.as_('hank');
PERFORM pg_temp.denied('le passager ne décline pas sa propre demande', format($$SELECT public.decline_seat_request(%L)::text$$, pg_temp.id('sr_hank')));
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.ok('dave décline hank', format($$SELECT public.decline_seat_request(%L)::text$$, pg_temp.id('sr_hank')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la demande est déclinée', format($$SELECT status FROM public.seat_requests WHERE id = %L$$, pg_temp.id('sr_hank')), 'declined');
PERFORM pg_temp.as_('hank');
-- AC-4 tient aujourd'hui, mais seulement par l'effet de DB-AC-2 (aucun renvoi n'est jamais possible).
PERFORM pg_temp.denied('une demande déclinée ne se renvoie pas aussitôt', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('dave')), '.');

-- Blocage entre passager et conducteur.
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('gina'), pg_temp.id('hank'));
PERFORM pg_temp.as_('hank');
PERFORM pg_temp.denied('pas de demande de place vers qui nous a bloqué', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('gina')));

-- IX-2 / BR-1 : la demande de place ne rouvre pas un contact refusé.
PERFORM pg_temp.as_('db');
INSERT INTO public.conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, created_at, last_message_at)
VALUES (least(pg_temp.id('ivy'), pg_temp.id('dave')), greatest(pg_temp.id('ivy'), pg_temp.id('dave')), pg_temp.id('ivy'), 'declined', 'profile', pg_temp.id('ivy'), now(), now());
PERFORM pg_temp.as_('ivy');
PERFORM pg_temp.ok('ivy demande une place à dave', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('dave')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('sr_ivy', pg_temp.sorties_sr('car', 'ivy', 'dave'));
PERFORM pg_temp.eq('le contact refusé n''est pas réactivé par une demande de place',
  format($$SELECT status FROM public.conversations WHERE user_1 = least(%L::uuid, %L::uuid) AND user_2 = greatest(%L::uuid, %L::uuid)$$,
    pg_temp.id('ivy'), pg_temp.id('dave'), pg_temp.id('ivy'), pg_temp.id('dave')), 'declined', 'IX-2');

-- cancel_pending_seat_request
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon n''annule pas une demande', format($$SELECT public.cancel_pending_seat_request(%L)::text$$, pg_temp.id('sr_ivy')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu n''annule pas une demande', format($$SELECT public.cancel_pending_seat_request(%L)::text$$, pg_temp.id('sr_ivy')));
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.denied('le conducteur n''annule pas la demande de la passagère', format($$SELECT public.cancel_pending_seat_request(%L)::text$$, pg_temp.id('sr_ivy')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu n''annule pas la demande d''autrui', format($$SELECT public.cancel_pending_seat_request(%L)::text$$, pg_temp.id('sr_ivy')));
PERFORM pg_temp.as_('ivy');
PERFORM pg_temp.ok('ivy annule sa demande', format($$SELECT public.cancel_pending_seat_request(%L)::text$$, pg_temp.id('sr_ivy')));
PERFORM pg_temp.denied('une demande annulée ne s''annule pas deux fois', format($$SELECT public.cancel_pending_seat_request(%L)::text$$, pg_temp.id('sr_ivy')));
PERFORM pg_temp.ok('après avoir annulé sa demande, ivy peut redemander au même conducteur', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('car'), pg_temp.id('dave')), 'DB-AC-2');

-- cancel_accepted_seat
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne rend pas une place', format($$SELECT public.cancel_accepted_seat(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne rend pas une place', format($$SELECT public.cancel_accepted_seat(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu ne rend pas la place d''autrui', format($$SELECT public.cancel_accepted_seat(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('erin');
PERFORM pg_temp.ok('erin rend sa place', format($$SELECT public.cancel_accepted_seat(%L)::text$$, pg_temp.id('sr_erin')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la place revient à dave', format($$SELECT transport_seats::text FROM public.participations WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('car'), pg_temp.id('dave')), '2');

-- ═════ Matériel ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne déclare pas de matériel', format($$SELECT public.set_activity_gear(%L, '[{"name":"corde","quantity":1}]'::jsonb)::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne déclare pas de matériel', format($$SELECT public.set_activity_gear(%L, '[{"name":"corde","quantity":1}]'::jsonb)::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un non-participant ne déclare pas de matériel', format($$SELECT public.set_activity_gear(%L, '[{"name":"corde","quantity":1}]'::jsonb)::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.ok('dave déclare une corde', format($$SELECT public.set_activity_gear(%L, '[{"name":"corde <b>60m</b>","quantity":500}]'::jsonb)::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('quantité bornée à 99 et balises retirées',
  format($$SELECT gear_name || '|' || quantity FROM public.activity_gear WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('car'), pg_temp.id('dave')), 'corde 60m|99');
PERFORM pg_temp.as_('hank');
PERFORM pg_temp.eq('un participant voit le matériel', format($$SELECT count(*)::text FROM public.activity_gear WHERE activity_id = %L$$, pg_temp.id('car')), '1');
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.eq('un inconnu ne voit pas le matériel', format($$SELECT count(*)::text FROM public.activity_gear WHERE activity_id = %L$$, pg_temp.id('car')), '0');
PERFORM pg_temp.denied('pas d''écriture directe dans activity_gear',
  format($$INSERT INTO public.activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES (%L, %L, 'x', 1, false)$$, pg_temp.id('car'), pg_temp.id('frank')));

PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne signale pas de matériel manquant', format($$SELECT public.add_missing_gear(%L, 'piolet')::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne signale pas de matériel manquant', format($$SELECT public.add_missing_gear(%L, 'piolet')::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu ne signale pas de matériel manquant', format($$SELECT public.add_missing_gear(%L, 'piolet')::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.ok('dave signale un piolet manquant', format($$SELECT public.add_missing_gear(%L, 'piolet', 2)::text$$, pg_temp.id('car')));
PERFORM pg_temp.denied('nom de matériel vide refusé', format($$SELECT public.add_missing_gear(%L, '   ')::text$$, pg_temp.id('car')), 'junto.gear_invalid');
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('un inconnu ne retire pas de matériel manquant', format($$SELECT public.remove_missing_gear(%L, 'piolet')::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne retire pas de matériel manquant', format($$SELECT public.remove_missing_gear(%L, 'piolet')::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('l''organisatrice retire le piolet manquant', format($$SELECT public.remove_missing_gear(%L, 'PIOLET')::text$$, pg_temp.id('car')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('plus de matériel manquant', format($$SELECT count(*)::text FROM public.activity_gear_missing WHERE activity_id = %L$$, pg_temp.id('car')), '0');

-- ═════ Alertes ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne crée pas d''alerte', $$SELECT public.create_alert(6.0, 44.0, 20)::text$$);
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne crée pas d''alerte', $$SELECT public.create_alert(6.0, 44.0, 20)::text$$);
PERFORM pg_temp.as_('kim');
PERFORM pg_temp.put('alert', pg_temp.ok('kim crée une alerte', $$SELECT public.create_alert(6.0, 44.0, 20, 'hiking', ARRAY['débutant'])::text$$));
PERFORM pg_temp.denied('niveau d''alerte inconnu refusé', $$SELECT public.create_alert(6.0, 44.0, 20, NULL, ARRAY['légende'])::text$$);
PERFORM pg_temp.denied('période d''alerte inversée refusée', $$SELECT public.create_alert(6.0, 44.0, 20, NULL, NULL, current_date + 5, current_date + 1)::text$$, 'junto.alert_date_invalid');
PERFORM pg_temp.denied('rayon d''alerte hors bornes refusé', $$SELECT public.create_alert(6.0, 44.0, 5000)::text$$, 'violates|junto');
PERFORM pg_temp.denied('pas d''écriture directe dans activity_alerts',
  format($$INSERT INTO public.activity_alerts (user_id, location, radius_km) VALUES (%L, 'SRID=4326;POINT(6 44)', 20)$$, pg_temp.id('kim')));
DECLARE i int;
BEGIN
  FOR i IN 1..9 LOOP PERFORM public.create_alert(6.0, 44.0, 20); END LOOP;
EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.put('alert_err', SQLERRM);
END;
PERFORM pg_temp.denied('11e alerte refusée', $$SELECT public.create_alert(6.0, 44.0, 20)::text$$, 'junto.alert_limit_reached');
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('coordonnées d''alerte invalides refusées', $$SELECT public.create_alert(6.0, 300.0, 20)::text$$, '.', 'DC-6');
PERFORM pg_temp.eq('un inconnu ne lit pas les alertes d''autrui', format($$SELECT count(*)::text FROM public.activity_alerts WHERE id = %L$$, pg_temp.id('alert')), '0');
PERFORM pg_temp.eq('un inconnu ne supprime pas les alertes d''autrui', format($$DELETE FROM public.activity_alerts WHERE id = %L$$, pg_temp.id('alert')), '0');

-- ═════ Accès direct aux tables ═════
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('pas d''inscription directe dans participations',
  format($$INSERT INTO public.participations (activity_id, user_id, status) VALUES (%L, %L, 'accepted')$$, pg_temp.id('priv'), pg_temp.id('frank')));
PERFORM pg_temp.denied('pas de demande de place directe',
  format($$INSERT INTO public.seat_requests (activity_id, requester_id, driver_id) VALUES (%L, %L, %L)$$, pg_temp.id('car'), pg_temp.id('frank'), pg_temp.id('dave')));
PERFORM pg_temp.denied('pas de création directe de sortie',
  format($$INSERT INTO public.activities (creator_id, sport_id, title, level, location_meeting, starts_at, duration) VALUES (%L, (SELECT id FROM public.sports WHERE key = 'hiking'), 'Directe', 'x', 'SRID=4326;POINT(6 44)', now() + interval '1 day', '2 hours')$$, pg_temp.id('frank')));
PERFORM pg_temp.eq('un inconnu ne modifie pas la sortie d''autrui', format($$UPDATE public.activities SET title = 'Pirate' WHERE id = %L$$, pg_temp.id('car')), '0');
PERFORM pg_temp.eq('un inconnu ne supprime pas la sortie d''autrui', format($$DELETE FROM public.activities WHERE id = %L$$, pg_temp.id('car')), '0');
PERFORM pg_temp.as_('erin');
PERFORM pg_temp.eq('une participante ne modifie pas sa participation en direct', format($$UPDATE public.participations SET status = 'removed', confirmed_present = true WHERE activity_id = %L AND user_id = %L$$, pg_temp.id('car'), pg_temp.id('erin')), '0');
PERFORM pg_temp.eq('une participante ne modifie pas une demande de place en direct', format($$UPDATE public.seat_requests SET status = 'accepted' WHERE id = %L$$, pg_temp.id('sr_erin_gina')), '0');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('la créatrice ne supprime pas sa sortie en direct', format($$DELETE FROM public.activities WHERE id = %L$$, pg_temp.id('car')), '0');
PERFORM pg_temp.ok('la créatrice tente de forcer statut / créateur / démo en direct', format($$UPDATE public.activities SET status = 'completed', creator_id = %L, is_demo = true, invite_token = gen_random_uuid() WHERE id = %L$$, pg_temp.id('bob'), pg_temp.id('car')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('statut, créateur et drapeau démo inchangés', format($$SELECT status || '|' || (creator_id = %L)::text || '|' || is_demo::text FROM public.activities WHERE id = %L$$, pg_temp.id('alice'), pg_temp.id('car')), 'published|true|false');

-- ═════ Sorties datées (carl) : AC-1, BR-7, BR-8 ═════
PERFORM pg_temp.as_('carl');
PERFORM pg_temp.put('done', pg_temp.ok('fixture : sortie de carl (deviendra terminée)', pg_temp.sorties_ca('public', 5)));
PERFORM pg_temp.put('run',  pg_temp.ok('fixture : sortie de carl (deviendra en cours)', pg_temp.sorties_ca('public', 5)));
PERFORM pg_temp.put('del',  pg_temp.ok('fixture : sortie de carl (sera retirée)', pg_temp.sorties_ca('public', 5)));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET starts_at = now() - interval '2 days', status = 'completed' WHERE id = pg_temp.id('done');
UPDATE public.activities SET starts_at = now() - interval '1 hour', status = 'in_progress' WHERE id = pg_temp.id('run');
PERFORM set_config('junto.bypass_lock', 'false', true);

PERFORM pg_temp.as_('carl');
PERFORM pg_temp.denied('une sortie terminée ne se modifie plus par update_activity', format($$SELECT public.update_activity(%L, 'Réécriture')::text$$, pg_temp.id('done')));
PERFORM pg_temp.denied('le sport d''une sortie terminée ne change pas en direct',
  format($$UPDATE public.activities SET sport_id = (SELECT id FROM public.sports WHERE key <> 'hiking' ORDER BY key LIMIT 1) WHERE id = %L$$, pg_temp.id('done')), '.', 'AC-1');
PERFORM pg_temp.denied('une date hors bornes ne passe pas en direct',
  format($$UPDATE public.activities SET starts_at = now() + interval '2 years' WHERE id = %L$$, pg_temp.id('del')), '.', 'AC-1');
PERFORM pg_temp.ok('carl tente de repousser sa sortie en cours', format($$SELECT public.update_activity(%L, p_starts_at => now() + interval '3 days')::text$$, pg_temp.id('run')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('une sortie en cours ne se déplace pas dans le futur',
  format($$SELECT (starts_at < now())::text FROM public.activities WHERE id = %L$$, pg_temp.id('run')), 'true', 'BR-7');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET deleted_at = now() WHERE id = pg_temp.id('del');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('carl');
PERFORM pg_temp.denied('une sortie retirée par l''admin ne se modifie plus', format($$SELECT public.update_activity(%L, 'Retour')::text$$, pg_temp.id('del')), 'Operation not permitted', 'BR-8');
PERFORM pg_temp.denied('une sortie retirée ne change plus de trace', format($$SELECT public.update_activity_trace(%L, '{"type":"LineString","coordinates":[[6,44],[6.1,44.1]]}'::jsonb)::text$$, pg_temp.id('del')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('on ne rejoint pas une sortie retirée', format($$SELECT public.join_activity(%L)$$, pg_temp.id('del')));
PERFORM pg_temp.denied('on ne rejoint pas une sortie terminée', format($$SELECT public.join_activity(%L)$$, pg_temp.id('done')));

-- ═════ AC-11 : sortie d'une organisatrice suspendue ═════
PERFORM pg_temp.as_('olga');
PERFORM pg_temp.put('olga_act', pg_temp.ok('fixture : sortie d''olga', pg_temp.sorties_ca('public', 5)));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = now() WHERE id = pg_temp.id('olga');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('la sortie d''une organisatrice suspendue disparaît de la carte', format($$SELECT count(*)::text FROM public.activities_with_coords WHERE id = %L$$, pg_temp.id('olga_act')), '0');
PERFORM pg_temp.denied('on ne rejoint pas la sortie d''une organisatrice suspendue', format($$SELECT public.join_activity(%L)$$, pg_temp.id('olga_act')), 'Operation not permitted', 'AC-11');
