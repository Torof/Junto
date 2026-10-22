-- 00536 — a suspended organiser's outing stays hidden from strangers on the
-- participant list too (audit 2026-10-23, outings F2).
--
-- get_activity_detail and get_transport_summary already hid it (AC-11), but
-- get_activity_participants still served the participants' identities to any
-- signed-in stranger. get_activity_seat_assignments now also refuses a deleted
-- outing or a suspended organiser's (frozen) one.

CREATE OR REPLACE FUNCTION public.get_activity_participants(p_activity_id uuid)
 RETURNS TABLE(participation_id uuid, activity_id uuid, user_id uuid, status text, created_at timestamp with time zone, left_at timestamp with time zone, confirmed_present boolean, transport_type text, transport_seats smallint, transport_from_name text, transport_departs_at timestamp with time zone, transport_from_lat double precision, transport_from_lng double precision, display_name text, avatar_url text, transport_from_locality text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_creator BOOLEAN;
  v_is_member BOOLEAN;
  v_live BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      -- 00472 (audit L3): the demo curtain, like every other read surface.
      AND (a.is_demo = false OR demo_content_visible())
      AND a.deleted_at IS NULL  -- 00516
      AND (
        -- 00536: a suspended organiser's outing is hidden from strangers (AC-11).
        (a.visibility IN ('public', 'approval') AND NOT private.user_is_suspended(a.creator_id))
        OR a.creator_id = v_user_id
        -- 00485 (AC-2): only an ACCEPTED participant, not a removed / left one.
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ) THEN
    RETURN;
  END IF;

  SELECT a.creator_id = v_user_id, a.status IN ('published', 'in_progress')
    INTO v_is_creator, v_live
  FROM activities a WHERE a.id = p_activity_id;
  v_is_member := v_is_creator OR EXISTS (
    SELECT 1 FROM participations p
    WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id AND p.status = 'accepted');

  RETURN QUERY
  SELECT
    p.id AS participation_id,
    p.activity_id,
    p.user_id,
    p.status,
    p.created_at,
    p.left_at,
    -- 00485 (DX-1): an absence is shown only to the organiser and to the
    -- person concerned; everyone else sees « present » or nothing.
    CASE WHEN p.user_id = v_user_id OR v_is_creator THEN p.confirmed_present
         -- 00488: only fellow members see « present » (once an outing is
         -- finalised, a missing tick would otherwise read as an absence).
         WHEN v_is_member AND p.confirmed_present THEN true ELSE NULL END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_type END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_seats END,
    -- 00485 (AC-2): a driver's starting point (often home) is shown only to
    -- the outing's accepted members, while it is upcoming / under way, and
    -- never across a block.
    -- 00521: the exact start point (often home) only for the driver's own
    -- accepted passengers; other members see the village (last column).
    CASE WHEN (p.user_id = v_user_id OR (v_live AND EXISTS (
      SELECT 1 FROM seat_requests sr WHERE sr.activity_id = p_activity_id
        AND sr.driver_id = p.user_id AND sr.requester_id = v_user_id AND sr.status = 'accepted')
      AND NOT EXISTS (SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
           OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_name END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_departs_at END,
    CASE WHEN (p.user_id = v_user_id OR (v_live AND EXISTS (
      SELECT 1 FROM seat_requests sr WHERE sr.activity_id = p_activity_id
        AND sr.driver_id = p.user_id AND sr.requester_id = v_user_id AND sr.status = 'accepted')
      AND NOT EXISTS (SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
           OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lat END,
    CASE WHEN (p.user_id = v_user_id OR (v_live AND EXISTS (
      SELECT 1 FROM seat_requests sr WHERE sr.activity_id = p_activity_id
        AND sr.driver_id = p.user_id AND sr.requester_id = v_user_id AND sr.status = 'accepted')
      AND NOT EXISTS (SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
           OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lng END,
    pp.display_name,
    pp.avatar_url,
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_locality END
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
  ORDER BY p.created_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_activity_seat_assignments(p_activity_id uuid)
 RETURNS TABLE(id uuid, driver_id uuid, requester_id uuid, display_name text, avatar_url text, pickup_from text, requested_pickup_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_creator UUID;
  v_live BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations p
    JOIN activities a ON a.id = p.activity_id
    WHERE p.activity_id = p_activity_id
      AND p.user_id = v_user_id
      AND p.status = 'accepted'
      AND a.deleted_at IS NULL                        -- 00536
      AND NOT private.user_is_suspended(a.creator_id) -- 00536: frozen outing
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.creator_id, a.status IN ('published', 'in_progress') INTO v_creator, v_live
  FROM activities a WHERE a.id = p_activity_id;

  RETURN QUERY
    SELECT
      sr.id,
      sr.driver_id,
      sr.requester_id,
      pp.display_name,
      pp.avatar_url,
      -- 00488: a pickup point (often home) goes to the driver, the passenger
      -- and the organiser; other members see it only while the outing is live.
      -- 00521: a pickup point goes to the driver, the passenger and the organiser only.
      CASE WHEN v_user_id IN (sr.driver_id, sr.requester_id, v_creator) THEN sr.pickup_from END,
      CASE WHEN v_user_id IN (sr.driver_id, sr.requester_id, v_creator) THEN sr.requested_pickup_at END
    FROM seat_requests sr
    JOIN public_profiles pp ON pp.id = sr.requester_id
    WHERE sr.activity_id = p_activity_id
      AND sr.status = 'accepted'
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id IN (sr.driver_id, sr.requester_id))
           OR (b.blocked_id = v_user_id AND b.blocker_id IN (sr.driver_id, sr.requester_id))
      );
END;
$function$;
