-- Migration 00090: fix grants on get_activity_seat_assignments
-- Previous migration's REVOKE FROM public may have blocked authenticated
-- callers. Align with the project's existing RPC grant pattern:
-- REVOKE FROM anon, GRANT TO authenticated (no parentheses, no REVOKE public).

REVOKE EXECUTE ON FUNCTION get_activity_seat_assignments FROM anon;
GRANT EXECUTE ON FUNCTION get_activity_seat_assignments TO authenticated;
