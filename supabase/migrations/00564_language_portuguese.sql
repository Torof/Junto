-- Portuguese (pt) joins the app languages (Scott 2026-10-31), same as 00563.
ALTER TABLE public.users DROP CONSTRAINT users_language_check;
ALTER TABLE public.users ADD CONSTRAINT users_language_check
  CHECK (language = ANY (ARRAY['fr', 'en', 'it', 'es', 'de', 'nl', 'pt']));
