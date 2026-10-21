-- ============================================================================
-- 00506 — ID-2 (décision Scott) : un compte suspendu peut toujours supprimer
-- son compte (droit à l'effacement), mais l'e-mail ne peut plus servir à se
-- réinscrire. On ne garde pas l'e-mail : seulement son empreinte HMAC-SHA256
-- avec un secret du serveur (app_config, illisible des clients). Une levée de
-- suspension avant la suppression ne laisse aucune trace. Réinscription
-- possible seulement par le support (suppression de la ligne).
-- ============================================================================

INSERT INTO app_config (name, value)
SELECT 'email_ban_pepper', encode(extensions.gen_random_bytes(32), 'hex')
WHERE NOT EXISTS (SELECT 1 FROM app_config WHERE name = 'email_ban_pepper');

CREATE TABLE IF NOT EXISTS banned_email_hashes (
  email_hash TEXT PRIMARY KEY CHECK (char_length(email_hash) = 64),
  banned_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE banned_email_hashes ENABLE ROW LEVEL SECURITY;
ALTER TABLE banned_email_hashes FORCE ROW LEVEL SECURITY;
REVOKE ALL ON banned_email_hashes FROM PUBLIC, anon, authenticated;

-- Normalised: lower case, trimmed, « +tag » removed from the local part.
CREATE OR REPLACE FUNCTION private.email_hash(p_email text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN p_email IS NULL OR position('@' in p_email) = 0 THEN NULL ELSE
    encode(extensions.hmac(
      regexp_replace(split_part(lower(trim(p_email)), '@', 1), '\+.*$', '') || '@' || split_part(lower(trim(p_email)), '@', 2),
      (SELECT value FROM app_config WHERE name = 'email_ban_pepper'), 'sha256'), 'hex') END;
$function$;

CREATE OR REPLACE FUNCTION private.email_is_banned(p_email text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM banned_email_hashes WHERE email_hash = private.email_hash(p_email));
$function$;

CREATE OR REPLACE FUNCTION private.ban_email_on_suspended_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_email TEXT;
BEGIN
  IF OLD.suspended_at IS NULL THEN RETURN OLD; END IF;
  SELECT email INTO v_auth_email FROM auth.users WHERE id = OLD.id;
  -- Both the profile e-mail and the current login e-mail (changed meanwhile?).
  INSERT INTO banned_email_hashes (email_hash)
  SELECT h FROM (VALUES (private.email_hash(OLD.email)), (private.email_hash(v_auth_email))) v(h)
  WHERE h IS NOT NULL
  ON CONFLICT (email_hash) DO NOTHING;
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trg_users_ban_email_on_suspended_delete ON users;
CREATE TRIGGER trg_users_ban_email_on_suspended_delete BEFORE DELETE ON users
  FOR EACH ROW EXECUTE FUNCTION private.ban_email_on_suspended_delete();

REVOKE ALL ON FUNCTION private.email_hash(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.email_is_banned(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.ban_email_on_suspended_delete() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 00506 (ID-2): an e-mail whose account was deleted while suspended cannot
  -- sign up again (re-registration goes through support).
  IF private.email_is_banned(NEW.email) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  INSERT INTO public.users (id, email, display_name, tier, created_at, updated_at)
  VALUES (NEW.id, NEW.email, generate_random_name(), 'premium', now(), now());
  RETURN NEW;
END;
$function$;
