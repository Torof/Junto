-- Migration 00038: Add 18 new sports + reorder all alphabetically

-- Add new sports (ON CONFLICT skip if already exists)
INSERT INTO sports (key, icon, category, display_order) VALUES
  ('badminton',         'badminton',         'ball',      0),
  ('canyoning',         'canyoning',         'water',     0),
  ('cross-country-ski', 'cross-country-ski', 'mountain',  0),
  ('crossfit',          'crossfit',          'endurance', 0),
  ('diving',            'diving',            'water',     0),
  ('football',          'football',          'ball',      0),
  ('horseback-riding',  'horseback-riding',  'outdoor',   0),
  ('ice-climbing',      'ice-climbing',      'mountain',  0),
  ('rafting',           'rafting',           'water',     0),
  ('rock-fishing',      'rock-fishing',      'water',     0),
  ('skateboarding',     'skateboarding',     'urban',     0),
  ('skydiving',         'skydiving',         'air',       0),
  ('slacklining',       'slacklining',       'outdoor',   0),
  ('stand-up-paddle',   'stand-up-paddle',   'water',     0),
  ('tennis',            'tennis',            'ball',      0),
  ('triathlon',         'triathlon',         'endurance', 0),
  ('via-ferrata',       'via-ferrata',       'mountain',  0),
  ('volleyball',        'volleyball',        'ball',      0)
ON CONFLICT (key) DO NOTHING;

-- Reorder ALL 33 sports alphabetically
UPDATE sports SET display_order = 1  WHERE key = 'badminton';
UPDATE sports SET display_order = 2  WHERE key = 'canyoning';
UPDATE sports SET display_order = 3  WHERE key = 'climbing';
UPDATE sports SET display_order = 4  WHERE key = 'cross-country-ski';
UPDATE sports SET display_order = 5  WHERE key = 'crossfit';
UPDATE sports SET display_order = 6  WHERE key = 'cycling';
UPDATE sports SET display_order = 7  WHERE key = 'diving';
UPDATE sports SET display_order = 8  WHERE key = 'football';
UPDATE sports SET display_order = 9  WHERE key = 'hiking';
UPDATE sports SET display_order = 10 WHERE key = 'horseback-riding';
UPDATE sports SET display_order = 11 WHERE key = 'ice-climbing';
UPDATE sports SET display_order = 12 WHERE key = 'kayaking';
UPDATE sports SET display_order = 13 WHERE key = 'mountain-biking';
UPDATE sports SET display_order = 14 WHERE key = 'mountaineering';
UPDATE sports SET display_order = 15 WHERE key = 'paragliding';
UPDATE sports SET display_order = 16 WHERE key = 'rafting';
UPDATE sports SET display_order = 17 WHERE key = 'rock-fishing';
UPDATE sports SET display_order = 18 WHERE key = 'running';
UPDATE sports SET display_order = 19 WHERE key = 'sailing';
UPDATE sports SET display_order = 20 WHERE key = 'skateboarding';
UPDATE sports SET display_order = 21 WHERE key = 'ski-touring';
UPDATE sports SET display_order = 22 WHERE key = 'skiing';
UPDATE sports SET display_order = 23 WHERE key = 'skydiving';
UPDATE sports SET display_order = 24 WHERE key = 'slacklining';
UPDATE sports SET display_order = 25 WHERE key = 'snowboarding';
UPDATE sports SET display_order = 26 WHERE key = 'stand-up-paddle';
UPDATE sports SET display_order = 27 WHERE key = 'surfing';
UPDATE sports SET display_order = 28 WHERE key = 'swimming';
UPDATE sports SET display_order = 29 WHERE key = 'tennis';
UPDATE sports SET display_order = 30 WHERE key = 'trail-running';
UPDATE sports SET display_order = 31 WHERE key = 'triathlon';
UPDATE sports SET display_order = 32 WHERE key = 'via-ferrata';
UPDATE sports SET display_order = 33 WHERE key = 'volleyball';
