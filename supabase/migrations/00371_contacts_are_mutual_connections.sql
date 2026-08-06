-- ============================================================================
-- 00371 — Contacts = mutual connections (Brique 5).
--
-- Retires the one-way roster (00341 add_contact): a contact could be added
-- without consent, and "Mes contacts" was asymmetric. Now a contact ≡ an ACTIVE
-- DM connection (00072, inherently bidirectional). get_contacts reads the
-- connections; get_recent_partners excludes people already connected; removing a
-- contact deletes the shared DM (symmetric, re-requestable). add_contact /
-- remove_contact dropped; the `contacts` table is left orphaned (drop later).
-- ============================================================================

-- 1) get_contacts → accepted mutual connections (active DMs), peer + not blocked.
CREATE OR REPLACE FUNCTION get_contacts()
RETURNS TABLE (id UUID, display_name TEXT, avatar_url TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT pp.id, pp.display_name, pp.avatar_url, c.created_at
  FROM conversations c
  JOIN public_profiles pp
    ON pp.id = CASE WHEN c.user_1 = v_user_id THEN c.user_2 ELSE c.user_1 END
  WHERE c.type = 'dm'
    AND c.status = 'active'
    AND (c.user_1 = v_user_id OR c.user_2 = v_user_id)
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
         OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
    )
  ORDER BY c.created_at DESC;
END;
$$;

-- 2) get_recent_partners → exclude people I'm already CONNECTED with (was: roster).
CREATE OR REPLACE FUNCTION get_recent_partners()
RETURNS TABLE (id UUID, display_name TEXT, avatar_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH my_activities AS (
    SELECT a.id, a.starts_at, a.creator_id
    FROM activities a
    WHERE a.deleted_at IS NULL
      AND a.starts_at <= now()
      AND a.starts_at > now() - INTERVAL '180 days'
      AND (
        a.creator_id = v_user_id
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ),
  partners AS (
    SELECT ma.creator_id AS uid, ma.starts_at AS at
    FROM my_activities ma
    WHERE ma.creator_id <> v_user_id
    UNION ALL
    SELECT p.user_id AS uid, ma.starts_at AS at
    FROM my_activities ma
    JOIN participations p
      ON p.activity_id = ma.id AND p.status = 'accepted' AND p.user_id <> v_user_id
  ),
  ranked AS (
    SELECT uid, max(at) AS last_at
    FROM partners
    GROUP BY uid
  )
  SELECT pp.id, pp.display_name, pp.avatar_url
  FROM ranked r
  JOIN public_profiles pp ON pp.id = r.uid
  WHERE NOT EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.type = 'dm' AND c.status = 'active'
        AND ((c.user_1 = v_user_id AND c.user_2 = r.uid)
          OR (c.user_1 = r.uid AND c.user_2 = v_user_id))
    )
    AND r.uid NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id)
    AND r.uid NOT IN (SELECT blocker_id FROM blocked_users WHERE blocked_id = v_user_id)
  ORDER BY r.last_at DESC
  LIMIT 20;
END;
$$;

-- 3) remove_connection → delete the shared active DM (symmetric; CASCADE members
--    + messages; the pair-unique index frees so they can re-request later).
CREATE OR REPLACE FUNCTION remove_connection(p_other_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  DELETE FROM conversations
  WHERE type = 'dm'
    AND status = 'active'
    AND ((user_1 = v_user_id AND user_2 = p_other_user_id)
      OR (user_1 = p_other_user_id AND user_2 = v_user_id));
END;
$$;

REVOKE ALL ON FUNCTION remove_connection(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_connection(UUID) TO authenticated;

-- 4) Retire the one-way roster functions (table left orphaned, drop later).
DROP FUNCTION IF EXISTS add_contact(UUID);
DROP FUNCTION IF EXISTS remove_contact(UUID);
