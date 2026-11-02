-- Participant-form reminders (Scott 2026-11-02): the pro needs shoe sizes,
-- heights and weights early enough to prepare the gear — the eve-of-outing
-- reminder (00567) comes too late for that.
--   · client, 18 h Paris, 3 days before an accepted booking whose group form
--     is incomplete → opens the form;
--   · pro, 9 h Paris, 2 days before, ONE notification per outing (offering +
--     day + half-day) counting the missing forms, manual bookings included.
-- Only offerings that ask for something (std or custom fields). The fixed
-- hour + fixed day offset make each reminder fire once per booking / outing.
-- create_notification honours preferences and skips suspended accounts.

CREATE OR REPLACE FUNCTION private.notify_booking_forms_reminders()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_bk RECORD;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 18 THEN RETURN; END IF;

  FOR v_bk IN
    SELECT b.id, b.client_id, b.day, b.period, po.title, pp.display_name AS pro_name
    FROM bookings b
    JOIN pro_offerings po ON po.id = b.offering_id
    LEFT JOIN public_profiles pp ON pp.id = b.pro_id
    WHERE b.status = 'accepted' AND b.client_id IS NOT NULL
      AND b.day = private.today_paris() + 3
      AND coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
          + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
      AND coalesce(jsonb_array_length(b.participant_info), 0) < b.party_size
  LOOP
    PERFORM create_notification(
      v_bk.client_id,
      'booking_forms_reminder',
      'Fiche du groupe à compléter',
      coalesce(v_bk.pro_name, 'Le professionnel') || ' attend les infos de ton groupe pour « '
        || coalesce(v_bk.title, 'ta sortie') || ' » (' || to_char(v_bk.day, 'DD/MM') || ').',
      jsonb_build_object('booking_id', v_bk.id,
        'params', jsonb_build_object('title', coalesce(v_bk.title, ''), 'name', coalesce(v_bk.pro_name, ''),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION private.notify_booking_forms_reminders() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.notify_booking_forms_missing()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row RECORD;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 9 THEN RETURN; END IF;

  FOR v_row IN
    SELECT b.pro_id, b.offering_id, b.day, b.period, po.title,
           sum(greatest(b.party_size - coalesce(jsonb_array_length(b.participant_info), 0), 0))::INTEGER AS missing,
           sum(b.party_size)::INTEGER AS total
    FROM bookings b
    JOIN pro_offerings po ON po.id = b.offering_id
    WHERE b.status = 'accepted'
      AND b.day = private.today_paris() + 2
      AND coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
          + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
    GROUP BY b.pro_id, b.offering_id, b.day, b.period, po.title
    HAVING sum(greatest(b.party_size - coalesce(jsonb_array_length(b.participant_info), 0), 0)) > 0
  LOOP
    PERFORM create_notification(
      v_row.pro_id,
      'booking_forms_missing',
      'Il manque des infos',
      '« ' || coalesce(v_row.title, 'Ta sortie') || ' » (' || to_char(v_row.day, 'DD/MM') || ') : '
        || v_row.missing || ' fiche' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END
        || ' participant manquante' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END
        || ' sur ' || v_row.total || '.',
      jsonb_build_object('offering_id', v_row.offering_id,
        'params', jsonb_build_object('title', coalesce(v_row.title, ''), 'date', to_char(v_row.day, 'YYYY-MM-DD'),
                                     'period', v_row.period, 'count', v_row.missing, 'total', v_row.total))
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION private.notify_booking_forms_missing() FROM PUBLIC, anon, authenticated;

-- pg_cron runs in UTC: both possible UTC hours, the function keeps the right one.
SELECT cron.schedule('junto-booking-forms-reminders', '0 16,17 * * *', 'SELECT private.notify_booking_forms_reminders();');
SELECT cron.schedule('junto-booking-forms-missing', '0 7,8 * * *', 'SELECT private.notify_booking_forms_missing();');
