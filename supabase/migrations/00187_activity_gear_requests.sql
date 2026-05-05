-- Migration 00187: gear-request feature ("add missing").
--
-- Lets any accepted participant flag that the group needs more of an
-- item than has been declared. The request shows in the gear tab as
-- a distinct missing-pill, taps open the existing per-item modal,
-- and the existing set_activity_gear RPC auto-decrements the request
-- when a user adds qty for a name that has an outstanding request.
--
-- Tone: requests are group concerns, no shaming. Any participant can
-- add to OR remove a request. UNIQUE (activity_id, gear_name) means
-- multiple users adding the same name aggregate into one row.

-- ============================================================================
-- Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS activity_gear_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  gear_name TEXT NOT NULL CHECK (char_length(trim(gear_name)) > 0 AND char_length(gear_name) <= 100),
  quantity INTEGER NOT NULL CHECK (quantity > 0 AND quantity <= 99),
  -- Original / latest requester. NULL after user deletion (request
  -- survives, since it's a group concern not a personal want).
  added_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (activity_id, gear_name)
);

ALTER TABLE activity_gear_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_gear_requests FORCE ROW LEVEL SECURITY;

-- SELECT: any accepted participant or the activity creator. Mirrors
-- the visibility model on activity_gear so the UI surface is
-- consistent.
DROP POLICY IF EXISTS "Participants read gear requests" ON activity_gear_requests;
CREATE POLICY "Participants read gear requests"
  ON activity_gear_requests
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM participations p
      WHERE p.activity_id = activity_gear_requests.activity_id
        AND p.user_id = auth.uid()
        AND p.status = 'accepted'
    )
    OR EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = activity_gear_requests.activity_id
        AND a.creator_id = auth.uid()
    )
  );

-- No INSERT/UPDATE/DELETE policies — DML only via the SECURITY DEFINER
-- RPCs below.

REVOKE ALL ON TABLE activity_gear_requests FROM PUBLIC;
REVOKE ALL ON TABLE activity_gear_requests FROM anon;
GRANT SELECT ON TABLE activity_gear_requests TO authenticated;

-- ============================================================================
-- request_activity_gear: upsert a request (additive on existing).
-- Authorization chain:
--   1. auth.uid() not null
--   2. caller not suspended
--   3. activity exists, status ∈ {published, in_progress}, not soft-deleted
--   4. caller is accepted participant
--   5. name not empty after trim, qty 1..99
-- Behaviour: ON CONFLICT (activity_id, gear_name) increments quantity
-- by the new qty (clamped to 99); added_by becomes the latest requester.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.request_activity_gear(
  p_activity_id UUID,
  p_name TEXT,
  p_quantity INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_clean_qty INTEGER;
  v_request_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id AND status IN ('published', 'in_progress') AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := trim(COALESCE(p_name, ''));
  IF char_length(v_clean_name) = 0 OR char_length(v_clean_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_qty := COALESCE(p_quantity, 0);
  IF v_clean_qty < 1 OR v_clean_qty > 99 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO activity_gear_requests (activity_id, gear_name, quantity, added_by)
  VALUES (p_activity_id, v_clean_name, v_clean_qty, v_user_id)
  ON CONFLICT (activity_id, gear_name)
  DO UPDATE SET
    quantity = LEAST(99, activity_gear_requests.quantity + EXCLUDED.quantity),
    added_by = EXCLUDED.added_by
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_activity_gear(UUID, TEXT, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.request_activity_gear(UUID, TEXT, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.request_activity_gear(UUID, TEXT, INTEGER) TO authenticated;

-- ============================================================================
-- withdraw_activity_gear_request: delete a request.
-- Authorization chain:
--   1. auth.uid() not null
--   2. caller not suspended
--   3. activity exists, status ∈ {published, in_progress}
--   4. caller is accepted participant
-- Note: any accepted participant can withdraw — the request is a
-- group-level concern, no per-user ownership of the action. Matches
-- the no-shaming framing.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.withdraw_activity_gear_request(
  p_activity_id UUID,
  p_name TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id AND status IN ('published', 'in_progress') AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := trim(COALESCE(p_name, ''));
  IF char_length(v_clean_name) = 0 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM activity_gear_requests
  WHERE activity_id = p_activity_id AND gear_name = v_clean_name;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.withdraw_activity_gear_request(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.withdraw_activity_gear_request(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.withdraw_activity_gear_request(UUID, TEXT) TO authenticated;

-- ============================================================================
-- set_activity_gear: extended to auto-decrement matching gear requests.
-- For each item where the user's NEW qty > OLD qty, the matching
-- request (if any) is reduced by min(delta, request.quantity). When
-- the request reaches 0, it's deleted. No-op when delta <= 0 — we
-- don't auto-resurrect requests on gear removal.
--
-- All other behaviour identical to the prior version.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.set_activity_gear(p_activity_id UUID, p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_item JSONB;
  v_name TEXT;
  v_qty INTEGER;
  v_old_qty INTEGER;
  v_delta INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id AND status IN ('published', 'in_progress') AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Snapshot the user's current gear into a temp table so we can
  -- compute deltas after the delete + reinsert.
  CREATE TEMP TABLE _prev_gear (gear_name TEXT, quantity INTEGER) ON COMMIT DROP;
  INSERT INTO _prev_gear (gear_name, quantity)
  SELECT gear_name, quantity FROM activity_gear
  WHERE activity_id = p_activity_id AND user_id = v_user_id;

  -- Replace the user's gear list (full replace, same as before).
  DELETE FROM activity_gear WHERE activity_id = p_activity_id AND user_id = v_user_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_name := trim(v_item->>'name');
    v_qty := COALESCE((v_item->>'quantity')::integer, 1);

    IF v_name IS NOT NULL AND char_length(v_name) > 0 AND v_qty > 0 THEN
      v_qty := LEAST(v_qty, 99);
      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity)
      VALUES (p_activity_id, v_user_id, v_name, v_qty);

      -- Compute delta vs previous; positive deltas decrement matching
      -- requests so adding gear "fulfils" outstanding asks.
      SELECT COALESCE(quantity, 0) INTO v_old_qty FROM _prev_gear WHERE gear_name = v_name;
      v_delta := v_qty - COALESCE(v_old_qty, 0);

      IF v_delta > 0 THEN
        UPDATE activity_gear_requests
        SET quantity = quantity - LEAST(v_delta, quantity)
        WHERE activity_id = p_activity_id AND gear_name = v_name;

        DELETE FROM activity_gear_requests
        WHERE activity_id = p_activity_id AND gear_name = v_name AND quantity <= 0;
      END IF;
    END IF;
  END LOOP;
END;
$$;

-- ============================================================================
-- Realtime: add the new table to supabase_realtime so changes propagate.
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'activity_gear_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE activity_gear_requests;
  END IF;
END $$;
