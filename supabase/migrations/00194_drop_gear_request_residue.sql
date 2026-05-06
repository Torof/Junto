-- Migration 00194: drop gear-request residue.
--
-- The "Add missing" gear-request flow (table activity_gear_requests +
-- request/withdraw RPCs + activity_gear.requested_by column + the
-- auto-decrement branch in set_activity_gear) was parked from the UI
-- after Scott's "plane dashboard" feedback. The DB was kept in place
-- in case the feature was revived. Decision now is to drop the residue
-- entirely and recreate cleanly when the feature comes back.
--
-- Order matters:
--   1. Replace set_activity_gear with the request-free version FIRST,
--      so it stops referencing activity_gear_requests and requested_by.
--   2. Drop the request RPCs (no consumers left after step 1).
--   3. Drop the table (no FKs into it).
--   4. Drop the requested_by column on activity_gear.
--
-- Authorization chain on the recreated set_activity_gear (unchanged
-- from the prior request-aware version, just without the trailing
-- request-decrement logic):
--   1. auth.uid() IS NOT NULL
--   2. caller not suspended
--   3. caller is accepted participant of p_activity_id
--   4. activity is published or in_progress, deleted_at IS NULL

-- ============================================================================
-- 1. Recreate set_activity_gear without the request branch.
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

  -- Full replace of this user's gear list. is_shared is resolved per
  -- item: catalog match wins; falls back to client value; falls back
  -- to false (free-form items default to personal).
  DELETE FROM activity_gear WHERE activity_id = p_activity_id AND user_id = v_user_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_name := trim(v_item->>'name');
    v_qty := COALESCE((v_item->>'quantity')::integer, 1);

    IF v_name IS NOT NULL AND char_length(v_name) > 0 AND v_qty > 0 THEN
      v_qty := LEAST(v_qty, 99);

      SELECT is_shared INTO v_catalog_is_shared
      FROM gear_catalog WHERE name_key = v_name LIMIT 1;
      v_is_shared := COALESCE(v_catalog_is_shared, (v_item->>'is_shared')::boolean, false);

      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared)
      VALUES (p_activity_id, v_user_id, v_name, v_qty, v_is_shared);
    END IF;
  END LOOP;
END;
$$;

-- ============================================================================
-- 2. Drop the request RPCs.
-- ============================================================================

DROP FUNCTION IF EXISTS public.request_activity_gear(UUID, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.request_activity_gear(UUID, TEXT, INTEGER, BOOLEAN);
DROP FUNCTION IF EXISTS public.withdraw_activity_gear_request(UUID, TEXT);

-- ============================================================================
-- 3. Drop the table. Realtime publication membership goes with it.
-- ============================================================================

DROP TABLE IF EXISTS public.activity_gear_requests;

-- ============================================================================
-- 4. Drop the now-orphan requested_by column on activity_gear.
-- ============================================================================

ALTER TABLE public.activity_gear DROP COLUMN IF EXISTS requested_by;
