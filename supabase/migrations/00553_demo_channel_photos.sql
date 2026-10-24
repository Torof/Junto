-- ============================================================================
-- 00553 — A photo for each demo channel (Scott 2026-10-24). Public-domain /
-- CC0 pictures (Openverse: Wikimedia, Flickr PDM, rawpixel CC0), uploaded to
-- channel-photos/demo/. The host comes from private.project_url(), never
-- written here. photo_url is pinned by the channels trigger, hence the bypass.
-- ============================================================================

DO $$
DECLARE
  v_base text := private.project_url() || '/storage/v1/object/public/channel-photos/demo/demo-channel-';
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE public.channels c
  SET photo_url = v_base || right(c.conversation_id::text, 1) || '.jpg'
  WHERE c.is_demo
    AND c.conversation_id IN (
      'cc000000-0000-4000-a000-000000000001', 'cc000000-0000-4000-a000-000000000002',
      'cc000000-0000-4000-a000-000000000003', 'cc000000-0000-4000-a000-000000000004',
      'cc000000-0000-4000-a000-000000000005', 'cc000000-0000-4000-a000-000000000006',
      'cc000000-0000-4000-a000-000000000007', 'cc000000-0000-4000-a000-000000000008',
      'cc000000-0000-4000-a000-000000000009');
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;
