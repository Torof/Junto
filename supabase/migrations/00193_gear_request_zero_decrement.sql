-- Migration 00193: avoid CHECK violation when decrementing a request to 0.
--
-- Bug: set_activity_gear used UPDATE-then-DELETE for the auto-decrement.
-- When v_delta equals (or exceeds) the request's quantity, the UPDATE
-- tries to set quantity = 0, which violates the CHECK (quantity > 0)
-- constraint. The function aborts and the user's gear write never
-- commits.
--
-- Fix: flip the order. DELETE first when v_delta would consume the
-- whole request (quantity <= v_delta), then UPDATE the rest. After
-- the DELETE, every surviving row has quantity > v_delta, so the
-- subtraction never hits 0.

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

      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared, requested_by)
      VALUES (p_activity_id, v_user_id, v_name, v_qty, v_is_shared, v_requested_by);

      IF v_delta > 0 THEN
        -- DELETE first: any request whose entire quantity is being
        -- claimed (quantity <= v_delta) gets removed. After this,
        -- surviving rows are guaranteed to have quantity > v_delta,
        -- so the UPDATE's subtraction never lands at zero.
        DELETE FROM activity_gear_requests
        WHERE activity_id = p_activity_id
          AND gear_name = v_name
          AND is_shared = v_is_shared
          AND quantity <= v_delta;

        UPDATE activity_gear_requests
        SET quantity = quantity - v_delta
        WHERE activity_id = p_activity_id
          AND gear_name = v_name
          AND is_shared = v_is_shared;
      END IF;
    END IF;
  END LOOP;
END;
$$;
