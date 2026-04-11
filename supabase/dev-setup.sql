-- Junto — Dev Setup Script
-- Run in Supabase SQL Editor after creating test accounts
-- Sets all users to premium + phone_verified
-- Safe to re-run at any time

SELECT set_config('junto.bypass_lock', 'true', true);

UPDATE users
SET phone_verified = true, tier = 'premium'
WHERE phone_verified = false OR tier != 'premium';

-- Show results
SELECT display_name, phone_verified, tier FROM users;
