-- ============================================================================
-- get_activity_detail — load a SINGLE activity by id for the detail screen,
-- including terminal statuses (completed / cancelled / expired) that
-- activities_with_coords deliberately hides from the map and lists.
--
-- Why: a notification can deep-link to an activity that has since finished.
-- Such an activity is absent from activities_with_coords (status filter) and,
-- for anyone who isn't the creator or a still-accepted participant, also from
-- my_activities / my_joined_activities — so getById returned NULL and the
-- screen sat on a skeleton. This function is getById's final fallback.
--
-- Access (validated with Scott): creator, OR anyone with any participation
-- row (every notification recipient has one), OR a public/approval activity.
-- private_link stays involved-only (token flow handles link access). The
-- detail screen still redacts member-only content (meeting map, org/chat tabs)
-- for non-participants via the participation prop — this only gates whether
-- the row loads at all, not how much of it is shown.
--
-- Returns SETOF activities_with_coords so the row shape (and the client's
-- NearbyActivity mapping) matches the public view exactly. The projection
-- below is copied verbatim from the view; only the WHERE differs.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_activity_detail(
  p_activity_id UUID
)
RETURNS SETOF activities_with_coords
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

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
    a.objective_name, a.start_name,
    a.trace_geojson,
    ST_X(COALESCE(a.location_objective, a.location_start, a.location_meeting)::geometry) AS lng,
    ST_Y(COALESCE(a.location_objective, a.location_start, a.location_meeting)::geometry) AS lat,
    ST_X(a.location_meeting::geometry) AS meeting_lng,
    ST_Y(a.location_meeting::geometry) AS meeting_lat,
    ST_X(a.location_end::geometry) AS end_lng,
    ST_Y(a.location_end::geometry) AS end_lat,
    ST_X(a.location_objective::geometry) AS objective_lng,
    ST_Y(a.location_objective::geometry) AS objective_lat,
    ST_X(a.location_start::geometry) AS start_lng,
    ST_Y(a.location_start::geometry) AS start_lat,
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
    AND NOT private.user_is_suspended(a.creator_id)
    -- Same blocked rule as the public view: hide if the viewer blocked the creator.
    AND a.creator_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
    -- Access gate: involved (creator or any participation) OR publicly listed.
    AND (
      a.creator_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id AND p.user_id = v_user_id
      )
      OR a.visibility IN ('public', 'approval')
    );
END;
$$;

REVOKE ALL ON FUNCTION get_activity_detail(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_activity_detail(UUID) TO authenticated;
