-- ============================================================================
-- 00434 — DÉCISION PRODUIT : le témoignage de PRÉSENCE par les pairs est
-- DÉSACTIVÉ (Scott 2026-10-01, après audit à deux niveaux).
--
-- ⚠️ La validation par les pairs du CARACTÈRE (traits, niveau perçu) n'est PAS
-- touchée : elle passe par give_reputation_badge / revoke_reputation_badge,
-- elle reste entièrement active, et `rate_participants` continue d'y inviter.
-- Seul le témoignage de PRÉSENCE s'arrête.
--
-- POURQUOI :
--   * Il ne DÉTECTE aucune absence — ça, c'est la géo et le QR. Son seul rôle
--     était de rattraper quelqu'un présent mais non validé (typiquement
--     téléphone mort de froid, cas réel et courant en montagne).
--   * Mais ce rattrapage ne fonctionne pas : il exige que DEUX inconnus votent
--     spontanément dans les 24 h, depuis un écran proposant jusqu'à 10 bascules
--     par personne. On ne supprime donc pas une protection, on supprime
--     l'illusion d'une protection — la personne au téléphone mort prenait déjà
--     la pénalité.
--   * Il a coûté 4 régressions, dont un VECTEUR DE FRAUDE introduit le
--     2026-10-01 par la Règle A de 00432/00433 : le créateur pouvait voter, sa
--     voix comptait dans les 2 requises, et la Règle A le créditait lui-même →
--     auto-crédit avec UN seul complice sur une sortie fictive. La désactivation
--     ferme ce vecteur.
--   * Le préjudice d'une accusation injuste est aujourd'hui quasi nul : le score
--     ne conditionne rien, son tri est cassé (public_profiles.reliability_score
--     est NULL depuis 00347) et son anneau est affiché sans libellé.
--
-- DÉCLENCHEUR DE RETOUR — ce n'est PAS « si les gens se plaignent », c'est
-- AVANT de rendre le score conséquent (filtre, tri réparé, libellé lisible,
-- seuil). Ce jour-là, accuser à tort devient un préjudice réel et un mécanisme
-- de contestation devient OBLIGATOIRE. Et pas sous la forme actuelle : la
-- personne CONTESTE (« j'étais là »), ce qui notifie ceux dont la présence est
-- VÉRIFIÉE, qui confirment d'un geste — une action, initiée par celui qui a la
-- motivation, adressée à ceux qui peuvent répondre.
--
-- POUR RÉACTIVER : supprimer le bloc marqué « DÉSACTIVÉ 00434 » dans
-- peer_validate_presence et restaurer notify_peer_review_closing depuis 00432
-- (lignes 468-581). ⚠️ NE PAS réactiver sans corriger d'abord le vecteur de
-- fraude : la voix du créateur ne doit pas compter dans le seuil de 2.
--
-- Bases vivantes vérifiées : peer_validate_presence = 00433,
-- notify_peer_review_closing / _validate_overdue / _validate_warning = 00432.
-- Signatures inchangées. Contrôle du nombre de fonctions créées en fin de
-- fichier (leçon 00432/00433).
-- ============================================================================

-- ---------- 1. peer_validate_presence : refus net ----------
-- Stub volontaire : on ne conserve pas l'ancien corps, il est dans 00433.
CREATE OR REPLACE FUNCTION peer_validate_presence(
  p_voted_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- DÉSACTIVÉ 00434. Code déjà mappé côté client
  -- (errors.code.peer_review_unavailable) ; aucun écran ne propose plus
  -- l'action, ceci n'est donc qu'un filet pour un client non mis à jour.
  RAISE EXCEPTION 'junto.peer_review_unavailable';
END;
$$;
REVOKE ALL ON FUNCTION peer_validate_presence(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION peer_validate_presence(UUID, UUID) TO authenticated;

-- ---------- 2. notify_peer_review_closing : plus rien à émettre ----------
-- Ses DEUX branches portaient sur la présence : (a) « valide tes
-- co-participants » et (b) presence_validate_final « demande à 2
-- co-participants de te confirmer ». Les deux inviteraient désormais à une
-- action impossible — (b) serait même un pur générateur d'anxiété, puisqu'à
-- fin+22h le QR est fermé depuis longtemps et qu'il ne reste donc RIEN à faire.
-- Deux types de notification disparaissent de la vie de l'utilisateur.
CREATE OR REPLACE FUNCTION notify_peer_review_closing(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN;  -- DÉSACTIVÉ 00434 (corps conservé dans 00432:468-581)
END;
$$;
REVOKE ALL ON FUNCTION notify_peer_review_closing(UUID) FROM PUBLIC, anon, authenticated;

-- ---------- 3. notify_presence_validate_overdue : la copie ne promet plus
-- le témoignage, seulement le QR (base 00432). ----------
CREATE OR REPLACE FUNCTION public.notify_presence_validate_overdue(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_accepted_count INTEGER;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '1 hour' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '1 hour 30 minutes' THEN RETURN; END IF;

  -- 00432 : le seuil passe de 3 à 2. À 2 participants, le QR est le SEUL
  -- recours (le témoignage entre pairs exige 3) — c'était donc la
  -- configuration qui avait le plus besoin d'être relancée, et la seule qui ne
  -- recevait RIEN entre T+15min et fin+3h. La copy est choisie selon le
  -- nombre : à 2, elle ne parle que du QR et ne menace d'aucune absence
  -- (close_presence_window_for remet à NULL sans pénalité à 2).
  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_accepted_count < 2 THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND p.user_id != v_activity.creator_id   -- Rule B: creator not nagged
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_overdue'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_overdue',
        v_activity.title,
        -- 00429 : l'ancienne copy affirmait « Tu es enregistré comme absent »,
        -- ce qui est FAUX à fin+1h (la finalisation n'a lieu qu'à fin+24h) et
        -- passait sous silence le QR, encore valable 2 h.
        CASE WHEN v_accepted_count >= 3 THEN
          'Ta présence n''est pas encore validée. Scanne le QR de l''organisateur — c''est encore possible jusqu''à 3 h après la fin. Sans validation, tu seras compté absent 24 h après la fin.'
        ELSE
          'Ta présence n''est pas encore validée. Scanne le QR de l''organisateur — à deux, c''est le seul moyen, et il reste ouvert jusqu''à 3 h après la fin. Sans ça, cette sortie ne sera simplement pas comptée (aucune absence, aucune pénalité).'
        END,
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION notify_presence_validate_overdue(UUID) FROM PUBLIC, anon, authenticated;
