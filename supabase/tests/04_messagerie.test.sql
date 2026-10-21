-- Domaine 4 — messagerie, contacts, groupes, canaux, notifications.

-- ───── Utilitaires locaux ─────
-- Connexion directe (fixture, en tant que 'db') : un fil DM actif « profil » entre deux comptes.
EXECUTE $p$CREATE FUNCTION pg_temp.ms_connect(a text, b text) RETURNS uuid
  LANGUAGE plpgsql SECURITY DEFINER AS $b$
  DECLARE v uuid;
  BEGIN
    INSERT INTO public.conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
    VALUES ('dm', LEAST(pg_temp.id(a), pg_temp.id(b)), GREATEST(pg_temp.id(a), pg_temp.id(b)), pg_temp.id(a),
            'active', 'profile', now(), now())
    RETURNING id INTO v;
    PERFORM pg_temp.put('dm_' || a || '_' || b, v::text);
    RETURN v;
  END $b$$p$;

-- Envoie n messages en rafale avec le rôle courant ; renvoie la première erreur ou 'none'.
EXECUTE $p$CREATE FUNCTION pg_temp.ms_flood(p_conv uuid, p_n int) RETURNS text
  LANGUAGE plpgsql AS $b$
  BEGIN
    FOR i IN 1..p_n LOOP
      BEGIN
        PERFORM public.send_message(p_conv, 'rafale ' || i);
      EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END;
    END LOOP;
    RETURN 'none';
  END $b$$p$;

-- Crée n groupes à la suite ; renvoie la première erreur ou 'none'.
EXECUTE $p$CREATE FUNCTION pg_temp.ms_groups(p_n int, p_members uuid[]) RETURNS text
  LANGUAGE plpgsql AS $b$
  BEGIN
    FOR i IN 1..p_n LOOP
      BEGIN
        PERFORM public.create_group('Groupe rafale ' || i, NULL, p_members);
      EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END;
    END LOOP;
    RETURN 'none';
  END $b$$p$;

-- Crée n canaux (forcés, en plein Pacifique) ; renvoie la première erreur ou 'none'.
EXECUTE $p$CREATE FUNCTION pg_temp.ms_channels(p_n int) RETURNS text
  LANGUAGE plpgsql AS $b$
  BEGIN
    FOR i IN 1..p_n LOOP
      BEGIN
        PERFORM * FROM public.create_channel('Canal rafale ' || i, -131 - i * 0.5, -46, 'Océan', 35, NULL, NULL, NULL, true);
      EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END;
    END LOOP;
    RETURN 'none';
  END $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.user('alice', 'tos');
PERFORM pg_temp.user('bob', 'tos');
PERFORM pg_temp.user('carol', 'tos');
PERFORM pg_temp.user('dave', 'tos');
PERFORM pg_temp.user('erin', 'tos');
PERFORM pg_temp.user('frank', 'tos');
PERFORM pg_temp.user('mal', 'tos');            -- inconnu de tous
PERFORM pg_temp.user('sam', 'tos,suspended');
PERFORM pg_temp.user('demo1', 'tos,demo');
FOR i IN 1..11 LOOP PERFORM pg_temp.user('t' || i, 'tos'); END LOOP;
PERFORM pg_temp.user('q1', 'tos');
PERFORM pg_temp.user('q2', 'tos');
PERFORM pg_temp.user('f1', 'tos');
PERFORM pg_temp.user('f2', 'tos');
PERFORM pg_temp.user('b1', 'tos');
PERFORM pg_temp.user('b2', 'tos');
PERFORM pg_temp.user('r1', 'tos');
PERFORM pg_temp.user('rq1', 'tos');
PERFORM pg_temp.user('rq2', 'tos');
PERFORM pg_temp.user('s1', 'tos');
PERFORM pg_temp.user('ch2', 'tos');

PERFORM pg_temp.as_('db');
PERFORM pg_temp.ms_connect('alice', 'carol');
PERFORM pg_temp.ms_connect('alice', 'dave');
PERFORM pg_temp.ms_connect('alice', 'erin');
PERFORM pg_temp.ms_connect('alice', 'frank');
PERFORM pg_temp.ms_connect('alice', 'sam');
PERFORM pg_temp.ms_connect('f1', 'f2');
PERFORM pg_temp.ms_connect('b1', 'b2');
PERFORM pg_temp.ms_connect('bob', 'carol');
PERFORM pg_temp.ms_connect('carol', 'dave');

-- ═════ Demandes de contact ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne peut pas envoyer de demande de contact',
  format($$SELECT public.send_contact_request(%L, 'Salut')::text$$, pg_temp.id('bob')));

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('pas de demande de contact à soi-même',
  format($$SELECT public.send_contact_request(%L, 'Salut')::text$$, pg_temp.id('alice')));
PERFORM pg_temp.denied('pas de demande vers un compte suspendu',
  format($$SELECT public.send_contact_request(%L, 'Salut')::text$$, pg_temp.id('sam')));
PERFORM pg_temp.denied('pas de demande vers un compte démo',
  format($$SELECT public.send_contact_request(%L, 'Salut')::text$$, pg_temp.id('demo1')));
PERFORM pg_temp.denied('une source réservée (invite) est refusée',
  format($$SELECT public.send_contact_request(%L, 'Salut', 'invite')::text$$, pg_temp.id('bob')));
PERFORM pg_temp.denied('message de demande vide refusé',
  format($$SELECT public.send_contact_request(%L, '   ')::text$$, pg_temp.id('bob')));
PERFORM pg_temp.denied('message de demande de plus de 500 caractères refusé',
  format($$SELECT public.send_contact_request(%L, repeat('x', 501))::text$$, pg_temp.id('bob')));
PERFORM pg_temp.put('dm_ab', pg_temp.ok('alice envoie une demande de contact à bob',
  format($$SELECT public.send_contact_request(%L, 'Salut <b>Bob</b>, on grimpe ?')::text$$, pg_temp.id('bob'))));

PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la demande crée une conversation en attente (jamais active)',
  format($$SELECT status FROM public.conversations WHERE id = %L$$, pg_temp.id('dm_ab')), 'pending_request');
PERFORM pg_temp.eq('le HTML du message de demande est retiré',
  format($$SELECT request_message FROM public.conversations WHERE id = %L$$, pg_temp.id('dm_ab')), 'Salut Bob, on grimpe ?');

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('l''émetteur ne peut pas écrire dans une demande en attente',
  format($$SELECT public.send_message(%L, 'Alors ?')::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.denied('l''émetteur ne peut pas renvoyer une demande déjà en cours',
  format($$SELECT public.send_contact_request(%L, 'Relance')::text$$, pg_temp.id('bob')));
PERFORM pg_temp.denied('l''émetteur ne peut pas accepter sa propre demande',
  format($$SELECT public.accept_contact_request(%L)::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.eq('état vu par l''émetteur : pending',
  format($$SELECT state FROM public.get_conversation_state_with(%L)$$, pg_temp.id('bob')), 'pending');
PERFORM pg_temp.eq('l''émetteur ne voit pas sa demande dans ses demandes reçues',
  $$SELECT count(*)::text FROM public.get_pending_contact_requests()$$, '0');

PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('le destinataire ne peut pas écrire avant d''accepter',
  format($$SELECT public.send_message(%L, 'Coucou')::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.eq('état vu par le destinataire : pending_received',
  format($$SELECT state FROM public.get_conversation_state_with(%L)$$, pg_temp.id('alice')), 'pending_received');
PERFORM pg_temp.eq('le destinataire voit la demande reçue',
  $$SELECT count(*)::text FROM public.get_pending_contact_requests()$$, '1');
PERFORM pg_temp.eq('le destinataire est notifié de la demande',
  $$SELECT count(*)::text FROM public.notifications WHERE type = 'contact_request'$$, '1');
PERFORM pg_temp.eq('une demande en attente n''apparaît pas dans la liste des conversations',
  format($$SELECT count(*)::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('dm_ab')), '0');

PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('un tiers ne peut pas accepter la demande',
  format($$SELECT public.accept_contact_request(%L)::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.denied('un tiers ne peut pas refuser la demande',
  format($$SELECT public.decline_contact_request(%L)::text$$, pg_temp.id('dm_ab')));

PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob accepte la demande', format($$SELECT public.accept_contact_request(%L)::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.eq('le message de la demande devient le premier message du fil',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L$$, pg_temp.id('dm_ab')), '1');
PERFORM pg_temp.denied('accepter deux fois est refusé',
  format($$SELECT public.accept_contact_request(%L)::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('l''émetteur est notifié de l''acceptation',
  $$SELECT count(*)::text FROM public.notifications WHERE type = 'contact_request_accepted'$$, '1');
PERFORM pg_temp.eq('bob apparaît dans les contacts d''alice',
  format($$SELECT count(*)::text FROM public.get_contacts() WHERE id = %L$$, pg_temp.id('bob')), '1');
PERFORM pg_temp.eq('état actif après acceptation',
  format($$SELECT state FROM public.get_conversation_state_with(%L)$$, pg_temp.id('bob')), 'active');

-- Refus silencieux : t1 → t2, t2 refuse.
PERFORM pg_temp.as_('t1');
PERFORM pg_temp.put('dm_t1t2', pg_temp.ok('t1 envoie une demande à t2',
  format($$SELECT public.send_contact_request(%L, 'Bonjour t2')::text$$, pg_temp.id('t2'))));
PERFORM pg_temp.as_('t2');
PERFORM pg_temp.ok('t2 refuse la demande', format($$SELECT public.decline_contact_request(%L)::text$$, pg_temp.id('dm_t1t2')));
PERFORM pg_temp.ok('refuser deux fois reste silencieux', format($$SELECT public.decline_contact_request(%L)::text$$, pg_temp.id('dm_t1t2')));
PERFORM pg_temp.eq('après refus, t2 ne voit plus la demande',
  $$SELECT count(*)::text FROM public.get_pending_contact_requests()$$, '0');
PERFORM pg_temp.denied('t2 ne peut pas accepter une demande refusée',
  format($$SELECT public.accept_contact_request(%L)::text$$, pg_temp.id('dm_t1t2')));
PERFORM pg_temp.as_('t1');
PERFORM pg_temp.eq('le refus est silencieux : l''émetteur voit toujours « pending »',
  format($$SELECT state FROM public.get_conversation_state_with(%L)$$, pg_temp.id('t2')), 'pending');
PERFORM pg_temp.eq('le refus ne notifie pas l''émetteur',
  $$SELECT count(*)::text FROM public.notifications$$, '0');
PERFORM pg_temp.denied('l''émetteur refusé ne peut pas écrire',
  format($$SELECT public.send_message(%L, 'Allô ?')::text$$, pg_temp.id('dm_t1t2')));
PERFORM pg_temp.denied('l''émetteur refusé ne peut pas renvoyer de demande',
  format($$SELECT public.send_contact_request(%L, 'Encore moi')::text$$, pg_temp.id('t2')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la conversation refusée reste « declined »',
  format($$SELECT status FROM public.conversations WHERE id = %L$$, pg_temp.id('dm_t1t2')), 'declined');

-- Plafonds : 5 demandes par jour, 10 en attente sur 30 jours.
PERFORM pg_temp.as_('erin');
FOR i IN 1..5 LOOP
  PERFORM pg_temp.ok('erin envoie la demande ' || i || '/5',
    format($$SELECT public.send_contact_request(%L, 'Salut')::text$$, pg_temp.id('t' || (i + 2))));
END LOOP;
PERFORM pg_temp.denied('la 6e demande du jour est refusée (plafond journalier)',
  format($$SELECT public.send_contact_request(%L, 'Salut')::text$$, pg_temp.id('t8')), 'junto\.contact_request_daily_cap');

PERFORM pg_temp.as_('db');
FOR i IN 1..10 LOOP
  INSERT INTO public.conversations (type, user_1, user_2, initiated_by, status, initiated_from, request_sender_id,
                                    request_message, request_expires_at, created_at, last_message_at)
  VALUES ('dm', LEAST(pg_temp.id('frank'), pg_temp.id('t' || i)), GREATEST(pg_temp.id('frank'), pg_temp.id('t' || i)),
          pg_temp.id('frank'), 'pending_request', 'profile', pg_temp.id('frank'), 'ancienne demande',
          now() + interval '28 days', now() - interval '2 days', now() - interval '2 days');
END LOOP;
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.denied('au-delà de 10 demandes en attente, nouvelle demande refusée',
  format($$SELECT public.send_contact_request(%L, 'Salut')::text$$, pg_temp.id('t11')), 'junto\.contact_request_pending_cap');

-- Blocage : aucune demande dans un sens comme dans l'autre.
PERFORM pg_temp.as_('erin');
PERFORM pg_temp.ok('erin bloque mal', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('erin'), pg_temp.id('mal')));
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('une personne bloquée ne peut pas envoyer de demande',
  format($$SELECT public.send_contact_request(%L, 'Pourquoi ?')::text$$, pg_temp.id('erin')));

-- ═════ QR de contact ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne crée pas de QR', $$SELECT public.create_contact_qr_token()$$);
PERFORM pg_temp.as_('demo1');
PERFORM pg_temp.denied('un compte démo ne crée pas de QR', $$SELECT public.create_contact_qr_token()$$);
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne crée pas de QR', $$SELECT public.create_contact_qr_token()$$);

PERFORM pg_temp.as_('q1');
PERFORM pg_temp.put('qr1', pg_temp.ok('q1 crée un QR', $$SELECT public.create_contact_qr_token()$$));
PERFORM pg_temp.eq('le jeton QR fait 64 caractères hexadécimaux',
  format($$SELECT (%L ~ '^[0-9a-f]{64}$')::text$$, pg_temp.get('qr1')), 'true');
PERFORM pg_temp.eq('scanner son propre QR ne fait rien',
  format($$SELECT coalesce(public.connect_via_qr_token(%L)::text, 'null')$$, pg_temp.get('qr1')), 'null');
PERFORM pg_temp.denied('la table des jetons QR n''est pas lisible directement',
  $$SELECT count(*)::text FROM public.contact_qr_tokens$$, 'permission denied');

PERFORM pg_temp.as_('q2');
PERFORM pg_temp.eq('un jeton malformé ne connecte pas',
  $$SELECT coalesce(public.connect_via_qr_token('pas-un-jeton')::text, 'null')$$, 'null');
PERFORM pg_temp.eq('un QR dont le propriétaire affiché ne correspond pas ne connecte pas',
  format($$SELECT coalesce(public.connect_via_qr_token(%L, %L)::text, 'null')$$, pg_temp.get('qr1'), pg_temp.id('mal')), 'null');
PERFORM pg_temp.put('dm_q', pg_temp.ok('q2 scanne le QR de q1',
  format($$SELECT public.connect_via_qr_token(%L, %L)::text$$, pg_temp.get('qr1'), pg_temp.id('q1'))));
PERFORM pg_temp.eq('le scan crée un fil actif', format($$SELECT state FROM public.get_conversation_state_with(%L)$$, pg_temp.id('q1')), 'active');
PERFORM pg_temp.eq('q1 apparaît dans les contacts de q2',
  format($$SELECT count(*)::text FROM public.get_contacts() WHERE id = %L$$, pg_temp.id('q1')), '1');

PERFORM pg_temp.as_('q1');
PERFORM pg_temp.put('qr2', pg_temp.ok('q1 crée un second QR', $$SELECT public.create_contact_qr_token()$$));
PERFORM pg_temp.ok('q1 révoque son second QR', format($$SELECT public.revoke_contact_qr_tokens(%L)::text$$, pg_temp.get('qr2')));
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.eq('un QR révoqué ne connecte plus',
  format($$SELECT coalesce(public.connect_via_qr_token(%L)::text, 'null')$$, pg_temp.get('qr2')), 'null');
PERFORM pg_temp.ok('mal tente de révoquer les QR de q1 (sans effet)', format($$SELECT public.revoke_contact_qr_tokens(%L)::text$$, pg_temp.get('qr1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('un tiers ne révoque pas le QR d''autrui',
  format($$SELECT (expires_at > now())::text FROM public.contact_qr_tokens WHERE token = %L$$, pg_temp.get('qr1')), 'true');

PERFORM pg_temp.as_('erin');
PERFORM pg_temp.put('qr3', pg_temp.ok('erin crée un QR', $$SELECT public.create_contact_qr_token()$$));
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.eq('une personne bloquée ne se connecte pas par QR',
  format($$SELECT coalesce(public.connect_via_qr_token(%L)::text, 'null')$$, pg_temp.get('qr3')), 'null');

-- Un QR après un refus : le fil devient actif, le message refusé n'est jamais publié.
PERFORM pg_temp.as_('t2');
PERFORM pg_temp.put('qr4', pg_temp.ok('t2 crée un QR', $$SELECT public.create_contact_qr_token()$$));
PERFORM pg_temp.as_('t1');
PERFORM pg_temp.eq('scanner le QR réutilise le fil refusé',
  format($$SELECT public.connect_via_qr_token(%L)::text$$, pg_temp.get('qr4')), pg_temp.get('dm_t1t2'));
PERFORM pg_temp.eq('le message d''une demande refusée n''est pas publié',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L$$, pg_temp.id('dm_t1t2')), '0');

-- ═════ Messages directs ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne peut pas envoyer de message', format($$SELECT public.send_message(%L, 'x')::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.denied('anon ne lit pas les messages', $$SELECT count(*)::text FROM public.messages$$);

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.put('m1', pg_temp.ok('alice écrit à bob', format($$SELECT public.send_message(%L, 'Premier message')::text$$, pg_temp.id('dm_ab'))));
PERFORM pg_temp.denied('message vide refusé', format($$SELECT public.send_message(%L, '   ')::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.denied('message de plus de 2000 caractères refusé', format($$SELECT public.send_message(%L, repeat('x', 2001))::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.denied('répondre à un message d''une autre conversation est refusé',
  format($$SELECT public.send_message(%L, 'réponse', %L)::text$$, pg_temp.id('dm_ab'), gen_random_uuid()));
PERFORM pg_temp.put('m_html', pg_temp.ok('alice envoie du HTML', format($$SELECT public.send_message(%L, '<script>x</script>Salut')::text$$, pg_temp.id('dm_ab'))));
PERFORM pg_temp.eq('le HTML des messages est retiré',
  format($$SELECT content FROM public.messages WHERE id = %L$$, pg_temp.id('m_html')), 'xSalut');
PERFORM pg_temp.ok('alice répond à son propre message', format($$SELECT public.send_message(%L, 'suite', %L)::text$$, pg_temp.id('dm_ab'), pg_temp.id('m1')));

PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('bob lit le message d''alice', format($$SELECT count(*)::text FROM public.messages WHERE id = %L$$, pg_temp.id('m1')), '1');
PERFORM pg_temp.eq('le fil est non lu pour bob',
  format($$SELECT is_unread::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('dm_ab')), 'true');
PERFORM pg_temp.ok('bob marque le fil comme lu', format($$SELECT public.mark_conversation_read(%L)::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.eq('le fil est lu pour bob',
  format($$SELECT is_unread::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('dm_ab')), 'false');
PERFORM pg_temp.eq('get_conversation_peer renvoie alice à bob',
  format($$SELECT other_id::text FROM public.get_conversation_peer(%L)$$, pg_temp.id('dm_ab')), pg_temp.get('alice'));

PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('un non-membre ne peut pas écrire dans un DM', format($$SELECT public.send_message(%L, 'intrus')::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.eq('un non-membre ne lit pas le DM', format($$SELECT count(*)::text FROM public.messages WHERE id = %L$$, pg_temp.id('m1')), '0');
PERFORM pg_temp.eq('get_conversation_peer ne révèle rien à un tiers',
  format($$SELECT count(*)::text FROM public.get_conversation_peer(%L)$$, pg_temp.id('dm_ab')), '0');
PERFORM pg_temp.eq('get_my_conversations ne liste pas le DM d''autrui',
  format($$SELECT count(*)::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('dm_ab')), '0');
PERFORM pg_temp.eq('get_conversation_state_with ne révèle rien d''une paire tierce',
  format($$SELECT count(*)::text FROM public.get_conversation_state_with(%L)$$, pg_temp.id('alice')), '0');
PERFORM pg_temp.ok('marquer lu un fil dont on n''est pas membre est sans effet', format($$SELECT public.mark_conversation_read(%L)::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.ok('masquer un fil dont on n''est pas membre est sans effet', format($$SELECT public.set_conversation_hidden(%L, true)::text$$, pg_temp.id('dm_ab')));

-- Écritures directes sur les tables
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('insertion directe dans messages refusée',
  format($$INSERT INTO public.messages (conversation_id, sender_id, content) VALUES (%L, %L, 'direct')$$, pg_temp.id('dm_ab'), pg_temp.id('alice')));
PERFORM pg_temp.eq('modification directe d''un message sans effet',
  format($$UPDATE public.messages SET content = 'falsifié' WHERE id = %L$$, pg_temp.id('m1')), '0');
PERFORM pg_temp.eq('suppression directe d''un message sans effet',
  format($$DELETE FROM public.messages WHERE id = %L$$, pg_temp.id('m1')), '0');
PERFORM pg_temp.denied('la table conversations n''est pas lisible directement', $$SELECT count(*)::text FROM public.conversations$$, 'permission denied');
PERFORM pg_temp.denied('insertion directe dans conversations refusée',
  format($$INSERT INTO public.conversations (type, user_1, user_2, status) VALUES ('dm', %L, %L, 'active')$$,
    LEAST(pg_temp.id('alice'), pg_temp.id('mal')), GREATEST(pg_temp.id('alice'), pg_temp.id('mal'))));
PERFORM pg_temp.eq('alice ne voit que sa propre ligne de membre du DM',
  format($$SELECT count(*)::text FROM public.conversation_members WHERE conversation_id = %L$$, pg_temp.id('dm_ab')), '1');
PERFORM pg_temp.eq('modification directe d''une ligne de membre sans effet',
  format($$UPDATE public.conversation_members SET last_read_at = now() WHERE conversation_id = %L$$, pg_temp.id('dm_ab')), '0');
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('s''ajouter soi-même comme membre d''un DM est refusé',
  format($$INSERT INTO public.conversation_members (conversation_id, user_id) VALUES (%L, %L)$$, pg_temp.id('dm_ab'), pg_temp.id('mal')));

-- Édition / suppression : auteur seulement
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('bob ne peut pas modifier le message d''alice', format($$SELECT public.edit_message(%L, 'piraté')::text$$, pg_temp.id('m1')));
PERFORM pg_temp.denied('bob ne peut pas supprimer le message d''alice', format($$SELECT public.delete_message(%L)::text$$, pg_temp.id('m1')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('modification de plus de 2000 caractères refusée', format($$SELECT public.edit_message(%L, repeat('x', 2001))::text$$, pg_temp.id('m1')));
PERFORM pg_temp.ok('alice modifie son message', format($$SELECT public.edit_message(%L, 'Premier message corrigé')::text$$, pg_temp.id('m1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la version d''origine est conservée pour la modération',
  format($$SELECT content FROM public.message_original_content WHERE message_id = %L$$, pg_temp.id('m1')), 'Premier message');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice supprime son message', format($$SELECT public.delete_message(%L)::text$$, pg_temp.id('m1')));
PERFORM pg_temp.denied('un message supprimé ne se modifie plus', format($$SELECT public.edit_message(%L, 'retour')::text$$, pg_temp.id('m1')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('un message supprimé n''est plus lisible', format($$SELECT count(*)::text FROM public.messages WHERE id = %L$$, pg_temp.id('m1')), '0');
PERFORM pg_temp.ok('un message supprimé reste signalable', format($$SELECT public.create_report('message', %L, 'Raison de test suffisamment longue')::text$$, pg_temp.id('m1')));

-- Masquer / démasquer
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice masque le fil', format($$SELECT public.set_conversation_hidden(%L, true)::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.eq('un fil masqué disparaît de la liste',
  format($$SELECT count(*)::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('dm_ab')), '0');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob répond', format($$SELECT public.send_message(%L, 'Tu es là ?')::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('un nouveau message fait réapparaître le fil',
  format($$SELECT count(*)::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('dm_ab')), '1');

-- Pair suspendu, compte suspendu
PERFORM pg_temp.denied('pas de message vers un compte suspendu', format($$SELECT public.send_message(%L, 'x')::text$$, pg_temp.id('dm_alice_sam')));
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu ne peut pas écrire', format($$SELECT public.send_message(%L, 'x')::text$$, pg_temp.id('dm_alice_sam')));

-- Blocage dans un DM
PERFORM pg_temp.as_('b1');
PERFORM pg_temp.ok('b1 écrit à b2', format($$SELECT public.send_message(%L, 'avant blocage')::text$$, pg_temp.id('dm_b1_b2')));
PERFORM pg_temp.as_('b2');
PERFORM pg_temp.ok('b2 bloque b1', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('b2'), pg_temp.id('b1')));
PERFORM pg_temp.eq('après blocage, le bloqueur ne lit plus le fil',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L$$, pg_temp.id('dm_b1_b2')), '0');
PERFORM pg_temp.denied('le bloqueur ne peut plus écrire', format($$SELECT public.send_message(%L, 'x')::text$$, pg_temp.id('dm_b1_b2')));
PERFORM pg_temp.as_('b1');
PERFORM pg_temp.denied('la personne bloquée ne peut plus écrire', format($$SELECT public.send_message(%L, 'x')::text$$, pg_temp.id('dm_b1_b2')));
PERFORM pg_temp.eq('le fil bloqué disparaît de la liste du bloqué aussi',
  format($$SELECT count(*)::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('dm_b1_b2')), '0');
PERFORM pg_temp.eq('le contact bloqué disparaît des contacts',
  format($$SELECT count(*)::text FROM public.get_contacts() WHERE id = %L$$, pg_temp.id('b2')), '0');

-- Limite de débit : 15 messages par minute dans un DM
PERFORM pg_temp.as_('f1');
PERFORM pg_temp.eq('au-delà de 15 messages par minute dans un DM, refus',
  format($$SELECT pg_temp.ms_flood(%L, 20)$$, pg_temp.id('dm_f1_f2')), 'junto.dm_rate_limit');

-- ═════ Demandes (contact / participation) ═════
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.put('act_a', pg_temp.ok('alice crée une sortie',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie test messagerie', 'x', 'Tous niveaux', 6, -130.5, -45.5, NULL, NULL, now() + interval '2 days')::text$$));
PERFORM pg_temp.as_('rq1');
PERFORM pg_temp.ok('rq1 envoie une demande de contact à alice',
  format($$SELECT public.send_contact_request(%L, 'Salut alice')::text$$, pg_temp.id('alice')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
PERFORM pg_temp.put('p_rq1', pg_temp.run(format($$INSERT INTO public.participations (activity_id, user_id, status, created_at)
  VALUES (%L, %L, 'pending', now()) RETURNING id::text$$, pg_temp.id('act_a'), pg_temp.id('rq1'))));
PERFORM pg_temp.put('p_rq2', pg_temp.run(format($$INSERT INTO public.participations (activity_id, user_id, status, created_at)
  VALUES (%L, %L, 'pending', now()) RETURNING id::text$$, pg_temp.id('act_a'), pg_temp.id('rq2'))));
PERFORM set_config('junto.bypass_lock', 'false', true);

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('la demande de contact en attente reste en attente',
  format($$SELECT status FROM public.conversations WHERE user_1 = LEAST(%L::uuid, %L::uuid) AND user_2 = GREATEST(%L::uuid, %L::uuid)$$,
    pg_temp.id('alice'), pg_temp.id('rq1'), pg_temp.id('alice'), pg_temp.id('rq1')), 'pending_request');
PERFORM pg_temp.as_('rq2');
PERFORM pg_temp.eq('un fil logistique ne fait pas un contact',
  format($$SELECT count(*)::text FROM public.get_contacts() WHERE id = %L$$, pg_temp.id('alice')), '0');
PERFORM pg_temp.as_('mal');

-- ═════ Partages (sortie, trace) ═════
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice partage sa sortie dans le DM', format($$SELECT public.share_activity_message(%L, %L)::text$$, pg_temp.id('dm_ab'), pg_temp.id('act_a')));
PERFORM pg_temp.denied('un second partage dans la minute est refusé',
  format($$SELECT public.share_activity_message(%L, %L)::text$$, pg_temp.id('dm_ab'), pg_temp.id('act_a')), 'junto\.share_rate_limit');
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('un non-membre ne partage pas dans un DM',
  format($$SELECT public.share_activity_message(%L, %L)::text$$, pg_temp.id('dm_ab'), pg_temp.id('act_a')));
PERFORM pg_temp.as_('carol');
PERFORM pg_temp.put('act_cp', pg_temp.ok('carol crée une sortie privée',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie privée test', 'x', 'Tous niveaux', 6, -130.6, -45.6, NULL, NULL, now() + interval '3 days', '2 hours', 'private_link')::text$$));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('on ne partage pas la sortie privée d''autrui',
  format($$SELECT public.share_activity_message(%L, %L)::text$$, pg_temp.id('dm_bob_carol'), pg_temp.id('act_cp')));
PERFORM pg_temp.eq('IX-1 : bob ne voit pas la sortie privée de carol avant tout partage', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('act_cp')), '0');
PERFORM pg_temp.as_('carol');
PERFORM pg_temp.ok('carol partage sa sortie privée avec bob', format($$SELECT public.share_activity_message(%L, %L)::text$$, pg_temp.id('dm_bob_carol'), pg_temp.id('act_cp')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('IX-1 : partagée par l''organisatrice, la sortie privée s''ouvre chez bob', format($$SELECT count(*)::text FROM public.get_activity_detail(%L)$$, pg_temp.id('act_cp')), '1');
PERFORM pg_temp.put('m_trace', pg_temp.ok('bob partage une trace',
  format($$SELECT public.share_trace_message(%L, '{"type":"LineString","coordinates":[[6.6,44.9],[6.61,44.91,1200]]}'::jsonb, 'Ma <b>trace</b>')::text$$, pg_temp.id('dm_ab'))));
PERFORM pg_temp.denied('une carte partagée n''est pas modifiable', format($$SELECT public.edit_message(%L, 'texte')::text$$, pg_temp.id('m_trace')));
PERFORM pg_temp.as_('carol');
PERFORM pg_temp.denied('une trace qui n''est pas une ligne est refusée',
  format($$SELECT public.share_trace_message(%L, '{"type":"Point","coordinates":[6.6,44.9]}'::jsonb, 'x')::text$$, pg_temp.id('dm_bob_carol')));
PERFORM pg_temp.denied('une trace d''un seul point est refusée',
  format($$SELECT public.share_trace_message(%L, '{"type":"LineString","coordinates":[[6.6,44.9]]}'::jsonb, 'x')::text$$, pg_temp.id('dm_bob_carol')));
PERFORM pg_temp.denied('une trace hors des bornes géographiques est refusée',
  format($$SELECT public.share_trace_message(%L, '{"type":"LineString","coordinates":[[6.6,44.9],[1e300,44.9]]}'::jsonb, 'x')::text$$, pg_temp.id('dm_bob_carol')));
PERFORM pg_temp.denied('une trace partagée de plusieurs Mo est refusée',
  format($$SELECT public.share_trace_message(%L, jsonb_build_object('type', 'LineString', 'coordinates', '[[6.6,44.9],[6.61,44.91]]'::jsonb,
      'properties', jsonb_build_object('pad', repeat('x', 2000000))), 'grosse')::text$$, pg_temp.id('dm_bob_carol')),
  'junto\.trace_too_large');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('b2_heavy', (SELECT jsonb_build_object('type', 'LineString', 'coordinates', '[[6.6,44.9],[6.61,44.91]]'::jsonb,
  'properties', jsonb_build_object('pad', (SELECT string_agg(md5(g::text), '') FROM generate_series(1, 28000) g)))::text));
FOR i IN 1..5 LOOP
  PERFORM pg_temp.as_('carol');
  PERFORM pg_temp.ok('B2 : carol partage une trace lourde (< 1 Mo) n° ' || i,
    format($$SELECT public.share_trace_message(%L, %L::jsonb, 'lourde')::text$$, pg_temp.id('dm_bob_carol'), pg_temp.get('b2_heavy')));
  PERFORM pg_temp.as_('db');
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE public.messages SET created_at = created_at - interval '2 minutes'
  WHERE sender_id = pg_temp.id('carol') AND metadata->>'type' = 'shared_trace';
  PERFORM set_config('junto.bypass_lock', 'false', true);
END LOOP;
PERFORM pg_temp.as_('carol');
PERFORM pg_temp.denied('B2 : au-delà de 5 Mo de traces partagées en 24 h, refusé',
  format($$SELECT public.share_trace_message(%L, %L::jsonb, 'lourde')::text$$, pg_temp.id('dm_bob_carol'), pg_temp.get('b2_heavy')),
  'junto\.share_daily_cap');

-- ═════ Groupes ═════
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('un groupe exige au moins deux autres membres',
  format($$SELECT public.create_group('Duo', NULL, ARRAY[%L]::uuid[])::text$$, pg_temp.id('bob')), 'junto\.group_min_members');
PERFORM pg_temp.denied('un nom de groupe vide est refusé',
  format($$SELECT public.create_group('  ', NULL, ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('bob'), pg_temp.id('carol')), 'junto\.group_name_invalid');
PERFORM pg_temp.denied('plus de 19 membres invités est refusé',
  $$SELECT public.create_group('Foule', NULL, ARRAY(SELECT gen_random_uuid() FROM generate_series(1, 20)))::text$$, 'junto\.group_cap');
PERFORM pg_temp.denied('des inconnus ne peuvent pas être ajoutés à un groupe (filtrés en silence)',
  format($$SELECT public.create_group('Inconnus', NULL, ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('mal'), pg_temp.id('t9')), 'junto\.group_min_members');
PERFORM pg_temp.put('g1', pg_temp.ok('alice crée un groupe avec ses contacts',
  format($$SELECT public.create_group('<i>Grimpe</i>', NULL, ARRAY[%L, %L, %L, %L]::uuid[])::text$$,
    pg_temp.id('bob'), pg_temp.id('carol'), pg_temp.id('dave'), pg_temp.id('mal'))));

PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('le groupe compte 4 membres (l''inconnu est écarté)',
  format($$SELECT count(*)::text FROM public.get_group_info(%L)$$, pg_temp.id('g1')), '4');
PERFORM pg_temp.eq('le nom du groupe est nettoyé du HTML',
  format($$SELECT DISTINCT group_name FROM public.get_group_info(%L)$$, pg_temp.id('g1')), 'Grimpe');
PERFORM pg_temp.eq('bob est notifié de son ajout au groupe',
  $$SELECT count(*)::text FROM public.notifications WHERE type = 'group_added'$$, '1');
PERFORM pg_temp.eq('le groupe apparaît dans la liste de bob',
  format($$SELECT count(*)::text FROM public.get_my_conversations() WHERE id = %L$$, pg_temp.id('g1')), '1');
PERFORM pg_temp.denied('seul le créateur renomme le groupe',
  format($$SELECT public.rename_group(%L, 'Pirate', NULL)::text$$, pg_temp.id('g1')));
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.eq('un non-membre ne lit pas les infos du groupe',
  format($$SELECT count(*)::text FROM public.get_group_info(%L)$$, pg_temp.id('g1')), '0');
PERFORM pg_temp.denied('un non-membre n''écrit pas dans le groupe',
  format($$SELECT public.send_message(%L, 'intrus')::text$$, pg_temp.id('g1')));
PERFORM pg_temp.denied('un non-membre n''ajoute personne au groupe',
  format($$SELECT public.add_group_member(%L, %L)::text$$, pg_temp.id('g1'), pg_temp.id('mal')));

PERFORM pg_temp.as_('carol');
PERFORM pg_temp.ok('carol écrit dans le groupe', format($$SELECT public.send_message(%L, 'Salut le groupe')::text$$, pg_temp.id('g1')));

PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('le créateur renomme le groupe', format($$SELECT public.rename_group(%L, 'Grimpe 05', NULL)::text$$, pg_temp.id('g1')));
PERFORM pg_temp.denied('nom de groupe de plus de 60 caractères refusé',
  format($$SELECT public.rename_group(%L, repeat('x', 61), NULL)::text$$, pg_temp.id('g1')), 'junto\.group_name_invalid');
PERFORM pg_temp.denied('on ne s''ajoute pas soi-même', format($$SELECT public.add_group_member(%L, %L)::text$$, pg_temp.id('g1'), pg_temp.id('alice')));
PERFORM pg_temp.denied('on n''ajoute pas un compte suspendu', format($$SELECT public.add_group_member(%L, %L)::text$$, pg_temp.id('g1'), pg_temp.id('sam')));
PERFORM pg_temp.denied('on n''ajoute pas un inconnu', format($$SELECT public.add_group_member(%L, %L)::text$$, pg_temp.id('g1'), pg_temp.id('mal')));
PERFORM pg_temp.denied('insertion directe d''un membre de groupe refusée',
  format($$INSERT INTO public.conversation_members (conversation_id, user_id) VALUES (%L, %L)$$, pg_temp.id('g1'), pg_temp.id('mal')));
PERFORM pg_temp.ok('alice ajoute un contact (frank)', format($$SELECT public.add_group_member(%L, %L)::text$$, pg_temp.id('g1'), pg_temp.id('frank')));
PERFORM pg_temp.eq('le groupe compte 5 membres', format($$SELECT count(*)::text FROM public.get_group_info(%L)$$, pg_temp.id('g1')), '5');
PERFORM pg_temp.denied('leave_group refuse un fil qui n''est pas un groupe',
  format($$SELECT public.leave_group(%L)::text$$, pg_temp.id('dm_ab')));

-- Blocage dans un groupe (MS-1) et oracle de blocage entre tiers (MS-2)
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob bloque dave', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('bob'), pg_temp.id('dave')));
PERFORM pg_temp.ok('bob bloque erin', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('bob'), pg_temp.id('erin')));
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.ok('dave écrit dans le groupe', format($$SELECT public.send_message(%L, 'message de dave')::text$$, pg_temp.id('g1')));
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.eq('bob ne lit pas les messages de dave, qu''il a bloqué, dans un groupe',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L AND sender_id = %L$$, pg_temp.id('g1'), pg_temp.id('dave')), '0');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('ajouter un contact bloqué par un autre membre ne révèle pas le blocage (pas d''erreur)',
  format($$SELECT public.add_group_member(%L, %L)::text$$, pg_temp.id('g1'), pg_temp.id('erin')));
PERFORM pg_temp.as_('carol');
PERFORM pg_temp.denied('deux personnes qui se bloquent ne sont pas réunies dans un nouveau groupe',
  format($$SELECT public.create_group('Trio', NULL, ARRAY[%L, %L]::uuid[])::text$$, pg_temp.id('bob'), pg_temp.id('dave')), 'junto\.group_min_members');

-- Quitter
PERFORM pg_temp.ok('carol quitte le groupe', format($$SELECT public.leave_group(%L)::text$$, pg_temp.id('g1')));
PERFORM pg_temp.denied('après départ, carol n''écrit plus', format($$SELECT public.send_message(%L, 'encore là')::text$$, pg_temp.id('g1')));
PERFORM pg_temp.eq('après départ, carol ne lit plus les infos du groupe',
  format($$SELECT count(*)::text FROM public.get_group_info(%L)$$, pg_temp.id('g1')), '0');
PERFORM pg_temp.eq('après départ, carol ne lit plus les messages du groupe',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L$$, pg_temp.id('g1')), '0');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.denied('une personne qui a quitté un groupe ne peut pas y être remise aussitôt',
  format($$SELECT public.add_group_member(%L, %L)::text$$, pg_temp.id('g1'), pg_temp.id('carol')), '.');

-- Plafond journalier de création de groupes (5)
PERFORM pg_temp.eq('au-delà de 5 groupes créés par jour, refus',
  format($$SELECT pg_temp.ms_groups(6, ARRAY[%L, %L]::uuid[])$$, pg_temp.id('bob'), pg_temp.id('frank')), 'junto.group_rate_limit');

-- ═════ Canaux ═════
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.put('ch1', pg_temp.ok('frank crée un canal',
  $$SELECT conversation_id::text FROM public.create_channel('Canal test', -130, -45, 'Océan Pacifique', 35)$$));
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.eq('un canal proche existant est proposé au lieu d''un doublon',
  $$SELECT conversation_id::text || ':' || duplicate::text FROM public.create_channel('Autre canal', -130.01, -45, 'Océan', 35)$$,
  pg_temp.get('ch1') || ':true');
PERFORM pg_temp.denied('nom de canal de plus de 60 caractères refusé',
  $$SELECT conversation_id::text FROM public.create_channel(repeat('x', 61), -150, -50, 'Océan', 35, NULL, NULL, NULL, true)$$, 'junto\.channel_name');
PERFORM pg_temp.denied('rayon de canal hors paliers refusé',
  $$SELECT conversation_id::text FROM public.create_channel('Canal', -150, -50, 'Océan', 50, NULL, NULL, NULL, true)$$, 'junto\.channel_radius');
PERFORM pg_temp.denied('sport de canal inconnu refusé',
  $$SELECT conversation_id::text FROM public.create_channel('Canal', -150, -50, 'Océan', 35, 'pas-un-sport', NULL, NULL, true)$$, 'junto\.channel_sport');
PERFORM pg_temp.denied('position de canal invalide refusée',
  $$SELECT conversation_id::text FROM public.create_channel('Canal', -150, 100, 'Océan', 35, NULL, NULL, NULL, true)$$, 'junto\.channel_place');
PERFORM pg_temp.denied('photo de canal hors du stockage du projet refusée',
  $$SELECT conversation_id::text FROM public.create_channel('Canal', -150, -50, 'Océan', 35, NULL, NULL, 'https://evil.example/x.jpg', true)$$, 'junto\.channel_photo');

PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon ne cherche pas de canaux', $$SELECT count(*)::text FROM public.search_channels(NULL, NULL, -130, -45)$$);

PERFORM pg_temp.as_('mal');
PERFORM pg_temp.eq('la recherche trouve le canal',
  format($$SELECT count(*)::text FROM public.search_channels(NULL, NULL, -130, -45) WHERE conversation_id = %L$$, pg_temp.id('ch1')), '1');
PERFORM pg_temp.eq('get_channel : mal n''est pas membre',
  format($$SELECT is_member::text FROM public.get_channel(%L)$$, pg_temp.id('ch1')), 'false');
PERFORM pg_temp.eq('un non-membre ne voit pas la liste des membres',
  format($$SELECT count(*)::text FROM public.get_channel_members(%L)$$, pg_temp.id('ch1')), '0');
PERFORM pg_temp.denied('un non-membre n''écrit pas dans le canal', format($$SELECT public.send_message(%L, 'x')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.ok('mal rejoint le canal', format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.eq('get_channel : mal est membre', format($$SELECT is_member::text FROM public.get_channel(%L)$$, pg_temp.id('ch1')), 'true');
PERFORM pg_temp.eq('un membre voit la liste des membres', format($$SELECT count(*)::text FROM public.get_channel_members(%L)$$, pg_temp.id('ch1')), '2');
PERFORM pg_temp.put('m_mal', pg_temp.ok('mal écrit dans le canal', format($$SELECT public.send_message(%L, 'bonjour le canal')::text$$, pg_temp.id('ch1'))));
PERFORM pg_temp.denied('un membre ne renomme pas le canal', format($$SELECT public.rename_channel(%L, 'Pirate')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.denied('un membre ne change pas la photo du canal', format($$SELECT public.set_channel_photo(%L, NULL)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.denied('un membre ne ferme pas le canal', format($$SELECT public.close_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.denied('un membre n''exclut pas le créateur', format($$SELECT public.remove_channel_member(%L, %L)::text$$, pg_temp.id('ch1'), pg_temp.id('frank')));

PERFORM pg_temp.as_('frank');
PERFORM pg_temp.ok('le créateur renomme le canal', format($$SELECT public.rename_channel(%L, 'Canal renommé')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.denied('photo hors du dossier du créateur refusée',
  format($$SELECT public.set_channel_photo(%L, 'https://evil.example/x.jpg')::text$$, pg_temp.id('ch1')), 'junto\.channel_photo');
PERFORM pg_temp.ok('le créateur pose une photo de son dossier',
  format($$SELECT public.set_channel_photo(%L, %L)::text$$, pg_temp.id('ch1'),
    'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/channel-photos/' || pg_temp.get('frank') || '/photo.jpg'));
PERFORM pg_temp.put('m_frank', pg_temp.ok('frank écrit dans le canal', format($$SELECT public.send_message(%L, 'message du créateur')::text$$, pg_temp.id('ch1'))));
PERFORM pg_temp.ok('le créateur supprime le message d''un membre (modération)', format($$SELECT public.delete_message(%L)::text$$, pg_temp.id('m_mal')));
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('un membre ne supprime pas le message du créateur', format($$SELECT public.delete_message(%L)::text$$, pg_temp.id('m_frank')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.ok('le créateur exclut mal', format($$SELECT public.remove_channel_member(%L, %L)::text$$, pg_temp.id('ch1'), pg_temp.id('mal')));
PERFORM pg_temp.as_('mal');
PERFORM pg_temp.denied('un exclu n''écrit plus', format($$SELECT public.send_message(%L, 'retour')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.denied('un exclu ne peut pas revenir', format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.eq('un exclu ne voit plus le canal', format($$SELECT count(*)::text FROM public.get_channel(%L)$$, pg_temp.id('ch1')), '0');
PERFORM pg_temp.eq('un exclu ne trouve plus le canal',
  format($$SELECT count(*)::text FROM public.search_channels(NULL, NULL, -130, -45) WHERE conversation_id = %L$$, pg_temp.id('ch1')), '0');

-- Blocage dans un canal (MS-1)
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.ok('frank bloque t6', format($$INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (%L, %L)$$, pg_temp.id('frank'), pg_temp.id('t6')));
PERFORM pg_temp.as_('t6');
PERFORM pg_temp.ok('t6 rejoint le canal de frank', format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.ok('t6 écrit dans le canal', format($$SELECT public.send_message(%L, 'message de t6')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.eq('frank ne lit pas les messages de t6, qu''il a bloqué, dans un canal',
  format($$SELECT count(*)::text FROM public.messages WHERE conversation_id = %L AND sender_id = %L$$, pg_temp.id('ch1'), pg_temp.id('t6')), '0');
PERFORM pg_temp.eq('MS-1 : frank lit toujours les autres messages du canal',
  format($$SELECT (count(*) > 0)::text FROM public.messages WHERE conversation_id = %L AND sender_id IS DISTINCT FROM %L$$, pg_temp.id('ch1'), pg_temp.id('t6')), 'true');
PERFORM pg_temp.as_('t6');
PERFORM pg_temp.ok('t6 quitte le canal', format($$SELECT public.leave_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.eq('après départ, t6 n''est plus membre', format($$SELECT is_member::text FROM public.get_channel(%L)$$, pg_temp.id('ch1')), 'false');

PERFORM pg_temp.as_('t9');
PERFORM pg_temp.ok('un canal est signalable', format($$SELECT public.create_report('channel', %L, 'Raison de test suffisamment longue')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('m_adm', 'tos,admin');
PERFORM pg_temp.as_('m_adm');
PERFORM pg_temp.ok('l''admin ferme un canal signalé', format($$SELECT public.admin_remove_content('channel', %L, 'Contenu signalé, fermeture')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le canal signalé est fermé', format($$SELECT (closed_at IS NOT NULL)::text FROM public.channels WHERE conversation_id = %L$$, pg_temp.id('ch1')), 'true');
PERFORM pg_temp.as_('t9');

-- Fermeture
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.ok('le créateur ferme le canal', format($$SELECT public.close_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.denied('plus d''écriture dans un canal fermé', format($$SELECT public.send_message(%L, 'x')::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.as_('t9');
PERFORM pg_temp.denied('on ne rejoint pas un canal fermé', format($$SELECT public.join_channel(%L)::text$$, pg_temp.id('ch1')));
PERFORM pg_temp.eq('un canal fermé n''apparaît plus dans la recherche',
  format($$SELECT count(*)::text FROM public.search_channels(NULL, NULL, -130, -45) WHERE conversation_id = %L$$, pg_temp.id('ch1')), '0');
PERFORM pg_temp.as_('frank');
PERFORM pg_temp.eq('au-delà de 5 canaux par jour, refus',
  $$SELECT (pg_temp.ms_channels(6) ~ '^junto\.channel_(cap|rate_limit)$')::text$$, 'true');

-- ═════ Notifications ═════
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.put('bob_notifs', pg_temp.ok('bob compte ses notifications', $$SELECT count(*)::text FROM public.notifications$$));
PERFORM pg_temp.eq('bob a bien des notifications', format($$SELECT (%L::int > 0)::text$$, pg_temp.get('bob_notifs')), 'true');
PERFORM pg_temp.eq('bob marque ses notifications comme lues',
  $$WITH u AS (UPDATE public.notifications SET read_at = now() RETURNING 1) SELECT (count(*) > 0)::text FROM u$$, 'true');
PERFORM pg_temp.ok('bob tente de réécrire le titre et le destinataire',
  format($$UPDATE public.notifications SET title = 'pwn', body = 'pwn', user_id = %L$$, pg_temp.id('alice')));
PERFORM pg_temp.denied('bob ne crée pas de notification',
  format($$INSERT INTO public.notifications (user_id, type, title, body) VALUES (%L, 'x', 'x', 'x')$$, pg_temp.id('bob')));
PERFORM pg_temp.eq('bob ne supprime pas ses notifications', $$DELETE FROM public.notifications$$, '0');
PERFORM pg_temp.denied('create_notification n''est pas appelable par un client',
  format($$SELECT public.create_notification(%L, 'x', 'x', 'x')::text$$, pg_temp.id('alice')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('les notifications de bob restent à bob', format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L$$, pg_temp.id('bob')), pg_temp.get('bob_notifs'));
PERFORM pg_temp.eq('seul read_at est modifiable (titre inchangé)',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND (title = 'pwn' OR body = 'pwn')$$, pg_temp.id('bob')), '0');
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.eq('alice ne voit pas les notifications de bob',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L$$, pg_temp.id('bob')), '0');
PERFORM pg_temp.eq('alice ne modifie pas les notifications de bob',
  format($$UPDATE public.notifications SET read_at = NULL WHERE user_id = %L$$, pg_temp.id('bob')), '0');
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.eq('anon ne lit aucune notification', $$SELECT count(*)::text FROM public.notifications$$, '0');

-- ═════ Jetons push ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('anon n''enregistre pas de jeton push', $$SELECT public.register_push_token('ExponentPushToken[junto-test-anon-001]')::text$$);
PERFORM pg_temp.as_('sam');
PERFORM pg_temp.denied('un compte suspendu n''enregistre pas de jeton push', $$SELECT public.register_push_token('ExponentPushToken[junto-test-sam-0001]')::text$$);
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('jeton push au mauvais format refusé', $$SELECT public.register_push_token('pas-un-jeton-push-valide-du-tout')::text$$);
PERFORM pg_temp.ok('bob enregistre son jeton push', $$SELECT public.register_push_token('ExponentPushToken[junto-test-bob-0001]', 'dev-bob')::text$$);
PERFORM pg_temp.eq('les jetons push ne sont pas lisibles par le client', $$SELECT count(*)::text FROM public.push_tokens$$, '0');
PERFORM pg_temp.denied('insertion directe d''un jeton push refusée',
  format($$INSERT INTO public.push_tokens (user_id, token) VALUES (%L, 'ExponentPushToken[junto-test-direct]')$$, pg_temp.id('bob')));
PERFORM pg_temp.as_('carol');
PERFORM pg_temp.ok('carol enregistre son jeton push', $$SELECT public.register_push_token('ExponentPushToken[junto-test-carol-01]')::text$$);
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le jeton de bob est enregistré',
  format($$SELECT count(*)::text FROM public.push_tokens WHERE user_id = %L$$, pg_temp.id('bob')), '1');
PERFORM pg_temp.eq('le jeton de carol n''est pas révoqué par bob',
  format($$SELECT count(*)::text FROM public.push_tokens WHERE user_id = %L$$, pg_temp.id('carol')), '1');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.ok('bob révoque le jeton de son appareil', $$SELECT public.revoke_push_token_for_device('dev-bob')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le jeton de l''appareil de bob est retiré',
  format($$SELECT count(*)::text FROM public.push_tokens WHERE user_id = %L$$, pg_temp.id('bob')), '0');

PERFORM pg_temp.as_('alice');

-- ═════ Invitations à une sortie : un refus doit tenir (MS-3) ═════
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice invite dave à sa sortie',
  format($$SELECT public.send_activity_invitations(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('act_a'), pg_temp.id('dave')));
PERFORM pg_temp.as_('dave');
PERFORM pg_temp.ok('dave refuse l''invitation', format($$SELECT public.decline_activity_invitation(%L)::text$$, pg_temp.id('act_a')));
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice réinvite dave', format($$SELECT public.send_activity_invitations(%L, ARRAY[%L]::uuid[])::text$$, pg_temp.id('act_a'), pg_temp.id('dave')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('une invitation refusée ne peut pas être renvoyée aussitôt',
  format($$SELECT count(*)::text FROM public.participations WHERE activity_id = %L AND user_id = %L AND status = 'invited'$$, pg_temp.id('act_a'), pg_temp.id('dave')),
  '0');

-- ═════ Demande de place vs demande de contact refusée (IX-2 / BR-1) ═════
PERFORM pg_temp.as_('carol');
PERFORM pg_temp.put('act_c', pg_temp.ok('carol crée une sortie publique',
  $$SELECT public.create_activity((SELECT id FROM public.sports WHERE key = 'hiking'), 'Sortie covoit test', 'x', 'Tous niveaux', 6, -130.7, -45.7, NULL, NULL, now() + interval '2 days')::text$$));
PERFORM pg_temp.as_('r1');
PERFORM pg_temp.put('dm_r1c', pg_temp.ok('r1 envoie une demande de contact à carol',
  format($$SELECT public.send_contact_request(%L, 'Salut carol')::text$$, pg_temp.id('carol'))));
PERFORM pg_temp.as_('carol');
PERFORM pg_temp.ok('carol refuse', format($$SELECT public.decline_contact_request(%L)::text$$, pg_temp.id('dm_r1c')));
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
PERFORM pg_temp.run(format($$INSERT INTO public.participations (activity_id, user_id, status, created_at) VALUES (%L, %L, 'accepted', now())$$,
  pg_temp.id('act_c'), pg_temp.id('r1')));
PERFORM pg_temp.run(format($$UPDATE public.participations SET transport_type = 'car', transport_seats = 3 WHERE activity_id = %L AND user_id = %L$$,
  pg_temp.id('act_c'), pg_temp.id('carol')));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('r1');
PERFORM pg_temp.ok('r1 demande une place à carol', format($$SELECT public.request_seat(%L, %L)::text$$, pg_temp.id('act_c'), pg_temp.id('carol')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('une demande de place ne rouvre pas une demande de contact refusée',
  format($$SELECT status FROM public.conversations WHERE id = %L$$, pg_temp.id('dm_r1c')), 'declined');
PERFORM pg_temp.eq('IX-2 : carol est quand même notifiée de la demande de place',
  format($$SELECT count(*)::text FROM public.notifications WHERE user_id = %L AND type = 'seat_request'$$, pg_temp.id('carol')), '1');

-- ═════ Plafond journalier de messages (AB-3) ═════
PERFORM pg_temp.as_('s1');
PERFORM pg_temp.put('ch_s1', pg_temp.ok('s1 crée un canal',
  $$SELECT conversation_id::text FROM public.create_channel('Canal s1', -140, -50, 'Océan', 35, NULL, NULL, NULL, true)$$));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.run(format($$INSERT INTO public.messages (conversation_id, sender_id, content, created_at)
  SELECT %L, %L, 'ancien ' || g, now() - interval '2 hours' FROM generate_series(1, 2000) g$$, pg_temp.id('ch_s1'), pg_temp.id('s1')));
PERFORM pg_temp.as_('s1');
PERFORM pg_temp.denied('après 2000 messages dans la journée, un plafond s''applique',
  format($$SELECT public.send_message(%L, 'encore un')::text$$, pg_temp.id('ch_s1')), '.');

-- ═════ Contenu des push de message (MS-5) ═════
-- request_seat (miroir legacy) laisse junto.skip_message_push actif pour la fin de la transaction : on le remet.
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.skip_message_push', 'false', true);
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('alice envoie un message avec un caractère de contrôle',
  format($$SELECT public.send_message(%L, %L)::text$$, pg_temp.id('dm_alice_carol'), 'Bonjour' || chr(1) || 'MS5MARK'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le texte du push de message est nettoyé (caractères de contrôle)',
  $$SELECT coalesce(bool_and(strpos(convert_from(body, 'UTF8'), '\u0001') = 0)::text, 'no push')
    FROM net.http_request_queue WHERE convert_from(body, 'UTF8') LIKE '%MS5MARK%'$$, 'true');

-- ═════ Retirer un contact ═════
PERFORM pg_temp.as_('alice');
PERFORM pg_temp.ok('retirer un non-contact est sans effet', format($$SELECT public.remove_connection(%L)::text$$, pg_temp.id('mal')));
PERFORM pg_temp.ok('retirer un fil logistique est sans effet', format($$SELECT public.remove_connection(%L)::text$$, pg_temp.id('rq2')));
PERFORM pg_temp.ok('alice retire bob de ses contacts', format($$SELECT public.remove_connection(%L)::text$$, pg_temp.id('bob')));
PERFORM pg_temp.eq('bob n''est plus dans les contacts d''alice',
  format($$SELECT count(*)::text FROM public.get_contacts() WHERE id = %L$$, pg_temp.id('bob')), '0');
PERFORM pg_temp.as_('bob');
PERFORM pg_temp.denied('bob ne peut plus écrire dans l''ancien fil', format($$SELECT public.send_message(%L, 'x')::text$$, pg_temp.id('dm_ab')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('le fil retiré est supprimé', format($$SELECT count(*)::text FROM public.conversations WHERE id = %L$$, pg_temp.id('dm_ab')), '0');
PERFORM pg_temp.eq('le fil retiré est archivé pour la modération',
  format($$SELECT count(*)::text FROM public.contact_removal_archive WHERE conversation_id = %L$$, pg_temp.id('dm_ab')), '1');
