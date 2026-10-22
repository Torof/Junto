-- ============================================================================
-- 00367 — Whitelist column guards on the unified messaging tables.
--
-- Defense-in-depth, matching the house *_whitelist_columns pattern (users /
-- activities / pro_*). BEFORE UPDATE, per row: freeze privileged identity /
-- ownership / audit columns to OLD unless junto.bypass_lock is set. INSERT stays
-- governed by the SECURITY DEFINER writers (no client write grant on any of the
-- three tables). The frozen set is DISJOINT from every column a live function
-- UPDATEs (status/name/icon/last_message_at/request_* on conversations,
-- last_read_at/hidden_at on members, content/edited_at/deleted_at on messages),
-- so no existing writer needs bypass_lock — nothing else changes.
-- ============================================================================

-- conversations — freeze DM pair, kind, owning activity, creator, request audit.
CREATE OR REPLACE FUNCTION conversations_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.user_1 := OLD.user_1;
  NEW.user_2 := OLD.user_2;
  NEW.type := OLD.type;
  NEW.activity_id := OLD.activity_id;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  NEW.initiated_by := OLD.initiated_by;
  NEW.initiated_from := OLD.initiated_from;
  NEW.request_sender_id := OLD.request_sender_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER conversations_lock_privileged
  BEFORE UPDATE ON conversations
  FOR EACH ROW EXECUTE FUNCTION conversations_whitelist_columns();

-- conversation_members — freeze the (conversation, user) key, who added, when.
CREATE OR REPLACE FUNCTION conversation_members_whitelist_columns()
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
  NEW.user_id := OLD.user_id;
  NEW.added_by := OLD.added_by;
  NEW.joined_at := OLD.joined_at;
  RETURN NEW;
END;
$$;

CREATE TRIGGER conversation_members_lock_privileged
  BEFORE UPDATE ON conversation_members
  FOR EACH ROW EXECUTE FUNCTION conversation_members_whitelist_columns();

-- messages — freeze identity, thread, author, reply target, timestamp, and the
-- share-card payload (edit_message may only touch content/edited_at).
CREATE OR REPLACE FUNCTION messages_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.conversation_id := OLD.conversation_id;
  NEW.sender_id := OLD.sender_id;
  NEW.reply_to_message_id := OLD.reply_to_message_id;
  NEW.created_at := OLD.created_at;
  NEW.metadata := OLD.metadata;
  RETURN NEW;
END;
$$;

CREATE TRIGGER messages_lock_privileged
  BEFORE UPDATE ON messages
  FOR EACH ROW EXECUTE FUNCTION messages_whitelist_columns();
