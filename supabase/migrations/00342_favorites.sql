-- ============================================================================
-- 00342 — Favorites: bookmark pro pages, pro offerings, and peer activities.
--
-- One table, three optional FK columns (exactly one set), ON DELETE CASCADE on
-- each so a favorite auto-vanishes if its target is hard-deleted. Expiry of
-- PEER activities is handled for free at READ time: get_favorites returns only
-- the refs, and the client renders them through the existing views
-- (activities_with_coords shows only published/in_progress, non-deleted), so a
-- favorited outing that passes/expires silently drops off the list — no dead
-- links, nothing to clean up. Writes via SECURITY DEFINER functions only.
-- ============================================================================

CREATE TABLE favorites (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id UUID REFERENCES activities(id) ON DELETE CASCADE,
  offering_id UUID REFERENCES pro_offerings(id) ON DELETE CASCADE,
  pro_id      UUID REFERENCES pro_profiles(user_id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (num_nonnulls(activity_id, offering_id, pro_id) = 1)
);

CREATE UNIQUE INDEX favorites_owner_activity ON favorites(owner_id, activity_id) WHERE activity_id IS NOT NULL;
CREATE UNIQUE INDEX favorites_owner_offering ON favorites(owner_id, offering_id) WHERE offering_id IS NOT NULL;
CREATE UNIQUE INDEX favorites_owner_pro      ON favorites(owner_id, pro_id)      WHERE pro_id IS NOT NULL;
CREATE INDEX favorites_owner_idx ON favorites(owner_id, created_at DESC);

ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites FORCE ROW LEVEL SECURITY;

CREATE POLICY favorites_select_own ON favorites
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid());
-- No write policies — SECURITY DEFINER functions only. No UPDATE path.
REVOKE ALL ON favorites FROM anon;
GRANT SELECT ON favorites TO authenticated;

-- ============================================================================
-- add_favorite(p_kind, p_id) — auth + non-suspended; target exists and is
-- valid/visible for its kind; insert into the right column.
-- ============================================================================
CREATE OR REPLACE FUNCTION add_favorite(p_kind TEXT, p_id UUID)
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
  IF p_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_kind = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities
      WHERE id = p_id AND deleted_at IS NULL AND status IN ('published', 'in_progress')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, activity_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'offering' THEN
    IF NOT EXISTS (
      SELECT 1 FROM pro_offerings o JOIN users u ON u.id = o.pro_id
      WHERE o.id = p_id AND u.suspended_at IS NULL
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, offering_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'pro' THEN
    IF NOT EXISTS (
      SELECT 1 FROM pro_profiles p JOIN users u ON u.id = p.user_id
      WHERE p.user_id = p_id AND p.status = 'approved' AND u.suspended_at IS NULL
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, pro_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION add_favorite(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_favorite(TEXT, UUID) TO authenticated;

-- ============================================================================
-- remove_favorite(p_kind, p_id) — delete your own row for that target.
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_favorite(p_kind TEXT, p_id UUID)
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

  IF p_kind = 'activity' THEN
    DELETE FROM favorites WHERE owner_id = v_user_id AND activity_id = p_id;
  ELSIF p_kind = 'offering' THEN
    DELETE FROM favorites WHERE owner_id = v_user_id AND offering_id = p_id;
  ELSIF p_kind = 'pro' THEN
    DELETE FROM favorites WHERE owner_id = v_user_id AND pro_id = p_id;
  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION remove_favorite(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_favorite(TEXT, UUID) TO authenticated;

-- ============================================================================
-- get_favorites — the caller's favorite refs (kind + id), newest first. The
-- client fetches full data per kind via the existing views, which apply
-- visibility/expiry filtering (so passed peer activities silently drop off).
-- ============================================================================
CREATE OR REPLACE FUNCTION get_favorites()
RETURNS TABLE (kind TEXT, ref_id UUID, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    CASE
      WHEN f.activity_id IS NOT NULL THEN 'activity'
      WHEN f.offering_id IS NOT NULL THEN 'offering'
      ELSE 'pro'
    END AS kind,
    coalesce(f.activity_id, f.offering_id, f.pro_id) AS ref_id,
    f.created_at
  FROM favorites f
  WHERE f.owner_id = v_user_id
  ORDER BY f.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION get_favorites() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_favorites() TO authenticated;
