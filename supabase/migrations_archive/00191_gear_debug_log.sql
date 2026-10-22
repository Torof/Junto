-- Migration 00191: TEMPORARY diagnostic log for set_activity_gear.
--
-- The auto-decrement of activity_gear_requests is silently not
-- running in production tests, but the function logic SELECTs both
-- catalog and request rows correctly when run directly. Most likely
-- cause: v_delta is 0 (user's new qty equals old qty so the IF
-- block never enters), but we can't confirm from the resulting rows
-- alone.
--
-- This migration adds a _set_activity_gear_log table and modifies
-- the RPC to insert one row per item processed, capturing the
-- computed values. We can drop the table + revert the function
-- once we've identified the cause.

CREATE TABLE IF NOT EXISTS _set_activity_gear_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id UUID NOT NULL,
  activity_id UUID NOT NULL,
  user_id UUID NOT NULL,
  gear_name TEXT NOT NULL,
  v_qty INTEGER NOT NULL,
  v_old_qty INTEGER NOT NULL,
  v_delta INTEGER NOT NULL,
  v_is_shared BOOLEAN NOT NULL,
  v_requested_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

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
  v_is_shared BOOLEAN;
  v_catalog_is_shared BOOLEAN;
  v_call_id UUID;
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

  v_call_id := gen_random_uuid();

  SELECT COALESCE(jsonb_object_agg(gear_name, quantity), '{}'::jsonb) INTO v_prev_gear
  FROM activity_gear
  WHERE activity_id = p_activity_id AND user_id = v_user_id;

  DELETE FROM activity_gear WHERE activity_id = p_activity_id AND user_id = v_user_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_name := trim(v_item->>'name');
    v_qty := COALESCE((v_item->>'quantity')::integer, 1);

    IF v_name IS NOT NULL AND char_length(v_name) > 0 AND v_qty > 0 THEN
      v_qty := LEAST(v_qty, 99);
      v_old_qty := COALESCE((v_prev_gear->>v_name)::integer, 0);
      v_delta := v_qty - v_old_qty;

      SELECT is_shared INTO v_catalog_is_shared
      FROM gear_catalog WHERE name_key = v_name LIMIT 1;
      v_is_shared := COALESCE(v_catalog_is_shared, (v_item->>'is_shared')::boolean, false);

      v_requested_by := NULL;
      IF v_delta > 0 THEN
        SELECT added_by INTO v_requested_by
        FROM activity_gear_requests
        WHERE activity_id = p_activity_id
          AND gear_name = v_name
          AND is_shared = v_is_shared;
      END IF;

      -- Diagnostic log row.
      INSERT INTO _set_activity_gear_log
        (call_id, activity_id, user_id, gear_name, v_qty, v_old_qty, v_delta, v_is_shared, v_requested_by)
      VALUES
        (v_call_id, p_activity_id, v_user_id, v_name, v_qty, v_old_qty, v_delta, v_is_shared, v_requested_by);

      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared, requested_by)
      VALUES (p_activity_id, v_user_id, v_name, v_qty, v_is_shared, v_requested_by);

      IF v_delta > 0 THEN
        UPDATE activity_gear_requests
        SET quantity = quantity - LEAST(v_delta, quantity)
        WHERE activity_id = p_activity_id
          AND gear_name = v_name
          AND is_shared = v_is_shared;

        DELETE FROM activity_gear_requests
        WHERE activity_id = p_activity_id
          AND gear_name = v_name
          AND is_shared = v_is_shared
          AND quantity <= 0;
      END IF;
    END IF;
  END LOOP;
END;
$$;
