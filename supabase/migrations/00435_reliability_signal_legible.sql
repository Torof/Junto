-- ============================================================================
-- 00435 — Rendre le score de fiabilité LISIBLE et JUSTE (Scott 2026-10-01,
-- « on répare tout »). Quatre défauts, dont un trouvé par Scott lui-même.
--
-- Constat de l'audit produit : toute la machinerie de présence alimentait un
-- indicateur qui, concrètement, se résumait à « une nuance de couleur sur un
-- anneau sans légende, dans un tri cassé ». Les trois volets ci-dessous
-- s'attaquent à cette phrase, le quatrième au compteur de sorties.
--
-- (1) TRI DE DÉCOUVERTE CASSÉ. `get_discovery_cards` triait sur
--     `pp.reliability_score`, que la vue `public_profiles` force à NULL depuis
--     00347 (elle ne publie que le palier, par conception de confidentialité).
--     La clé de tri était donc constamment vide et le classement retombait sur
--     la distance seule — alors que « tri par fiabilité » est une décision
--     produit documentée. Six réécritures successives de la fonction ont
--     transporté le bug, dont deux écrites cette semaine. Corrigé en triant sur
--     `u.reliability_score` (table déjà jointe). C'est un ORDER BY : aucune
--     colonne supplémentaire n'est retournée, le score brut reste non publié.
--
-- (2) COMPTEUR DE SORTIES FAUX (trouvé par Scott). Il comptait toute
--     participation `accepted`, sans vérifier que la sortie ait eu lieu : on
--     pouvait s'inscrire à 200 sorties futures et afficher « 200 sorties »
--     immédiatement, sans y aller. Et c'est le chiffre qu'un inconnu lit sur une
--     carte Découverte avant de décider de contacter quelqu'un. Aligné sur le
--     prédicat de `get_user_public_stats` : sortie terminée, non supprimée,
--     présence non démentie.
--
-- (3) CONSTANTE DU SCORE 3 → 1. Elle écrasait les scores vers le haut au point
--     que le signal ne discriminait plus (détail dans la fonction).
--
-- (4) RECALCUL DE TOUS LES SCORES EXISTANTS, sinon le changement (3) ne
--     s'appliquerait qu'aux utilisateurs dont le score est recalculé plus tard,
--     laissant une population mélangeant deux barèmes.
--
-- Bases vivantes vérifiées : get_discovery_cards = 00426,
-- recalculate_reliability_score = 00128. Signatures inchangées.
-- Contrôle du nombre de fonctions en fin de fichier (leçon 00432/00433).
-- ============================================================================

-- ---------- 1+2. get_discovery_cards (base 00426) ----------
CREATE OR REPLACE FUNCTION get_discovery_cards()
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

-- ---------- 3. recalculate_reliability_score (base 00128) ----------
CREATE OR REPLACE FUNCTION recalculate_reliability_score(
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- 00435 : constante bayésienne 3 → 1. Avec 3, les scores étaient écrasés
  -- vers le haut au point que le signal ne discriminait plus : quelqu'un qui
  -- s'inscrit à une seule sortie et n'y va pas affichait (3+0)/(3+1) = 75 %,
  -- soit « Bonne » — le MÊME palier qu'un habitué irréprochable — et il fallait
  -- quatre défections consécutives pour tomber en « Faible ».
  -- Avec 1 : 1 absence sur 1 → 50 % (« Correcte »), 2 sur 2 → 33 % (« Faible »),
  -- et un historique sain protège toujours (10 présences + 1 absence → 92 %,
  -- « Excellente »). Un nouveau compte reste à NULL (palier « nouveau ») jusqu'à
  -- sa première sortie terminée, donc on n'affiche jamais 100 % à quelqu'un qui
  -- n'a rien fait.
  v_prior CONSTANT INTEGER := 1;
  v_total INTEGER;
  v_present INTEGER;
  v_late_cancels INTEGER;
  v_score FLOAT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('reliability_' || p_user_id::text));

  -- Validations on activities where the user is the creator AND no other
  -- accepted participant exists are recorded but don't count toward
  -- reliability — solo activities can't be peer-witnessed. The next recalc
  -- after a participant joins picks them up automatically.
  SELECT count(*) INTO v_total
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present IS NOT NULL
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  SELECT count(*) INTO v_present
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present = true
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  SELECT count(*) INTO v_late_cancels
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.status = 'withdrawn'
    AND p.left_at IS NOT NULL
    AND p.left_at > a.starts_at - INTERVAL '12 hours'
    AND p.penalty_waived = FALSE
    AND a.requires_presence = TRUE;

  v_score := ROUND(
    (((v_prior + v_present)::float / (v_prior + v_total + v_late_cancels)::float) * 100)::numeric,
    1
  )::float;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION recalculate_reliability_score(UUID) FROM PUBLIC, anon, authenticated;

-- ---------- 4. Recalcul de tous les scores existants sous le nouveau barème ----------
-- Sans ça, (3) ne vaudrait que pour les futurs recalculs : deux barèmes
-- cohabiteraient dans la base. On ne recalcule que les utilisateurs ayant déjà
-- un score (les comptes sans sortie restent à NULL → palier « nouveau »).
DO $$
DECLARE
  v_uid UUID;
  v_n INTEGER := 0;
BEGIN
  FOR v_uid IN SELECT id FROM users WHERE reliability_score IS NOT NULL LOOP
    PERFORM recalculate_reliability_score(v_uid);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'Scores recalcules sous le nouveau bareme : %', v_n;
END $$;
