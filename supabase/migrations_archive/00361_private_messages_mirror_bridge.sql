-- ============================================================================
-- 00361 — Interim mirror bridge: private_messages → messages (brique 2, part 9).
--
-- Three legacy writers still INSERT into private_messages directly:
-- invite_users_to_activity (shared_activity card branch + its hourly counter),
-- request_seat and accept_seat_request (seat_request_pending / seat_accepted
-- seeded messages). Rather than blind-rewriting those three large bodies at the
-- tail of the wave, this trigger mirrors every INSERT into the unified store —
-- same ids (ON CONFLICT DO NOTHING), and the mirrored insert fires the 00359
-- broadcast+push trigger, so the NEW client sees these messages live.
--
-- The proper ports (rewrite the three writers onto `messages`) + the final
-- DROP of wall_messages / private_messages / edit_private_message /
-- edit_wall_message are scheduled with the post-code adversarial audit
-- (Brique 3) — the drop must anyway wait out the OTA window.
-- ============================================================================

CREATE OR REPLACE FUNCTION mirror_private_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO messages (id, conversation_id, sender_id, content, metadata,
                        reply_to_message_id, edited_at, deleted_at, created_at)
  VALUES (NEW.id, NEW.conversation_id, NEW.sender_id, NEW.content, NEW.metadata,
          NEW.reply_to_message_id, NEW.edited_at, NEW.deleted_at, NEW.created_at)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_mirror_private_message
  AFTER INSERT ON private_messages
  FOR EACH ROW EXECUTE FUNCTION mirror_private_message();
