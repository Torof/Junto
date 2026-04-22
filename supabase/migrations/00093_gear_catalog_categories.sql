-- Migration 00093: gear catalog categories for V2 visual grouping
-- Adds category_key to cluster items. Category labels and colors live
-- client-side (constant mapping) to keep the schema lean.

ALTER TABLE gear_catalog ADD COLUMN category_key TEXT NOT NULL DEFAULT 'personal'
  CHECK (category_key IN ('safety', 'technical', 'water', 'personal'));

-- Seed existing items
UPDATE gear_catalog SET category_key = 'safety' WHERE name_key IN (
  'Casque', 'Baudrier', 'DVA', 'Pelle', 'Sonde', 'Trousse de secours',
  'Gilet de sauvetage', 'Secours'
);
UPDATE gear_catalog SET category_key = 'technical' WHERE name_key IN (
  'Corde 60m', 'Corde 70m', 'Dégaines', 'Assureur', 'Mousquetons', 'Sangles',
  'Descendeur', 'Crampons', 'Piolet', 'Broches à glace', 'Voile', 'Sellette',
  'Variomètre', 'Corde 30m (canyon)', 'Corde 60m (canyon)', 'Corde 80m (canyon)'
);
UPDATE gear_catalog SET category_key = 'water' WHERE name_key IN (
  'Combinaison néoprène', 'Pagaie', 'Planche', 'Bidon étanche'
);
-- 'personal' default covers: Lampe frontale, Carte / GPS, Eau / Gourde,
-- Chaussons escalade, Magnésie, Peaux de phoque, Radio

CREATE INDEX idx_gear_catalog_category_key ON gear_catalog(category_key);
