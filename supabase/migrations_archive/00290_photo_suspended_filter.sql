-- Migration 00290: hide a suspended pro's photos at the row level.
--
-- Deferred hardening #2 from the 2026-07-07 security audit. The parent
-- pro_offerings / pro_profiles policies already exclude suspended pros, but the
-- photo tables' SELECT policies did not — so a suspended pro's offering and
-- community photo URLs stayed directly readable (cosmetic image-URL leak). Add
-- the same suspended predicate the parents use.
--
-- (Deferred hardening #1 — security_invoker on the definer views — is
-- intentionally NOT done: 7 of the 9 candidate views read cross-user data via
-- public_profiles/users, and under security_invoker the caller would hit users'
-- own-row RLS, breaking every name/avatar resolution. Those views are definer
-- BY DESIGN to cross RLS. The 2 that could take it (review stats) are anon-
-- revoked aggregates with nothing sensitive to gain. So #1 is skipped.)
--
-- Non-breaking: only HIDES suspended pros' rows; normal (non-suspended) reads
-- are unchanged. private.user_is_suspended(uuid) is executable by anon and
-- authenticated (verified), so both policies still evaluate.
--
-- ROLLBACK: restore the two policies to their prior USING (scratchpad
-- 00290_rollback.sql).

-- Public community photos — keep the public read, exclude suspended pros.
ALTER POLICY pro_community_photos_public_read ON public.pro_community_photos
  USING (NOT private.user_is_suspended(pro_id));

-- Offering photos — parent-visibility EXISTS, plus the suspended exclusion.
ALTER POLICY pro_offering_photos_select ON public.pro_offering_photos
  USING (
    EXISTS (
      SELECT 1 FROM pro_offerings o
      WHERE o.id = pro_offering_photos.offering_id
        AND NOT private.user_is_suspended(o.pro_id)
    )
  );
