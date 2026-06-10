-- Migration 00258: pro & offering reviews (Pro Phase 4B).
--
-- Google-Maps model, decided 2026-06-10: ungated (any authenticated
-- non-owner can review — the pro system is a storefront, there is no
-- in-app participation evidence to gate on), 1-5 stars + optional text,
-- one review per (reviewer, target), editable forever, deleted with the
-- reviewer's account (CASCADE). The pro gets a single editable reply
-- slot per review (owner-response model).
--
-- Deliberate: blocks do NOT affect review visibility — if a pro's
-- blocks hid reviews, blocking critics would be review-laundering.
-- Abuse controls are: one-per-target, 10 creations/24h, report target
-- types, moderation.
--
-- Scoped exception to the no-social-scoring principle: reviews attach
-- to the pro storefront surfaces only (pro_profiles, pro_offerings),
-- never to users or activities. Peer trust remains reliability-only.

-- ============================================================================
-- pro_reviews
-- ============================================================================
CREATE TABLE pro_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_id UUID NOT NULL REFERENCES pro_profiles(user_id) ON DELETE CASCADE,
  reviewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body TEXT CHECK (body IS NULL OR char_length(body) <= 1000),
  pro_reply TEXT CHECK (pro_reply IS NULL OR char_length(pro_reply) <= 1000),
  pro_reply_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (pro_id, reviewer_id)
);

CREATE INDEX pro_reviews_pro_created_idx ON pro_reviews(pro_id, created_at DESC);
CREATE INDEX pro_reviews_reviewer_created_idx ON pro_reviews(reviewer_id, created_at DESC);

ALTER TABLE pro_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE pro_reviews FORCE ROW LEVEL SECURITY;

-- Read-only for clients; both sides must be non-suspended. No block
-- filter by design (see header). Writes via RPCs only.
CREATE POLICY pro_reviews_select ON pro_reviews
  FOR SELECT
  TO authenticated
  USING (
    NOT private.user_is_suspended(pro_reviews.reviewer_id)
    AND NOT private.user_is_suspended(pro_reviews.pro_id)
  );

-- ============================================================================
-- offering_reviews
-- ============================================================================
CREATE TABLE offering_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offering_id UUID NOT NULL REFERENCES pro_offerings(id) ON DELETE CASCADE,
  reviewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body TEXT CHECK (body IS NULL OR char_length(body) <= 1000),
  pro_reply TEXT CHECK (pro_reply IS NULL OR char_length(pro_reply) <= 1000),
  pro_reply_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (offering_id, reviewer_id)
);

CREATE INDEX offering_reviews_offering_created_idx ON offering_reviews(offering_id, created_at DESC);
CREATE INDEX offering_reviews_reviewer_created_idx ON offering_reviews(reviewer_id, created_at DESC);

ALTER TABLE offering_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE offering_reviews FORCE ROW LEVEL SECURITY;

-- Parent-visibility EXISTS: pro_offerings RLS applies recursively and
-- already hides suspended pros' offerings (00256), so their reviews
-- inherit the gate. Positive-EXISTS shape on purpose — a NOT EXISTS
-- (...suspended...) would invert once the parent row is RLS-hidden.
CREATE POLICY offering_reviews_select ON offering_reviews
  FOR SELECT
  TO authenticated
  USING (
    NOT private.user_is_suspended(offering_reviews.reviewer_id)
    AND EXISTS (
      SELECT 1 FROM pro_offerings o WHERE o.id = offering_reviews.offering_id
    )
  );

-- ============================================================================
-- Privileged-column whitelist triggers — only rating / body / updated_at
-- are writable on a plain UPDATE (what update_* RPCs use). The reply
-- slot is RPC-managed via bypass_lock.
-- ============================================================================
CREATE OR REPLACE FUNCTION pro_reviews_whitelist_columns()
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
  NEW.reviewer_id := OLD.reviewer_id;
  NEW.pro_reply := OLD.pro_reply;
  NEW.pro_reply_at := OLD.pro_reply_at;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION pro_reviews_whitelist_columns FROM anon, authenticated;

CREATE TRIGGER pro_reviews_lock_privileged
  BEFORE UPDATE ON pro_reviews
  FOR EACH ROW EXECUTE FUNCTION pro_reviews_whitelist_columns();

CREATE OR REPLACE FUNCTION offering_reviews_whitelist_columns()
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
  NEW.offering_id := OLD.offering_id;
  NEW.reviewer_id := OLD.reviewer_id;
  NEW.pro_reply := OLD.pro_reply;
  NEW.pro_reply_at := OLD.pro_reply_at;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION offering_reviews_whitelist_columns FROM anon, authenticated;

CREATE TRIGGER offering_reviews_lock_privileged
  BEFORE UPDATE ON offering_reviews
  FOR EACH ROW EXECUTE FUNCTION offering_reviews_whitelist_columns();

-- ============================================================================
-- HTML strip triggers (backstop — RPCs sanitize before length checks)
-- ============================================================================
CREATE OR REPLACE FUNCTION strip_html_reviews()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.body IS NOT NULL THEN
    NEW.body := regexp_replace(NEW.body, '<[^>]*>', '', 'g');
  END IF;
  IF NEW.pro_reply IS NOT NULL THEN
    NEW.pro_reply := regexp_replace(NEW.pro_reply, '<[^>]*>', '', 'g');
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION strip_html_reviews FROM anon, authenticated;

CREATE TRIGGER pro_reviews_strip_html
  BEFORE INSERT OR UPDATE ON pro_reviews
  FOR EACH ROW EXECUTE FUNCTION strip_html_reviews();

CREATE TRIGGER offering_reviews_strip_html
  BEFORE INSERT OR UPDATE ON offering_reviews
  FOR EACH ROW EXECUTE FUNCTION strip_html_reviews();

-- ============================================================================
-- updated_at touch triggers. updated_at means "the review was edited" —
-- the reply RPCs run under bypass_lock and must NOT bump it, so the
-- touch is skipped in bypass mode (only the reply path uses bypass on
-- these tables).
-- ============================================================================
CREATE OR REPLACE FUNCTION reviews_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION reviews_touch_updated_at FROM anon, authenticated;

CREATE TRIGGER pro_reviews_touch_updated_at
  BEFORE UPDATE ON pro_reviews
  FOR EACH ROW EXECUTE FUNCTION reviews_touch_updated_at();

CREATE TRIGGER offering_reviews_touch_updated_at
  BEFORE UPDATE ON offering_reviews
  FOR EACH ROW EXECUTE FUNCTION reviews_touch_updated_at();

-- ============================================================================
-- create_pro_review — any authenticated non-owner, 10 reviews/24h
-- combined across both tables, one per (reviewer, pro).
-- ============================================================================
CREATE OR REPLACE FUNCTION create_pro_review(
  p_pro_id UUID,
  p_rating SMALLINT,
  p_body TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_body TEXT;
  v_daily_count INTEGER;
  v_review_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Target must be an existing, non-suspended pro; no self-review.
  IF p_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = p_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Sanitize before the length check; empty collapses to NULL.
  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  -- Serialize this reviewer's review writes: one-per-target check +
  -- combined 10/24h rate limit + insert, atomically.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reviews'));

  IF EXISTS (
    SELECT 1 FROM pro_reviews WHERE pro_id = p_pro_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT (
    (SELECT count(*) FROM pro_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
    +
    (SELECT count(*) FROM offering_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
  ) INTO v_daily_count;

  IF v_daily_count >= 10 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  BEGIN
    INSERT INTO pro_reviews (pro_id, reviewer_id, rating, body, created_at, updated_at)
    VALUES (p_pro_id, v_user_id, p_rating, v_body, now(), now())
    RETURNING id INTO v_review_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Operation not permitted';
  END;

  RETURN v_review_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_pro_review FROM anon;
GRANT EXECUTE ON FUNCTION create_pro_review TO authenticated;

-- ============================================================================
-- update_pro_review — reviewer only, rating/body only
-- ============================================================================
CREATE OR REPLACE FUNCTION update_pro_review(
  p_review_id UUID,
  p_rating SMALLINT,
  p_body TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_body TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  UPDATE pro_reviews SET rating = p_rating, body = v_body WHERE id = p_review_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_pro_review FROM anon;
GRANT EXECUTE ON FUNCTION update_pro_review TO authenticated;

-- ============================================================================
-- delete_pro_review — reviewer only
-- ============================================================================
CREATE OR REPLACE FUNCTION delete_pro_review(p_review_id UUID)
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
    SELECT 1 FROM pro_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_reviews WHERE id = p_review_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION delete_pro_review FROM anon;
GRANT EXECUTE ON FUNCTION delete_pro_review TO authenticated;

-- ============================================================================
-- reply_to_pro_review — the reviewed pro only. NULL/empty clears.
-- ============================================================================
CREATE OR REPLACE FUNCTION reply_to_pro_review(
  p_review_id UUID,
  p_reply TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_reply TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_reviews WHERE id = p_review_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_reply IS NOT NULL THEN
    v_reply := trim(regexp_replace(p_reply, '<[^>]*>', '', 'g'));
    IF char_length(v_reply) = 0 THEN v_reply := NULL; END IF;
    IF v_reply IS NOT NULL AND char_length(v_reply) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE pro_reviews
  SET pro_reply = v_reply,
      pro_reply_at = CASE WHEN v_reply IS NULL THEN NULL ELSE now() END
  WHERE id = p_review_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION reply_to_pro_review FROM anon;
GRANT EXECUTE ON FUNCTION reply_to_pro_review TO authenticated;

-- ============================================================================
-- create_offering_review — same chain, target = offering, self = its pro
-- ============================================================================
CREATE OR REPLACE FUNCTION create_offering_review(
  p_offering_id UUID,
  p_rating SMALLINT,
  p_body TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_pro_id UUID;
  v_body TEXT;
  v_daily_count INTEGER;
  v_review_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT pro_id INTO v_pro_id FROM pro_offerings WHERE id = p_offering_id;
  IF v_pro_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reviews'));

  IF EXISTS (
    SELECT 1 FROM offering_reviews WHERE offering_id = p_offering_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT (
    (SELECT count(*) FROM pro_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
    +
    (SELECT count(*) FROM offering_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
  ) INTO v_daily_count;

  IF v_daily_count >= 10 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  BEGIN
    INSERT INTO offering_reviews (offering_id, reviewer_id, rating, body, created_at, updated_at)
    VALUES (p_offering_id, v_user_id, p_rating, v_body, now(), now())
    RETURNING id INTO v_review_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Operation not permitted';
  END;

  RETURN v_review_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_offering_review FROM anon;
GRANT EXECUTE ON FUNCTION create_offering_review TO authenticated;

-- ============================================================================
-- update_offering_review — reviewer only
-- ============================================================================
CREATE OR REPLACE FUNCTION update_offering_review(
  p_review_id UUID,
  p_rating SMALLINT,
  p_body TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_body TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM offering_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  UPDATE offering_reviews SET rating = p_rating, body = v_body WHERE id = p_review_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_offering_review FROM anon;
GRANT EXECUTE ON FUNCTION update_offering_review TO authenticated;

-- ============================================================================
-- delete_offering_review — reviewer only
-- ============================================================================
CREATE OR REPLACE FUNCTION delete_offering_review(p_review_id UUID)
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
    SELECT 1 FROM offering_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM offering_reviews WHERE id = p_review_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION delete_offering_review FROM anon;
GRANT EXECUTE ON FUNCTION delete_offering_review TO authenticated;

-- ============================================================================
-- reply_to_offering_review — the offering's pro only. NULL/empty clears.
-- ============================================================================
CREATE OR REPLACE FUNCTION reply_to_offering_review(
  p_review_id UUID,
  p_reply TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_reply TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM offering_reviews r
    JOIN pro_offerings o ON o.id = r.offering_id
    WHERE r.id = p_review_id AND o.pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_reply IS NOT NULL THEN
    v_reply := trim(regexp_replace(p_reply, '<[^>]*>', '', 'g'));
    IF char_length(v_reply) = 0 THEN v_reply := NULL; END IF;
    IF v_reply IS NOT NULL AND char_length(v_reply) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE offering_reviews
  SET pro_reply = v_reply,
      pro_reply_at = CASE WHEN v_reply IS NULL THEN NULL ELSE now() END
  WHERE id = p_review_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION reply_to_offering_review FROM anon;
GRANT EXECUTE ON FUNCTION reply_to_offering_review TO authenticated;

-- ============================================================================
-- Display views — reviewer identity via public_profiles (which filters
-- suspended users in its own body). Views run as owner, so the
-- suspension filters are repeated explicitly per the SECURITY.md rule.
-- ============================================================================
CREATE VIEW pro_reviews_with_profiles AS
SELECT
  r.id,
  r.pro_id,
  r.reviewer_id,
  r.rating,
  r.body,
  r.pro_reply,
  r.pro_reply_at,
  r.created_at,
  r.updated_at,
  pp.display_name AS reviewer_name,
  pp.avatar_url AS reviewer_avatar
FROM pro_reviews r
JOIN public_profiles pp ON pp.id = r.reviewer_id
WHERE NOT private.user_is_suspended(r.reviewer_id)
  AND NOT private.user_is_suspended(r.pro_id);

GRANT SELECT ON pro_reviews_with_profiles TO authenticated;

CREATE VIEW offering_reviews_with_profiles AS
SELECT
  r.id,
  r.offering_id,
  r.reviewer_id,
  r.rating,
  r.body,
  r.pro_reply,
  r.pro_reply_at,
  r.created_at,
  r.updated_at,
  pp.display_name AS reviewer_name,
  pp.avatar_url AS reviewer_avatar
FROM offering_reviews r
JOIN public_profiles pp ON pp.id = r.reviewer_id
JOIN pro_offerings o ON o.id = r.offering_id
WHERE NOT private.user_is_suspended(r.reviewer_id)
  AND NOT private.user_is_suspended(o.pro_id);

GRANT SELECT ON offering_reviews_with_profiles TO authenticated;

-- Aggregates for the hero displays — same suspension filters so the
-- average matches the visible list.
CREATE VIEW pro_review_stats AS
SELECT
  r.pro_id,
  count(*)::int AS review_count,
  avg(r.rating)::numeric(3, 2) AS avg_rating
FROM pro_reviews r
WHERE NOT private.user_is_suspended(r.reviewer_id)
  AND NOT private.user_is_suspended(r.pro_id)
GROUP BY r.pro_id;

GRANT SELECT ON pro_review_stats TO authenticated;

CREATE VIEW offering_review_stats AS
SELECT
  r.offering_id,
  count(*)::int AS review_count,
  avg(r.rating)::numeric(3, 2) AS avg_rating
FROM offering_reviews r
JOIN pro_offerings o ON o.id = r.offering_id
WHERE NOT private.user_is_suspended(r.reviewer_id)
  AND NOT private.user_is_suspended(o.pro_id)
GROUP BY r.offering_id;

GRANT SELECT ON offering_review_stats TO authenticated;

-- ============================================================================
-- Reports — reviews become reportable targets
-- ============================================================================
ALTER TABLE reports DROP CONSTRAINT reports_target_type_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_type_check
  CHECK (target_type IN ('user', 'activity', 'wall_message', 'private_message', 'pro_review', 'offering_review'));

CREATE OR REPLACE FUNCTION create_report(
  p_target_type TEXT,
  p_target_id UUID,
  p_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_report_id UUID;
  v_hourly_count INTEGER;
  v_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type NOT IN ('user', 'activity', 'wall_message', 'private_message', 'pro_review', 'offering_review') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Sanitize first so the length check is on cleaned text.
  v_reason := regexp_replace(trim(p_reason), '<[^>]*>', '', 'g');

  IF char_length(v_reason) < 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type = 'user' AND p_target_id = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type = 'user' AND NOT EXISTS (SELECT 1 FROM users WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'activity' AND NOT EXISTS (SELECT 1 FROM activities WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'wall_message' AND NOT EXISTS (SELECT 1 FROM wall_messages WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'private_message' AND NOT EXISTS (SELECT 1 FROM private_messages WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'pro_review' AND NOT EXISTS (SELECT 1 FROM pro_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'offering_review' AND NOT EXISTS (SELECT 1 FROM offering_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM reports
    WHERE reporter_id = v_user_id AND target_type = p_target_type AND target_id = p_target_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reports'));

  SELECT count(*) INTO v_hourly_count
  FROM reports
  WHERE reporter_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO reports (reporter_id, target_type, target_id, reason, status, created_at)
  VALUES (v_user_id, p_target_type, p_target_id, v_reason, 'pending', now())
  RETURNING id INTO v_report_id;

  RETURN v_report_id;
END;
$$;
