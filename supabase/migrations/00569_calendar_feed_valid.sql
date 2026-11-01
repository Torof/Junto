-- The feed answers 404 to an unknown or regenerated token (the subscribed
-- calendar then shows the link is dead) — edge-only check, service_role.
CREATE OR REPLACE FUNCTION public.calendar_feed_valid(p_token text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT p_token ~ '^[0-9a-f]{64}$' AND EXISTS (
    SELECT 1 FROM private.pro_calendar_links l
    JOIN pro_profiles pp ON pp.user_id = l.pro_id AND pp.status = 'approved'
    JOIN users u ON u.id = l.pro_id AND u.suspended_at IS NULL AND u.tier = 'pro'
    WHERE l.export_token = p_token
  );
$$;

REVOKE ALL ON FUNCTION public.calendar_feed_valid(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calendar_feed_valid(text) TO service_role;
