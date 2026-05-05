-- Migration 00189: rewrite set_activity_gear without RECORD indirection.
--
-- The previous version used `SELECT added_by INTO v_request` (RECORD)
-- and then `v_request.added_by` to populate v_requested_by. The
-- requested_by column ended up NULL on all newly inserted gear rows
-- in production, suggesting either the field-of-NULL-record access
-- silently returned NULL or there was a subtle PL/pgSQL RECORD quirk
-- in this loop. Rewriting with `SELECT added_by INTO v_requested_by`
-- (direct UUID variable) removes the indirection — same logic, no
-- intermediate RECORD.

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

  -- Snapshot the user's current gear as a name → quantity JSONB map.
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

      -- Direct UUID assignment — no RECORD intermediate. v_requested_by
      -- is reset to NULL each iteration so a previous match doesn't
      -- leak into the next item.
      v_requested_by := NULL;
      IF v_delta > 0 THEN
        SELECT added_by INTO v_requested_by
        FROM activity_gear_requests
        WHERE activity_id = p_activity_id AND gear_name = v_name;
      END IF;

      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, requested_by)
      VALUES (p_activity_id, v_user_id, v_name, v_qty, v_requested_by);

      -- Auto-decrement the matching request by the delta. Positive
      -- deltas only; gear removal doesn't auto-resurrect requests.
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
