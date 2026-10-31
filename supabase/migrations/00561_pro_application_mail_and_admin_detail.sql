-- ============================================================================
-- 00561 — Demandes pro : e-mail à askandgo + fiche admin complète
-- (Scott 2026-10-31).
--
--   (1) admin_get_pending_pro_applications renvoie TOUTE la demande : en plus
--       de l'identité et des contacts, métier, accroche, description,
--       Instagram / Facebook, coordonnées du lieu, date de mise à jour et
--       ancienneté du compte. La fiche admin n'affichait qu'un résumé — on
--       valide un pro sur l'ensemble de ce qu'il a déclaré. Chaîne
--       d'autorisation inchangée (admin actif, non suspendu). Type de retour
--       changé → DROP puis CREATE.
--
--   (2) notify_pro_application (trigger AFTER INSERT / UPDATE OF status sur
--       pro_profiles) : quand une demande passe en « pending » (nouvelle
--       demande ou demande corrigée après refus), appelle la fonction Edge
--       `notify-pro-application`, qui envoie l'e-mail à contact@askandgo.io.
--       Seul l'user_id part dans l'appel : la fonction relit la demande avec
--       la clé de service (rien d'injectable par le client). Même secret
--       partagé que send-push (app_config.push_webhook_secret). Plafond de 3
--       e-mails par compte et par 24 h (rate_events) contre une boucle
--       inscription / désinscription. Ne bloque jamais l'inscription : toute
--       erreur de l'appel est avalée.
-- ============================================================================

-- (1) Fiche admin complète -----------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_get_pending_pro_applications();

CREATE FUNCTION public.admin_get_pending_pro_applications()
RETURNS TABLE(
  user_id uuid, display_name text, company_name text, real_name text,
  profession text, tagline text, description text,
  email text, phone text, website text, instagram text, facebook text,
  primary_location_name text, primary_lng double precision, primary_lat double precision,
  created_at timestamp with time zone, updated_at timestamp with time zone,
  account_created_at timestamp with time zone,
  prior_review_count integer, last_review_action text, last_review_at timestamp with time zone
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00420 D2 : le passif approve/reject reste visible (re-validation éclairée).
  RETURN QUERY
  SELECT pp.user_id, pp.display_name, pp.company_name, pp.real_name,
         pp.profession, pp.tagline, pp.description,
         pp.email, pp.phone, pp.website, pp.instagram, pp.facebook,
         pp.primary_location_name,
         extensions.st_x(pp.primary_location::extensions.geometry),
         extensions.st_y(pp.primary_location::extensions.geometry),
         pp.created_at, pp.updated_at,
         u.created_at,
         coalesce(h.cnt, 0)::INTEGER, h.last_action, h.last_at
  FROM pro_profiles pp
  JOIN users u ON u.id = pp.user_id
  LEFT JOIN LATERAL (
    SELECT count(*)::INTEGER AS cnt,
           (ARRAY_AGG(a.action ORDER BY a.created_at DESC))[1] AS last_action,
           max(a.created_at) AS last_at
    FROM admin_actions a
    WHERE a.target_id = pp.user_id
      AND a.action IN ('approve_pro', 'reject_pro')
  ) h ON true
  WHERE pp.status = 'pending'
  ORDER BY pp.created_at ASC;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_get_pending_pro_applications() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_pending_pro_applications() TO authenticated;

-- (2) E-mail à chaque demande en attente ---------------------------------------
CREATE FUNCTION public.notify_pro_application()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  IF NEW.status <> 'pending' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'pending' THEN RETURN NEW; END IF;

  BEGIN
    IF (SELECT count(*) FROM rate_events
        WHERE user_id = NEW.user_id AND kind = 'pro_application_mail'
          AND at > now() - interval '24 hours') >= 3 THEN
      RETURN NEW;
    END IF;

    SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
    IF v_secret IS NULL OR private.project_url() IS NULL THEN RETURN NEW; END IF;

    INSERT INTO rate_events (user_id, kind) VALUES (NEW.user_id, 'pro_application_mail');

    PERFORM net.http_post(
      url := private.project_url() || '/functions/v1/notify-pro-application',
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'x-junto-push-secret', v_secret),
      body := jsonb_build_object('user_id', NEW.user_id,
                                 'resubmission', TG_OP = 'UPDATE')
    );
  EXCEPTION WHEN OTHERS THEN
    -- Jamais bloquer une demande pro pour un e-mail.
    RAISE WARNING 'notify_pro_application: %', SQLERRM;
  END;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_pro_application() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER pro_profiles_notify_application
  AFTER INSERT OR UPDATE OF status ON public.pro_profiles
  FOR EACH ROW EXECUTE FUNCTION public.notify_pro_application();
