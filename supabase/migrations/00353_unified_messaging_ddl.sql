-- ============================================================================
-- 00353 — Unified messaging: DDL + data migration (brique 2, part 1).
-- Spec: docs/sprint-messaging.md §6 + validated chains lots ①-⑤.
--
-- Extends `conversations` (type dm/group/activity), creates
-- `conversation_members` (uniform membership + read-state + hidden) and
-- `messages` (single store), migrates existing DM/wall data, backfills
-- member rows. Old tables are dropped in a LATER migration (after client OTA).
-- Whitelist UPDATE triggers: consciously deferred to the post-code audit —
-- no client write grants exist on any of the three tables (writes are
-- SECURITY DEFINER only), so the trigger layer is pure defense-in-depth.
-- ============================================================================

-- ---------- 1. conversations: extension ----------
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'dm',
  ADD COLUMN IF NOT EXISTS activity_id UUID REFERENCES activities(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS name TEXT,
  ADD COLUMN IF NOT EXISTS icon TEXT,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE conversations ALTER COLUMN user_1 DROP NOT NULL;
ALTER TABLE conversations ALTER COLUMN user_2 DROP NOT NULL;
ALTER TABLE conversations ALTER COLUMN initiated_by DROP NOT NULL;

-- Per-type shape constraints (reviewer C5 set). Existing rows are all dm.
ALTER TABLE conversations
  ADD CONSTRAINT conversations_type_check
    CHECK (type IN ('dm', 'group', 'activity', 'channel')),
  ADD CONSTRAINT conversations_dm_pair_check
    CHECK ((type = 'dm') = (user_1 IS NOT NULL AND user_2 IS NOT NULL)),
  ADD CONSTRAINT conversations_dm_ordered_check
    CHECK (type <> 'dm' OR user_1 < user_2),
  ADD CONSTRAINT conversations_activity_check
    CHECK ((type = 'activity') = (activity_id IS NOT NULL)),
  ADD CONSTRAINT conversations_group_name_check
    CHECK ((type = 'group') = (name IS NOT NULL)),
  ADD CONSTRAINT conversations_name_len_check
    CHECK (name IS NULL OR char_length(name) BETWEEN 1 AND 60),
  ADD CONSTRAINT conversations_icon_len_check
    CHECK (icon IS NULL OR char_length(icon) BETWEEN 1 AND 8),
  ADD CONSTRAINT conversations_status_by_type_check
    CHECK (
      (type = 'dm' AND status IN ('pending_request', 'active', 'declined'))
      OR (type <> 'dm' AND status = 'active')
    );

CREATE UNIQUE INDEX IF NOT EXISTS conversations_activity_unique
  ON conversations (activity_id) WHERE activity_id IS NOT NULL;

-- ---------- 2. conversation_members ----------
CREATE TABLE conversation_members (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  added_by UUID REFERENCES users(id) ON DELETE SET NULL,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_read_at TIMESTAMPTZ,
  hidden_at TIMESTAMPTZ,
  PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX conversation_members_user_idx ON conversation_members (user_id);
ALTER TABLE conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_members FORCE ROW LEVEL SECURITY;
-- Own rows only (no read receipts — Scott arbitrage #5). No write policies:
-- every write goes through SECURITY DEFINER functions.
CREATE POLICY conversation_members_select_own ON conversation_members
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE ALL ON conversation_members FROM anon;
GRANT SELECT ON conversation_members TO authenticated;

-- ---------- 3. helpers (private schema — policy-safe cross-table checks) ----------
CREATE OR REPLACE FUNCTION private.is_conversation_member(p_conversation_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM conversation_members
    WHERE conversation_id = p_conversation_id AND user_id = p_user_id
  );
$$;
REVOKE ALL ON FUNCTION private.is_conversation_member(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.is_conversation_member(UUID, UUID) TO authenticated, anon;

-- Per-type author visibility (wall parity 00324): in ACTIVITY conversations a
-- message whose author is blocked by the viewer, or suspended, is hidden.
-- DM/group: author always visible (dm blocks gate at send; group = WhatsApp choice).
CREATE OR REPLACE FUNCTION private.message_author_visible(p_conversation_id UUID, p_sender_id UUID, p_viewer_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_sender_id IS NULL THEN TRUE
    WHEN NOT EXISTS (SELECT 1 FROM conversations c WHERE c.id = p_conversation_id AND c.type = 'activity') THEN TRUE
    ELSE (
      NOT EXISTS (
        SELECT 1 FROM blocked_users
        WHERE blocker_id = p_viewer_id AND blocked_id = p_sender_id
      )
      AND NOT private.user_is_suspended(p_sender_id)
    )
  END;
$$;
REVOKE ALL ON FUNCTION private.message_author_visible(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.message_author_visible(UUID, UUID, UUID) TO authenticated, anon;

-- ---------- 4. messages ----------
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES users(id) ON DELETE SET NULL,
  content TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 2000),
  metadata JSONB,
  reply_to_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX messages_conversation_created_idx ON messages (conversation_id, created_at DESC);
CREATE INDEX messages_sender_idx ON messages (sender_id);
CREATE INDEX messages_reply_to_idx ON messages (reply_to_message_id) WHERE reply_to_message_id IS NOT NULL;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages FORCE ROW LEVEL SECURITY;
CREATE POLICY messages_select_member ON messages
  FOR SELECT TO authenticated USING (
    deleted_at IS NULL
    AND private.is_conversation_member(conversation_id, auth.uid())
    AND private.message_author_visible(conversation_id, sender_id, auth.uid())
  );
REVOKE ALL ON messages FROM anon;
GRANT SELECT ON messages TO authenticated;

-- Strip-HTML on write (port of the 00006 pattern).
CREATE OR REPLACE FUNCTION strip_html_messages()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.content := regexp_replace(NEW.content, '<[^>]*>', '', 'g');
  RETURN NEW;
END;
$$;
CREATE TRIGGER messages_strip_html
  BEFORE INSERT OR UPDATE OF content ON messages
  FOR EACH ROW EXECUTE FUNCTION strip_html_messages();

-- ---------- 5. data migration (near-empty prod: testers inactive, demo has no messages) ----------
-- 5a. Member rows for existing DM conversations (both users, joined at creation;
--     port hidden_by_* into per-member hidden_at).
INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at, hidden_at)
SELECT c.id, c.user_1, NULL, c.created_at,
       CASE WHEN c.hidden_by_user_1 THEN now() ELSE NULL END
FROM conversations c WHERE c.type = 'dm' AND c.user_1 IS NOT NULL
ON CONFLICT DO NOTHING;
INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at, hidden_at)
SELECT c.id, c.user_2, NULL, c.created_at,
       CASE WHEN c.hidden_by_user_2 THEN now() ELSE NULL END
FROM conversations c WHERE c.type = 'dm' AND c.user_2 IS NOT NULL
ON CONFLICT DO NOTHING;

-- 5b. Activity conversations for ALL existing activities (soft-deleted included —
--     harmless, the hub filters; keeps any old wall history addressable).
INSERT INTO conversations (type, activity_id, status, created_at, last_message_at)
SELECT 'activity', a.id, 'active', a.created_at, NULL
FROM activities a
ON CONFLICT (activity_id) WHERE activity_id IS NOT NULL DO NOTHING;

-- 5c. Activity member rows from ACCEPTED participations (creator included via
--     his own accepted row — the no-special-case rule).
INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
SELECT c.id, p.user_id, NULL, p.created_at
FROM participations p
JOIN conversations c ON c.activity_id = p.activity_id
WHERE p.status = 'accepted'
ON CONFLICT DO NOTHING;

-- 5d. Messages: private first (keep ids so reply FKs survive), then walls.
INSERT INTO messages (id, conversation_id, sender_id, content, metadata, reply_to_message_id, edited_at, deleted_at, created_at)
SELECT pm.id, pm.conversation_id, pm.sender_id, pm.content, pm.metadata,
       pm.reply_to_message_id, pm.edited_at, pm.deleted_at, pm.created_at
FROM private_messages pm
WHERE pm.conversation_id IS NOT NULL
ON CONFLICT (id) DO NOTHING;

INSERT INTO messages (id, conversation_id, sender_id, content, edited_at, deleted_at, created_at)
SELECT wm.id, c.id, wm.user_id, wm.content, wm.edited_at, wm.deleted_at, wm.created_at
FROM wall_messages wm
JOIN conversations c ON c.activity_id = wm.activity_id
ON CONFLICT (id) DO NOTHING;

-- last_message_at refresh for activity conversations that got wall history.
UPDATE conversations c
SET last_message_at = sub.max_created
FROM (
  SELECT conversation_id, max(created_at) AS max_created
  FROM messages GROUP BY conversation_id
) sub
WHERE sub.conversation_id = c.id
  AND (c.last_message_at IS NULL OR c.last_message_at < sub.max_created);
