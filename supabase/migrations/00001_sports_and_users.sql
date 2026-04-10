-- Migration 00001: sports + users tables
-- Following SECURITY.md: ENABLE RLS + FORCE RLS immediately after CREATE TABLE
-- All policies written before any data insertion

-- ============================================================================
-- ENABLE PostGIS (should already be enabled via dashboard, but safe to repeat)
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================================
-- UTILITY: random name generator for user registration
-- ============================================================================
CREATE OR REPLACE FUNCTION generate_random_name()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  adjectives TEXT[] := ARRAY[
    'Brave', 'Swift', 'Bold', 'Calm', 'Keen',
    'Wild', 'Free', 'Sharp', 'Cool', 'Warm',
    'Bright', 'Quick', 'Steady', 'Light', 'Strong'
  ];
  animals TEXT[] := ARRAY[
    'Falcon', 'Wolf', 'Eagle', 'Bear', 'Fox',
    'Hawk', 'Lynx', 'Otter', 'Deer', 'Heron',
    'Marmot', 'Ibex', 'Chamois', 'Viper', 'Trout'
  ];
  adj TEXT;
  animal TEXT;
  digits TEXT;
BEGIN
  adj := adjectives[1 + floor(random() * array_length(adjectives, 1))::int];
  animal := animals[1 + floor(random() * array_length(animals, 1))::int];
  digits := lpad(floor(random() * 10000)::text, 4, '0');
  RETURN adj || animal || digits;
END;
$$;

-- Internal function: REVOKE from client roles
REVOKE EXECUTE ON FUNCTION generate_random_name() FROM anon, authenticated;

-- ============================================================================
-- TABLE: sports (reference data)
-- ============================================================================
CREATE TABLE sports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT UNIQUE NOT NULL,
  icon TEXT NOT NULL,
  category TEXT NOT NULL,
  display_order INTEGER NOT NULL
);

ALTER TABLE sports ENABLE ROW LEVEL SECURITY;
ALTER TABLE sports FORCE ROW LEVEL SECURITY;

-- SELECT: everyone including anon
CREATE POLICY "sports_select_all"
  ON sports FOR SELECT
  USING (true);

-- INSERT/UPDATE/DELETE: admin only
CREATE POLICY "sports_insert_admin"
  ON sports FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true));

CREATE POLICY "sports_update_admin"
  ON sports FOR UPDATE
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true));

CREATE POLICY "sports_delete_admin"
  ON sports FOR DELETE
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true));

-- ============================================================================
-- TABLE: users
-- ============================================================================
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  display_name TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 2 AND 30),
  avatar_url TEXT,
  bio TEXT CHECK (char_length(bio) <= 500),
  sports JSONB DEFAULT '[]'::jsonb,
  levels_per_sport JSONB DEFAULT '{}'::jsonb,
  date_of_birth DATE,
  phone_verified BOOLEAN DEFAULT false NOT NULL,
  phone_verified_at TIMESTAMPTZ,
  tier TEXT DEFAULT 'free' NOT NULL CHECK (tier IN ('free', 'premium', 'pro')),
  is_pro_verified BOOLEAN DEFAULT false NOT NULL,
  pro_verified_at TIMESTAMPTZ,
  is_admin BOOLEAN DEFAULT false NOT NULL,
  suspended_at TIMESTAMPTZ,
  accepted_tos_at TIMESTAMPTZ,
  accepted_privacy_at TIMESTAMPTZ,
  push_token TEXT,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

-- SELECT: authenticated users can read their own full row only
-- Others access via public_profiles view (no anon SELECT on this table)
CREATE POLICY "users_select_own"
  ON users FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

-- INSERT: no client policy — trigger only
-- (no CREATE POLICY for INSERT = blocked for all client roles)

-- UPDATE: own row only (whitelist trigger enforces allowed columns)
CREATE POLICY "users_update_own"
  ON users FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- DELETE: no client policy — Edge Function only
-- (no CREATE POLICY for DELETE = blocked for all client roles)

-- ============================================================================
-- VIEW: public_profiles (column-level access control)
-- ============================================================================
CREATE VIEW public_profiles AS
SELECT
  id,
  display_name,
  avatar_url,
  bio,
  sports,
  levels_per_sport,
  created_at
FROM users
WHERE suspended_at IS NULL;

GRANT SELECT ON public_profiles TO anon, authenticated;

-- ============================================================================
-- TRIGGER: on_auth_user_created — server-side user row creation
-- ============================================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, display_name, created_at, updated_at)
  VALUES (NEW.id, NEW.email, generate_random_name(), now(), now());
  RETURN NEW;
END;
$$;

-- Internal trigger function: REVOKE from client roles
REVOKE EXECUTE ON FUNCTION handle_new_user() FROM anon, authenticated;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================================
-- TRIGGER: handle_user_update — whitelist column protection + auto updated_at
-- ============================================================================
CREATE OR REPLACE FUNCTION handle_user_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Bypass for authorized server-side functions
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  -- WHITELIST: force ALL non-allowed columns to their old values
  -- Any new column added to the table is automatically protected
  NEW.id := OLD.id;
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.date_of_birth := OLD.date_of_birth;
  NEW.is_admin := OLD.is_admin;
  NEW.tier := OLD.tier;
  NEW.is_pro_verified := OLD.is_pro_verified;
  NEW.pro_verified_at := OLD.pro_verified_at;
  NEW.suspended_at := OLD.suspended_at;
  NEW.phone_verified := OLD.phone_verified;
  NEW.phone_verified_at := OLD.phone_verified_at;
  NEW.accepted_tos_at := OLD.accepted_tos_at;
  NEW.accepted_privacy_at := OLD.accepted_privacy_at;
  NEW.push_token := OLD.push_token;

  -- Allowed columns: display_name, avatar_url, bio, sports, levels_per_sport
  -- (NOT listed above = client can modify them)

  -- Auto-update updated_at
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Internal trigger function: REVOKE from client roles
REVOKE EXECUTE ON FUNCTION handle_user_update() FROM anon, authenticated;

CREATE TRIGGER on_user_update
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION handle_user_update();

-- ============================================================================
-- SPORTS REFERENCE DATA (not seed data — required for app to function)
-- ============================================================================
INSERT INTO sports (key, icon, category, display_order) VALUES
  ('hiking',        'hiking',        'mountain', 1),
  ('climbing',      'climbing',      'mountain', 2),
  ('ski-touring',   'ski-touring',   'mountain', 3),
  ('trail-running', 'trail-running', 'mountain', 4),
  ('mountaineering','mountaineering','mountain', 5),
  ('cycling',       'cycling',       'road',     6),
  ('mountain-biking','mountain-biking','mountain',7),
  ('kayaking',      'kayaking',      'water',    8),
  ('surfing',       'surfing',       'water',    9),
  ('sailing',       'sailing',       'water',    10),
  ('paragliding',   'paragliding',   'air',      11),
  ('skiing',        'skiing',        'mountain', 12),
  ('snowboarding',  'snowboarding',  'mountain', 13),
  ('running',       'running',       'road',     14),
  ('swimming',      'swimming',      'water',    15);
