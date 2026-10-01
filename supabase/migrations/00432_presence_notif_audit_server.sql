-- ============================================================================
-- 00432 — Audit des notifications de présence : corrections serveur
-- (Scott 2026-10-01, « je te laisse choisir ce qui fait le plus de sens et qui
-- est le mieux en termes d'expérience utilisateur »).
--
-- (1) RÈGLE A sur le chemin du TÉMOIGNAGE — le trou que 00428 n'a pas couvert.
--     00428 l'a restaurée sur géo, elle existait déjà sur QR, elle n'a JAMAIS
--     existé sur peer_validate_presence. Conséquence : sortie à 3+, QR jamais
--     sorti, fenêtre géo manquée, les deux participants se témoignent
--     mutuellement → le créateur reste NULL, n'est relancé par RIEN (il est
--     exclu des relances PRÉCISÉMENT parce que la Règle A devait s'en charger)
--     et se fait marquer ABSENT de sa propre sortie à fin+24h avec pénalité.
--     La même preuve était jugée suffisante pour pénaliser les autres et
--     insuffisante pour le valider, lui.
--     Arbitrage (délégué) : on étend la Règle A plutôt que de simplement ne pas
--     le pénaliser. Junto a déjà posé la doctrine « quelqu'un d'autre a
--     confirmé ⇒ la sortie a eu lieu ⇒ l'organisateur y était » sur géo et QR
--     (00291/00292) ; être incohérent sur le 3e chemin est pire que le risque
--     théorique de créditer un organisateur absent. Et l'option prudente
--     laissait les organisateurs ne jamais capitaliser leurs propres sorties.
--
-- (2) LES DEUX PRÉ-AVERTISSEMENTS N'ÉCRIVENT PLUS AU CRÉATEUR. Il recevait
--     « prépare-toi à valider ta présence sur place » alors qu'il n'a AUCUN
--     chemin d'auto-validation (invariant 00292), et la fiche d'activité ne
--     mentionnait même pas la présence pour lui à T-2h. Son action à lui c'est
--     qr_create_reminder (T-10min), qui reste.
--
-- (3) RELANCES ÉTENDUES AUX SORTIES À 2 (seuil 3 → 2) avec une copy dédiée.
--     C'était la configuration la plus mal servie : le QR y est le SEUL recours
--     (le témoignage exige 3) et elle ne recevait RIEN entre T+15min et fin+3h.
--     À 2, la copy ne parle que du QR et ne menace d'AUCUNE absence, parce
--     qu'à 2 close_presence_window_for remet à NULL sans pénalité.
--
-- (4) notify_peer_review_closing : seuil 2 → 3. Ses DEUX branches invitaient à
--     une action que le serveur refuse sous 3 participants. La branche (a) était
--     devenue atteignable à 2 par MA faute en 00429 (gate « = TRUE » →
--     « IS DISTINCT FROM FALSE ») : l'ancien gate bloquait ce cas par accident.
--     La branche (b) menaçait en plus d'une absence qui n'arrive jamais à 2 —
--     l'écran client affiche littéralement le contraire 10 secondes plus tard.
--
-- (5) close_due_presence_windows : garde CRÉATEUR SUSPENDU. Les 4 boucles de
--     notification l'excluent (00427), le finaliseur non → les participants
--     d'un organisateur suspendu ne recevaient plus aucun signal, n'avaient
--     aucun QR possible, et prenaient quand même tous une absence + pénalité.
--     Seul cas de l'audit où des utilisateurs totalement passifs sont punis.
--
-- Bases vivantes vérifiées par grep de TOUTES les redéfinitions :
--   peer_validate_presence / notify_presence_validate_warning / _overdue /
--   notify_peer_review_closing = 00429 · notify_presence_pre_warning(_10min)
--   = 00229 · close_due_presence_windows = 00107. Signatures inchangées.
--   Contrôle croisé : tout champ de RECORD ajouté (creator_id) est présent dans
--   le SELECT correspondant — plpgsql ne le vérifie qu'à l'exécution.
-- ============================================================================

-- ---------- 1. peer_validate_presence (base 00429) ----------
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

-- ---------- 2. notify_presence_pre_warning (base 00229) ----------
CREATE OR REPLACE FUNCTION notify_presence_pre_warning(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, requires_presence, creator_id
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'published' THEN RETURN; END IF;
  IF now() < v_activity.starts_at - INTERVAL '2 hours' OR now() >= v_activity.starts_at THEN
    RETURN;
  END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      -- 00432 : le créateur n'a AUCUN chemin d'auto-validation (invariant
      -- 00292). Lui dire « prépare-toi à valider ta présence » était une
      -- consigne inexécutable, et la fiche d'activité ne mentionnait même pas
      -- la présence pour lui à ce moment-là. Son action à lui, c'est
      -- qr_create_reminder à T-10min.
      AND p.user_id != v_activity.creator_id
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning',
        v_activity.title,
        'Démarre dans 2h — prépare-toi à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;


-- ---------- 3. notify_presence_pre_warning_10min (base 00229) ----------
CREATE OR REPLACE FUNCTION notify_presence_pre_warning_10min(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN RETURN; END IF;

  IF now() < v_activity.starts_at - INTERVAL '10 minutes' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      -- 00432 : le créateur n'a AUCUN chemin d'auto-validation (invariant
      -- 00292). Lui dire « prépare-toi à valider ta présence » était une
      -- consigne inexécutable, et la fiche d'activité ne mentionnait même pas
      -- la présence pour lui à ce moment-là. Son action à lui, c'est
      -- qr_create_reminder à T-10min.
      AND p.user_id != v_activity.creator_id
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning_10min'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning_10min',
        v_activity.title,
        'Démarre dans 10 min — pense à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;


-- ---------- 4. notify_presence_validate_warning (base 00429) ----------
CREATE OR REPLACE FUNCTION public.notify_presence_validate_warning(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_accepted_count INTEGER;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  IF now() < v_activity.starts_at + (v_activity.duration / 2) THEN RETURN; END IF;
  IF now() >= v_activity.starts_at + v_activity.duration THEN RETURN; END IF;

  -- Peer testimony (and thus the self-validate nag) only applies from 3.
  -- 00432 : le seuil passe de 3 à 2. À 2 participants, le QR est le SEUL
  -- recours (le témoignage entre pairs exige 3) — c'était donc la
  -- configuration qui avait le plus besoin d'être relancée, et la seule qui ne
  -- recevait RIEN entre T+15min et fin+3h. La copy est choisie selon le
  -- nombre : à 2, elle ne parle que du QR et ne menace d'aucune absence
  -- (close_presence_window_for remet à NULL sans pénalité à 2).
  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_accepted_count < 2 THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND p.user_id != v_activity.creator_id   -- Rule B: creator not nagged
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_warning',
        'Valide ta présence',
        CASE WHEN v_accepted_count >= 3 THEN
          'Scanne le QR de l''organisateur pour « ' || v_activity.title ||
          ' » — la validation automatique par géolocalisation s''est fermée 15 min après le début. Le QR reste valable jusqu''à 3 h après la fin.'
        ELSE
          'Scanne le QR de l''organisateur pour « ' || v_activity.title ||
          ' » — à deux, c''est le seul moyen de valider ta présence, et il reste ouvert jusqu''à 3 h après la fin.'
        END,
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

-- ---------- 5. notify_presence_validate_overdue (base 00429) ----------
CREATE OR REPLACE FUNCTION public.notify_presence_validate_overdue(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_accepted_count INTEGER;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '1 hour' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '1 hour 30 minutes' THEN RETURN; END IF;

  -- 00432 : le seuil passe de 3 à 2. À 2 participants, le QR est le SEUL
  -- recours (le témoignage entre pairs exige 3) — c'était donc la
  -- configuration qui avait le plus besoin d'être relancée, et la seule qui ne
  -- recevait RIEN entre T+15min et fin+3h. La copy est choisie selon le
  -- nombre : à 2, elle ne parle que du QR et ne menace d'aucune absence
  -- (close_presence_window_for remet à NULL sans pénalité à 2).
  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_accepted_count < 2 THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND p.user_id != v_activity.creator_id   -- Rule B: creator not nagged
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_overdue'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_overdue',
        v_activity.title,
        -- 00429 : l'ancienne copy affirmait « Tu es enregistré comme absent »,
        -- ce qui est FAUX à fin+1h (la finalisation n'a lieu qu'à fin+24h) et
        -- passait sous silence le QR, encore valable 2 h.
        CASE WHEN v_accepted_count >= 3 THEN
          'Ta présence n''est pas encore validée. Scanne le QR de l''organisateur (encore possible jusqu''à 3 h après la fin) ou demande à 2 co-participants de te valider. Sans validation, tu seras compté absent 24 h après la fin.'
        ELSE
          'Ta présence n''est pas encore validée. Scanne le QR de l''organisateur — à deux, c''est le seul moyen, et il reste ouvert jusqu''à 3 h après la fin. Sans ça, cette sortie ne sera simplement pas comptée (aucune absence, aucune pénalité).'
        END,
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

-- ---------- 6. notify_peer_review_closing (base 00429) ----------
CREATE OR REPLACE FUNCTION notify_peer_review_closing(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '22 hours' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  -- 00432 : seuil 2 -> 3. Les DEUX branches de cette fonction invitent à une
  -- action que le serveur refuse sous 3 participants (peer_validate_presence
  -- lève junto.peer_review_unavailable) :
  --   (a) « valide tes co-participants » → refusé ;
  --   (b) presence_validate_final « demande à 2 co-participants » → il n'y en a
  --       qu'un, ET à 2 personne n'est jamais marqué absent (close_presence_
  --       window_for remet à NULL sans pénalité) : la menace était fausse.
  -- La branche (a) était en plus devenue ATTEIGNABLE à 2 par ma faute en 00429
  -- (gate passé de « confirmed_present = TRUE » à « IS DISTINCT FROM FALSE ») :
  -- l'ancien gate bloquait ce cas par accident. À 2, la relance utile est
  -- presence_validate_overdue, désormais étendue à ce cas (00432).
  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 3 THEN
    RETURN;
  END IF;

  -- (a) Nudge confirmed peers who still have someone to vouch for.
  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      -- 00429 : le gate était « confirmed_present = TRUE » — or depuis 00327
      -- témoigner ne demande PLUS d'être soi-même confirmé présent. Résultat :
      -- sur une sortie où personne n'avait pu valider (cas garanti pendant la
      -- panne géo), PERSONNE ne recevait la relance, alors que n'importe quel
      -- participant pouvait sauver les autres. Seuls les absents confirmés
      -- (FALSE) sont exclus : eux ne comptent plus.
      AND p.confirmed_present IS DISTINCT FROM FALSE
      AND EXISTS (
        SELECT 1
        FROM participations p2
        WHERE p2.activity_id = p_activity_id
          AND p2.status = 'accepted'
          AND p2.confirmed_present IS NULL
          AND p2.user_id <> p.user_id
          AND NOT EXISTS (
            SELECT 1 FROM peer_validations pv
            WHERE pv.activity_id = p_activity_id
              AND pv.voter_id = p.user_id
              AND pv.voted_id = p2.user_id
          )
      )
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'peer_review_closing'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'peer_review_closing',
        v_activity.title,
        'Dernière chance pour valider tes co-participants — la fenêtre se ferme dans 2 h. Ton vote compte même si ta propre présence n''est pas confirmée.',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;

  -- (b) NEW: warn the still-unconfirmed attendees themselves, before the
  --     end+24h auto-FALSE penalty. They may never reopen the activity.
  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_final'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_final',
        v_activity.title,
        -- 00429 : il faut DEUX témoignages (00327), et le témoin n'a plus besoin
        -- d'être lui-même confirmé présent — l'ancienne copy demandait « un
        -- participant présent », doublement faux.
        'Ta présence n''a pas été validée. Demande à 2 co-participants de te confirmer avant que ça compte comme une absence — fenêtre fermée dans 2 h.',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

-- ---------- 7. close_due_presence_windows (base 00107) ----------
CREATE OR REPLACE FUNCTION close_due_presence_windows()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  FOR v_activity_id IN
    SELECT a.id
    FROM activities a
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.starts_at + a.duration + INTERVAL '24 hours' < now()
      AND a.deleted_at IS NULL
      -- 00432 : ne JAMAIS finaliser une sortie dont le créateur est suspendu.
      -- Les 4 boucles de notification l'excluent déjà (00427) — sans cette
      -- garde, l'asymétrie était la pire des deux : les participants ne
      -- recevaient plus AUCUN signal, n'avaient aucun QR possible
      -- (create_presence_token refuse), et prenaient quand même tous une
      -- absence + pénalité de fiabilité à fin+24h sans avoir rien pu faire.
      AND NOT EXISTS (
        SELECT 1 FROM users c
        WHERE c.id = a.creator_id AND c.suspended_at IS NOT NULL
      )
      AND EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id
          AND p.status = 'accepted'
          AND p.confirmed_present IS NULL
      )
  LOOP
    PERFORM close_presence_window_for(v_activity_id);
  END LOOP;
END;
$$;
REVOKE EXECUTE ON FUNCTION close_due_presence_windows FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. peer_validate_presence: 48h → 24h
-- ----------------------------------------------------------------------------
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
  v_is_creator BOOLEAN;
  v_voter_present BOOLEAN;
  v_voted_status TEXT;
  v_voted_present BOOLEAN;
  v_vote_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, creator_id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' OR v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_is_creator := (v_user_id = v_activity.creator_id);

  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id;
  IF v_voted_status != 'accepted' OR v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_is_creator THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    PERFORM recalculate_reliability_score(p_voted_id);
    RETURN;
  END IF;

  SELECT confirmed_present INTO v_voter_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
  IF v_voter_present IS NOT TRUE THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_vote_count
  FROM peer_validations
  WHERE activity_id = p_activity_id AND voted_id = p_voted_id;

  IF v_vote_count >= 2 THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    PERFORM recalculate_reliability_score(p_voted_id);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION notify_presence_pre_warning(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION notify_presence_pre_warning_10min(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION notify_presence_validate_warning(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION notify_presence_validate_overdue(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION notify_peer_review_closing(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION close_due_presence_windows() FROM PUBLIC, anon, authenticated;
