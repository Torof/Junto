-- ============================================================================
-- 00343 — Demo: swap the "Air & water" pin/logo image.
--
-- The current pin_image_url (biplace-1: a close-up tandem selfie, two people
-- pulling faces) reads as goofy, not sporty. Replace it with parapente.jpg —
-- three wings soaring over the valley, no faces, a cleaner sporty shot.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles
    SET pin_image_url = 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/parapente.jpg'
    WHERE user_id = 'd0000000-0000-4000-a000-000000000001';
END $$;
