-- ============================================================================
-- 00390 — TEMPORARY demo seed (Scott 2026-08-27): 3 fake partners with an
-- active dispo that MIRRORS the caller's own active dispo (same sports + window,
-- base offset a few km, radius 30/50) so the Découverte match cards actually
-- render for a solo tester. Marked is_demo + email 'demo-partner-%@junto.local'
-- so they are trivially removable. REMOVE via a follow-up cleanup migration once
-- the visual is validated. No-op if no real active dispo exists to mirror.
-- ============================================================================

DO $$
DECLARE
  v_t RECORD;
  v_ids UUID[] := ARRAY[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
  v_names TEXT[] := ARRAY['Marc', 'Léa', 'Tom'];
  v_labels TEXT[] := ARRAY['Briançon', 'Montgenèvre', 'Le Monêtier'];
  v_radii INT[] := ARRAY[30, 50, 30];
  v_dx DOUBLE PRECISION[] := ARRAY[0.06, 0.13, 0.18];
  v_intent TEXT[];
  v_tr TEXT[];
  i INT;
BEGIN
  -- Mirror a real (non-demo) active dispo — the tester's.
  SELECT d.sport_keys AS sports, d.window_start AS ws, d.window_end AS we,
         ST_X(d.base::geometry) AS lng, ST_Y(d.base::geometry) AS lat
    INTO v_t
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.is_demo = false AND u.suspended_at IS NULL
  WHERE d.is_active
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE NOTICE 'No real active dispo to mirror — no demo partners seeded.';
    RETURN;
  END IF;

  FOR i IN 1..3 LOOP
    INSERT INTO auth.users (id, instance_id, aud, role, email, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    VALUES (v_ids[i], '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'demo-partner-' || i || '@junto.local', now(),
            '{"provider":"demo","providers":["demo"]}'::jsonb, '{"demo":true}'::jsonb, now(), now());
    -- handle_new_user() created public.users with a random name — set ours + demo flag.
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE public.users SET display_name = v_names[i], is_demo = true WHERE id = v_ids[i];
    PERFORM set_config('junto.bypass_lock', 'false', true);

    v_intent := CASE i WHEN 1 THEN ARRAY['performance', 'dog', 'active']
                       WHEN 2 THEN ARRAY['detente', 'solo', 'calm']
                       ELSE ARRAY['discovery', 'group', 'early'] END;
    v_tr := CASE i WHEN 1 THEN ARRAY['car', 'bike']
                   WHEN 2 THEN ARRAY['on_foot']
                   ELSE ARRAY['car'] END;

    INSERT INTO discovery_availabilities
      (user_id, sport_keys, levels, intent, base, base_label, radius_km, transport_modes, window_start, window_end, is_active)
    VALUES (
      v_ids[i], v_t.sports, '{}'::jsonb, v_intent,
      ST_SetSRID(ST_MakePoint(v_t.lng + v_dx[i], v_t.lat), 4326)::geography,
      v_labels[i], v_radii[i], v_tr, v_t.ws, v_t.we, true
    );
  END LOOP;
END $$;
