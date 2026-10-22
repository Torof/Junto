-- ============================================================================
-- 00469 — Audit octobre 2026, phase 2 : contacts et QR (docs/AUDIT_2026-10.md
-- M2, M3, M4, L1, L2, L5). Décision Scott 2026-10-21 : uniquement des
-- corrections invisibles, le QR fonctionne exactement comme avant.
-- Base = définitions vivantes (00456 pour le QR, remove_connection live).
--
-- M2  Jeton QR : durée de vie 10 min → 2 min (l'écran le rafraîchit toutes les
--     60 s) + revoke_contact_qr_tokens() appelé à la fermeture de l'écran. Une
--     capture relayée est morte avant d'être scannée ; le scan à plusieurs en
--     face à face marche toujours (pas d'usage unique). Quota de création
--     30/h → 120/h (un rafraîchissement par minute écran ouvert). Les jetons
--     révoqués ou expirés restent comptés une heure (balayage sur created_at).
-- M3  Un scan active toujours une demande en attente ou refusée, mais ne
--     republie le message de demande QUE si elle était en attente. Le lien
--     d'invitation à une sortie (pending_activity_id) est consommé.
-- L1  Les échecs comptent dans le quota de scans : plus de RAISE après
--     l'insertion du quota (qui annulait la ligne) — RETURN NULL, même signal
--     générique pour toutes les causes (inconnu, expiré, bloqué, suspendu, démo).
-- L2  p_expected_owner (facultatif) : l'app passe l'identifiant affiché dans le
--     QR ; s'il ne correspond pas au propriétaire du jeton → NULL.
-- L5  Un compte démo ne peut pas scanner (rideau démo côté écriture).
-- M4  « Retirer de mes contacts » efface toujours le fil des deux côtés (rien ne
--     change à l'écran), mais son contenu est d'abord archivé dans
--     contact_removal_archive (admin seulement, 90 jours) : un harceleur qui se
--     retire ne détruit plus les preuves d'un signalement.
-- ============================================================================

-- ---------- M2 : création ----------
CREATE OR REPLACE FUNCTION public.create_contact_qr_token()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_token TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND (suspended_at IS NOT NULL OR is_demo)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_qr_token'));
  -- Keep revoked/expired rows for an hour so they still count in the quota.
  DELETE FROM contact_qr_tokens WHERE user_id = v_user_id AND created_at < now() - INTERVAL '1 hour';
  SELECT count(*) INTO v_count FROM contact_qr_tokens
  WHERE user_id = v_user_id AND created_at > now() - INTERVAL '1 hour';
  IF v_count >= 120 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;

  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  INSERT INTO contact_qr_tokens (token, user_id, expires_at)
  VALUES (v_token, v_user_id, now() + INTERVAL '2 minutes');
  RETURN v_token;
END;
$function$;

-- ---------- M2 : révocation à la fermeture de l'écran ----------
CREATE OR REPLACE FUNCTION public.revoke_contact_qr_tokens()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- Own tokens only; no suspension check needed (revoking only removes power).
  UPDATE contact_qr_tokens SET expires_at = now()
  WHERE user_id = v_user_id AND expires_at > now();
END;
$function$;
REVOKE ALL ON FUNCTION public.revoke_contact_qr_tokens() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_contact_qr_tokens() TO authenticated;

-- ---------- M3 / L1 / L2 / L5 : scan ----------
DROP FUNCTION IF EXISTS public.connect_via_qr_token(text);
CREATE OR REPLACE FUNCTION public.connect_via_qr_token(p_token text, p_expected_owner uuid DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_owner UUID;
  v_user_1 UUID;
  v_user_2 UUID;
  v_conv RECORD;
  v_conversation_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- L5: a suspended or demo account never scans.
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND (suspended_at IS NOT NULL OR is_demo)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Scan quota first. From here on, every failure RETURNs NULL instead of
  -- raising, so the quota row is kept and failed attempts count too (L1).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_qr_scan'));
  DELETE FROM contact_qr_scans WHERE user_id = v_user_id AND scanned_at < now() - INTERVAL '1 hour';
  SELECT count(*) INTO v_count FROM contact_qr_scans WHERE user_id = v_user_id;
  IF v_count >= 30 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO contact_qr_scans (user_id) VALUES (v_user_id);

  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN NULL; END IF;

  -- Opportunistic sweep of long-dead tokens (anyone's).
  DELETE FROM contact_qr_tokens WHERE created_at < now() - INTERVAL '1 day';

  SELECT user_id INTO v_owner FROM contact_qr_tokens
  WHERE token = p_token AND expires_at > now();
  IF v_owner IS NULL OR v_owner = v_user_id THEN RETURN NULL; END IF;
  -- L2: the id printed in the QR must be the token's owner.
  IF p_expected_owner IS NOT NULL AND p_expected_owner <> v_owner THEN RETURN NULL; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_owner AND suspended_at IS NULL AND is_demo = false
  ) THEN
    RETURN NULL;
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_owner)
       OR (blocker_id = v_owner AND blocked_id = v_user_id)
  ) THEN
    RETURN NULL;
  END IF;

  IF v_user_id < v_owner THEN
    v_user_1 := v_user_id; v_user_2 := v_owner;
  ELSE
    v_user_1 := v_owner; v_user_2 := v_user_id;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_user_1::text || '_' || v_user_2::text || '_dm'));

  SELECT * INTO v_conv FROM conversations
  WHERE type = 'dm' AND user_1 = v_user_1 AND user_2 = v_user_2
  FOR UPDATE;

  IF v_conv.id IS NOT NULL THEN
    IF v_conv.status = 'active' THEN RETURN v_conv.id; END IF;
    UPDATE conversations
    SET status = 'active', request_expires_at = NULL, last_message_at = now()
    WHERE id = v_conv.id;
    -- M3: only a request that was still pending carries a message worth
    -- opening the thread with; a declined one stays unpublished.
    IF v_conv.status = 'pending_request'
       AND v_conv.request_sender_id IS NOT NULL
       AND v_conv.request_message IS NOT NULL
       AND char_length(trim(v_conv.request_message)) > 0 THEN
      INSERT INTO messages (conversation_id, sender_id, content, created_at)
      VALUES (v_conv.id, v_conv.request_sender_id, v_conv.request_message, now());
    END IF;
    -- M3: a pending outing-invite link is consumed (it was never meant to
    -- ride on a QR connection).
    IF v_conv.pending_activity_id IS NOT NULL THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE conversations SET pending_activity_id = NULL WHERE id = v_conv.id;
      PERFORM set_config('junto.bypass_lock', 'false', true);
    END IF;
    RETURN v_conv.id;
  END IF;

  INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, created_at, last_message_at)
  VALUES (v_user_1, v_user_2, v_user_id, 'active', 'profile', NULL, now(), now())
  RETURNING id INTO v_conversation_id;

  RETURN v_conversation_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.connect_via_qr_token(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.connect_via_qr_token(text, uuid) TO authenticated;

-- ---------- M4 : archive avant retrait ----------
CREATE TABLE IF NOT EXISTS contact_removal_archive (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL,
  user_1 UUID NOT NULL,
  user_2 UUID NOT NULL,
  removed_by UUID NOT NULL,
  removed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  messages JSONB NOT NULL DEFAULT '[]'::jsonb
);
ALTER TABLE contact_removal_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_removal_archive FORCE ROW LEVEL SECURITY;
REVOKE ALL ON contact_removal_archive FROM PUBLIC, anon, authenticated;
CREATE INDEX IF NOT EXISTS contact_removal_archive_removed_at_idx ON contact_removal_archive (removed_at);

CREATE OR REPLACE FUNCTION public.remove_connection(p_other_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only a genuine social connection can be removed here — never a transport /
  -- request_reply logistics thread.
  SELECT id, user_1, user_2 INTO v_conv
  FROM conversations
  WHERE type = 'dm'
    AND status = 'active'
    AND initiated_from IN ('profile', 'discovery', 'invite')
    AND ((user_1 = v_user_id AND user_2 = p_other_user_id)
      OR (user_1 = p_other_user_id AND user_2 = v_user_id));
  IF v_conv.id IS NULL THEN RETURN; END IF;

  -- A live carpool between the pair would be stranded (accepted seat + reservation)
  -- if we deleted the shared thread. Ask the user to settle it first.
  IF EXISTS (
    SELECT 1 FROM seat_requests s
    WHERE s.status IN ('pending', 'accepted')
      AND ((s.driver_id = v_user_id AND s.requester_id = p_other_user_id)
        OR (s.driver_id = p_other_user_id AND s.requester_id = v_user_id))
  ) THEN
    RAISE EXCEPTION 'junto.carpool_active';
  END IF;

  -- 00469 (audit M4): keep the thread for moderation before it disappears.
  INSERT INTO contact_removal_archive (conversation_id, user_1, user_2, removed_by, messages)
  SELECT v_conv.id, v_conv.user_1, v_conv.user_2, v_user_id,
         COALESCE(jsonb_agg(jsonb_build_object(
           'id', m.id, 'sender_id', m.sender_id, 'content', m.content, 'created_at', m.created_at
         ) ORDER BY m.created_at), '[]'::jsonb)
  FROM messages m WHERE m.conversation_id = v_conv.id;

  DELETE FROM conversations WHERE id = v_conv.id;
END;
$function$;

CREATE OR REPLACE FUNCTION purge_contact_removal_archive()
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  DELETE FROM contact_removal_archive WHERE removed_at < now() - INTERVAL '90 days';
$$;
REVOKE ALL ON FUNCTION purge_contact_removal_archive() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule('junto-contact-archive-purge')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'junto-contact-archive-purge');
SELECT cron.schedule('junto-contact-archive-purge', '30 4 * * *', 'SELECT public.purge_contact_removal_archive();');
