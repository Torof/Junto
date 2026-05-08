-- Migration 00212: extend handle_activity_update whitelist for columns
-- added since 00083. Closes group A from the parallel security audit.
--
-- Until now, the whitelist trigger pinned only the columns documented
-- in 00083. Several columns added afterward were never added to the
-- whitelist, which means a creator could write them directly via
-- PostgREST `.update(...)` and bypass every documented setter RPC's
-- auth chain. The "default-protected — new columns are protected"
-- claim of the whitelist did NOT hold for activities.
--
-- Most damaging gap: `deleted_at`. Without a pin, a creator could
-- silently soft-delete or un-soft-delete an activity, bypassing
-- cancel_activity (no notifications, no reason, no status check).
--
-- All affected setter RPCs (cancel_activity, update_activity_trace,
-- update_activity_metrics, update_activity_start_name) already call
-- set_config('junto.bypass_lock', 'true', true) before their writes,
-- so this trigger change is safe to apply.
--
-- New unconditional pins:
--   deleted_at        — soft-delete flag (cancel_activity via bypass)
--   cancelled_reason  — cancellation reason (cancel_activity)
--   distance_km       — metrics setter
--   elevation_gain_m  — metrics setter
--   start_name        — start name setter
--   trace_geojson     — trace setter
--   route             — legacy GIS column, no active writer
--
-- Conditional pins (locked once accepted participants exist) unchanged
-- from 00083: location_*, starts_at, level, max_participants,
-- visibility, requires_presence, objective_name.

CREATE OR REPLACE FUNCTION handle_activity_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  -- Unconditionally privileged columns. Writable only via SECURITY
  -- DEFINER functions that explicitly call bypass_lock.
  NEW.creator_id := OLD.creator_id;
  NEW.status := OLD.status;
  NEW.invite_token := OLD.invite_token;
  NEW.created_at := OLD.created_at;
  NEW.deleted_at := OLD.deleted_at;
  NEW.cancelled_reason := OLD.cancelled_reason;
  NEW.distance_km := OLD.distance_km;
  NEW.elevation_gain_m := OLD.elevation_gain_m;
  NEW.start_name := OLD.start_name;
  NEW.trace_geojson := OLD.trace_geojson;
  NEW.route := OLD.route;

  -- Locked once accepted participants exist.
  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_start := OLD.location_start;
    NEW.location_meeting := OLD.location_meeting;
    NEW.location_end := OLD.location_end;
    NEW.location_objective := OLD.location_objective;
    NEW.objective_name := OLD.objective_name;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
    NEW.requires_presence := OLD.requires_presence;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
