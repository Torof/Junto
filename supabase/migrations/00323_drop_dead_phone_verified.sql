-- Migration 00323: drop the dead phone-verification columns
--
-- Phone verification was added early then removed: the create_activity gate on
-- phone_verified is gone since 00316, and create_alert (00270) no longer gates
-- on it either. No active function reads phone_verified, and no client code
-- uses it (only stale generated types). The users table still carries
-- phone_verified / phone_verified_at, and the whitelist trigger still protects
-- them — pure dead weight. Remove both.
--
-- Order matters: rewrite the trigger to stop referencing the columns BEFORE
-- dropping them (same body as 00318, minus the two phone lines).

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
  NEW.id := OLD.id;
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.age_confirmed_at := OLD.age_confirmed_at;
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

ALTER TABLE users DROP COLUMN IF EXISTS phone_verified;
ALTER TABLE users DROP COLUMN IF EXISTS phone_verified_at;
