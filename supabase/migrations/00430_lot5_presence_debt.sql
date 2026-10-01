-- ============================================================================
-- 00430 — LOT 5 : la dette identifiée par l'audit présence (Scott 2026-10-01,
-- « traite les trois points, le plus sécurisé et le mieux »).
--
-- (1) DÉDUPLICATION DES NOTIFICATIONS — l'index unique partiel (00117) n'a
--     jamais été étendu : il couvre `presence_pre_warning`, `qr_create_reminder`,
--     `peer_review_closing` (+ `presence_confirmed` via son propre index 00131)
--     mais PAS `presence_pre_warning_10min` (00165), `presence_validate_warning`,
--     `presence_validate_overdue`, `presence_validate_final` (00265) ni
--     `rate_participants` (00427). Pour ces 5 types, les `EXCEPTION WHEN
--     unique_violation` des émetteurs sont du CODE MORT et la déduplication
--     repose sur un `NOT EXISTS` non atomique — or le cron tourne chaque minute
--     (00114) ET `transition_single_activity` est appelée en parallèle par
--     chaque client au premier plan : double émission plausible.
--     Ici : purge des doublons existants (on garde le PLUS ANCIEN, celui que
--     l'utilisateur a pu voir/collapser), puis index étendu. Les types morts
--     `presence_reminder` / `presence_last_call` (lignes purgées en 00166)
--     sortent de la liste.
--
-- (2) remove_participant — ÉCRASAIT `confirmed_present` SANS AUCUNE LIMITE DE
--     TEMPS : le créateur pouvait, des semaines après une sortie terminée,
--     effacer la présence validée d'un participant. Effets : perte du crédit de
--     fiabilité et de la sortie réelle pour la victime (le score compte
--     `confirmed_present IS NOT NULL` SANS filtrer le statut de participation,
--     00128), et à 3+ retirer le seul confirmé neutralise tout le monde.
--     Vecteur de représailles et de réécriture d'historique.
--     Choix (le plus sûr) : **refuser le retrait d'une personne déjà validée
--     présente** plutôt que d'effacer le fait — on ne « dés-invite » pas
--     quelqu'un qui est vérifiablement sur place — ET refuser le retrait une
--     fois la sortie finie (la liste devient de l'historique). Pas de
--     raisonnement fragile sur la sémantique du score : le fait n'est jamais
--     touché. Le créateur garde les voies normales (signalement, annulation).
--
-- Base vivante vérifiée : remove_participant = 00116 (grep de toutes les
-- redéfinitions : 00020, 00024, 00116). Signature (UUID) inchangée → pas de
-- surcharge. Tous les champs de RECORD utilisés sont dans le SELECT.
-- ============================================================================

-- ---------- 1. Déduplication : purge puis index étendu ----------
-- Purge d'abord, sinon le CREATE UNIQUE INDEX échoue sur les doublons déjà en
-- base. On garde la ligne la plus ancienne ; `id` départage les ex æquo.
DELETE FROM notifications n
USING notifications older
WHERE n.type IN (
        'presence_pre_warning', 'presence_pre_warning_10min',
        'presence_validate_warning', 'presence_validate_overdue',
        'presence_validate_final', 'qr_create_reminder',
        'peer_review_closing', 'rate_participants'
      )
  AND older.type = n.type
  AND older.user_id = n.user_id
  AND (n.data->>'activity_id') IS NOT NULL
  AND (older.data->>'activity_id') = (n.data->>'activity_id')
  AND (older.created_at < n.created_at
       OR (older.created_at = n.created_at AND older.id < n.id));

DROP INDEX IF EXISTS idx_notif_presence_dedup;
CREATE UNIQUE INDEX idx_notif_presence_dedup
ON notifications (user_id, type, ((data->>'activity_id')))
WHERE type IN (
  'presence_pre_warning', 'presence_pre_warning_10min',
  'presence_validate_warning', 'presence_validate_overdue',
  'presence_validate_final', 'qr_create_reminder',
  'peer_review_closing', 'rate_participants'
);
-- NB : une ligne sans `activity_id` laisse un NULL dans la clé — Postgres
-- autorise plusieurs NULL, donc ces notifications ne sont pas contraintes
-- (aucune des 8 n'est émise sans activity_id, c'est une ceinture).

-- ---------- 2. remove_participant (base 00116) ----------
CREATE OR REPLACE FUNCTION remove_participant(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.activity_id, p.confirmed_present,
         a.creator_id, a.title, a.status AS activity_status, a.deleted_at
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.user_id = v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00430 : retirer quelqu'un est une action de LOGISTIQUE (avant / pendant),
  -- pas une édition d'historique. Après la fin, la liste des participants est
  -- un fait acquis. Code parlant : le créateur voit que la sortie est passée,
  -- rien de sensible n'est révélé.
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'junto.activity_ended_no_remove';
  END IF;

  -- 00430 : on ne « dés-invite » pas quelqu'un dont la présence est VÉRIFIÉE
  -- (QR, géo ou témoignage de deux pairs). Avant, cette présence était effacée
  -- (`confirmed_present = NULL`) : la victime perdait son crédit de fiabilité
  -- et sa sortie réelle, et à 3+ retirer le seul confirmé neutralisait tout le
  -- monde. On refuse plutôt que d'effacer le fait.
  IF v_participation.confirmed_present IS NOT NULL THEN
    RAISE EXCEPTION 'junto.participant_present_no_remove';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'removed',
      confirmed_present = NULL   -- déjà NULL (gardé par ceinture)
  WHERE id = p_participation_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM create_notification(
    v_participation.user_id,
    'participant_removed',
    'Retiré de l''activité',
    'Tu as été retiré de ' || v_participation.title,
    jsonb_build_object('activity_id', v_participation.activity_id)
  );
END;
$$;
REVOKE ALL ON FUNCTION remove_participant(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_participant(UUID) TO authenticated;
