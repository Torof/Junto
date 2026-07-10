-- 00311: accept_participation — serialize the capacity check on the activity row
--
-- The only lock was FOR UPDATE OF p (the participation row): two concurrent
-- accepts of two DIFFERENT pending requests each counted N < max and both
-- accepted -> N+2 > max (overfill). Same window against a concurrent
-- update_activity lowering max_participants (possible while no accepted
-- non-creator exists — the whitelist trigger only locks it after that).
-- Fix: take FOR UPDATE on the activity row (same lock join_activity takes,
-- so accepts also serialize with joins) and re-read max_participants under
-- the lock before counting. Lock order participation -> activity is safe:
-- no live function takes them in the opposite order.
-- Authorization chain otherwise unchanged (auth, suspension, creator-only,
-- activity status gate, pending-only, junto.activity_full, 50 soft-cap).

CREATE OR REPLACE FUNCTION accept_participation(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_max_participants INTEGER;
  v_current_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.activity_id, p.user_id, p.status, a.creator_id, a.status AS activity_status, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_participation.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Lock the activity row and re-read the cap under the lock: serializes
  -- concurrent accepts with each other, with join_activity (same lock) and
  -- with update_activity lowering the cap.
  SELECT max_participants INTO v_max_participants
  FROM activities WHERE id = v_participation.activity_id
  FOR UPDATE;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = v_participation.activity_id AND status = 'accepted';

  -- Open activities (max_participants IS NULL) honor a hidden 50-soft-cap, same as join_activity
  IF v_current_count >= COALESCE(v_max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'accepted' WHERE id = p_participation_id;

  PERFORM create_notification(
    v_participation.user_id,
    'request_accepted',
    'Demande acceptée',
    'Ta demande pour ' || v_participation.title || ' a été acceptée',
    jsonb_build_object('activity_id', v_participation.activity_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION accept_participation FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION accept_participation FROM anon;
GRANT EXECUTE ON FUNCTION accept_participation TO authenticated;
