-- 00318: replace date-of-birth collection with an 18+ self-attestation
--
-- Scott's call (2026-07-12): the DOB picker only ever fed the 18+ age gate
-- and the onboarding-complete marker — the birthdate was never displayed
-- or reused. A DOB entry verifies nothing a checkbox doesn't (both rely on
-- honesty), and storing a full birthdate breaches data-minimisation for a
-- need that is just "is adult". So: drop date_of_birth, record a simple
-- age_confirmed_at timestamp instead.
--
-- confirm_age_adult() authorization chain (validated by Scott): auth +
-- not-suspended + idempotent (no-op if already confirmed) + stamps
-- age_confirmed_at under bypass_lock. No server-side age math is possible
-- anymore (no birthdate) — the client attests, exactly like the TOS
-- acceptance it sits next to. Safe now: test data will be wiped pre-launch.

ALTER TABLE users ADD COLUMN IF NOT EXISTS age_confirmed_at TIMESTAMPTZ;

-- ---------------------------------------------------------------------------
-- confirm_age_adult — records the 18+ attestation (one-time, idempotent)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION confirm_age_adult()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Idempotent: already confirmed → no-op (re-confirming is harmless).
  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND age_confirmed_at IS NOT NULL) THEN
    RETURN;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET age_confirmed_at = now() WHERE id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION confirm_age_adult() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION confirm_age_adult() FROM anon;
GRANT EXECUTE ON FUNCTION confirm_age_adult() TO authenticated;

-- ---------------------------------------------------------------------------
-- Drop the old DOB setter (latest def 00271) — no longer used.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS set_date_of_birth(DATE);

-- ---------------------------------------------------------------------------
-- Whitelist trigger: date_of_birth line replaced by age_confirmed_at (both
-- privileged — writable only via the bypass_lock functions).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION handle_user_update()
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

  -- WHITELIST: any non-allowed column is forced back to its OLD value.
  -- Allowed (writable by the user): display_name, avatar_url, bio, sports, notification_preferences
  -- `levels_per_sport` is NO LONGER writable directly — only via set_sport_level
  -- (peer-gated). Forced to OLD below.
  NEW.id := OLD.id;
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.age_confirmed_at := OLD.age_confirmed_at;
  NEW.phone_verified := OLD.phone_verified;
  NEW.phone_verified_at := OLD.phone_verified_at;
  NEW.tier := OLD.tier;
  NEW.is_pro_verified := OLD.is_pro_verified;
  NEW.pro_verified_at := OLD.pro_verified_at;
  NEW.is_admin := OLD.is_admin;
  NEW.suspended_at := OLD.suspended_at;
  NEW.accepted_tos_at := OLD.accepted_tos_at;
  NEW.accepted_privacy_at := OLD.accepted_privacy_at;
  NEW.tutorial_seen_at := OLD.tutorial_seen_at;
  NEW.push_token := OLD.push_token;
  NEW.reliability_score := OLD.reliability_score;
  NEW.levels_per_sport := OLD.levels_per_sport;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Drop the column (also drops the 00012 age CHECK constraint on it).
-- ---------------------------------------------------------------------------
ALTER TABLE users DROP COLUMN IF EXISTS date_of_birth;
