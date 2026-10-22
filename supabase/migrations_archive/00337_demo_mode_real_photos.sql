-- ============================================================================
-- 00337 — Demo mode: real photos (Scott's assets/demo, uploaded to pro-photos)
--
-- LoremFlickr keyword images were still off-topic. Scott provided 14 real shots
-- (9 canyoning + 5 parapente), uploaded to the public `pro-photos/demo/` folder.
-- Re-seed the galleries from those: canyon photos → the two canyoning offers +
-- the pro gallery, parapente/biplace → the Prorel offer + gallery + pin.
--
-- Clean re-seed (DELETE demo photo rows, re-INSERT) rather than UPDATE-in-place,
-- since the counts change (galleries grow from 2-3 to 3-5 photos).
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  DELETE FROM pro_profile_photos  WHERE pro_id = 'd0000000-0000-4000-a000-000000000001';
  DELETE FROM pro_offering_photos WHERE offering_id IN (
    'b0000000-0000-4000-a000-000000000001',
    'b0000000-0000-4000-a000-000000000002',
    'b0000000-0000-4000-a000-000000000003'
  );

  -- Pro page gallery (canyon + parapente mix)
  INSERT INTO pro_profile_photos (pro_id, photo_url, order_index) VALUES
    ('d0000000-0000-4000-a000-000000000001', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/canyon-6.jpg',    0),
    ('d0000000-0000-4000-a000-000000000001', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/parapente.jpg',   1),
    ('d0000000-0000-4000-a000-000000000001', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/canyon-7.jpg',    2),
    ('d0000000-0000-4000-a000-000000000001', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/biplace-4.jpg',   3),
    ('d0000000-0000-4000-a000-000000000001', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/canyon-8.jpeg',   4);

  -- Offering: Canyon du Fournel
  INSERT INTO pro_offering_photos (offering_id, photo_url, order_index) VALUES
    ('b0000000-0000-4000-a000-000000000001', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/canyoning-1.jpg', 0),
    ('b0000000-0000-4000-a000-000000000001', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/canyon-2.jpg',    1),
    ('b0000000-0000-4000-a000-000000000001', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/canyon-3.jpg',    2);

  -- Offering: Torrent des Acles
  INSERT INTO pro_offering_photos (offering_id, photo_url, order_index) VALUES
    ('b0000000-0000-4000-a000-000000000002', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/canyon-4.jpg',    0),
    ('b0000000-0000-4000-a000-000000000002', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/canyon-5.jpg',    1),
    ('b0000000-0000-4000-a000-000000000002', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/canyon-saut.jpg', 2);

  -- Offering: Vol biplace au Prorel
  INSERT INTO pro_offering_photos (offering_id, photo_url, order_index) VALUES
    ('b0000000-0000-4000-a000-000000000003', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/biplace-1.jpg',   0),
    ('b0000000-0000-4000-a000-000000000003', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/biplace-2.jpg',   1),
    ('b0000000-0000-4000-a000-000000000003', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/biplace-3.jpg',   2);

  -- Pro pin image
  UPDATE pro_profiles
    SET pin_image_url = 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/biplace-1.jpg'
    WHERE user_id = 'd0000000-0000-4000-a000-000000000001';
END $$;
