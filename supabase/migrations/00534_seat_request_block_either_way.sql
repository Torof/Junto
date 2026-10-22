-- 00534 — follow-up of 00533: the seat-request read policy really honours a
-- block in either direction.
--
-- Inside a policy, the blocked_users subquery runs with the reader's own RLS:
-- the driver cannot see a block the PASSENGER made, so the passenger's block
-- did not hide the row from the driver (caught by test C7). The check goes
-- through a definer helper that sees both directions and returns only a boolean.

CREATE OR REPLACE FUNCTION private.blocked_either_way(p_a uuid, p_b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT EXISTS (SELECT 1 FROM blocked_users
                 WHERE (blocker_id = p_a AND blocked_id = p_b) OR (blocker_id = p_b AND blocked_id = p_a));
$function$;
REVOKE ALL ON FUNCTION private.blocked_either_way(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.blocked_either_way(uuid, uuid) TO authenticated;  -- used inside RLS

DROP POLICY IF EXISTS "Users see their own seat requests" ON public.seat_requests;
CREATE POLICY "Users see their own seat requests" ON public.seat_requests
  FOR SELECT TO authenticated
  USING ((requester_id = auth.uid() OR driver_id = auth.uid())
         AND NOT private.blocked_either_way(requester_id, driver_id));
