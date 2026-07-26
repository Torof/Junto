-- ============================================================================
-- 00338 — Demo mode: offering availability + per-sport level grades
--
-- Two demo-data corrections (the features already exist app-wide):
--   1. schedule_text ("Horaires / disponibilité") was left empty on the demo
--      offerings, so the availability line never showed. Fill it.
--   2. The demo climbing + paragliding activities used generic levels
--      (intermédiaire/avancé) instead of the per-sport grade scales the create
--      form actually offers (climbing → French sport grades, paragliding →
--      brevets). formatLevelRange renders "5c → 7a" etc. Fix the seed data.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 1) Availability on the three demo offerings.
  UPDATE pro_offerings SET schedule_text = 'Tous les jours en saison · départs 9h et 14h'
    WHERE id = 'b0000000-0000-4000-a000-000000000001'; -- Canyon du Fournel
  UPDATE pro_offerings SET schedule_text = 'Juin à septembre · sur réservation'
    WHERE id = 'b0000000-0000-4000-a000-000000000002'; -- Torrent des Acles
  UPDATE pro_offerings SET schedule_text = 'Toute l''année · selon conditions météo'
    WHERE id = 'b0000000-0000-4000-a000-000000000003'; -- Vol biplace au Prorel

  -- 2) Real grades on the demo activities (climbing → French sport scale,
  --    paragliding → pilot brevet). Hiking keeps its generic tier (its signal
  --    is distance + D+, not a grade scale).
  UPDATE activities SET level = '5c', level_max = '7a'
    WHERE id = 'a0000000-0000-4000-a000-000000000002'; -- Escalade Rocher Baron
  UPDATE activities SET level = '5a', level_max = '6a'
    WHERE id = 'a0000000-0000-4000-a000-000000000003'; -- Escalade Falaise de Puy-Chalvin
  UPDATE activities SET level = 'Pilote autonome', level_max = NULL
    WHERE id = 'a0000000-0000-4000-a000-000000000004'; -- Parapente Cime de la Condamine
END $$;
