-- Migration 00250: pro_offerings_with_coords view.
--
-- Powers the catalog listings (on pro profile) and the map (lozenge
-- pins). Joins sports for sport_key/icon/category, and pro_profiles
-- for display_name (so a card can show "Mont Aiguille — Pierre Guide"
-- without a second round-trip).
--
-- Read-only public view; inherits from pro_offerings public-read RLS.

CREATE VIEW pro_offerings_with_coords AS
SELECT
  o.id,
  o.pro_id,
  o.sport_id,
  o.title,
  o.description,
  o.level,
  o.location_name,
  o.duration,
  o.max_participants,
  o.schedule_text,
  o.distance_km,
  o.elevation_gain_m,
  o.image_url,
  o.created_at,
  o.updated_at,
  ST_X(o.location::geometry) AS lng,
  ST_Y(o.location::geometry) AS lat,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  pp.display_name AS pro_name
FROM pro_offerings o
JOIN sports s ON o.sport_id = s.id
JOIN pro_profiles pp ON o.pro_id = pp.user_id;

GRANT SELECT ON pro_offerings_with_coords TO anon, authenticated;
