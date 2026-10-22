-- ============================================================================
-- 00442 — Expose the demo flag to the client (Scott 2026-10-08).
--
-- Since 00426, send_contact_request / invite refuse any is_demo target (write
-- curtain, admin in demo mode included — invariant kept). But the Discovery
-- cards and the public profile did not say WHICH people are demo, so the
-- admin testing in demo mode tapped « Contacter » / « Demander le contact »
-- and got a generic error. The server was right; the UI could not know.
--
-- Two read surfaces gain `is_demo` (the flag only — a boolean the demo user
-- already reveals by existing behind the curtain). No authorization change.
--   public_profiles      ← base 00347 (anon REVOKE re-applied; later copies: none)
--   get_discovery_cards  ← base 00435 (return type changes → DROP first, PGRST203)
-- ============================================================================

CREATE OR REPLACE VIEW public_profiles AS
  SELECT id, display_name, avatar_url, bio, sports, levels_per_sport, created_at,
         NULL::double precision AS reliability_score,
         reliability_tier(reliability_score) AS reliability_tier,
         is_demo
  FROM users
  WHERE suspended_at IS NULL
    AND (is_demo = false OR demo_content_visible());
REVOKE SELECT ON public_profiles FROM anon;

DROP FUNCTION IF EXISTS get_discovery_cards();
CREATE OR REPLACE FUNCTION get_discovery_cards()
RETURNS TABLE (
  user_id UUID, display_name TEXT, avatar_url TEXT, reliability_tier TEXT,
  sport_keys TEXT[], levels JSONB, transport_modes TEXT[], radius_km INTEGER,
  window_start TIMESTAMPTZ, window_end TIMESTAMPTZ, intent TEXT[],
  distance_km DOUBLE PRECISION, sorties_count INTEGER, about TEXT,
  contact_state TEXT, conversation_id UUID,
  is_demo BOOLEAN
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
         -- 00435 (trouvé par Scott) : ce compteur n'exigeait QUE status =
         -- 'accepted' — donc s'inscrire à 200 sorties futures affichait
         -- « 200 sorties » immédiatement, sans qu'aucune ait eu lieu. Et c'est
         -- le chiffre qu'un inconnu lit avant de décider de te contacter. On
         -- applique le même prédicat que get_user_public_stats : sortie
         -- réellement terminée, et présence non démentie.
         (SELECT count(*)::int FROM participations p
          JOIN activities pa ON pa.id = p.activity_id
          WHERE p.user_id = d.user_id
            AND p.status = 'accepted'
            AND p.confirmed_present IS DISTINCT FROM false
            AND pa.status = 'completed'
            AND pa.deleted_at IS NULL) AS sorties_count,
         d.about,
         coalesce((
           SELECT CASE
             WHEN c.status = 'active' THEN 'connected'
             WHEN c.request_sender_id = v_user_id THEN 'pending'
             WHEN c.status = 'pending_request' AND c.request_expires_at > NOW() THEN 'pending_received'
             ELSE 'none'
           END
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
         ) AS conversation_id,
         u.is_demo
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
  -- 00435 : le tri portait sur pp.reliability_score, que la vue public_profiles
  -- force à NULL depuis 00347 (elle ne publie que le palier) → clé de tri
  -- constamment vide, classement dégénéré en distance seule, et ce depuis six
  -- réécritures de cette fonction. On trie sur la table users, déjà jointe
  -- ligne « JOIN users u ». Ce n'est qu'un ORDER BY : aucune colonne
  -- supplémentaire n'est retournée, donc le score brut reste non publié.
  ORDER BY u.reliability_score DESC NULLS LAST, distance_km ASC;
END;
$$;

REVOKE ALL ON FUNCTION get_discovery_cards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_discovery_cards() TO authenticated;
