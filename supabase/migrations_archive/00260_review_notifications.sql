-- Migration 00260: review notifications.
--
-- Two new types in the spine:
--   review_received — to the pro, when a review lands on their page or
--                     one of their offerings (create only, not edits).
--   review_reply    — to the reviewer, when the pro replies (first
--                     reply only — reply edits and clears stay silent).
--
-- Both flow through create_notification (prefs gate + suspension check
-- + sanitize) and the AFTER INSERT push trigger — no direct http_post
-- needed since neither type aggregates in place.

-- ============================================================================
-- 1. Notify helpers (internal — REVOKE all client roles)
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_review_received(
  p_pro_id UUID,
  p_reviewer_name TEXT,
  p_rating SMALLINT,
  p_target_label TEXT,
  p_data JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean_name TEXT;
  v_clean_label TEXT;
BEGIN
  v_clean_name := sanitize_notif_text(coalesce(p_reviewer_name, 'Quelqu''un'));
  v_clean_label := sanitize_notif_text(coalesce(p_target_label, ''));
  PERFORM create_notification(
    p_pro_id,
    'review_received',
    'Nouvel avis',
    v_clean_name || ' a laissé un avis (' || p_rating || '★) sur ' || v_clean_label,
    p_data
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_review_received FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION notify_review_reply(
  p_reviewer_id UUID,
  p_pro_name TEXT,
  p_target_label TEXT,
  p_data JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean_name TEXT;
  v_clean_label TEXT;
BEGIN
  v_clean_name := sanitize_notif_text(coalesce(p_pro_name, 'Le pro'));
  v_clean_label := sanitize_notif_text(coalesce(p_target_label, ''));
  PERFORM create_notification(
    p_reviewer_id,
    'review_reply',
    'Réponse à ton avis',
    v_clean_name || ' a répondu à ton avis sur ' || v_clean_label,
    p_data
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_review_reply FROM public, anon, authenticated;

-- ============================================================================
-- 2. create_pro_review — unchanged chain + notify at the end
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
  v_reviewer_name TEXT;
  v_pro_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

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

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

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

  SELECT display_name INTO v_reviewer_name FROM users WHERE id = v_user_id;
  SELECT display_name INTO v_pro_name FROM pro_profiles WHERE user_id = p_pro_id;
  PERFORM notify_review_received(
    p_pro_id,
    v_reviewer_name,
    p_rating,
    v_pro_name,
    jsonb_build_object('pro_id', p_pro_id, 'review_id', v_review_id)
  );

  RETURN v_review_id;
END;
$$;

-- ============================================================================
-- 3. create_offering_review — unchanged chain + notify at the end
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
  v_reviewer_name TEXT;
  v_offering_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT pro_id, title INTO v_pro_id, v_offering_title FROM pro_offerings WHERE id = p_offering_id;
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

  SELECT display_name INTO v_reviewer_name FROM users WHERE id = v_user_id;
  PERFORM notify_review_received(
    v_pro_id,
    v_reviewer_name,
    p_rating,
    v_offering_title,
    jsonb_build_object('offering_id', p_offering_id, 'review_id', v_review_id)
  );

  RETURN v_review_id;
END;
$$;

-- ============================================================================
-- 4. reply_to_pro_review — notify the reviewer on FIRST reply only
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
  v_reviewer_id UUID;
  v_had_reply BOOLEAN;
  v_pro_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT reviewer_id, pro_reply IS NOT NULL
  INTO v_reviewer_id, v_had_reply
  FROM pro_reviews
  WHERE id = p_review_id AND pro_id = v_user_id;

  IF v_reviewer_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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

  IF v_reply IS NOT NULL AND NOT v_had_reply THEN
    SELECT display_name INTO v_pro_name FROM pro_profiles WHERE user_id = v_user_id;
    PERFORM notify_review_reply(
      v_reviewer_id,
      v_pro_name,
      v_pro_name,
      jsonb_build_object('pro_id', v_user_id, 'review_id', p_review_id)
    );
  END IF;
END;
$$;

-- ============================================================================
-- 5. reply_to_offering_review — notify the reviewer on FIRST reply only
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
  v_reviewer_id UUID;
  v_had_reply BOOLEAN;
  v_offering_id UUID;
  v_offering_title TEXT;
  v_pro_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT r.reviewer_id, r.pro_reply IS NOT NULL, o.id, o.title
  INTO v_reviewer_id, v_had_reply, v_offering_id, v_offering_title
  FROM offering_reviews r
  JOIN pro_offerings o ON o.id = r.offering_id
  WHERE r.id = p_review_id AND o.pro_id = v_user_id;

  IF v_reviewer_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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

  IF v_reply IS NOT NULL AND NOT v_had_reply THEN
    SELECT display_name INTO v_pro_name FROM pro_profiles WHERE user_id = v_user_id;
    PERFORM notify_review_reply(
      v_reviewer_id,
      v_pro_name,
      v_offering_title,
      jsonb_build_object('offering_id', v_offering_id, 'review_id', p_review_id)
    );
  END IF;
END;
$$;

-- ============================================================================
-- 6. Prefs: DEFAULT + backfill (00168 pattern). Both types default ON.
-- ============================================================================
ALTER TABLE users
  ALTER COLUMN notification_preferences SET DEFAULT '{
    "join_request": true,
    "participant_joined": false,
    "request_accepted": true,
    "request_refused": true,
    "participant_removed": true,
    "participant_left": false,
    "participant_left_late": true,
    "activity_cancelled": true,
    "activity_updated": false,
    "rate_participants": true,
    "presence_pre_warning": true,
    "presence_pre_warning_10min": true,
    "presence_validate_warning": true,
    "presence_validate_overdue": true,
    "presence_confirmed": true,
    "badge_unlocked": true,
    "qr_create_reminder": true,
    "peer_review_closing": true,
    "seat_request": true,
    "seat_request_accepted": true,
    "seat_request_declined": true,
    "seat_request_expired": true,
    "driver_left": true,
    "contact_request": true,
    "contact_request_accepted": true,
    "alert_match": true,
    "review_received": true,
    "review_reply": true
  }'::jsonb;

-- Backfill: only the two new keys, preserving every existing choice.
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users
  SET notification_preferences =
    '{"review_received": true, "review_reply": true}'::jsonb || notification_preferences
  WHERE notification_preferences IS NOT NULL
    AND NOT (notification_preferences ? 'review_received');
END;
$$;
