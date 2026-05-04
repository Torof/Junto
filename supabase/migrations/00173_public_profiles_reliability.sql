-- Migration 00173: expose reliability_score on the public_profiles view.
--
-- The trust pillar (profile screen) already shows another user's
-- reliability tier — it's a deliberately public signal, the whole
-- premise of "trust strangers to do outdoor activities together"
-- depends on others being able to read it before committing.
--
-- The Organisation tab's GroupCard wants to render a tier ring around
-- each driver's avatar so the trust signal reaches the actual decision
-- point ("ride with this stranger?"). Per CLAUDE.md, JOINs against
-- user data must go through public_profiles, so the score belongs on
-- this view rather than via a per-driver RPC.
--
-- Strictly additive: existing columns kept in original order so
-- CREATE OR REPLACE VIEW preserves all existing dependents (JOINs in
-- other views, RPC reads). Existing GRANTs survive REPLACE.

CREATE OR REPLACE VIEW public_profiles AS
SELECT
  id,
  display_name,
  avatar_url,
  bio,
  sports,
  levels_per_sport,
  created_at,
  reliability_score
FROM users
WHERE suspended_at IS NULL;
