-- ============================================================================
-- 00478 — Phase A2 : résidus trouvés par la contre-vérification de 00477.
--
-- DB-MS-1 get_recent_partners : colonne `id` ambiguë → liste « partenaires
--         récents » (inviter, créer un groupe) cassée pour tout le monde.
-- PR-4    La colonne participations.late_cancel_at de 00477 s'effaçait quand la
--         ligne était supprimée (refus d'une nouvelle invitation, cascade de
--         blocage) et comptait double après une réinscription suivie d'un
--         verdict de présence. → table `late_cancels` (une ligne par personne et
--         sortie, jamais supprimée par ces chemins), comptée seulement sans
--         verdict de présence et hors sorties annulées / retirées ; une nouvelle
--         annulation tardive réarme une levée précédente. Reprise depuis
--         late_cancel_at puis suppression de la colonne.
-- PR-6    Levée de pénalité impossible après réinscription, et liste des départs
--         tardifs toujours vide côté organisateur → waive_late_cancel_penalty
--         s'appuie sur le registre ; nouvelle get_late_leavers (créateur seul).
-- AB-1    La déduplication « a quitté » masquait l'avis de départ TARDIF après un
--         départ anticipé → une notification au plus par TYPE et par 24 h.
-- ============================================================================

CREATE TABLE IF NOT EXISTS late_cancels (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  at TIMESTAMPTZ NOT NULL DEFAULT now(),
  waived BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (user_id, activity_id)
);
ALTER TABLE late_cancels ENABLE ROW LEVEL SECURITY;
ALTER TABLE late_cancels FORCE ROW LEVEL SECURITY;
REVOKE ALL ON late_cancels FROM PUBLIC, anon, authenticated;
CREATE INDEX IF NOT EXISTS late_cancels_activity_idx ON late_cancels (activity_id);

INSERT INTO late_cancels (user_id, activity_id, at, waived)
SELECT user_id, activity_id, late_cancel_at, penalty_waived
FROM participations WHERE late_cancel_at IS NOT NULL
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.leave_activity(p_activity_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity RECORD;
  v_user_name TEXT;
  v_is_late BOOLEAN;
  v_reason TEXT;
  v_was_driver BOOLEAN;
  v_passenger RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := NULLIF(left(trim(coalesce(p_reason, '')), 200), '');

  SELECT p.id, p.status, p.transport_type, p.transport_seats
  INTO v_participation
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id
  FOR UPDATE;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_participation.status NOT IN ('accepted', 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, creator_id, title, requires_presence INTO v_activity
  FROM activities WHERE id = p_activity_id;

  -- Block creator from leaving their own activity (would orphan the activity)
  IF v_user_id = v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00477 (PR-5): only leaving an ACCEPTED place late is a late cancel;
  -- withdrawing a request nobody answered is not.
  v_is_late := v_participation.status = 'accepted'
               AND v_activity.requires_presence
               AND (v_activity.starts_at - INTERVAL '12 hours' < now());

  v_was_driver := v_participation.transport_type IN ('car', 'carpool');

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn',
      left_at = now(),
      left_reason = v_reason,
      transport_type = NULL,
      transport_seats = NULL,
      transport_from_name = NULL,
      transport_departs_at = NULL
  WHERE id = v_participation.id;

  -- 00478 (PR-4): the late cancel goes to its own ledger, which no rejoin,
  -- re-invitation, declined invitation or block cascade can erase. A new late
  -- cancel on the same outing re-arms a previous waiver.
  IF v_is_late THEN
    INSERT INTO late_cancels (user_id, activity_id, at, waived)
    VALUES (v_user_id, p_activity_id, now(), false)
    ON CONFLICT (user_id, activity_id) DO UPDATE SET at = now(), waived = false;
  END IF;

  PERFORM recalculate_reliability_score(v_user_id);

  SELECT display_name INTO v_user_name FROM users WHERE id = v_user_id;
  -- 00477/00478 (AB-1): at most one notification of EACH type per participant
  -- and outing per 24 h — an early leave never hides a later late one.
  IF NOT EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_activity.creator_id
      AND type = CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END
      AND data->>'participation_id' = v_participation.id::text
      AND created_at > now() - INTERVAL '24 hours'
  ) THEN
  PERFORM create_notification(
    v_activity.creator_id,
    CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END,
    coalesce(v_user_name, 'Quelqu''un') || ' a quitté « ' || v_activity.title || ' »',
    CASE
      WHEN v_is_late THEN 'Départ tardif — pénalité de fiabilité appliquée, tu peux la lever depuis la sortie.'
      ELSE coalesce(v_reason, '')
    END,
    jsonb_build_object('activity_id', p_activity_id, 'participation_id', v_participation.id, 'late', v_is_late,
      'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', v_activity.title, 'reason', coalesce(v_reason, '')))
  );
  END IF;

  -- If the leaver was offering rides, cancel their pending/accepted seat_requests
  -- and notify each affected requester so they can find another ride.
  IF v_was_driver THEN
    FOR v_passenger IN
      SELECT id, requester_id FROM seat_requests
      WHERE activity_id = p_activity_id AND driver_id = v_user_id
        AND status IN ('pending', 'accepted')
    LOOP
      UPDATE seat_requests SET status = 'cancelled' WHERE id = v_passenger.id;
      PERFORM create_notification(
        v_passenger.requester_id,
        'driver_left',
        'Place annulée',
        coalesce(v_user_name, 'Le conducteur') || ' a quitté « ' || v_activity.title || ' » — trouve une autre place',
        jsonb_build_object('activity_id', p_activity_id, 'driver_id', v_user_id,
          'params', jsonb_build_object('name', coalesce(v_user_name, 'Le conducteur'), 'title', v_activity.title))
      );
    END LOOP;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.recalculate_reliability_score(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- 00435 : constante bayésienne 3 → 1. Avec 3, les scores étaient écrasés
  -- vers le haut au point que le signal ne discriminait plus : quelqu'un qui
  -- s'inscrit à une seule sortie et n'y va pas affichait (3+0)/(3+1) = 75 %,
  -- soit « Bonne » — le MÊME palier qu'un habitué irréprochable — et il fallait
  -- quatre défections consécutives pour tomber en « Faible ».
  -- Avec 1 : 1 absence sur 1 → 50 % (« Correcte »), 2 sur 2 → 33 % (« Faible »),
  -- et un historique sain protège toujours (10 présences + 1 absence → 92 %,
  -- « Excellente »). Un nouveau compte reste à NULL (palier « nouveau ») jusqu'à
  -- sa première sortie terminée, donc on n'affiche jamais 100 % à quelqu'un qui
  -- n'a rien fait.
  v_prior CONSTANT INTEGER := 1;
  v_total INTEGER;
  v_present INTEGER;
  v_late_cancels INTEGER;
  v_score FLOAT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('reliability_' || p_user_id::text));

  -- Validations on activities where the user is the creator AND no other
  -- accepted participant exists are recorded but don't count toward
  -- reliability — solo activities can't be peer-witnessed. The next recalc
  -- after a participant joins picks them up automatically.
  SELECT count(*) INTO v_total
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present IS NOT NULL
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  SELECT count(*) INTO v_present
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present = true
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  -- 00478 (PR-4): late cancels come from the late_cancels ledger. One per
  -- outing; not counted once the person has a presence verdict on that outing
  -- (no double count after a rejoin), nor on outings cancelled or removed.
  SELECT count(*) INTO v_late_cancels
  FROM late_cancels lc
  JOIN activities a ON a.id = lc.activity_id
  WHERE lc.user_id = p_user_id
    AND lc.waived = FALSE
    AND a.requires_presence = TRUE
    AND a.status <> 'cancelled'
    AND a.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM participations p
      WHERE p.activity_id = lc.activity_id AND p.user_id = lc.user_id
        AND p.confirmed_present IS NOT NULL
    );

  v_score := ROUND(
    (((v_prior + v_present)::float / (v_prior + v_total + v_late_cancels)::float) * 100)::numeric,
    1
  )::float;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.waive_late_cancel_penalty(p_participation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_target UUID;
  v_activity UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_user_id AND u0.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.user_id, p.activity_id, a.creator_id INTO v_target, v_activity, v_creator
  FROM participations p JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id;
  IF NOT FOUND OR v_user_id IS DISTINCT FROM v_creator THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00478: keyed on the ledger, so a waiver still works after the person rejoined.
  IF NOT EXISTS (SELECT 1 FROM late_cancels WHERE user_id = v_target AND activity_id = v_activity) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE late_cancels SET waived = TRUE WHERE user_id = v_target AND activity_id = v_activity;
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET penalty_waived = TRUE WHERE id = p_participation_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM recalculate_reliability_score(v_target);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_late_leavers(p_activity_id uuid)
 RETURNS TABLE(participation_id uuid, user_id uuid, display_name text, avatar_url text, left_at timestamptz, left_reason text, penalty_waived boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_user_id AND u0.suspended_at IS NOT NULL) THEN RETURN; END IF;
  -- Creator only (00478, audit PR-6: the client read participations directly,
  -- which RLS limits to the caller's own row, so the list was always empty).
  IF NOT EXISTS (SELECT 1 FROM activities a0 WHERE a0.id = p_activity_id AND a0.creator_id = v_user_id) THEN RETURN; END IF;

  RETURN QUERY
    SELECT p.id, lc.user_id, pp.display_name, pp.avatar_url, lc.at, p.left_reason, lc.waived
    FROM late_cancels lc
    JOIN participations p ON p.activity_id = lc.activity_id AND p.user_id = lc.user_id
    JOIN public_profiles pp ON pp.id = lc.user_id
    WHERE lc.activity_id = p_activity_id
    ORDER BY lc.at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_recent_partners()
 RETURNS TABLE(id uuid, display_name text, avatar_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_user_id AND u0.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH my_activities AS (
    SELECT a.id, a.starts_at, a.creator_id
    FROM activities a
    WHERE a.deleted_at IS NULL
      AND a.starts_at <= now()
      AND a.starts_at > now() - INTERVAL '180 days'
      AND (
        a.creator_id = v_user_id
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ),
  partners AS (
    SELECT ma.creator_id AS uid, ma.starts_at AS at
    FROM my_activities ma
    WHERE ma.creator_id <> v_user_id
    UNION ALL
    SELECT p.user_id AS uid, ma.starts_at AS at
    FROM my_activities ma
    JOIN participations p
      ON p.activity_id = ma.id AND p.status = 'accepted' AND p.user_id <> v_user_id
  ),
  ranked AS (
    SELECT uid, max(at) AS last_at
    FROM partners
    GROUP BY uid
  )
  SELECT pp.id, pp.display_name, pp.avatar_url
  FROM ranked r
  JOIN public_profiles pp ON pp.id = r.uid
  WHERE NOT EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.type = 'dm' AND c.status = 'active'
        AND ((c.user_1 = v_user_id AND c.user_2 = r.uid)
          OR (c.user_1 = r.uid AND c.user_2 = v_user_id))
    )
    AND r.uid NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id)
    AND r.uid NOT IN (SELECT blocker_id FROM blocked_users WHERE blocked_id = v_user_id)
  ORDER BY r.last_at DESC
  LIMIT 20;
END;
$function$;

ALTER TABLE participations DROP COLUMN IF EXISTS late_cancel_at;

REVOKE ALL ON FUNCTION public.get_late_leavers(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_late_leavers(uuid) TO authenticated;
