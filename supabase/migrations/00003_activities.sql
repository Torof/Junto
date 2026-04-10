-- Migration 00003: activities table + triggers
-- NOTE: SELECT RLS policy deferred to migration 00005 (requires participations table)

CREATE TABLE activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sport_id UUID NOT NULL REFERENCES sports(id) ON DELETE RESTRICT,
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 100),
  description TEXT CHECK (char_length(description) <= 2000),
  level TEXT NOT NULL,
  max_participants INTEGER NOT NULL CHECK (max_participants BETWEEN 2 AND 50),
  location_start GEOGRAPHY(Point, 4326) NOT NULL,
  location_meeting GEOGRAPHY(Point, 4326),
  route GEOGRAPHY(LineString, 4326),
  starts_at TIMESTAMPTZ NOT NULL,
  duration INTERVAL NOT NULL CHECK (duration >= INTERVAL '15 minutes'),
  visibility TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'approval', 'private_link', 'private_link_approval')),
  invite_token UUID DEFAULT gen_random_uuid() NOT NULL,
  status TEXT NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'in_progress', 'completed', 'cancelled', 'expired')),
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX activities_location_start_idx ON activities USING GIST (location_start);

ALTER TABLE activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE activities FORCE ROW LEVEL SECURITY;

-- UPDATE: creator only (lock trigger protects privileged + locked fields)
CREATE POLICY "activities_update_creator"
  ON activities FOR UPDATE
  TO authenticated
  USING (auth.uid() = creator_id)
  WITH CHECK (auth.uid() = creator_id);

-- INSERT: no client policy — via create_activity function only
-- DELETE: no client policy — cancel only, CASCADE on user deletion
-- SELECT: deferred to migration 00005

-- ============================================================================
-- TRIGGER: handle_activity_update — whitelist protection + auto updated_at
-- ============================================================================
CREATE OR REPLACE FUNCTION handle_activity_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  NEW.creator_id := OLD.creator_id;
  NEW.status := OLD.status;
  NEW.invite_token := OLD.invite_token;
  NEW.created_at := OLD.created_at;

  -- Conditional lock deferred: participations table referenced at runtime only
  -- Safe because no data exists at migration time
  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_start := OLD.location_start;
    NEW.location_meeting := OLD.location_meeting;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION handle_activity_update() FROM anon, authenticated;

CREATE TRIGGER on_activity_update
  BEFORE UPDATE ON activities
  FOR EACH ROW EXECUTE FUNCTION handle_activity_update();

-- ============================================================================
-- HTML STRIP TRIGGER
-- ============================================================================
CREATE OR REPLACE FUNCTION strip_html_tags()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.title IS NOT NULL THEN
    NEW.title := regexp_replace(NEW.title, '<[^>]*>', '', 'g');
  END IF;
  IF NEW.description IS NOT NULL THEN
    NEW.description := regexp_replace(NEW.description, '<[^>]*>', '', 'g');
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION strip_html_tags() FROM anon, authenticated;

CREATE TRIGGER activities_strip_html
  BEFORE INSERT OR UPDATE ON activities
  FOR EACH ROW EXECUTE FUNCTION strip_html_tags();
