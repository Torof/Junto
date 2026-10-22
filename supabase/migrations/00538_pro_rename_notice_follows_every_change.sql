-- 00538 — every rename of an approved pro page reaches the admins
-- (audit 2026-10-23, messaging/pro F4).
--
-- The one-notice-a-day throttle (00522 F6) hid a second rename: « Guide Alpha
-- → Guide Beta » stayed the only notice while the page now said something
-- else. Notifications cannot be edited (handle_notification_update pins every
-- column), so the day's notice is REPLACED: deleted, then re-created as
-- « first name of the day → current name » (fresh, unread, pushed). Renaming
-- back to the morning's name simply clears the notice. Still one notice per pro
-- and admin at a time.

CREATE OR REPLACE FUNCTION private.notify_pro_renamed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_admin UUID;
  v_first TEXT;
  v_new TEXT;
BEGIN
  IF NEW.status <> 'approved' OR NEW.display_name IS NOT DISTINCT FROM OLD.display_name THEN RETURN NULL; END IF;
  v_new := sanitize_notif_text(coalesce(NEW.display_name, '?'));
  FOR v_admin IN SELECT id FROM users WHERE is_admin AND suspended_at IS NULL LOOP
    v_first := NULL;
    -- The day's notice, if any: keep its starting name, replace it.
    DELETE FROM notifications n
    WHERE n.id = (SELECT n2.id FROM notifications n2
                  WHERE n2.user_id = v_admin AND n2.type = 'pro_renamed'
                    AND n2.data->>'pro_id' = NEW.user_id::text AND n2.created_at > now() - INTERVAL '1 day'
                  ORDER BY n2.created_at DESC LIMIT 1)
    RETURNING n.data->'params'->>'old' INTO v_first;
    v_first := coalesce(v_first, sanitize_notif_text(coalesce(OLD.display_name, '?')));
    CONTINUE WHEN v_first = v_new;  -- back to the day's first name: nothing to report
    PERFORM create_notification(v_admin, 'pro_renamed', 'Vitrine pro renommée',
      v_first || ' → ' || v_new,
      jsonb_build_object('pro_id', NEW.user_id, 'params', jsonb_build_object('old', v_first, 'new', v_new)));
  END LOOP;
  RETURN NULL;
END;
$function$;
