-- Migration 00254: drop legacy banner_url / image_url + their RPCs,
-- rebuild pro_offerings_with_coords with image_url sourced from the
-- first gallery photo.
--
-- Phase 4A consolidation. 00253 already copied existing values into
-- the new gallery tables, and the shipping app (post-OTA) reads the
-- gallery directly. This migration closes the loop: the legacy
-- columns + their setters are gone, and the offering view exposes
-- image_url as a subquery against pro_offering_photos so client code
-- that already reads `offering.image_url` (catalog cards, nearby pin
-- queries) keeps working without name changes.

DROP FUNCTION IF EXISTS set_pro_banner(TEXT);
DROP FUNCTION IF EXISTS set_pro_offering_image(UUID, TEXT);

DROP VIEW IF EXISTS pro_offerings_with_coords;

ALTER TABLE pro_profiles DROP COLUMN IF EXISTS banner_url;
ALTER TABLE pro_offerings DROP COLUMN IF EXISTS image_url;

-- Recreated view — same external shape (image_url stays as a column
-- name) but now sourced from the first photo of the per-offering
-- gallery. ORDER BY order_index ASC + LIMIT 1 is the contract: the
-- pro's curation in PhotoManager picks the hero.
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
  (
    SELECT photo_url
    FROM pro_offering_photos p
    WHERE p.offering_id = o.id
    ORDER BY order_index ASC
    LIMIT 1
  ) AS image_url,
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
