-- Migration 00036: Lazy activity transitions (no pg_cron dependency)
-- Two layers: lazy (with notifications) + global fallback (status only, no notifications)
-- No duplicate notification risk — only the lazy layer sends notifications

-- ============================================================================
-- INDEX: optimized for status-first queries
-- ============================================================================
CREATE INDEX activities_status_starts_idx
ON activities(status, starts_at DESC)
WHERE deleted_at IS NULL;

-- ============================================================================
-- FUNCTION: transition_single_activity (lazy, scoped, idempotent, WITH notifications)
-- Called when viewing activity detail
-- ============================================================================
CREATE OR REPLACE FUNCTION transition_single_activity(
  p_activity_id UUID
)
RETURNS TEXT
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

  -- 2. Get activity with lock to prevent races
  SELECT id, creator_id, title, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_activity IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Must be creator or accepted participant (not withdrawn/refused/removed)
  IF v_user_id != v_activity.creator_id THEN
    IF NOT EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
    ) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  -- 4. Bypass trigger for status updates
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 5. published → expired (no participants, 2h past)
  IF v_activity.status = 'published' AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  -- 6. published → in_progress
  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
    END IF;
  END IF;

  -- 7. in_progress → completed (with notifications)
  IF v_activity.status = 'in_progress' AND v_activity.starts_at + v_activity.duration <= now() THEN
    UPDATE activities SET status = 'completed', updated_at = now()
    WHERE id = p_activity_id AND status = 'in_progress';

    IF FOUND THEN
      -- Notify creator to confirm presence
      PERFORM create_notification(
        v_activity.creator_id,
        'confirm_presence',
        'Activité terminée',
        'Confirme qui était présent à ' || v_activity.title,
        jsonb_build_object('activity_id', p_activity_id)
      );

      -- Notify all participants to rate
      FOR v_participant IN
        SELECT user_id FROM participations
        WHERE activity_id = p_activity_id AND status = 'accepted'
      LOOP
        PERFORM create_notification(
          v_participant.user_id,
          'rate_participants',
          'Évalue tes co-participants',
          'Comment s''est passé ' || v_activity.title || ' ?',
          jsonb_build_object('activity_id', p_activity_id)
        );
      END LOOP;

      RETURN 'completed';
    END IF;
  END IF;

  RETURN v_activity.status;
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_single_activity FROM anon;
GRANT EXECUTE ON FUNCTION transition_single_activity TO authenticated;

-- ============================================================================
-- FUNCTION: transition_statuses_only (global fallback, NO notifications)
-- Status updates only — notifications handled by lazy transition
-- ============================================================================
CREATE OR REPLACE FUNCTION transition_statuses_only()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- published → in_progress
  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published'
    AND starts_at <= now();

  -- in_progress → completed (NO notifications — lazy transition handles those)
  UPDATE activities
  SET status = 'completed', updated_at = now()
  WHERE status = 'in_progress'
    AND starts_at + duration <= now();

  -- published → expired
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

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;

-- ============================================================================
-- FUNCTION: check_activity_transitions (client-callable global wrapper)
-- ============================================================================
CREATE OR REPLACE FUNCTION check_activity_transitions()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('activity_transitions')) THEN
    RETURN;
  END IF;

  PERFORM transition_statuses_only();
END;
$$;

REVOKE EXECUTE ON FUNCTION check_activity_transitions FROM anon;
GRANT EXECUTE ON FUNCTION check_activity_transitions TO authenticated;
