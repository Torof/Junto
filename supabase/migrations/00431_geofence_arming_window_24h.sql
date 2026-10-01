-- ============================================================================
-- 00431 — La validation de présence automatique APP FERMÉE devient réellement
-- opérante (Scott 2026-10-01 : « être capable d'utiliser l'auto-vérification de
-- géolocalisation même lorsque l'app est fermée »).
--
-- Constat : la capacité existait déjà et était correctement construite — vrai
-- geofencing de l'OS (`startGeofencingAsync`), tâche déclarée au niveau module
-- et importée dans app/_layout.tsx, donc le système réveille l'app même tuée.
-- MAIS les zones n'étaient transmises à l'OS que si l'app passait au premier
-- plan entre T-2h et T+15min (cette fonction). Rouler 1 h 30 jusqu'au départ
-- sans ouvrir Junto ⇒ aucune zone posée ⇒ la détection en arrière-plan
-- n'existait tout simplement pas pour cette sortie. Le niveau 1 de l'entonnoir
-- de fiabilité (géo auto) fuyait, et c'est celui dont dépendent tous les autres.
--
-- Fix : fenêtre d'ARMEMENT à 24 h. Elle ne touche PAS la validité d'une
-- présence — celle-ci reste bornée à T±15min en deux endroits indépendants :
-- la tâche de geofencing (qui diffère une notification si l'entrée se déclenche
-- trop tôt) et confirm_presence_via_geo côté serveur. Les trois autres
-- consommateurs de cette liste (vérification à l'ouverture, veilleur au premier
-- plan, service Android au premier plan) filtrent tous déjà strictement
-- T±15min : vérifié avant d'écrire cette migration, aucun ne démarrera plus tôt.
--
-- + ORDER BY starts_at : le client plafonne à 20 zones (limite iOS) et coupait
-- une liste non ordonnée. Avec 2 h c'était théorique, avec 24 h il faut garder
-- les sorties les plus proches.
--
-- Base vivante vérifiée : 00306 (grep de toutes les redéfinitions : 00306 seul
-- la définit, 00307 ne fait que des REVOKE). Colonnes de retour inchangées.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_my_active_presence_activities()
RETURNS TABLE(activity_id uuid, title text, starts_at timestamp with time zone, duration interval, meeting_lng double precision, meeting_lat double precision, end_lng double precision, end_lat double precision)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    a.id AS activity_id,
    a.title,
    a.starts_at,
    a.duration,
    ST_X(a.location_meeting::geometry)::float AS meeting_lng,
    ST_Y(a.location_meeting::geometry)::float AS meeting_lat,
    ST_X(a.location_end::geometry)::float AS end_lng,
    ST_Y(a.location_end::geometry)::float AS end_lat
  FROM activities a
  JOIN participations p ON p.activity_id = a.id
  WHERE p.user_id = v_user_id
    AND p.status = 'accepted'
    AND p.confirmed_present IS NULL
    AND a.creator_id != v_user_id          -- creator never self-confirms
    AND a.requires_presence = TRUE
    AND a.deleted_at IS NULL
    AND a.status IN ('published', 'in_progress')
    -- 00431 : fenêtre d'ARMEMENT élargie de 2 h à 24 h. Elle ne décide PAS
    -- quand une présence est valide (ça reste T±15min, vérifié par la tâche de
    -- geofencing ET par confirm_presence_via_geo) : elle décide seulement quand
    -- l'OS reçoit la zone à surveiller. À 2 h, il fallait ouvrir l'app dans un
    -- créneau de 2 h 15 pour que la détection en arrière-plan existe — sinon la
    -- validation « automatique, app fermée » n'avait jamais lieu. À 24 h,
    -- n'importe quelle ouverture de l'app la veille arme le système.
    AND now() >= a.starts_at - INTERVAL '24 hours'
    AND now() <= a.starts_at + INTERVAL '15 minutes'
  -- Les plus proches d'abord : le client plafonne à 20 zones (limite iOS) et
  -- coupait jusqu'ici une liste non triée, donc au hasard.
  ORDER BY a.starts_at ASC;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_my_active_presence_activities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_active_presence_activities() TO authenticated;
