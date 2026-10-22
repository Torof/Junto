-- Pro offering texts lose their HTML and invisible characters (audit, small 11
-- / FIN2-1): every other public text was already cleaned (outings, messages,
-- reviews, pro page), while an offering's title and description kept their
-- tags — and pro_offerings_with_coords is read by the website without an account.

CREATE OR REPLACE FUNCTION public.strip_html_offerings()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.title IS NOT NULL THEN
    NEW.title := private.strip_invisible(regexp_replace(NEW.title, '<[^>]*>', '', 'g'));
  END IF;
  IF NEW.description IS NOT NULL THEN
    NEW.description := private.strip_invisible(regexp_replace(NEW.description, '<[^>]*>', '', 'g'));
  END IF;
  IF NEW.level IS NOT NULL THEN
    NEW.level := private.strip_invisible(regexp_replace(NEW.level, '<[^>]*>', '', 'g'));
  END IF;
  IF NEW.location_name IS NOT NULL THEN
    NEW.location_name := private.strip_invisible(regexp_replace(NEW.location_name, '<[^>]*>', '', 'g'));
  END IF;
  IF NEW.schedule_text IS NOT NULL THEN
    NEW.schedule_text := private.strip_invisible(regexp_replace(NEW.schedule_text, '<[^>]*>', '', 'g'));
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.strip_html_offerings() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER pro_offerings_strip_html
  BEFORE INSERT OR UPDATE ON public.pro_offerings
  FOR EACH ROW EXECUTE FUNCTION public.strip_html_offerings();

-- Existing rows: the trigger cleans them on this no-op update.
SELECT set_config('junto.bypass_lock', 'true', true);
UPDATE public.pro_offerings SET title = title
WHERE title ~ '<[^>]*>' OR description ~ '<[^>]*>' OR level ~ '<[^>]*>'
   OR location_name ~ '<[^>]*>' OR schedule_text ~ '<[^>]*>'
   OR concat_ws(' ', title, description, level, location_name, schedule_text)
      ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
SELECT set_config('junto.bypass_lock', 'false', true);
