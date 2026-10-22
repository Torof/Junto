-- Migration 00009: auth-related RPC functions (set_date_of_birth, accept_tos)

-- ============================================================================
-- FUNCTION: set_date_of_birth (one-time only, must be 18+)
-- ============================================================================
CREATE OR REPLACE FUNCTION set_date_of_birth(p_date_of_birth DATE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Auth check
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- One-time only: reject if already set
  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND date_of_birth IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Age verification: must be 18+
  IF p_date_of_birth > (CURRENT_DATE - INTERVAL '18 years')::date THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Set the value (bypass whitelist trigger)
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET date_of_birth = p_date_of_birth WHERE id = auth.uid();
END;
$$;

-- Client-callable: authenticated only, not anon
REVOKE EXECUTE ON FUNCTION set_date_of_birth(DATE) FROM anon;
GRANT EXECUTE ON FUNCTION set_date_of_birth(DATE) TO authenticated;

-- ============================================================================
-- FUNCTION: accept_tos (one-time only, sets both timestamps)
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_tos()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Auth check
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- One-time only: reject if already accepted
  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND accepted_tos_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Set both consent timestamps (bypass whitelist trigger)
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET accepted_tos_at = now(), accepted_privacy_at = now() WHERE id = auth.uid();
END;
$$;

-- Client-callable: authenticated only, not anon
REVOKE EXECUTE ON FUNCTION accept_tos() FROM anon;
GRANT EXECUTE ON FUNCTION accept_tos() TO authenticated;
