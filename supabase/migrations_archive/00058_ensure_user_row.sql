-- Migration 00058: self-healing function — creates public.users row if missing for the current auth user

CREATE OR REPLACE FUNCTION ensure_user_row()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_email TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM public.users WHERE id = v_user_id) THEN
    RETURN;
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = v_user_id;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO public.users (id, email, display_name, tier, created_at, updated_at)
  VALUES (v_user_id, v_email, generate_random_name(), 'premium', now(), now())
  ON CONFLICT (id) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION ensure_user_row FROM anon;
GRANT EXECUTE ON FUNCTION ensure_user_row TO authenticated;
