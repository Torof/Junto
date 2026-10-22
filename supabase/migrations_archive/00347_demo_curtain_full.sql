-- ============================================================================
-- 00347 — SECURITY FIX: extend the demo curtain to every read surface (audit).
--
-- Demo mode gated only the 3 map/list views; the base tables, get_activity_detail
-- and the review/profile views had no demo predicate, so an authenticated
-- non-admin could read demo content (activities, offerings, reviews, demo user
-- identities, photos) directly via PostgREST, independent of the demo_mode flag.
--
-- Fix: add `(is_demo = false OR demo_content_visible())` to every remaining
-- surface, gating on the row's own is_demo (activities/offerings) or the parent
-- pro/offering's is_demo (photos/reviews/stats). SAFE BY CONSTRUCTION: the
-- clause is always true for non-demo rows, so real content is never affected —
-- only is_demo=true rows are hidden from non-admins (admin+toggle-on still sees).
-- ============================================================================

-- 1) activities base SELECT policy — demo gate on the discoverable branch.
ALTER POLICY "activities_select_authenticated" ON activities
  USING (
    NOT private.user_is_suspended(auth.uid())
    AND (
      (
        status IN ('published', 'in_progress')
        AND deleted_at IS NULL
        AND visibility IN ('public', 'approval')
        AND (is_demo = false OR demo_content_visible())
        AND NOT private.user_is_suspended(activities.creator_id)
        AND creator_id NOT IN (
          SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
        )
      )
      OR auth.uid() = creator_id
      OR EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = activities.id
          AND user_id = auth.uid()
          AND status IN ('accepted', 'pending')
      )
    )
  );

-- 2) pro_offerings base SELECT policy.
ALTER POLICY pro_offerings_select ON pro_offerings
  USING (
    NOT private.user_is_suspended(pro_offerings.pro_id)
    AND (is_demo = false OR demo_content_visible())
  );

-- 3) pro_profile_photos — gate on the parent pro's is_demo.
ALTER POLICY pro_profile_photos_select ON pro_profile_photos
  USING (
    NOT private.user_is_suspended(pro_profile_photos.pro_id)
    AND (demo_content_visible() OR EXISTS (
      SELECT 1 FROM pro_profiles dp WHERE dp.user_id = pro_profile_photos.pro_id AND dp.is_demo = false
    ))
  );

-- 4) pro_offering_photos — gate inside the parent-offering EXISTS.
ALTER POLICY pro_offering_photos_select ON pro_offering_photos
  USING (
    EXISTS (
      SELECT 1 FROM pro_offerings o
      WHERE o.id = pro_offering_photos.offering_id
        AND NOT private.user_is_suspended(o.pro_id)
        AND (o.is_demo = false OR demo_content_visible())
    )
  );

-- 5) pro_reviews base SELECT policy — gate on the parent pro.
ALTER POLICY pro_reviews_select ON pro_reviews
  USING (
    NOT private.user_is_suspended(pro_reviews.reviewer_id)
    AND NOT private.user_is_suspended(pro_reviews.pro_id)
    AND (demo_content_visible() OR EXISTS (
      SELECT 1 FROM pro_profiles dp WHERE dp.user_id = pro_reviews.pro_id AND dp.is_demo = false
    ))
  );

-- 6) offering_reviews base SELECT policy — gate inside the parent-offering EXISTS.
ALTER POLICY offering_reviews_select ON offering_reviews
  USING (
    NOT private.user_is_suspended(offering_reviews.reviewer_id)
    AND EXISTS (
      SELECT 1 FROM pro_offerings o
      WHERE o.id = offering_reviews.offering_id
        AND (o.is_demo = false OR demo_content_visible())
    )
  );

-- 7) get_activity_detail RPC — demo gate in its WHERE (reproduced from 00316).
CREATE OR REPLACE FUNCTION get_activity_detail(p_activity_id UUID)
RETURNS SETOF activities_with_coords
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT
    a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
    a.distance_km, a.elevation_gain_m,
    a.max_participants, a.starts_at, a.duration, a.visibility,
    a.requires_presence,
    a.status, a.deleted_at, a.created_at, a.updated_at,
    a.objective_name, a.meeting_name,
    a.trace_geojson,
    ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
    ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
    ST_X(a.location_meeting::geometry) AS meeting_lng,
    ST_Y(a.location_meeting::geometry) AS meeting_lat,
    ST_X(a.location_end::geometry) AS end_lng,
    ST_Y(a.location_end::geometry) AS end_lat,
    ST_X(a.location_objective::geometry) AS objective_lng,
    ST_Y(a.location_objective::geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    (SELECT count(*)::int FROM participations p
     WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
    a.level_max
  FROM activities a
  JOIN public_profiles pp ON a.creator_id = pp.id
  JOIN sports s ON a.sport_id = s.id
  WHERE a.id = p_activity_id
    AND a.deleted_at IS NULL
    AND (a.is_demo = false OR demo_content_visible())
    AND NOT private.user_is_suspended(a.creator_id)
    AND a.creator_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
    AND (
      a.creator_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id AND p.user_id = v_user_id
          AND p.status IN ('accepted', 'pending')
      )
      OR a.visibility IN ('public', 'approval')
    );
END;
$$;
REVOKE ALL ON FUNCTION get_activity_detail(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_activity_detail(UUID) TO authenticated;

-- 8) public_profiles — hide demo users (the gate handles the admin case; real
--    users never join to a demo user, so no legit rows drop).
CREATE OR REPLACE VIEW public_profiles AS
  SELECT id, display_name, avatar_url, bio, sports, levels_per_sport, created_at,
         NULL::double precision AS reliability_score,
         reliability_tier(reliability_score) AS reliability_tier
  FROM users
  WHERE suspended_at IS NULL
    AND (is_demo = false OR demo_content_visible());
REVOKE SELECT ON public_profiles FROM anon;

-- 9) Review display + stats views — demo gate on the parent pro/offering.
CREATE OR REPLACE VIEW pro_reviews_with_profiles AS
SELECT r.id, r.pro_id, r.reviewer_id, r.rating, r.body, r.pro_reply, r.pro_reply_at,
       r.created_at, r.updated_at,
       pp.display_name AS reviewer_name, pp.avatar_url AS reviewer_avatar
FROM pro_reviews r
JOIN public_profiles pp ON pp.id = r.reviewer_id
WHERE NOT private.user_is_suspended(r.reviewer_id)
  AND NOT private.user_is_suspended(r.pro_id)
  AND (demo_content_visible() OR EXISTS (SELECT 1 FROM pro_profiles dp WHERE dp.user_id = r.pro_id AND dp.is_demo = false));
GRANT SELECT ON pro_reviews_with_profiles TO authenticated;

CREATE OR REPLACE VIEW offering_reviews_with_profiles AS
SELECT r.id, r.offering_id, r.reviewer_id, r.rating, r.body, r.pro_reply, r.pro_reply_at,
       r.created_at, r.updated_at,
       pp.display_name AS reviewer_name, pp.avatar_url AS reviewer_avatar
FROM offering_reviews r
JOIN public_profiles pp ON pp.id = r.reviewer_id
JOIN pro_offerings o ON o.id = r.offering_id
WHERE NOT private.user_is_suspended(r.reviewer_id)
  AND NOT private.user_is_suspended(o.pro_id)
  AND (o.is_demo = false OR demo_content_visible());
GRANT SELECT ON offering_reviews_with_profiles TO authenticated;

CREATE OR REPLACE VIEW pro_review_stats AS
SELECT r.pro_id, count(*)::int AS review_count, avg(r.rating)::numeric(3, 2) AS avg_rating
FROM pro_reviews r
WHERE NOT private.user_is_suspended(r.reviewer_id)
  AND NOT private.user_is_suspended(r.pro_id)
  AND (demo_content_visible() OR EXISTS (SELECT 1 FROM pro_profiles dp WHERE dp.user_id = r.pro_id AND dp.is_demo = false))
GROUP BY r.pro_id;
GRANT SELECT ON pro_review_stats TO authenticated;

CREATE OR REPLACE VIEW offering_review_stats AS
SELECT r.offering_id, count(*)::int AS review_count, avg(r.rating)::numeric(3, 2) AS avg_rating
FROM offering_reviews r
JOIN pro_offerings o ON o.id = r.offering_id
WHERE NOT private.user_is_suspended(r.reviewer_id)
  AND NOT private.user_is_suspended(o.pro_id)
  AND (o.is_demo = false OR demo_content_visible())
GROUP BY r.offering_id;
GRANT SELECT ON offering_review_stats TO authenticated;
