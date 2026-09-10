#!/usr/bin/env bash
# backup.sh — nightly dump of the proxy database, verified, pruned, and
# (optionally) copied off the host. Phase 0 of proxy/HA-PLAN.md.
#
# Runs on web05 as the subscription user, from cron:
#   15 3 * * * cd /var/www/vhosts/world-ict.nl/zammadproxy.world-ict.nl && ./backup.sh >> /var/www/vhosts/world-ict.nl/backups/proxy/cron.log 2>&1
# (03:15 — after the 02:00 Veeam image of the host, so the dump never runs
# inside its snapshot, and before retention.js at 03:30, so it still holds
# what retention is about to delete. Each dump reaches the off-host image the
# following night.)
#
# Reads the database credentials from config.json next to server.js, so there
# is nothing to configure for a plain local dump.
#
# Off-host: the whole host is imaged nightly by Veeam to an external location,
# and that image includes BACKUP_DIR. A Veeam image of a running MariaDB is
# only crash-consistent; this dump is transactionally consistent and restores
# as a single database in minutes — so the two complement each other. Run it
# BEFORE the Veeam job so the day's dump is in the day's image. The rclone
# copy below is an optional second channel, not a requirement. Alerting is
# switched on by HEALTHCHECK_URL, see "Optional" below.
#
# Exit status is non-zero on any failure, and the failure is reported to the
# health-check URL when one is set — a backup that silently stops running is
# the failure mode this script exists to prevent.

set -euo pipefail
# Dumps hold every agent's push registration and the chat directory: 600, always.
umask 077

PROXY_DIR="${PROXY_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONFIG="${CONFIG:-$PROXY_DIR/config.json}"
# Outside every docroot: the subscription root, not httpdocs or a vhost dir.
BACKUP_DIR="${BACKUP_DIR:-/var/www/vhosts/world-ict.nl/backups/proxy}"
KEEP_DAYS="${KEEP_DAYS:-30}"

# Optional:
#   RCLONE_REMOTE="storagebox:proxy-backups"   copy each dump off-host with rclone
#   REMOTE_KEEP_DAYS=60                        prune the remote copy
#   HEALTHCHECK_URL="https://hc-ping.com/…"    ping on success, …/fail on failure
RCLONE_REMOTE="${RCLONE_REMOTE:-}"
REMOTE_KEEP_DAYS="${REMOTE_KEEP_DAYS:-60}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
ping_hc() { [[ -n "$HEALTHCHECK_URL" ]] && curl -fsS -m 10 --retry 3 -o /dev/null "$HEALTHCHECK_URL$1" || true; }
fail() { log "FAILED: $*"; ping_hc "/fail"; exit 1; }
trap 'fail "unexpected error on line $LINENO"' ERR

[[ -r "$CONFIG" ]] || fail "cannot read $CONFIG"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# --- credentials -----------------------------------------------------------
# Never on the command line (visible in `ps`): a 600 defaults file instead.
read_cfg() {
    if command -v python3 >/dev/null; then
        python3 - "$CONFIG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["dbConfig"]
for k in ("host", "port", "user", "password", "database"):
    print(c.get(k, ""))
PY
    elif command -v node >/dev/null; then
        node -e 'const c=require(process.argv[1]).dbConfig;for(const k of ["host","port","user","password","database"])console.log(c[k]??"")' "$CONFIG"
    else
        fail "need python3 or node to read config.json"
    fi
}
{ read -r DB_HOST; read -r DB_PORT; read -r DB_USER; read -r DB_PASS; read -r DB_NAME; } < <(read_cfg)
[[ -n "$DB_NAME" && -n "$DB_USER" ]] || fail "dbConfig in $CONFIG lacks user/database"
DB_HOST="${DB_HOST:-localhost}"; DB_PORT="${DB_PORT:-3306}"

DEFAULTS="$(mktemp "$BACKUP_DIR/.my.XXXXXX")"
chmod 600 "$DEFAULTS"
printf '[client]\nhost=%s\nport=%s\nuser=%s\npassword=%s\n' "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" > "$DEFAULTS"
trap 'rm -f "$DEFAULTS"' EXIT

DUMP_BIN="$(command -v mariadb-dump || command -v mysqldump || true)"
[[ -n "$DUMP_BIN" ]] || fail "neither mariadb-dump nor mysqldump is available to this user"

# --- dump ------------------------------------------------------------------
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/proxy-$DB_NAME-$STAMP.sql.gz"
log "dumping $DB_NAME from $DB_HOST to $(basename "$OUT")"
# --single-transaction: consistent snapshot without locking the live tables.
# --no-tablespaces: Plesk DB users lack the PROCESS privilege that would need.
"$DUMP_BIN" --defaults-extra-file="$DEFAULTS" \
    --single-transaction --quick --no-tablespaces --skip-lock-tables \
    --routines=0 --events=0 --triggers "$DB_NAME" | gzip -6 > "$OUT"

# --- verify ----------------------------------------------------------------
gzip -t "$OUT" || fail "gzip integrity check failed for $OUT"
zcat "$OUT" | tail -c 400 | grep -q -- "-- Dump completed" || fail "dump has no 'Dump completed' marker — truncated?"
for t in registrations chat_users chat_messages; do
    zcat "$OUT" | grep -q "CREATE TABLE \`$t\`" || fail "table $t missing from dump"
done
SIZE="$(du -h "$OUT" | cut -f1)"
log "verified: $SIZE, tables present"

# --- prune -----------------------------------------------------------------
find "$BACKUP_DIR" -name 'proxy-*.sql.gz' -mtime "+$KEEP_DAYS" -print -delete | sed 's/^/pruned /' || true

# --- off-host --------------------------------------------------------------
if [[ -n "$RCLONE_REMOTE" ]]; then
    # No root on this host, so rclone lives in ~/bin — which cron's PATH lacks.
    RCLONE="$(command -v rclone || true)"; [[ -x "$HOME/bin/rclone" ]] && RCLONE="$HOME/bin/rclone"
    [[ -n "$RCLONE" ]] || fail "RCLONE_REMOTE set but rclone is not installed (expected ~/bin/rclone)"
    "$RCLONE" copy "$OUT" "$RCLONE_REMOTE/" --quiet || fail "rclone copy failed"
    "$RCLONE" delete "$RCLONE_REMOTE/" --min-age "${REMOTE_KEEP_DAYS}d" --quiet || true
    log "copied to $RCLONE_REMOTE"
else
    log "no RCLONE_REMOTE set: off-host copy is left to the host-level (Veeam) backup"
fi

ping_hc ""
log "OK $(basename "$OUT")"
