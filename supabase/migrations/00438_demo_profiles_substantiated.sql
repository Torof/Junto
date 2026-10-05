-- ============================================================================
-- 00438 — Demo profiles substantiated (Scott 2026-10-05: « j'aimerais que ces
-- faux profils soient réellement étayés »). Three defects left the 8 demo
-- partners' profiles thin:
--   (1) users.sports / levels_per_sport were never set (00334/00415 only set
--       name, portrait, bio) → no sport icons, sports_count = 0.
--   (2) 00435 re-ran recalculate_reliability_score on EVERY user with a score,
--       demo users included: their history participations had
--       confirmed_present NULL → 0 counted outings → (1+0)/(1+0) = 100 for all
--       nine. The hardcoded 94/82/68/88/74/91/61/79 of 00392/00415 were lost.
--   (3) close_due_presence_windows (cron) walks every completed +
--       requires_presence activity ended > 24h ago with NULL presences — the
--       00393 history exactly — and close_presence_window_for flips a
--       completed activity with no confirmed presence to 'expired'. Counts,
--       trophies, level dots and counted votes vanish with it. The creators
--       also had no participation row on their own history outings (the real
--       create_activity inserts one), so the hero's « Créées » stayed at 0.
--
-- Repair, for the 8 peer partners (#2–#9; Air & Water #1 untouched):
--   A. declared sports + levels (generic tiers, as set_sport_level stores).
--   B. history back to 'completed' + creator participation rows + 18 more
--      completed outings (c0000000-… ids, which admin_set_demo_mode's
--      date refresh already skips).
--   C. confirmed_present set EXPLICITLY on every history participation
--      (present/absent per persona) + 2 late withdrawals → reliability is
--      DERIVED by the real formula, no hardcoded score any more, and the
--      sweep can never expire the history again (no NULL left).
--   D. counted trait votes for all 8 (≥5 per trait) + 'level_right' votes on
--      each main sport, from present co-participants.
--   E. recalculate_reliability_score for the 8 → expected tiers:
--      see the NOTICE lines at the end of the push (one per demo user).
-- ============================================================================

-- ---------- A. Declared sports + levels (privileged → bypass) ----------
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE public.users u SET
    sports           = d.sports,
    levels_per_sport = d.levels
  FROM (VALUES
    ('d0000000-0000-4000-a000-000000000002'::uuid, '["hiking", "trail-running", "ski-touring"]'::jsonb, '{"hiking": "avancé", "trail-running": "intermédiaire", "ski-touring": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000003'::uuid, '["climbing-sport", "bouldering", "mountaineering"]'::jsonb, '{"climbing-sport": "avancé", "bouldering": "intermédiaire", "mountaineering": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000004'::uuid, '["climbing-sport", "climbing-multipitch", "mountaineering", "via-ferrata"]'::jsonb, '{"climbing-sport": "intermédiaire", "climbing-multipitch": "intermédiaire", "mountaineering": "intermédiaire", "via-ferrata": "avancé"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000005'::uuid, '["paragliding", "hiking"]'::jsonb, '{"paragliding": "intermédiaire", "hiking": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000006'::uuid, '["via-ferrata", "canyoning", "ski-touring", "hiking"]'::jsonb, '{"via-ferrata": "intermédiaire", "canyoning": "intermédiaire", "ski-touring": "intermédiaire", "hiking": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000007'::uuid, '["mtb-enduro", "gravel", "cycling"]'::jsonb, '{"mtb-enduro": "avancé", "gravel": "avancé", "cycling": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000008'::uuid, '["trail-running", "running"]'::jsonb, '{"trail-running": "avancé", "running": "avancé"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000009'::uuid, '["windsurfing", "swimming"]'::jsonb, '{"windsurfing": "débutant", "swimming": "avancé"}'::jsonb)
  ) AS d(id, sports, levels)
  WHERE u.id = d.id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;

-- ---------- B0. Trim three over-generous 00393 participations ----------
-- (everyone was on everything → every profile had 8+ distinct sports and the
-- same « Polyvalent » tier; a little less overlap gives real variety.)
DELETE FROM reputation_votes WHERE (voter_id, activity_id) IN (
  ('d0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000004'::uuid),
  ('d0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000004'::uuid),
  ('d0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000008'::uuid),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'c0000000-0000-4000-a000-000000000006'::uuid)
);
DELETE FROM participations WHERE (user_id, activity_id) IN (
  ('d0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000004'::uuid),
  ('d0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000004'::uuid),
  ('d0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000008'::uuid),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'c0000000-0000-4000-a000-000000000006'::uuid)
);

-- ---------- B1. History back to 'completed' (status is whitelist-protected) ----------
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE activities
  SET status = 'completed', updated_at = now()
  WHERE is_demo = true AND id::text LIKE 'c0000000-%' AND deleted_at IS NULL
    AND status <> 'completed';
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;

-- ---------- B2. 18 more completed history outings ----------
INSERT INTO activities
  (id, creator_id, sport_id, title, description, level, level_max,
   max_participants, location_meeting, meeting_name,
   location_objective, objective_name,
   starts_at, duration, visibility, requires_presence, status,
   distance_km, elevation_gain_m, is_demo)
VALUES
  ('c0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000002',
   (SELECT id FROM sports WHERE key = 'hiking'),
   'Lac de l''Eychauda', 'Montée régulière depuis Chambran, lac encore gelé par endroits.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.486, 44.962), 4326)::geography, 'Chambran',
   ST_SetSRID(ST_MakePoint(6.47, 44.985), 4326)::geography, 'Lac de l''Eychauda',
   now() - INTERVAL '300 days', INTERVAL '6 hours', 'public', true, 'completed', 12.0, 850, true),
  ('c0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-000000000002',
   (SELECT id FROM sports WHERE key = 'hiking'),
   'Col de l''Izoard par la Casse Déserte', 'Boucle depuis Arvieux, passage dans la Casse Déserte.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.74, 44.77), 4326)::geography, 'Arvieux',
   ST_SetSRID(ST_MakePoint(6.735, 44.82), 4326)::geography, 'Col de l''Izoard',
   now() - INTERVAL '250 days', INTERVAL '5 hours', 'public', true, 'completed', 14.0, 700, true),
  ('c0000000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-000000000002',
   (SELECT id FROM sports WHERE key = 'trail-running'),
   'Tour du Mont Chaberton', 'Grosse sortie, 1600 m de D+, rythme soutenu.',
   'avancé', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.76, 44.95), 4326)::geography, 'Montgenèvre',
   ST_SetSRID(ST_MakePoint(6.75, 44.962), 4326)::geography, 'Mont Chaberton',
   now() - INTERVAL '120 days', INTERVAL '4 hours', 'public', true, 'completed', 22.0, 1600, true),
  ('c0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000003',
   (SELECT id FROM sports WHERE key = 'climbing-sport'),
   'Grimpe à Freissinières', 'Voies longues et bien équipées, du 6a au 7b.',
   'avancé', NULL, 5,
   ST_SetSRID(ST_MakePoint(6.54, 44.75), 4326)::geography, 'Freissinières',
   ST_SetSRID(ST_MakePoint(6.52, 44.745), 4326)::geography, 'Falaise de Freissinières',
   now() - INTERVAL '280 days', INTERVAL '5 hours', 'public', true, 'completed', NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-000000000003',
   (SELECT id FROM sports WHERE key = 'climbing-sport'),
   'Couennes à Ailefroide', 'Journée à Ailefroide, secteur Fissure d''Ailefroide.',
   'avancé', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.43, 44.89), 4326)::geography, 'Ailefroide',
   ST_SetSRID(ST_MakePoint(6.425, 44.885), 4326)::geography, 'Secteur Fissure d''Ailefroide',
   now() - INTERVAL '200 days', INTERVAL '5 hours', 'public', true, 'completed', NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000003',
   (SELECT id FROM sports WHERE key = 'climbing-sport'),
   'Soirée grimpe à Rocher Baron', 'Après-boulot, dalle et dévers, on finit à la frontale.',
   'avancé', NULL, 5,
   ST_SetSRID(ST_MakePoint(6.629, 44.876), 4326)::geography, 'Villar-Saint-Pancrace',
   ST_SetSRID(ST_MakePoint(6.589, 44.845), 4326)::geography, 'Rocher Baron',
   now() - INTERVAL '90 days', INTERVAL '4 hours', 'public', true, 'completed', NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000003',
   (SELECT id FROM sports WHERE key = 'bouldering'),
   'Blocs du Bois de l''Ours', 'Session blocs, crash pads en commun.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.635, 44.895), 4326)::geography, 'Briançon gare',
   ST_SetSRID(ST_MakePoint(6.65, 44.905), 4326)::geography, 'Bois de l''Ours',
   now() - INTERVAL '60 days', INTERVAL '3 hours', 'public', true, 'completed', NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-000000000004',
   (SELECT id FROM sports WHERE key = 'climbing-multipitch'),
   'Grande voie à la Tête d''Aval', 'Voie de 250 m en 6a max, descente en rappel.',
   'avancé', NULL, 4,
   ST_SetSRID(ST_MakePoint(6.448, 44.835), 4326)::geography, 'Vallouise',
   ST_SetSRID(ST_MakePoint(6.47, 44.845), 4326)::geography, 'Tête d''Aval de Montbrison',
   now() - INTERVAL '150 days', INTERVAL '8 hours', 'public', true, 'completed', NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-000000000004',
   (SELECT id FROM sports WHERE key = 'mountaineering'),
   'Pelvoux par le couloir Coolidge', 'Course de neige, départ 3 h du refuge.',
   'avancé', NULL, 4,
   ST_SetSRID(ST_MakePoint(6.43, 44.89), 4326)::geography, 'Ailefroide',
   ST_SetSRID(ST_MakePoint(6.35, 44.9), 4326)::geography, 'Mont Pelvoux',
   now() - INTERVAL '170 days', INTERVAL '10 hours', 'public', true, 'completed', 11.0, 1900, true),
  ('c0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-000000000005',
   (SELECT id FROM sports WHERE key = 'paragliding'),
   'Vol du matin depuis le Prorel', 'Décollage à 9 h, conditions calmes, atterrissage à la gare.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.587, 44.902), 4326)::geography, 'Décollage du Prorel',
   ST_SetSRID(ST_MakePoint(6.635, 44.895), 4326)::geography, 'Atterrissage de Briançon',
   now() - INTERVAL '110 days', INTERVAL '4 hours', 'public', true, 'completed', NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-000000000006',
   (SELECT id FROM sports WHERE key = 'ski-touring'),
   'Crête de Dormillouse', 'Neige froide, montée régulière, descente plein nord.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.47, 44.726), 4326)::geography, 'Dormillouse',
   ST_SetSRID(ST_MakePoint(6.5, 44.74), 4326)::geography, 'Crête de Dormillouse',
   now() - INTERVAL '230 days', INTERVAL '5 hours', 'public', true, 'completed', 9.0, 1000, true),
  ('c0000000-0000-4000-a000-000000000020', 'd0000000-0000-4000-a000-000000000006',
   (SELECT id FROM sports WHERE key = 'ski-touring'),
   'Pic de Rochebrune', 'Longue montée, couloir sommital à 40°, crampons utiles.',
   'avancé', NULL, 4,
   ST_SetSRID(ST_MakePoint(6.76, 44.775), 4326)::geography, 'Brunissard',
   ST_SetSRID(ST_MakePoint(6.77, 44.79), 4326)::geography, 'Pic de Rochebrune',
   now() - INTERVAL '210 days', INTERVAL '7 hours', 'public', true, 'completed', 13.0, 1500, true),
  ('c0000000-0000-4000-a000-000000000021', 'd0000000-0000-4000-a000-000000000007',
   (SELECT id FROM sports WHERE key = 'mtb-enduro'),
   'Enduro à Montgenèvre', 'Trois descentes, remontée en navette.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.726, 44.932), 4326)::geography, 'Montgenèvre',
   ST_SetSRID(ST_MakePoint(6.735, 44.96), 4326)::geography, 'Sommet des Gondrans',
   now() - INTERVAL '80 days', INTERVAL '4 hours', 'public', true, 'completed', 25.0, 400, true),
  ('c0000000-0000-4000-a000-000000000022', 'd0000000-0000-4000-a000-000000000007',
   (SELECT id FROM sports WHERE key = 'gravel'),
   'Gravel autour du lac de Serre-Ponçon', 'Pistes et petites routes, 70 km, pause baignade.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.495, 44.564), 4326)::geography, 'Embrun',
   ST_SetSRID(ST_MakePoint(6.42, 44.52), 4326)::geography, 'Savines-le-Lac',
   now() - INTERVAL '45 days', INTERVAL '5 hours', 'public', true, 'completed', 70.0, 900, true),
  ('c0000000-0000-4000-a000-000000000023', 'd0000000-0000-4000-a000-000000000008',
   (SELECT id FROM sports WHERE key = 'trail-running'),
   'Sortie longue au Granon', 'Montée tranquille, on discute, descente sur les singles.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.61, 44.945), 4326)::geography, 'Col du Granon',
   ST_SetSRID(ST_MakePoint(6.63, 44.96), 4326)::geography, 'Pic du Lauzin',
   now() - INTERVAL '70 days', INTERVAL '3 hours', 'public', true, 'completed', 16.0, 900, true),
  ('c0000000-0000-4000-a000-000000000024', 'd0000000-0000-4000-a000-000000000009',
   (SELECT id FROM sports WHERE key = 'windsurfing'),
   'Planche à voile au plan d''eau', 'Vent thermique l''après-midi, matos de location possible.',
   'débutant', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.489, 44.558), 4326)::geography, 'Plan d''eau d''Embrun',
   ST_SetSRID(ST_MakePoint(6.48, 44.555), 4326)::geography, 'Plan d''eau d''Embrun',
   now() - INTERVAL '50 days', INTERVAL '4 hours', 'public', true, 'completed', NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000025', 'd0000000-0000-4000-a000-000000000007',
   (SELECT id FROM sports WHERE key = 'mtb-enduro'),
   'Enduro aux Orres', 'Pistes du bike park puis singles naturels, protections conseillées.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.553, 44.508), 4326)::geography, 'Les Orres 1650',
   ST_SetSRID(ST_MakePoint(6.58, 44.495), 4326)::geography, 'Sommet du Bois Méan',
   now() - INTERVAL '140 days', INTERVAL '5 hours', 'public', true, 'completed', 30.0, 500, true),
  ('c0000000-0000-4000-a000-000000000026', 'd0000000-0000-4000-a000-000000000007',
   (SELECT id FROM sports WHERE key = 'mtb-enduro'),
   'Enduro à Vars', 'Descentes engagées, bonne technique requise.',
   'avancé', NULL, 5,
   ST_SetSRID(ST_MakePoint(6.69, 44.58), 4326)::geography, 'Vars Sainte-Marie',
   ST_SetSRID(ST_MakePoint(6.7, 44.6), 4326)::geography, 'Crête de Chabrières',
   now() - INTERVAL '100 days', INTERVAL '5 hours', 'public', true, 'completed', 28.0, 600, true)
ON CONFLICT (id) DO NOTHING;

-- ---------- B3. Accepted participations (creators included) ----------
INSERT INTO participations (activity_id, user_id, status, created_at)
SELECT p.activity_id, p.user_id, 'accepted', a.starts_at - INTERVAL '6 days'
FROM (VALUES
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000001'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
  ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
  ('c0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000011'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000011'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000011'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000011'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000012'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000012'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000012'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000012'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000014'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000014'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000014'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000014'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000015'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000015'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000015'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000020'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000020'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000020'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
  ('c0000000-0000-4000-a000-000000000021'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000021'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000021'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000021'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
  ('c0000000-0000-4000-a000-000000000022'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000022'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000022'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000022'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000023'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000023'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000023'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000023'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-000000000024'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
  ('c0000000-0000-4000-a000-000000000024'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000024'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000024'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000025'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000025'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
  ('c0000000-0000-4000-a000-000000000025'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
  ('c0000000-0000-4000-a000-000000000026'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-000000000026'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-000000000026'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid)
) AS p(activity_id, user_id)
JOIN activities a ON a.id = p.activity_id
ON CONFLICT (user_id, activity_id) DO NOTHING;

-- ---------- B4. Late withdrawals (counted against reliability) ----------
INSERT INTO participations (activity_id, user_id, status, left_at, left_reason, created_at)
SELECT p.activity_id, p.user_id, 'withdrawn', a.starts_at - INTERVAL '3 hours', 'Empêchement de dernière minute', a.starts_at - INTERVAL '8 days'
FROM (VALUES
  ('c0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid)
) AS p(activity_id, user_id)
JOIN activities a ON a.id = p.activity_id
ON CONFLICT (user_id, activity_id) DO NOTHING;

-- ---------- C. Explicit presence on every history participation ----------
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations p
  SET confirmed_present = true
  FROM activities a
  WHERE a.id = p.activity_id AND a.is_demo = true AND a.id::text LIKE 'c0000000-%'
    AND p.status = 'accepted';
  UPDATE participations p
  SET confirmed_present = false
  FROM (VALUES
    ('c0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('c0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('c0000000-0000-4000-a000-000000000023'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('c0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('c0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
    ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('c0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('c0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('c0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('c0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('c0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('c0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('c0000000-0000-4000-a000-000000000022'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('c0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('c0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('c0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('c0000000-0000-4000-a000-000000000014'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('c0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('c0000000-0000-4000-a000-000000000021'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid)
  ) AS x(activity_id, user_id)
  WHERE p.activity_id = x.activity_id AND p.user_id = x.user_id AND p.status = 'accepted';
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;

-- ---------- D. Counted peer votes: traits + level_right ----------
INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, counted_at, created_at)
SELECT v.voter, v.voted, v.activity, v.badge, a.starts_at + a.duration + INTERVAL '26 hours', a.starts_at + a.duration + INTERVAL '5 hours'
FROM (VALUES
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000004'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000004'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000004'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000013'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000013'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000013'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000008'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000008'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000008'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000017'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000017'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000006'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000006'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000006'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000009'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000009'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000009'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000021'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000021'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000022'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000025'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000025'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000026'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000026'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000023'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000023'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000011'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000011'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000011'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid, 'c0000000-0000-4000-a000-000000000024'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid, 'c0000000-0000-4000-a000-000000000024'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid, 'c0000000-0000-4000-a000-000000000024'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid, 'c0000000-0000-4000-a000-000000000006'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid, 'c0000000-0000-4000-a000-000000000006'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid, 'c0000000-0000-4000-a000-000000000009'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid, 'c0000000-0000-4000-a000-000000000009'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid, 'c0000000-0000-4000-a000-000000000009'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid, 'c0000000-0000-4000-a000-000000000009'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid, 'c0000000-0000-4000-a000-000000000011'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid, 'c0000000-0000-4000-a000-000000000011'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid, 'c0000000-0000-4000-a000-000000000012'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid, 'c0000000-0000-4000-a000-000000000012'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid, 'c0000000-0000-4000-a000-000000000012'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid, 'c0000000-0000-4000-a000-000000000013'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid, 'c0000000-0000-4000-a000-000000000013'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid, 'c0000000-0000-4000-a000-000000000019'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid, 'c0000000-0000-4000-a000-000000000019'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid, 'c0000000-0000-4000-a000-000000000019'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid, 'c0000000-0000-4000-a000-000000000020'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000004'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid, 'c0000000-0000-4000-a000-000000000020'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000013'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000013'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid, 'c0000000-0000-4000-a000-000000000013'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000018'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid, 'c0000000-0000-4000-a000-000000000018'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000021'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000021'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000025'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid, 'c0000000-0000-4000-a000-000000000025'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000023'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000023'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000011'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000003'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000011'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid, 'c0000000-0000-4000-a000-000000000011'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid, 'c0000000-0000-4000-a000-000000000024'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid, 'c0000000-0000-4000-a000-000000000024'::uuid, 'level_right'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid, 'c0000000-0000-4000-a000-000000000024'::uuid, 'level_right')
) AS v(voter, voted, activity, badge)
JOIN activities a ON a.id = v.activity
ON CONFLICT (voter_id, voted_id, activity_id, badge_key) DO NOTHING;

-- ---------- E. Reliability derived from the data above ----------
DO $$
DECLARE
  v_u RECORD;
BEGIN
  FOR v_u IN
    SELECT id, display_name FROM users
    WHERE is_demo = true AND id::text LIKE 'd0000000-%' AND id <> 'd0000000-0000-4000-a000-000000000001'
  LOOP
    PERFORM recalculate_reliability_score(v_u.id);
  END LOOP;
  FOR v_u IN
    SELECT display_name, reliability_score FROM users
    WHERE is_demo = true AND id::text LIKE 'd0000000-%' ORDER BY display_name
  LOOP
    RAISE NOTICE 'demo reliability % = %', v_u.display_name, v_u.reliability_score;
  END LOOP;
END $$;
