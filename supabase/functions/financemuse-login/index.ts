import { body, clients, json, rateLimit } from '../_shared/http.ts';

// financemuse username-or-email login (PRD §5.1).
// POST { identifier, password } -> { access_token, refresh_token,
//   expires_in, token_type, user: { id } } on success, or an identical
// generic 401 { error: 'Invalid credentials' } on EVERY failure path
// (unknown username, unknown email, suspended profile, wrong password)
// so usernames cannot be enumerated and the resolved email is NEVER
// returned to the client. Bare usernames are resolved server-side only
// via financemuse.resolve_login_email (SECURITY DEFINER, service_role
// only). Mirrors login-identifier, including verify_only.
Deno.serve(async request => {
  try {
    const input = await body(request);
    if (typeof input.password !== 'string' || input.password.length === 0 || input.password.length > 1024) return json({ error: 'Invalid credentials' }, 401);
    if (typeof input.identifier !== 'string' || input.identifier.length === 0 || input.identifier.length > 254) return json({ error: 'Invalid credentials' }, 401);
    const identifier = input.identifier.trim();
    const isEmail = identifier.includes('@');
    if (!isEmail && !/^[a-z0-9_]{3,24}$/.test(identifier.toLowerCase())) return json({ error: 'Invalid credentials' }, 401);
    const { service, auth } = clients();
    await rateLimit(service, `financemuse-login:${identifier.toLowerCase()}`);
    let email: string | null = null;
    if (isEmail) {
      email = identifier;
    } else {
      // Service client on the financemuse schema: the RPC lives there,
      // not in public (unlike adoetz_login_lookup).
      const { data } = await service.schema('financemuse').rpc('resolve_login_email', { p_username: identifier.toLowerCase() });
      email = typeof data === 'string' ? data : null;
    }
    const { data, error } = await auth.auth.signInWithPassword({ email: email ?? 'unavailable@example.invalid', password: input.password });
    if (error || !data.session || !email) return json({ error: 'Invalid credentials' }, 401);
    if (input.verify_only === true) {
      await auth.auth.signOut({ scope: 'local' });
      return json({ ok: true });
    }
    return json({ access_token: data.session.access_token, refresh_token: data.session.refresh_token, expires_in: data.session.expires_in, token_type: 'bearer', user: { id: data.user?.id } });
  } catch { return json({ error: 'Sign in unavailable. Try again later.' }, 429); }
});
