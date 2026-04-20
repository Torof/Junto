-- Migration 00084: gear catalog + per-activity gear declarations

-- Shared gear dictionary — items tagged by sport
CREATE TABLE gear_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_key TEXT NOT NULL UNIQUE,
  sport_keys TEXT[] NOT NULL DEFAULT '{}',
  display_order INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE gear_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE gear_catalog FORCE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read gear catalog"
  ON gear_catalog FOR SELECT USING (true);

GRANT SELECT ON gear_catalog TO anon, authenticated;

-- Per-activity gear declarations
CREATE TABLE activity_gear (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  gear_name TEXT NOT NULL CHECK (char_length(gear_name) BETWEEN 1 AND 100),
  quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 99),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (activity_id, user_id, gear_name)
);

ALTER TABLE activity_gear ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_gear FORCE ROW LEVEL SECURITY;

CREATE POLICY "Participants can read activity gear"
  ON activity_gear FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = activity_gear.activity_id
        AND user_id = auth.uid()
        AND status = 'accepted'
    )
    OR EXISTS (
      SELECT 1 FROM activities
      WHERE id = activity_gear.activity_id
        AND creator_id = auth.uid()
    )
  );

GRANT SELECT ON activity_gear TO authenticated;

-- ============================================================================
-- RPC: set gear for an activity (replaces all user's gear for that activity)
-- ============================================================================
CREATE OR REPLACE FUNCTION set_activity_gear(
  p_activity_id UUID,
  p_items JSONB -- array of {name: string, quantity: number}
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_item JSONB;
  v_name TEXT;
  v_qty INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Must be accepted participant
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Activity must be active
  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id AND status IN ('published', 'in_progress') AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Delete existing gear for this user+activity
  DELETE FROM activity_gear WHERE activity_id = p_activity_id AND user_id = v_user_id;

  -- Insert new items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_name := trim(v_item->>'name');
    v_qty := COALESCE((v_item->>'quantity')::integer, 1);

    IF v_name IS NOT NULL AND char_length(v_name) > 0 AND v_qty > 0 THEN
      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity)
      VALUES (p_activity_id, v_user_id, v_name, LEAST(v_qty, 99));
    END IF;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION set_activity_gear FROM anon;
GRANT EXECUTE ON FUNCTION set_activity_gear TO authenticated;

-- ============================================================================
-- Seed gear catalog
-- ============================================================================
INSERT INTO gear_catalog (name_key, sport_keys, display_order) VALUES
  -- Climbing / Mountaineering
  ('Corde 60m', ARRAY['climbing', 'mountaineering', 'ice-climbing'], 1),
  ('Corde 70m', ARRAY['climbing', 'mountaineering', 'ice-climbing'], 2),
  ('Dégaines', ARRAY['climbing', 'mountaineering', 'via-ferrata'], 3),
  ('Baudrier', ARRAY['climbing', 'mountaineering', 'canyoning', 'via-ferrata', 'ice-climbing'], 4),
  ('Casque', ARRAY['climbing', 'mountaineering', 'canyoning', 'via-ferrata', 'ice-climbing', 'cycling', 'mountain-biking', 'kayaking', 'skiing', 'ski-touring'], 5),
  ('Assureur', ARRAY['climbing', 'mountaineering', 'ice-climbing'], 6),
  ('Mousquetons', ARRAY['climbing', 'mountaineering', 'canyoning', 'via-ferrata', 'ice-climbing'], 7),
  ('Sangles', ARRAY['climbing', 'mountaineering', 'canyoning', 'ice-climbing'], 8),
  ('Chaussons escalade', ARRAY['climbing'], 9),
  ('Magnésie', ARRAY['climbing'], 10),

  -- Mountaineering specific
  ('Crampons', ARRAY['mountaineering', 'ice-climbing', 'ski-touring'], 11),
  ('Piolet', ARRAY['mountaineering', 'ice-climbing'], 12),
  ('Broches à glace', ARRAY['ice-climbing', 'mountaineering'], 13),

  -- Canyoning
  ('Combinaison néoprène', ARRAY['canyoning', 'kayaking', 'surfing', 'diving'], 14),
  ('Descendeur', ARRAY['canyoning'], 15),
  ('Bidon étanche', ARRAY['canyoning', 'kayaking', 'rafting', 'stand-up-paddle'], 16),

  -- Paragliding
  ('Voile', ARRAY['paragliding'], 17),
  ('Sellette', ARRAY['paragliding'], 18),
  ('Secours', ARRAY['paragliding'], 19),
  ('Variomètre', ARRAY['paragliding'], 20),
  ('Radio', ARRAY['paragliding', 'mountaineering', 'ski-touring'], 21),

  -- Water sports
  ('Pagaie', ARRAY['kayaking', 'stand-up-paddle', 'rafting'], 22),
  ('Gilet de sauvetage', ARRAY['kayaking', 'rafting', 'sailing', 'stand-up-paddle'], 23),
  ('Planche', ARRAY['surfing', 'stand-up-paddle'], 24),

  -- Ski / Ski touring
  ('DVA', ARRAY['ski-touring', 'skiing'], 25),
  ('Pelle', ARRAY['ski-touring'], 26),
  ('Sonde', ARRAY['ski-touring'], 27),
  ('Peaux de phoque', ARRAY['ski-touring'], 28),

  -- General outdoor
  ('Trousse de secours', ARRAY['hiking', 'climbing', 'mountaineering', 'ski-touring', 'trail-running', 'canyoning', 'via-ferrata'], 29),
  ('Lampe frontale', ARRAY['hiking', 'climbing', 'mountaineering', 'canyoning', 'trail-running', 'via-ferrata', 'ski-touring'], 30),
  ('Carte / GPS', ARRAY['hiking', 'mountaineering', 'ski-touring', 'trail-running'], 31),
  ('Eau / Gourde', ARRAY['hiking', 'climbing', 'mountaineering', 'trail-running', 'cycling', 'mountain-biking'], 32);
