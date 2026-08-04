-- ============================================================================
-- 00354 — Unified messaging: triggers (brique 2, part 2 — validated lot ③).
--
-- Pure DATA triggers: no auth.uid(), no suspension checks, tolerant of
-- missing rows (they fire under cron, seeds, and account-deletion cascades —
-- a RAISE would abort legal flows). Non-deferrable, row-level, immediate.
-- ============================================================================

-- ---------- 1. Activity → conversation creation ----------
CREATE OR REPLACE FUNCTION create_activity_conversation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO conversations (type, activity_id, status, created_at)
  VALUES ('activity', NEW.id, 'active', now())
  ON CONFLICT (activity_id) WHERE activity_id IS NOT NULL DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_activity_conversation
  AFTER INSERT ON activities
  FOR EACH ROW EXECUTE FUNCTION create_activity_conversation();

-- ---------- 2. participations ⇄ members sync (the 23-transition rules) ----------
CREATE OR REPLACE FUNCTION sync_activity_membership()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv_id UUID;
BEGIN
  -- Immutable keys guard (future-proof: no writer re-points a row today).
  IF TG_OP = 'UPDATE' AND (NEW.user_id IS DISTINCT FROM OLD.user_id
                        OR NEW.activity_id IS DISTINCT FROM OLD.activity_id) THEN
    RAISE EXCEPTION 'participations keys are immutable';
  END IF;

  IF TG_OP = 'DELETE' THEN
    -- Tolerant cleanup; redundant with FK cascades (order unspecified) — never fails.
    IF OLD.status = 'accepted' THEN
      DELETE FROM conversation_members cm
      USING conversations c
      WHERE c.activity_id = OLD.activity_id
        AND cm.conversation_id = c.id AND cm.user_id = OLD.user_id;
    END IF;
    RETURN OLD;
  END IF;

  -- Gain: became accepted (INSERT accepted, or UPDATE from any other status).
  IF NEW.status = 'accepted' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'accepted') THEN
    SELECT id INTO v_conv_id FROM conversations WHERE activity_id = NEW.activity_id;
    IF v_conv_id IS NOT NULL THEN
      INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
      VALUES (v_conv_id, NEW.user_id, NULL, now())
      ON CONFLICT (conversation_id, user_id) DO NOTHING;
    END IF;
  -- Loss: left accepted (remove / withdraw / expire / refuse — all UPDATEs).
  ELSIF TG_OP = 'UPDATE' AND OLD.status = 'accepted' AND NEW.status IS DISTINCT FROM 'accepted' THEN
    DELETE FROM conversation_members cm
    USING conversations c
    WHERE c.activity_id = NEW.activity_id
      AND cm.conversation_id = c.id AND cm.user_id = NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_sync_activity_membership
  AFTER INSERT OR DELETE OR UPDATE ON participations
  FOR EACH ROW
  EXECUTE FUNCTION sync_activity_membership();

-- ---------- 3. Block cascade extension: clear invited rows of the pair ----------
-- (Existing cascade_block_to_requests keeps declining pending DMs; existing
-- participation cascade keeps refusing pendings. This adds: invitations
-- between the pair are silently deleted — same semantics as declining.)
CREATE OR REPLACE FUNCTION cascade_block_invited()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM participations p
  USING activities a
  WHERE p.activity_id = a.id
    AND p.status = 'invited'
    AND (
      (p.user_id = NEW.blocked_id AND a.creator_id = NEW.blocker_id)
      OR (p.user_id = NEW.blocker_id AND a.creator_id = NEW.blocked_id)
    );
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_cascade_block_invited
  AFTER INSERT ON blocked_users
  FOR EACH ROW EXECUTE FUNCTION cascade_block_invited();

-- ---------- 4. Expiry extension: invited expires like pending ----------
-- 00263's transition trigger flips pending→expired when the activity ends or
-- is cancelled. Extend the same rule to invited (neither has a member row —
-- sync-safe by construction). We wrap rather than redefine 00263's function:
-- a second AFTER UPDATE trigger on activities with the same firing condition.
CREATE OR REPLACE FUNCTION expire_invited_on_activity_end()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('completed', 'cancelled', 'expired')
     AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE participations
    SET status = 'expired'
    WHERE activity_id = NEW.id AND status = 'invited';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_expire_invited
  AFTER UPDATE OF status ON activities
  FOR EACH ROW EXECUTE FUNCTION expire_invited_on_activity_end();

-- ---------- 5. participations: allow the new 'invited' status ----------
DO $$
DECLARE v_cname TEXT;
BEGIN
  SELECT conname INTO v_cname
  FROM pg_constraint
  WHERE conrelid = 'participations'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%status%IN%';
  IF v_cname IS NOT NULL THEN
    EXECUTE 'ALTER TABLE participations DROP CONSTRAINT ' || quote_ident(v_cname);
  END IF;
END $$;
ALTER TABLE participations ADD CONSTRAINT participations_status_check
  CHECK (status IN ('pending', 'accepted', 'refused', 'removed', 'withdrawn', 'expired', 'invited'));

-- Invitation columns (privileged: settable only via SECURITY DEFINER functions).
ALTER TABLE participations
  ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS invite_message TEXT;
ALTER TABLE participations
  ADD CONSTRAINT participations_invite_msg_len_check
    CHECK (invite_message IS NULL OR char_length(invite_message) <= 500);
