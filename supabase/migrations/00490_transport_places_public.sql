-- ============================================================================
-- 00490 — Résumé covoiturage : retour des lieux de départ pour tous (décision
-- Scott). On sait d'où partent les voitures, pas qui : le détail transport par
-- personne est masqué pour les non-membres dans la liste des participants.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_transport_summary(p_activity_id uuid)
 RETURNS TABLE(transport_type text, count integer, total_seats integer, cities text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
      AND (a.is_demo = false OR demo_content_visible())
      AND (
        a.visibility IN ('public', 'approval')
        OR a.creator_id = v_user_id
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_is_member := EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.creator_id = v_user_id)
    OR EXISTS (SELECT 1 FROM participations p WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id AND p.status = 'accepted');

  RETURN QUERY
  SELECT
    p.transport_type,
    count(*)::int AS count,
    COALESCE(sum(p.transport_seats)::int, 0) AS total_seats,
    -- 00490 (Scott): where the cars leave from is what makes someone join
    -- (« a car leaves from my town »), so every viewer of the outing sees the
    -- places — never WHO leaves from where (per-person transport is masked
    -- for non-members in get_activity_participants). Never across a block.
    array_agg(DISTINCT p.transport_from_name) FILTER (
      WHERE p.transport_from_name IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM blocked_users b
          WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
             OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id))) AS cities
  FROM participations p
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.transport_type IS NOT NULL
  GROUP BY p.transport_type
  ORDER BY count DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_activity_participants(p_activity_id uuid)
 RETURNS TABLE(participation_id uuid, activity_id uuid, user_id uuid, status text, created_at timestamp with time zone, left_at timestamp with time zone, confirmed_present boolean, transport_type text, transport_seats smallint, transport_from_name text, transport_departs_at timestamp with time zone, transport_from_lat double precision, transport_from_lng double precision, display_name text, avatar_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_creator BOOLEAN;
  v_is_member BOOLEAN;
  v_live BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      -- 00472 (audit L3): the demo curtain, like every other read surface.
      AND (a.is_demo = false OR demo_content_visible())
      AND (
        a.visibility IN ('public', 'approval')
        OR a.creator_id = v_user_id
        -- 00485 (AC-2): only an ACCEPTED participant, not a removed / left one.
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ) THEN
    RETURN;
  END IF;

  SELECT a.creator_id = v_user_id, a.status IN ('published', 'in_progress')
    INTO v_is_creator, v_live
  FROM activities a WHERE a.id = p_activity_id;
  v_is_member := v_is_creator OR EXISTS (
    SELECT 1 FROM participations p
    WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id AND p.status = 'accepted');

  RETURN QUERY
  SELECT
    p.id AS participation_id,
    p.activity_id,
    p.user_id,
    p.status,
    p.created_at,
    p.left_at,
    -- 00485 (DX-1): an absence is shown only to the organiser and to the
    -- person concerned; everyone else sees « present » or nothing.
    CASE WHEN p.user_id = v_user_id OR v_is_creator THEN p.confirmed_present
         -- 00488: only fellow members see « present » (once an outing is
         -- finalised, a missing tick would otherwise read as an absence).
         WHEN v_is_member AND p.confirmed_present THEN true ELSE NULL END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_type END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_seats END,
    -- 00485 (AC-2): a driver's starting point (often home) is shown only to
    -- the outing's accepted members, while it is upcoming / under way, and
    -- never across a block.
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_name END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_departs_at END,
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lat END,
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lng END,
    pp.display_name,
    pp.avatar_url
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
  ORDER BY p.created_at;
END;
$function$;
