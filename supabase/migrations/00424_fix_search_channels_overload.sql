-- ============================================================================
-- 00424 — RÉPARATION : 00423 est reparti du corps 00382 (5 params) alors que
-- la version vivante était 00404 (4 params, + radius_km/photo_url) → une
-- SURCHARGE a été créée au lieu d'un remplacement → PostgREST ambigu → la
-- liste des discussions rendait vide (régression signalée par Scott).
-- Ici : DROP de la surcharge fautive, et la version 00404 reprend du service
-- avec l'extension voulue par 00423 (la requête libre matche aussi le sport
-- et la description).
-- ============================================================================
DROP FUNCTION IF EXISTS search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER);

CREATE OR REPLACE FUNCTION search_channels(
  p_query TEXT DEFAULT NULL,
  p_sport_key TEXT DEFAULT NULL,
  p_near_lng DOUBLE PRECISION DEFAULT NULL,
  p_near_lat DOUBLE PRECISION DEFAULT NULL
) RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_key TEXT, base_label TEXT, radius_km INTEGER, description TEXT,
  photo_url TEXT, distance_km DOUBLE PRECISION, member_count INTEGER, is_member BOOLEAN, is_creator BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_near GEOGRAPHY;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  v_near := CASE WHEN p_near_lng IS NOT NULL AND p_near_lat IS NOT NULL
                 THEN ST_SetSRID(ST_MakePoint(p_near_lng, p_near_lat), 4326)::geography END;

  RETURN QUERY
  SELECT c.conversation_id, conv.name, c.sport_key, c.base_label, c.radius_km, c.description, c.photo_url,
         CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) / 1000.0 END AS distance_km,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id) AS member_count,
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id) AS is_member,
         (c.created_by = v_user_id) AS is_creator
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.closed_at IS NULL
    AND (p_sport_key IS NULL OR p_sport_key = c.sport_key)
    AND (p_query IS NULL
         OR conv.name ILIKE '%' || p_query || '%'
         OR c.base_label ILIKE '%' || p_query || '%'
         OR c.sport_key ILIKE '%' || p_query || '%'
         OR coalesce(c.description, '') ILIKE '%' || p_query || '%')
    AND (v_near IS NULL OR ST_DWithin(c.base, v_near, c.radius_km * 1000.0))
    AND NOT EXISTS (SELECT 1 FROM channel_bans b WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id)
  ORDER BY
    CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) END ASC NULLS LAST,
    (SELECT count(*) FROM conversation_members m WHERE m.conversation_id = c.conversation_id) DESC,
    c.created_at DESC
  LIMIT 60;
END;
$$;
REVOKE ALL ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
