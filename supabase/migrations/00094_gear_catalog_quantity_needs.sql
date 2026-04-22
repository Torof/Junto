-- Migration 00094: per-person vs shared quantity needs for gear_catalog
-- Lets the client compute "required qty" for each item based on participant
-- count (per-person items) or a fixed shared recommendation (shared items).
-- Example: 4 participants = 4 helmets but only 1 rope.

ALTER TABLE gear_catalog
  ADD COLUMN per_person BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN shared_recommended_qty INTEGER;

-- Per-person items: 1 per participant (helmet, harness, wetsuit, etc.)
-- These stay with default per_person = true, shared_recommended_qty = NULL.
-- Listed here for clarity but no UPDATE needed for them.
-- Casque, Baudrier, Combinaison néoprène, DVA, Chaussons escalade, Crampons,
-- Gilet de sauvetage, Lampe frontale, Eau / Gourde, Sellette, Voile,
-- Peaux de phoque, Magnésie, Piolet, Planche, Pagaie

-- Shared items: 1 for the whole group
UPDATE gear_catalog SET per_person = false, shared_recommended_qty = 1
  WHERE name_key IN (
    'Corde 30m (canyon)', 'Corde 60m (canyon)', 'Corde 80m (canyon)',
    'Corde 60m', 'Corde 70m',
    'Descendeur', 'Assureur',
    'Carte / GPS', 'Pelle', 'Sonde',
    'Bidon étanche', 'Radio', 'Variomètre', 'Secours',
    'Trousse de secours'
  );

-- Shared items with a specific recommended count
UPDATE gear_catalog SET per_person = false, shared_recommended_qty = 15
  WHERE name_key = 'Mousquetons';

UPDATE gear_catalog SET per_person = false, shared_recommended_qty = 6
  WHERE name_key = 'Dégaines';

UPDATE gear_catalog SET per_person = false, shared_recommended_qty = 3
  WHERE name_key IN ('Sangles', 'Broches à glace');

-- Integrity: shared_recommended_qty must be set iff per_person = false.
ALTER TABLE gear_catalog
  ADD CONSTRAINT gear_catalog_qty_logic_check CHECK (
    (per_person = true AND shared_recommended_qty IS NULL)
    OR
    (per_person = false AND shared_recommended_qty IS NOT NULL AND shared_recommended_qty > 0)
  );
