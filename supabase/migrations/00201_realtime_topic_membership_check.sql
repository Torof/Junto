-- Migration 00201: gate activity:* broadcast subscribers to participants/creator.
--
-- Audit pass 2 / M-2: 00183 created a permissive realtime.messages
-- SELECT policy — `realtime.topic() LIKE 'activity:%'` — which let
-- ANY authenticated user subscribe to ANY activity:<id> topic and
-- receive the {table, op} ping stream. No row data leaks (the
-- payload is just metadata) but the timing/event stream itself is
-- a leak: an attacker who knows an activity_id can detect
-- participant joins/leaves and seat-request churn in real time.
-- The 00183 comment explicitly flagged this as a "future hardening
-- pass". This is that pass.
--
-- New policy: same `LIKE 'activity:%'` topic-shape gate, AND the
-- caller must be either an accepted participant of the activity
-- whose UUID is encoded in the topic, or the activity's creator.
-- Mirrors the existing participations SELECT policy (00004) so the
-- realtime authorisation aligns with the data-layer authorisation.
--
-- UUIDs are compared as text to skip an explicit cast — the LIKE
-- guard ensures we only run the EXISTS for topics matching
-- 'activity:<something>'. For non-UUID suffixes (malformed topics)
-- both EXISTS clauses return false and the read is denied, which
-- is the correct fallback.
--
-- Performance: a per-event EXISTS on participations or activities,
-- both indexed on the predicate columns. Low-volume pre-launch
-- traffic; revisit if subscriber count grows.

DROP POLICY IF EXISTS "realtime_activity_topics_read" ON realtime.messages;
CREATE POLICY "realtime_activity_topics_read"
  ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (
    realtime.topic() LIKE 'activity:%'
    AND (
      EXISTS (
        SELECT 1 FROM public.participations p
        WHERE p.activity_id::text = substring(realtime.topic(), 10)
          AND p.user_id = auth.uid()
          AND p.status = 'accepted'
      )
      OR EXISTS (
        SELECT 1 FROM public.activities a
        WHERE a.id::text = substring(realtime.topic(), 10)
          AND a.creator_id = auth.uid()
      )
    )
  );
