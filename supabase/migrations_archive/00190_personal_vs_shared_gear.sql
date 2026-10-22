-- Migration 00190: split gear into personal vs shared.
--
-- Personal gear (helmet, harness, paddle) is what each user packs for
-- themselves — aggregating in a "common inventory" makes no sense.
-- Shared gear (rope, dry bag, first aid kit) is brought once for the
-- whole group — common inventory is exactly the right view.
--
-- The is_shared flag lives on:
--   gear_catalog            — canonical classification per item.
--   activity_gear           — per-row, so display can filter.
--   activity_gear_requests  — independent of catalog: a personal
--                              request and a group request can both
--                              exist for the same name (helmet for me
--                              vs helmet for the group).
--
-- Catalog wins over client input when both are present — users can't
-- accidentally re-classify a known item. Free-form items rely on the
-- client toggle (Personnel / Partagé in the custom sheet).

-- ============================================================================
-- 1. gear_catalog
-- ============================================================================

ALTER TABLE gear_catalog ADD COLUMN IF NOT EXISTS is_shared BOOLEAN NOT NULL DEFAULT false;

UPDATE gear_catalog SET is_shared = true WHERE name_key IN (
  'Corde 60m',
  'Corde 70m',
  'Dégaines',
  'Mousquetons',
  'Sangles',
  'Broches à glace',
  'Bidon étanche',
  'Corde 30m (canyon)',
  'Corde 60m (canyon)',
  'Corde 80m (canyon)',
  'Trousse de secours',
  'Carte / GPS',
  'Radio'
);

-- ============================================================================
-- 2. activity_gear
-- ============================================================================

ALTER TABLE activity_gear ADD COLUMN IF NOT EXISTS is_shared BOOLEAN NOT NULL DEFAULT false;

-- Backfill: any existing row whose name matches a now-shared catalog
-- item flips to shared. Free-form items stay at default (personal).
UPDATE activity_gear SET is_shared = true
WHERE gear_name IN (SELECT name_key FROM gear_catalog WHERE is_shared = true);

-- ============================================================================
-- 3. activity_gear_requests
-- ============================================================================

ALTER TABLE activity_gear_requests ADD COLUMN IF NOT EXISTS is_shared BOOLEAN NOT NULL DEFAULT false;

UPDATE activity_gear_requests SET is_shared = true
WHERE gear_name IN (SELECT name_key FROM gear_catalog WHERE is_shared = true);

-- Replace the unique constraint so a personal request and a group
-- request for the same gear name can coexist.
ALTER TABLE activity_gear_requests
  DROP CONSTRAINT IF EXISTS activity_gear_requests_activity_id_gear_name_key;
ALTER TABLE activity_gear_requests
  ADD CONSTRAINT activity_gear_requests_activity_id_gear_name_is_shared_key
  UNIQUE (activity_id, gear_name, is_shared);

-- ============================================================================
-- 4. set_activity_gear — accepts is_shared per item, matches request
--    decrement on (activity_id, gear_name, is_shared) tuple.
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

  -- Snapshot the user's current gear: name → quantity (we don't need
  -- is_shared here — the auto-decrement matches by both name AND
  -- is_shared on the request, and is_shared comes from catalog/input).
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

      -- Catalog wins over client input (users can't reclassify a known
      -- item). Free-form items use the client-supplied is_shared, then
      -- fall back to false.
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

-- ============================================================================
-- 5. request_activity_gear — accepts p_is_shared, ON CONFLICT on the
--    new (activity_id, gear_name, is_shared) key.
-- ============================================================================

DROP FUNCTION IF EXISTS public.request_activity_gear(UUID, TEXT, INTEGER);
CREATE OR REPLACE FUNCTION public.request_activity_gear(
  p_activity_id UUID,
  p_name TEXT,
  p_quantity INTEGER,
  p_is_shared BOOLEAN DEFAULT false
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

  -- Catalog wins over caller's flag, same rule as set_activity_gear.
  SELECT is_shared INTO v_catalog_is_shared
  FROM gear_catalog WHERE name_key = v_clean_name LIMIT 1;
  v_is_shared := COALESCE(v_catalog_is_shared, p_is_shared);

  INSERT INTO activity_gear_requests (activity_id, gear_name, quantity, added_by, is_shared)
  VALUES (p_activity_id, v_clean_name, v_clean_qty, v_user_id, v_is_shared)
  ON CONFLICT (activity_id, gear_name, is_shared)
  DO UPDATE SET
    quantity = LEAST(99, activity_gear_requests.quantity + EXCLUDED.quantity),
    added_by = EXCLUDED.added_by
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_activity_gear(UUID, TEXT, INTEGER, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.request_activity_gear(UUID, TEXT, INTEGER, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.request_activity_gear(UUID, TEXT, INTEGER, BOOLEAN) TO authenticated;
