-- ============================================================================
-- 00375 — Discovery (axe D) B1: the `discovery_availabilities` table ("dispos").
--
-- A dispo = one user's intent to do a sport, in a time window, around a chosen
-- place, reachable by ≥1 transport mode. v1: one row per user (editable), the
-- partial-unique index enforces one ACTIVE at a time (v2 presets → many inactive).
-- All writes go through SECURITY DEFINER functions (00376); clients get only
-- own-row SELECT (others' dispos surface via the curated get_discovery_cards).
-- Matching (sport ∩ · zone overlap ST_Distance < r_a+r_b · window overlap) lives
-- in the read functions, not here.
-- ============================================================================

CREATE TABLE discovery_availabilities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sport_keys TEXT[] NOT NULL CHECK (array_length(sport_keys, 1) BETWEEN 1 AND 3),
  levels JSONB,                       -- optional per-sport grade { "climbing-sport": "6a" }
  base GEOGRAPHY(POINT, 4326) NOT NULL,   -- chosen place (geocoded / map pin), NOT the GPS
  base_label TEXT NOT NULL CHECK (char_length(base_label) BETWEEN 1 AND 120),
  radius_km INTEGER CHECK (radius_km IS NULL OR radius_km IN (5, 10, 15, 30, 50)),  -- NULL = "peu importe"
  transport_modes TEXT[] NOT NULL CHECK (
    array_length(transport_modes, 1) BETWEEN 1 AND 5
    AND transport_modes <@ ARRAY['car', 'motorbike', 'bike', 'on_foot', 'public_transport']
  ),
  window_start TIMESTAMPTZ NOT NULL,
  window_end TIMESTAMPTZ NOT NULL CHECK (window_end > window_start),
  is_active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One ACTIVE dispo per user (v1: one row total; v2 presets: many inactive + 1 active).
CREATE UNIQUE INDEX discovery_one_active_per_user ON discovery_availabilities (user_id) WHERE is_active;
-- Matching scans active dispos by geography.
CREATE INDEX discovery_active_base_gix ON discovery_availabilities USING GIST (base) WHERE is_active;

ALTER TABLE discovery_availabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE discovery_availabilities FORCE ROW LEVEL SECURITY;

-- Own row only; every other read is via the curated get_discovery_* functions.
CREATE POLICY discovery_select_own ON discovery_availabilities
  FOR SELECT USING (user_id = auth.uid());
-- No client INSERT/UPDATE/DELETE — functions only.

-- Whitelist trigger — freeze identity/lifecycle columns on UPDATE (is_active is
-- flipped only via activate/deactivate_dispo, which set bypass_lock).
CREATE OR REPLACE FUNCTION discovery_availabilities_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.user_id := OLD.user_id;
  NEW.is_active := OLD.is_active;
  NEW.created_at := OLD.created_at;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER discovery_lock_privileged
  BEFORE UPDATE ON discovery_availabilities
  FOR EACH ROW EXECUTE FUNCTION discovery_availabilities_whitelist_columns();

REVOKE ALL ON discovery_availabilities FROM anon;
GRANT SELECT ON discovery_availabilities TO authenticated;
