-- ============================================================================
-- 00392 — Give the 3 Discovery demo partners a reliability score + a real
-- portrait, so the match cards demo the ReliabilityRing + avatar convincingly.
--
-- reliability_score is a privileged/computed column (frozen by the users
-- whitelist trigger) → set under bypass_lock. reliability_tier is derived from
-- it by public_profiles, so setting the score is enough. avatar_url is ordinary
-- profile content but set in the same bypass block. Varied tiers on purpose
-- (excellent / good / fair) for a richer demo.
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE public.users AS u
  SET reliability_score = v.score,
      avatar_url        = v.avatar
  FROM (VALUES
    ('d0000000-0000-4000-a000-000000000002'::uuid, 82::float, 'https://randomuser.me/api/portraits/women/44.jpg'), -- Marie L. → good
    ('d0000000-0000-4000-a000-000000000003'::uuid, 94::float, 'https://randomuser.me/api/portraits/men/32.jpg'),   -- Thomas B. → excellent
    ('d0000000-0000-4000-a000-000000000006'::uuid, 68::float, 'https://randomuser.me/api/portraits/women/68.jpg')  -- Léa M. → fair
  ) AS v(id, score, avatar)
  WHERE u.id = v.id;
END $$;
