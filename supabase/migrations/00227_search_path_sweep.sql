-- Migration 00227: drop unnecessary `, extensions` from search_path on
-- 17 RPCs that don't actually call any extension-schema function.
-- From the parallel security audit NIT list.
--
-- SECURITY.md "SECURITY DEFINER" prescribes `SET search_path = public`
-- as the default. Adding `, extensions` is only justified when the
-- function body calls PostGIS (ST_*), pgcrypto, etc. Several RPCs
-- carried `, extensions` despite never using anything from there —
-- inconsistent with the documented baseline and with the cleaner
-- pattern already applied in 00200.
--
-- Functions retaining `, extensions` (verified to call ST_* / geometry
-- / geography casts):
--   - check_alerts_for_activity      (ST_DWithin)
--   - confirm_presence_via_geo       (ST_X / ST_Y / ST_DWithin)
--   - create_activity                (ST_GeomFromText / location_start)
--   - create_alert                   (ST_GeomFromText)
--   - get_my_active_presence_activities (ST_X / ST_Y on location_*)
--   - update_activity                (ST_GeomFromText)
--
-- Plus `transition_activity_status` left alone here — a separate
-- migration may drop it entirely if confirmed unused (legacy from
-- 00035 superseded by transition_single_activity + cron).
--
-- Using ALTER FUNCTION ... SET search_path = public so we don't have
-- to recopy every body verbatim.

ALTER FUNCTION public.accept_participation(p_participation_id uuid)
  SET search_path = public;

ALTER FUNCTION public.cancel_activity(p_activity_id uuid, p_reason text)
  SET search_path = public;

ALTER FUNCTION public.check_activity_transitions()
  SET search_path = public;

ALTER FUNCTION public.confirm_presence_via_token(p_token text, p_skip_push boolean)
  SET search_path = public;

ALTER FUNCTION public.create_presence_token(p_activity_id uuid)
  SET search_path = public;

ALTER FUNCTION public.join_activity(p_activity_id uuid)
  SET search_path = public;

ALTER FUNCTION public.leave_activity(p_activity_id uuid, p_reason text)
  SET search_path = public;

ALTER FUNCTION public.notify_participant_joined(
  p_creator_id uuid,
  p_activity_id uuid,
  p_joiner_name text,
  p_activity_title text
) SET search_path = public;

ALTER FUNCTION public.push_notification_to_device()
  SET search_path = public;

ALTER FUNCTION public.refuse_participation(p_participation_id uuid)
  SET search_path = public;

ALTER FUNCTION public.remove_participant(p_participation_id uuid)
  SET search_path = public;

ALTER FUNCTION public.send_private_message(
  p_conversation_id uuid,
  p_content text,
  p_reply_to_message_id uuid
) SET search_path = public;

ALTER FUNCTION public.share_activity_message(p_conversation_id uuid, p_activity_id uuid)
  SET search_path = public;

ALTER FUNCTION public.share_trace_message(
  p_conversation_id uuid,
  p_trace_geojson jsonb,
  p_name text
) SET search_path = public;

ALTER FUNCTION public.transition_single_activity(p_activity_id uuid)
  SET search_path = public;

ALTER FUNCTION public.transition_statuses_only()
  SET search_path = public;

ALTER FUNCTION public.waive_late_cancel_penalty(p_participation_id uuid)
  SET search_path = public;
