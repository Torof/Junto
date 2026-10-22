-- ============================================================================
-- 00393 — Fill the demo profiles (Scott 2026-08-27): give the demo users a real
-- past so their profiles look full when opened from a Discovery card.
--
-- Profile blocks (get_user_public_stats / get_user_trophies / _sport_levels /
-- _award_aggregates) ALL count only activities.status='completed'. The showcase
-- demo activities are 'published' (and re-dated to the future on every demo-mode
-- enable), so they never feed the profile. This seeds a separate HISTORY of 8
-- COMPLETED is_demo outings among the 6 demo users → non-zero completed / created
-- / joined counts, ~8 sports, and a "Rejoint" trophy (≥5 joined). It also seeds
-- peer judgments (reputation_votes, counted) → "vouched" trait badges + a
-- positive per-sport honesty triangle.
--
-- reliability_score stays as set in 00392 (94/82/68) for varied demo tiers — no
-- recompute is triggered here. admin_set_demo_mode is patched so its date-refresh
-- skips completed activities (otherwise it would un-complete this history).
-- ============================================================================

-- ---------- (1) 8 completed HISTORY activities (is_demo, past) ----------
INSERT INTO activities
  (id, creator_id, sport_id, title, description, level, level_max,
   max_participants, location_meeting, meeting_name,
   location_objective, objective_name,
   starts_at, duration, visibility, requires_presence, status,
   distance_km, elevation_gain_m, is_demo)
VALUES
  ('c0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000002',
   (SELECT id FROM sports WHERE key = 'hiking'),
   'Boucle des Partias', 'Sortie tranquille en boucle, pique-nique au sommet.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.578, 44.884), 4326)::geography, 'Puy-Chalvin',
   ST_SetSRID(ST_MakePoint(6.554, 44.877), 4326)::geography, 'Croix d''Aquila',
   now() - INTERVAL '40 days', INTERVAL '5 hours', 'public', true, 'completed', 11.0, 600, true),

  ('c0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000003',
   (SELECT id FROM sports WHERE key = 'climbing-sport'),
   'Couennes au Rocher Baron', 'Belle après-midi grimpe, voies de la 4 à la 6c.',
   'intermédiaire', 'avancé', 6,
   ST_SetSRID(ST_MakePoint(6.629, 44.876), 4326)::geography, 'Villar-Saint-Pancrace',
   ST_SetSRID(ST_MakePoint(6.589, 44.845), 4326)::geography, 'Rocher Baron',
   now() - INTERVAL '35 days', INTERVAL '4 hours', 'public', true, 'completed', NULL, NULL, true),

  ('c0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000002',
   (SELECT id FROM sports WHERE key = 'trail-running'),
   'Trail du Prorel', 'Montée sèche puis single retour, bon rythme.',
   'avancé', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.635, 44.895), 4326)::geography, 'Briançon gare',
   ST_SetSRID(ST_MakePoint(6.587, 44.902), 4326)::geography, 'Sommet du Prorel',
   now() - INTERVAL '30 days', INTERVAL '3 hours', 'public', true, 'completed', 14.0, 1100, true),

  ('c0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000004',
   (SELECT id FROM sports WHERE key = 'via-ferrata'),
   'Via ferrata des Vigneaux', 'Parcours ludique, ambiance aérienne, débutants bienvenus.',
   'débutant', 'intermédiaire', 8,
   ST_SetSRID(ST_MakePoint(6.503, 44.845), 4326)::geography, 'Les Vigneaux',
   ST_SetSRID(ST_MakePoint(6.505, 44.848), 4326)::geography, 'Via des Vigneaux',
   now() - INTERVAL '25 days', INTERVAL '4 hours', 'public', true, 'completed', NULL, 400, true),

  ('c0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000003',
   (SELECT id FROM sports WHERE key = 'mountaineering'),
   'Arête de la Blanche', 'Course facile PD, réveil tôt, glace matinale.',
   'avancé', NULL, 4,
   ST_SetSRID(ST_MakePoint(6.512, 44.912), 4326)::geography, 'Vallouise',
   ST_SetSRID(ST_MakePoint(6.480, 44.930), 4326)::geography, 'Arête de la Blanche',
   now() - INTERVAL '20 days', INTERVAL '8 hours', 'public', true, 'completed', 9.0, 1300, true),

  ('c0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000005',
   (SELECT id FROM sports WHERE key = 'canyoning'),
   'Canyon du Fournel', 'Descente aquatique, combinaison obligatoire, super rappels.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.500, 44.788), 4326)::geography, 'L''Argentière',
   ST_SetSRID(ST_MakePoint(6.527, 44.788), 4326)::geography, 'Canyon du Fournel',
   now() - INTERVAL '15 days', INTERVAL '5 hours', 'public', true, 'completed', NULL, NULL, true),

  ('c0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000006',
   (SELECT id FROM sports WHERE key = 'ski-touring'),
   'Rando à ski du Granon', 'Poudreuse au rendez-vous, montée peau de phoque, belle descente.',
   'intermédiaire', 'avancé', 6,
   ST_SetSRID(ST_MakePoint(6.610, 44.945), 4326)::geography, 'Col du Granon',
   ST_SetSRID(ST_MakePoint(6.630, 44.960), 4326)::geography, 'Pic du Lauzin',
   now() - INTERVAL '10 days', INTERVAL '5 hours', 'public', true, 'completed', 8.0, 900, true),

  ('c0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000004',
   (SELECT id FROM sports WHERE key = 'trekking'),
   'Traversée des Écrins (2j)', 'Rando itinérante sur deux jours, refuge le soir.',
   'avancé', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.400, 44.900), 4326)::geography, 'Ailefroide',
   ST_SetSRID(ST_MakePoint(6.360, 44.920), 4326)::geography, 'Refuge du Glacier Blanc',
   now() - INTERVAL '5 days', INTERVAL '30 hours', 'public', true, 'completed', 24.0, 1800, true)
ON CONFLICT (id) DO NOTHING;

-- ---------- (2) Accepted participations (drive counts/trophies/levels) ----------
INSERT INTO participations (activity_id, user_id, status)
SELECT p.activity_id, p.user_id, 'accepted'
FROM (VALUES
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid)
) AS p(activity_id, user_id)
ON CONFLICT (user_id, activity_id) DO NOTHING;

-- ---------- (3) Peer judgments — counted reputation votes ----------
-- Trait "vouched" badges: ≥5 distinct voters on one shared activity → bronze.
--   Thomas #3: Ponctuel + Préparé (voters 1,2,4,5,6 on c2)
--   Marie  #2: Conciliant + Préparé (voters 1,3,4,5,6 on c1)
--   Léa    #6: Prudent + Ponctuel (voters 1,2,3,4,5 on c7)
INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, counted_at)
SELECT g.voter, g.voted, g.activity, g.badge, now()
FROM (
  SELECT v.voter, 'd0000000-0000-4000-a000-000000000003'::uuid AS voted,
         'c0000000-0000-4000-a000-000000000002'::uuid AS activity, b.badge
  FROM unnest(ARRAY['d0000000-0000-4000-a000-000000000001','d0000000-0000-4000-a000-000000000002',
                    'd0000000-0000-4000-a000-000000000004','d0000000-0000-4000-a000-000000000005',
                    'd0000000-0000-4000-a000-000000000006']::uuid[]) AS v(voter)
  CROSS JOIN unnest(ARRAY['punctual','prepared']) AS b(badge)
  UNION ALL
  SELECT v.voter, 'd0000000-0000-4000-a000-000000000002'::uuid,
         'c0000000-0000-4000-a000-000000000001'::uuid, b.badge
  FROM unnest(ARRAY['d0000000-0000-4000-a000-000000000001','d0000000-0000-4000-a000-000000000003',
                    'd0000000-0000-4000-a000-000000000004','d0000000-0000-4000-a000-000000000005',
                    'd0000000-0000-4000-a000-000000000006']::uuid[]) AS v(voter)
  CROSS JOIN unnest(ARRAY['conciliant','prepared']) AS b(badge)
  UNION ALL
  SELECT v.voter, 'd0000000-0000-4000-a000-000000000006'::uuid,
         'c0000000-0000-4000-a000-000000000007'::uuid, b.badge
  FROM unnest(ARRAY['d0000000-0000-4000-a000-000000000001','d0000000-0000-4000-a000-000000000002',
                    'd0000000-0000-4000-a000-000000000003','d0000000-0000-4000-a000-000000000004',
                    'd0000000-0000-4000-a000-000000000005']::uuid[]) AS v(voter)
  CROSS JOIN unnest(ARRAY['prudent','punctual']) AS b(badge)
) AS g(voter, voted, activity, badge)
ON CONFLICT (voter_id, voted_id, activity_id, badge_key) DO NOTHING;

-- Per-sport honesty triangle: positive 'level_right' votes on the target's sport.
--   Thomas on climbing (c2), Marie on hiking (c1), Léa on ski-touring (c7).
INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, counted_at)
SELECT g.voter, g.voted, g.activity, 'level_right', now()
FROM (
  SELECT v.voter, 'd0000000-0000-4000-a000-000000000003'::uuid AS voted,
         'c0000000-0000-4000-a000-000000000002'::uuid AS activity
  FROM unnest(ARRAY['d0000000-0000-4000-a000-000000000002','d0000000-0000-4000-a000-000000000004',
                    'd0000000-0000-4000-a000-000000000006']::uuid[]) AS v(voter)
  UNION ALL
  SELECT v.voter, 'd0000000-0000-4000-a000-000000000002'::uuid,
         'c0000000-0000-4000-a000-000000000001'::uuid
  FROM unnest(ARRAY['d0000000-0000-4000-a000-000000000003','d0000000-0000-4000-a000-000000000004',
                    'd0000000-0000-4000-a000-000000000006']::uuid[]) AS v(voter)
  UNION ALL
  SELECT v.voter, 'd0000000-0000-4000-a000-000000000006'::uuid,
         'c0000000-0000-4000-a000-000000000007'::uuid
  FROM unnest(ARRAY['d0000000-0000-4000-a000-000000000002','d0000000-0000-4000-a000-000000000003',
                    'd0000000-0000-4000-a000-000000000004']::uuid[]) AS v(voter)
) AS g(voter, voted, activity)
ON CONFLICT (voter_id, voted_id, activity_id, badge_key) DO NOTHING;

-- ---------- (4) Protect the history from the demo-mode date refresh ----------
-- admin_set_demo_mode re-stamps every is_demo activity to a future date +
-- 'published' on enable. Restrict that to the SHOWCASE (non-completed) ones so
-- this completed history is never un-completed.
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

    -- Showcase demo activities only (never the completed history) → future dates.
    WITH ordered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM activities
      WHERE is_demo = true AND deleted_at IS NULL AND status <> 'completed'
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

    -- Demo dispos mirror the enabling admin's own active dispo (see 00391).
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
