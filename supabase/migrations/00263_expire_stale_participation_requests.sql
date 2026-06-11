-- Migration 00263: auto-expire stale participation requests.
--
-- Bug (vérifié 2026-06-11) : une demande de participation 'pending' sur
-- une activité qui se termine (completed / cancelled / expired) restait
-- 'pending' pour toujours — carte fantôme permanente dans l'onglet
-- "En attente" de Mes activités, sans aucun chemin de résolution. Le
-- mécanisme exact existait déjà pour les seat_requests (mig 00142,
-- assoupli en 00157) mais les demandes de participation avaient été
-- oubliées.
--
-- Fix, en miroir du précédent seat_requests :
--   1. Nouveau statut 'expired' dans le CHECK de participations —
--      additif (tous les filtres du code sélectionnent des statuts
--      explicites), sémantiquement honnête ('refused' mentirait :
--      personne n'a refusé, personne n'a répondu).
--   2. Le trigger de transition (on_activity_finished_expire_seat_requests)
--      flippe AUSSI les participations pending → expired. SILENCIEUX,
--      par décision 00157 : cancelled → le requester reçoit déjà la
--      notif d'annulation (cancel_activity notifie pending inclus) ;
--      completed/expired → l'utilisateur l'apprend par d'autres canaux,
--      une notif post-hoc est du bruit.
--   3. La vue my_pending_activities filtre sur les statuts actifs —
--      double défense : même un row pending résiduel ne s'affiche plus.
--   4. Backfill des rows fantômes existants (sans notification).
--
-- Pas de whitelist trigger sur participations (cf. 00065/00200) — les
-- UPDATE directs depuis les fonctions SECURITY DEFINER sont le pattern.

-- ============================================================================
-- 1. Statut 'expired'
-- ============================================================================
ALTER TABLE participations DROP CONSTRAINT participations_status_check;
ALTER TABLE participations ADD CONSTRAINT participations_status_check
  CHECK (status IN ('pending', 'accepted', 'refused', 'removed', 'withdrawn', 'expired'));

-- ============================================================================
-- 2. Trigger étendu — couvre désormais seat_requests ET participations.
--    Même nom de fonction : le binding du trigger (mig 00142) est inchangé.
-- ============================================================================
CREATE OR REPLACE FUNCTION on_activity_finished_expire_seat_requests()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
BEGIN
  IF NEW.status NOT IN ('completed', 'cancelled', 'expired') THEN
    RETURN NEW;
  END IF;
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Cleanup only — flip pending requests to expired so the UI no longer
  -- shows them as pending. No notification emission (00157 decision);
  -- the activity-status transition reaches the user through other
  -- channels.
  FOR v_request IN
    SELECT id
    FROM seat_requests
    WHERE activity_id = NEW.id AND status = 'pending'
    FOR UPDATE
  LOOP
    UPDATE seat_requests SET status = 'expired' WHERE id = v_request.id;
  END LOOP;

  -- Same treatment for participation requests (mig 00263 — they were
  -- the forgotten sibling and ghosted the "En attente" tab forever).
  UPDATE participations
  SET status = 'expired'
  WHERE activity_id = NEW.id AND status = 'pending';

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION on_activity_finished_expire_seat_requests FROM public, anon, authenticated;

-- ============================================================================
-- 3. Vue — ne montrer que les demandes sur activités encore actives
-- ============================================================================
CREATE OR REPLACE VIEW my_pending_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.start_name,
  a.trace_geojson,
  ST_X(COALESCE(a.location_objective, a.location_start, a.location_meeting)::geometry) AS lng,
  ST_Y(COALESCE(a.location_objective, a.location_start, a.location_meeting)::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  ST_X(a.location_objective::geometry) AS objective_lng,
  ST_Y(a.location_objective::geometry) AS objective_lat,
  ST_X(a.location_start::geometry) AS start_lng,
  ST_Y(a.location_start::geometry) AS start_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count
FROM activities a
JOIN participations par ON par.activity_id = a.id
  AND par.user_id = auth.uid()
  AND par.status = 'pending'
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.creator_id <> auth.uid()
  AND a.deleted_at IS NULL
  AND a.status IN ('published', 'in_progress');

-- ============================================================================
-- 4. Backfill — les fantômes existants, en silence
-- ============================================================================
UPDATE participations par
SET status = 'expired'
FROM activities a
WHERE par.activity_id = a.id
  AND par.status = 'pending'
  AND a.status IN ('completed', 'cancelled', 'expired');
