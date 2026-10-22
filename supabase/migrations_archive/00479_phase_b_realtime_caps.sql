-- ============================================================================
-- 00479 — Phase B : les deux failles HIGH restantes + AB-10.
--
-- AB-3  Plafonds quotidiens : 500 messages / 24 h par compte ; 20 traces et 50
--       sorties partagées / 24 h ; taille d'une trace partagée bornée (MS-7).
-- AB-2  Carte : `activities` et `participations` ne sont plus publiées en
--       postgres_changes (chaque carte ouverte recevait chaque modification de
--       chaque sortie). À la place, un signal SANS CONTENU sur le canal privé
--       `map` (comptes connectés), au plus une fois toutes les 15 s par sortie,
--       seulement pour les sorties publiques / sur demande non démo, et seulement
--       quand un champ visible sur la carte change ou qu'une place se prend /
--       se libère. Identité de réplication de `activities` revenue à DEFAULT.
-- AB-10 Matériel : `activity_gear` et `activity_gear_missing` passent sur le
--       canal privé de la sortie (`activity:<id>`, déjà réservé aux participants)
--       au lieu de postgres_changes, dont les suppressions ne se filtrent pas.
-- ============================================================================

CREATE INDEX IF NOT EXISTS messages_sender_created_idx ON messages (sender_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.send_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_other UUID;
  v_count INTEGER;
  v_limit INTEGER;
  v_msg_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, type, status, user_1, user_2, activity_id INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_conv.type = 'dm' THEN
    IF v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_other := CASE WHEN v_conv.user_1 = v_user_id THEN v_conv.user_2 ELSE v_conv.user_1 END;
    -- Peer must exist and not be suspended (parity with old send_private_message).
    IF EXISTS (SELECT 1 FROM users WHERE id = v_other AND suspended_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_other)
         OR (blocker_id = v_other AND blocked_id = v_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_limit := 15;
  ELSIF v_conv.type = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = v_conv.activity_id AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_limit := 30;
  ELSE
    v_limit := 30;
  END IF;

  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM messages m
    WHERE m.id = p_reply_to_message_id
      AND m.conversation_id = p_conversation_id AND m.deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_send_message'));
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND conversation_id = p_conversation_id
    AND created_at > now() - INTERVAL '1 minute';
  IF v_count >= v_limit THEN
    IF v_conv.type = 'dm' THEN RAISE EXCEPTION 'junto.dm_rate_limit';
    ELSE RAISE EXCEPTION 'junto.wall_rate_limit'; END IF;
  END IF;
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND created_at > now() - INTERVAL '1 minute';
  IF v_count >= 60 THEN RAISE EXCEPTION 'junto.send_rate_limit'; END IF;
  -- 00479 (AB-3): daily cap — one account could otherwise fill the database
  -- in under a day (60/min × 2000 chars, no daily bound).
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_count >= 500 THEN RAISE EXCEPTION 'junto.message_daily_cap'; END IF;

  INSERT INTO messages (conversation_id, sender_id, content, reply_to_message_id)
  VALUES (p_conversation_id, v_user_id, trim(p_content), p_reply_to_message_id)
  RETURNING id INTO v_msg_id;

  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id AND hidden_at IS NOT NULL;

  RETURN v_msg_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.share_trace_message(p_conversation_id uuid, p_trace_geojson jsonb, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_coord_count INTEGER;
  v_clean_name TEXT;
  v_recent INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.assert_can_send(p_conversation_id, v_user_id);

  IF p_trace_geojson IS NULL
     OR p_trace_geojson->>'type' != 'LineString'
     OR jsonb_typeof(p_trace_geojson->'coordinates') != 'array' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  v_coord_count := jsonb_array_length(p_trace_geojson->'coordinates');
  IF v_coord_count < 2 OR v_coord_count > 10000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- Schema + NUMERIC BOUNDS (design review: 1e300 coords sailed straight into
  -- the map renderer). lon/lat ranges, plausible elevation.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_trace_geojson->'coordinates') AS coord
    WHERE jsonb_typeof(coord) != 'array'
       OR jsonb_array_length(coord) < 2
       OR jsonb_array_length(coord) > 3
       OR jsonb_typeof(coord->0) != 'number'
       OR jsonb_typeof(coord->1) != 'number'
       OR (coord->>0)::numeric < -180 OR (coord->>0)::numeric > 180
       OR (coord->>1)::numeric < -90 OR (coord->>1)::numeric > 90
       OR (jsonb_array_length(coord) = 3 AND (
            jsonb_typeof(coord->2) != 'number'
            OR (coord->>2)::numeric < -500 OR (coord->>2)::numeric > 9000
       ))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := CASE
    WHEN p_name IS NOT NULL AND char_length(trim(p_name)) > 0
    THEN substring(regexp_replace(trim(p_name), '<[^>]*>', '', 'g') from 1 for 100)
    ELSE 'trace.gpx'
  END;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_trace'));
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
    AND created_at > now() - INTERVAL '1 minute';
  IF v_recent >= 1 THEN RAISE EXCEPTION 'junto.share_rate_limit'; END IF;
  -- 00479 (AB-3 / MS-7): daily cap and total size bound (≤ 1 MB, the shared
  -- trace gate used by activities) — numbers of arbitrary precision made
  -- multi-MB messages possible.
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
    AND created_at > now() - INTERVAL '24 hours';
  IF v_recent >= 20 THEN RAISE EXCEPTION 'junto.share_daily_cap'; END IF;
  IF NOT trace_geojson_ok(p_trace_geojson) THEN RAISE EXCEPTION 'junto.trace_geojson_invalid'; END IF;

  RETURN private.insert_rich_message(
    p_conversation_id, v_user_id,
    '🗺️ ' || v_clean_name,
    jsonb_build_object('type', 'shared_trace', 'name', v_clean_name, 'trace_geojson', p_trace_geojson)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.share_activity_message(p_conversation_id uuid, p_activity_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_can_see BOOLEAN;
  v_recent INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.assert_can_send(p_conversation_id, v_user_id);

  SELECT id, title, visibility, deleted_at, creator_id, is_demo, sport_id INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL
     OR (v_activity.is_demo AND NOT demo_content_visible()) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Share gate: public → anyone; private → creator only; approval → participant.
  v_can_see := v_activity.visibility = 'public'
    OR v_activity.creator_id = v_user_id
    OR (
      v_activity.visibility = 'approval'
      AND EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = p_activity_id AND user_id = v_user_id
          AND status IN ('accepted', 'pending')
      )
    );
  IF NOT v_can_see THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Channel sport lock: a channel WITH a sport only accepts activities of that
  -- sport. Sport-less channels (and non-channel conversations) are unrestricted.
  IF EXISTS (
    SELECT 1 FROM channels ch
    WHERE ch.conversation_id = p_conversation_id
      AND ch.sport_key IS NOT NULL
      AND ch.sport_key IS DISTINCT FROM (SELECT s.key FROM sports s WHERE s.id = v_activity.sport_id)
  ) THEN
    RAISE EXCEPTION 'junto.channel_sport_mismatch';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_activity'));
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_activity'
    AND created_at > now() - INTERVAL '1 minute';
  IF v_recent >= 1 THEN RAISE EXCEPTION 'junto.share_rate_limit'; END IF;
  -- 00479 (AB-3): daily cap.
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_activity'
    AND created_at > now() - INTERVAL '24 hours';
  IF v_recent >= 50 THEN RAISE EXCEPTION 'junto.share_daily_cap'; END IF;

  RETURN private.insert_rich_message(
    p_conversation_id, v_user_id,
    '📍 ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g'),
    jsonb_build_object('type', 'shared_activity', 'activity_id', p_activity_id)
  );
END;
$function$;

-- ---------- AB-2 : signal carte ----------
CREATE TABLE IF NOT EXISTS map_broadcasts (
  activity_id UUID PRIMARY KEY,
  at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE map_broadcasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE map_broadcasts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON map_broadcasts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.map_ping(p_activity_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sent INT;
BEGIN
  -- Throttle: at most one signal per outing every 15 s.
  INSERT INTO map_broadcasts (activity_id, at) VALUES (p_activity_id, now())
  ON CONFLICT (activity_id) DO UPDATE SET at = now()
    WHERE map_broadcasts.at < now() - INTERVAL '15 seconds';
  GET DIAGNOSTICS v_sent = ROW_COUNT;
  IF v_sent = 0 THEN RETURN; END IF;
  BEGIN
    PERFORM realtime.send('{}'::jsonb, 'map', 'map', true);
  EXCEPTION WHEN OTHERS THEN NULL; -- never fail the user's write for a ping
  END;
END;
$function$;
REVOKE ALL ON FUNCTION public.map_ping(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.broadcast_map_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.visibility IN ('public', 'approval') AND NOT OLD.is_demo THEN PERFORM map_ping(OLD.id); END IF;
    RETURN NULL;
  END IF;
  IF NEW.is_demo THEN RETURN NULL; END IF;
  IF NOT (NEW.visibility IN ('public', 'approval')
          OR (TG_OP = 'UPDATE' AND OLD.visibility IN ('public', 'approval'))) THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'UPDATE' AND NOT (
       NEW.status IS DISTINCT FROM OLD.status
    OR NEW.starts_at IS DISTINCT FROM OLD.starts_at
    OR NEW.duration IS DISTINCT FROM OLD.duration
    OR NEW.location_meeting IS DISTINCT FROM OLD.location_meeting
    OR NEW.location_objective IS DISTINCT FROM OLD.location_objective
    OR NEW.title IS DISTINCT FROM OLD.title
    OR NEW.max_participants IS DISTINCT FROM OLD.max_participants
    OR NEW.visibility IS DISTINCT FROM OLD.visibility
    OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
    OR NEW.level IS DISTINCT FROM OLD.level
    OR NEW.level_max IS DISTINCT FROM OLD.level_max
    OR NEW.sport_id IS DISTINCT FROM OLD.sport_id
  ) THEN
    RETURN NULL;
  END IF;
  PERFORM map_ping(NEW.id);
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.broadcast_map_activity() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.broadcast_map_participation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_activity UUID;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NULL; END IF;
  v_activity := CASE WHEN TG_OP = 'DELETE' THEN OLD.activity_id ELSE NEW.activity_id END;
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = v_activity
             AND a.visibility IN ('public', 'approval') AND NOT a.is_demo) THEN
    PERFORM map_ping(v_activity);
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.broadcast_map_participation() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_activities_map_broadcast ON activities;
CREATE TRIGGER trg_activities_map_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON activities
  FOR EACH ROW EXECUTE FUNCTION broadcast_map_activity();

DROP TRIGGER IF EXISTS trg_participations_map_broadcast ON participations;
CREATE TRIGGER trg_participations_map_broadcast
  AFTER INSERT OR UPDATE OF status OR DELETE ON participations
  FOR EACH ROW EXECUTE FUNCTION broadcast_map_participation();

DROP POLICY IF EXISTS realtime_map_topic_read ON realtime.messages;
CREATE POLICY realtime_map_topic_read ON realtime.messages
  FOR SELECT TO authenticated
  USING (realtime.topic() = 'map');

-- ---------- AB-10 : matériel sur le canal privé de la sortie ----------
DROP TRIGGER IF EXISTS trg_activity_gear_broadcast ON activity_gear;
CREATE TRIGGER trg_activity_gear_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON activity_gear
  FOR EACH ROW EXECUTE FUNCTION broadcast_activity_change();
DROP TRIGGER IF EXISTS trg_activity_gear_missing_broadcast ON activity_gear_missing;
CREATE TRIGGER trg_activity_gear_missing_broadcast
  AFTER INSERT OR UPDATE OR DELETE ON activity_gear_missing
  FOR EACH ROW EXECUTE FUNCTION broadcast_activity_change();

-- ---------- Publication : plus de postgres_changes pour ces 4 tables ----------
ALTER PUBLICATION supabase_realtime DROP TABLE activities, participations, activity_gear, activity_gear_missing;
ALTER TABLE activities REPLICA IDENTITY DEFAULT;
ALTER TABLE activity_gear REPLICA IDENTITY DEFAULT;
