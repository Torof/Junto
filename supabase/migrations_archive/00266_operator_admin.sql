-- Migration 00266: grant operator/admin to the founder account.
--
-- Context: Scott (dev.solidity@proton.me) couldn't create activities.
-- Prime suspect: the 00262 anti-spam caps (10/24h, 15/30d) — a developer
-- dogfooding trivially exceeds 15 creates in 30 days (every test activity
-- counts, any status). The operator needs admin regardless (moderation
-- screens), and admins bypass the create caps (00144 branch). is_admin is
-- a privileged column (handle_user_update forces it to OLD), so the
-- update runs under junto.bypass_lock. The RAISE NOTICE lines confirm the
-- diagnosis in the push output (one-time, read-only diagnostic).
DO $$
DECLARE
  v_id UUID;
  v_admin BOOLEAN;
  v_tier TEXT;
  v_suspended BOOLEAN;
  v_30d INTEGER;
  v_24h INTEGER;
BEGIN
  SELECT id, coalesce(is_admin, FALSE), tier, suspended_at IS NOT NULL
    INTO v_id, v_admin, v_tier, v_suspended
  FROM public.users WHERE email = 'dev.solidity@proton.me';

  IF v_id IS NULL THEN
    RAISE NOTICE '[00266] account dev.solidity@proton.me NOT FOUND';
    RETURN;
  END IF;

  SELECT count(*) FILTER (WHERE created_at > now() - interval '30 days'),
         count(*) FILTER (WHERE created_at > now() - interval '1 day')
    INTO v_30d, v_24h
  FROM activities WHERE creator_id = v_id;

  RAISE NOTICE '[00266] before: tier=% admin=% suspended=% created_30d=% (cap 15) created_24h=% (cap 10)',
    v_tier, v_admin, v_suspended, v_30d, v_24h;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE public.users SET is_admin = TRUE WHERE id = v_id;

  RAISE NOTICE '[00266] is_admin set TRUE — caps now bypassed for this operator account';
END $$;
