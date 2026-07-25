-- ============================================================================
-- 00336 — Demo mode: themed placeholder photos
--
-- Phase 2 seeded picsum photos (random → a dog showed up on a canyoning offer).
-- Swap them for LoremFlickr keyword images: topically relevant (canyoning /
-- paragliding / mountain) and stable per `lock` value. Still placeholders —
-- Scott swaps for real shots later.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- Pro pin image
  UPDATE pro_profiles
    SET pin_image_url = 'https://loremflickr.com/400/400/canyoning?lock=10'
    WHERE user_id = 'd0000000-0000-4000-a000-000000000001';

  -- Pro page gallery (canyoning / parapente / montagne)
  UPDATE pro_profile_photos SET photo_url = 'https://loremflickr.com/1200/800/canyoning?lock=11'
    WHERE pro_id = 'd0000000-0000-4000-a000-000000000001' AND order_index = 0;
  UPDATE pro_profile_photos SET photo_url = 'https://loremflickr.com/1200/800/paragliding?lock=12'
    WHERE pro_id = 'd0000000-0000-4000-a000-000000000001' AND order_index = 1;
  UPDATE pro_profile_photos SET photo_url = 'https://loremflickr.com/1200/800/mountain?lock=13'
    WHERE pro_id = 'd0000000-0000-4000-a000-000000000001' AND order_index = 2;

  -- Offering galleries
  UPDATE pro_offering_photos SET photo_url = 'https://loremflickr.com/1200/800/canyoning?lock=21'
    WHERE offering_id = 'b0000000-0000-4000-a000-000000000001' AND order_index = 0;
  UPDATE pro_offering_photos SET photo_url = 'https://loremflickr.com/1200/800/canyoning?lock=22'
    WHERE offering_id = 'b0000000-0000-4000-a000-000000000001' AND order_index = 1;
  UPDATE pro_offering_photos SET photo_url = 'https://loremflickr.com/1200/800/canyoning?lock=23'
    WHERE offering_id = 'b0000000-0000-4000-a000-000000000002' AND order_index = 0;
  UPDATE pro_offering_photos SET photo_url = 'https://loremflickr.com/1200/800/canyoning?lock=24'
    WHERE offering_id = 'b0000000-0000-4000-a000-000000000002' AND order_index = 1;
  UPDATE pro_offering_photos SET photo_url = 'https://loremflickr.com/1200/800/paragliding?lock=31'
    WHERE offering_id = 'b0000000-0000-4000-a000-000000000003' AND order_index = 0;
  UPDATE pro_offering_photos SET photo_url = 'https://loremflickr.com/1200/800/paragliding?lock=32'
    WHERE offering_id = 'b0000000-0000-4000-a000-000000000003' AND order_index = 1;
END $$;
