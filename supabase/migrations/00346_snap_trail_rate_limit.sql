-- ============================================================================
-- 00346 — Per-user rate limit for the snap-trail edge function (audit MEDIUM).
--
-- The JWT gate limited WHO can spend the free ORS quota, not HOW MUCH — a single
-- authed user could loop the endpoint and drain it for everyone. Add a small
-- per-user usage log + a SECURITY DEFINER `consume_snap_trail_quota()` the edge
-- function calls (as the caller) before hitting ORS: 200 snaps / rolling hour.
-- Internal table — no policies, no grants — reachable only via the function.
-- ============================================================================
CREATE TABLE snap_trail_calls (
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  called_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX snap_trail_calls_user_idx ON snap_trail_calls(user_id, called_at DESC);

ALTER TABLE snap_trail_calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE snap_trail_calls FORCE ROW LEVEL SECURITY;
REVOKE ALL ON snap_trail_calls FROM anon, authenticated;

CREATE OR REPLACE FUNCTION consume_snap_trail_quota()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID;
  v_count INTEGER;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_snap_trail'));
  DELETE FROM snap_trail_calls WHERE user_id = v_user AND called_at < now() - INTERVAL '1 hour';
  SELECT count(*) INTO v_count FROM snap_trail_calls WHERE user_id = v_user;
  IF v_count >= 200 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO snap_trail_calls (user_id) VALUES (v_user);
END;
$$;
REVOKE ALL ON FUNCTION consume_snap_trail_quota() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION consume_snap_trail_quota() TO authenticated;
