-- ============================================================================
-- 00436 — Correction de DEUX défauts introduits par mes propres correctifs de
-- la semaine (Scott 2026-10-01, « finir les deux bugs »).
--
-- Ici, le volet serveur du premier : le QR affichait une ÉCHÉANCE FAUSSE.
-- Lundi (OTA) j'ai fait renouveler le token au bout de 25 min pour qu'un
-- organisateur laissant la feuille ouverte n'affiche pas un code mort. Mais
-- cette fonction REND LE TOKEN EXISTANT tant qu'il n'est pas expiré, au lieu
-- d'en frapper un neuf. Le « renouvellement » récupérait donc le même code, le
-- client remettait son compteur local à zéro et annonçait « valide jusqu'à
-- maintenant + 30 min » — alors que le vrai code mourait à son heure d'origine.
-- Résultat : jusqu'à ~20 min pendant lesquelles le QR est mort ET l'écran
-- affirme qu'il est valide. C'est pire que la panne silencieuse de départ,
-- puisqu'on affirme désormais quelque chose de faux.
--
-- Fix serveur (1 ligne) : ne réutiliser un token que s'il lui reste > 5 min.
-- Fix client (même OTA) : ne pas réinitialiser le compteur local quand le
-- serveur rend le MÊME token — l'échéance affichée reste alors celle de la
-- frappe réelle.
--
-- Rétrocompatible : signature et type de retour inchangés, donc un client plus
-- ancien continue de fonctionner — et profite même du correctif, puisqu'il
-- reçoit désormais un token frais au lieu d'un mourant.
--
-- Le second défaut (purge du cache hors-ligne devenue plus courte que la borne
-- serveur que j'avais élargie) est purement client, pas de SQL.
--
-- Base vivante vérifiée : create_presence_token = 00429.
-- ============================================================================

CREATE OR REPLACE FUNCTION create_presence_token(p_activity_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_creator_id UUID;
  v_token TEXT;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_requires_presence BOOLEAN;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT creator_id, starts_at, duration, status, deleted_at, requires_presence, is_demo
  INTO v_creator_id, v_starts_at, v_duration, v_status, v_deleted_at, v_requires_presence, v_is_demo
  FROM activities WHERE id = p_activity_id;
  IF v_creator_id IS NULL OR v_creator_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00429 : ne pas frapper un token sur une sortie supprimée / annulée /
  -- expirée, ni sans validation de présence, ni sur une sortie démo.
  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  IF v_requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  IF v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '15 minutes' OR now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
    RAISE EXCEPTION 'junto.presence_token_window_closed';
  END IF;

  SELECT token INTO v_token FROM presence_tokens
  -- 00436 : on ne réutilise un token que s'il lui reste plus de 5 MINUTES.
  -- Avant, la condition était « expires_at > now() » : un client qui demandait
  -- un renouvellement récupérait donc le token mourant au lieu d'un neuf, et
  -- comme il n'a aucun moyen de connaître la vraie échéance, il affichait
  -- « valide 30 min de plus » sur un code qui allait mourir — un QR mort à
  -- l'écran, pendant que l'app affirmait le contraire. Cette borne garantit
  -- qu'une demande proche de l'expiration rend un token réellement frais.
  WHERE activity_id = p_activity_id AND expires_at > now() + INTERVAL '5 minutes'
  LIMIT 1;

  IF v_token IS NULL THEN
    v_token := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
    INSERT INTO presence_tokens (token, activity_id, expires_at)
    VALUES (v_token, p_activity_id, now() + INTERVAL '30 minutes');
  END IF;

  RETURN v_token;
END;
$$;

REVOKE ALL ON FUNCTION create_presence_token(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_presence_token(UUID) TO authenticated;
