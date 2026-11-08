CREATE OR REPLACE FUNCTION private.on_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  username_value text;
  invite_id uuid;
begin
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
$function$

