-- Migration 00019: ensure client-callable functions are not callable by anon via public role

-- The issue: even with REVOKE FROM anon + GRANT TO authenticated,
-- PostgREST may still route calls from anon because the 'public' role has EXECUTE.
-- Revoke from public, then re-grant only to authenticated.

REVOKE EXECUTE ON FUNCTION create_activity FROM public;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;

REVOKE EXECUTE ON FUNCTION set_date_of_birth(DATE) FROM public;
GRANT EXECUTE ON FUNCTION set_date_of_birth(DATE) TO authenticated;

REVOKE EXECUTE ON FUNCTION accept_tos() FROM public;
GRANT EXECUTE ON FUNCTION accept_tos() TO authenticated;
