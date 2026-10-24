-- ============================================================================
-- 00550 — Demo channels (Scott 2026-10-24): nine lively discussion channels
-- around Briançon, Gap and Grenoble, filled by the demo users, behind the
-- same curtain as every other demo object (visible only to an admin with the
-- demo mode on — demo_content_visible()).
--
--   (1) channels.is_demo (privileged, pinned by the whitelist trigger).
--   (2) private.demo_channel_hidden(conversation): a demo channel while the
--       curtain is down. Wired into the ONE membership gate every message
--       path uses (is_conversation_member → messages RLS, send / share / edit
--       / delete, wall reads), the realtime conversation topic, and the channel
--       read RPCs (search, detail, roster, join) + get_my_conversations.
--   (3) admin_set_demo_mode: turning the demo on slides each demo channel's
--       messages so its last one reads as recent (the outings are re-dated
--       the same way).
--   (4) The nine channels, their members and their conversations
--       (push off while seeding: junto.skip_message_push).
-- All rebuilt from their live definitions; CREATE OR REPLACE keeps grants.
-- ============================================================================

ALTER TABLE public.channels ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION private.demo_channel_hidden(p_conversation_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT EXISTS (SELECT 1 FROM channels c WHERE c.conversation_id = p_conversation_id AND c.is_demo)
     AND NOT demo_content_visible();
$function$;
-- Called from the realtime policy, evaluated as the client role.
GRANT EXECUTE ON FUNCTION private.demo_channel_hidden(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.channels_whitelist_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.conversation_id := OLD.conversation_id;
  NEW.sport_key := OLD.sport_key;
  NEW.base := OLD.base;
  NEW.base_label := OLD.base_label;
  NEW.radius_km := OLD.radius_km;
  NEW.photo_url := OLD.photo_url;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  NEW.is_demo := OLD.is_demo;  -- 00550
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.is_conversation_member(p_conversation_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM conversation_members
    WHERE conversation_id = p_conversation_id AND user_id = p_user_id
  )
  -- 00514: a suspended account reads no conversation any more.
  AND NOT private.user_is_suspended(p_user_id)
  -- 00550: a demo channel is nobody's conversation while the curtain is down.
  AND NOT private.demo_channel_hidden(p_conversation_id);
$function$;

CREATE OR REPLACE FUNCTION public.search_channels(p_query text DEFAULT NULL::text, p_sport_key text DEFAULT NULL::text, p_near_lng double precision DEFAULT NULL::double precision, p_near_lat double precision DEFAULT NULL::double precision)
 RETURNS TABLE(conversation_id uuid, name text, sport_key text, base_label text, radius_km integer, description text, photo_url text, distance_km double precision, member_count integer, is_member boolean, is_creator boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_near GEOGRAPHY;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  -- 00499 (AB-14): bounded query.
  IF p_query IS NOT NULL AND char_length(p_query) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_near := CASE WHEN p_near_lng IS NOT NULL AND p_near_lat IS NOT NULL
                 THEN ST_SetSRID(ST_MakePoint(p_near_lng, p_near_lat), 4326)::geography END;

  RETURN QUERY
  SELECT c.conversation_id, conv.name, c.sport_key, c.base_label, c.radius_km, c.description, c.photo_url,
         CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) / 1000.0 END AS distance_km,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id) AS member_count,
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id) AS is_member,
         (c.created_by = v_user_id) AS is_creator
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.closed_at IS NULL
    AND (NOT c.is_demo OR demo_content_visible())  -- 00550
    AND (p_sport_key IS NULL OR p_sport_key = c.sport_key)
    AND (p_query IS NULL
         OR conv.name ILIKE '%' || p_query || '%'
         OR c.base_label ILIKE '%' || p_query || '%'
         OR c.sport_key ILIKE '%' || p_query || '%'
         OR coalesce(c.description, '') ILIKE '%' || p_query || '%')
    AND (v_near IS NULL OR ST_DWithin(c.base, v_near, c.radius_km * 1000.0))
    AND NOT EXISTS (SELECT 1 FROM channel_bans b WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id)
  ORDER BY
    CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) END ASC NULLS LAST,
    (SELECT count(*) FROM conversation_members m WHERE m.conversation_id = c.conversation_id) DESC,
    c.created_at DESC
  LIMIT 60;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_channel(p_conversation_id uuid)
 RETURNS TABLE(conversation_id uuid, name text, sport_key text, base_lng double precision, base_lat double precision, base_label text, radius_km integer, description text, photo_url text, member_count integer, is_member boolean, is_creator boolean, is_closed boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.conversation_id, conv.name, c.sport_key,
         ST_X(c.base::geometry), ST_Y(c.base::geometry), c.base_label, c.radius_km,
         c.description, c.photo_url,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id),
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id),
         (c.created_by = v_user_id),
         (c.closed_at IS NOT NULL)
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.conversation_id = p_conversation_id
    AND (NOT c.is_demo OR demo_content_visible())  -- 00550
    AND NOT EXISTS (
      SELECT 1 FROM channel_bans b
      WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_channel_members(p_conversation_id uuid)
 RETURNS TABLE(user_id uuid, display_name text, avatar_url text, reliability_tier text, is_creator boolean, joined_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  -- Channel must exist; caller must be a member to see the roster.
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF private.demo_channel_hidden(p_conversation_id) THEN RETURN; END IF;  -- 00550
  IF NOT EXISTS (
    SELECT 1 FROM conversation_members m
    WHERE m.conversation_id = p_conversation_id AND m.user_id = v_user_id
  ) THEN RETURN; END IF;

  RETURN QUERY
  SELECT m.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         (m.user_id = v_creator) AS is_creator, m.joined_at
  FROM conversation_members m
  JOIN public_profiles pp ON pp.id = m.user_id
  WHERE m.conversation_id = p_conversation_id
    -- 00546: someone the viewer blocked leaves their roster (their messages are
    -- already hidden), except for the creator, who must still be able to ban them.
    AND (v_user_id = v_creator OR NOT EXISTS (
      SELECT 1 FROM blocked_users b WHERE b.blocker_id = v_user_id AND b.blocked_id = m.user_id))
  ORDER BY (m.user_id = v_creator) DESC, m.joined_at ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.join_channel(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_ch RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Serialize against remove_channel_member so a ban-check + INSERT can't
  -- interleave with a DELETE + ban INSERT (no member+banned state).
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_channel_members'));

  SELECT c.conversation_id, c.closed_at INTO v_ch
  FROM channels c WHERE c.conversation_id = p_conversation_id;
  IF v_ch.conversation_id IS NULL OR v_ch.closed_at IS NOT NULL
     OR private.demo_channel_hidden(p_conversation_id) THEN  -- 00550
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM channel_bans WHERE conversation_id = p_conversation_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00514 (MS-6): bounded discussions (each message fans out to every member).
  IF (SELECT count(*) FROM conversation_members WHERE conversation_id = p_conversation_id) >= 500 THEN
    RAISE EXCEPTION 'junto.channel_full';
  END IF;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (p_conversation_id, v_user_id, NULL, now())
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_conversations()
 RETURNS TABLE(id uuid, type text, status text, last_message_at timestamp with time zone, created_at timestamp with time zone, last_message_content text, last_message_sender_id uuid, last_message_metadata jsonb, is_unread boolean, user_1 uuid, user_2 uuid, other_user_id uuid, other_user_name text, other_user_avatar text, other_user_reliability_tier text, name text, icon text, member_count integer, activity_id uuid, activity_title text, sport_id uuid, photo_url text, initiated_from text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    c.id, c.type, c.status, c.last_message_at, c.created_at,
    lm.content, lm.sender_id, lm.metadata,
    EXISTS (
      SELECT 1 FROM messages m
      WHERE m.conversation_id = c.id
        AND m.deleted_at IS NULL
        AND m.sender_id IS DISTINCT FROM auth.uid()
        AND private.message_author_visible(c.id, m.sender_id, auth.uid())
        AND (me.last_read_at IS NULL OR m.created_at > me.last_read_at)
    ) AS is_unread,
    c.user_1, c.user_2,
    CASE WHEN c.type = 'dm' THEN (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END) END,
    CASE WHEN c.type = 'dm' THEN COALESCE(pp.display_name, '?') END,
    CASE WHEN c.type = 'dm' THEN pp.avatar_url END,
    CASE WHEN c.type = 'dm' THEN pp.reliability_tier END,
    CASE WHEN c.type IN ('group', 'channel') THEN c.name END,
    CASE WHEN c.type = 'group' THEN c.icon END,
    CASE WHEN c.type IN ('group', 'channel') THEN (SELECT count(*)::int FROM conversation_members gm WHERE gm.conversation_id = c.id) END,
    CASE WHEN c.type = 'activity' THEN c.activity_id END,
    CASE WHEN c.type = 'activity' THEN act.title END,
    CASE WHEN c.type = 'activity' THEN act.sport_id WHEN c.type = 'channel' THEN cs.id END,
    CASE WHEN c.type = 'channel' THEN ch.photo_url END,
    CASE WHEN c.type = 'dm' THEN c.initiated_from END
  FROM conversations c
  JOIN conversation_members me
    ON me.conversation_id = c.id AND me.user_id = auth.uid() AND me.hidden_at IS NULL
  LEFT JOIN public_profiles pp
    ON c.type = 'dm' AND pp.id = (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END)
  LEFT JOIN activities act
    ON c.type = 'activity' AND act.id = c.activity_id
  LEFT JOIN channels ch
    ON c.type = 'channel' AND ch.conversation_id = c.id
  LEFT JOIN sports cs
    ON ch.sport_key IS NOT NULL AND cs.key = ch.sport_key
  LEFT JOIN LATERAL (
    SELECT m.content, m.sender_id, m.metadata
    FROM messages m
    WHERE m.conversation_id = c.id AND m.deleted_at IS NULL
      AND private.message_author_visible(m.conversation_id, m.sender_id, auth.uid())
    ORDER BY m.created_at DESC LIMIT 1
  ) lm ON TRUE
  WHERE auth.uid() IS NOT NULL
    AND NOT private.user_is_suspended(auth.uid())  -- 00515: suspended → nothing
    AND (
      (c.type = 'dm' AND c.status = 'active'
        AND NOT EXISTS (
          SELECT 1 FROM blocked_users b
          WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
             OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
        ))
      OR c.type = 'group'
      OR (c.type = 'channel' AND (NOT coalesce(ch.is_demo, false) OR demo_content_visible()))  -- 00550
      OR (c.type = 'activity'
          AND act.id IS NOT NULL
          AND act.deleted_at IS NULL
          AND act.is_demo = (SELECT u.is_demo FROM users u WHERE u.id = auth.uid())
          AND (act.status IN ('published', 'in_progress')
               OR act.starts_at > now() - INTERVAL '30 days'))
    )
  ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
$function$;

DROP POLICY IF EXISTS realtime_conversation_topics_read ON realtime.messages;
CREATE POLICY realtime_conversation_topics_read ON realtime.messages AS PERMISSIVE FOR SELECT TO authenticated USING (
  (realtime.topic() ~~ 'conversation:%'::text)
  AND (EXISTS (SELECT 1 FROM conversation_members cm
               WHERE (cm.conversation_id)::text = substring(realtime.topic(), 14)
                 AND cm.user_id = auth.uid()
                 AND NOT private.demo_channel_hidden(cm.conversation_id)))  -- 00550
  AND (NOT private.user_is_suspended(auth.uid()))
);

CREATE OR REPLACE FUNCTION public.admin_set_demo_mode(p_on boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_admin uuid;
  v_base GEOGRAPHY;
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
  v_sports TEXT[];
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE app_config SET value = CASE WHEN p_on THEN 'true' ELSE 'false' END
  WHERE name = 'demo_mode';

  IF p_on THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);

    -- Showcase demo activities only → future dates. The completed HISTORY
    -- (c0000000-…, feeds the rich profiles) is excluded by UUID range so it can
    -- never be dragged into the re-date pool (a status-only guard traps it).
    WITH ordered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM activities
      WHERE is_demo = true AND deleted_at IS NULL AND id::text NOT LIKE 'c0000000-%'
    ),
    target AS (
      SELECT a.id, a.starts_at AS old_start,
             date_trunc('day', now())
               + make_interval(
                   days  => (1 + ((o.rn - 1) / 2))::int, -- 00457 : deux sorties par jour (50 sorties → 25 jours)
                   hours => (ARRAY[9,14,8,16,10,17,11,15])[((o.rn - 1) % 8) + 1],
                   mins  => (ARRAY[0,30,15,0,45,30,0,30])[((o.rn - 1) % 8) + 1]
                 ) AS new_start
      FROM activities a JOIN ordered o ON o.id = a.id
    ),
    -- Carpool departures and pickups follow their outing (same snapshot).
    shifted_transport AS (
      UPDATE participations p
      SET transport_departs_at = p.transport_departs_at + (t.new_start - t.old_start)
      FROM target t
      WHERE p.activity_id = t.id AND p.transport_departs_at IS NOT NULL
      RETURNING p.id
    ),
    shifted_pickups AS (
      UPDATE seat_requests s
      SET requested_pickup_at = s.requested_pickup_at + (t.new_start - t.old_start)
      FROM target t
      WHERE s.activity_id = t.id AND s.requested_pickup_at IS NOT NULL
      RETURNING s.id
    )
    UPDATE activities a
    SET starts_at = t.new_start, status = 'published'
    FROM target t
    WHERE a.id = t.id;

    -- Demo dispos: each partner keeps ONE of the admin's sports (rotation →
    -- every card matches) + up to 2 of its own flavor sports, on a varied
    -- sub-window of the admin's window, with varied radius/offset per partner.
    SELECT d.base, d.window_start, d.window_end, d.sport_keys
      INTO v_base, v_ws, v_we, v_sports
    FROM discovery_availabilities d
    WHERE d.user_id = v_admin AND d.is_active AND d.is_demo = false;

    IF v_base IS NOT NULL THEN
      WITH ordered AS (
        SELECT id, user_id, row_number() OVER (ORDER BY user_id) AS rn
        FROM discovery_availabilities WHERE is_demo = true
      ),
      flavors(user_id, extras) AS (VALUES
        ('d0000000-0000-4000-a000-000000000002'::uuid, ARRAY['trail-running','hiking']),
        ('d0000000-0000-4000-a000-000000000003'::uuid, ARRAY['climbing-sport','bouldering']),
        ('d0000000-0000-4000-a000-000000000004'::uuid, ARRAY['climbing-multipitch','mountaineering']),
        ('d0000000-0000-4000-a000-000000000005'::uuid, ARRAY['paragliding','hiking']),
        ('d0000000-0000-4000-a000-000000000006'::uuid, ARRAY['via-ferrata','canyoning']),
        ('d0000000-0000-4000-a000-000000000007'::uuid, ARRAY['mtb-enduro','gravel']),
        ('d0000000-0000-4000-a000-000000000008'::uuid, ARRAY['trail-running','running']),
        ('d0000000-0000-4000-a000-000000000009'::uuid, ARRAY['windsurfing','swimming'])
      )
      UPDATE discovery_availabilities dd
      SET sport_keys = (
            ARRAY[v_sports[((o.rn - 1) % cardinality(v_sports)) + 1]]
            || array_remove(COALESCE(f.extras, '{}'::text[]),
                            v_sports[((o.rn - 1) % cardinality(v_sports)) + 1])
          )[1:3],
          window_start = v_ws + (v_we - v_ws)
            * ((ARRAY[0,2,1,3,0,2,1,3])[((o.rn - 1) % 8) + 1] / 10.0),
          window_end   = v_we - (v_we - v_ws)
            * ((ARRAY[0,1,2,0,3,1,0,2])[((o.rn - 1) % 8) + 1] / 10.0),
          radius_km    = (ARRAY[30,50,15,NULL,50,10,30,15])[((o.rn - 1) % 8) + 1],
          base = ST_SetSRID(ST_MakePoint(
                   ST_X(v_base::geometry) + (ARRAY[0.06,0.13,-0.08,0.10,-0.12,0.15,0.04,-0.05])[((o.rn - 1) % 8) + 1],
                   ST_Y(v_base::geometry) + (ARRAY[0.00,0.03,-0.02,0.05,0.02,0.01,-0.04,0.04])[((o.rn - 1) % 8) + 1]),
                 4326)::geography,
          is_active = true
      FROM ordered o
      LEFT JOIN flavors f ON f.user_id = o.user_id
      WHERE dd.id = o.id;
    END IF;

    -- 00550: demo channels stay alive — each one's messages slide so its last
    -- message reads as recent (a few hours apart from one channel to the next).
    WITH ranked AS (
      SELECT c.conversation_id, row_number() OVER (ORDER BY c.created_at, c.conversation_id) AS rn
      FROM channels c WHERE c.is_demo
    ), shift AS (
      SELECT r.conversation_id,
             (now() - make_interval(mins => (25 + (r.rn::int * 97) % 600))) - max(m.created_at) AS d
      FROM ranked r JOIN messages m ON m.conversation_id = r.conversation_id
      GROUP BY r.conversation_id, r.rn
    )
    UPDATE messages m SET created_at = m.created_at + s.d
    FROM shift s WHERE m.conversation_id = s.conversation_id;
    UPDATE conversations cv
    SET last_message_at = (SELECT max(m.created_at) FROM messages m WHERE m.conversation_id = cv.id)
    WHERE cv.id IN (SELECT conversation_id FROM channels WHERE is_demo);
  END IF;

  PERFORM log_admin_action(
    v_admin,
    CASE WHEN p_on THEN 'demo_mode_on' ELSE 'demo_mode_off' END,
    'app_config', NULL, NULL, NULL
  );
END;
$function$;
DO $seed$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  PERFORM set_config('junto.skip_message_push', 'true', true);


  -- 1 · Peaux de phoque & poudreuse · Briançonnais
  INSERT INTO conversations (id, type, status, name, created_by, created_at, last_message_at)
  VALUES ('cc000000-0000-4000-a000-000000000001', 'channel', 'active', 'Peaux de phoque & poudreuse · Briançonnais', 'd0000000-0000-4000-a000-000000000013', now() - INTERVAL '214 hours', now() - INTERVAL '6 hours');
  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at, is_demo)
  VALUES ('cc000000-0000-4000-a000-000000000001', 'ski-touring', extensions.ST_SetSRID(extensions.ST_MakePoint(6.6436, 44.8986), 4326)::extensions.geography, 'Briançon', 60,
          'Skis de rando autour de Briançon : conditions du jour, risque d''avalanche, binômes pour partir tôt. Débutants bienvenus, DVA-pelle-sonde obligatoires.', 'd0000000-0000-4000-a000-000000000013', now() - INTERVAL '214 hours', true);
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at) VALUES
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000013', NULL, now() - INTERVAL '214 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000002', NULL, now() - INTERVAL '212 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-00000000000c', NULL, now() - INTERVAL '211 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000006', NULL, now() - INTERVAL '210 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000003', NULL, now() - INTERVAL '209 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000008', NULL, now() - INTERVAL '208 hours');
  INSERT INTO messages (conversation_id, sender_id, content, created_at) VALUES
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000013', 'Salut à tous ! Ici on se cale des sorties en peaux autour de Briançon. Petite règle de la maison : on donne toujours le BRA du jour avant de proposer un itinéraire.', now() - INTERVAL '190 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-00000000000c', 'Top ! Quelqu''un est allé voir du côté de Névache ? Il paraît que ça a bien tenu au-dessus de 2000.', now() - INTERVAL '170 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000002', 'J''y étais avant-hier, belle neige sur les versants nord, croûté au sud dès 11 h. Départ tôt conseillé.', now() - INTERVAL '166 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000006', 'Je débute un peu en rando, quelqu''un serait partant pour une sortie tranquille, 800 m de D+ max ?', now() - INTERVAL '120 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000013', 'Avec plaisir Léa. Le Col de Buffère c''est parfait pour ça, pente douce et peu exposé. On peut faire ça samedi matin.', now() - INTERVAL '117 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000003', 'Je me greffe ! Je peux prendre deux personnes en voiture depuis Montgenèvre.', now() - INTERVAL '90 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000008', 'Attention, risque 3 annoncé pour ce week-end après la chute de neige. On reste sur du raisonnable.', now() - INTERVAL '60 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-00000000000c', 'Bien vu. Je propose qu''on fasse un petit exercice DVA au parking avant de partir, ça ne fait jamais de mal.', now() - INTERVAL '55 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000006', 'Super, je n''ai jamais fait d''exercice de recherche, ça me rassure. Je prends ma sonde toute neuve 😄', now() - INTERVAL '30 hours'),
    ('cc000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000013', 'Parfait. Rendez-vous 7 h 30 au parking de Névache samedi, on regarde le BRA vendredi soir pour confirmer.', now() - INTERVAL '6 hours');

  -- 2 · Les mouillés de la Haute-Durance
  INSERT INTO conversations (id, type, status, name, created_by, created_at, last_message_at)
  VALUES ('cc000000-0000-4000-a000-000000000002', 'channel', 'active', 'Les mouillés de la Haute-Durance', 'd0000000-0000-4000-a000-000000000015', now() - INTERVAL '234 hours', now() - INTERVAL '20 hours');
  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at, is_demo)
  VALUES ('cc000000-0000-4000-a000-000000000002', 'canyoning', extensions.ST_SetSRID(extensions.ST_MakePoint(6.556, 44.79), 4326)::extensions.geography, 'L''Argentière-la-Bessée', 60,
          'Canyons du Fournel, du Rif Bel, de Saint-Pierre… On partage niveaux d''eau, cordes et voitures de navette.', 'd0000000-0000-4000-a000-000000000015', now() - INTERVAL '234 hours', true);
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at) VALUES
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000015', NULL, now() - INTERVAL '234 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000006', NULL, now() - INTERVAL '232 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000004', NULL, now() - INTERVAL '231 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-00000000000b', NULL, now() - INTERVAL '230 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000017', NULL, now() - INTERVAL '229 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000009', NULL, now() - INTERVAL '228 hours');
  INSERT INTO messages (conversation_id, sender_id, content, created_at) VALUES
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000015', 'Bienvenue chez les mouillés ! On parle canyons de la vallée : niveaux d''eau, matos, navettes.', now() - INTERVAL '210 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-00000000000b', 'Le Fournel coule comment en ce moment ? Je le connais seulement en plein été.', now() - INTERVAL '205 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000015', 'Débit correct, l''eau est fraîche, combinaison 5 mm obligatoire. Les toboggans du bas sont superbes.', now() - INTERVAL '200 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000004', 'Je cherche du monde pour le Rif Bel, j''ai deux cordes de 60 m et les kits.', now() - INTERVAL '150 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000017', 'Partant ! Je n''ai jamais fait le Rif Bel, il y a des rappels guidés ?', now() - INTERVAL '146 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000004', 'Deux ou trois, rien de très engagé. Le plus long fait 25 m.', now() - INTERVAL '143 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000009', 'Je peux faire la navette avec mon van, il y a 6 places.', now() - INTERVAL '80 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000006', 'Génial Camille ! Je prends les longes et le kit pharma.', now() - INTERVAL '72 hours'),
    ('cc000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000015', 'Petite info : orages annoncés jeudi, on évite les canyons à bassin versant large ce jour-là. Prudence.', now() - INTERVAL '20 hours');

  -- 3 · Trail à la frontale · Briançon
  INSERT INTO conversations (id, type, status, name, created_by, created_at, last_message_at)
  VALUES ('cc000000-0000-4000-a000-000000000003', 'channel', 'active', 'Trail à la frontale · Briançon', 'd0000000-0000-4000-a000-000000000008', now() - INTERVAL '254 hours', now() - INTERVAL '36 hours');
  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at, is_demo)
  VALUES ('cc000000-0000-4000-a000-000000000003', 'trail-running', extensions.ST_SetSRID(extensions.ST_MakePoint(6.6436, 44.8986), 4326)::extensions.geography, 'Briançon', 35,
          'Sorties trail avant le boulot ou à la tombée de la nuit, à la frontale. Tous rythmes, on attend au sommet.', 'd0000000-0000-4000-a000-000000000008', now() - INTERVAL '254 hours', true);
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at) VALUES
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000008', NULL, now() - INTERVAL '254 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000002', NULL, now() - INTERVAL '252 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-00000000000a', NULL, now() - INTERVAL '251 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000018', NULL, now() - INTERVAL '250 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-00000000000e', NULL, now() - INTERVAL '249 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000016', NULL, now() - INTERVAL '248 hours');
  INSERT INTO messages (conversation_id, sender_id, content, created_at) VALUES
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000008', 'Le principe : on court quand les autres dorment 😄 Sorties tôt le matin ou en soirée, frontale obligatoire.', now() - INTERVAL '230 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-00000000000a', 'J''adore l''idée. Le tour du fort des Têtes à la frontale, ça vous dit ?', now() - INTERVAL '224 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000002', 'Carrément, 12 km et 600 m de D+, parfait pour une sortie du soir.', now() - INTERVAL '221 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000018', 'Je suis en vacances à Briançon deux semaines, je ne connais personne, je peux me joindre à vous ?', now() - INTERVAL '180 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000008', 'Bien sûr Hanna, c''est exactement pour ça que le canal existe ! Mardi soir 19 h devant la collégiale.', now() - INTERVAL '178 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-00000000000e', 'Je viendrai aussi, mais je cours plus lentement, ça va aller ?', now() - INTERVAL '100 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000016', 'Pas de souci, on se regroupe à chaque intersection. Personne ne reste derrière.', now() - INTERVAL '97 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000008', 'Retour de mardi : 7 coureurs, coucher de soleil sur la Meije en prime. On remet ça jeudi ?', now() - INTERVAL '40 hours'),
    ('cc000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-00000000000a', 'Jeudi oui ! Je ramène des barres à partager.', now() - INTERVAL '36 hours');

  -- 4 · Grimpe au soleil à Céüse
  INSERT INTO conversations (id, type, status, name, created_by, created_at, last_message_at)
  VALUES ('cc000000-0000-4000-a000-000000000004', 'channel', 'active', 'Grimpe au soleil à Céüse', 'd0000000-0000-4000-a000-000000000011', now() - INTERVAL '284 hours', now() - INTERVAL '24 hours');
  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at, is_demo)
  VALUES ('cc000000-0000-4000-a000-000000000004', 'climbing-sport', extensions.ST_SetSRID(extensions.ST_MakePoint(5.95, 44.505), 4326)::extensions.geography, 'Céüse', 60,
          'Pour ceux qui cherchent un binôme en falaise, du 5 au 7, et les infos conditions du moment à Céüse et autour de Gap.', 'd0000000-0000-4000-a000-000000000011', now() - INTERVAL '284 hours', true);
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at) VALUES
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000011', NULL, now() - INTERVAL '284 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000003', NULL, now() - INTERVAL '282 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000004', NULL, now() - INTERVAL '281 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000017', NULL, now() - INTERVAL '280 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000010', NULL, now() - INTERVAL '279 hours');
  INSERT INTO messages (conversation_id, sender_id, content, created_at) VALUES
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000011', 'Salut la team ! Céüse, Sigottier, Orpierre… on se trouve des binômes et on partage les conditions.', now() - INTERVAL '260 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000003', 'Céüse en ce moment c''est sec et frais le matin, parfait. Le soleil arrive vers 13 h sur la face sud.', now() - INTERVAL '255 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000010', 'Je grimpe dans le 6a/6b, je cherche quelqu''un pour la secteur Biographie cette semaine. La marche d''approche m''effraie un peu 😅', now() - INTERVAL '190 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000004', 'Compte 1 h de marche tranquille. Je viens mercredi si tu veux, on peut faire quelques longueurs ensemble.', now() - INTERVAL '187 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000017', 'Info : le parking du Cédé est en travaux, garez-vous plus bas.', now() - INTERVAL '140 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000011', 'Quelqu''un a une corde de 80 m ? Les voies du Biographie en ont souvent besoin.', now() - INTERVAL '85 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000003', 'J''en ai une, je la prête volontiers.', now() - INTERVAL '82 hours'),
    ('cc000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000010', 'Grosse journée mercredi avec Julie, mon premier 6b à Céüse ! Merci le canal 🙏', now() - INTERVAL '24 hours');

  -- 5 · On se jette à l'eau · canyons du Gapençais
  INSERT INTO conversations (id, type, status, name, created_by, created_at, last_message_at)
  VALUES ('cc000000-0000-4000-a000-000000000005', 'channel', 'active', 'On se jette à l''eau · canyons du Gapençais', 'd0000000-0000-4000-a000-00000000000b', now() - INTERVAL '324 hours', now() - INTERVAL '48 hours');
  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at, is_demo)
  VALUES ('cc000000-0000-4000-a000-000000000005', 'canyoning', extensions.ST_SetSRID(extensions.ST_MakePoint(6.0786, 44.5594), 4326)::extensions.geography, 'Gap', 60,
          'Canyons du Gapençais, du Dévoluy et du Buëch. On s''organise pour les navettes et on partage les sauts qui valent le coup.', 'd0000000-0000-4000-a000-00000000000b', now() - INTERVAL '324 hours', true);
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at) VALUES
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-00000000000b', NULL, now() - INTERVAL '324 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000015', NULL, now() - INTERVAL '322 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000006', NULL, now() - INTERVAL '321 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000009', NULL, now() - INTERVAL '320 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000012', NULL, now() - INTERVAL '319 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000016', NULL, now() - INTERVAL '318 hours');
  INSERT INTO messages (conversation_id, sender_id, content, created_at) VALUES
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-00000000000b', 'Bienvenue ! Ici on parle canyons autour de Gap : Infernet, la Pisse, les Gillardes…', now() - INTERVAL '300 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000012', 'Les Gillardes c''est accessible pour quelqu''un qui débute ?', now() - INTERVAL '294 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000015', 'Oui, c''est un très bon premier canyon, quelques sauts optionnels et peu de rappels.', now() - INTERVAL '291 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000009', 'Je propose une sortie aux Gillardes dimanche, il reste 3 places. Départ 9 h de Gap.', now() - INTERVAL '230 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000016', 'Je prends une place ! Je n''ai pas de combinaison, on peut en louer sur place ?', now() - INTERVAL '226 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-00000000000b', 'À Saint-Étienne-en-Dévoluy oui, prévois la réservation la veille.', now() - INTERVAL '224 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000006', 'Petit rappel sécurité : on ne saute jamais sans avoir sondé, même si on connaît le canyon.', now() - INTERVAL '150 hours'),
    ('cc000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000012', 'Je me suis lancée aux Gillardes avec Camille, quelle journée ! Prochaine étape : l''Infernet ?', now() - INTERVAL '48 hours');

  -- 6 · Thermiques & décos du Gapençais
  INSERT INTO conversations (id, type, status, name, created_by, created_at, last_message_at)
  VALUES ('cc000000-0000-4000-a000-000000000006', 'channel', 'active', 'Thermiques & décos du Gapençais', 'd0000000-0000-4000-a000-000000000005', now() - INTERVAL '304 hours', now() - INTERVAL '30 hours');
  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at, is_demo)
  VALUES ('cc000000-0000-4000-a000-000000000006', 'paragliding', extensions.ST_SetSRID(extensions.ST_MakePoint(6.0786, 44.5594), 4326)::extensions.geography, 'Gap', 60,
          'Parapente autour de Gap : météo aéro, décos qui marchent, navettes et covoit vers Saint-Vincent, Aujour et Charance.', 'd0000000-0000-4000-a000-000000000005', now() - INTERVAL '304 hours', true);
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at) VALUES
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000005', NULL, now() - INTERVAL '304 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000010', NULL, now() - INTERVAL '302 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000014', NULL, now() - INTERVAL '301 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-00000000000f', NULL, now() - INTERVAL '300 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-00000000000e', NULL, now() - INTERVAL '299 hours');
  INSERT INTO messages (conversation_id, sender_id, content, created_at) VALUES
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000005', 'Salut les volants ! Ici on se coordonne pour les vols autour de Gap : météo, décos, navettes.', now() - INTERVAL '280 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000010', 'Saint-Vincent-les-Forts demain ? Les modèles annoncent des thermiques propres dès midi.', now() - INTERVAL '276 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000005', 'Bonne idée, vent faible d''ouest, ça devrait bien monter. Je fais la navette.', now() - INTERVAL '273 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-00000000000f', 'Je suis élève en progression, je peux vous suivre en restant prudent ?', now() - INTERVAL '200 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000010', 'Bien sûr ! Reste sur les conditions du matin et on fait un debrief après.', now() - INTERVAL '197 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000014', 'Charance était magique ce soir, restitution de fin de journée au-dessus de Gap 😍', now() - INTERVAL '130 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-00000000000e', 'Je ne vole pas encore mais j''ai très envie de faire un baptême, vous avez une école à conseiller ?', now() - INTERVAL '125 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000005', 'Plusieurs écoles sur Gap et Serre-Ponçon, dis-moi en privé, je te donne quelques noms.', now() - INTERVAL '122 hours'),
    ('cc000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-00000000000f', 'Premier vol de plus d''une heure aujourd''hui grâce à vos conseils, merci !', now() - INTERVAL '30 hours');

  -- 7 · Les grimpeurs du dimanche · Chartreuse & Vercors
  INSERT INTO conversations (id, type, status, name, created_by, created_at, last_message_at)
  VALUES ('cc000000-0000-4000-a000-000000000007', 'channel', 'active', 'Les grimpeurs du dimanche · Chartreuse & Vercors', 'd0000000-0000-4000-a000-000000000017', now() - INTERVAL '344 hours', now() - INTERVAL '35 hours');
  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at, is_demo)
  VALUES ('cc000000-0000-4000-a000-000000000007', 'climbing-sport', extensions.ST_SetSRID(extensions.ST_MakePoint(5.7245, 45.1885), 4326)::extensions.geography, 'Grenoble', 60,
          'Grimpe en falaise autour de Grenoble — Chartreuse, Vercors, Belledonne. Sortie du dimanche, binômes, topos et covoit depuis Grenoble.', 'd0000000-0000-4000-a000-000000000017', now() - INTERVAL '344 hours', true);
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at) VALUES
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000017', NULL, now() - INTERVAL '344 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000011', NULL, now() - INTERVAL '342 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000003', NULL, now() - INTERVAL '341 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000014', NULL, now() - INTERVAL '340 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-00000000000d', NULL, now() - INTERVAL '339 hours');
  INSERT INTO messages (conversation_id, sender_id, content, created_at) VALUES
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000017', 'Bienvenue aux grimpeurs du dimanche ! On s''organise pour les falaises autour de Grenoble.', now() - INTERVAL '320 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000014', 'Quelqu''un connaît les Rochers de Presles ? On m''a dit que c''était magnifique mais engagé.', now() - INTERVAL '316 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000017', 'Magnifique oui, mais vise les voies équipées récemment, les vieilles sont exigeantes. Comptez 6a minimum.', now() - INTERVAL '312 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-00000000000d', 'Je viens d''arriver à Grenoble, je grimpe en salle, je cherche quelqu''un pour une première en falaise.', now() - INTERVAL '240 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000011', 'Viens avec nous dimanche à Comboire, c''est parfait pour débuter dehors, et c''est à 10 min de la ville.', now() - INTERVAL '236 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000003', 'Je descends de Montgenèvre le week-end prochain, je covoiture volontiers depuis Briançon.', now() - INTERVAL '160 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-00000000000d', 'Comboire c''était top ! J''ai enfin compris comment faire un relais. Merci la team.', now() - INTERVAL '90 hours'),
    ('cc000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000017', 'Dimanche prochain : Saint-Égrève, rendez-vous 9 h au parking. Qui est chaud ?', now() - INTERVAL '35 hours');

  -- 8 · Belledonne en peaux, départ à l'aube
  INSERT INTO conversations (id, type, status, name, created_by, created_at, last_message_at)
  VALUES ('cc000000-0000-4000-a000-000000000008', 'channel', 'active', 'Belledonne en peaux, départ à l''aube', 'd0000000-0000-4000-a000-00000000000c', now() - INTERVAL '364 hours', now() - INTERVAL '60 hours');
  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at, is_demo)
  VALUES ('cc000000-0000-4000-a000-000000000008', 'ski-touring', extensions.ST_SetSRID(extensions.ST_MakePoint(5.875, 45.12), 4326)::extensions.geography, 'Chamrousse', 60,
          'Ski de rando dans Belledonne : départs à l''aube, pentes nord, sommets autour de Chamrousse et du Pleynet.', 'd0000000-0000-4000-a000-00000000000c', now() - INTERVAL '364 hours', true);
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at) VALUES
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-00000000000c', NULL, now() - INTERVAL '364 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000013', NULL, now() - INTERVAL '362 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000002', NULL, now() - INTERVAL '361 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000014', NULL, now() - INTERVAL '360 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000018', NULL, now() - INTERVAL '359 hours');
  INSERT INTO messages (conversation_id, sender_id, content, created_at) VALUES
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-00000000000c', 'Hello ! Ici on part tôt et on redescend avant que ça transforme. Belledonne et alentours.', now() - INTERVAL '340 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000013', 'La Croix de Chamrousse au lever du soleil, c''est un classique qu''on devrait faire ensemble.', now() - INTERVAL '336 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000014', 'Je suis snowboardeuse, je viens de passer au splitboard, ça vous dérange ?', now() - INTERVAL '330 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-00000000000c', 'Pas du tout, au contraire ! Les splits sont les bienvenus.', now() - INTERVAL '327 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000018', 'Quel est le bon niveau pour le Grand Colon ? Je fais du 1000 m de D+ sans problème.', now() - INTERVAL '260 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000013', 'Le Grand Colon est assez long, plutôt 1500 m. Fais d''abord la Croix de Belledonne en vacances.', now() - INTERVAL '255 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000002', 'Retour du Pleynet : neige froide au nord, croûte au sud dès 10 h. Partez tôt !', now() - INTERVAL '180 hours'),
    ('cc000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-00000000000c', 'Sortie samedi 6 h depuis Chamrousse, 3 places dans ma voiture depuis Grenoble.', now() - INTERVAL '60 hours');

  -- 9 · Vercors en baudrier mouillé
  INSERT INTO conversations (id, type, status, name, created_by, created_at, last_message_at)
  VALUES ('cc000000-0000-4000-a000-000000000009', 'channel', 'active', 'Vercors en baudrier mouillé', 'd0000000-0000-4000-a000-000000000012', now() - INTERVAL '384 hours', now() - INTERVAL '50 hours');
  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at, is_demo)
  VALUES ('cc000000-0000-4000-a000-000000000009', 'canyoning', extensions.ST_SetSRID(extensions.ST_MakePoint(5.553, 45.07), 4326)::extensions.geography, 'Villard-de-Lans', 60,
          'Canyons du Vercors : Écouges, Furon, Bruyant… Sorties à la journée, navettes et partage du matériel.', 'd0000000-0000-4000-a000-000000000012', now() - INTERVAL '384 hours', true);
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at) VALUES
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000012', NULL, now() - INTERVAL '384 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000015', NULL, now() - INTERVAL '382 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-00000000000b', NULL, now() - INTERVAL '381 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000009', NULL, now() - INTERVAL '380 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000017', NULL, now() - INTERVAL '379 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-00000000000f', NULL, now() - INTERVAL '378 hours');
  INSERT INTO messages (conversation_id, sender_id, content, created_at) VALUES
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000012', 'Salut à tous ! Le Vercors regorge de canyons, on s''organise ici pour y aller ensemble.', now() - INTERVAL '360 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000015', 'Le Furon c''est génial en fin d''été, l''eau est bonne et il y a pas mal de sauts.', now() - INTERVAL '354 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-00000000000f', 'Je n''ai jamais fait de canyon, le Furon c''est raisonnable pour un premier ?', now() - INTERVAL '300 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000012', 'Oui, la partie basse est parfaite pour débuter. On t''emmène !', now() - INTERVAL '297 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000017', 'Attention, les Écouges ont des rappels plus techniques, ne le faites qu''avec un encadrant expérimenté.', now() - INTERVAL '220 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-00000000000b', 'Je peux encadrer les Écouges le week-end prochain, j''ai fait la formation SNC cette année.', now() - INTERVAL '150 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000009', 'Je viens ! Je fais la navette, mon van est garé au départ.', now() - INTERVAL '145 hours'),
    ('cc000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000012', 'Belle sortie au Furon avec Rémi pour son baptême de canyon. Il est déjà accro 😄', now() - INTERVAL '50 hours');
END $seed$;
