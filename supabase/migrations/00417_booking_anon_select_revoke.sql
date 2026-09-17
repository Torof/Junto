-- ============================================================================
-- 00417 — Défense en profondeur : pas de SELECT anon sur les tables booking
-- (le RLS FORCE + policies auth.uid() renvoient déjà zéro ligne, mais
-- manual_phone est une donnée personnelle — double serrure, pattern users).
-- ============================================================================
REVOKE SELECT ON bookings FROM anon, PUBLIC;
REVOKE SELECT ON pro_availabilities FROM anon, PUBLIC;
