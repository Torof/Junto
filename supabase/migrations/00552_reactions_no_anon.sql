-- 00552 — message_reactions is for signed-in members only: the default
-- privileges gave anon SELECT (RLS already returned nothing; the C20 guard
-- wants no new object readable without an account).
REVOKE ALL ON public.message_reactions FROM anon;
