-- 00525 — profile level dots count the outing levels the app really stores
-- (Scott 2026-10-22, after explanation: the profile keeps showing only the 4
-- plain tiers; this only fixes the COUNT behind them).
--
-- get_user_sport_levels compared levels to lowercase 'intermédiaire' /
-- 'avancé' / 'expert', while the app stores « Intermédiaire », « Avancé »…
-- or a sport grade (« 6b », « WI6 », « Classe III », « TD »…): almost every
-- profile stayed at 1 dot. private.level_tier maps a level to its plain tier
-- with the per-sport scales of src/constants/sport-levels.ts (keep both in
-- sync when a scale changes). The span's lower bound (level) is what counts,
-- as before: an outing « 5c → 7a » does not prove 7a.

CREATE OR REPLACE FUNCTION private.level_tier(p_sport_key text, p_level text)
 RETURNS smallint
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_level IS NULL THEN NULL
    WHEN lower(p_level) IN ('débutant', 'beginner') THEN 0
    WHEN lower(p_level) IN ('intermédiaire', 'intermediate') THEN 1
    WHEN lower(p_level) IN ('avancé', 'advanced') THEN 2
    WHEN lower(p_level) = 'expert' THEN 3
    ELSE (
      SELECT v.tier::smallint FROM (VALUES
        ('fr','5a',0),('fr','5b',0),('fr','5c',0),('fr','6a',1),('fr','6b',1),('fr','6c',1),
        ('fr','7a',2),('fr','7b',2),('fr','7c',2),('fr','8a',3),('fr','8b',3),('fr','8c',3),
        ('font','5',0),('font','6a',1),('font','6b',1),('font','6c',1),('font','7a',2),('font','7b',2),('font','7c',2),('font','8a',3),
        ('alpine','f',0),('alpine','pd',1),('alpine','ad',1),('alpine','d',2),('alpine','td',2),('alpine','ed',3),
        ('ice','wi3',1),('ice','wi4',2),('ice','wi5',2),('ice','wi6',3),
        ('dry','m5',1),('dry','m6',1),('dry','m7',2),('dry','m8',2),('dry','m9',3),
        ('vf','pd',0),('vf','ad',1),('vf','d',2),('vf','td',2),('vf','ed',3),
        ('canyon','v2',0),('canyon','v3',1),('canyon','v4',1),('canyon','v5',2),('canyon','v6',2),('canyon','v7',3),
        ('ww','classe ii',0),('ww','classe iii',1),('ww','classe iv',2),('ww','classe v',3),
        ('ski','s1',0),('ski','s2',1),('ski','s3',2),('ski','s4',2),('ski','s5',3),
        ('piste','vert',0),('piste','bleu',1),('piste','rouge',2),('piste','noir',3),
        ('fly','découverte',0),('fly','brevet en cours',0),('fly','pilote autonome',1),('fly','confirmé',2),
        ('dive','n1',0),('dive','n2',1),('dive','n3',2),('dive','n4',3),
        ('apnea','découverte',0),('apnea','10-20 m',1),('apnea','20-30 m',2),('apnea','30 m+',3)
      ) AS v(scale, label, tier)
      WHERE v.label = lower(p_level)
        AND v.scale = CASE p_sport_key
          WHEN 'climbing-sport' THEN 'fr' WHEN 'climbing-multipitch' THEN 'fr'
          WHEN 'bouldering' THEN 'font' WHEN 'mountaineering' THEN 'alpine'
          WHEN 'ice-climbing' THEN 'ice' WHEN 'dry-tooling' THEN 'dry'
          WHEN 'via-ferrata' THEN 'vf' WHEN 'canyoning' THEN 'canyon'
          WHEN 'kayaking' THEN 'ww' WHEN 'canoe' THEN 'ww' WHEN 'rafting' THEN 'ww'
          WHEN 'ski-touring' THEN 'ski' WHEN 'ski-freeride' THEN 'ski' WHEN 'splitboard' THEN 'ski'
          WHEN 'skiing' THEN 'piste' WHEN 'snowboarding' THEN 'piste'
          WHEN 'mtb-xc' THEN 'piste' WHEN 'mtb-enduro' THEN 'piste' WHEN 'mtb-downhill' THEN 'piste'
          WHEN 'paragliding' THEN 'fly' WHEN 'speed-riding' THEN 'fly' WHEN 'hang-gliding' THEN 'fly'
          WHEN 'diving' THEN 'dive' WHEN 'freediving' THEN 'apnea'
          ELSE NULL END
    )
  END;
$function$;
REVOKE ALL ON FUNCTION private.level_tier(text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_user_sport_levels(p_user_id uuid)
 RETURNS TABLE(sport_key text, dots smallint, last_at timestamp with time zone, first_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH completed AS (
    SELECT s.key AS sport_key, private.level_tier(s.key, a.level) AS tier, a.starts_at AS at
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND p.confirmed_present = true /* 00521: validated presence only */  -- 00495 (PR-7)
      AND a.status = 'completed'
      AND a.deleted_at IS NULL  -- 00495
      AND NOT private.user_is_suspended(p_user_id)  -- 00503 (DX-3)
      AND auth.uid() IS NOT NULL AND NOT private.user_is_suspended(auth.uid())  -- 00520 (ID-9)
      -- 00419 M3 : rideau démo.
      AND NOT (
        EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
        AND NOT demo_content_visible()
      )
  ),
  agg AS (
    SELECT
      completed.sport_key,
      count(*) AS total,
      count(*) FILTER (
        WHERE completed.tier >= 1  -- 00525: app values (« Intermédiaire », « 6b »…)
      ) AS at_intermediate,
      count(*) FILTER (
        WHERE completed.tier >= 2
      ) AS at_advanced,
      count(*) FILTER (WHERE completed.tier = 3) AS at_expert,
      max(completed.at) AS last_at,
      min(completed.at) AS first_at
    FROM completed
    GROUP BY completed.sport_key
  )
  SELECT
    agg.sport_key,
    (CASE
      WHEN agg.at_expert >= 3 THEN 4
      WHEN agg.at_advanced >= 5 THEN 3
      WHEN agg.at_intermediate >= 3 THEN 2
      WHEN agg.total >= 1 THEN 1
      ELSE 0
    END)::SMALLINT AS dots,
    -- 00499 (DX-4): month only — an exact time could date a private outing.
    date_trunc('month', agg.last_at),
    date_trunc('month', agg.first_at)
  FROM agg
  WHERE agg.total > 0;
$function$;
