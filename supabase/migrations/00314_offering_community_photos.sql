-- 00314: community photos on pro OFFERINGS
--
-- The pro profile page already accepts community photos from any signed-in
-- passionné (00283, Google-Maps model); the offering page was owner-only.
-- Scott (2026-07-10): everyone must be able to post photos on offerings too,
-- and removal stays contributor-or-pro-owner (already the 00283 rule —
-- remove_pro_community_photo is unchanged).
--
-- Mechanics: pro_community_photos gains a nullable offering_id. NULL =
-- profile-level photo (existing rows untouched); set = photo attached to
-- that offering, shown on its page. The pro profile keeps showing ALL of
-- the pro's community photos (offering ones included — a photo of their
-- outing is a photo of their business).
--
-- add_pro_community_photo gains p_offering_id (DEFAULT NULL). Signature
-- changes -> DROP + CREATE + explicit REVOKE/GRANT (DROP resets ACLs).
-- Authorization chain (validated by Scott 2026-07-10): unchanged from
-- 00283 (auth, suspension, pro exists, bucket-URL shape, own-review link,
-- advisory lock, 5-photos-per-user-per-pro cap covering profile+offerings
-- combined) + NEW: when p_offering_id is provided, the offering must exist
-- AND belong to p_pro_id (generic error otherwise).

ALTER TABLE pro_community_photos
  ADD COLUMN offering_id UUID REFERENCES pro_offerings(id) ON DELETE CASCADE;

CREATE INDEX pro_community_photos_offering_idx
  ON pro_community_photos(offering_id, created_at DESC)
  WHERE offering_id IS NOT NULL;

-- Immutable after insert, like every other column on this table.
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
  NEW.offering_id := OLD.offering_id;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION pro_community_photos_whitelist_columns FROM anon, authenticated;

DROP FUNCTION add_pro_community_photo(UUID, TEXT, UUID);

CREATE FUNCTION add_pro_community_photo(
  p_pro_id UUID,
  p_photo_url TEXT,
  p_review_id UUID DEFAULT NULL,
  p_offering_id UUID DEFAULT NULL
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

  -- if attached to an offering, it must exist and belong to THIS pro
  IF p_offering_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_offerings
    WHERE id = p_offering_id AND pro_id = p_pro_id
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

  INSERT INTO pro_community_photos (pro_id, contributor_id, photo_url, review_id, offering_id)
  VALUES (p_pro_id, v_user_id, p_photo_url, p_review_id, p_offering_id)
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$$;

REVOKE ALL ON FUNCTION add_pro_community_photo FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION add_pro_community_photo FROM anon;
GRANT EXECUTE ON FUNCTION add_pro_community_photo TO authenticated;
