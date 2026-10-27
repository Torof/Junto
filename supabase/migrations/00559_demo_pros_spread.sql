-- ============================================================================
-- 00559 — Les sorties pro démo de 00558 partageaient des points exacts (sept
-- au décollage de Chabre, trois à Ailefroide…) : sur la carte elles ne
-- formaient qu'un cluster insécable (Scott 2026-10-27). Chaque sortie prend
-- un lieu propre et plausible : décollages sud / nord, pente-école,
-- atterrissage, secteurs de falaise, accès au Glacier Blanc. Règle pour la
-- suite : jamais deux objets démo au même point.
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE public.pro_offerings o
  SET location = extensions.ST_SetSRID(extensions.ST_MakePoint(s.lng, s.lat), 4326)::extensions.geography,
      location_name = s.name
  FROM (VALUES
    -- Lise (Ailefroide) : le village reste à la page ; les sorties sur leurs secteurs
    ('b0000000-0000-4000-a000-000000000005'::uuid, 6.4320, 44.8842, 'Dalles-écoles d''Ailefroide'),
    ('b0000000-0000-4000-a000-000000000006'::uuid, 6.4280, 44.8905, 'Tête de la Draye (Ailefroide)'),
    ('b0000000-0000-4000-a000-000000000007'::uuid, 6.4395, 44.8880, 'Secteur de la Fissure (Ailefroide)'),
    -- Théo (Chabre)
    ('b0000000-0000-4000-a000-00000000000a'::uuid, 5.8115, 44.3372, 'Décollage nord de Chabre'),
    ('b0000000-0000-4000-a000-00000000000c'::uuid, 5.8270, 44.3205, 'Atterrissage de Laragne'),
    -- Les Ailes du Buëch (Chabre, autres points)
    ('b0000000-0000-4000-a000-00000000000d'::uuid, 5.7980, 44.3315, 'Décollage sud de Chabre (école)'),
    ('b0000000-0000-4000-a000-00000000000e'::uuid, 5.8135, 44.3385, 'Décollage nord de Chabre'),
    ('b0000000-0000-4000-a000-00000000000f'::uuid, 5.8255, 44.3230, 'Atterrissage de Laragne'),
    ('b0000000-0000-4000-a000-000000000010'::uuid, 5.8300, 44.3400, 'Crête de Chabre'),
    -- Nicolas : l'initiation glacier part du sentier du Glacier Blanc
    ('b0000000-0000-4000-a000-000000000012'::uuid, 6.4080, 44.9290, 'Sentier du Glacier Blanc (Pelvoux)'),
    -- Marion : le trail part des hauts de Guillestre, pas du bureau
    ('b0000000-0000-4000-a000-000000000017'::uuid, 6.6560, 44.6660, 'Hauts de Guillestre')
  ) AS s(id, lng, lat, name)
  WHERE o.id = s.id AND o.is_demo;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;
