-- ============================================================================
-- 00481 — Phase B2 (suite) : set_activity_gear insère objet par objet, donc
-- le signal « par instruction » partait encore une fois par objet (vu par le
-- test B2 : 40 objets). Le signal est coupé pendant la réécriture et un seul
-- est envoyé à la fin.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.broadcast_activity_change_stmt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_activity UUID;
BEGIN
  -- 00481: set_activity_gear sends its own single ping.
  IF current_setting('junto.gear_quiet', true) = 'true' THEN RETURN NULL; END IF;
  -- Transition tables only exist for the events that define them: branch on
  -- TG_OP so an INSERT trigger never references old_rows (and vice versa).
  FOR v_activity IN EXECUTE CASE TG_OP
      WHEN 'INSERT' THEN 'SELECT DISTINCT activity_id FROM new_rows WHERE activity_id IS NOT NULL'
      WHEN 'DELETE' THEN 'SELECT DISTINCT activity_id FROM old_rows WHERE activity_id IS NOT NULL'
      ELSE 'SELECT activity_id FROM new_rows WHERE activity_id IS NOT NULL UNION SELECT activity_id FROM old_rows WHERE activity_id IS NOT NULL'
    END
  LOOP
    BEGIN
      PERFORM realtime.send(jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP), 'change', 'activity:' || v_activity::text, true);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_activity_gear(p_activity_id uuid, p_items jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_item JSONB;
  v_name TEXT;
  v_qty INTEGER;
  v_is_shared BOOLEAN;
  v_catalog_is_shared BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('gear', 20, INTERVAL '1 minute');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- H7: cap the array size so a megabyte-sized payload can't blow up
  -- the loop. 50 items is generous for legit use.
  IF jsonb_array_length(p_items) > 50 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00481: the per-item loop below is one INSERT statement per item, so the
  -- statement-level ping fired once per item. Silence it for the rewrite and
  -- send a single ping at the end.
  PERFORM set_config('junto.gear_quiet', 'true', true);
  DELETE FROM activity_gear WHERE activity_id = p_activity_id AND user_id = v_user_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    -- H5c: strip HTML/script tags before storing the user-provided
    -- gear name (catalog items are stored as keys and immune).
    v_name := regexp_replace(trim(v_item->>'name'), '<[^>]*>', '', 'g');
    v_qty := COALESCE((v_item->>'quantity')::integer, 1);

    IF v_name IS NOT NULL AND char_length(v_name) > 0 AND v_qty > 0 THEN
      v_qty := LEAST(v_qty, 99);

      SELECT is_shared INTO v_catalog_is_shared
      FROM gear_catalog WHERE name_key = v_name LIMIT 1;
      v_is_shared := COALESCE(v_catalog_is_shared, (v_item->>'is_shared')::boolean, false);

      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared)
      VALUES (p_activity_id, v_user_id, v_name, v_qty, v_is_shared);
    END IF;
  END LOOP;
  PERFORM set_config('junto.gear_quiet', 'false', true);
  BEGIN
    PERFORM realtime.send(jsonb_build_object('table', 'activity_gear', 'op', 'UPDATE'), 'change', 'activity:' || p_activity_id::text, true);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
$function$;
