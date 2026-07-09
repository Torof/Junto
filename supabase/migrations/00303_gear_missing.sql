-- Migration 00303: "Manquant" gear tiles (Phase 2 of the gear-tab redesign).
-- Authorization chain validated by Scott 2026-07-09.
--
-- Model: a missing item is a STANDALONE collaborative statement ("il manque
-- un réchaud") — no requests, no lending, no quantities-needed arithmetic
-- (that judged-needs model was rejected; see docs/GEAR_NEEDS.md history).
-- Any accepted participant (or the creator) can add/remove one; declaring a
-- matching SHARED contribution auto-clears the tile (server trigger, atomic).
-- NOT the old 00187 request system (dropped in 00194) — different model.

-- ============================================================================
-- 1. Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS activity_gear_missing (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
  quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 99),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One tile per item name (case-insensitive) per activity.
CREATE UNIQUE INDEX IF NOT EXISTS ux_gear_missing_activity_name
  ON activity_gear_missing (activity_id, lower(name));

ALTER TABLE activity_gear_missing ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_gear_missing FORCE ROW LEVEL SECURITY;

-- Read: accepted participants + creator; hide rows authored by someone the
-- caller blocked (same unidirectional semantics as activity_gear, 00203).
CREATE POLICY "Participants can read missing gear"
  ON activity_gear_missing FOR SELECT
  USING (
    (
      EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = activity_gear_missing.activity_id
          AND user_id = auth.uid()
          AND status = 'accepted'
      )
      OR EXISTS (
        SELECT 1 FROM activities
        WHERE id = activity_gear_missing.activity_id
          AND creator_id = auth.uid()
      )
    )
    AND (
      created_by IS NULL
      OR created_by NOT IN (
        SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
      )
    )
  );

GRANT SELECT ON activity_gear_missing TO authenticated;
-- No INSERT/UPDATE/DELETE policies or grants: writes go through the
-- SECURITY DEFINER functions below only (postgres has BYPASSRLS — 00288).

-- ============================================================================
-- 2. add_missing_gear — upsert a missing tile
-- Chain: auth → suspension → active activity → accepted participant OR
-- creator → sanitize + caps. Duplicate name = quantity update (no error).
-- ============================================================================
CREATE OR REPLACE FUNCTION add_missing_gear(
  p_activity_id UUID,
  p_name TEXT,
  p_quantity INTEGER DEFAULT 1
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
  v_qty INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) AND NOT EXISTS (
    SELECT 1 FROM activities WHERE id = p_activity_id AND creator_id = v_user_id
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Same HTML-strip as set_activity_gear (00238 H5c).
  v_name := regexp_replace(trim(coalesce(p_name, '')), '<[^>]*>', '', 'g');
  IF char_length(v_name) < 1 OR char_length(v_name) > 60 THEN
    RAISE EXCEPTION 'junto.gear_invalid';
  END IF;
  v_qty := GREATEST(1, LEAST(coalesce(p_quantity, 1), 99));

  -- Anti-noise cap.
  IF (SELECT count(*) FROM activity_gear_missing WHERE activity_id = p_activity_id) >= 20 THEN
    RAISE EXCEPTION 'junto.gear_missing_limit';
  END IF;

  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by)
  VALUES (p_activity_id, v_name, v_qty, v_user_id)
  ON CONFLICT (activity_id, lower(name))
  DO UPDATE SET quantity = EXCLUDED.quantity;
END;
$$;

REVOKE EXECUTE ON FUNCTION add_missing_gear FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION add_missing_gear TO authenticated;

-- ============================================================================
-- 3. remove_missing_gear — collaborative removal (any accepted participant
-- or the creator; same chain minus input caps)
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_missing_gear(
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) AND NOT EXISTS (
    SELECT 1 FROM activities WHERE id = p_activity_id AND creator_id = v_user_id
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  DELETE FROM activity_gear_missing
  WHERE activity_id = p_activity_id
    AND lower(name) = lower(trim(coalesce(p_name, '')));
END;
$$;

REVOKE EXECUTE ON FUNCTION remove_missing_gear FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION remove_missing_gear TO authenticated;

-- ============================================================================
-- 4. Auto-clear: declaring a SHARED contribution with a matching name closes
-- the missing tile — atomic, server-side, no client coordination. Runs as
-- postgres (BYPASSRLS) since inserts come from set_activity_gear (definer).
-- ============================================================================
CREATE OR REPLACE FUNCTION clear_missing_on_shared_gear()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.is_shared THEN
    DELETE FROM activity_gear_missing
    WHERE activity_id = NEW.activity_id
      AND lower(name) = lower(NEW.gear_name);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clear_missing_on_shared_gear ON activity_gear;
CREATE TRIGGER trg_clear_missing_on_shared_gear
  AFTER INSERT ON activity_gear
  FOR EACH ROW
  EXECUTE FUNCTION clear_missing_on_shared_gear();

-- ============================================================================
-- 5. Realtime
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'activity_gear_missing'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE activity_gear_missing;
  END IF;
END $$;
