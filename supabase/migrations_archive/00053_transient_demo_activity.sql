-- Migration 00053: make demo activity transient (reuse if exists, delete on tutorial end)

-- ============================================================================
-- seed_demo_activity — reuse existing demo activity nearby instead of duplicating
-- ============================================================================
CREATE OR REPLACE FUNCTION seed_demo_activity(
  p_lng FLOAT,
  p_lat FLOAT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_sport_id UUID;
  v_activity_id UUID;
  v_demo_user_id UUID := '0deadbee-f000-0000-0000-000000000001';
  v_offset_lng FLOAT := 0.015;
  v_offset_lat FLOAT := 0.015;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Reuse if a demo activity already exists within ~5 km of requested point
  SELECT id INTO v_activity_id
  FROM activities
  WHERE creator_id = v_demo_user_id
    AND ST_DWithin(
      location_start,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      5000
    )
  LIMIT 1;

  IF v_activity_id IS NOT NULL THEN
    RETURN v_activity_id;
  END IF;

  -- Otherwise create one
  SELECT id INTO v_sport_id FROM sports WHERE key = 'running' LIMIT 1;
  IF v_sport_id IS NULL THEN
    SELECT id INTO v_sport_id FROM sports ORDER BY key LIMIT 1;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start,
    starts_at, duration, visibility, status, created_at, updated_at
  ) VALUES (
    v_demo_user_id,
    v_sport_id,
    'Sortie découverte Junto',
    'Activité de démonstration pour découvrir l''app.',
    'débutant',
    10,
    ST_SetSRID(ST_MakePoint(p_lng + v_offset_lng, p_lat + v_offset_lat), 4326)::geography,
    now() + INTERVAL '3 days',
    '2 hours'::interval,
    'public',
    'published',
    now(), now()
  ) RETURNING id INTO v_activity_id;

  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_demo_user_id, 'accepted', now());

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION seed_demo_activity FROM anon;
GRANT EXECUTE ON FUNCTION seed_demo_activity TO authenticated;

-- ============================================================================
-- delete_demo_activity — called at end of tutorial
-- Only deletes if the activity is owned by the demo user
-- ============================================================================
CREATE OR REPLACE FUNCTION delete_demo_activity(p_activity_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_demo_user_id UUID := '0deadbee-f000-0000-0000-000000000001';
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  DELETE FROM activities
  WHERE id = p_activity_id
    AND creator_id = v_demo_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION delete_demo_activity FROM anon;
GRANT EXECUTE ON FUNCTION delete_demo_activity TO authenticated;
