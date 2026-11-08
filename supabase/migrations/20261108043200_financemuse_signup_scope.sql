-- financemuse signup scope (2026-11-08).
--
-- Problem: private.on_signup() (trigger adoetz_signup on auth.users) required
-- an invite_code for EVERY signup instance-wide, so no financemuse user could
-- sign up (500 P0001 'Registration is invitation only').
--
-- Fix: scope the trigger by app marker in raw_user_meta_data.
--   * app = 'financemuse' -> create ONLY financemuse.profiles +
--     financemuse.user_roles (role 'user'). No public.profiles, no
--     private.accounts, no invitation consumed.
--   * anything else -> the EXACT previous invite-only path, unchanged,
--     including the two early RETURN NEW bypasses (adoetz_invite_id in
--     raw_app_meta_data, waclonegem_private.invite_reservations < 1h).
--
-- Backup of the previous function definition (verbatim pg_get_functiondef):
--   /root/supabase-project/backups/on_signup-20261108.sql (oracle)
--   supabase/backups/on_signup_before_20261108.sql (this repo)
-- Trigger name, SECURITY DEFINER, search_path='' all unchanged. The trigger
-- itself is NOT dropped or disabled. GOTRUE settings untouched.
-- The Flutter app must send data: {'app': 'financemuse', 'username': ...,
-- 'display_name': ...} on signUp; the trigger is the single writer of the
-- financemuse profile row (the app no longer inserts it itself).

CREATE OR REPLACE FUNCTION private.on_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  username_value text;
  display_value text;
  invite_id uuid;
begin
  -- Existing bypasses, unchanged.
  if coalesce(new.raw_app_meta_data->>'adoetz_invite_id', '') <> '' then
    return new;
  end if;
  if new.email is not null and exists (
    select 1
      from waclonegem_private.invite_reservations r
     where r.email = new.email
       and r.created_at > now() - interval '1 hour'
  ) then
    return new;
  end if;

  -- financemuse branch: open signup, no invitation required.
  if coalesce(new.raw_user_meta_data->>'app', '') = 'financemuse' then
    username_value := lower(nullif(trim(new.raw_user_meta_data->>'username'), ''));
    if username_value is null or username_value !~ '^[a-z0-9_]{3,24}$' then
      raise exception 'Invalid username';
    end if;
    if exists (select 1 from financemuse.profiles p where p.username_normalized = username_value) then
      raise exception 'Username already taken';
    end if;
    display_value := coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), username_value);
    insert into financemuse.profiles (user_id, username, username_normalized, display_name)
      values (new.id, username_value, username_value, display_value);
    insert into financemuse.user_roles (user_id, role)
      values (new.id, 'user');
    return new;
  end if;

  -- Existing invite-only path (WhatsApp / adoetz), unchanged.
  username_value := new.raw_user_meta_data->>'username';
  if username_value is null or new.raw_user_meta_data->>'invite_code' is null then
    raise exception 'Registration is invitation only';
  end if;
  select id into invite_id from private.invitations
  where token_hash = encode(extensions.digest(new.raw_user_meta_data->>'invite_code', 'sha256'), 'hex')
    and used_at is null and not revoked and expires_at > now()
  for update;
  if invite_id is null then
    raise exception 'Invitation unavailable';
  end if;
  insert into public.profiles (id, username, display_name)
    values (new.id, username_value, username_value);
  insert into private.accounts (id) values (new.id);
  update private.invitations set used_by = new.id, used_at = now() where id = invite_id;
  update auth.users set raw_user_meta_data = raw_user_meta_data - 'invite_code' where id = new.id;
  return new;
end
$function$;
