-- ============================================================================
-- 00468 — Correctif de 00467 (H2 b) : un REVOKE de colonne n'a aucun effet
-- tant que le rôle garde le SELECT sur la TABLE. On retire le SELECT de table
-- et on le rend colonne par colonne, sans participant_info. Le client ne lit
-- jamais la table directement (get_pro_agenda / get_my_bookings, SECURITY
-- DEFINER, servent les réponses) ; la policy de 00467 reste en place.
-- ============================================================================
REVOKE SELECT ON bookings FROM authenticated, anon;
GRANT SELECT (id, offering_id, pro_id, client_id, manual_name, manual_phone, day, period,
              party_size, message, status, created_at, updated_at, submitted_count,
              last_submitted_at)
  ON bookings TO authenticated;
