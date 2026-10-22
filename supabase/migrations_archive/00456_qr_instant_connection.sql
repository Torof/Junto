-- ============================================================================
-- 00456 — QR scan = instant connection (Scott 2026-10-16, « je te laisse faire »).
--
-- Face to face, « ajoute-moi » must be ONE gesture. Showing your QR is an
-- explicit consent, scanning it is the other one — so the scan opens the
-- conversation directly, without the request → accept round trip. A link
-- shared by message proves no co-presence and keeps the request flow.
--
-- The QR therefore carries a SHORT-LIVED TOKEN (10 min, rotated by the screen),
-- not the bare user id: a screenshot or a forwarded QR dies quickly, and the
-- static /u/<id> link stays what it was (profile → request).
--
--   contact_qr_tokens              internal (no grants), token · owner · expiry
--   contact_qr_scans               internal, per-user scan quota log
--   create_contact_qr_token()      RPC — my current token (30 / h)
--   connect_via_qr_token(p_token)  RPC — the scanner's side (30 / h)
--
-- Invariant 00072 amended, same spirit as reply_to_request: « never an active
-- DM without the consent of both » — token issuance = the owner's consent,
-- the scan = the scanner's. The DM is tagged initiated_from = 'profile' (a
-- social origin: get_contacts / remove_connection / discovery state all keep
-- working unchanged); request_sender_id stays NULL so it never counts against
-- anyone's request caps. No notification: the owner is standing right there,
-- and the conversation appears in their Messages.
-- ============================================================================

CREATE TABLE contact_qr_tokens (
  token      TEXT PRIMARY KEY CHECK (token ~ '^[0-9a-f]{64}$'),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX contact_qr_tokens_user_idx ON contact_qr_tokens(user_id, created_at DESC);
ALTER TABLE contact_qr_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_qr_tokens FORCE ROW LEVEL SECURITY;
REVOKE ALL ON contact_qr_tokens FROM anon, authenticated;

CREATE TABLE contact_qr_scans (
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  scanned_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX contact_qr_scans_user_idx ON contact_qr_scans(user_id, scanned_at DESC);
ALTER TABLE contact_qr_scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_qr_scans FORCE ROW LEVEL SECURITY;
REVOKE ALL ON contact_qr_scans FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- create_contact_qr_token — auth · not suspended · not demo · 30 tokens /
-- rolling hour (advisory lock) · 10-minute validity · 256-bit random token.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_contact_qr_token()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  DELETE FROM contact_qr_tokens WHERE user_id = v_user_id AND expires_at < now();
  SELECT count(*) INTO v_count FROM contact_qr_tokens
  WHERE user_id = v_user_id AND created_at > now() - INTERVAL '1 hour';
  IF v_count >= 30 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;

  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  INSERT INTO contact_qr_tokens (token, user_id, expires_at)
  VALUES (v_token, v_user_id, now() + INTERVAL '10 minutes');
  RETURN v_token;
END;
$$;

REVOKE ALL ON FUNCTION create_contact_qr_token() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION create_contact_qr_token() FROM anon;
GRANT EXECUTE ON FUNCTION create_contact_qr_token() TO authenticated;

-- ----------------------------------------------------------------------------
-- connect_via_qr_token — the scanner. Chain:
--   auth · not suspended · 30 scans / rolling hour · token shape · token live
--   (unknown / expired → generic) · owner ≠ me · owner not suspended, not demo
--   · no block either way · pair lock · existing DM: active → returned as is,
--   pending / declined → activated (request message becomes the first message,
--   as accept_contact_request does) · none → created ACTIVE, 'profile',
--   request_sender_id NULL · member rows via trg_dm_member_rows.
-- Returns the conversation id.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION connect_via_qr_token(p_token TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Scan quota first (also bounds any guessing, however hopeless at 256 bits).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_qr_scan'));
  DELETE FROM contact_qr_scans WHERE user_id = v_user_id AND scanned_at < now() - INTERVAL '1 hour';
  SELECT count(*) INTO v_count FROM contact_qr_scans WHERE user_id = v_user_id;
  IF v_count >= 30 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO contact_qr_scans (user_id) VALUES (v_user_id);

  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Opportunistic sweep of long-dead tokens (anyone's).
  DELETE FROM contact_qr_tokens WHERE expires_at < now() - INTERVAL '1 day';

  SELECT user_id INTO v_owner FROM contact_qr_tokens
  WHERE token = p_token AND expires_at > now();
  IF v_owner IS NULL OR v_owner = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_owner AND suspended_at IS NULL AND is_demo = false
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_owner)
       OR (blocker_id = v_owner AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
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
    -- A pending or declined request between the two: both consents are now
    -- on the table, activate it the way accept_contact_request does.
    UPDATE conversations
    SET status = 'active', request_expires_at = NULL, last_message_at = now()
    WHERE id = v_conv.id;
    IF v_conv.request_sender_id IS NOT NULL
       AND v_conv.request_message IS NOT NULL
       AND char_length(trim(v_conv.request_message)) > 0 THEN
      INSERT INTO messages (conversation_id, sender_id, content, created_at)
      VALUES (v_conv.id, v_conv.request_sender_id, v_conv.request_message, now());
    END IF;
    RETURN v_conv.id;
  END IF;

  INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, created_at, last_message_at)
  VALUES (v_user_1, v_user_2, v_user_id, 'active', 'profile', NULL, now(), now())
  RETURNING id INTO v_conversation_id;

  RETURN v_conversation_id;
END;
$$;

REVOKE ALL ON FUNCTION connect_via_qr_token(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION connect_via_qr_token(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION connect_via_qr_token(TEXT) TO authenticated;
