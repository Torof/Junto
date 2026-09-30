-- ============================================================================
-- 00428 — LOT 1 (URGENCE) : le spine de présence est à moitié mort. Deux
-- régressions déployées, trouvées par l'audit présence (Scott 2026-09-30).
--
-- (1) confirm_presence_via_geo — LA VALIDATION GÉO NE FONCTIONNE PLUS DU TOUT
--     depuis le déploiement de 00419 (2026-09-27). 00419 a été reconstruite
--     depuis 00272, un ancêtre ANTÉRIEUR à 00292 et à 00306. Trois dégâts :
--       (a) elle référence `location_start`, colonne SUPPRIMÉE en 00306 →
--           « column location_start does not exist » à CHAQUE appel. Un corps
--           plpgsql n'est pas résolu au CREATE, donc la migration est passée
--           sans erreur et la fonction échoue seulement à l'exécution.
--           Aggravant : le message n'est pas reconnu comme refus terminal par
--           le cache offline (lib/presence-offline-cache) → rejeu en boucle et
--           notification « Présence détectée » qui ne bascule jamais.
--       (b) l'invariant 00292 « le créateur ne s'auto-atteste JAMAIS » a
--           disparu → auto-attestation possible par appel direct (le vecteur
--           single-attester retiré volontairement en 00108/00140/00292).
--       (c) la Règle A (00292) a disparu → un participant qui confirme ne
--           valide plus le créateur. Comme le créateur n'est JAMAIS relancé
--           (Règle B : exclu de validate_warning/overdue/final, précisément
--           parce que la Règle A s'en chargeait), il finit marqué ABSENT de sa
--           propre sortie à fin+24h (00330) avec pénalité de fiabilité.
--     Ici : corps 00419 conservé (y compris son durcissement « captured_at
--     futur = forgé »), colonne morte retirée, (b) et (c) restaurés verbatim
--     depuis 00292.
--
-- (2) transition_single_activity — appelait notify_presence_reminders(UUID),
--     SUPPRIMÉE en 00148, appel transporté verbatim 00136 → 00225 → 00286 →
--     00427. La RPC échouait donc TOUJOURS sur une activité published/
--     in_progress, avant le flip completed, la fermeture de fenêtre de
--     présence et rate_participants. Invisible parce que les deux appelants
--     client avalent l'erreur. Le « force completed » de l'écran d'évaluation
--     n'a donc jamais fonctionné, et l'ajout 00427 côté lazy était mort-né.
--     (transition_statuses_only, le chemin cron, ne l'appelait pas → c'est
--     pourquoi les notifications partaient quand même.)
--
-- Bases vivantes vérifiées par grep de TOUTES les redéfinitions :
--   confirm_presence_via_geo = 00419 (+ invariants 00292), signature (UUID,
--   FLOAT, FLOAT, TIMESTAMPTZ, BOOLEAN) inchangée → pas de surcharge ;
--   transition_single_activity = 00427, signature (UUID) inchangée.
-- ============================================================================

-- ---------- 1. confirm_presence_via_geo ----------
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration, status, deleted_at, creator_id
  INTO v_starts_at, v_duration, v_status, v_deleted_at, v_creator_id
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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
    IF now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
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

-- ---------- 2. transition_single_activity : appel mort retiré ----------
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

  SELECT id, creator_id, status, title, starts_at, duration, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN NULL; END IF;
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
