-- ============================================================================
-- 00381 — Channels (open thematic discussion channels), table + guards.
--
-- A channel is a conversations row with type='channel' (reserved since 00353),
-- plus this 1:1 side table carrying the topic identity: sport + place. Open
-- membership (anyone joins), persistent, distinct from private groups.
--
-- Reads go through SECURITY DEFINER RPCs only (search_channels/get_channel),
-- like the rest of the unified messaging tables — no direct client SELECT.
-- ============================================================================

-- A channel needs a name, like a group. The 00353 constraint tied name-not-null
-- exclusively to type='group'; widen it to group+channel.
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_group_name_check;
ALTER TABLE conversations
  ADD CONSTRAINT conversations_group_name_check
  CHECK ((type IN ('group', 'channel')) = (name IS NOT NULL));

CREATE TABLE channels (
  conversation_id UUID PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
  sport_key TEXT NOT NULL REFERENCES sports(key) ON DELETE RESTRICT,
  base GEOGRAPHY(Point, 4326) NOT NULL,
  base_label TEXT NOT NULL CHECK (char_length(base_label) BETWEEN 1 AND 120),
  description TEXT CHECK (description IS NULL OR char_length(description) <= 500),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX channels_base_gist ON channels USING GIST (base);
CREATE INDEX channels_sport_idx ON channels (sport_key);

ALTER TABLE channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE channels FORCE ROW LEVEL SECURITY;
-- No policies: every read/write goes through SECURITY DEFINER functions
-- (curated, like conversations). Deny all direct access.
REVOKE ALL ON channels FROM anon, authenticated;

-- Whitelist guard (defense-in-depth): freeze the topic identity on any UPDATE.
-- description/closed_at stay mutable (rename/close functions), and there is no
-- client write grant anyway.
CREATE OR REPLACE FUNCTION channels_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.conversation_id := OLD.conversation_id;
  NEW.sport_key := OLD.sport_key;
  NEW.base := OLD.base;
  NEW.base_label := OLD.base_label;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;
CREATE TRIGGER channels_lock_privileged
  BEFORE UPDATE ON channels
  FOR EACH ROW EXECUTE FUNCTION channels_whitelist_columns();
