-- Migration 00051: TEMPORARY — auto-grant premium tier to all new signups
-- Revert this migration before launching wider (use payment flow instead).

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, display_name, tier, created_at, updated_at)
  VALUES (NEW.id, NEW.email, generate_random_name(), 'premium', now(), now());
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION handle_new_user() FROM anon, authenticated;
