-- Migration 00188: fix gear-request realtime + link gear contributions to requesters.
--
-- Two bugs + one feature:
--
-- 1) Realtime UPDATE/DELETE events on activity_gear and
--    activity_gear_requests were silently dropped because their OLD
--    payloads only carry the primary key, and the RLS SELECT policies
--    use EXISTS subqueries on activity_id. With no activity_id in OLD,
--    RLS can't evaluate against the old row and the broadcast never
--    reaches participants. REPLICA IDENTITY FULL puts every column in
--    the change payload so RLS can pass.
--
-- 2) The temp-table snapshot inside set_activity_gear was fragile
--    (CREATE TEMP TABLE inside a SECURITY DEFINER function across
--    pooled connections has subtle ordering issues). Replacing with an
--    inline JSONB snapshot — same delta semantics, no temp object.
--
-- 3) New activity_gear.requested_by column links a user's gear
--    contribution to the original requester whose ask it fulfilled.
--    set_activity_gear sets it when the delta decrements a matching
--    request; the UI surfaces it as a "demandé par X" chip on the
--    user's gear list.

-- ============================================================================
-- 1. REPLICA IDENTITY FULL — fixes UPDATE/DELETE broadcast under RLS
-- ============================================================================

ALTER TABLE activity_gear REPLICA IDENTITY FULL;
ALTER TABLE activity_gear_requests REPLICA IDENTITY FULL;

-- ============================================================================
-- 2. activity_gear.requested_by — link to the request's added_by
-- ============================================================================

ALTER TABLE activity_gear
  ADD COLUMN IF NOT EXISTS requested_by UUID REFERENCES users(id) ON DELETE SET NULL;

-- ============================================================================
-- 3. set_activity_gear — JSONB snapshot + auto-link requested_by
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
  v_prev_gear JSONB;
  v_request RECORD;
  v_requested_by UUID;
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

  -- Snapshot the user's current gear as a name → quantity map. Inline
  -- JSONB avoids the temp-table fragility.
  SELECT COALESCE(jsonb_object_agg(gear_name, quantity), '{}'::jsonb) INTO v_prev_gear
  FROM activity_gear
  WHERE activity_id = p_activity_id AND user_id = v_user_id;

  -- Replace the user's gear list (full replace).
  DELETE FROM activity_gear WHERE activity_id = p_activity_id AND user_id = v_user_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_name := trim(v_item->>'name');
    v_qty := COALESCE((v_item->>'quantity')::integer, 1);

    IF v_name IS NOT NULL AND char_length(v_name) > 0 AND v_qty > 0 THEN
      v_qty := LEAST(v_qty, 99);
      v_old_qty := COALESCE((v_prev_gear->>v_name)::integer, 0);
      v_delta := v_qty - v_old_qty;

      -- If the contribution increased and there's a matching request,
      -- capture the requester so we can record the link on the new
      -- gear row (lets the UI show "demandé par X" next to this item).
      v_requested_by := NULL;
      IF v_delta > 0 THEN
        SELECT added_by INTO v_request
        FROM activity_gear_requests
        WHERE activity_id = p_activity_id AND gear_name = v_name;
        v_requested_by := v_request.added_by;
      END IF;

      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, requested_by)
      VALUES (p_activity_id, v_user_id, v_name, v_qty, v_requested_by);

      -- Auto-decrement the matching request by the delta. Positive
      -- deltas only — gear removal doesn't auto-resurrect requests.
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
