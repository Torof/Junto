-- Invisible and direction characters stripped from EVERY user-typed text shown
-- to others (lot B1 of the 2026-10-23 sweep). 00532 covered users, outings,
-- messages, reviews and (00540) offerings; the pro page, channel / group names,
-- availabilities, seat and invitation messages, place names and the rest kept
-- U+202E & co — a pro or channel name could still spoof text in lists.
-- One generic trigger, column list in its arguments.

CREATE OR REPLACE FUNCTION private.strip_invisible_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_row jsonb := to_jsonb(NEW);
  v_patch jsonb := '{}'::jsonb;
  v_col text;
BEGIN
  FOR i IN 0 .. TG_NARGS - 1 LOOP
    v_col := TG_ARGV[i];
    IF v_row ->> v_col IS NOT NULL THEN
      v_patch := v_patch || jsonb_build_object(v_col, private.strip_invisible(v_row ->> v_col));
    END IF;
  END LOOP;
  IF v_patch <> '{}'::jsonb THEN
    NEW := jsonb_populate_record(NEW, v_patch);
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.strip_invisible_columns() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER activities_strip_invisible
  BEFORE INSERT OR UPDATE OF cancelled_reason, objective_name, meeting_name, meeting_locality ON public.activities
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('cancelled_reason', 'objective_name', 'meeting_name', 'meeting_locality');

CREATE TRIGGER bookings_strip_invisible
  BEFORE INSERT OR UPDATE OF manual_name, message ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('manual_name', 'message');

CREATE TRIGGER channels_strip_invisible
  BEFORE INSERT OR UPDATE OF base_label, description ON public.channels
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('base_label', 'description');

CREATE TRIGGER conversations_strip_invisible
  BEFORE INSERT OR UPDATE OF request_message, name ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('request_message', 'name');

CREATE TRIGGER discovery_availabilities_strip_invisible
  BEFORE INSERT OR UPDATE OF base_label, about ON public.discovery_availabilities
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('base_label', 'about');

CREATE TRIGGER gpx_traces_strip_invisible
  BEFORE INSERT OR UPDATE OF name ON public.gpx_traces
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('name');

CREATE TRIGGER participations_strip_invisible
  BEFORE INSERT OR UPDATE OF left_reason, transport_from_name, invite_message, transport_from_locality ON public.participations
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('left_reason', 'transport_from_name', 'invite_message', 'transport_from_locality');

CREATE TRIGGER pro_profiles_strip_invisible
  BEFORE INSERT OR UPDATE OF display_name, company_name, tagline, description, primary_location_name ON public.pro_profiles
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('display_name', 'company_name', 'tagline', 'description', 'primary_location_name');

CREATE TRIGGER reports_strip_invisible
  BEFORE INSERT OR UPDATE OF reason ON public.reports
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('reason');

CREATE TRIGGER seat_requests_strip_invisible
  BEFORE INSERT OR UPDATE OF pickup_from, message ON public.seat_requests
  FOR EACH ROW EXECUTE FUNCTION private.strip_invisible_columns('pickup_from', 'message');

-- Existing rows: a no-op update lets the trigger clean them.
SELECT set_config('junto.bypass_lock', 'true', true);
UPDATE public.activities SET cancelled_reason = cancelled_reason WHERE concat_ws(' ', cancelled_reason, objective_name, meeting_name, meeting_locality) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
UPDATE public.bookings SET manual_name = manual_name WHERE concat_ws(' ', manual_name, message) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
UPDATE public.channels SET base_label = base_label WHERE concat_ws(' ', base_label, description) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
UPDATE public.conversations SET request_message = request_message WHERE concat_ws(' ', request_message, name) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
UPDATE public.discovery_availabilities SET base_label = base_label WHERE concat_ws(' ', base_label, about) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
UPDATE public.gpx_traces SET name = name WHERE concat_ws(' ', name) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
UPDATE public.participations SET left_reason = left_reason WHERE concat_ws(' ', left_reason, transport_from_name, invite_message, transport_from_locality) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
UPDATE public.pro_profiles SET display_name = display_name WHERE concat_ws(' ', display_name, company_name, tagline, description, primary_location_name) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
UPDATE public.reports SET reason = reason WHERE concat_ws(' ', reason) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
UPDATE public.seat_requests SET pickup_from = pickup_from WHERE concat_ws(' ', pickup_from, message) ~ '[­​‎‏‪-‮⁠-⁤⁦-⁩﻿]';
SELECT set_config('junto.bypass_lock', 'false', true);
