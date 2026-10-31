-- Dutch (nl) joins the app languages (Scott 2026-10-31): users.language is
-- mirrored from the app, so its CHECK must accept every shipped language.
ALTER TABLE public.users DROP CONSTRAINT users_language_check;
ALTER TABLE public.users ADD CONSTRAINT users_language_check
  CHECK (language = ANY (ARRAY['fr', 'en', 'it', 'es', 'de', 'nl']));
