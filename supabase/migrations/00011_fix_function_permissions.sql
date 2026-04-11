-- Migration 00011: fix function EXECUTE permissions
-- Supabase grants EXECUTE to public by default on all public schema functions.
-- We need to revoke default privileges and then grant explicitly.

-- Revoke default execute on all existing functions from anon
-- Then grant back only the client-callable ones to authenticated

-- Step 1: Revoke from anon on all our functions
DO $$
DECLARE
  func_name TEXT;
BEGIN
  FOR func_name IN
    SELECT routine_name FROM information_schema.routines
    WHERE routine_schema = 'public' AND routine_type = 'FUNCTION'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I FROM anon', func_name);
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN NULL; -- some functions may have argument overloads
END $$;

-- Step 2: Explicitly grant client-callable functions to authenticated only
GRANT EXECUTE ON FUNCTION set_date_of_birth(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION accept_tos() TO authenticated;

-- Internal functions stay revoked from both anon and authenticated:
-- generate_random_name, handle_new_user, handle_user_update,
-- handle_activity_update, strip_html_tags, strip_html_users,
-- strip_html_wall_messages, strip_html_private_messages

-- Prevent future functions from auto-granting to anon
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM public;
