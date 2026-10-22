-- Migration 00307: house-standard tightening — the presence-activities RPC
-- kept the default PUBLIC execute grant since its creation (anon calls
-- returned [] via the internal auth guard; no leak, but belt-and-braces).
REVOKE EXECUTE ON FUNCTION get_my_active_presence_activities FROM PUBLIC, anon;
