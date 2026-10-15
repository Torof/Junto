-- ============================================================================
-- 00450 — Notifications multilingues, lots E (présence), F (avis, badges,
-- validation pro) et G (messages). Même principe que 00447→00449 : title/body
-- FR = secours, data.params (+ variant) pour la langue du lecteur. Copy FR :
-- relances de présence ramenées sous 120 caractères (audit 2026-10-15), plus
-- de variante 3+/2 sur l'avertissement, variante « duo » sur la relance
-- (à deux : pas d'absence, la sortie n'est pas comptée), « Présence non
-- validée », évaluation reformulée, emoji retiré de la validation pro.
-- Messages : le payload push porte name/context/preview (variante dm sans
-- contexte) ; le texte composé par send-push dans la langue du destinataire.
-- Rituel live-version : fonctions reconstruites depuis leur dernière
-- définition ; seuls les appels de notification / le payload changent.
--   notify_presence_pre_warning        ← 00432
--   notify_presence_pre_warning_10min  ← 00432
--   notify_presence_validate_warning   ← 00432
--   notify_presence_validate_overdue   ← 00434
--   notify_presence_confirmed          ← 00150
--   notify_creator_qr_reminder         ← 00229
--   notify_rate_participants           ← 00427
--   notify_review_received             ← 00260
--   notify_review_reply                ← 00260
--   award_badge_progression            ← 00159
--   approve_pro                        ← 00419
--   reject_pro                         ← 00329
--   broadcast_and_push_message         ← 00437
-- ============================================================================

-- ---------- notify_presence_pre_warning (base 00432) ----------
CREATE OR REPLACE FUNCTION notify_presence_pre_warning(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, requires_presence, creator_id
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'published' THEN RETURN; END IF;
  IF now() < v_activity.starts_at - INTERVAL '2 hours' OR now() >= v_activity.starts_at THEN
    RETURN;
  END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      -- 00432 : le créateur n'a AUCUN chemin d'auto-validation (invariant
      -- 00292). Lui dire « prépare-toi à valider ta présence » était une
      -- consigne inexécutable, et la fiche d'activité ne mentionnait même pas
      -- la présence pour lui à ce moment-là. Son action à lui, c'est
      -- qr_create_reminder à T-10min.
      AND p.user_id != v_activity.creator_id
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning',
        v_activity.title,
        'Démarre dans 2 h — prépare-toi à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

-- ---------- notify_presence_pre_warning_10min (base 00432) ----------
CREATE OR REPLACE FUNCTION notify_presence_pre_warning_10min(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN RETURN; END IF;

  IF now() < v_activity.starts_at - INTERVAL '10 minutes' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      -- 00432 : le créateur n'a AUCUN chemin d'auto-validation (invariant
      -- 00292). Lui dire « prépare-toi à valider ta présence » était une
      -- consigne inexécutable, et la fiche d'activité ne mentionnait même pas
      -- la présence pour lui à ce moment-là. Son action à lui, c'est
      -- qr_create_reminder à T-10min.
      AND p.user_id != v_activity.creator_id
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning_10min'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning_10min',
        v_activity.title,
        'Démarre dans 10 min — pense à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

-- ---------- notify_presence_validate_warning (base 00432) ----------
CREATE OR REPLACE FUNCTION public.notify_presence_validate_warning(p_activity_id uuid)
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
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  IF now() < v_activity.starts_at + (v_activity.duration / 2) THEN RETURN; END IF;
  IF now() >= v_activity.starts_at + v_activity.duration THEN RETURN; END IF;

  -- Peer testimony (and thus the self-validate nag) only applies from 3.
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
          AND n.type = 'presence_validate_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_warning',
        'Valide ta présence',
        -- 00450 : une seule phrase, ≤ 120 caractères (audit 2026-10-15) — la
        -- distinction 3+/2 ne changeait que des détails que la push tronquait.
        'Scanne le QR de l''organisateur — valable jusqu''à 3 h après la fin de « ' || v_activity.title || ' ».',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

-- ---------- notify_presence_validate_overdue (base 00434) ----------
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
        'Présence non validée',
        -- 00450 : ≤ 120 caractères (audit 2026-10-15). À deux, pas d'absence
        -- possible : la sortie n'est simplement pas comptée (00327/00434).
        CASE WHEN v_accepted_count >= 3 THEN
          'Scanne le QR de l''organisateur avant 3 h après la fin de « ' || v_activity.title || ' », sinon ce sera une absence.'
        ELSE
          'Scanne le QR de l''organisateur avant 3 h après la fin de « ' || v_activity.title || ' », sinon la sortie ne sera pas comptée.'
        END,
        jsonb_build_object('activity_id', p_activity_id,
          'variant', CASE WHEN v_accepted_count >= 3 THEN NULL ELSE 'duo' END,
          'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

-- ---------- notify_presence_confirmed (base 00150) ----------
CREATE OR REPLACE FUNCTION notify_presence_confirmed(
  p_user_id UUID,
  p_activity_id UUID,
  p_skip_push BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title TEXT;
  v_data JSONB;
BEGIN
  SELECT title INTO v_title FROM activities WHERE id = p_activity_id;
  IF v_title IS NULL THEN RETURN; END IF;

  v_data := jsonb_build_object('activity_id', p_activity_id);
  IF p_skip_push THEN
    v_data := v_data || jsonb_build_object('skip_push', TRUE);
  END IF;

  BEGIN
    PERFORM create_notification(
      p_user_id,
      'presence_confirmed',
      'Présence confirmée',
      'Ta présence est validée pour « ' || v_title || ' »',
      coalesce(v_data, '{}'::jsonb) || jsonb_build_object('params', jsonb_build_object('title', v_title))
    );
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END;
$$;

-- ---------- notify_creator_qr_reminder (base 00229) ----------
CREATE OR REPLACE FUNCTION notify_creator_qr_reminder(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
BEGIN
  SELECT id, creator_id, title, status, starts_at, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN RETURN; END IF;

  IF now() < v_activity.starts_at - INTERVAL '10 minutes' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_activity.creator_id
      AND type = 'qr_create_reminder'
      AND (data->>'activity_id')::uuid = p_activity_id
  ) THEN RETURN; END IF;

  BEGIN
    PERFORM create_notification(
      v_activity.creator_id,
      'qr_create_reminder',
      v_activity.title,
      'Génère le QR de présence pour tes participants',
      jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
    );
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;
END;
$$;

-- ---------- notify_rate_participants (base 00427) ----------
CREATE OR REPLACE FUNCTION notify_rate_participants(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, deleted_at
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.deleted_at IS NOT NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  -- La fenêtre de vote réelle : fin+15 min → fin+24 h. Avant : silence
  -- (le prochain balayage émettra) ; après : plus de sens, on n'émet jamais.
  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  -- Gate solo (00265) : personne à évaluer en dessous de 2 acceptés.
  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'rate_participants'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'rate_participants',
        'Évalue tes co-participants',
        '« ' || v_activity.title || ' » — dis-nous comment ça s''est passé.',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

-- ---------- notify_review_received (base 00260) ----------
CREATE OR REPLACE FUNCTION notify_review_received(
  p_pro_id UUID,
  p_reviewer_name TEXT,
  p_rating SMALLINT,
  p_target_label TEXT,
  p_data JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean_name TEXT;
  v_clean_label TEXT;
BEGIN
  v_clean_name := sanitize_notif_text(coalesce(p_reviewer_name, 'Quelqu''un'));
  v_clean_label := sanitize_notif_text(coalesce(p_target_label, ''));
  PERFORM create_notification(
    p_pro_id,
    'review_received',
    'Nouvel avis',
    v_clean_name || ' a laissé un avis (' || p_rating || '★) sur ' || v_clean_label,
    coalesce(p_data, '{}'::jsonb) || jsonb_build_object('params', jsonb_build_object('name', v_clean_name, 'rating', p_rating, 'label', v_clean_label))
  );
END;
$$;

-- ---------- notify_review_reply (base 00260) ----------
CREATE OR REPLACE FUNCTION notify_review_reply(
  p_reviewer_id UUID,
  p_pro_name TEXT,
  p_target_label TEXT,
  p_data JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean_name TEXT;
  v_clean_label TEXT;
BEGIN
  v_clean_name := sanitize_notif_text(coalesce(p_pro_name, 'Le pro'));
  v_clean_label := sanitize_notif_text(coalesce(p_target_label, ''));
  PERFORM create_notification(
    p_reviewer_id,
    'review_reply',
    'Réponse à ton avis',
    v_clean_name || ' a répondu à ton avis sur ' || v_clean_label,
    coalesce(p_data, '{}'::jsonb) || jsonb_build_object('params', jsonb_build_object('name', v_clean_name, 'label', v_clean_label))
  );
END;
$$;

-- ---------- award_badge_progression (base 00159) ----------
CREATE OR REPLACE FUNCTION award_badge_progression(
  p_user_id UUID,
  p_silent BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
  v_tier TEXT;
  v_inserted UUID;
  v_label TEXT;
BEGIN
  -- Joined activities (where the user wasn't the creator)
  SELECT count(*) INTO v_count
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND a.status = 'completed'
    AND a.creator_id != p_user_id
    AND a.deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'joined', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('joined', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'joined', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
  v_inserted := NULL;

  -- Created activities
  SELECT count(*) INTO v_count
  FROM activities
  WHERE creator_id = p_user_id
    AND status = 'completed'
    AND deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'created', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('created', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'created', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
END;
$$;

-- ---------- approve_pro (base 00419) ----------
CREATE OR REPLACE FUNCTION approve_pro(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_user_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles
    SET status = 'approved', rejection_reason = NULL, reviewed_at = now(), reviewed_by = v_admin
    WHERE user_id = p_user_id;
  -- 00419 : si unregister_as_pro a supprimé la ligne entre le check et ici,
  -- ne surtout pas poser tier='pro' sans profil.
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE users SET tier = 'pro' WHERE id = p_user_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (p_user_id, 'pro_approved', 'Page pro validée',
          'Ta page pro est en ligne. Tu peux maintenant publier tes sorties.',
          jsonb_build_object('pro_id', p_user_id, 'params', '{}'::jsonb));

  PERFORM log_admin_action(v_admin, 'approve_pro', 'pro_profile', p_user_id, NULL, NULL);
END;
$$;

-- ---------- reject_pro (base 00329) ----------
CREATE OR REPLACE FUNCTION reject_pro(p_user_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_user_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_reason IS NOT NULL AND char_length(p_reason) > 500 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles
    SET status = 'rejected', rejection_reason = NULLIF(trim(coalesce(p_reason, '')), ''),
        reviewed_at = now(), reviewed_by = v_admin
    WHERE user_id = p_user_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (p_user_id, 'pro_rejected', 'Demande pro refusée',
          coalesce(NULLIF(trim(coalesce(p_reason, '')), ''), 'Ta demande de page pro n''a pas été validée. Corrige tes informations et renvoie-la.'),
          jsonb_build_object('pro_id', p_user_id,
            'variant', CASE WHEN NULLIF(trim(coalesce(p_reason, '')), '') IS NULL THEN NULL ELSE 'reason' END,
            'params', jsonb_build_object('reason', coalesce(NULLIF(trim(coalesce(p_reason, '')), ''), ''))));

  PERFORM log_admin_action(v_admin, 'reject_pro', 'pro_profile', p_user_id, NULLIF(trim(coalesce(p_reason, '')), ''), NULL);
END;
$$;

-- ---------- broadcast_and_push_message (base 00437) ----------
CREATE OR REPLACE FUNCTION broadcast_and_push_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_conv RECORD;
  v_sender_name TEXT;
  v_secret TEXT;
  v_recipients UUID[];
  v_uid UUID;
  v_title TEXT;
BEGIN
  SELECT type, name, activity_id INTO v_conv
  FROM conversations WHERE id = NEW.conversation_id;

  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('table', 'messages', 'op', 'INSERT',
                         'conversation_id', NEW.conversation_id, 'message_id', NEW.id),
      'change', 'conversation:' || NEW.conversation_id::text, true);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  IF v_conv.type = 'activity' AND v_conv.activity_id IS NOT NULL THEN
    BEGIN
      PERFORM realtime.send(
        jsonb_build_object('table', 'messages', 'op', 'INSERT',
                           'conversation_id', NEW.conversation_id),
        'wall', 'activity:' || v_conv.activity_id::text, true);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  SELECT array_agg(cm.user_id) INTO v_recipients
  FROM conversation_members cm
  WHERE cm.conversation_id = NEW.conversation_id
    AND cm.user_id IS DISTINCT FROM NEW.sender_id
    AND (NEW.sender_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE b.blocker_id = cm.user_id AND b.blocked_id = NEW.sender_id
    ));
  IF v_recipients IS NULL OR array_length(v_recipients, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  FOREACH v_uid IN ARRAY v_recipients LOOP
    BEGIN
      PERFORM realtime.send(
        jsonb_build_object('conversation_id', NEW.conversation_id),
        'inbox', 'user:' || v_uid::text, true);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;

  -- Push leg — skipped for rows mirrored from a legacy writer (already pushed).
  IF current_setting('junto.skip_message_push', true) IS DISTINCT FROM 'true' THEN
    IF NEW.sender_id IS NOT NULL THEN
      SELECT display_name INTO v_sender_name FROM users WHERE id = NEW.sender_id;
    END IF;
    v_title := coalesce(v_sender_name, 'Junto');
    IF v_conv.type = 'group' AND v_conv.name IS NOT NULL THEN
      v_title := v_title || ' · ' || v_conv.name;
    ELSIF v_conv.type = 'activity' THEN
      SELECT v_title || ' · ' || regexp_replace(a.title, '<[^>]*>', '', 'g')
      INTO v_title FROM activities a WHERE a.id = v_conv.activity_id;
    END IF;

    SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
    IF v_secret IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json',
                                        'x-junto-push-secret', v_secret),
          body := jsonb_build_object(
            'user_ids', to_jsonb(v_recipients),
            'title', v_title,
            'body', left(NEW.content, 140),
            -- 00437 : pour un fil d'ACTIVITÉ, on ajoute activity_id. Sans lui, le
            -- routeur push ouvrait /conversation/{id} — l'écran DM/groupe, qui ne
            -- sait pas afficher un fil d'activité (le mur vit dans l'onglet chat de
            -- l'écran d'activité). Les DM et groupes gardent le payload d'origine.
            'data', CASE
              WHEN v_conv.type = 'activity' AND v_conv.activity_id IS NOT NULL THEN
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message',
                                   'activity_id', v_conv.activity_id,
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'Junto'),
                                     'context', (SELECT regexp_replace(a.title, '<[^>]*>', '', 'g') FROM activities a WHERE a.id = v_conv.activity_id),
                                     'preview', left(NEW.content, 140)))
              WHEN v_conv.name IS NOT NULL THEN
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message',
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'Junto'),
                                     'context', v_conv.name, 'preview', left(NEW.content, 140)))
              ELSE
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message', 'variant', 'dm',
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'Junto'),
                                     'preview', left(NEW.content, 140)))
            END,
            'collapseId', 'message-' || NEW.conversation_id::text
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
