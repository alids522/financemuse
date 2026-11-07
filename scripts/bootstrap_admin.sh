#!/usr/bin/env bash
# Finance Tracker — first-admin bootstrap (SERVER ONLY).
# Grants the admin role to an EXISTING Supabase auth user. This is the only
# supported way to create the first admin: there is no public endpoint and
# the first user is NOT auto-admin (PRD §7.2).
#
# Run ON THE ORACLE SERVER (it shells into the supabase-db container):
#   sudo bash scripts/bootstrap_admin.sh <auth-user-uuid>
#   sudo bash scripts/bootstrap_admin.sh --list
#   sudo bash scripts/bootstrap_admin.sh --revoke <auth-user-uuid>
#
# The auth user must already exist (sign up in the app first, or create via
# the Supabase Auth API / Studio). The script never takes or prints a
# password, token, or key. It refuses to remove the last remaining admin.
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-supabase-db}"

psql() {
  sudo docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

is_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

usage() {
  echo "Usage: $0 <auth-user-uuid> | --list | --revoke <auth-user-uuid>" >&2
  exit 2
}

case "${1:-}" in
  --list)
    psql -c "SELECT ur.user_id, u.email, ur.role, ur.created_at FROM financemuse.user_roles ur LEFT JOIN auth.users u ON u.id = ur.user_id ORDER BY ur.created_at;"
    ;;
  --revoke)
    UID="${2:-}"; is_uuid "$UID" || usage
    REMAINING="$(psql -tAc "SELECT COUNT(*) FROM financemuse.user_roles WHERE role='admin' AND user_id <> '$UID';")"
    if [ "$REMAINING" -eq 0 ]; then
      echo "REFUSING: $UID is the last admin." >&2
      exit 1
    fi
    psql -c "DELETE FROM financemuse.user_roles WHERE user_id='$UID' AND role='admin';"
    psql -c "INSERT INTO financemuse.admin_audit_logs (admin_user_id, target_user_id, action, reason, result) VALUES ('$UID', '$UID', 'revoke_admin', 'bootstrap script revoke', 'ok');"
    echo "Admin role revoked for $UID ($REMAINING admin(s) remain)."
    ;;
  '')
    usage
    ;;
  *)
    UID="$1"; is_uuid "$UID" || usage
    psql <<SQL
BEGIN;
-- Auth user must exist; otherwise the FK raises and nothing changes.
INSERT INTO financemuse.user_roles (user_id, role, created_by)
VALUES ('$UID', 'admin', '$UID')
ON CONFLICT (user_id, role) DO NOTHING;
INSERT INTO financemuse.admin_audit_logs (admin_user_id, target_user_id, action, reason, result)
VALUES ('$UID', '$UID', 'grant_admin', 'first-admin bootstrap (server script)', 'ok');
COMMIT;
SQL
    psql -c "SELECT user_id, role, created_at FROM financemuse.user_roles WHERE user_id='$UID';"
    echo "Done. $UID is now an admin. Verify in the app under Admin > User Management."
    ;;
esac
