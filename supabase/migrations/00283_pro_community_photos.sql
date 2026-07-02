-- Migration 00283: community photos on a pro page (Google-Maps style).
--
-- Anyone (authenticated) can add photos to a pro page — as part of a review or
-- standalone. The pro owner can delete any (moderation); a contributor can
-- delete their own. Kept in a SEPARATE table from the owner's curated
-- pro_profile_photos so it never entangles the owner's 25-cap / reorder logic.
--
-- Storage: reuses the existing `pro-photos` bucket. Each uploader writes under
-- their own `<uid>/…` path (existing pro_photos_insert_own policy allows it),
-- read is public — so no storage policy change is needed. Removal deletes only
-- the DB row (matches remove_pro_photo; storage objects orphan, tolerated).
--
-- Decided with Scott 2026-07-02: everyone can post, pro moderates by deleting,
-- cap 5 photos per user per pro.

-- ============================================================================
-- pro_community_photos
-- ============================================================================
CREATE TABLE pro_community_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_id UUID NOT NULL REFERENCES pro_profiles(user_id) ON DELETE CASCADE,
  contributor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL CHECK (char_length(photo_url) BETWEEN 1 AND 500),
  -- Optional link to the review it was posted with, so it can render inline on
  -- that review. Standalone gallery contributions leave it NULL.
  review_id UUID REFERENCES pro_reviews(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX pro_community_photos_pro_idx ON pro_community_photos(pro_id, created_at DESC);
CREATE INDEX pro_community_photos_review_idx ON pro_community_photos(review_id);
CREATE INDEX pro_community_photos_contributor_idx ON pro_community_photos(contributor_id, pro_id);

ALTER TABLE pro_community_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE pro_community_photos FORCE ROW LEVEL SECURITY;

CREATE POLICY pro_community_photos_public_read ON pro_community_photos
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- No write policies — RPCs are the only write path.

-- Privileged-column lock: nothing is updatable (add + delete only), so force
-- every column back to OLD on any UPDATE that isn't an explicit bypass.
CREATE OR REPLACE FUNCTION pro_community_photos_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.pro_id := OLD.pro_id;
  NEW.contributor_id := OLD.contributor_id;
  NEW.photo_url := OLD.photo_url;
  NEW.review_id := OLD.review_id;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION pro_community_photos_whitelist_columns FROM anon, authenticated;

CREATE TRIGGER pro_community_photos_lock_privileged
  BEFORE UPDATE ON pro_community_photos
  FOR EACH ROW EXECUTE FUNCTION pro_community_photos_whitelist_columns();

-- ============================================================================
-- add_pro_community_photo — anyone authenticated, 5 max per user per pro
-- ============================================================================
CREATE OR REPLACE FUNCTION add_pro_community_photo(
  p_pro_id UUID,
  p_photo_url TEXT,
  p_review_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_photo_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- target must be a real pro
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- url must be a well-formed pro-photos bucket URL (no arbitrary links)
  IF p_photo_url IS NULL
     OR char_length(p_photo_url) < 1
     OR char_length(p_photo_url) > 500
     OR p_photo_url NOT LIKE '%/pro-photos/%' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- if linked to a review, it must be THIS user's review on THIS pro
  IF p_review_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_reviews
    WHERE id = p_review_id AND reviewer_id = v_user_id AND pro_id = p_pro_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- rate limit: 5 photos per user per pro (user-actionable → friendly code)
  PERFORM pg_advisory_xact_lock(hashtext('add_community_photo:' || v_user_id::text || ':' || p_pro_id::text));

  SELECT count(*) INTO v_count
  FROM pro_community_photos
  WHERE pro_id = p_pro_id AND contributor_id = v_user_id;

  IF v_count >= 5 THEN
    RAISE EXCEPTION 'junto.photo_limit';
  END IF;

  INSERT INTO pro_community_photos (pro_id, contributor_id, photo_url, review_id)
  VALUES (p_pro_id, v_user_id, p_photo_url, p_review_id)
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION add_pro_community_photo FROM anon;
GRANT EXECUTE ON FUNCTION add_pro_community_photo TO authenticated;

-- ============================================================================
-- remove_pro_community_photo — the contributor (own) OR the pro owner (moderate)
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_pro_community_photo(p_photo_id UUID)
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

  -- allowed if the caller uploaded it, or owns the pro page (pro_id = owner uid)
  IF NOT EXISTS (
    SELECT 1 FROM pro_community_photos
    WHERE id = p_photo_id AND (contributor_id = v_user_id OR pro_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_community_photos WHERE id = p_photo_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION remove_pro_community_photo FROM anon;
GRANT EXECUTE ON FUNCTION remove_pro_community_photo TO authenticated;
