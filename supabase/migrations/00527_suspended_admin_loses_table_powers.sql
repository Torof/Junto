-- 00527 — a suspended admin loses every admin power, including the four that
-- went through direct table policies (audit 2026-10-23, identity F1).
--
-- Suspension is the only way to stop a rogue or compromised admin, yet seven
-- policies only checked users.is_admin: a suspended admin could still read all
-- reports and everyone's block lists, read the admin log, rewrite or dismiss a
-- report with no trace, and edit the sports catalogue.
--
-- * private.is_active_admin(uid): admin AND not suspended — used everywhere.
-- * reports: the direct UPDATE policy is dropped. Moderation goes ONLY through
--   moderate_report (which checks an active admin and logs to admin_actions);
--   the app never updates reports directly.

CREATE OR REPLACE FUNCTION private.is_active_admin(p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT EXISTS (SELECT 1 FROM users WHERE id = p_uid AND is_admin = true AND suspended_at IS NULL);
$function$;
REVOKE ALL ON FUNCTION private.is_active_admin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_active_admin(uuid) TO authenticated;  -- evaluated inside RLS policies

DROP POLICY IF EXISTS admin_actions_select_admin ON public.admin_actions;
CREATE POLICY admin_actions_select_admin ON public.admin_actions
  FOR SELECT TO authenticated USING (private.is_active_admin(auth.uid()));

DROP POLICY IF EXISTS blocked_users_select_own ON public.blocked_users;
CREATE POLICY blocked_users_select_own ON public.blocked_users
  FOR SELECT TO authenticated USING (blocker_id = auth.uid() OR private.is_active_admin(auth.uid()));

DROP POLICY IF EXISTS reports_select ON public.reports;
CREATE POLICY reports_select ON public.reports
  FOR SELECT TO authenticated USING (reporter_id = auth.uid() OR private.is_active_admin(auth.uid()));

DROP POLICY IF EXISTS reports_update_admin ON public.reports;

DROP POLICY IF EXISTS sports_insert_admin ON public.sports;
CREATE POLICY sports_insert_admin ON public.sports
  FOR INSERT TO authenticated WITH CHECK (private.is_active_admin(auth.uid()));
DROP POLICY IF EXISTS sports_update_admin ON public.sports;
CREATE POLICY sports_update_admin ON public.sports
  FOR UPDATE TO authenticated USING (private.is_active_admin(auth.uid())) WITH CHECK (private.is_active_admin(auth.uid()));
DROP POLICY IF EXISTS sports_delete_admin ON public.sports;
CREATE POLICY sports_delete_admin ON public.sports
  FOR DELETE TO authenticated USING (private.is_active_admin(auth.uid()));
