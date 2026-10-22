-- 00530 — the person who reports someone no longer reads the report back
-- (audit 2026-10-23, identity F2).
--
-- reports_select let the reporter read their report, including status and the
-- admin's private note after moderation — revealing to a third party that the
-- target was sanctioned (and why). The app reads reports only on admin screens;
-- create_report already handles duplicates server-side. Only an active admin
-- reads reports now.

DROP POLICY IF EXISTS reports_select ON public.reports;
CREATE POLICY reports_select ON public.reports
  FOR SELECT TO authenticated USING (private.is_active_admin(auth.uid()));
