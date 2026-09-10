#!/usr/bin/env bash
# restore.sh — load a backup.sh dump into a database. Two uses:
#
#   1. Restore test (do this once after setting up backups, then quarterly):
#      create an empty database in Plesk (Databases > Add, same user) and
#        ./restore.sh --into zammadproxy_restoretest backups/proxy/proxy-…sql.gz
#      then `./restore.sh --verify zammadproxy_restoretest` prints row counts.
#      Drop the test database in Plesk afterwards.
#
#   2. Real restore into the live database (after data loss):
#        ./restore.sh --yes backups/proxy/proxy-…sql.gz
#      Tables are dropped and recreated by the dump. Stop the app first
#      (Plesk > Node.js > Disable, or rename tmp/restart.txt trick will not do:
#      Passenger keeps serving), restore, then start it — otherwise a request
#      landing mid-restore sees half a schema.
#
# Credentials come from config.json like backup.sh. The target database
# defaults to the one in config.json; --into overrides it. A Plesk database
# user is bound to one database, so a scratch database usually has its own
# user: pass it as TARGET_USER / TARGET_PASS in the environment and they are
# used instead of the config.json credentials, e.g.
#   TARGET_USER=restoretest TARGET_PASS='…' ./restore.sh --into zammadproxy_restoretest dump.sql.gz

set -euo pipefail

PROXY_DIR="${PROXY_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONFIG="${CONFIG:-$PROXY_DIR/config.json}"

usage() { sed -n '2,20p' "$0"; exit 1; }

TARGET=""; YES=0; VERIFY=0; DUMP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --into) TARGET="$2"; shift 2 ;;
        --yes) YES=1; shift ;;
        --verify) VERIFY=1; TARGET="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) DUMP="$1"; shift ;;
    esac
done

{ read -r DB_HOST; read -r DB_PORT; read -r DB_USER; read -r DB_PASS; read -r DB_NAME; } < <(
    python3 - "$CONFIG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["dbConfig"]
for k in ("host", "port", "user", "password", "database"):
    print(c.get(k, ""))
PY
)
DB_HOST="${DB_HOST:-localhost}"; DB_PORT="${DB_PORT:-3306}"
TARGET="${TARGET:-$DB_NAME}"
if [[ -n "${TARGET_USER:-}" ]]; then DB_USER="$TARGET_USER"; DB_PASS="${TARGET_PASS:-}"; fi

DEFAULTS="$(mktemp)"
chmod 600 "$DEFAULTS"
printf '[client]\nhost=%s\nport=%s\nuser=%s\npassword=%s\n' "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" > "$DEFAULTS"
trap 'rm -f "$DEFAULTS"' EXIT
CLIENT="$(command -v mariadb || command -v mysql)"

if [[ $VERIFY -eq 1 ]]; then
    echo "row counts in $TARGET:"
    "$CLIENT" --defaults-extra-file="$DEFAULTS" "$TARGET" -e "
        SELECT 'registrations' AS t, COUNT(*) AS n FROM registrations
        UNION ALL SELECT 'chat_users', COUNT(*) FROM chat_users
        UNION ALL SELECT 'chat_devices', COUNT(*) FROM chat_devices
        UNION ALL SELECT 'chat_messages', COUNT(*) FROM chat_messages
        UNION ALL SELECT 'chat_attachments', COUNT(*) FROM chat_attachments;"
    exit 0
fi

[[ -n "$DUMP" && -r "$DUMP" ]] || usage
gzip -t "$DUMP" || { echo "corrupt archive: $DUMP" >&2; exit 1; }

if [[ "$TARGET" == "$DB_NAME" && $YES -ne 1 ]]; then
    echo "This replaces the LIVE database '$DB_NAME' with $(basename "$DUMP")." >&2
    echo "Re-run with --yes to confirm, or use --into <other-db> for a test restore." >&2
    exit 1
fi

echo "restoring $(basename "$DUMP") into $TARGET on $DB_HOST ..."
zcat "$DUMP" | "$CLIENT" --defaults-extra-file="$DEFAULTS" "$TARGET"
echo "done. Verify with: $0 --verify $TARGET"
