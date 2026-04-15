-- Migration 00057: ensure on_auth_user_created trigger exists
-- It may have been lost during the earlier db reset (auth schema triggers don't always survive).

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
