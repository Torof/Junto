-- 00532 — invisible / direction-changing characters are removed from texts
-- other people see (audit 2026-10-23, identity F5).
--
-- A display name could carry U+202E (right-to-left override) or zero-width
-- characters: it reversed the rest of the line in other users' notifications
-- and lists (spoofing). The MS-5 fix removed only control characters; Unicode
-- "format" characters (soft hyphen, zero-width, bidi marks/embeddings/isolates,
-- BOM) were missed. private.strip_invisible removes them; applied to profiles,
-- outings, messages, reviews and notification texts (send-push does the same).

CREATE OR REPLACE FUNCTION private.strip_invisible(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT regexp_replace(p, '[\u00AD\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]', '', 'g');
$function$;
REVOKE ALL ON FUNCTION private.strip_invisible(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.strip_invisible(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.strip_html_users()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.display_name IS NOT NULL THEN
    NEW.display_name := private.strip_invisible(regexp_replace(NEW.display_name, '<[^>]*>', '', 'g'));
  END IF;
  IF NEW.bio IS NOT NULL THEN
    NEW.bio := private.strip_invisible(regexp_replace(NEW.bio, '<[^>]*>', '', 'g'));
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.strip_html_tags()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.title IS NOT NULL THEN
    NEW.title := private.strip_invisible(regexp_replace(NEW.title, '<[^>]*>', '', 'g'));
  END IF;
  IF NEW.description IS NOT NULL THEN
    NEW.description := private.strip_invisible(regexp_replace(NEW.description, '<[^>]*>', '', 'g'));
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.strip_html_messages()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.content := private.strip_invisible(regexp_replace(NEW.content, '<[^>]*>', '', 'g'));
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.strip_html_reviews()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.body IS NOT NULL THEN
    NEW.body := private.strip_invisible(regexp_replace(NEW.body, '<[^>]*>', '', 'g'));
  END IF;
  IF NEW.pro_reply IS NOT NULL THEN
    NEW.pro_reply := private.strip_invisible(regexp_replace(NEW.pro_reply, '<[^>]*>', '', 'g'));
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sanitize_notif_text(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT substring(
    private.strip_invisible(regexp_replace(
      regexp_replace(coalesce(p, ''), '<[^>]*>', '', 'g'),
      '[\x00-\x1F\x7F]', '', 'g'
    ))
    FROM 1 FOR 200
  );
$function$;

-- Existing texts (a re-save through the triggers above).
SELECT set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET display_name = display_name, bio = bio
WHERE display_name ~ '[\u00AD\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]'
   OR bio ~ '[\u00AD\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]';
UPDATE public.activities SET title = title, description = description
WHERE title ~ '[\u00AD\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]'
   OR description ~ '[\u00AD\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]';
SELECT set_config('junto.bypass_lock', 'false', true);
