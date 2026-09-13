-- ============================================================================
-- 00415 — More Discovery demo partners (Scott 2026-09-13): 3 → 8 demo dispos,
-- diverse "types" so a solo tester sees varied match cards.
--   (1) 3 NEW demo users (#7 Nadia K., #8 Hugo P., #9 Camille V.) — same
--       pattern as 00334 (auth.users fixed UUID → trigger → bypass identity).
--   (2) Portraits + reliability for Julie R. (#4) & Karim D. (#5) (they only
--       had ui-avatars from 00334) and for the 3 new users. Varied tiers.
--   (3) A bit of completed HISTORY participation for the new users (00393
--       c0000000-… activities) so their profiles/sorties_count aren't empty.
--   (4) 5 new demo dispos (Julie, Karim, Nadia, Hugo, Camille) — diverse
--       sports (incl. the 00414 newcomers), vibes, abouts, radii (one NULL =
--       "peu importe"), transports. Gated by the same is_demo curtain.
--   (5) admin_set_demo_mode refresh reworked for DIVERSITY: instead of
--       overwriting every demo dispo with the admin's exact sports, each
--       partner keeps ONE admin sport (rotation → guaranteed match) + its own
--       2 "flavor" sports; windows become varied sub-windows of the admin's;
--       radii/offsets varied per partner. Offsets stay small enough that the
--       tightest radius pair (admin 5 + partner 10 = 15 km) still matches.
-- ============================================================================

-- ---------- (1) New demo users ----------
INSERT INTO auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000007', 'authenticated', 'authenticated', 'demo.nadia@junto.demo',   '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000008', 'authenticated', 'authenticated', 'demo.hugo@junto.demo',    '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000009', 'authenticated', 'authenticated', 'demo.camille@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}')
ON CONFLICT (id) DO NOTHING;

-- ---------- (1+2) Identity / portraits / reliability under bypass ----------
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE public.users u SET
    display_name      = d.display_name,
    avatar_url        = d.avatar_url,
    bio               = d.bio,
    reliability_score = d.score,
    is_demo           = true
  FROM (VALUES
    ('d0000000-0000-4000-a000-000000000007'::uuid, 'Nadia K.',   'https://randomuser.me/api/portraits/women/22.jpg', 'VTT enduro & gravel dans l''Embrunais.',            91::float),
    ('d0000000-0000-4000-a000-000000000008'::uuid, 'Hugo P.',    'https://randomuser.me/api/portraits/men/75.jpg',   'Trail — en préparation de mon premier ultra.',      61::float),
    ('d0000000-0000-4000-a000-000000000009'::uuid, 'Camille V.', 'https://randomuser.me/api/portraits/women/33.jpg', 'Windsurf & natation en eau libre.',                 79::float)
  ) AS d(id, display_name, avatar_url, bio, score)
  WHERE u.id = d.id;

  -- Julie & Karim get real portraits + a score (varied tiers), like 00392.
  UPDATE public.users u SET
    avatar_url        = d.avatar_url,
    reliability_score = d.score
  FROM (VALUES
    ('d0000000-0000-4000-a000-000000000004'::uuid, 'https://randomuser.me/api/portraits/women/51.jpg', 88::float), -- Julie R. → good
    ('d0000000-0000-4000-a000-000000000005'::uuid, 'https://randomuser.me/api/portraits/men/41.jpg',   74::float)  -- Karim D. → fair/good
  ) AS d(id, avatar_url, score)
  WHERE u.id = d.id;

  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;

-- ---------- (3) Completed-history participation for the new users ----------
INSERT INTO participations (activity_id, user_id, status)
SELECT p.activity_id, p.user_id, 'accepted'
FROM (VALUES
  -- Nadia: rando Partias, trail Prorel, ski Granon
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  -- Hugo: trail Prorel, via ferrata, traversée Écrins
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  -- Camille: canyon du Fournel, rando Partias
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid)
) AS p(activity_id, user_id)
ON CONFLICT (user_id, activity_id) DO NOTHING;

-- ---------- (4) 5 new demo dispos (diverse types) ----------
-- Static fallback values (shown if demo mode is enabled while the admin has no
-- active dispo); overwritten by the admin_set_demo_mode refresh below.
INSERT INTO discovery_availabilities
  (user_id, sport_keys, levels, intent, about, base, base_label, radius_km, transport_modes, window_start, window_end, is_active, is_demo)
SELECT v.user_id, v.sports, v.levels, v.intent, v.about,
       ST_SetSRID(ST_MakePoint(v.lng, v.lat), 4326)::geography,
       v.label, v.radius, v.transport, now(), now() + INTERVAL '14 days', true, true
FROM (VALUES
  ('d0000000-0000-4000-a000-000000000004'::uuid,                                     -- Julie R. — grimpe engagée
   ARRAY['climbing-sport','climbing-multipitch','mountaineering'],
   '{"climbing-sport":"6a","climbing-multipitch":"5c"}'::jsonb,
   ARRAY['same_level','long_outing','performance'],
   'Grimpeuse depuis dix ans, autant à l''aise en couenne qu''en grande voie. Je cherche des cordées sérieuses pour des journées complètes, idéalement le week-end.',
   'L''Argentière-la-Bessée', 15, ARRAY['car','public_transport'], 6.560, 44.788),
  ('d0000000-0000-4000-a000-000000000005'::uuid,                                     -- Karim D. — marche-vol
   ARRAY['paragliding','hiking'], '{}'::jsonb,
   ARRAY['early','solo','experienced'],
   'Parapentiste, marche-vol surtout. Décollage tôt le matin, je redescends toujours à pied. Ouvert aux curieux qui veulent voir ce que ça donne.',
   'Vallouise', NULL, ARRAY['car','motorbike'], 6.487, 44.846),
  ('d0000000-0000-4000-a000-000000000007'::uuid,                                     -- Nadia K. — VTT/gravel
   ARRAY['mtb-enduro','gravel','cycling'], '{}'::jsonb,
   ARRAY['after_work','regular','challenge'],
   'Enduro ou gravel selon la météo. Après le boulot en semaine, plus long le week-end. Je roule à un rythme soutenu mais j''attends en haut !',
   'Embrun', 50, ARRAY['car','bike'], 6.495, 44.564),
  ('d0000000-0000-4000-a000-000000000008'::uuid,                                     -- Hugo P. — trail
   ARRAY['trail-running','running'], '{}'::jsonb,
   ARRAY['training','regular','early','performance'],
   'Trail le matin avant le travail, sortie longue le dimanche. Objectif premier ultra l''an prochain — je cherche des partenaires réguliers pour tenir le plan d''entraînement.',
   'Serre Chevalier', 10, ARRAY['on_foot','public_transport'], 6.556, 44.941),
  ('d0000000-0000-4000-a000-000000000009'::uuid,                                     -- Camille V. — nouveaux sports 00414
   ARRAY['windsurfing','swimming'], '{}'::jsonb,
   ARRAY['discovery','mixed','photo','conviviality'],
   'Nouvelle dans la région ! Planche à voile dès qu''il y a du vent, natation en lac sinon. Partante pour découvrir d''autres spots et d''autres sports.',
   'Plan d''eau d''Embrun', 30, ARRAY['car'], 6.489, 44.558)
) AS v(user_id, sports, levels, intent, about, label, radius, transport, lng, lat)
WHERE NOT EXISTS (
  SELECT 1 FROM discovery_availabilities d WHERE d.user_id = v.user_id
);

-- ---------- (5) Diversity-preserving refresh in admin_set_demo_mode ----------
-- Reproduced from 00398; only the demo-dispo UPDATE changes.
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

    -- Showcase demo activities only → future dates. The completed HISTORY
    -- (c0000000-…, feeds the rich profiles) is excluded by UUID range so it can
    -- never be dragged into the re-date pool (a status-only guard traps it).
    WITH ordered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM activities
      WHERE is_demo = true AND deleted_at IS NULL AND id::text NOT LIKE 'c0000000-%'
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

    -- Demo dispos: each partner keeps ONE of the admin's sports (rotation →
    -- every card matches) + up to 2 of its own flavor sports, on a varied
    -- sub-window of the admin's window, with varied radius/offset per partner.
    SELECT d.base, d.window_start, d.window_end, d.sport_keys
      INTO v_base, v_ws, v_we, v_sports
    FROM discovery_availabilities d
    WHERE d.user_id = v_admin AND d.is_active AND d.is_demo = false;

    IF v_base IS NOT NULL THEN
      WITH ordered AS (
        SELECT id, user_id, row_number() OVER (ORDER BY user_id) AS rn
        FROM discovery_availabilities WHERE is_demo = true
      ),
      flavors(user_id, extras) AS (VALUES
        ('d0000000-0000-4000-a000-000000000002'::uuid, ARRAY['trail-running','hiking']),
        ('d0000000-0000-4000-a000-000000000003'::uuid, ARRAY['climbing-sport','bouldering']),
        ('d0000000-0000-4000-a000-000000000004'::uuid, ARRAY['climbing-multipitch','mountaineering']),
        ('d0000000-0000-4000-a000-000000000005'::uuid, ARRAY['paragliding','hiking']),
        ('d0000000-0000-4000-a000-000000000006'::uuid, ARRAY['via-ferrata','canyoning']),
        ('d0000000-0000-4000-a000-000000000007'::uuid, ARRAY['mtb-enduro','gravel']),
        ('d0000000-0000-4000-a000-000000000008'::uuid, ARRAY['trail-running','running']),
        ('d0000000-0000-4000-a000-000000000009'::uuid, ARRAY['windsurfing','swimming'])
      )
      UPDATE discovery_availabilities dd
      SET sport_keys = (
            ARRAY[v_sports[((o.rn - 1) % cardinality(v_sports)) + 1]]
            || array_remove(COALESCE(f.extras, '{}'::text[]),
                            v_sports[((o.rn - 1) % cardinality(v_sports)) + 1])
          )[1:3],
          window_start = v_ws + (v_we - v_ws)
            * ((ARRAY[0,2,1,3,0,2,1,3])[((o.rn - 1) % 8) + 1] / 10.0),
          window_end   = v_we - (v_we - v_ws)
            * ((ARRAY[0,1,2,0,3,1,0,2])[((o.rn - 1) % 8) + 1] / 10.0),
          radius_km    = (ARRAY[30,50,15,NULL,50,10,30,15])[((o.rn - 1) % 8) + 1],
          base = ST_SetSRID(ST_MakePoint(
                   ST_X(v_base::geometry) + (ARRAY[0.06,0.13,-0.08,0.10,-0.12,0.15,0.04,-0.05])[((o.rn - 1) % 8) + 1],
                   ST_Y(v_base::geometry) + (ARRAY[0.00,0.03,-0.02,0.05,0.02,0.01,-0.04,0.04])[((o.rn - 1) % 8) + 1]),
                 4326)::geography,
          is_active = true
      FROM ordered o
      LEFT JOIN flavors f ON f.user_id = o.user_id
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
