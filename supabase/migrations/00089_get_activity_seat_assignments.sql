-- Migration 00089: expose accepted seat assignments to all activity participants
-- RLS on seat_requests only lets requester+driver see their own rows, so a
-- third co-participant cannot see who's riding with whom. This SECURITY DEFINER
-- function exposes accepted assignments to any accepted participant of the
-- activity, for UI display (seat pips, passenger list, etc.).
--
-- Authorization chain:
--   1. auth.uid() IS NOT NULL
--   2. caller is not suspended (users.suspended_at IS NULL)
--   3. caller is an accepted participant of p_activity_id

CREATE OR REPLACE FUNCTION get_activity_seat_assignments(p_activity_id UUID)
RETURNS TABLE (
  id UUID,
  driver_id UUID,
  requester_id UUID,
  display_name TEXT,
  avatar_url TEXT
)
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

  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id
      AND user_id = v_user_id
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
    SELECT
      sr.id,
      sr.driver_id,
      sr.requester_id,
      pp.display_name,
      pp.avatar_url
    FROM seat_requests sr
    JOIN public_profiles pp ON pp.id = sr.requester_id
    WHERE sr.activity_id = p_activity_id
      AND sr.status = 'accepted';
END;
$$;

REVOKE EXECUTE ON FUNCTION get_activity_seat_assignments(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION get_activity_seat_assignments(UUID) FROM public;
GRANT EXECUTE ON FUNCTION get_activity_seat_assignments(UUID) TO authenticated;
