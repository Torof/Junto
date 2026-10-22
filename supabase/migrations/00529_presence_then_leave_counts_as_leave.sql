-- 00529 — confirming presence then leaving no longer counts as present nor
-- erases the late-cancel penalty (audit 2026-10-23, outings F1).
--
-- recalculate_reliability_score counted confirmed_present whatever the row's
-- status, and skipped the late cancel as soon as a presence existed: someone
-- could scan the QR at T-15, leave, and keep +1 present with no penalty. Only
-- a presence on a participation that is still accepted counts now.

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
    AND p.status = 'accepted'  -- 00529: a presence on a row the person left does not count
    AND a.deleted_at IS NULL AND a.status <> 'cancelled'  -- 00495 (PR-10)
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
    AND p.status = 'accepted'  -- 00529
    AND a.deleted_at IS NULL AND a.status <> 'cancelled'  -- 00495 (PR-10)
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
        AND p.status = 'accepted'  -- 00529: validating then leaving keeps the late cancel
    );

  v_score := ROUND(
    (((v_prior + v_present)::float / (v_prior + v_total + v_late_cancels)::float) * 100)::numeric,
    1
  )::float;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$function$;
