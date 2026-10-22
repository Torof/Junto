-- Migration 00259: revoke the review RPCs from PUBLIC.
--
-- Default privileges grant EXECUTE to PUBLIC on new functions, so the
-- 00258 "REVOKE ... FROM anon" alone left the RPCs invocable by anon
-- (caught by post-apply smoke test: anon got the generic P0001 from
-- the auth check instead of an ACL denial). Same fix as 00018.
-- No security impact — every chain denies at auth.uid() — this closes
-- the ACL layer to match the documented model.

REVOKE EXECUTE ON FUNCTION create_pro_review(UUID, SMALLINT, TEXT) FROM public;
REVOKE EXECUTE ON FUNCTION update_pro_review(UUID, SMALLINT, TEXT) FROM public;
REVOKE EXECUTE ON FUNCTION delete_pro_review(UUID) FROM public;
REVOKE EXECUTE ON FUNCTION reply_to_pro_review(UUID, TEXT) FROM public;
REVOKE EXECUTE ON FUNCTION create_offering_review(UUID, SMALLINT, TEXT) FROM public;
REVOKE EXECUTE ON FUNCTION update_offering_review(UUID, SMALLINT, TEXT) FROM public;
REVOKE EXECUTE ON FUNCTION delete_offering_review(UUID) FROM public;
REVOKE EXECUTE ON FUNCTION reply_to_offering_review(UUID, TEXT) FROM public;
