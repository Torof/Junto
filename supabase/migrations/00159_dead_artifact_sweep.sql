-- Migration 00159: dead-artifact sweep + badge_unlocked alignment.
--
-- Bundles every cleanup item identified in the notification audit:
--
--  A. Badge progression alignment with new awards system (mig 00155):
--     - badge_tier_for now returns bronze/silver/gold at 5/20/50
--     - badge_label_fr returns new labels for joined/created only
--     - user_badge_progression rows migrated from t1-t5 to new tiers,
--       sport rows deleted (no profile equivalent)
--     - CHECK constraints tightened
--     - award_badge_progression drops the per-sport branch
--
--  B. Deprecated reputation_votes keys deleted (data dead since mig 00152/00154):
--     trustworthy, great_leader, good_vibes, difficult_attitude,
--     unreliable_field, level_overestimated, late_canceller,
--     level_accurate, level_under
--     give_reputation_badge whitelist also drops level_under so no new
--     ones can be cast.
--
--  C. Deprecated notification rows deleted (types dropped in mig 00148):
--     presence_reminder, presence_last_call
--
--  D. Orphan endorsement system removed entirely (UI dropped during the
--     SportIconGrid removal — table, functions, indexes all gone):
--     sport_level_endorsements table + submit_sport_level_endorsement
--     + get_user_sport_endorsements
--
--  E. Orphan get_user_sport_breakdown function dropped (UI dropped at
--     same time as the endorsement table).
--
-- Each section is independently safe (no cross-dependencies) and the
-- migration is idempotent where possible (DROP IF EXISTS, etc).

-- ============================================================================
-- A. Badge alignment + cleanup
-- ============================================================================

-- A.1 New tier helper: bronze/silver/gold matching mig 00155 thresholds
CREATE OR REPLACE FUNCTION badge_tier_for(p_count INTEGER)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_count >= 50 THEN 'gold'
    WHEN p_count >= 20 THEN 'silver'
    WHEN p_count >= 5  THEN 'bronze'
    ELSE NULL
  END;
$$;

GRANT EXECUTE ON FUNCTION badge_tier_for TO authenticated;

-- A.2 Labels: only joined and created (no per-sport, no t1-t5)
CREATE OR REPLACE FUNCTION badge_label_fr(p_category TEXT, p_tier TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_category || '_' || p_tier
    WHEN 'joined_bronze'  THEN 'Membre'
    WHEN 'joined_silver'  THEN 'Régulier'
    WHEN 'joined_gold'    THEN 'Pilier'
    WHEN 'created_bronze' THEN 'Initiateur'
    WHEN 'created_silver' THEN 'Animateur'
    WHEN 'created_gold'   THEN 'Bâtisseur'
    ELSE NULL
  END;
$$;

-- A.3 Migrate existing user_badge_progression rows. Drop CHECK first so
-- we can update tier_key freely; re-add at the end with new allowed values.
ALTER TABLE user_badge_progression DROP CONSTRAINT IF EXISTS user_badge_progression_tier_key_check;
ALTER TABLE user_badge_progression DROP CONSTRAINT IF EXISTS user_badge_progression_category_check;

-- Order matters: drop redundant rows first, then rename remaining ones.

-- t2 is always covered by t1 (both → bronze in new system)
DELETE FROM user_badge_progression
WHERE tier_key = 't2'
  AND category IN ('joined', 'created');

-- Drop t5 entries when t4 already exists (both map to gold; keep earliest = t4)
DELETE FROM user_badge_progression u
WHERE u.tier_key = 't5'
  AND u.category IN ('joined', 'created')
  AND EXISTS (
    SELECT 1 FROM user_badge_progression u2
    WHERE u2.user_id = u.user_id
      AND u2.category = u.category
      AND u2.tier_key = 't4'
  );

-- Rename remaining tiers to new names
UPDATE user_badge_progression
  SET tier_key = 'bronze'
  WHERE tier_key = 't1' AND category IN ('joined', 'created');

UPDATE user_badge_progression
  SET tier_key = 'silver'
  WHERE tier_key = 't3' AND category IN ('joined', 'created');

UPDATE user_badge_progression
  SET tier_key = 'gold'
  WHERE tier_key IN ('t4', 't5') AND category IN ('joined', 'created');

-- Wipe per-sport progression entirely (no profile equivalent in new system,
-- no notif emission going forward).
DELETE FROM user_badge_progression WHERE category = 'sport';

-- Re-add tightened constraints
ALTER TABLE user_badge_progression
  ADD CONSTRAINT user_badge_progression_tier_key_check
  CHECK (tier_key IN ('bronze', 'silver', 'gold'));

ALTER TABLE user_badge_progression
  ADD CONSTRAINT user_badge_progression_category_check
  CHECK (category IN ('joined', 'created'));

-- A.4 Rewrite the emitter: only joined and created, no per-sport loop
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
BEGIN
  -- Joined activities (where the user wasn't the creator)
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

  -- Created activities
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
END;
$$;

REVOKE EXECUTE ON FUNCTION award_badge_progression FROM anon, authenticated;

-- ============================================================================
-- B. Deprecated reputation_votes keys
-- ============================================================================

DELETE FROM reputation_votes
WHERE badge_key IN (
  'trustworthy',
  'great_leader',
  'good_vibes',
  'difficult_attitude',
  'unreliable_field',
  'level_overestimated',
  'late_canceller',
  'level_accurate',
  'level_under'
);

-- Update give_reputation_badge whitelist to drop level_under so no new
-- ones can be cast even by legacy clients. Function recreated verbatim
-- from mig 00154 with only the v_valid_keys array changed.
CREATE OR REPLACE FUNCTION give_reputation_badge(
  p_voted_id UUID,
  p_activity_id UUID,
  p_badge_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_valid_keys TEXT[] := ARRAY[
    -- Global positives
    'punctual', 'prepared', 'conciliant', 'prudent',
    -- Global negatives
    'unprepared', 'aggressive', 'reckless',
    -- Per-sport level votes (mutually exclusive; level_under removed)
    'level_over', 'level_right'
  ];
  v_level_keys TEXT[] := ARRAY['level_over', 'level_right'];
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT (p_badge_key = ANY(v_valid_keys)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_voted_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_badge_key = ANY(v_level_keys) THEN
    DELETE FROM reputation_votes
    WHERE voter_id = v_user_id
      AND voted_id = p_voted_id
      AND activity_id = p_activity_id
      AND badge_key = ANY(v_level_keys);
  END IF;

  INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, p_badge_key, now());
END;
$$;

REVOKE EXECUTE ON FUNCTION give_reputation_badge FROM anon;
GRANT EXECUTE ON FUNCTION give_reputation_badge TO authenticated;

-- ============================================================================
-- C. Deprecated notification rows
-- ============================================================================

DELETE FROM notifications
WHERE type IN ('presence_reminder', 'presence_last_call');

-- ============================================================================
-- D. Orphan endorsement system
-- ============================================================================

DROP FUNCTION IF EXISTS submit_sport_level_endorsement(UUID, UUID, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS get_user_sport_endorsements(UUID);
DROP TABLE IF EXISTS sport_level_endorsements;

-- ============================================================================
-- E. Orphan sport breakdown
-- ============================================================================

DROP FUNCTION IF EXISTS get_user_sport_breakdown(UUID);
