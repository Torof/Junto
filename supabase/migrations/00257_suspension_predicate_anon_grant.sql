-- Migration 00257: grant the suspension predicate to anon.
--
-- 00256 put private.user_is_suspended() in the body of
-- activities_with_coords. Table access through a view is checked
-- against the view owner, but FUNCTION calls in a view body execute
-- with the caller's privileges (same mechanism that lets auth.uid()
-- resolve to the caller). anon had no USAGE on the schema nor EXECUTE
-- on the function, so the visitor map got "permission denied for
-- function user_is_suspended".
--
-- Safe to grant: the private schema is not exposed by PostgREST
-- (verified: /rest/v1/rpc/user_is_suspended → 404), and anon has no
-- other SQL surface. The function body runs as its owner either way.

GRANT USAGE ON SCHEMA private TO anon;
GRANT EXECUTE ON FUNCTION private.user_is_suspended(UUID) TO anon;
