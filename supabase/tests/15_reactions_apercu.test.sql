-- Domaine 15 — réactions emoji et aperçu d'un canal non rejoint (mig 00551).

-- ───── Fixtures : un canal ouvert (rx_a anime, rx_b membre), un message de chacun ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('rx_a', 'tos');
PERFORM pg_temp.user('rx_b', 'tos');
PERFORM pg_temp.user('rx_out', 'tos');   -- pas membre
PERFORM pg_temp.user('rx_ban', 'tos');   -- banni du canal
PERFORM pg_temp.user('rx_susp', 'tos,suspended');
PERFORM pg_temp.put('rx_conv', gen_random_uuid()::text);
PERFORM set_config('junto.skip_message_push', 'true', true);
INSERT INTO public.conversations (id, type, status, name, created_by)
VALUES (pg_temp.id('rx_conv'), 'channel', 'active', 'Canal de test réactions', pg_temp.id('rx_a'));
INSERT INTO public.channels (conversation_id, sport_key, base, base_label, radius_km, created_by)
VALUES (pg_temp.id('rx_conv'), 'climbing-sport', ST_SetSRID(ST_MakePoint(6.08, 44.56), 4326)::geography, 'Gap', 60, pg_temp.id('rx_a'));
INSERT INTO public.conversation_members (conversation_id, user_id) VALUES
  (pg_temp.id('rx_conv'), pg_temp.id('rx_a')), (pg_temp.id('rx_conv'), pg_temp.id('rx_b'));
INSERT INTO public.channel_bans (conversation_id, user_id) VALUES (pg_temp.id('rx_conv'), pg_temp.id('rx_ban'));
PERFORM pg_temp.put('rx_m1', gen_random_uuid()::text);
PERFORM pg_temp.put('rx_m2', gen_random_uuid()::text);
INSERT INTO public.messages (id, conversation_id, sender_id, content, created_at)
VALUES (pg_temp.id('rx_m1'), pg_temp.id('rx_conv'), pg_temp.id('rx_a'), 'Salut le canal', now() - INTERVAL '2 minutes');
INSERT INTO public.messages (id, conversation_id, sender_id, content, created_at)
VALUES (pg_temp.id('rx_m2'), pg_temp.id('rx_conv'), pg_temp.id('rx_b'), 'Hello !', now() - INTERVAL '1 minute');
PERFORM set_config('junto.skip_message_push', 'false', true);

-- ═════ RX1 — Un membre réagit, change, retire ═════
PERFORM pg_temp.as_('rx_b');
PERFORM pg_temp.ok('RX1 un membre réagit', format($$SELECT public.set_message_reaction(%L, '👍')::text$$, pg_temp.id('rx_m1')));
PERFORM pg_temp.eq('RX1 la réaction est lisible par un membre',
  format($$SELECT emoji FROM public.message_reactions WHERE message_id = %L$$, pg_temp.id('rx_m1')), '👍');
PERFORM pg_temp.ok('RX1 un autre emoji remplace', format($$SELECT public.set_message_reaction(%L, '❤️')::text$$, pg_temp.id('rx_m1')));
PERFORM pg_temp.eq('RX1 une seule réaction par personne',
  format($$SELECT count(*)::text || ':' || max(emoji) FROM public.message_reactions WHERE message_id = %L$$, pg_temp.id('rx_m1')), '1:❤️');
PERFORM pg_temp.ok('RX1 le même emoji retire', format($$SELECT public.set_message_reaction(%L, '❤️')::text$$, pg_temp.id('rx_m1')));
PERFORM pg_temp.eq('RX1 plus de réaction',
  format($$SELECT count(*)::text FROM public.message_reactions WHERE message_id = %L$$, pg_temp.id('rx_m1')), '0');

-- ═════ RX2 — Ce qui est refusé ═════
PERFORM pg_temp.denied('RX2 texte libre refusé', format($$SELECT public.set_message_reaction(%L, 'lol')::text$$, pg_temp.id('rx_m1')), 'junto.reaction_invalid');
PERFORM pg_temp.denied('RX2 lettres accentuées refusées', format($$SELECT public.set_message_reaction(%L, 'é')::text$$, pg_temp.id('rx_m1')), 'junto.reaction_invalid');
PERFORM pg_temp.denied('RX2 pas d''écriture directe', format($$INSERT INTO public.message_reactions (message_id, user_id, emoji) VALUES (%L, %L, '👍')$$, pg_temp.id('rx_m1'), pg_temp.id('rx_b')));
PERFORM pg_temp.as_('rx_out');
PERFORM pg_temp.denied('RX2 un non-membre ne réagit pas', format($$SELECT public.set_message_reaction(%L, '👍')::text$$, pg_temp.id('rx_m1')));
PERFORM pg_temp.as_('rx_susp');
PERFORM pg_temp.denied('RX2 un compte suspendu ne réagit pas', format($$SELECT public.set_message_reaction(%L, '👍')::text$$, pg_temp.id('rx_m1')));

-- ═════ RX3 — Blocage : on ne réagit pas, on ne voit pas ses réactions ═════
PERFORM pg_temp.as_('rx_b');
PERFORM pg_temp.ok('RX3 rx_b réagit au message de rx_a', format($$SELECT public.set_message_reaction(%L, '🔥')::text$$, pg_temp.id('rx_m1')));
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('rx_a'), pg_temp.id('rx_b'));
PERFORM pg_temp.as_('rx_a');
PERFORM pg_temp.eq('RX3 rx_a ne voit pas la réaction de celui qu''il a bloqué',
  format($$SELECT count(*)::text FROM public.message_reactions WHERE message_id = %L$$, pg_temp.id('rx_m1')), '0');
PERFORM pg_temp.denied('RX3 rx_a ne réagit pas au message de celui qu''il a bloqué', format($$SELECT public.set_message_reaction(%L, '👍')::text$$, pg_temp.id('rx_m2')));
PERFORM pg_temp.as_('db');
DELETE FROM public.blocked_users WHERE blocker_id = pg_temp.id('rx_a') AND blocked_id = pg_temp.id('rx_b');

-- ═════ RX4 — Aperçu d'un canal non rejoint ═════
PERFORM pg_temp.as_('rx_out');
PERFORM pg_temp.eq('RX4 un non-membre lit l''aperçu (2 messages)',
  format($$SELECT count(*)::text FROM public.get_channel_preview(%L)$$, pg_temp.id('rx_conv')), '2');
PERFORM pg_temp.eq('RX4 dans l''ordre, le plus ancien d''abord',
  format($$SELECT content FROM public.get_channel_preview(%L) LIMIT 1$$, pg_temp.id('rx_conv')), 'Salut le canal');
PERFORM pg_temp.eq('RX4 un non-membre ne lit toujours pas les messages directement',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L$$, pg_temp.id('rx_conv')), '0');
PERFORM pg_temp.as_('rx_ban');
PERFORM pg_temp.eq('RX4 un banni n''a pas d''aperçu',
  format($$SELECT count(*)::text FROM public.get_channel_preview(%L)$$, pg_temp.id('rx_conv')), '0');
PERFORM pg_temp.as_('rx_susp');
PERFORM pg_temp.eq('RX4 un compte suspendu n''a pas d''aperçu',
  format($$SELECT count(*)::text FROM public.get_channel_preview(%L)$$, pg_temp.id('rx_conv')), '0');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('RX4 sans compte, pas d''aperçu', format($$SELECT count(*)::text FROM public.get_channel_preview(%L)$$, pg_temp.id('rx_conv')));
PERFORM pg_temp.as_('db');
INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (pg_temp.id('rx_out'), pg_temp.id('rx_b'));
PERFORM pg_temp.as_('rx_out');
PERFORM pg_temp.eq('RX4 l''aperçu cache l''auteur qu''on a bloqué',
  format($$SELECT count(*)::text FROM public.get_channel_preview(%L)$$, pg_temp.id('rx_conv')), '1');

-- ═════ RX5 — Rideau démo : pas d'aperçu d'un canal démo ═════
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.channels SET is_demo = true WHERE conversation_id = pg_temp.id('rx_conv');
PERFORM set_config('junto.bypass_lock', 'false', true);
UPDATE public.app_config SET value = 'false' WHERE name = 'demo_mode';
PERFORM pg_temp.as_('rx_out');
PERFORM pg_temp.eq('RX5 canal démo, rideau baissé : aperçu vide',
  format($$SELECT count(*)::text FROM public.get_channel_preview(%L)$$, pg_temp.id('rx_conv')), '0');
