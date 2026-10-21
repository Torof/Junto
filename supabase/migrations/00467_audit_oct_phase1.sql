-- ============================================================================
-- 00467 — Audit octobre 2026, phase 1 (docs/AUDIT_2026-10.md H2 + M1).
-- Scott 2026-10-21 : « il faut toutes les réparer ».
--
-- H2 — données participants des réservations (taille, poids, âge, réponses) :
--   (a) la policy de lecture directe de `bookings` exige désormais un appelant
--       non suspendu (un pro suspendu lisait encore toutes ses réservations) ;
--   (b) la colonne participant_info n'est plus lisible en direct : le client ne
--       lit jamais la table (seulement get_pro_agenda / get_my_bookings, SECURITY
--       DEFINER, inchangées) ;
--   (c) participant_info est effacé à toute sortie de l'état « accepted »
--       (annulation client ou pro, refus, expiration, suspension) ET au retour en
--       « pending » de la branche de réutilisation de create_booking — un trigger
--       couvre tous les chemins sans reconstruire cinq fonctions ;
--   (d) purge quotidienne des réponses 30 jours après le jour de la sortie.
--
-- M1 — la durée d'une sortie restait modifiable après son début (rouvrait la
--   fenêtre du QR de présence et repoussait la clôture des absences sans
--   limite). Gel de `duration` dès que la sortie a commencé (avant le début,
--   un changement reste permis et notifié comme aujourd'hui), base = définition
--   vivante de handle_activity_update (00441). + borne haute 7 jours (max
--   actuel en base : 48 h ; le formulaire plafonne à 24 h 59).
-- ============================================================================

-- ---------- H2 (a) ----------
DROP POLICY IF EXISTS bookings_select_parties ON bookings;
CREATE POLICY bookings_select_parties ON bookings FOR SELECT
  USING (
    (client_id = auth.uid() OR pro_id = auth.uid())
    AND NOT private.user_is_suspended(auth.uid())
  );

-- ---------- H2 (b) ----------
REVOKE SELECT (participant_info) ON bookings FROM authenticated, anon;

-- ---------- H2 (c) ----------
CREATE OR REPLACE FUNCTION bookings_clear_participant_info()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'accepted' THEN
    NEW.participant_info := NULL;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION bookings_clear_participant_info() FROM PUBLIC, anon, authenticated;

-- Name sorts after bookings_whitelist_trg → runs last, even under bypass_lock.
DROP TRIGGER IF EXISTS bookings_zz_clear_participant_info ON bookings;
CREATE TRIGGER bookings_zz_clear_participant_info
  BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION bookings_clear_participant_info();

-- Existing rows already out of the accepted state.
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET participant_info = NULL
  WHERE participant_info IS NOT NULL AND status <> 'accepted';
END $$;

-- ---------- H2 (d) ----------
CREATE OR REPLACE FUNCTION purge_booking_participant_info()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET participant_info = NULL
  WHERE participant_info IS NOT NULL AND day < current_date - 30;
END;
$$;
REVOKE ALL ON FUNCTION purge_booking_participant_info() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule('junto-booking-participant-purge')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'junto-booking-participant-purge');
SELECT cron.schedule('junto-booking-participant-purge', '15 4 * * *', 'SELECT public.purge_booking_participant_info();');

-- ---------- M1 ----------
CREATE OR REPLACE FUNCTION public.handle_activity_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  NEW.creator_id := OLD.creator_id;
  NEW.status := OLD.status;
  NEW.invite_token := OLD.invite_token;
  NEW.created_at := OLD.created_at;
  NEW.deleted_at := OLD.deleted_at;
  NEW.cancelled_reason := OLD.cancelled_reason;
  NEW.distance_km := OLD.distance_km;
  NEW.elevation_gain_m := OLD.elevation_gain_m;
  NEW.meeting_name := OLD.meeting_name;
  NEW.trace_geojson := OLD.trace_geojson;
  NEW.route := OLD.route;
  NEW.is_demo := OLD.is_demo;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_meeting := OLD.location_meeting;
    NEW.location_end := OLD.location_end;
    NEW.location_objective := OLD.location_objective;
    NEW.objective_name := OLD.objective_name;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.level_max := OLD.level_max;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
    NEW.requires_presence := OLD.requires_presence;
  END IF;

  -- 00467 (audit M1): once the outing has started, its end is fixed — the
  -- presence QR window and the absence finalizer both hang off it.
  IF now() >= OLD.starts_at THEN
    NEW.duration := OLD.duration;
  END IF;

  -- 00441: the locality follows the meeting pin and nothing else — it may
  -- only change in the same UPDATE that moves location_meeting (which the
  -- participant lock above already freezes once someone has joined).
  IF NEW.location_meeting IS NOT DISTINCT FROM OLD.location_meeting THEN
    NEW.meeting_locality := OLD.meeting_locality;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

ALTER TABLE activities DROP CONSTRAINT IF EXISTS activities_duration_check;
ALTER TABLE activities ADD CONSTRAINT activities_duration_check
  CHECK (duration >= INTERVAL '15 minutes' AND duration <= INTERVAL '7 days');
