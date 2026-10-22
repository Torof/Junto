-- Migration 00304: revoke Supabase's default table grants from anon on
-- activity_gear_missing (house standard, cf. 00288). RLS already returned
-- zero rows to anon; this makes the deny explicit at the grant layer too.
REVOKE ALL ON activity_gear_missing FROM anon;
