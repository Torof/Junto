-- 00282 — taxonomy v2.1: "à pied" universe + canyoning to water
--
-- Two recategorisations decided with Scott (2026-07-01), refining the v2
-- universes (migration 00281):
--
--   1. Foot-locomotion sports get their own universe. hiking + trekking were
--      in 'mountain' and running + trail-running in 'running'; that split the
--      same trails/people across two universes. They now share one 'on-foot'
--      category ("À pied"). 'mountain' becomes technical-alpine (climbing,
--      mountaineering, ski-touring, snowshoeing, caving). Snowshoeing stays in
--      'mountain' on purpose — it's a winter/alpine outing, not casual walking.
--
--   2. canyoning moves mountain -> water. It's a wetsuit/jumps/swims aquatic
--      sport; the old canyon+caving grouping split (caving is dry/underground
--      and stays in 'mountain').
--
-- sports.category is free text (no CHECK), so this is pure data movement. No
-- function or view branches on category — it's only a grouping/accent label,
-- so nothing else needs touching server-side. Pro pushpin pin_icon is
-- region-derived (not sport-category), so its 4-value CHECK is unaffected.

UPDATE sports SET category = 'on-foot'
  WHERE key IN ('hiking', 'trekking', 'trail-running', 'running');

UPDATE sports SET category = 'water'
  WHERE key = 'canyoning';
