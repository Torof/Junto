-- ============================================================================
-- 00414 — Three new sports (Scott 2026-09-11): football, planche à voile,
-- wakeboard — outdoor group sports requested for launch coverage.
-- Categories: football → on-foot; windsurfing + wakeboard → water.
-- Level scales fall back to the generic tier client-side; no gear presets.
-- ============================================================================
INSERT INTO sports (key, icon, category, display_order, is_active) VALUES
  ('football',    'football',    'on-foot', 42, true),
  ('windsurfing', 'windsurfing', 'water',   43, true),
  ('wakeboard',   'wakeboard',   'water',   44, true)
ON CONFLICT (key) DO NOTHING;
