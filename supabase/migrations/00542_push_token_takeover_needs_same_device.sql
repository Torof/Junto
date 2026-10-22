-- A push token registered to another account moves only when the same device
-- presents it (audit, small 13): anyone who learnt someone's token could take
-- it over and cut that person off from their notifications.

CREATE OR REPLACE FUNCTION public.register_push_token(p_token text, p_device_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_token IS NULL OR char_length(p_token) < 20 OR char_length(p_token) > 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_token !~ '^Exp(o|onent)PushToken\[.+\]$' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00542: a token registered to another account moves only when the same
  -- device presents it (account switch on one phone). Anyone else who learnt
  -- the token cannot divert that person's notifications — silently ignored.
  IF EXISTS (SELECT 1 FROM push_tokens WHERE token = p_token AND user_id != v_user_id
             AND device_id IS DISTINCT FROM p_device_id) THEN
    RETURN;
  END IF;
  DELETE FROM push_tokens WHERE token = p_token AND user_id != v_user_id;

  IF p_device_id IS NOT NULL THEN
    DELETE FROM push_tokens
      WHERE user_id = v_user_id
        AND device_id = p_device_id
        AND token != p_token;
    INSERT INTO push_tokens (user_id, token, device_id)
      VALUES (v_user_id, p_token, p_device_id)
      ON CONFLICT (user_id, token)
      DO UPDATE SET device_id = EXCLUDED.device_id, created_at = now();  -- 00519: last use
  ELSE
    INSERT INTO push_tokens (user_id, token)
      VALUES (v_user_id, p_token)
      ON CONFLICT (user_id, token) DO UPDATE SET created_at = now();  -- 00519: last use
  END IF;

  -- 00514 (AB-11): at most 10 devices per account (oldest dropped).
  DELETE FROM push_tokens WHERE user_id = v_user_id AND token NOT IN (
    SELECT token FROM push_tokens WHERE user_id = v_user_id ORDER BY created_at DESC LIMIT 10);

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE push_token = p_token AND id != v_user_id;
  UPDATE users SET push_token = p_token WHERE id = v_user_id;
END;
$function$;
