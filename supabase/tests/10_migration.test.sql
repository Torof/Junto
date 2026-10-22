-- Domaine 10 — ce que la migration vers le nouveau projet doit porter (2026-10-22).
-- L'export de la structure (pg_dump -n public -n private) ne contient ni le stockage, ni le
-- temps réel, ni les tâches planifiées, ni app_config, ni les droits par défaut : ils sont
-- recréés à part (MIGRATION_PLAN §B.5-B.8, scripts/migration/outside-dump.sql), puis la démo
-- est recopiée (copy-demo.py). Ces tests vérifient le résultat sur n'importe quel projet ;
-- ce qui ne vaut que pour le nouveau dépend d'un fait lu dans la base (où vit PostGIS).
-- Déjà couverts ailleurs : déclencheurs auth.users / storage.objects (chaque pg_temp.user,
-- 08 E1, quota en 00), RLS forcée, propriétaires, search_path, adresse du projet (00, 09).
-- Ne jamais renvoyer la valeur d'un secret : les requêtes ne rendent que des noms.

PERFORM pg_temp.as_('db');

-- ═════ M1 — Stockage : espaces et policies ═════
PERFORM pg_temp.eq('M1 les 3 espaces de stockage : publics, 5 Mo, jpeg / png / webp',
  $$SELECT string_agg(id || '|' || public || '|' || coalesce(file_size_limit::text, 'null') || '|'
      || coalesce((SELECT string_agg(m, ' ' ORDER BY m) FROM unnest(allowed_mime_types) m), 'null'), ', ' ORDER BY id)
    FROM storage.buckets$$,
  'avatars|true|5242880|image/jpeg image/png image/webp, channel-photos|true|5242880|image/jpeg image/png image/webp, pro-photos|true|5242880|image/jpeg image/png image/webp');
PERFORM pg_temp.eq('M1 storage.objects : exactement les 12 policies (lire / écrire / modifier / supprimer dans son dossier)',
  $$SELECT string_agg(policyname || ':' || cmd || ':' || array_to_string(roles, ','), ', ' ORDER BY policyname COLLATE "C")
    FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'$$,
  'avatars_delete_own:DELETE:authenticated, avatars_insert_own:INSERT:authenticated, avatars_read_own:SELECT:authenticated, avatars_update_own:UPDATE:authenticated, '
  || 'channel_photos_delete_own:DELETE:authenticated, channel_photos_insert_own:INSERT:authenticated, channel_photos_read_own:SELECT:authenticated, channel_photos_update_own:UPDATE:authenticated, '
  || 'pro_photos_delete_own:DELETE:authenticated, pro_photos_insert_own:INSERT:authenticated, pro_photos_read_own:SELECT:authenticated, pro_photos_update_own:UPDATE:authenticated');

-- ═════ M2 — Temps réel ═════
PERFORM pg_temp.eq('M2 realtime.messages : exactement les 4 policies de lecture des canaux',
  $$SELECT string_agg(policyname || ':' || cmd || ':' || array_to_string(roles, ','), ', ' ORDER BY policyname COLLATE "C")
    FROM pg_policies WHERE schemaname = 'realtime' AND tablename = 'messages'$$,
  'realtime_activity_topics_read:SELECT:authenticated, realtime_conversation_topics_read:SELECT:authenticated, realtime_map_topic_read:SELECT:authenticated, realtime_user_topic_read:SELECT:authenticated');
PERFORM pg_temp.eq('M2 publication supabase_realtime = notifications + seat_requests, rien d''autre',
  $$SELECT string_agg(schemaname || '.' || tablename, ',' ORDER BY tablename) FROM pg_publication_tables WHERE pubname = 'supabase_realtime'$$,
  'public.notifications,public.seat_requests');
PERFORM pg_temp.eq('M2 notifications en REPLICA IDENTITY FULL (filtres des abonnements)',
  $$SELECT relreplident::text FROM pg_class WHERE oid = 'public.notifications'::regclass$$, 'f');

-- ═════ M3 — Tâches planifiées ═════
PERFORM pg_temp.eq('M3 exactement les 6 tâches planifiées, actives, au bon rythme, en postgres',
  $$SELECT string_agg(jobname || '|' || schedule || '|' || active || '|' || username || '|' || command, ' ¦ ' ORDER BY jobname) FROM cron.job$$,
  'junto-booking-participant-purge|15 4 * * *|true|postgres|SELECT public.purge_booking_participant_info(); ¦ '
  || 'junto-contact-archive-purge|30 4 * * *|true|postgres|SELECT public.purge_contact_removal_archive(); ¦ '
  || 'junto-cron-log-purge|50 4 * * *|true|postgres|DELETE FROM cron.job_run_details WHERE end_time < now() - interval ''7 days'' ¦ '
  || 'junto-notif-purge|0 4 * * *|true|postgres|SELECT public.purge_old_notifications(); ¦ '
  || 'junto-presence-sweep|* * * * *|true|postgres|SELECT public.check_activity_transitions(); ¦ '
  || 'junto-throttle-purge|45 4 * * *|true|postgres|SELECT public.purge_throttle_tables();');
PERFORM pg_temp.eq('M3 chaque fonction appelée par une tâche existe (sans argument)',
  $$SELECT coalesce(string_agg(m[1], ', '), '') FROM cron.job j CROSS JOIN LATERAL regexp_matches(j.command, '(public\.[a-z0-9_]+)\(\)', 'g') m
    WHERE to_regprocedure(m[1] || '()') IS NULL$$, '');

-- ═════ M4 — app_config (recréée à la main, hors export) ═════
PERFORM pg_temp.eq('M4 app_config contient les 4 clés requises',
  $$SELECT string_agg(name, ',' ORDER BY name) FROM public.app_config
    WHERE name IN ('demo_mode', 'email_ban_pepper', 'project_url', 'push_webhook_secret')$$,
  'demo_mode,email_ban_pepper,project_url,push_webhook_secret');
-- Seuls les NOMS des clés non conformes sont renvoyés, jamais leur valeur.
PERFORM pg_temp.eq('M4 secret push non vide (≥ 32), poivre = 64 hexadécimaux, demo_mode booléen',
  $$SELECT coalesce(string_agg(k, ','), '') FROM (VALUES
      ('push_webhook_secret', (SELECT length(value) >= 32 FROM public.app_config WHERE name = 'push_webhook_secret')),
      ('email_ban_pepper',    (SELECT value ~ '^[0-9a-f]{64}$' FROM public.app_config WHERE name = 'email_ban_pepper')),
      ('demo_mode',           (SELECT value IN ('true', 'false') FROM public.app_config WHERE name = 'demo_mode'))
    ) v(k, good) WHERE good IS NOT TRUE$$, '');

-- ═════ M5 — Droits par défaut de postgres (MIGRATION_PLAN §B.5) ═════
-- Global : fonctions sans PUBLIC. public : tables en lecture pour les clients, tout pour
-- service_role ; fonctions pour service_role seulement ; séquences. (storage : plateforme.)
-- Renvoie les écarts : « + » en trop, « - » manquant.
PERFORM pg_temp.eq('M5 droits par défaut de postgres (global + public) exactement ceux voulus',
  $$WITH got AS (
      SELECT coalesce(nullif(d.defaclnamespace, 0::oid)::regnamespace::text, '*') AS ns, d.defaclobjtype::text AS t,
             CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END AS g, a.privilege_type AS p
      FROM pg_default_acl d CROSS JOIN LATERAL aclexplode(d.defaclacl) a
      WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace IN (0::oid, 'public'::regnamespace)),
    want AS (
      SELECT '*' AS ns, 'f' AS t, 'postgres' AS g, 'EXECUTE' AS p
      UNION ALL SELECT 'public', 'f', g, 'EXECUTE' FROM unnest('{postgres,service_role}'::text[]) g
      UNION ALL SELECT 'public', 'S', g, p FROM unnest('{postgres,anon,authenticated,service_role}'::text[]) g, unnest('{SELECT,UPDATE,USAGE}'::text[]) p
      UNION ALL SELECT 'public', 'r', g, p FROM unnest('{postgres,service_role}'::text[]) g,
                       unnest('{INSERT,SELECT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN}'::text[]) p
      UNION ALL SELECT 'public', 'r', g, 'SELECT' FROM unnest('{anon,authenticated}'::text[]) g)
    SELECT coalesce(string_agg(x, ', ' ORDER BY x), '') FROM (
      SELECT '+' || ns || '/' || t || '/' || g || '/' || p AS x FROM (SELECT * FROM got EXCEPT SELECT * FROM want) a
      UNION ALL
      SELECT '-' || ns || '/' || t || '/' || g || '/' || p FROM (SELECT * FROM want EXCEPT SELECT * FROM got) b) z$$, '');

-- ═════ M6 — Lecture par colonne (MIGRATION_PLAN §2) ═════
-- activities, bookings, pro_profiles n'ont pas de lecture sur la table entière : un droit de
-- table rejoué par erreur rendrait lisibles toutes les colonnes ci-dessous d'un coup.
PERFORM pg_temp.eq('M6 aucun droit de lecture sur la table entière pour les clients (activities, bookings, pro_profiles)',
  $$SELECT coalesce(string_agg(g || ':' || t, ','), '') FROM unnest('{anon,authenticated}'::text[]) g, unnest('{activities,bookings,pro_profiles}'::text[]) t
    WHERE has_table_privilege(g, 'public.' || t, 'SELECT')$$, '');
PERFORM pg_temp.eq('M6 exactement ces colonnes restent illisibles pour un compte',
  $$SELECT string_agg(c.relname || '.' || a.attname, ',' ORDER BY c.relname || '.' || a.attname COLLATE "C")
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relnamespace = 'public'::regnamespace AND c.relname IN ('activities', 'bookings', 'pro_profiles')
      AND a.attnum > 0 AND NOT a.attisdropped AND NOT has_column_privilege('authenticated', c.oid, a.attnum, 'SELECT')$$,
  'activities.invite_token,bookings.participant_info,bookings.price_eur,bookings.price_unit,pro_profiles.company_name,'
  || 'pro_profiles.primary_location,pro_profiles.real_name,pro_profiles.rejection_reason,pro_profiles.reviewed_at,pro_profiles.reviewed_by');

-- ═════ M7 — Historique des migrations (nouveau projet seulement) ═════
-- MIGRATION_PLAN §B.8 / §F.6 : le nouveau projet démarre avec la migration de base 00526 ;
-- un `db push` ne doit jamais y rejouer les migrations archivées.
IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis' AND extnamespace = 'public'::regnamespace) THEN
  PERFORM pg_temp.eq('M7 nouveau projet : la migration de base 00526 est la première de l''historique',
    $$SELECT min(version) FROM supabase_migrations.schema_migrations$$, '00526');
END IF;

-- ═════ M8 — Démo recopiée ═════
-- Le rideau démo repose sur is_demo de chaque ligne : il doit suivre celui du propriétaire.
PERFORM pg_temp.eq('M8 drapeau démo des sorties, dispos, vitrines et offres = celui du propriétaire',
  $$SELECT coalesce(string_agg(t, ','), '') FROM (
      SELECT 'activities' t FROM public.activities x JOIN public.users u ON u.id = x.creator_id WHERE x.is_demo <> u.is_demo
      UNION SELECT 'discovery_availabilities' FROM public.discovery_availabilities x JOIN public.users u ON u.id = x.user_id WHERE x.is_demo <> u.is_demo
      UNION SELECT 'pro_profiles' FROM public.pro_profiles x JOIN public.users u ON u.id = x.user_id WHERE x.is_demo <> u.is_demo
      UNION SELECT 'pro_offerings' FROM public.pro_offerings x JOIN public.users u ON u.id = x.pro_id WHERE x.is_demo <> u.is_demo) z$$, '');
-- Les adresses de photos de l'ancien projet ont été réécrites : aucune ne vise un autre projet.
PERFORM pg_temp.eq('M8 aucune adresse de photo ne vise un autre projet Supabase',
  $$SELECT count(*)::text FROM (
      SELECT avatar_url AS url FROM public.users
      UNION ALL SELECT photo_url FROM public.channels
      UNION ALL SELECT pin_image_url FROM public.pro_profiles
      UNION ALL SELECT photo_url FROM public.pro_profile_photos
      UNION ALL SELECT photo_url FROM public.pro_offering_photos
      UNION ALL SELECT photo_url FROM public.pro_community_photos) u
    WHERE url ILIKE '%.supabase.co%' AND left(url, length(pg_temp.host()) + 1) <> pg_temp.host() || '/'$$, '0');
PERFORM pg_temp.eq('M8 chaque photo de la démo hébergée chez nous existe dans le stockage',
  $$SELECT count(*)::text FROM (
      SELECT avatar_url AS url FROM public.users WHERE is_demo
      UNION ALL SELECT pin_image_url FROM public.pro_profiles WHERE is_demo
      UNION ALL SELECT p.photo_url FROM public.pro_profile_photos p JOIN public.users u ON u.id = p.pro_id WHERE u.is_demo
      UNION ALL SELECT p.photo_url FROM public.pro_offering_photos p JOIN public.pro_offerings o ON o.id = p.offering_id WHERE o.is_demo
      UNION ALL SELECT p.photo_url FROM public.pro_community_photos p JOIN public.users u ON u.id = p.contributor_id WHERE u.is_demo
      UNION ALL SELECT c.photo_url FROM public.channels c JOIN public.users u ON u.id = c.created_by WHERE u.is_demo) u
    WHERE left(url, length(pg_temp.host() || '/storage/v1/object/public/')) = pg_temp.host() || '/storage/v1/object/public/'
      AND NOT EXISTS (SELECT 1 FROM storage.objects o
                      WHERE o.bucket_id || '/' || o.name = split_part(substr(url, length(pg_temp.host() || '/storage/v1/object/public/') + 1), '?', 1))$$, '0');
