-- Migration 00253: backfill existing banner_url / image_url into the
-- new gallery tables.
--
-- Phase 4A keeps banner_url + image_url intact during this step so the
-- deployed app keeps rendering until the OTA with the gallery-aware
-- code lands. The column drops + view rebuild + RPC removal happen in
-- a separate migration (00254) AFTER the gallery-aware code is shipping.
--
-- Idempotent — uses ON CONFLICT to dodge double-inserts at order_index = 0
-- if the migration is rerun.

INSERT INTO pro_profile_photos (pro_id, photo_url, order_index)
SELECT user_id, banner_url, 0
FROM pro_profiles
WHERE banner_url IS NOT NULL
  AND char_length(banner_url) BETWEEN 1 AND 500
ON CONFLICT (pro_id, order_index) DO NOTHING;

INSERT INTO pro_offering_photos (offering_id, photo_url, order_index)
SELECT id, image_url, 0
FROM pro_offerings
WHERE image_url IS NOT NULL
  AND char_length(image_url) BETWEEN 1 AND 500
ON CONFLICT (offering_id, order_index) DO NOTHING;
