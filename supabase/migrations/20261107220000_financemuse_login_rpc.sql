-- financemuse username -> email lookup for the financemuse-login Edge
-- Function (2026-11-07). The app never queries emails: the Edge Function
-- calls this RPC with its service-role client, signs in with the resolved
-- email server-side, and returns an identical generic 401 on every
-- failure path (unknown username / suspended / wrong password), so the
-- email is never exposed to the client and usernames cannot be enumerated.
--
-- SECURITY DEFINER so it can read auth.users.email past RLS; callable
-- ONLY by service_role. It deliberately does NOT touch the adoetz
-- invitation trigger or the private/public adoetz schemas.

CREATE OR REPLACE FUNCTION financemuse.resolve_login_email(p_username TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT u.email
  FROM auth.users u
  JOIN financemuse.profiles p ON p.user_id = u.id
  WHERE p.username_normalized = lower(p_username)
    AND p.status = 'active'
  LIMIT 1
$$;

REVOKE ALL ON FUNCTION financemuse.resolve_login_email(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION financemuse.resolve_login_email(TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION financemuse.resolve_login_email(TEXT) TO service_role;
