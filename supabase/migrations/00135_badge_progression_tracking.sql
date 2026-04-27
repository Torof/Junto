-- Migration 00135: track badge tier progression + emit level-up notifs.
-- New table user_badge_progression records every (category, sport_key, tier)
-- the user has unlocked. Helper functions translate counts → tier and tier
-- → French label. A trigger on activities flipping to 'completed' recomputes
-- progression for every accepted participant and inserts new rows + a
-- 'badge_unlocked' notification only for never-before-awarded tiers.
--
-- Existing users are silently backfilled at migration time so they don't get
-- spurious notifs about tiers they already had.

-- ============================================================================
-- 1. Tier ladder helper
-- ============================================================================
CREATE OR REPLACE FUNCTION badge_tier_for(p_count INTEGER)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_count >= 75 THEN 't5'
    WHEN p_count >= 50 THEN 't4'
    WHEN p_count >= 20 THEN 't3'
    WHEN p_count >= 10 THEN 't2'
    WHEN p_count >= 5  THEN 't1'
    ELSE NULL
  END;
$$;

GRANT EXECUTE ON FUNCTION badge_tier_for TO authenticated;

-- ============================================================================
-- 2. French label for (category, tier) — used in the notif body
-- ============================================================================
CREATE OR REPLACE FUNCTION badge_label_fr(p_category TEXT, p_tier TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_category || '_' || p_tier
    WHEN 'joined_t1'  THEN 'Membre'
    WHEN 'joined_t2'  THEN 'Actif'
    WHEN 'joined_t3'  THEN 'Régulier'
    WHEN 'joined_t4'  THEN 'Habitué'
    WHEN 'joined_t5'  THEN 'Pilier'
    WHEN 'created_t1' THEN 'Initiateur'
    WHEN 'created_t2' THEN 'Organisateur'
    WHEN 'created_t3' THEN 'Animateur'
    WHEN 'created_t4' THEN 'Coordinateur'
    WHEN 'created_t5' THEN 'Bâtisseur'
    WHEN 'sport_t1'   THEN 'Curieux'
    WHEN 'sport_t2'   THEN 'Adepte'
    WHEN 'sport_t3'   THEN 'Mordu'
    WHEN 'sport_t4'   THEN 'Passionné'
    WHEN 'sport_t5'   THEN 'Inconditionnel'
    ELSE 'Niveau ' || upper(p_tier)
  END;
$$;

-- ============================================================================
-- 3. user_badge_progression table
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_badge_progression (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('joined','created','sport')),
  sport_key TEXT,
  tier_key TEXT NOT NULL CHECK (tier_key IN ('t1','t2','t3','t4','t5')),
  awarded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ubp_unique
  ON user_badge_progression (user_id, category, COALESCE(sport_key, ''), tier_key);

CREATE INDEX IF NOT EXISTS idx_ubp_user ON user_badge_progression (user_id);

ALTER TABLE user_badge_progression ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_badge_progression FORCE ROW LEVEL SECURITY;

CREATE POLICY "user_badge_progression_select_own"
  ON user_badge_progression FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- No client INSERT/UPDATE/DELETE — managed exclusively via the helpers below.

-- ============================================================================
-- 4. award_badge_progression(user_id, silent)
--    Recomputes counts, inserts any newly-crossed tier rows, and fires
--    'badge_unlocked' notifs unless silent=true (used for backfill).
-- ============================================================================
CREATE OR REPLACE FUNCTION award_badge_progression(
  p_user_id UUID,
  p_silent BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
  v_tier TEXT;
  v_inserted UUID;
  v_label TEXT;
  v_sport RECORD;
BEGIN
  -- Joined
  SELECT count(*) INTO v_count
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND a.status = 'completed'
    AND a.creator_id != p_user_id
    AND a.deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'joined', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('joined', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'joined', 'tier', v_tier)
      );
    END IF;
  END IF;
  v_inserted := NULL;

  -- Created
  SELECT count(*) INTO v_count
  FROM activities
  WHERE creator_id = p_user_id
    AND status = 'completed'
    AND deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'created', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('created', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'created', 'tier', v_tier)
      );
    END IF;
  END IF;
  v_inserted := NULL;

  -- Per-sport
  FOR v_sport IN
    SELECT s.key AS sport_key, count(*)::int AS cnt
    FROM participations par
    JOIN activities a ON a.id = par.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE par.user_id = p_user_id
      AND par.status = 'accepted'
      AND a.status = 'completed'
      AND a.deleted_at IS NULL
    GROUP BY s.key
  LOOP
    v_tier := badge_tier_for(v_sport.cnt);
    IF v_tier IS NOT NULL THEN
      INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
      VALUES (p_user_id, 'sport', v_sport.sport_key, v_tier)
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_inserted;
      IF v_inserted IS NOT NULL AND NOT p_silent THEN
        v_label := badge_label_fr('sport', v_tier);
        PERFORM create_notification(
          p_user_id,
          'badge_unlocked',
          'Nouveau badge !',
          'Tu es maintenant ' || v_label || ' — ' || v_sport.sport_key,
          jsonb_build_object('category', 'sport', 'tier', v_tier, 'sport_key', v_sport.sport_key)
        );
      END IF;
      v_inserted := NULL;
    END IF;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION award_badge_progression FROM anon, authenticated;

-- ============================================================================
-- 5. Trigger: when an activity flips to 'completed', award everyone affected
-- ============================================================================
CREATE OR REPLACE FUNCTION on_activity_completed_award_badges()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    -- Recompute for every accepted participant (creator included — they're
    -- in participations as 'accepted' since create_activity inserts a row).
    FOR v_user_id IN
      SELECT user_id FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted'
    LOOP
      PERFORM award_badge_progression(v_user_id, FALSE);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_award_badges_on_complete ON activities;
CREATE TRIGGER trg_award_badges_on_complete
  AFTER UPDATE OF status ON activities
  FOR EACH ROW
  EXECUTE FUNCTION on_activity_completed_award_badges();

-- ============================================================================
-- 6. Backfill: silently award current state for every existing user
-- ============================================================================
DO $$
DECLARE
  v_user RECORD;
BEGIN
  FOR v_user IN SELECT id FROM users LOOP
    PERFORM award_badge_progression(v_user.id, TRUE);
  END LOOP;
END $$;
