-- Domaine 14 — canaux démo (mig 00550). Un canal démo reste derrière le rideau
-- comme tout objet démo : visible et utilisable seulement par un admin, mode démo
-- allumé. Rideau baissé, aucun chemin ne le laisse passer — recherche, fiche,
-- membres, adhésion, liste des conversations, messages (RLS), envoi.

EXECUTE $p$CREATE FUNCTION pg_temp.cd_demo_mode(p_on boolean) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  BEGIN
    UPDATE public.app_config SET value = p_on::text WHERE name = 'demo_mode';
    IF NOT FOUND THEN INSERT INTO public.app_config (name, value) VALUES ('demo_mode', p_on::text); END IF;
  END $b$$p$;

-- ───── Fixtures : un canal démo avec un membre démo, un vrai membre et un message ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('cd_u', 'tos');
PERFORM pg_temp.user('cd_adm', 'tos,admin');
PERFORM pg_temp.user('cd_demo', 'tos,demo');
PERFORM pg_temp.put('cd_conv', gen_random_uuid()::text);
PERFORM set_config('junto.bypass_lock', 'true', true);
PERFORM set_config('junto.skip_message_push', 'true', true);
INSERT INTO public.conversations (id, type, status, name, created_by)
VALUES (pg_temp.id('cd_conv'), 'channel', 'active', 'Canal démo de test', pg_temp.id('cd_demo'));
INSERT INTO public.channels (conversation_id, sport_key, base, base_label, radius_km, created_by, is_demo)
VALUES (pg_temp.id('cd_conv'), 'climbing-sport', ST_SetSRID(ST_MakePoint(6.08, 44.56), 4326)::geography, 'Gap', 60, pg_temp.id('cd_demo'), true);
INSERT INTO public.conversation_members (conversation_id, user_id) VALUES
  (pg_temp.id('cd_conv'), pg_temp.id('cd_demo')),
  (pg_temp.id('cd_conv'), pg_temp.id('cd_u'));
INSERT INTO public.messages (conversation_id, sender_id, content)
VALUES (pg_temp.id('cd_conv'), pg_temp.id('cd_demo'), 'Message démo');
PERFORM set_config('junto.skip_message_push', 'false', true);
PERFORM pg_temp.cd_demo_mode(false);

-- ═════ CD1 — Rideau baissé : un vrai compte, même membre, ne voit rien ═════
PERFORM pg_temp.as_('cd_u');
PERFORM pg_temp.eq('CD1 recherche : pas de canal démo',
  format($$SELECT count(*)::text FROM public.search_channels(NULL, NULL, 6.08, 44.56) WHERE conversation_id = %L$$, pg_temp.id('cd_conv')), '0');
PERFORM pg_temp.eq('CD1 fiche : vide',
  format($$SELECT count(*)::text FROM public.get_channel(%L)$$, pg_temp.id('cd_conv')), '0');
PERFORM pg_temp.eq('CD1 membres : vide, même pour un membre',
  format($$SELECT count(*)::text FROM public.get_channel_members(%L)$$, pg_temp.id('cd_conv')), '0');
PERFORM pg_temp.eq('CD1 liste des conversations : absent',
  format($$SELECT count(*)::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('cd_conv')), '0');
PERFORM pg_temp.eq('CD1 messages (RLS) : rien',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L$$, pg_temp.id('cd_conv')), '0');
PERFORM pg_temp.denied('CD1 envoi refusé',
  format($$SELECT public.send_message(%L, 'coucou', NULL)::text$$, pg_temp.id('cd_conv')));
PERFORM pg_temp.denied('CD1 adhésion refusée',
  format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('cd_conv')));

-- ═════ CD2 — Rideau baissé : un admin non plus (le mode démo est éteint) ═════
PERFORM pg_temp.as_('cd_adm');
PERFORM pg_temp.eq('CD2 admin, démo éteinte : recherche sans canal démo',
  format($$SELECT count(*)::text FROM public.search_channels(NULL, NULL, 6.08, 44.56) WHERE conversation_id = %L$$, pg_temp.id('cd_conv')), '0');
PERFORM pg_temp.denied('CD2 admin, démo éteinte : adhésion refusée',
  format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('cd_conv')));

-- ═════ CD3 — Mode démo allumé : un vrai compte non-admin ne voit toujours rien ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.cd_demo_mode(true);
PERFORM pg_temp.as_('cd_u');
PERFORM pg_temp.eq('CD3 non-admin, démo allumée : recherche sans canal démo',
  format($$SELECT count(*)::text FROM public.search_channels(NULL, NULL, 6.08, 44.56) WHERE conversation_id = %L$$, pg_temp.id('cd_conv')), '0');
PERFORM pg_temp.eq('CD3 non-admin, démo allumée : messages invisibles',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L$$, pg_temp.id('cd_conv')), '0');

-- ═════ CD4 — Mode démo allumé : l'admin le voit, le rejoint, lit et écrit ═════
PERFORM pg_temp.as_('cd_adm');
PERFORM pg_temp.eq('CD4 admin, démo allumée : le canal sort dans la recherche',
  format($$SELECT count(*)::text FROM public.search_channels(NULL, NULL, 6.08, 44.56) WHERE conversation_id = %L$$, pg_temp.id('cd_conv')), '1');
PERFORM pg_temp.eq('CD4 admin, démo allumée : fiche visible',
  format($$SELECT count(*)::text FROM public.get_channel(%L)$$, pg_temp.id('cd_conv')), '1');
PERFORM pg_temp.ok('CD4 admin, démo allumée : il rejoint',
  format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('cd_conv')));
PERFORM pg_temp.eq('CD4 admin membre : il lit le message démo',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L$$, pg_temp.id('cd_conv')), '1');
PERFORM pg_temp.eq('CD4 admin membre : le canal est dans ses conversations',
  format($$SELECT count(*)::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('cd_conv')), '1');

-- ═════ CD5 — Le drapeau démo d'un canal ne se change pas hors migration ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.cd_demo_mode(false);
PERFORM set_config('junto.bypass_lock', 'false', true);
UPDATE public.channels SET is_demo = false WHERE conversation_id = pg_temp.id('cd_conv');
PERFORM pg_temp.eq('CD5 is_demo épinglé par le déclencheur',
  format($$SELECT is_demo::text FROM public.channels WHERE conversation_id = %L$$, pg_temp.id('cd_conv')), 'true');
