-- ============================================================================
-- 00429 — LOT 2 (gardes serveur) de l'audit présence (Scott 2026-09-30).
--
-- (1) REJEU HORS-LIGNE : la borne d'ARRIVÉE passe de fin+3h à fin+24h
--     (confirm_presence_via_geo). Scénario outdoor normal : fin 17h, réseau
--     retrouvé à 18h30, app ouverte à 21h → la preuve, mesurée sur place et
--     valide, était jetée en silence. L'anti-fraude réel reste l'heure de
--     CAPTURE (fenêtre T±15min), la distance ≤150 m, le refus d'un captured_at
--     futur (00419) et l'idempotence — pas l'heure d'arrivée. Aligné sur la
--     fenêtre de témoignage et sur l'auto-absence (fin+24h). Le cache client
--     garde les événements 30 h, donc il couvre la nouvelle borne.
--
-- (2) GARDE « SORTIE SUPPRIMÉE » sur 3 fonctions : peer_validate_presence,
--     close_presence_window_for et transition_single_activity. Le balayage
--     cron filtrait déjà deleted_at (00107) mais PAS le chemin lazy : un
--     participant qui ouvrait une vieille notification sur une activité
--     retirée par la modération déclenchait la finalisation, donc les absences
--     + pénalités de fiabilité que le cron refusait justement de poser.
--
-- (3) GARDE « SORTIE SANS VALIDATION DE PRÉSENCE » sur les 3 écrivains
--     (confirm géo, confirm QR, création de token). Aucun ne testait
--     requires_presence, alors que le finaliseur sort tôt dans ce cas : on
--     pouvait donc confirmer sa présence en boucle sur des sorties sans
--     présence — score de fiabilité qui ne monte que, sans risque de baisse.
--
-- (4) RIDEAU DÉMO sur les 4 écrivains de présence (garde ABSOLUE, admin en
--     mode démo compris — même règle que join_activity et que 00426). Les
--     seeds démo sont aujourd'hui requires_presence = false, ce qui masquait
--     le trou ; un seul seed démo à true ouvrait tout le spine sur le score
--     de fiabilité RÉEL de l'admin.
--
-- (5) TEXTES DE NOTIFICATION faux réparés + un verrou qui bloquait les
--     relances (détail sur chaque fonction). Rappel : les notifications
--     n'affichent JAMAIS d'horodatage absolu (le serveur est en UTC, « 19h30 »
--     serait faux pour l'utilisateur) → échéances relatives ici, horaires
--     absolus côté client (lot 3).
--
-- (6) peer_validate_presence distingue enfin « déjà validé » de « fenêtre
--     fermée, compté absent » (le second levait le premier, message trompeur).
--
-- Bases vivantes vérifiées par grep de TOUTES les redéfinitions :
--   confirm_presence_via_geo = 00428 · confirm_presence_via_token = 00292 ·
--   create_presence_token = 00272 · peer_validate_presence = 00327 ·
--   close_presence_window_for = 00330 · transition_single_activity = 00428 ·
--   notify_presence_validate_warning = 00302 ·
--   notify_presence_validate_overdue = 00291 ·
--   notify_peer_review_closing = 00265.
-- Toutes les signatures sont inchangées → aucune surcharge créée.
-- Contrôle croisé effectué : tout champ de RECORD utilisé est bien présent
-- dans le SELECT correspondant (un plpgsql ne le vérifie qu'à l'exécution —
-- c'est précisément le piège de 00419).
-- ============================================================================
-- ---------- 1. confirm_presence_via_geo (base 00428) ----------
CREATE OR REPLACE FUNCTION confirm_presence_via_geo(
  p_activity_id UUID,
  p_lng FLOAT,
  p_lat FLOAT,
  p_captured_at TIMESTAMPTZ DEFAULT NULL,
  p_skip_push BOOLEAN DEFAULT TRUE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_user_point GEOGRAPHY;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_d_trace FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_window_anchor TIMESTAMPTZ;
  v_creator_id UUID;
  v_creator_flipped INTEGER;
  v_requires_presence BOOLEAN;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration, status, deleted_at, creator_id, requires_presence, is_demo
  INTO v_starts_at, v_duration, v_status, v_deleted_at, v_creator_id, v_requires_presence, v_is_demo
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00429 : une sortie qui ne demande PAS de validation de présence n'a aucun
  -- chemin de confirmation (le finaliseur sort tôt, donc aucun risque de FALSE)
  -- → confirmer y gonflait le score de fiabilité sans risque de baisse.
  IF v_requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  -- 00429 : rideau démo côté ÉCRITURE, garde ABSOLUE (admin en mode démo
  -- compris) — même règle que join_activity et que les envois de 00426.
  IF v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- RESTAURÉ (00292) — Invariant : la présence du créateur n'est JAMAIS
  -- auto-attestée. No-op silencieux (pas une erreur : le client ne propose
  -- pas le bouton, un appel direct ne doit simplement rien faire).
  IF v_user_id = v_creator_id THEN RETURN; END IF;

  -- Reject cancelled / expired activities, and soft-deleted ones. The
  -- time-window check below catches future-dated activities, but a
  -- creator cancelling within the validation window would otherwise
  -- still allow validations.
  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;

  IF p_captured_at IS NULL THEN
    v_window_anchor := now();
  ELSE
    -- 00419 : un événement « capturé dans le futur » est forcément forgé
    -- (2 min de tolérance d'horloge pour les replays offline légitimes).
    IF p_captured_at > now() + INTERVAL '2 minutes' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 00429 : la borne d'ARRIVÉE du rejeu passe de fin+3h à fin+24h (alignée
    -- sur la fenêtre de témoignage et sur l'auto-absence). Scénario outdoor
    -- normal : fin 17h, réseau retrouvé à 18h30, app ouverte à 21h → la preuve
    -- était valide et mesurée sur place, elle était jetée. L'anti-fraude réel
    -- reste l'heure de CAPTURE (fenêtre T±15min, vérifiée juste en dessous),
    -- la distance, le refus du futur et l'idempotence — pas l'heure d'arrivée.
    IF now() > v_starts_at + v_duration + INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.presence_window_closed';
    END IF;
    v_window_anchor := p_captured_at;
  END IF;

  IF v_window_anchor < v_starts_at - INTERVAL '15 minutes'
     OR v_window_anchor > v_starts_at + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.presence_window_closed';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RETURN; END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  -- CORRIGÉ (00428) : location_start a été SUPPRIMÉE en 00306 (fusionnée dans
  -- location_meeting). 00419 la référençait encore → la fonction levait
  -- « column location_start does not exist » à CHAQUE appel. Les trois points
  -- valides sont meeting / end / trace.
  SELECT
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END,
    CASE WHEN trace_geojson IS NOT NULL
         THEN ST_Distance(ST_GeomFromGeoJSON(trace_geojson::text)::geography, v_user_point)
         ELSE NULL END
  INTO v_d_meeting, v_d_end, v_d_trace
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end,     999999),
    coalesce(v_d_trace,   999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'junto.presence_too_far';
  END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id, p_skip_push);

  -- RESTAURÉ (00292) — Règle A : un non-créateur qui confirme PROUVE que la
  -- sortie a eu lieu → la présence du créateur est validée automatiquement.
  -- C'est le SEUL chemin de validation du créateur côté géo (il n'est jamais
  -- relancé par les notifications, précisément parce que cette règle existe).
  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, p_activity_id, p_skip_push);
    END IF;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ, BOOLEAN) TO authenticated;

-- ---------- 2. confirm_presence_via_token (base 00292) ----------
CREATE OR REPLACE FUNCTION public.confirm_presence_via_token(p_token text, p_skip_push boolean DEFAULT true)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_user_id UUID;
  v_token_record RECORD;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_activity_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_creator_id UUID;
  v_creator_flipped INTEGER;
  v_requires_presence BOOLEAN;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT activity_id, expires_at INTO v_token_record
  FROM presence_tokens WHERE token = p_token;
  IF v_token_record IS NULL OR v_token_record.expires_at < now() THEN
    RAISE EXCEPTION 'junto.presence_token_invalid';
  END IF;

  v_activity_id := v_token_record.activity_id;

  SELECT starts_at, duration, status, deleted_at, creator_id, requires_presence, is_demo
  INTO v_starts_at, v_duration, v_status, v_deleted_at, v_creator_id, v_requires_presence, v_is_demo
  FROM activities WHERE id = v_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00429 : une sortie qui ne demande PAS de validation de présence n'a aucun
  -- chemin de confirmation (le finaliseur sort tôt, donc aucun risque de FALSE)
  -- → confirmer y gonflait le score de fiabilité sans risque de baisse.
  IF v_requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  -- 00429 : rideau démo côté ÉCRITURE, garde ABSOLUE (admin en mode démo
  -- compris) — même règle que join_activity et que les envois de 00426.
  IF v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;

  -- Invariant: the creator never self-confirms (via their own QR either).
  IF v_user_id = v_creator_id THEN RETURN v_activity_id; END IF;

  IF now() < v_starts_at - INTERVAL '15 minutes' OR now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
    RAISE EXCEPTION 'junto.presence_window_closed';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = v_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RETURN v_activity_id; END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, v_activity_id, p_skip_push);

  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = v_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, v_activity_id, p_skip_push);
    END IF;
  END IF;

  RETURN v_activity_id;
END;
$$;

REVOKE ALL ON FUNCTION confirm_presence_via_token(TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_token(TEXT, BOOLEAN) TO authenticated;

-- ---------- 3. create_presence_token (base 00272) ----------
CREATE OR REPLACE FUNCTION create_presence_token(p_activity_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_creator_id UUID;
  v_token TEXT;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_requires_presence BOOLEAN;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT creator_id, starts_at, duration, status, deleted_at, requires_presence, is_demo
  INTO v_creator_id, v_starts_at, v_duration, v_status, v_deleted_at, v_requires_presence, v_is_demo
  FROM activities WHERE id = p_activity_id;
  IF v_creator_id IS NULL OR v_creator_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00429 : ne pas frapper un token sur une sortie supprimée / annulée /
  -- expirée, ni sans validation de présence, ni sur une sortie démo.
  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  IF v_requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  IF v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '15 minutes' OR now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
    RAISE EXCEPTION 'junto.presence_token_window_closed';
  END IF;

  SELECT token INTO v_token FROM presence_tokens
  WHERE activity_id = p_activity_id AND expires_at > now()
  LIMIT 1;

  IF v_token IS NULL THEN
    v_token := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
    INSERT INTO presence_tokens (token, activity_id, expires_at)
    VALUES (v_token, p_activity_id, now() + INTERVAL '30 minutes');
  END IF;

  RETURN v_token;
END;
$$;

REVOKE ALL ON FUNCTION create_presence_token(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_presence_token(UUID) TO authenticated;

-- ---------- 4. peer_validate_presence (base 00327) ----------
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

  SELECT id, status, starts_at, duration, requires_presence, deleted_at, is_demo
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
    END IF;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION peer_validate_presence(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION peer_validate_presence(UUID, UUID) TO authenticated;

-- ---------- 5. close_presence_window_for (base 00330) — interne ----------
CREATE OR REPLACE FUNCTION public.close_presence_window_for(p_activity_id uuid)
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
  SELECT id, status, starts_at, duration, requires_presence, creator_id, deleted_at
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  -- 00429 : ne JAMAIS finaliser (donc ne jamais poser d'absence ni de pénalité)
  -- sur une sortie retirée par la modération. Le balayage cron filtre déjà
  -- deleted_at (00107) ; le chemin lazy, non → un participant qui ouvrait une
  -- vieille notification déclenchait les absences que le cron refusait de poser.
  IF v_activity.deleted_at IS NOT NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() <= v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  -- Deferred evaluations: commit (make count) every reputation vote whose BOTH
  -- parties ended up confirmed present. Runs before the presence branching
  -- below — the confirmed-present set is already fixed (finalisation only flips
  -- NULLs to FALSE / neutralises, never adds a TRUE). requires_presence = false
  -- returned earlier, so a no-presence activity never commits any vote, and if
  -- nobody was confirmed present there is simply no anchored pair to commit.
  UPDATE reputation_votes rv
  SET counted_at = now()
  WHERE rv.activity_id = p_activity_id
    AND rv.counted_at IS NULL
    AND rv.voter_id <> rv.voted_id  -- defensive: a self-vote would break the CHECK re-validation
    AND EXISTS (
      SELECT 1 FROM participations pv
      WHERE pv.activity_id = p_activity_id
        AND pv.user_id = rv.voter_id
        AND pv.status = 'accepted'
        AND pv.confirmed_present = TRUE
    )
    AND EXISTS (
      SELECT 1 FROM participations pt
      WHERE pt.activity_id = p_activity_id
        AND pt.user_id = rv.voted_id
        AND pt.status = 'accepted'
        AND pt.confirmed_present = TRUE
    );

  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  -- Solo (creator alone): "absent" is undefined. Leave NULL untouched.
  IF v_accepted_count < 2 THEN RETURN; END IF;

  -- Rule C — exactly 2: presence only via QR/geo (peer testimony is circular).
  -- A non-creator confirmation auto-validates both (rule A), so its ABSENCE
  -- means the meetup wasn't verifiable -> re-expire, wipe any lone self-
  -- validation so nothing counts, and never penalise.
  IF v_accepted_count = 2 THEN
    IF NOT EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted'
        AND user_id != v_activity.creator_id AND confirmed_present = TRUE
    ) THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE activities SET status = 'expired', updated_at = now()
      WHERE id = p_activity_id AND status = 'completed';
      FOR v_target IN
        SELECT user_id FROM participations
        WHERE activity_id = p_activity_id AND status = 'accepted'
          AND confirmed_present IS NOT NULL
      LOOP
        UPDATE participations SET confirmed_present = NULL
        WHERE activity_id = p_activity_id AND user_id = v_target.user_id AND status = 'accepted';
        PERFORM recalculate_reliability_score(v_target.user_id);
      END LOOP;
    END IF;
    RETURN;
  END IF;

  -- 3+ : the review happened iff at least one participant is confirmed present.
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- Nobody confirmed -> the review never ran. Can't tell absent from forgotten:
  -- stay neutral for everyone (expire, no penalty), like the 2-person case.
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND status = 'accepted' AND confirmed_present = TRUE
  ) THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'completed';
    RETURN;
  END IF;

  -- At least one presence established -> the unconfirmed are genuine no-shows.
  FOR v_target IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id
      AND status = 'accepted'
      AND confirmed_present IS NULL
  LOOP
    UPDATE participations
    SET confirmed_present = FALSE
    WHERE activity_id = p_activity_id
      AND user_id = v_target.user_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;

    PERFORM recalculate_reliability_score(v_target.user_id);
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION close_presence_window_for(UUID) FROM PUBLIC, anon, authenticated;

-- ---------- 6. transition_single_activity (base 00428) ----------
CREATE OR REPLACE FUNCTION transition_single_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN NULL;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  SELECT id, creator_id, status, title, starts_at, duration, requires_presence, deleted_at
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN NULL; END IF;
  -- 00429 : même garde que le balayage cron — une sortie supprimée ne transite
  -- plus (sinon elle passait 'completed' puis se faisait finaliser).
  IF v_activity.deleted_at IS NOT NULL THEN RETURN v_activity.status; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress', 'completed') THEN
    RETURN v_activity.status;
  END IF;

  IF v_activity.status = 'published'
     AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id
          AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
      -- CORRIGÉ (00428) : notify_presence_reminders(UUID) a été SUPPRIMÉE en
      -- 00148 (spine de notifs simplifié) mais l'appel a été transporté
      -- verbatim de migration en migration (00136 → 00225 → 00286 → 00427).
      -- Résultat : cette RPC levait « function does not exist » à chaque
      -- appel, donc le flip completed, la fermeture de fenêtre de présence et
      -- rate_participants côté lazy n'ont JAMAIS tourné (les deux appelants
      -- client avalent l'erreur). Les rappels pré-event vivent dans
      -- notify_presence_pre_warning / _10min, appelés par le balayage cron.
      PERFORM notify_creator_qr_reminder(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    PERFORM notify_creator_qr_reminder(p_activity_id);
  END IF;

  IF v_activity.status = 'in_progress' AND v_activity.starts_at + v_activity.duration <= now() THEN
    -- Solo end-of-window → expired, not completed (see header).
    IF (SELECT count(*) FROM participations p
        WHERE p.activity_id = p_activity_id
        AND p.status = 'accepted'
        AND p.user_id != v_activity.creator_id) = 0
    THEN
      UPDATE activities SET status = 'expired', updated_at = now()
      WHERE id = p_activity_id AND status = 'in_progress';
      IF FOUND THEN
        RETURN 'expired';
      END IF;
    END IF;

    UPDATE activities SET status = 'completed', updated_at = now()
    WHERE id = p_activity_id AND status = 'in_progress';
    IF FOUND THEN
      v_activity.status := 'completed';
    END IF;
  END IF;

  IF v_activity.status = 'completed' THEN
    PERFORM close_presence_window_for(p_activity_id);
    -- 00427: emit rate_participants here too (lazy path) — gates internally
    -- on the real vote window [end+15min, end+24h] + dedup.
    PERFORM notify_rate_participants(p_activity_id);
  END IF;

  RETURN v_activity.status;
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_single_activity(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION transition_single_activity(UUID) TO authenticated;

-- ---------- 7-9. Textes de notification (internes) ----------
CREATE OR REPLACE FUNCTION public.notify_presence_validate_warning(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
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
  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 3 THEN
    RETURN;
  END IF;

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
        'Scanne le QR de l''organisateur pour « ' || v_activity.title ||
        ' » — la validation automatique par géolocalisation s''est fermée 15 min après le début. Le QR reste valable jusqu''à 3 h après la fin.',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_presence_validate_overdue(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '1 hour' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '1 hour 30 minutes' THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 3 THEN
    RETURN;
  END IF;

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
        'Ta présence n''est pas encore validée. Scanne le QR de l''organisateur (encore possible jusqu''à 3 h après la fin) ou demande à 2 co-participants de te valider. Sans validation, tu seras compté absent 24 h après la fin.',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

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

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
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
REVOKE EXECUTE ON FUNCTION notify_peer_review_closing FROM anon, authenticated;

REVOKE ALL ON FUNCTION notify_presence_validate_warning(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION notify_presence_validate_overdue(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION notify_peer_review_closing(UUID) FROM PUBLIC, anon, authenticated;
