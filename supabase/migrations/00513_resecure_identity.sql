-- ============================================================================
-- 00513 — Re-sécurisation, lot identité (audit neuf).
-- ID-2  Contournement : supprimer son profil par la RPC seule laissait le
--       compte de connexion vivant, et ensure_user_row recréait un profil
--       neuf, non suspendu. ensure_user_row refuse désormais un e-mail
--       interdit ; l'écran « compte suspendu » passe par la suppression
--       complète (fonction delete-account, qui purge aussi les photos de
--       canal). Empreinte : points Gmail ignorés ; un changement d'e-mail de
--       connexion vers un e-mail interdit est refusé.
-- ID-4  Suspendre depuis un signalement : seulement la personne visée, par le
--       chemin complet admin_suspend_user.
-- ID-3 / AB-8 suite : users.sports est un tableau borné, préférences bornées.
-- ============================================================================

CREATE OR REPLACE FUNCTION private.email_hash(p_email text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN p_email IS NULL OR position('@' in p_email) = 0 THEN NULL ELSE
    encode(extensions.hmac(
      -- 00513: Gmail ignores dots in the local part, and googlemail.com = gmail.com.
      CASE WHEN split_part(lower(trim(p_email)), '@', 2) IN ('gmail.com', 'googlemail.com')
        THEN replace(regexp_replace(split_part(lower(trim(p_email)), '@', 1), '\+.*$', ''), '.', '') || '@gmail.com'
        ELSE regexp_replace(split_part(lower(trim(p_email)), '@', 1), '\+.*$', '') || '@' || split_part(lower(trim(p_email)), '@', 2) END,
      (SELECT value FROM app_config WHERE name = 'email_ban_pepper'), 'sha256'), 'hex') END;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_user_row()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- 00513: an account deleted while suspended cannot come back through its
  -- surviving login (the profile row is recreated here, not in
  -- handle_new_user — the ID-2 bypass found by the re-secure audit).
  IF private.email_is_banned(v_email) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO public.users (id, email, display_name, tier, created_at, updated_at)
  VALUES (v_user_id, v_email, generate_random_name(), 'premium', now(), now())
  ON CONFLICT (id) DO NOTHING;
END;
$function$;

CREATE OR REPLACE FUNCTION public.moderate_report(p_report_id uuid, p_action text, p_admin_note text DEFAULT NULL::text, p_suspend_user_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_report RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_action NOT IN ('dismissed', 'actioned') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status, target_type, target_id INTO v_report FROM reports WHERE id = p_report_id;
  IF v_report IS NULL OR v_report.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE reports
  SET status = p_action, admin_note = p_admin_note, resolved_at = now()
  WHERE id = p_report_id;

  IF p_suspend_user_id IS NOT NULL AND p_action = 'actioned' THEN
    -- 00513 (ID-4): only the person the report is about can be suspended
    -- from it, through the full suspension path (reason, booking
    -- cancellations, notifications, log).
    IF p_suspend_user_id IS DISTINCT FROM (
      SELECT CASE v_report.target_type
        WHEN 'user' THEN v_report.target_id
        WHEN 'message' THEN (SELECT m.sender_id FROM messages m WHERE m.id = v_report.target_id)
        WHEN 'activity' THEN (SELECT a.creator_id FROM activities a WHERE a.id = v_report.target_id)
        WHEN 'pro_review' THEN (SELECT r.reviewer_id FROM pro_reviews r WHERE r.id = v_report.target_id)
        WHEN 'offering_review' THEN (SELECT r.reviewer_id FROM offering_reviews r WHERE r.id = v_report.target_id)
        WHEN 'group' THEN (SELECT c.created_by FROM conversations c WHERE c.id = v_report.target_id)
        WHEN 'channel' THEN (SELECT ch.created_by FROM channels ch WHERE ch.conversation_id = v_report.target_id)
      END) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    PERFORM admin_suspend_user(p_suspend_user_id, coalesce(nullif(trim(p_admin_note), ''), 'Signalement n° ' || p_report_id::text));
  END IF;

  PERFORM log_admin_action(
    v_user_id, 'moderate_report', 'report', p_report_id, p_admin_note,
    jsonb_build_object('action', p_action, 'suspended_user_id', p_suspend_user_id)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION private.refuse_banned_email_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.email IS DISTINCT FROM OLD.email AND private.email_is_banned(NEW.email) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.refuse_banned_email_change() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS junto_refuse_banned_email_change ON auth.users;
CREATE TRIGGER junto_refuse_banned_email_change BEFORE UPDATE OF email ON auth.users
  FOR EACH ROW EXECUTE FUNCTION private.refuse_banned_email_change();

ALTER TABLE users ADD CONSTRAINT users_sports_shape CHECK (
  sports IS NULL OR (jsonb_typeof(sports) = 'array' AND jsonb_array_length(sports) <= 40 AND pg_column_size(sports) < 2048));
ALTER TABLE users ADD CONSTRAINT users_notification_preferences_size CHECK (
  notification_preferences IS NULL OR (jsonb_typeof(notification_preferences) = 'object' AND pg_column_size(notification_preferences) < 4096));
