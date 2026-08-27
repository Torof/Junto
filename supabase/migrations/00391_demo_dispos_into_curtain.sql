-- ============================================================================
-- 00391 — Fold demo Discovery dispos into the admin demo-mode curtain.
--
-- Replaces the one-shot 00390 seed (unguarded, always-on, random-UUID users)
-- with 3 dispos carried by EXISTING demo users, gated by the same curtain as
-- demo activities: visible only to a non-suspended admin while `demo_mode` is on.
--
--   (0) drop the 00390 one-shot partners.
--   (1) discovery_availabilities.is_demo (+ freeze it in the whitelist trigger).
--   (2) close the Discovery curtain hole: get_discovery_cards / _count /
--       get_dispo_zone now hide is_demo rows unless demo_content_visible().
--   (3) seed 3 demo dispos on demo users #2/#3/#6 (Marie L. / Thomas B. / Léa M.).
--   (4) admin_set_demo_mode: on enable, mirror the enabling admin's OWN active
--       dispo (sports + window) into the 3 demo dispos, bases offset a few km,
--       so the match cards always render — parallel to the activity-date refresh.
-- ============================================================================

-- ---------- (0) Remove the one-shot 00390 seed ----------
DELETE FROM auth.users WHERE email LIKE 'demo-partner-%@junto.local';

-- ---------- (1) is_demo column + whitelist freeze ----------
ALTER TABLE discovery_availabilities
  ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION discovery_availabilities_whitelist_columns()
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
  NEW.id := OLD.id;
  NEW.user_id := OLD.user_id;
  NEW.is_active := OLD.is_active;
  NEW.is_demo := OLD.is_demo;
  NEW.created_at := OLD.created_at;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ---------- (2) Curtain gate on the Discovery read functions ----------
-- get_discovery_cards (reproduced from 00380 + curtain gate on candidates)
CREATE OR REPLACE FUNCTION get_discovery_cards()
RETURNS TABLE (
  user_id UUID, display_name TEXT, avatar_url TEXT, reliability_tier TEXT,
  sport_keys TEXT[], levels JSONB, transport_modes TEXT[], radius_km INTEGER,
  window_start TIMESTAMPTZ, window_end TIMESTAMPTZ, intent TEXT[],
  distance_km DOUBLE PRECISION, sorties_count INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_radius INTEGER;
  v_sports TEXT[];
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  SELECT d.base, d.radius_km, d.sport_keys, d.window_start, d.window_end
    INTO v_base, v_radius, v_sports, v_ws, v_we
  FROM discovery_availabilities d WHERE d.user_id = v_user_id AND d.is_active;
  IF v_base IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT d.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         d.sport_keys, d.levels, d.transport_modes, d.radius_km,
         d.window_start, d.window_end, d.intent,
         (ST_Distance(d.base, v_base) / 1000.0) AS distance_km,
         (SELECT count(*)::int FROM participations p
          WHERE p.user_id = d.user_id AND p.status = 'accepted') AS sorties_count
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  JOIN public_profiles pp ON pp.id = d.user_id
  WHERE d.is_active
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && v_sports
    AND tstzrange(d.window_start, d.window_end) && tstzrange(v_ws, v_we)
    AND (v_radius IS NULL OR d.radius_km IS NULL
         OR ST_DWithin(d.base, v_base, (v_radius + d.radius_km) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id))
  ORDER BY pp.reliability_score DESC NULLS LAST, distance_km ASC;
END;
$$;
REVOKE ALL ON FUNCTION get_discovery_cards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_discovery_cards() TO authenticated;

-- get_discovery_count (reproduced from 00376 + curtain gate on candidates)
CREATE OR REPLACE FUNCTION get_discovery_count(
  p_sport_keys TEXT[],
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_radius_km INTEGER,
  p_window_start TIMESTAMPTZ,
  p_window_end TIMESTAMPTZ
) RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN 0; END IF;
  IF p_sport_keys IS NULL OR array_length(p_sport_keys, 1) IS NULL
     OR p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_window_start IS NULL OR p_window_end IS NULL THEN
    RETURN 0;
  END IF;
  v_base := ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography;

  SELECT count(*) INTO v_count
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  WHERE d.is_active
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && p_sport_keys
    AND tstzrange(d.window_start, d.window_end) && tstzrange(p_window_start, p_window_end)
    AND (p_radius_km IS NULL OR d.radius_km IS NULL
         OR ST_DWithin(d.base, v_base, (p_radius_km + d.radius_km) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id));

  IF v_count > 0 AND v_count <= 2 THEN RETURN -1; END IF;  -- -1 = "quelques"
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION get_discovery_count(TEXT[], DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_discovery_count(TEXT[], DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

-- get_dispo_zone (reproduced from 00380 + curtain gate on the target)
CREATE OR REPLACE FUNCTION get_dispo_zone(p_user_id UUID)
RETURNS TABLE (base_lng DOUBLE PRECISION, base_lat DOUBLE PRECISION, radius_km INTEGER)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_radius INTEGER;
  v_sports TEXT[];
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;
  IF v_user_id = p_user_id THEN RETURN; END IF;  -- own zone comes from get_my_dispo

  SELECT d.base, d.radius_km, d.sport_keys, d.window_start, d.window_end
    INTO v_base, v_radius, v_sports, v_ws, v_we
  FROM discovery_availabilities d WHERE d.user_id = v_user_id AND d.is_active;
  IF v_base IS NULL THEN RETURN; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE (b.blocker_id = v_user_id AND b.blocked_id = p_user_id)
       OR (b.blocker_id = p_user_id AND b.blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  RETURN QUERY
  SELECT ST_X(t.base::geometry), ST_Y(t.base::geometry), t.radius_km
  FROM discovery_availabilities t
  JOIN users u ON u.id = t.user_id AND u.suspended_at IS NULL
  WHERE t.user_id = p_user_id
    AND t.is_active
    AND (t.is_demo = false OR demo_content_visible())
    AND t.sport_keys && v_sports
    AND tstzrange(t.window_start, t.window_end) && tstzrange(v_ws, v_we)
    AND (v_radius IS NULL OR t.radius_km IS NULL
         OR ST_DWithin(t.base, v_base, (v_radius + t.radius_km) * 1000.0));
END;
$$;
REVOKE ALL ON FUNCTION get_dispo_zone(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_dispo_zone(UUID) TO authenticated;

-- ---------- (3) Seed 3 demo dispos on existing demo users ----------
-- Marie L. (#2), Thomas B. (#3), Léa M. (#6). Fallback sports/window/base near
-- Briançon; overwritten by admin_set_demo_mode on enable to mirror the admin's
-- own dispo. is_active + is_demo set directly (whitelist trigger is UPDATE-only).
INSERT INTO discovery_availabilities
  (user_id, sport_keys, levels, intent, base, base_label, radius_km, transport_modes, window_start, window_end, is_active, is_demo)
SELECT v.user_id, v.sports, '{}'::jsonb, v.intent,
       ST_SetSRID(ST_MakePoint(v.lng, 44.897), 4326)::geography,
       v.label, v.radius, v.transport, now(), now() + INTERVAL '14 days', true, true
FROM (VALUES
  ('d0000000-0000-4000-a000-000000000002'::uuid, ARRAY['hiking','trail-running'], ARRAY['performance','dog','active'],  'Briançon',       30, ARRAY['car','bike'], 6.695),
  ('d0000000-0000-4000-a000-000000000003'::uuid, ARRAY['climbing-sport'],         ARRAY['detente','solo','calm'],       'Montgenèvre',    50, ARRAY['on_foot'],   6.765),
  ('d0000000-0000-4000-a000-000000000006'::uuid, ARRAY['hiking'],                 ARRAY['discovery','group','early'],   'Le Monêtier',    30, ARRAY['car'],       6.815)
) AS v(user_id, sports, intent, label, radius, transport, lng)
WHERE NOT EXISTS (
  SELECT 1 FROM discovery_availabilities d WHERE d.user_id = v.user_id
);

-- ---------- (4) admin_set_demo_mode: also mirror admin's dispo into demo dispos ----------
CREATE OR REPLACE FUNCTION admin_set_demo_mode(p_on boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin uuid;
  v_base GEOGRAPHY;
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
  v_sports TEXT[];
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE app_config SET value = CASE WHEN p_on THEN 'true' ELSE 'false' END
  WHERE name = 'demo_mode';

  IF p_on THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);

    -- Demo activities: distinct upcoming day + time-of-day (unchanged from 00335).
    WITH ordered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM activities WHERE is_demo = true AND deleted_at IS NULL
    )
    UPDATE activities a
    SET starts_at = date_trunc('day', now())
          + make_interval(
              days  => (1 + o.rn * 2)::int,
              hours => (ARRAY[9,14,11,17,8,16,10,15])[((o.rn - 1) % 8) + 1],
              mins  => (ARRAY[0,30,0,30,15,0,45,30])[((o.rn - 1) % 8) + 1]
            ),
        status = 'published'
    FROM ordered o
    WHERE a.id = o.id;

    -- Demo dispos: mirror the enabling admin's OWN active dispo so the match
    -- cards always render. Bases offset a few km east; radii varied for display.
    SELECT d.base, d.window_start, d.window_end, d.sport_keys
      INTO v_base, v_ws, v_we, v_sports
    FROM discovery_availabilities d
    WHERE d.user_id = v_admin AND d.is_active AND d.is_demo = false;

    IF v_base IS NOT NULL THEN
      WITH ordered AS (
        SELECT id, row_number() OVER (ORDER BY user_id) AS rn
        FROM discovery_availabilities WHERE is_demo = true
      )
      UPDATE discovery_availabilities dd
      SET sport_keys   = v_sports,
          window_start = v_ws,
          window_end   = v_we,
          radius_km    = (ARRAY[30,50,30])[((o.rn - 1) % 3) + 1],
          base = ST_SetSRID(ST_MakePoint(
                   ST_X(v_base::geometry) + (ARRAY[0.06,0.13,0.18])[((o.rn - 1) % 3) + 1],
                   ST_Y(v_base::geometry)), 4326)::geography,
          is_active = true
      FROM ordered o
      WHERE dd.id = o.id;
    END IF;
  END IF;

  PERFORM log_admin_action(
    v_admin,
    CASE WHEN p_on THEN 'demo_mode_on' ELSE 'demo_mode_off' END,
    'app_config', NULL, NULL, NULL
  );
END;
$$;
REVOKE ALL ON FUNCTION admin_set_demo_mode(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_demo_mode(boolean) TO authenticated;
