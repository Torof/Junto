-- 00578 revoked every private function from visitors (GRANTS-4) — but the
-- visitor map view (activities_with_coords) calls private.user_is_suspended,
-- and a function inside a view is executed with the CALLER's EXECUTE right.
-- Visitors get back exactly that one function (it only says whether a given
-- account is suspended — the map already hides those outings).
GRANT USAGE ON SCHEMA private TO anon;
GRANT EXECUTE ON FUNCTION private.user_is_suspended(uuid) TO anon;
