-- ============================================================================
-- 00352 — conversations: no direct client reads (brique 1, phase 2).
--
-- Closes the last live finding of the messaging-design review: the
-- conversations_select_own policy (00031) let a request sender read
-- status='declined' via PostgREST, making the silent decline UI-deep only.
-- Since 00351 + the production OTA, every client read goes through the four
-- curated SECURITY DEFINER RPCs (which coalesce declined→pending for the
-- sender), so the base table can now be sealed like its writes already are.
--
-- Sequencing note: applied AFTER the client OTA (c38c3eb) was published —
-- an old bundle launching post-drop shows one empty messagerie load, then
-- self-heals on the next launch when the OTA applies (testers inactive,
-- accepted by Scott).
-- ============================================================================

DROP POLICY IF EXISTS conversations_select_own ON conversations;
REVOKE SELECT ON conversations FROM authenticated;
REVOKE SELECT ON conversations FROM anon;
