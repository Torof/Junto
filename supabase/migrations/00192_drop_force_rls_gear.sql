-- Migration 00192: drop FORCE RLS on gear tables; clean up diagnostic.
--
-- Root cause of the auto-decrement silently no-op'ing: activity_gear
-- and activity_gear_requests had FORCE ROW LEVEL SECURITY enabled
-- (set in 00187 by reflex). FORCE RLS makes RLS apply to the table
-- owner too — which interferes with SECURITY DEFINER functions
-- running as postgres in unintuitive ways. Specifically the SELECT
-- inside set_activity_gear sometimes returned no rows and the
-- UPDATE silently affected zero rows even though both should have
-- matched.
--
-- The DML on these tables is exclusively via SECURITY DEFINER RPCs
-- (set_activity_gear, request_activity_gear, withdraw_activity
-- _gear_request). Direct authenticated-role DML is denied — there
-- are no INSERT/UPDATE/DELETE policies, only SELECT. So:
--   - keep ENABLE RLS so authenticated/anon roles only see what
--     the SELECT policy allows
--   - drop FORCE RLS so postgres (with BYPASSRLS=true) bypasses
--     RLS as expected when running as the function owner
--
-- This also restores set_activity_gear to its production form
-- (the diagnostic log INSERT and helper table are removed).

ALTER TABLE activity_gear NO FORCE ROW LEVEL SECURITY;
ALTER TABLE activity_gear_requests NO FORCE ROW LEVEL SECURITY;

-- Cleanup: diagnostic table + test wrapper.
DROP TABLE IF EXISTS _set_activity_gear_log;
DROP FUNCTION IF EXISTS _test_update_request();

-- Restore set_activity_gear to its non-diagnostic form (identical
-- logic to 00190 + 00191, just without the _set_activity_gear_log
-- INSERT).
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
