-- ============================================================================
-- 00425 — Découverte : les cartes connaissent l'état de relation de la paire
-- (audit du flux Contacter/Inviter, Scott 2026-09-30).
-- Problème : les boutons ignoraient la relation existante — pour une paire
-- déjà CONNECTÉE, « Contacter » toastait « envoyée » sans rien envoyer et
-- « Inviter » échouait en générique ; pour une demande EN ATTENTE, un reload
-- ré-armait le bouton et le re-tap prenait une erreur sèche.
-- Fix : + contact_state ('none' | 'pending' | 'connected') et conversation_id
-- (UNIQUEMENT si active). Anti-oracle intact : un refus (declined) est rendu
-- comme 'pending' — même règle que get_conversation_state_with (00351) ; le
-- refus silencieux reste indistinguable d'une attente.
-- Base : 00394 (dernière version, vérifiée). Chaîne d'autorisation inchangée.
-- ============================================================================
DROP FUNCTION get_discovery_cards();
CREATE FUNCTION get_discovery_cards()
RETURNS TABLE (
  user_id UUID, display_name TEXT, avatar_url TEXT, reliability_tier TEXT,
  sport_keys TEXT[], levels JSONB, transport_modes TEXT[], radius_km INTEGER,
  window_start TIMESTAMPTZ, window_end TIMESTAMPTZ, intent TEXT[],
  distance_km DOUBLE PRECISION, sorties_count INTEGER, about TEXT,
  contact_state TEXT, conversation_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_radius INTEGER;
  v_sports TEXT[];
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  SELECT d.base, d.radius_km, d.sport_keys, d.window_start, d.window_end
    INTO v_base, v_radius, v_sports, v_ws, v_we
  FROM discovery_availabilities d WHERE d.user_id = v_user_id AND d.is_active;
  IF v_base IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT d.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         d.sport_keys, d.levels, d.transport_modes, d.radius_km,
         d.window_start, d.window_end, d.intent,
         (ST_Distance(d.base, v_base) / 1000.0) AS distance_km,
         (SELECT count(*)::int FROM participations p
          WHERE p.user_id = d.user_id AND p.status = 'accepted') AS sorties_count,
         d.about,
         coalesce((
           SELECT CASE WHEN c.status = 'active' THEN 'connected' ELSE 'pending' END
           FROM conversations c
           WHERE c.type = 'dm'
             AND c.user_1 = LEAST(v_user_id, d.user_id)
             AND c.user_2 = GREATEST(v_user_id, d.user_id)
         ), 'none') AS contact_state,
         (
           SELECT c.id FROM conversations c
           WHERE c.type = 'dm' AND c.status = 'active'
             AND c.user_1 = LEAST(v_user_id, d.user_id)
             AND c.user_2 = GREATEST(v_user_id, d.user_id)
         ) AS conversation_id
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  JOIN public_profiles pp ON pp.id = d.user_id
  WHERE d.is_active
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && v_sports
    AND tstzrange(d.window_start, d.window_end) && tstzrange(v_ws, v_we)
    AND (v_radius IS NULL OR d.radius_km IS NULL
         OR ST_DWithin(d.base, v_base, (v_radius + d.radius_km) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id))
  ORDER BY pp.reliability_score DESC NULLS LAST, distance_km ASC;
END;
$$;
REVOKE ALL ON FUNCTION get_discovery_cards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_discovery_cards() TO authenticated;
