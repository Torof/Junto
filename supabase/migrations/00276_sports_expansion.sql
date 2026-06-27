-- ============================================================================
-- Sports expansion (see docs/SPORTS_PLAN.md).
-- Splits climbing → couenne/grande voie/bloc, mountain-biking → XC/enduro/DH,
-- adds ~16 outdoor + coastal sports, re-points & removes the two generic keys,
-- and extends gear_catalog. Level scales / icons / i18n live in the client.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. New sports
-- ---------------------------------------------------------------------------
INSERT INTO sports (key, icon, category, display_order) VALUES
  ('climbing-sport',      'climbing-sport',      'mountain', 20),
  ('climbing-multipitch', 'climbing-multipitch', 'mountain', 21),
  ('bouldering',          'bouldering',          'mountain', 22),
  ('dry-tooling',         'dry-tooling',         'mountain', 23),
  ('caving',              'caving',              'outdoor',  24),
  ('nordic-walking',      'nordic-walking',      'outdoor',  25),
  ('snowshoeing',         'snowshoeing',         'mountain', 26),
  ('ski-freeride',        'ski-freeride',        'mountain', 27),
  ('splitboard',          'splitboard',          'mountain', 28),
  ('mtb-xc',              'mtb-xc',              'mountain', 29),
  ('mtb-enduro',          'mtb-enduro',          'mountain', 30),
  ('mtb-downhill',        'mtb-downhill',        'mountain', 31),
  ('gravel',              'gravel',              'road',     32),
  ('speed-riding',        'speed-riding',        'air',      33),
  ('hang-gliding',        'hang-gliding',        'air',      34),
  ('freediving',          'freediving',          'water',    35),
  ('highlining',          'highlining',          'outdoor',  36),
  ('kitesurf',            'kitesurf',            'water',    37),
  ('windsurf',            'windsurf',            'water',    38),
  ('wakeboard',           'wakeboard',           'water',    39);

-- ---------------------------------------------------------------------------
-- 2. Re-point existing data off the generic keys, then remove them
--    (sport_id is ON DELETE RESTRICT, so the UPDATEs must come first).
--    climbing → climbing-sport (Couenne), mountain-biking → mtb-xc.
-- ---------------------------------------------------------------------------
UPDATE activities      SET sport_id = (SELECT id FROM sports WHERE key = 'climbing-sport')
  WHERE sport_id = (SELECT id FROM sports WHERE key = 'climbing');
UPDATE pro_offerings   SET sport_id = (SELECT id FROM sports WHERE key = 'climbing-sport')
  WHERE sport_id = (SELECT id FROM sports WHERE key = 'climbing');

UPDATE activities      SET sport_id = (SELECT id FROM sports WHERE key = 'mtb-xc')
  WHERE sport_id = (SELECT id FROM sports WHERE key = 'mountain-biking');
UPDATE pro_offerings   SET sport_id = (SELECT id FROM sports WHERE key = 'mtb-xc')
  WHERE sport_id = (SELECT id FROM sports WHERE key = 'mountain-biking');

DELETE FROM sports WHERE key IN ('climbing', 'mountain-biking');

-- ---------------------------------------------------------------------------
-- 3. Gear catalog
-- ---------------------------------------------------------------------------
-- 3a. Re-tag the generic-key gear onto the splits.
UPDATE gear_catalog
  SET sport_keys = array_remove(sport_keys, 'climbing') || ARRAY['climbing-sport', 'climbing-multipitch']
  WHERE 'climbing' = ANY(sport_keys);
UPDATE gear_catalog
  SET sport_keys = array_remove(sport_keys, 'mountain-biking') || ARRAY['mtb-xc', 'mtb-enduro', 'mtb-downhill']
  WHERE 'mountain-biking' = ANY(sport_keys);

-- 3b. Tag existing shared items onto new sports (append, no duplicate rows).
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'gravel')
  WHERE name_key IN ('Casque', 'Eau / Gourde') AND NOT ('gravel' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'climbing-multipitch')
  WHERE name_key IN ('Trousse de secours', 'Lampe frontale') AND NOT ('climbing-multipitch' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'snowshoeing')
  WHERE name_key IN ('Bâtons', 'Guêtres', 'DVA', 'Pelle', 'Sonde', 'Trousse de secours', 'Lampe frontale', 'Eau / Gourde') AND NOT ('snowshoeing' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'ski-freeride')
  WHERE name_key IN ('Casque', 'DVA', 'Pelle', 'Sonde') AND NOT ('ski-freeride' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'splitboard')
  WHERE name_key IN ('Casque', 'DVA', 'Pelle', 'Sonde', 'Peaux de phoque') AND NOT ('splitboard' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'dry-tooling')
  WHERE name_key IN ('Corde 60m', 'Baudrier', 'Casque', 'Assureur', 'Mousquetons', 'Dégaines', 'Crampons') AND NOT ('dry-tooling' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'speed-riding')
  WHERE name_key IN ('Casque', 'Radio') AND NOT ('speed-riding' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'hang-gliding')
  WHERE name_key IN ('Casque', 'Secours', 'Variomètre', 'Radio') AND NOT ('hang-gliding' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'freediving')
  WHERE name_key IN ('Combinaison néoprène', 'Bouée') AND NOT ('freediving' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'highlining')
  WHERE name_key IN ('Baudrier', 'Mousquetons', 'Sangles', 'Longe', 'Casque') AND NOT ('highlining' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'caving')
  WHERE name_key IN ('Casque', 'Baudrier', 'Descendeur', 'Mousquetons', 'Combinaison néoprène', 'Trousse de secours', 'Lampe frontale') AND NOT ('caving' = ANY(sport_keys));

-- 3c. New gear items.
INSERT INTO gear_catalog (name_key, sport_keys, display_order) VALUES
  -- Diving — fill the big gap
  ('Bouteille de plongée',  ARRAY['diving'], 40),
  ('Détendeur',             ARRAY['diving'], 41),
  ('Gilet stabilisateur',   ARRAY['diving'], 42),
  ('Masque',                ARRAY['diving', 'freediving'], 43),
  ('Palmes',                ARRAY['diving', 'freediving'], 44),
  ('Ordinateur de plongée', ARRAY['diving', 'freediving'], 45),
  -- Bike (all disciplines) + gravel
  ('Gants',                 ARRAY['mtb-xc', 'mtb-enduro', 'mtb-downhill', 'gravel', 'cycling'], 46),
  ('Chambre à air',         ARRAY['mtb-xc', 'mtb-enduro', 'mtb-downhill', 'gravel', 'cycling'], 47),
  ('Kit de réparation',     ARRAY['mtb-xc', 'mtb-enduro', 'mtb-downhill', 'gravel', 'cycling'], 48),
  ('Pompe',                 ARRAY['mtb-xc', 'mtb-enduro', 'mtb-downhill', 'gravel', 'cycling'], 49),
  ('Protections (genoux/coudes)', ARRAY['mtb-enduro', 'mtb-downhill'], 50),
  ('Casque intégral',       ARRAY['mtb-downhill'], 51),
  -- Bouldering
  ('Crashpad',              ARRAY['bouldering'], 52),
  ('Brosse',                ARRAY['bouldering'], 53),
  -- Grande voie extras
  ('Coinceurs / Friends',   ARRAY['climbing-multipitch', 'mountaineering'], 54),
  ('Topo',                  ARRAY['climbing-multipitch', 'caving'], 55),
  -- Dry-tooling
  ('Piolets dry-tooling',   ARRAY['dry-tooling'], 56),
  -- Snowshoeing
  ('Raquettes',             ARRAY['snowshoeing'], 57),
  -- Ski freeride / splitboard
  ('Airbag',                ARRAY['ski-freeride', 'splitboard', 'ski-touring'], 58),
  -- Speed-riding / hang-gliding
  ('Aile',                  ARRAY['speed-riding', 'hang-gliding'], 59),
  ('Sellette / harnais',    ARRAY['speed-riding', 'hang-gliding'], 60),
  -- Freediving
  ('Plomb',                 ARRAY['freediving'], 61),
  -- Highline
  ('Sangle highline',       ARRAY['highlining'], 62),
  ('Backup / longe',        ARRAY['highlining', 'slacklining'], 63),
  -- Caving
  ('Descendeur / croll',    ARRAY['caving'], 64),
  -- Cross-country ski
  ('Skis de fond',          ARRAY['cross-country-ski'], 65),
  ('Bâtons',                ARRAY['cross-country-ski', 'nordic-walking', 'ski-touring', 'snowshoeing'], 66),
  -- Water (kite/wind/wake)
  ('Combinaison',           ARRAY['kitesurf', 'windsurf', 'wakeboard'], 67),
  ('Gilet de sauvetage',    ARRAY['kitesurf', 'windsurf', 'wakeboard'], 68)
ON CONFLICT (name_key) DO UPDATE
  SET sport_keys = (
    SELECT ARRAY(SELECT DISTINCT unnest(gear_catalog.sport_keys || EXCLUDED.sport_keys))
  );
