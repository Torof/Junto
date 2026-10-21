-- ============================================================================
-- 00509 — Bug trouvé par la régénération des types : depuis 00441 (lieu-dit du
-- rendez-vous), l'app demande meeting_locality aux vues my_activities,
-- my_joined_activities et my_pending_activities, qui ne l'ont jamais eue →
-- les listes « Mes sorties » et le sélecteur de sortie échouaient. Colonne
-- ajoutée en fin de vue (les colonnes existantes ne bougent pas).
-- ============================================================================

CREATE OR REPLACE VIEW public.my_activities AS
SELECT a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.distance_km,
    a.elevation_gain_m,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.requires_presence,
    a.status,
    a.deleted_at,
    a.created_at,
    a.updated_at,
    a.objective_name,
    a.meeting_name,
    a.trace_geojson,
    st_x((COALESCE(a.location_objective, a.location_meeting))::geometry) AS lng,
    st_y((COALESCE(a.location_objective, a.location_meeting))::geometry) AS lat,
    st_x((a.location_meeting)::geometry) AS meeting_lng,
    st_y((a.location_meeting)::geometry) AS meeting_lat,
    st_x((a.location_end)::geometry) AS end_lng,
    st_y((a.location_end)::geometry) AS end_lat,
    st_x((a.location_objective)::geometry) AS objective_lng,
    st_y((a.location_objective)::geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    ( SELECT (count(*))::integer AS count
           FROM participations p
          WHERE ((p.activity_id = a.id) AND (p.status = 'accepted'::text))) AS participant_count,
    a.level_max,
    a.meeting_locality
   FROM ((activities a
     JOIN public_profiles pp ON ((a.creator_id = pp.id)))
     JOIN sports s ON ((a.sport_id = s.id)))
  WHERE (a.creator_id = auth.uid());

CREATE OR REPLACE VIEW public.my_joined_activities AS
SELECT a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.distance_km,
    a.elevation_gain_m,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.requires_presence,
    a.status,
    a.deleted_at,
    a.created_at,
    a.updated_at,
    a.objective_name,
    a.meeting_name,
    a.trace_geojson,
    st_x((COALESCE(a.location_objective, a.location_meeting))::geometry) AS lng,
    st_y((COALESCE(a.location_objective, a.location_meeting))::geometry) AS lat,
    st_x((a.location_meeting)::geometry) AS meeting_lng,
    st_y((a.location_meeting)::geometry) AS meeting_lat,
    st_x((a.location_end)::geometry) AS end_lng,
    st_y((a.location_end)::geometry) AS end_lat,
    st_x((a.location_objective)::geometry) AS objective_lng,
    st_y((a.location_objective)::geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    ( SELECT (count(*))::integer AS count
           FROM participations p
          WHERE ((p.activity_id = a.id) AND (p.status = 'accepted'::text))) AS participant_count,
    a.level_max,
    a.meeting_locality
   FROM (((activities a
     JOIN participations par ON (((par.activity_id = a.id) AND (par.user_id = auth.uid()) AND (par.status = 'accepted'::text))))
     JOIN public_profiles pp ON ((a.creator_id = pp.id)))
     JOIN sports s ON ((a.sport_id = s.id)))
  WHERE ((a.creator_id <> auth.uid()) AND (a.deleted_at IS NULL));

CREATE OR REPLACE VIEW public.my_pending_activities AS
SELECT a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.distance_km,
    a.elevation_gain_m,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.requires_presence,
    a.status,
    a.deleted_at,
    a.created_at,
    a.updated_at,
    a.objective_name,
    a.meeting_name,
    a.trace_geojson,
    st_x((COALESCE(a.location_objective, a.location_meeting))::geometry) AS lng,
    st_y((COALESCE(a.location_objective, a.location_meeting))::geometry) AS lat,
    st_x((a.location_meeting)::geometry) AS meeting_lng,
    st_y((a.location_meeting)::geometry) AS meeting_lat,
    st_x((a.location_end)::geometry) AS end_lng,
    st_y((a.location_end)::geometry) AS end_lat,
    st_x((a.location_objective)::geometry) AS objective_lng,
    st_y((a.location_objective)::geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    ( SELECT (count(*))::integer AS count
           FROM participations p
          WHERE ((p.activity_id = a.id) AND (p.status = 'accepted'::text))) AS participant_count,
    a.level_max,
    a.meeting_locality
   FROM (((activities a
     JOIN participations par ON (((par.activity_id = a.id) AND (par.user_id = auth.uid()) AND (par.status = 'pending'::text))))
     JOIN public_profiles pp ON ((a.creator_id = pp.id)))
     JOIN sports s ON ((a.sport_id = s.id)))
  WHERE ((a.creator_id <> auth.uid()) AND (a.deleted_at IS NULL));

