-- Migration 00033: Trust model foundation
-- 1. confirmed_present on participations
-- 2. reliability_score on users
-- 3. Update transition function to notify creator on completion
-- 4. confirm_presence function for creator
-- 5. Ensure pg_cron is scheduled

-- ============================================================================
-- SCHEMA: add confirmed_present to participations + reliability_score to users
-- ============================================================================
ALTER TABLE participations ADD COLUMN confirmed_present BOOLEAN;

SELECT set_config('junto.bypass_lock', 'true', true);
ALTER TABLE users ADD COLUMN reliability_score FLOAT;

-- Add reliability_score to whitelist trigger (read-only for client — updated by functions)
CREATE OR REPLACE FUNCTION handle_user_update()
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

  -- WHITELIST: force ALL non-allowed columns to their old values
  NEW.id := OLD.id;
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.date_of_birth := OLD.date_of_birth;
  NEW.is_admin := OLD.is_admin;
  NEW.tier := OLD.tier;
  NEW.is_pro_verified := OLD.is_pro_verified;
  NEW.pro_verified_at := OLD.pro_verified_at;
  NEW.suspended_at := OLD.suspended_at;
  NEW.phone_verified := OLD.phone_verified;
  NEW.phone_verified_at := OLD.phone_verified_at;
  NEW.accepted_tos_at := OLD.accepted_tos_at;
  NEW.accepted_privacy_at := OLD.accepted_privacy_at;
  NEW.push_token := OLD.push_token;
  NEW.reliability_score := OLD.reliability_score;

  -- Allowed: display_name, avatar_url, bio, sports, levels_per_sport, notification_preferences

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ============================================================================
-- FUNCTION: transition_activity_status (updated — notify creator on completion)
-- ============================================================================
CREATE OR REPLACE FUNCTION transition_activity_status()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- published → in_progress (starts_at reached)
  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published'
    AND starts_at <= now();

  -- in_progress → completed (starts_at + duration reached)
  -- Notify creator to confirm presence
  FOR v_activity IN
    SELECT id, creator_id, title
    FROM activities
    WHERE status = 'in_progress'
      AND starts_at + duration <= now()
  LOOP
    UPDATE activities SET status = 'completed', updated_at = now() WHERE id = v_activity.id;

    PERFORM create_notification(
      v_activity.creator_id,
      'confirm_presence',
      'Activité terminée',
      'Confirme qui était présent à ' || v_activity.title,
      jsonb_build_object('activity_id', v_activity.id)
    );
  END LOOP;

  -- published → expired (starts_at + 2h passed, no participants besides creator)
  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'published'
    AND starts_at + INTERVAL '2 hours' < now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_activity_status() FROM anon, authenticated;

-- ============================================================================
-- FUNCTION: confirm_presence (creator confirms who showed up)
-- ============================================================================
CREATE OR REPLACE FUNCTION confirm_presence(
  p_activity_id UUID,
  p_present_user_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Activity exists, is completed, caller is creator
  SELECT id, creator_id, status INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Check presence hasn't been confirmed already
  IF EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND confirmed_present IS NOT NULL
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Mark presence for all accepted participants (except creator)
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE participations
  SET confirmed_present = (user_id = ANY(p_present_user_ids))
  WHERE activity_id = p_activity_id
    AND status = 'accepted'
    AND user_id != v_user_id;

  -- Creator is always present
  UPDATE participations
  SET confirmed_present = true
  WHERE activity_id = p_activity_id
    AND user_id = v_user_id
    AND status = 'accepted';

  -- 6. Recalculate reliability score for all participants
  FOR v_participant IN
    SELECT DISTINCT user_id FROM participations
    WHERE activity_id = p_activity_id AND status = 'accepted'
  LOOP
    PERFORM recalculate_reliability_score(v_participant.user_id);
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence TO authenticated;

-- ============================================================================
-- FUNCTION: recalculate_reliability_score (internal)
-- Score = (present + on_time_cancels) / total_confirmed_activities
-- Late cancellation (< 12h) counts as negative
-- ============================================================================
CREATE OR REPLACE FUNCTION recalculate_reliability_score(
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total INTEGER;
  v_present INTEGER;
  v_late_cancels INTEGER;
  v_score FLOAT;
BEGIN
  -- Total activities where presence was confirmed (by any creator)
  SELECT count(*) INTO v_total
  FROM participations
  WHERE user_id = p_user_id
    AND confirmed_present IS NOT NULL;

  -- Activities where user was present
  SELECT count(*) INTO v_present
  FROM participations
  WHERE user_id = p_user_id
    AND confirmed_present = true;

  -- Late cancellations (left < 12h before start)
  SELECT count(*) INTO v_late_cancels
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.status = 'withdrawn'
    AND p.left_at IS NOT NULL
    AND p.left_at > a.starts_at - INTERVAL '12 hours';

  -- Calculate score (0 to 100)
  IF v_total + v_late_cancels = 0 THEN
    v_score := NULL; -- Not enough data
  ELSE
    v_score := ROUND((v_present::float / (v_total + v_late_cancels)::float) * 100, 1);
  END IF;

  -- Update user
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION recalculate_reliability_score FROM anon, authenticated;

-- ============================================================================
-- ============================================================================
-- UPDATE: get_user_public_stats to include reliability_score
-- ============================================================================
DROP FUNCTION IF EXISTS get_user_public_stats;

CREATE OR REPLACE FUNCTION get_user_public_stats(
  p_user_id UUID
)
RETURNS TABLE (
  total_activities INTEGER,
  completed_activities INTEGER,
  sports_count INTEGER,
  reliability_score FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    (SELECT count(*)::int FROM participations
     WHERE user_id = p_user_id AND status = 'accepted') AS total_activities,
    (SELECT count(*)::int FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id AND par.status = 'accepted' AND a.status = 'completed') AS completed_activities,
    (SELECT count(DISTINCT jsonb_array_elements_text)::int
     FROM users, jsonb_array_elements_text(sports)
     WHERE users.id = p_user_id) AS sports_count,
    (SELECT u.reliability_score FROM users u WHERE u.id = p_user_id) AS reliability_score;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_public_stats FROM anon;
GRANT EXECUTE ON FUNCTION get_user_public_stats TO authenticated;

-- Reschedule pg_cron (every 5 minutes instead of 10)
-- ============================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('transition-activity-status');
    PERFORM cron.schedule(
      'transition-activity-status',
      '*/5 * * * *',
      'SELECT transition_activity_status()'
    );
  END IF;
END $$;
