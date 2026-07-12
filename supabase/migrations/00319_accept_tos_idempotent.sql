-- 00319: accept_tos becomes idempotent
--
-- accept_tos raised 'Operation not permitted' when accepted_tos_at was
-- already set. After 00318 (age attestation), pre-existing accounts have
-- age_confirmed_at NULL and are re-shown the onboarding; their TOS is
-- already accepted, so confirming errored and wedged the screen. A user
-- re-accepting their own TOS is harmless — no-op and keep the original
-- timestamp instead of erroring. Authorization chain otherwise unchanged.

CREATE OR REPLACE FUNCTION accept_tos()
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

  PERFORM pg_advisory_xact_lock(hashtext('accept_tos:' || auth.uid()::text));

  -- Idempotent: already accepted -> no-op, preserving the original
  -- acceptance timestamp (the legally meaningful one). Was RAISE, which
  -- blocked the onboarding submit for pre-existing accounts re-shown the
  -- onboarding after the age-attestation migration (Scott 2026-07-12).
  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND accepted_tos_at IS NOT NULL) THEN
    RETURN;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET accepted_tos_at = now(), accepted_privacy_at = now() WHERE id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION accept_tos() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION accept_tos() FROM anon;
GRANT EXECUTE ON FUNCTION accept_tos() TO authenticated;
