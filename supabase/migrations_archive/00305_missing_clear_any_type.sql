-- Migration 00305: clear a missing tile on ANY matching gear declaration.
--
-- 00303's trigger only fired for is_shared=true inserts, but set_activity_gear
-- forces catalog items to their catalog type — declaring "Casque" (personal in
-- the catalog) after a "manque casque" tile left the tile open and the item
-- landed in "Chacun son sac". The gap is answered either way: clear on any
-- name match.
CREATE OR REPLACE FUNCTION clear_missing_on_shared_gear()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  DELETE FROM activity_gear_missing
  WHERE activity_id = NEW.activity_id
    AND lower(name) = lower(NEW.gear_name);
  RETURN NEW;
END;
$$;
