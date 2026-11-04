-- Domaine 18 — Agenda pro : synchronisation avec Google / Apple / Outlook
-- (mig 00568 liens d'agenda, 00569 calendar_feed_valid, 00575/00577 flux avec
-- dates fixes et demandes sur plusieurs jours).
--
--   Export : un flux iCal privé des réservations, lu par l'edge `calendar-feed`
--            avec un jeton secret (64 hex) ; fonctions réservées à service_role.
--   Import : l'adresse iCal secrète de l'agenda du pro (Google / iCloud /
--            Outlook uniquement), lue toutes les 15 min par l'edge
--            `calendar-import`, qui renvoie des demi-journées occupées.
--            Une demi-journée occupée n'est plus réservable.
--
-- CALENDAR-1/2/3/6 (coût CPU de l'import, récurrences anciennes, fuseaux
-- partagés, pliage des lignes ICS) concernent le code des fonctions Edge : déjà
-- corrigés là-bas, rien à tester en SQL.
-- private.trigger_calendar_import appelle net.http_post : jamais appelé ici,
-- on vérifie seulement qu'aucun client ne peut l'exécuter.

-- ───── Helpers locaux ─────
EXECUTE $p$CREATE FUNCTION pg_temp.ag_register_sql(p_name text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.register_as_pro(p_display_name := %L, p_company_name := 'SARL Agenda', p_real_name := 'Jean Test',
      p_primary_lng := 6.6, p_primary_lat := 44.9, p_primary_location_name := 'Briançon')::text$s$, p_name) $b$$p$;
EXECUTE $p$CREATE FUNCTION pg_temp.ag_offering_sql(p_title text) RETURNS text
  LANGUAGE sql AS $b$ SELECT format($s$SELECT public.create_pro_offering(p_sport_id := %L, p_title := %L, p_description := 'Description test',
      p_level := 'Tous niveaux', p_location_lng := 6.6, p_location_lat := 44.9, p_location_name := 'Briançon',
      p_max_participants := 8, p_price_eur := 50, p_price_unit := 'person')::text$s$, pg_temp.id('ag_sport'), p_title) $b$$p$;
-- Jeton d'export actuel d'un pro (lu en base, comme le ferait l'edge).
EXECUTE $p$CREATE FUNCTION pg_temp.ag_token(p_label text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT export_token FROM private.pro_calendar_links WHERE pro_id = pg_temp.id(p_label) $b$$p$;
-- Demi-journées occupées d'un pro.
EXECUTE $p$CREATE FUNCTION pg_temp.ag_busy(p_label text) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT count(*)::text FROM private.pro_busy_slots WHERE pro_id = pg_temp.id(p_label) $b$$p$;
-- Aujourd'hui + n jours (Europe/Paris), utilisable sous un rôle client.
EXECUTE $p$CREATE FUNCTION pg_temp.d(p_days int) RETURNS date
  LANGUAGE sql SECURITY DEFINER AS $b$ SELECT private.today_paris() + p_days $b$$p$;
-- Un créneau JSON {day, period} à today + n jours.
EXECUTE $p$CREATE FUNCTION pg_temp.ag_slot(p_days int, p_period text) RETURNS jsonb
  LANGUAGE sql AS $b$ SELECT jsonb_build_object('day', pg_temp.d(p_days)::text, 'period', p_period) $b$$p$;
-- CALENDAR-5 (corrigé 00578) : calendar_import_apply(pro, créneaux, erreur, adresse lue). Rend le
-- nombre de demi-journées occupées après l'appel.
EXECUTE $p$CREATE FUNCTION pg_temp.ag_apply_read_url(p_label text, p_slots jsonb, p_url text) RETURNS text
  LANGUAGE plpgsql AS $b$
  BEGIN
    EXECUTE 'SELECT public.calendar_import_apply($1, $2, NULL::text, $3)' USING pg_temp.id(p_label), p_slots, p_url;
    RETURN pg_temp.ag_busy(p_label);
  END $b$$p$;

-- ───── Fixtures ─────
PERFORM pg_temp.as_('db');
PERFORM pg_temp.user('ag_pro', 'tos');     -- pro approuvé principal (export + import)
PERFORM pg_temp.user('ag_url', 'tos');     -- pro approuvé dédié aux adresses d'import (plafond 10/jour)
PERFORM pg_temp.user('ag_pro2', 'tos');    -- pro approuvé : suspendu puis repassé en tier free
PERFORM pg_temp.user('ag_pro3', 'tos');    -- pro approuvé qui se désinscrit (CALENDAR-4)
PERFORM pg_temp.user('ag_cand', 'tos');    -- candidature en attente
PERFORM pg_temp.user('ag_cli', 'tos');
PERFORM pg_temp.user('ag_cli2', 'tos');
PERFORM pg_temp.user('ag_cli3', 'tos');
PERFORM pg_temp.user('ag_sam', 'tos,suspended');
PERFORM pg_temp.user('ag_adm', 'tos,admin');
PERFORM pg_temp.put('ag_sport', (SELECT id::text FROM public.sports WHERE key = 'hiking'));
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET display_name = 'Léa Cliente' WHERE id = pg_temp.id('ag_cli');
UPDATE public.users SET display_name = 'Marc Client' WHERE id = pg_temp.id('ag_cli2');
UPDATE public.users SET display_name = 'Zoé Cliente' WHERE id = pg_temp.id('ag_cli3');
PERFORM set_config('junto.bypass_lock', 'false', true);

PERFORM pg_temp.as_('ag_pro');  PERFORM pg_temp.ok('AG0 inscription ag_pro', pg_temp.ag_register_sql('Agenda Pro'));
PERFORM pg_temp.as_('ag_url');  PERFORM pg_temp.ok('AG0 inscription ag_url', pg_temp.ag_register_sql('Agenda Url'));
PERFORM pg_temp.as_('ag_pro2'); PERFORM pg_temp.ok('AG0 inscription ag_pro2', pg_temp.ag_register_sql('Agenda Deux'));
PERFORM pg_temp.as_('ag_pro3'); PERFORM pg_temp.ok('AG0 inscription ag_pro3', pg_temp.ag_register_sql('Agenda Trois'));
PERFORM pg_temp.as_('ag_cand'); PERFORM pg_temp.ok('AG0 inscription ag_cand', pg_temp.ag_register_sql('Agenda Candidat'));
PERFORM pg_temp.as_('ag_adm');
PERFORM pg_temp.ok('AG0 approbation ag_pro', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.ok('AG0 approbation ag_url', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('ag_url')));
PERFORM pg_temp.ok('AG0 approbation ag_pro2', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('ag_pro2')));
PERFORM pg_temp.ok('AG0 approbation ag_pro3', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('ag_pro3')));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.put('ag_off', pg_temp.ok('AG0 ag_pro crée une offre', pg_temp.ag_offering_sql('Sortie agenda')));
PERFORM pg_temp.put('ag_off2', pg_temp.ok('AG0 ag_pro crée une offre sur plusieurs jours', pg_temp.ag_offering_sql('Raid deux jours')));
PERFORM pg_temp.as_('ag_pro2');
PERFORM pg_temp.put('ag_off_p2', pg_temp.ok('AG0 ag_pro2 crée une offre', pg_temp.ag_offering_sql('Sortie pro2')));

-- ═════ AG1 — Les tables privées sont hors d'atteinte des clients ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('AG1 anon ne lit pas les liens d''agenda', $$SELECT count(*)::text FROM private.pro_calendar_links$$);
PERFORM pg_temp.denied('AG1 anon ne lit pas les demi-journées occupées', $$SELECT count(*)::text FROM private.pro_busy_slots$$);
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.ok('AG1 le pro crée son lien (get_calendar_links)', $$SELECT count(*)::text FROM public.get_calendar_links()$$);
PERFORM pg_temp.denied('AG1 le pro ne lit pas sa ligne de lien directement', $$SELECT export_token FROM private.pro_calendar_links$$);
PERFORM pg_temp.denied('AG1 le pro n''écrit pas son jeton directement',
  format($$UPDATE private.pro_calendar_links SET export_token = repeat('a', 64) WHERE pro_id = %L$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.denied('AG1 le pro n''écrit pas son adresse d''import directement',
  format($$UPDATE private.pro_calendar_links SET import_url = 'https://evil.example/x' WHERE pro_id = %L$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.denied('AG1 le pro ne lit pas ses demi-journées occupées directement', $$SELECT count(*)::text FROM private.pro_busy_slots$$);
PERFORM pg_temp.denied('AG1 le pro ne s''ajoute pas de demi-journée occupée',
  format($$INSERT INTO private.pro_busy_slots (pro_id, day, period) VALUES (%L, current_date + 3, 'am')$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.as_('ag_cli');
PERFORM pg_temp.denied('AG1 un membre ne lit pas les liens d''agenda', $$SELECT export_token FROM private.pro_calendar_links$$);
PERFORM pg_temp.denied('AG1 un membre ne vide pas les demi-journées occupées d''un pro',
  format($$DELETE FROM private.pro_busy_slots WHERE pro_id = %L$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.denied('AG1 un membre ne crée pas de lien pour un pro',
  format($$INSERT INTO private.pro_calendar_links (pro_id, export_token) VALUES (%L, repeat('b', 64))$$, pg_temp.id('ag_cli')));

-- ═════ AG2 — get_calendar_links ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('AG2 anon : pas de lien d''agenda', $$SELECT count(*)::text FROM public.get_calendar_links()$$);
PERFORM pg_temp.as_('ag_cli');
PERFORM pg_temp.denied('AG2 un non-pro n''a pas de lien d''agenda', $$SELECT count(*)::text FROM public.get_calendar_links()$$, 'Operation not permitted');
PERFORM pg_temp.as_('ag_cand');
PERFORM pg_temp.denied('AG2 une candidature en attente n''a pas de lien d''agenda', $$SELECT count(*)::text FROM public.get_calendar_links()$$, 'Operation not permitted');
PERFORM pg_temp.as_('ag_sam');
PERFORM pg_temp.denied('AG2 un suspendu n''a pas de lien d''agenda', $$SELECT count(*)::text FROM public.get_calendar_links()$$, 'Operation not permitted');
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.eq('AG2 une seule ligne pour le pro', $$SELECT count(*)::text FROM public.get_calendar_links()$$, '1');
PERFORM pg_temp.eq('AG2 jeton d''export : 64 caractères hexadécimaux', $$SELECT (export_token ~ '^[0-9a-f]{64}$')::text FROM public.get_calendar_links()$$, 'true');
PERFORM pg_temp.eq('AG2 par défaut (00581) : noms masqués, pas d''import', $$SELECT hide_names::text || '/' || import_connected::text || '/' || coalesce(import_synced_at::text, 'null') || '/' || coalesce(import_error, 'null') FROM public.get_calendar_links()$$, 'true/false/null/null');
PERFORM pg_temp.put('ag_tok0', pg_temp.ok('AG2 lecture du jeton', $$SELECT export_token FROM public.get_calendar_links()$$));
PERFORM pg_temp.eq('AG2 relire ne change pas le jeton', $$SELECT export_token FROM public.get_calendar_links()$$, pg_temp.get('ag_tok0'));
PERFORM pg_temp.as_('ag_pro2');
PERFORM pg_temp.put('ag_tok_p2', pg_temp.ok('AG2 ag_pro2 lit son jeton', $$SELECT export_token FROM public.get_calendar_links()$$));
PERFORM pg_temp.eq('AG2 chaque pro a son propre jeton', format($$SELECT (%L <> %L)::text$$, pg_temp.get('ag_tok0'), pg_temp.get('ag_tok_p2')), 'true');

-- ═════ AG3 — regenerate_calendar_export ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('AG3 anon ne régénère pas de jeton', $$SELECT public.regenerate_calendar_export()$$);
PERFORM pg_temp.as_('ag_cli');
PERFORM pg_temp.denied('AG3 un non-pro ne régénère pas de jeton', $$SELECT public.regenerate_calendar_export()$$, 'Operation not permitted');
PERFORM pg_temp.as_('ag_cand');
PERFORM pg_temp.denied('AG3 une candidature en attente ne régénère pas de jeton', $$SELECT public.regenerate_calendar_export()$$, 'Operation not permitted');
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.put('ag_tok1', pg_temp.ok('AG3 le pro régénère son jeton', $$SELECT public.regenerate_calendar_export()$$));
PERFORM pg_temp.eq('AG3 le nouveau jeton fait 64 hex', format($$SELECT (%L ~ '^[0-9a-f]{64}$')::text$$, pg_temp.get('ag_tok1')), 'true');
PERFORM pg_temp.eq('AG3 le nouveau jeton diffère de l''ancien', format($$SELECT (%L <> %L)::text$$, pg_temp.get('ag_tok1'), pg_temp.get('ag_tok0')), 'true');
PERFORM pg_temp.eq('AG3 get_calendar_links rend le nouveau jeton', $$SELECT export_token FROM public.get_calendar_links()$$, pg_temp.get('ag_tok1'));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG3 l''ancien jeton ne vaut plus rien', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok0')), 'false');
PERFORM pg_temp.eq('AG3 le nouveau jeton est valide', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok1')), 'true');
PERFORM pg_temp.eq('AG3 le jeton de pro2 est intact', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok_p2')), 'true');
-- Plafond : 10 régénérations par jour (1 déjà faite).
PERFORM pg_temp.as_('ag_pro');
FOR i IN 2..10 LOOP
  PERFORM public.regenerate_calendar_export();
END LOOP;
PERFORM pg_temp.denied('AG3 11e régénération du jour refusée', $$SELECT public.regenerate_calendar_export()$$, 'junto.too_many_actions');
PERFORM pg_temp.put('ag_tok', pg_temp.ok('AG3 jeton courant après la série', $$SELECT export_token FROM public.get_calendar_links()$$));

-- ═════ AG4 — set_calendar_export_hide_names ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('AG4 anon ne masque rien', $$SELECT public.set_calendar_export_hide_names(true)::text$$);
PERFORM pg_temp.as_('ag_cli');
PERFORM pg_temp.denied('AG4 un non-pro ne masque rien', $$SELECT public.set_calendar_export_hide_names(true)::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('ag_cand');
PERFORM pg_temp.denied('AG4 une candidature en attente ne masque rien', $$SELECT public.set_calendar_export_hide_names(true)::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.denied('AG4 NULL refusé', $$SELECT public.set_calendar_export_hide_names(NULL)::text$$, 'Operation not permitted');
PERFORM pg_temp.ok('AG4 le pro masque les noms', $$SELECT public.set_calendar_export_hide_names(true)::text$$);
PERFORM pg_temp.eq('AG4 le choix est relu', $$SELECT hide_names::text FROM public.get_calendar_links()$$, 'true');
PERFORM pg_temp.ok('AG4 le pro réaffiche les noms', $$SELECT public.set_calendar_export_hide_names(false)::text$$);
PERFORM pg_temp.eq('AG4 retour à l''affichage', $$SELECT hide_names::text FROM public.get_calendar_links()$$, 'false');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG4 le réglage de ag_pro ne touche pas ag_pro2 (défaut : masqués)',
  format($$SELECT hide_names::text FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_pro2')), 'true');

-- ═════ AG5 — set_calendar_import_url : qui, et quelles adresses ═════
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('AG5 anon ne branche pas d''agenda', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/x/basic.ics')::text$$);
PERFORM pg_temp.as_('ag_cli');
PERFORM pg_temp.denied('AG5 un non-pro ne branche pas d''agenda', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/x/basic.ics')::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('ag_cand');
PERFORM pg_temp.denied('AG5 une candidature en attente ne branche pas d''agenda', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/x/basic.ics')::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('ag_sam');
PERFORM pg_temp.denied('AG5 un suspendu ne branche pas d''agenda', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/x/basic.ics')::text$$, 'Operation not permitted');

-- Adresses acceptées (ag_url : 6 appels acceptés, sous le plafond de 10).
PERFORM pg_temp.as_('ag_url');
PERFORM pg_temp.ok('AG5 Google en https accepté', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/private-0123/basic.ics')::text$$);
PERFORM pg_temp.eq('AG5 get_calendar_links : import branché', $$SELECT import_connected::text FROM public.get_calendar_links()$$, 'true');
PERFORM pg_temp.eq('AG5 l''adresse importée n''est jamais rendue, même à son propriétaire',
  $$SELECT (row_to_json(l)::text ~ 'calendar\.google\.com')::text FROM public.get_calendar_links() l$$, 'false');
PERFORM pg_temp.ok('AG5 webcal:// iCloud accepté', $$SELECT public.set_calendar_import_url('webcal://p42-caldav.icloud.com/published/2/ABCdef')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG5 webcal:// est normalisé en https://',
  format($$SELECT import_url FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_url')), 'https://p42-caldav.icloud.com/published/2/ABCdef');
PERFORM pg_temp.as_('ag_url');
PERFORM pg_temp.ok('AG5 WEBCALS:// (majuscules) accepté', $$SELECT public.set_calendar_import_url('WEBCALS://p7-caldav.icloud.com/published/2/X')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG5 WEBCALS:// normalisé aussi',
  format($$SELECT import_url FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_url')), 'https://p7-caldav.icloud.com/published/2/X');
PERFORM pg_temp.as_('ag_url');
PERFORM pg_temp.ok('AG5 Outlook 365 accepté', $$SELECT public.set_calendar_import_url('https://outlook.office365.com/owa/calendar/a@b.fr/c/calendar.ics')::text$$);
PERFORM pg_temp.ok('AG5 Outlook.com accepté', $$SELECT public.set_calendar_import_url('https://outlook.live.com/owa/calendar/00000000/reachcalendar.ics')::text$$);
PERFORM pg_temp.ok('AG5 espaces autour de l''adresse retirés', $$SELECT public.set_calendar_import_url('   https://calendar.google.com/calendar/ical/x/basic.ics   ')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG5 adresse enregistrée sans les espaces',
  format($$SELECT import_url FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_url')), 'https://calendar.google.com/calendar/ical/x/basic.ics');

-- Adresses refusées (code non sensible junto.calendar_url ; l'adresse précédente reste).
PERFORM pg_temp.as_('ag_url');
PERFORM pg_temp.denied('AG5 http:// refusé', $$SELECT public.set_calendar_import_url('http://calendar.google.com/calendar/ical/x/basic.ics')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 autre hôte refusé', $$SELECT public.set_calendar_import_url('https://evil.example/calendar.ics')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 hôte autorisé en chemin refusé', $$SELECT public.set_calendar_import_url('https://evil.example/calendar.google.com/x')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 sous-domaine piège refusé', $$SELECT public.set_calendar_import_url('https://calendar.google.com.evil.example/x')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 identifiants piège (google@evil) refusés', $$SELECT public.set_calendar_import_url('https://calendar.google.com@evil.example/')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 identifiants avant l''hôte refusés', $$SELECT public.set_calendar_import_url('https://user:pass@calendar.google.com/x')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 port explicite refusé', $$SELECT public.set_calendar_import_url('https://calendar.google.com:8443/x')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 adresse IPv4 refusée', $$SELECT public.set_calendar_import_url('https://169.254.169.254/latest/meta-data/')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 adresse IPv6 refusée', $$SELECT public.set_calendar_import_url('https://[::1]/x')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 hôte sans chemin refusé', $$SELECT public.set_calendar_import_url('https://calendar.google.com')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 iCloud sans numéro de serveur refusé', $$SELECT public.set_calendar_import_url('https://p-caldav.icloud.com/x')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 espace dans l''adresse refusé', $$SELECT public.set_calendar_import_url('https://calendar.google.com/a b.ics')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 tabulation dans l''adresse refusée', format($$SELECT public.set_calendar_import_url(%L)::text$$, 'https://calendar.google.com/a' || chr(9) || 'b.ics'), 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 saut de ligne dans l''adresse refusé', format($$SELECT public.set_calendar_import_url(%L)::text$$, 'https://calendar.google.com/a' || chr(10) || 'b.ics'), 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 plus de 500 caractères refusé', format($$SELECT public.set_calendar_import_url(%L)::text$$, 'https://calendar.google.com/' || repeat('a', 480)), 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 file:// refusé', $$SELECT public.set_calendar_import_url('file:///etc/passwd')::text$$, 'junto.calendar_url');
PERFORM pg_temp.denied('AG5 javascript: refusé', $$SELECT public.set_calendar_import_url('javascript:alert(1)')::text$$, 'junto.calendar_url');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG5 une adresse refusée laisse la précédente en place',
  format($$SELECT import_url FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_url')), 'https://calendar.google.com/calendar/ical/x/basic.ics');
-- Le test d'hôte lui-même (fonction interne, appelée en base).
PERFORM pg_temp.eq('AG5 calendar_import_host_ok : les 4 hôtes autorisés',
  $$SELECT (private.calendar_import_host_ok('https://calendar.google.com/x') AND private.calendar_import_host_ok('https://p12-caldav.icloud.com/x')
       AND private.calendar_import_host_ok('https://outlook.office365.com/x') AND private.calendar_import_host_ok('https://outlook.live.com/x'))::text$$, 'true');
PERFORM pg_temp.eq('AG5 calendar_import_host_ok : webcal brut refusé (normalisé avant par le setter)',
  $$SELECT private.calendar_import_host_ok('webcal://calendar.google.com/x')::text$$, 'false');
PERFORM pg_temp.eq('AG5 calendar_import_host_ok : majuscules dans l''hôte refusées',
  $$SELECT private.calendar_import_host_ok('https://CALENDAR.google.com/x')::text$$, 'false');
-- Plafond : 10 changements d'adresse par jour (ag_url en a fait 6 acceptés ;
-- un appel refusé n'est pas compté : son événement est annulé avec l'erreur).
PERFORM pg_temp.as_('ag_url');
PERFORM pg_temp.ok('AG5 7e changement accepté', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/y/basic.ics')::text$$);
PERFORM pg_temp.ok('AG5 8e changement accepté', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/z/basic.ics')::text$$);
PERFORM pg_temp.ok('AG5 9e changement accepté', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/v/basic.ics')::text$$);
-- 00578 (T-CAL-UNPLUG) : débrancher n'est jamais compté, seul poser une adresse l'est.
PERFORM pg_temp.ok('AG5 débranchement accepté (non compté)', $$SELECT public.set_calendar_import_url(NULL)::text$$);
PERFORM pg_temp.ok('AG5 10e changement accepté (le débranchement n''a pas compté)', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/w/basic.ics')::text$$);
PERFORM pg_temp.denied('AG5 11e changement du jour refusé', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/u/basic.ics')::text$$, 'junto.too_many_actions');
PERFORM pg_temp.ok('AG5 au plafond, débrancher reste possible', $$SELECT public.set_calendar_import_url(NULL)::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG5 débranché au plafond : plus d''adresse',
  format($$SELECT coalesce(import_url, 'null') FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_url')), 'null');

-- ═════ AG6 — Fonctions réservées aux fonctions Edge (service_role) ═════
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG6 aucune fonction edge exécutable par anon',
  $$SELECT count(*)::text FROM unnest(ARRAY['public.calendar_feed_bookings(text)', 'public.calendar_feed_valid(text)',
      'public.calendar_import_targets()', 'public.calendar_import_apply(uuid,jsonb,text,text)']) f
    WHERE has_function_privilege('anon', f::regprocedure, 'EXECUTE')$$, '0');
PERFORM pg_temp.eq('AG6 aucune fonction edge exécutable par authenticated',
  $$SELECT count(*)::text FROM unnest(ARRAY['public.calendar_feed_bookings(text)', 'public.calendar_feed_valid(text)',
      'public.calendar_import_targets()', 'public.calendar_import_apply(uuid,jsonb,text,text)']) f
    WHERE has_function_privilege('authenticated', f::regprocedure, 'EXECUTE')$$, '0');
PERFORM pg_temp.eq('AG6 les 4 fonctions edge restent exécutables par service_role',
  $$SELECT count(*)::text FROM unnest(ARRAY['public.calendar_feed_bookings(text)', 'public.calendar_feed_valid(text)',
      'public.calendar_import_targets()', 'public.calendar_import_apply(uuid,jsonb,text,text)']) f
    WHERE has_function_privilege('service_role', f::regprocedure, 'EXECUTE')$$, '4');
PERFORM pg_temp.eq('AG6 CALENDAR-5 l''ancienne signature à 3 paramètres n''existe plus',
  $$SELECT (to_regprocedure('public.calendar_import_apply(uuid,jsonb,text)') IS NULL)::text$$, 'true');
PERFORM pg_temp.eq('AG6 fonctions internes (déclencheur d''import, création de lien, test d''hôte) fermées aux clients',
  $$SELECT count(*)::text FROM unnest(ARRAY['private.trigger_calendar_import()', 'private.ensure_calendar_link(uuid)', 'private.calendar_import_host_ok(text)']) f,
      unnest(ARRAY['anon', 'authenticated']) r
    WHERE has_function_privilege(r, f::regprocedure, 'EXECUTE')$$, '0');
PERFORM pg_temp.eq('AG6 les RPC client du pro ne sont pas exécutables par anon',
  $$SELECT count(*)::text FROM unnest(ARRAY['public.get_calendar_links()', 'public.regenerate_calendar_export()',
      'public.set_calendar_export_hide_names(boolean)', 'public.set_calendar_import_url(text)']) f
    WHERE has_function_privilege('anon', f::regprocedure, 'EXECUTE')$$, '0');
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.denied('AG6 le pro ne lit pas son flux par la fonction edge', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok')));
PERFORM pg_temp.denied('AG6 le pro ne teste pas un jeton', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok')));
PERFORM pg_temp.denied('AG6 le pro ne liste pas les adresses importées', $$SELECT count(*)::text FROM public.calendar_import_targets()$$);
PERFORM pg_temp.denied('AG6 le pro n''écrit pas ses demi-journées occupées par la fonction edge',
  format($$SELECT public.calendar_import_apply(%L, '[]'::jsonb, NULL)::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.as_('ag_cli');
PERFORM pg_temp.denied('AG6 un membre ne lit pas le flux d''un pro avec son jeton', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok')));
PERFORM pg_temp.denied('AG6 un membre ne vide pas l''agenda importé d''un pro',
  format($$SELECT public.calendar_import_apply(%L, '[]'::jsonb, NULL)::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.as_('anon');
PERFORM pg_temp.denied('AG6 anon ne lit pas de flux', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok')));
PERFORM pg_temp.denied('AG6 anon ne teste pas de jeton', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok')));
PERFORM pg_temp.denied('AG6 anon ne liste pas les adresses importées', $$SELECT count(*)::text FROM public.calendar_import_targets()$$);
PERFORM pg_temp.denied('AG6 anon n''écrit pas de demi-journées occupées',
  format($$SELECT public.calendar_import_apply(%L, '[]'::jsonb, NULL)::text$$, pg_temp.id('ag_pro')));

-- ═════ AG7 — Le flux d'export (calendar_feed_bookings), comme l'appelle l'edge ═════
-- Réservations de ag_pro, insérées en base (T = aujourd'hui, Europe/Paris).
PERFORM pg_temp.as_('db');
PERFORM pg_temp.put('bk_pend', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_acc', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_cancel', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_declined', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_expired', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_manual', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_m31', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_m32', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_p190', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_p191', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_multi', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_multi_old', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_multi_gone', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_other_pro', gen_random_uuid()::text);
INSERT INTO public.bookings (id, offering_id, pro_id, client_id, manual_name, day, period, end_day, party_size, status) VALUES
  (pg_temp.id('bk_pend'),      pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'),  NULL, pg_temp.d(5),   'am', NULL, 2, 'pending'),
  (pg_temp.id('bk_acc'),       pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli2'), NULL, pg_temp.d(6),   'pm', NULL, 3, 'accepted'),
  (pg_temp.id('bk_cancel'),    pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'),  NULL, pg_temp.d(7),   'am', NULL, 1, 'cancelled'),
  (pg_temp.id('bk_declined'),  pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'),  NULL, pg_temp.d(8),   'am', NULL, 1, 'declined'),
  (pg_temp.id('bk_expired'),   pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'),  NULL, pg_temp.d(-2),   'am', NULL, 1, 'expired'),
  (pg_temp.id('bk_manual'),    pg_temp.id('ag_off'), pg_temp.id('ag_pro'), NULL, 'Client Manuel',   pg_temp.d(9),   'pm', NULL, 4, 'accepted'),
  (pg_temp.id('bk_m31'),       pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'),  NULL, pg_temp.d(-31),  'am', NULL, 1, 'accepted'),
  (pg_temp.id('bk_m32'),       pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'),  NULL, pg_temp.d(-32),  'am', NULL, 1, 'accepted'),
  (pg_temp.id('bk_p190'),      pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'),  NULL, pg_temp.d(190), 'am', NULL, 1, 'pending'),
  (pg_temp.id('bk_p191'),      pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'),  NULL, pg_temp.d(191), 'am', NULL, 1, 'pending'),
  (pg_temp.id('bk_multi'),     pg_temp.id('ag_off2'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'), NULL, pg_temp.d(30),  'am', pg_temp.d(32), 2, 'accepted'),
  (pg_temp.id('bk_multi_old'), pg_temp.id('ag_off2'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'), NULL, pg_temp.d(-35),  'am', pg_temp.d(-30), 2, 'accepted'),
  (pg_temp.id('bk_multi_gone'),pg_temp.id('ag_off2'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'), NULL, pg_temp.d(-45),  'am', pg_temp.d(-40), 2, 'accepted'),
  (pg_temp.id('bk_other_pro'), pg_temp.id('ag_off_p2'), pg_temp.id('ag_pro2'), pg_temp.id('ag_cli'), NULL, pg_temp.d(5), 'am', NULL, 1, 'accepted');
-- Une date fixe (00575) sur 3 jours avec ses inscrits, et une date fixe annulée.
PERFORM pg_temp.put('ag_sess', gen_random_uuid()::text);
PERFORM pg_temp.put('ag_sess_x', gen_random_uuid()::text);
INSERT INTO public.pro_sessions (id, pro_id, offering_id, start_day, start_period, end_day, end_period, max_participants, status) VALUES
  (pg_temp.id('ag_sess'),   pg_temp.id('ag_pro'), pg_temp.id('ag_off'), pg_temp.d(20), 'am', pg_temp.d(22), 'pm', 8, 'scheduled'),
  (pg_temp.id('ag_sess_x'), pg_temp.id('ag_pro'), pg_temp.id('ag_off'), pg_temp.d(40), 'am', pg_temp.d(40), 'pm', 6, 'cancelled');
PERFORM pg_temp.put('bk_s1', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_s2', gen_random_uuid()::text);
PERFORM pg_temp.put('bk_s3', gen_random_uuid()::text);
INSERT INTO public.bookings (id, offering_id, pro_id, client_id, day, period, party_size, status, session_id) VALUES
  (pg_temp.id('bk_s1'), pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli'),  pg_temp.d(20), 'am', 3, 'accepted', pg_temp.id('ag_sess')),
  (pg_temp.id('bk_s2'), pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli2'), pg_temp.d(20), 'am', 2, 'accepted', pg_temp.id('ag_sess')),
  (pg_temp.id('bk_s3'), pg_temp.id('ag_off'), pg_temp.id('ag_pro'), pg_temp.id('ag_cli3'), pg_temp.d(20), 'am', 1, 'cancelled', pg_temp.id('ag_sess'));

-- Jetons invalides : rien.
PERFORM pg_temp.eq('AG7 jeton NULL : aucune ligne', $$SELECT count(*)::text FROM public.calendar_feed_bookings(NULL)$$, '0');
PERFORM pg_temp.eq('AG7 jeton mal formé : aucune ligne', $$SELECT count(*)::text FROM public.calendar_feed_bookings('abc')$$, '0');
PERFORM pg_temp.eq('AG7 jeton en majuscules : aucune ligne', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, upper(pg_temp.get('ag_tok'))), '0');
PERFORM pg_temp.eq('AG7 jeton avec un motif SQL : aucune ligne', $$SELECT count(*)::text FROM public.calendar_feed_bookings('%')$$, '0');
PERFORM pg_temp.eq('AG7 jeton inconnu bien formé : aucune ligne', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, repeat('0', 64)), '0');
PERFORM pg_temp.eq('AG7 jeton révoqué (régénéré) : aucune ligne', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok0')), '0');
PERFORM pg_temp.eq('AG7 calendar_feed_valid : mal formé', $$SELECT coalesce(public.calendar_feed_valid('abc'), false)::text$$, 'false');
PERFORM pg_temp.eq('AG7 calendar_feed_valid : NULL', $$SELECT coalesce(public.calendar_feed_valid(NULL), false)::text$$, 'false');
PERFORM pg_temp.eq('AG7 calendar_feed_valid : inconnu', format($$SELECT public.calendar_feed_valid(%L)::text$$, repeat('0', 64)), 'false');
PERFORM pg_temp.eq('AG7 calendar_feed_valid : jeton courant', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok')), 'true');

-- Contenu du flux de ag_pro.
PERFORM pg_temp.eq('AG7 demande en attente listée, avec le nom du client',
  format($$SELECT status || '/' || client_name || '/' || party_size || '/' || is_manual::text || '/' || kind FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('bk_pend')),
  'pending/Léa Cliente/2/false/booking');
PERFORM pg_temp.eq('AG7 réservation acceptée listée, sur sa demi-journée',
  format($$SELECT status || '/' || client_name || '/' || period || '/' || (end_day = day)::text || '/' || end_period FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('bk_acc')),
  'accepted/Marc Client/pm/true/pm');
PERFORM pg_temp.eq('AG7 le titre de l''offre est fourni', format($$SELECT offering_title FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('bk_acc')), 'Sortie agenda');
PERFORM pg_temp.eq('AG7 annulée, refusée, expirée : absentes',
  format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L) WHERE id IN (%L, %L, %L)$$, pg_temp.get('ag_tok'), pg_temp.id('bk_cancel'), pg_temp.id('bk_declined'), pg_temp.id('bk_expired')), '0');
PERFORM pg_temp.eq('AG7 réservation manuelle : nom saisi par le pro, marquée manuelle',
  format($$SELECT client_name || '/' || is_manual::text FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('bk_manual')), 'Client Manuel/true');
PERFORM pg_temp.eq('AG7 fenêtre : J-31 inclus, J-32 exclu',
  format($$SELECT string_agg(id::text, ',') = %L FROM public.calendar_feed_bookings(%L) WHERE id IN (%L, %L)$$, pg_temp.id('bk_m31')::text, pg_temp.get('ag_tok'), pg_temp.id('bk_m31'), pg_temp.id('bk_m32')), 'true');
PERFORM pg_temp.eq('AG7 fenêtre : J+190 inclus, J+191 exclu',
  format($$SELECT string_agg(id::text, ',') = %L FROM public.calendar_feed_bookings(%L) WHERE id IN (%L, %L)$$, pg_temp.id('bk_p190')::text, pg_temp.get('ag_tok'), pg_temp.id('bk_p190'), pg_temp.id('bk_p191')), 'true');
PERFORM pg_temp.eq('AG7 demande sur plusieurs jours : du matin du 1er jour à l''après-midi du dernier',
  format($$SELECT period || '→' || (end_day - day)::text || 'j/' || end_period FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('bk_multi')), 'am→2j/pm');
PERFORM pg_temp.eq('AG7 plusieurs jours commencés avant J-31 mais finis après : listée',
  format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('bk_multi_old')), '1');
PERFORM pg_temp.eq('AG7 plusieurs jours finis avant J-31 : absente',
  format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('bk_multi_gone')), '0');
PERFORM pg_temp.eq('AG7 la réservation d''un autre pro n''apparaît pas',
  format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('bk_other_pro')), '0');
PERFORM pg_temp.eq('AG7 date fixe : une seule ligne, sur toute sa durée',
  format($$SELECT kind || '/' || start_ok || '/' || end_period || '/' || max_participants FROM (SELECT kind, (day = pg_temp.d(20) AND end_day = pg_temp.d(22))::text AS start_ok, end_period, max_participants FROM public.calendar_feed_bookings(%L) WHERE id = %L) x$$, pg_temp.get('ag_tok'), pg_temp.id('ag_sess')),
  'session/true/pm/8');
PERFORM pg_temp.eq('AG7 date fixe : places = inscrits acceptés (3 + 2, l''annulé ne compte pas)',
  format($$SELECT party_size::text FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('ag_sess')), '5');
PERFORM pg_temp.eq('AG7 date fixe : aucun nom de client',
  format($$SELECT coalesce(client_name, 'null') FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('ag_sess')), 'null');
PERFORM pg_temp.eq('AG7 les inscriptions à une date fixe ne sont pas listées une à une',
  format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L) WHERE id IN (%L, %L, %L)$$, pg_temp.get('ag_tok'), pg_temp.id('bk_s1'), pg_temp.id('bk_s2'), pg_temp.id('bk_s3')), '0');
PERFORM pg_temp.eq('AG7 une date fixe annulée n''apparaît pas',
  format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L) WHERE id = %L$$, pg_temp.get('ag_tok'), pg_temp.id('ag_sess_x')), '0');
PERFORM pg_temp.eq('AG7 total du flux : 7 réservations + 1 date fixe',
  format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok')), '8');
PERFORM pg_temp.eq('AG7 le flux n''expose ni téléphone, ni message, ni fiche participant (colonnes fixes)',
  $$SELECT count(*)::text FROM pg_proc p, unnest(p.proargnames) a WHERE p.oid = 'public.calendar_feed_bookings(text)'::regprocedure
      AND a IN ('manual_phone', 'message', 'participant_info', 'client_id', 'phone', 'email')$$, '0');
-- Noms masqués : le drapeau accompagne chaque ligne (l'edge remplace alors le nom par « Réservation »).
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.ok('AG7 le pro masque les noms', $$SELECT public.set_calendar_export_hide_names(true)::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG7 noms masqués : drapeau levé sur chaque ligne',
  format($$SELECT bool_and(hide_names)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok')), 'true');
PERFORM pg_temp.eq('AG7 noms masqués : même contenu qu''avant',
  format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok')), '8');
-- 00578 (T-CAL-NAMES) : masqués dès la base, pas seulement dans la fonction edge (clients et saisies manuelles).
PERFORM pg_temp.eq('AG7 noms masqués : aucun nom de client rendu par le flux',
  format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L) WHERE client_name IS NOT NULL$$, pg_temp.get('ag_tok')), '0');
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.ok('AG7 le pro réaffiche les noms', $$SELECT public.set_calendar_export_hide_names(false)::text$$);

-- Pro suspendu, pro sans tier pro, candidature : flux vide, jeton invalide.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG7 ag_pro2 : flux actif avant suspension', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok_p2')), '1');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = now() WHERE id = pg_temp.id('ag_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('AG7 pro suspendu : flux vide', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok_p2')), '0');
PERFORM pg_temp.eq('AG7 pro suspendu : jeton invalide (404)', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok_p2')), 'false');
PERFORM pg_temp.as_('ag_pro2');
PERFORM pg_temp.denied('AG7 pro suspendu : plus de get_calendar_links', $$SELECT count(*)::text FROM public.get_calendar_links()$$, 'Operation not permitted');
PERFORM pg_temp.denied('AG7 pro suspendu : pas de régénération', $$SELECT public.regenerate_calendar_export()$$, 'Operation not permitted');
PERFORM pg_temp.denied('AG7 pro suspendu : pas de masquage', $$SELECT public.set_calendar_export_hide_names(true)::text$$, 'Operation not permitted');
PERFORM pg_temp.as_('db');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = NULL, tier = 'free' WHERE id = pg_temp.id('ag_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('AG7 pro approuvé mais sans tier pro : flux vide', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok_p2')), '0');
PERFORM pg_temp.eq('AG7 pro sans tier pro : jeton invalide', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok_p2')), 'false');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET tier = 'pro' WHERE id = pg_temp.id('ag_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
-- Une candidature en attente qui aurait une ligne (créée en base) ne sert rien.
PERFORM private.ensure_calendar_link(pg_temp.id('ag_cand'));
PERFORM pg_temp.put('ag_tok_cand', pg_temp.ag_token('ag_cand'));
PERFORM pg_temp.eq('AG7 candidature en attente : jeton invalide', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok_cand')), 'false');
PERFORM pg_temp.eq('AG7 candidature en attente : flux vide', format($$SELECT count(*)::text FROM public.calendar_feed_bookings(%L)$$, pg_temp.get('ag_tok_cand')), '0');

-- ═════ AG8 — Import : adresses à lire (calendar_import_targets) ═════
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.ok('AG8 ag_pro branche son agenda Google', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/pro/private-1/basic.ics')::text$$);
PERFORM pg_temp.eq('AG8 branché : pas encore synchronisé, pas d''erreur',
  $$SELECT import_connected::text || '/' || coalesce(import_synced_at::text, 'null') || '/' || coalesce(import_error, 'null') FROM public.get_calendar_links()$$, 'true/null/null');
PERFORM pg_temp.as_('ag_pro2');
PERFORM pg_temp.ok('AG8 ag_pro2 branche son agenda Outlook', $$SELECT public.set_calendar_import_url('https://outlook.live.com/owa/calendar/p2/calendar.ics')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG8 le pro branché est listé avec son adresse',
  format($$SELECT import_url FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_pro')), 'https://calendar.google.com/calendar/ical/pro/private-1/basic.ics');
PERFORM pg_temp.eq('AG8 un pro débranché n''est pas listé', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_url')), '0');
PERFORM pg_temp.eq('AG8 un membre sans lien n''est pas listé', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_cli')), '0');
-- Adresse posée en base hors liste d'hôtes (ex. reprise) : jamais lue.
UPDATE private.pro_calendar_links SET import_url = 'https://evil.example/cal.ics' WHERE pro_id = pg_temp.id('ag_cand');
PERFORM pg_temp.eq('AG8 candidature en attente : jamais lue', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_cand')), '0');
UPDATE private.pro_calendar_links SET import_url = 'https://evil.example/cal.ics' WHERE pro_id = pg_temp.id('ag_url');
PERFORM pg_temp.eq('AG8 hôte hors liste stocké en base : jamais lu', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_url')), '0');
UPDATE private.pro_calendar_links SET import_url = NULL WHERE pro_id IN (pg_temp.id('ag_url'), pg_temp.id('ag_cand'));
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = now() WHERE id = pg_temp.id('ag_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('AG8 pro suspendu : son agenda n''est plus lu', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_pro2')), '0');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET suspended_at = NULL WHERE id = pg_temp.id('ag_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('AG8 levée de suspension : de nouveau lu', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_pro2')), '1');
-- 00578 (T-CAL-TIER) : comme le flux d'export, l'import exige le tier pro.
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET tier = 'free' WHERE id = pg_temp.id('ag_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('AG8 pro approuvé mais sans tier pro : son agenda n''est pas lu', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_pro2')), '0');
PERFORM set_config('junto.bypass_lock', 'true', true);
UPDATE public.users SET tier = 'pro' WHERE id = pg_temp.id('ag_pro2');
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.eq('AG8 tier pro rendu : de nouveau lu', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_pro2')), '1');

-- ═════ AG9 — Import : écriture des demi-journées occupées (calendar_import_apply) ═════
PERFORM pg_temp.ok('AG9 résultat d''import appliqué',
  format($$SELECT public.calendar_import_apply(%L, jsonb_build_array(pg_temp.ag_slot(3, 'am'), pg_temp.ag_slot(3, 'am'), pg_temp.ag_slot(11, 'pm'),
      pg_temp.ag_slot(190, 'am'), pg_temp.ag_slot(-1, 'am'), pg_temp.ag_slot(191, 'pm'), pg_temp.ag_slot(4, 'night'),
      jsonb_build_object('day', 'demain', 'period', 'am'), jsonb_build_object('period', 'pm'), '"texte"'::jsonb), NULL)::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.eq('AG9 gardés : J+3 matin (dédoublonné), J+11 après-midi, J+190 ; écartés : passé, > J+190, période ou jour invalides',
  format($$SELECT string_agg((day - pg_temp.d(0))::text || period, ',' ORDER BY day, period) FROM private.pro_busy_slots WHERE pro_id = %L$$, pg_temp.id('ag_pro')), '3am,11pm,190am');
PERFORM pg_temp.eq('AG9 synchronisé, sans erreur',
  format($$SELECT (import_synced_at IS NOT NULL)::text || '/' || coalesce(import_error, 'null') FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_pro')), 'true/null');
PERFORM pg_temp.eq('AG9 les demi-journées d''un pro ne touchent pas un autre', $$SELECT pg_temp.ag_busy('ag_pro2')$$, '0');
-- Une erreur de lecture garde les demi-journées connues.
PERFORM pg_temp.ok('AG9 erreur de lecture signalée', format($$SELECT public.calendar_import_apply(%L, NULL, 'unreachable')::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.eq('AG9 erreur : les demi-journées précédentes restent', $$SELECT pg_temp.ag_busy('ag_pro')$$, '3');
PERFORM pg_temp.eq('AG9 erreur : enregistrée et visible du pro (code fixe, pas d''adresse)',
  format($$SELECT import_error FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_pro')), 'unreachable');
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.eq('AG9 le pro lit l''erreur', $$SELECT import_error FROM public.get_calendar_links()$$, 'unreachable');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('AG9 erreur trop longue', format($$SELECT public.calendar_import_apply(%L, '[]'::jsonb, repeat('x', 300))::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.eq('AG9 erreur coupée à 200 caractères', format($$SELECT char_length(import_error)::text FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_pro')), '200');
PERFORM pg_temp.eq('AG9 l''erreur l''emporte sur la liste (rien n''est effacé)', $$SELECT pg_temp.ag_busy('ag_pro')$$, '3');
-- Validation du tableau.
PERFORM pg_temp.denied('AG9 ni liste ni erreur : refusé', format($$SELECT public.calendar_import_apply(%L, NULL, NULL)::text$$, pg_temp.id('ag_pro')), 'Operation not permitted');
PERFORM pg_temp.denied('AG9 un objet au lieu d''un tableau : refusé', format($$SELECT public.calendar_import_apply(%L, '{"day":"2030-01-01"}'::jsonb, NULL)::text$$, pg_temp.id('ag_pro')), 'Operation not permitted');
PERFORM pg_temp.denied('AG9 plus de 400 créneaux : refusé',
  format($$SELECT public.calendar_import_apply(%L, (SELECT jsonb_agg(pg_temp.ag_slot(3, 'am')) FROM generate_series(1, 401)), NULL)::text$$, pg_temp.id('ag_pro')), 'Operation not permitted');
PERFORM pg_temp.eq('AG9 un lot refusé ne change rien', $$SELECT pg_temp.ag_busy('ag_pro')$$, '3');
PERFORM pg_temp.ok('AG9 400 créneaux : accepté',
  format($$SELECT public.calendar_import_apply(%L, (SELECT jsonb_agg(pg_temp.ag_slot(3 + (g %% 2), CASE WHEN g %% 3 = 0 THEN 'am' ELSE 'pm' END)) FROM generate_series(1, 400) g), NULL)::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.eq('AG9 un lot remplace entièrement le précédent', $$SELECT pg_temp.ag_busy('ag_pro')$$, '4');
PERFORM pg_temp.eq('AG9 un succès efface l''erreur précédente', format($$SELECT coalesce(import_error, 'null') FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_pro')), 'null');
PERFORM pg_temp.ok('AG9 liste vide : plus rien d''occupé', format($$SELECT public.calendar_import_apply(%L, '[]'::jsonb, NULL)::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.eq('AG9 liste vide appliquée', $$SELECT pg_temp.ag_busy('ag_pro')$$, '0');
-- 00578 (T-CAL-DATE) : une date impossible est sautée, le reste du lot est appliqué.
PERFORM pg_temp.ok('AG9 une date impossible dans le lot ne fait pas échouer l''import',
  format($$SELECT public.calendar_import_apply(%L, jsonb_build_array(pg_temp.ag_slot(3, 'am'),
      jsonb_build_object('day', (extract(year FROM pg_temp.d(30))::int + 1)::text || '-02-30', 'period', 'am'),
      jsonb_build_object('day', to_char(pg_temp.d(5), 'YYYY-MM') || '-32', 'period', 'pm'),
      jsonb_build_object('day', to_char(pg_temp.d(5), 'YYYY') || '-13-01', 'period', 'pm')), NULL)::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.eq('AG9 date impossible : seule la date valide est gardée',
  format($$SELECT string_agg((day - pg_temp.d(0))::text || period, ',') FROM private.pro_busy_slots WHERE pro_id = %L$$, pg_temp.id('ag_pro')), '3am');
PERFORM pg_temp.ok('AG9 retour à une liste vide', format($$SELECT public.calendar_import_apply(%L, '[]'::jsonb, NULL)::text$$, pg_temp.id('ag_pro')));
-- Pro sans import branché : rien n'est écrit.
PERFORM pg_temp.ok('AG9 membre sans lien : appel sans effet', format($$SELECT public.calendar_import_apply(%L, jsonb_build_array(pg_temp.ag_slot(3, 'am')), NULL)::text$$, pg_temp.id('ag_cli')));
PERFORM pg_temp.eq('AG9 membre sans lien : aucune ligne créée',
  format($$SELECT (SELECT count(*) FROM private.pro_busy_slots WHERE pro_id = %L) + (SELECT count(*) FROM private.pro_calendar_links WHERE pro_id = %L)$$, pg_temp.id('ag_cli'), pg_temp.id('ag_cli')), '0');
PERFORM pg_temp.ok('AG9 pro débranché : appel sans effet', format($$SELECT public.calendar_import_apply(%L, jsonb_build_array(pg_temp.ag_slot(3, 'am')), NULL)::text$$, pg_temp.id('ag_url')));
PERFORM pg_temp.eq('AG9 pro débranché : aucune demi-journée écrite', $$SELECT pg_temp.ag_busy('ag_url')$$, '0');
PERFORM pg_temp.ok('AG9 pro débranché : une erreur n''est pas enregistrée non plus', format($$SELECT public.calendar_import_apply(%L, NULL, 'unreachable')::text$$, pg_temp.id('ag_url')));
PERFORM pg_temp.eq('AG9 pro débranché : pas d''erreur affichée', format($$SELECT coalesce(import_error, 'null') FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_url')), 'null');

-- ═════ AG10 — Effet des demi-journées occupées sur la réservation ═════
PERFORM pg_temp.as_('ag_pro');
PERFORM public.set_pro_availability(pg_temp.d(3), 'am', true);
PERFORM public.set_pro_availability(pg_temp.d(3), 'pm', true);
PERFORM public.set_pro_availability(pg_temp.d(12), 'am', true);
PERFORM public.set_pro_availability(pg_temp.d(12), 'pm', true);
PERFORM public.set_pro_availability(pg_temp.d(13), 'am', true);
PERFORM public.set_pro_availability(pg_temp.d(13), 'pm', true);
PERFORM pg_temp.ok('AG10 l''offre plusieurs jours se demande sur 2 jours', format($$SELECT public.set_offering_request_length(%L, 2)::text$$, pg_temp.id('ag_off2')));
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('AG10 import : J+3 matin et J+13 après-midi occupés',
  format($$SELECT public.calendar_import_apply(%L, jsonb_build_array(pg_temp.ag_slot(3, 'am'), pg_temp.ag_slot(13, 'pm')), NULL)::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.as_('ag_cli3');
PERFORM pg_temp.eq('AG10 la demi-journée occupée disparaît des disponibilités',
  format($$SELECT count(*)::text FROM public.get_pro_availability(%L) WHERE day = pg_temp.d(3) AND period = 'am'$$, pg_temp.id('ag_pro')), '0');
PERFORM pg_temp.eq('AG10 l''autre demi-journée reste proposée',
  format($$SELECT count(*)::text FROM public.get_pro_availability(%L) WHERE day = pg_temp.d(3) AND period = 'pm'$$, pg_temp.id('ag_pro')), '1');
PERFORM pg_temp.denied('AG10 réserver une demi-journée occupée est refusé',
  format($$SELECT public.create_booking(%L, pg_temp.d(3), 'am', 1)::text$$, pg_temp.id('ag_off')), 'junto.booking_slot_unavailable');
PERFORM pg_temp.ok('AG10 réserver la demi-journée libre reste possible',
  format($$SELECT public.create_booking(%L, pg_temp.d(3), 'pm', 1)::text$$, pg_temp.id('ag_off')));
PERFORM pg_temp.denied('AG10 une demande sur 2 jours qui touche une demi-journée occupée est refusée',
  format($$SELECT public.create_booking(%L, pg_temp.d(12), 'am', 1)::text$$, pg_temp.id('ag_off2')), 'junto.booking_slot_unavailable');
PERFORM pg_temp.as_('ag_pro');
PERFORM pg_temp.eq('AG10 le pro voit ses demi-journées occupées dans son agenda',
  $$SELECT count(*)::text FROM public.get_pro_agenda(pg_temp.d(0), pg_temp.d(30)) WHERE kind = 'busy'$$, '2');
-- Débrancher l'agenda oublie les demi-journées occupées.
PERFORM pg_temp.ok('AG10 le pro débranche son agenda', $$SELECT public.set_calendar_import_url('   ')::text$$);
PERFORM pg_temp.eq('AG10 débranché : get_calendar_links le dit', $$SELECT import_connected::text || '/' || coalesce(import_synced_at::text, 'null') FROM public.get_calendar_links()$$, 'false/null');
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG10 débranché : demi-journées occupées effacées', $$SELECT pg_temp.ag_busy('ag_pro')$$, '0');
PERFORM pg_temp.eq('AG10 débranché : plus lu par l''import', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_pro')), '0');
PERFORM pg_temp.ok('AG10 un résultat arrivé après le débranchement est ignoré',
  format($$SELECT public.calendar_import_apply(%L, jsonb_build_array(pg_temp.ag_slot(3, 'am')), NULL)::text$$, pg_temp.id('ag_pro')));
PERFORM pg_temp.eq('AG10 rien n''est réécrit', $$SELECT pg_temp.ag_busy('ag_pro')$$, '0');
PERFORM pg_temp.as_('ag_cli3');
PERFORM pg_temp.eq('AG10 la demi-journée redevient proposée',
  format($$SELECT count(*)::text FROM public.get_pro_availability(%L) WHERE day = pg_temp.d(3) AND period = 'am'$$, pg_temp.id('ag_pro')), '1');
-- Changer d'adresse remet la synchro à zéro.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('AG10 ag_pro2 : premier import réussi', format($$SELECT public.calendar_import_apply(%L, jsonb_build_array(pg_temp.ag_slot(5, 'pm')), NULL)::text$$, pg_temp.id('ag_pro2')));
PERFORM pg_temp.as_('ag_pro2');
PERFORM pg_temp.ok('AG10 ag_pro2 change d''adresse', $$SELECT public.set_calendar_import_url('https://outlook.office365.com/owa/calendar/p2/nouveau.ics')::text$$);
PERFORM pg_temp.eq('AG10 nouvelle adresse : synchro remise à zéro', $$SELECT coalesce(import_synced_at::text, 'null') || '/' || coalesce(import_error, 'null') FROM public.get_calendar_links()$$, 'null/null');
-- Plafond des changements d'adresse, posé en base (10 par jour).
PERFORM pg_temp.as_('db');
INSERT INTO public.rate_events (user_id, kind) SELECT pg_temp.id('ag_pro2'), 'calendar_import_set' FROM generate_series(1, 10);
PERFORM pg_temp.as_('ag_pro2');
PERFORM pg_temp.denied('AG10 plafond atteint : changer d''adresse est refusé', $$SELECT public.set_calendar_import_url('https://outlook.office365.com/owa/calendar/p2/autre.ics')::text$$, 'junto.too_many_actions');
-- (débrancher au plafond reste possible — testé après CALENDAR-5, qui a besoin de l'adresse branchée)

-- ═════ AG11 — Failles de l'audit (CALENDAR-5 / CALENDAR-4 corrigés 00578 ; CALENDAR-7 plateforme) ═════
-- CALENDAR-5 : un import qui a lu l'ANCIENNE adresse n'écrase pas la nouvelle.
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG11 CALENDAR-5 résultat lu sur l''ancienne adresse ignoré',
  $$SELECT pg_temp.ag_apply_read_url('ag_pro2', jsonb_build_array(pg_temp.ag_slot(6, 'am'), pg_temp.ag_slot(7, 'am')), 'https://outlook.live.com/owa/calendar/p2/calendar.ics')$$,
  '1');
PERFORM pg_temp.eq('AG11 CALENDAR-5 résultat lu sur l''adresse courante appliqué',
  $$SELECT pg_temp.ag_apply_read_url('ag_pro2', jsonb_build_array(pg_temp.ag_slot(6, 'am'), pg_temp.ag_slot(7, 'am')), 'https://outlook.office365.com/owa/calendar/p2/nouveau.ics')$$,
  '2');
-- 00578 (T-CAL-UNPLUG) : au plafond des changements d'adresse, débrancher reste possible.
PERFORM pg_temp.as_('ag_pro2');
PERFORM pg_temp.ok('AG10 plafond atteint : débrancher reste possible (non compté)', $$SELECT public.set_calendar_import_url(NULL)::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG10 débranché au plafond : plus d''adresse, demi-journées effacées',
  format($$SELECT coalesce(import_url, 'null') || '/' || pg_temp.ag_busy('ag_pro2') FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_pro2')), 'null/0');
PERFORM pg_temp.ok('AG11 CALENDAR-5 un résultat arrivé après le débranchement (adresse lue fournie) est ignoré',
  $$SELECT pg_temp.ag_apply_read_url('ag_pro2', jsonb_build_array(pg_temp.ag_slot(6, 'am')), 'https://outlook.office365.com/owa/calendar/p2/nouveau.ics')$$);
PERFORM pg_temp.eq('AG11 CALENDAR-5 rien n''est réécrit après le débranchement', $$SELECT pg_temp.ag_busy('ag_pro2')$$, '0');

-- CALENDAR-7 : pg_net (requêtes HTTP sortantes) fermé aux clients. Hors de notre portée : le schéma net
-- appartient à supabase_admin, un REVOKE fait par postgres (00578) reste sans effet, et net n'est pas
-- exposé par PostgREST (aucun appel client possible en pratique). Gardé en xfail sous l'identifiant
-- CALENDAR-7-PLATFORM, à lever si la plateforme change ces droits.
PERFORM pg_temp.eq('AG11 CALENDAR-7 net.http_get/post/delete non exécutables par anon',
  $$SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'net' AND p.proname IN ('http_get', 'http_post', 'http_delete') AND has_function_privilege('anon', p.oid, 'EXECUTE')$$, '0', 'CALENDAR-7-PLATFORM');
PERFORM pg_temp.eq('AG11 CALENDAR-7 net.http_get/post/delete non exécutables par authenticated',
  $$SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'net' AND p.proname IN ('http_get', 'http_post', 'http_delete') AND has_function_privilege('authenticated', p.oid, 'EXECUTE')$$, '0', 'CALENDAR-7-PLATFORM');
PERFORM pg_temp.eq('AG11 net.http_* existent bien (le contrôle ci-dessus n''est pas vide)',
  $$SELECT (count(*) >= 3)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'net' AND p.proname IN ('http_get', 'http_post', 'http_delete')$$, 'true');

-- CALENDAR-4 (corrigé 00578) : se désinscrire comme pro coupe le flux et l'import pour de bon.
PERFORM pg_temp.as_('ag_pro3');
PERFORM pg_temp.put('ag_tok3', pg_temp.ok('AG11 ag_pro3 lit son jeton', $$SELECT export_token FROM public.get_calendar_links()$$));
PERFORM pg_temp.ok('AG11 ag_pro3 branche son agenda', $$SELECT public.set_calendar_import_url('https://calendar.google.com/calendar/ical/p3/basic.ics')::text$$);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.ok('AG11 ag_pro3 : import appliqué', format($$SELECT public.calendar_import_apply(%L, jsonb_build_array(pg_temp.ag_slot(4, 'am')), NULL)::text$$, pg_temp.id('ag_pro3')));
PERFORM pg_temp.as_('ag_pro3');
PERFORM pg_temp.ok('AG11 ag_pro3 se désinscrit', $$SELECT public.unregister_as_pro()::text$$);
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG11 désinscrit : le jeton ne vaut plus rien', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok3')), 'false');
PERFORM pg_temp.eq('AG11 désinscrit : plus lu par l''import', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_pro3')), '0');
PERFORM pg_temp.eq('AG11 CALENDAR-4 désinscrit : le lien (jeton, adresse importée) est supprimé',
  format($$SELECT count(*)::text FROM private.pro_calendar_links WHERE pro_id = %L$$, pg_temp.id('ag_pro3')), '0');
PERFORM pg_temp.eq('AG11 CALENDAR-4 désinscrit : les demi-journées occupées sont supprimées', $$SELECT pg_temp.ag_busy('ag_pro3')$$, '0');
PERFORM pg_temp.as_('ag_pro3');
PERFORM pg_temp.ok('AG11 ag_pro3 se réinscrit', pg_temp.ag_register_sql('Agenda Trois bis'));
PERFORM pg_temp.as_('ag_adm');
PERFORM pg_temp.ok('AG11 ag_pro3 est de nouveau approuvé', format($$SELECT public.approve_pro(%L)::text$$, pg_temp.id('ag_pro3')));
PERFORM set_config('junto.bypass_lock', 'false', true);
PERFORM pg_temp.as_('db');
PERFORM pg_temp.eq('AG11 CALENDAR-4 réapprouvé : l''ancien jeton ne revit pas', format($$SELECT public.calendar_feed_valid(%L)::text$$, pg_temp.get('ag_tok3')), 'false');
PERFORM pg_temp.eq('AG11 CALENDAR-4 réapprouvé : l''ancienne adresse n''est pas relue', format($$SELECT count(*)::text FROM public.calendar_import_targets() WHERE pro_id = %L$$, pg_temp.id('ag_pro3')), '0');
PERFORM pg_temp.as_('ag_pro3');
PERFORM pg_temp.eq('AG11 CALENDAR-4 réapprouvé : un nouveau jeton est remis', format($$SELECT (export_token <> %L)::text FROM public.get_calendar_links()$$, pg_temp.get('ag_tok3')), 'true');
