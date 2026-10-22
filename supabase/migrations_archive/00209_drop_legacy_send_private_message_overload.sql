-- Migration 00209: drop the legacy 2-arg send_private_message overload.
--
-- 00208 added a 3-arg version (with p_reply_to_message_id DEFAULT NULL)
-- but Postgres treats different-arity signatures as separate functions,
-- so the original 2-arg version from 00185 stayed in place. PostgREST
-- then routes calls based on the keys present in the JSON body — when
-- the client sends `p_reply_to_message_id: undefined` (dropped from
-- JSON), the call matches the 2-arg overload AND the 3-arg overload's
-- defaulted form simultaneously, which Postgres flags as ambiguous.
-- The client-side fix is to always pass the third parameter (null when
-- no reply) so the 3-arg overload is unambiguous; this migration
-- removes the legacy overload so the ambiguity can't reappear.
--
-- Auth chain unchanged — 00208's 3-arg version remains the canonical
-- send_private_message and already covers the no-reply path via
-- DEFAULT NULL.

DROP FUNCTION IF EXISTS public.send_private_message(UUID, TEXT);
