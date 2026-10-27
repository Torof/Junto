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

-- ═════ CD6 — Les pros démo (00558) restent derrière le rideau ═════
-- Cinq pages pro et vingt sorties semées en migration : un vrai compte ne voit
-- ni la page, ni la sortie, ni leurs avis ; l'admin en mode démo voit tout.
PERFORM pg_temp.as_('cd_u');
PERFORM pg_temp.eq('CD6 rideau baissé : aucune page pro démo (00558)',
  $$SELECT count(*)::text FROM public.pro_profiles WHERE user_id IN ('d0000000-0000-4000-a000-000000000019','d0000000-0000-4000-a000-00000000001a','d0000000-0000-4000-a000-00000000001b','d0000000-0000-4000-a000-00000000001c','d0000000-0000-4000-a000-00000000001d')$$, '0');
PERFORM pg_temp.eq('CD6 rideau baissé : aucune sortie pro démo (00558)',
  $$SELECT count(*)::text FROM public.pro_offerings WHERE pro_id IN ('d0000000-0000-4000-a000-000000000019','d0000000-0000-4000-a000-00000000001a','d0000000-0000-4000-a000-00000000001b','d0000000-0000-4000-a000-00000000001c','d0000000-0000-4000-a000-00000000001d')$$, '0');
PERFORM pg_temp.eq('CD6 rideau baissé : aucun avis sur une sortie démo',
  $$SELECT count(*)::text FROM public.offering_reviews WHERE offering_id = 'b0000000-0000-4000-a000-000000000011'$$, '0');
PERFORM pg_temp.as_('cd_adm');
PERFORM pg_temp.cd_demo_mode(true);
PERFORM pg_temp.eq('CD6 admin, mode démo : les cinq pages pro',
  $$SELECT count(*)::text FROM public.pro_profiles WHERE user_id IN ('d0000000-0000-4000-a000-000000000019','d0000000-0000-4000-a000-00000000001a','d0000000-0000-4000-a000-00000000001b','d0000000-0000-4000-a000-00000000001c','d0000000-0000-4000-a000-00000000001d')$$, '5');
PERFORM pg_temp.eq('CD6 admin, mode démo : les vingt sorties',
  $$SELECT count(*)::text FROM public.pro_offerings WHERE pro_id IN ('d0000000-0000-4000-a000-000000000019','d0000000-0000-4000-a000-00000000001a','d0000000-0000-4000-a000-00000000001b','d0000000-0000-4000-a000-00000000001c','d0000000-0000-4000-a000-00000000001d')$$, '20');
PERFORM pg_temp.eq('CD6 admin, mode démo : chaque page a sa sortie mise en avant',
  $$SELECT count(*)::text FROM public.pro_profiles WHERE is_demo AND featured_offering_id IS NOT NULL AND user_id <> 'd0000000-0000-4000-a000-000000000001'$$, '5');
PERFORM pg_temp.cd_demo_mode(false);
