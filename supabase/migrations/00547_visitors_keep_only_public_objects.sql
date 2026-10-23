-- A visitor without an account keeps read access to the public objects only
-- (lot B5 of the 2026-10-23 sweep): the outings map, the offerings map, the
-- sports list and the gear catalogue. The other SELECT grants on user-data
-- tables were inherited leftovers — RLS refused every row, but one future
-- policy written « TO public » would have opened them. The definer views keep
-- working: they read the base tables with their owner's rights.
-- Also drops the authenticated UPDATE grant on reports, dead since 00527
-- (moderation goes through moderate_report only).

REVOKE SELECT ON
  public.activity_alerts, public.activity_gear, public.app_config, public.blocked_users,
  public.notifications, public.offering_reviews, public.participations, public.presence_tokens,
  public.pro_offering_photos, public.pro_offerings, public.pro_profile_photos, public.pro_reviews,
  public.push_tokens, public.reports, public.reputation_votes, public.seat_requests,
  public.user_badge_progression,
  public.my_activities, public.my_joined_activities, public.my_pending_activities
FROM anon;

REVOKE UPDATE ON public.reports FROM authenticated;
