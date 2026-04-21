-- Migration 00086: add canyoning-specific ropes + tag existing ropes

-- Add canyoning ropes (semi-static, different from climbing)
INSERT INTO gear_catalog (name_key, sport_keys, display_order) VALUES
  ('Corde 30m (canyon)', ARRAY['canyoning'], 16),
  ('Corde 60m (canyon)', ARRAY['canyoning'], 17),
  ('Corde 80m (canyon)', ARRAY['canyoning'], 18);
