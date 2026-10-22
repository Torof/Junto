-- ============================================================================
-- 00433 — RÉPARATION URGENTE : 00432 a écrasé peer_validate_presence par une
-- version de 00107.
--
-- Ce qui s'est passé : l'extraction automatique de close_due_presence_windows
-- depuis 00107 a débordé de son `$$;` et a embarqué la fonction SUIVANTE du
-- fichier — une version de peer_validate_presence antérieure de 320
-- migrations — placée APRÈS la bonne dans 00432, donc gagnante.
--
-- Ce que la version parasite réintroduisait (tout vérifié) :
--   * le FLIP DIRECT DU CRÉATEUR : `IF v_is_creator THEN UPDATE … SET
--     confirmed_present = TRUE` — le vecteur de fraude mono-attesteur retiré
--     volontairement en 00108/00140 puis pour le cas 2 en 00327 ;
--   * le verrou « le témoin doit être lui-même confirmé présent », retiré en
--     00327 parce qu'il créait un interblocage ;
--   * l'absence du seuil de 3 participants, des gardes `deleted_at` et
--     `is_demo` (00429), et de la Règle A ajoutée par 00432.
--
-- Ici : la bonne version de 00432 est réappliquée à l'identique, en dernier.
-- La 00432 reste en place (elle est déjà appliquée) ; sur une base neuve,
-- l'ordre 00432 → 00433 aboutit au bon état.
--
-- LEÇON (3e occurrence cette semaine, et la seule que j'ai commise en direct) :
-- extraire un corps de fonction par plage automatique est dangereux dès que le
-- fichier source en contient plusieurs. Toujours vérifier la LISTE des
-- fonctions créées par la migration assemblée avant de pousser — un
-- `grep -c "CREATE OR REPLACE FUNCTION"` qui ne correspond pas au nombre
-- attendu est le signal, et c'est exactement lui qui a permis de l'attraper.
-- ============================================================================

CREATE OR REPLACE FUNCTION peer_validate_presence(
  p_voted_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_voted_status TEXT;
  v_voted_present BOOLEAN;
  v_vote_count INTEGER;
  v_creator_flipped INTEGER;
  v_accepted_count INTEGER;
  v_flipped INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(
    hashtext('peer_validate:' || p_activity_id::text || ':' || p_voted_id::text)
  );

  SELECT id, status, starts_at, duration, requires_presence, deleted_at, is_demo, creator_id
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00429 : une sortie retirée par la modération ne se témoigne plus, et le
  -- rideau démo gate aussi ce chemin d'écriture.
  IF v_activity.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'junto.peer_review_unavailable';
  END IF;
  IF v_activity.is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.peer_review_no_presence';
  END IF;
  IF v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'junto.peer_review_not_completed';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.peer_review_window_not_open';
  END IF;
  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'junto.peer_review_window_closed';
  END IF;

  -- Target must be an accepted participant and not already confirmed.
  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id
  FOR UPDATE;

  IF v_voted_status IS NULL OR v_voted_status != 'accepted' THEN
    RAISE EXCEPTION 'junto.peer_review_target_not_in';
  END IF;
  -- 00429 : distinguer « déjà validé » de « fenêtre fermée, compté absent ».
  -- FALSE est posé par le finaliseur à fin+24h : dire « déjà validé » à ce
  -- moment-là est faux et déroutant.
  IF v_voted_present IS FALSE THEN
    RAISE EXCEPTION 'junto.peer_review_window_closed';
  END IF;
  IF v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'junto.peer_already_validated';
  END IF;

  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  -- Peer testimony only from 3 participants up. At 2, QR/geo is the only path.
  IF v_accepted_count < 3 THEN
    RAISE EXCEPTION 'junto.peer_review_unavailable';
  END IF;

  -- Voter must be an accepted participant (need NOT be pre-verified present).
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_vote_count
  FROM peer_validations
  WHERE activity_id = p_activity_id AND voted_id = p_voted_id;

  -- 2 distinct co-participants confirm presence.
  IF v_vote_count >= 2 THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_flipped = ROW_COUNT;
    IF v_flipped > 0 THEN
      PERFORM recalculate_reliability_score(p_voted_id);
      PERFORM notify_presence_confirmed(p_voted_id, p_activity_id);

      -- 00432 — RÈGLE A sur le chemin du TÉMOIGNAGE (manquait : 00428 ne l'a
      -- restaurée que sur géo, elle existait déjà sur QR). Deux témoignages
      -- établissent que la sortie a eu lieu avec des gens sur place → la
      -- présence du créateur est validée, exactement comme sur les deux autres
      -- chemins. Sans ça, le créateur restait NULL, n'était relancé par RIEN
      -- (il est exclu des relances PRÉCISÉMENT parce que la Règle A existe) et
      -- se faisait marquer ABSENT de sa propre sortie à fin+24h avec pénalité.
      -- ⚠️ NE JAMAIS RETIRER — même invariant que sur géo/QR, cf. SECURITY.md.
      IF v_activity.creator_id IS NOT NULL
         AND v_activity.creator_id <> p_voted_id THEN
        UPDATE participations
        SET confirmed_present = TRUE
        WHERE activity_id = p_activity_id
          AND user_id = v_activity.creator_id
          AND status = 'accepted'
          AND confirmed_present IS NULL;
        GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
        IF v_creator_flipped > 0 THEN
          PERFORM recalculate_reliability_score(v_activity.creator_id);
          PERFORM notify_presence_confirmed(v_activity.creator_id, p_activity_id, FALSE);
        END IF;
      END IF;
    END IF;
  END IF;
END;
$$;


REVOKE ALL ON FUNCTION peer_validate_presence(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION peer_validate_presence(UUID, UUID) TO authenticated;
