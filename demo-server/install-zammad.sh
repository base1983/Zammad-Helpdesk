#!/usr/bin/env bash
# install-zammad.sh — Zammad demo instance for App Review on a Plesk host.
#
# Target: web05.world-ict.net (Ubuntu 22.04, Plesk), serving
# https://zammaddemo.world-ict.nl. Run as root AFTER the subdomain exists in
# Plesk (see README.md — step 1). Idempotent: safe to re-run.
#
# What it does:
#   1. PostgreSQL 14 + Redis 6 from Ubuntu (both hard requirements of Zammad).
#   2. Zammad from the official packager.io repository.
#   3. Binds the Rails server and websocket to 127.0.0.1 only; Plesk's nginx
#      proxies to them (see plesk-nginx-directives.conf).
#   4. Removes the nginx site the package drops into /etc/nginx/sites-enabled —
#      on a Plesk host that file would shadow Plesk's own vhosts.
#   5. Sets FQDN/https so generated links and the CSRF origin check are right.
#
# Elasticsearch is deliberately skipped: it is optional, needs another ~2 GB of
# RAM, and a demo with a few dozen tickets searches fine without it.

set -euo pipefail

FQDN="${FQDN:-zammaddemo.world-ict.nl}"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo -i)." >&2
    exit 1
fi

echo "==> [1/5] PostgreSQL + Redis"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl apt-transport-https gnupg postgresql redis-server
systemctl enable --now postgresql redis-server

# Redis must only ever listen locally — it has no auth by default.
if ! grep -qE '^bind 127\.0\.0\.1' /etc/redis/redis.conf; then
    sed -i 's/^bind .*/bind 127.0.0.1 ::1/' /etc/redis/redis.conf
    systemctl restart redis-server
fi

echo "==> [2/5] Zammad repository + package"
if [[ ! -f /usr/share/keyrings/zammad.gpg ]]; then
    curl -fsSL "https://go.packager.io/srv/deb/zammad/zammad/gpg-key.gpg" \
        -o /usr/share/keyrings/zammad.gpg
    chmod 644 /usr/share/keyrings/zammad.gpg
fi
curl -fsSL "https://go.packager.io/srv/zammad/zammad/stable/installer/ubuntu/22.04.list" \
    -o /etc/apt/sources.list.d/zammad.list
apt-get update -qq
apt-get install -y -qq zammad

echo "==> [3/5] Bind to loopback; Plesk's nginx is the only public face"
zammad config:set ZAMMAD_BIND_IP=127.0.0.1
zammad config:set ZAMMAD_RAILS_PORT=3000
zammad config:set ZAMMAD_WEBSOCKET_PORT=6042
zammad config:set ZAMMAD_WEB_CONCURRENCY=2

echo "==> [4/5] Drop the package's own nginx site (Plesk owns nginx here)"
# The postinst writes a server block for 'localhost' on :80/:443. Under Plesk
# that either conflicts with the panel's default vhost or is never included —
# either way it must not be there.
rm -f /etc/nginx/sites-enabled/zammad.conf /etc/nginx/sites-available/zammad.conf
if command -v plesk >/dev/null; then
    plesk sbin nginxmng --enable >/dev/null 2>&1 || true
    plesk bin server_pref --update -nginx-reload true >/dev/null 2>&1 || true
    systemctl reload nginx || systemctl reload sw-nginx || true
fi

echo "==> [5/5] Instance settings"
systemctl enable --now zammad
# The first migration can take a minute; wait for the app to answer before
# touching settings through it.
for _ in $(seq 1 60); do
    if curl -fs -o /dev/null http://127.0.0.1:3000/api/v1/getting_started; then break; fi
    sleep 2
done
zammad run rails r "
Setting.set('fqdn', '${FQDN}')
Setting.set('http_type', 'https')
Setting.set('api_token_access', true)
Setting.set('system_init_done', true) if Setting.get('system_init_done').nil?
puts 'fqdn=' + Setting.get('fqdn') + ' http_type=' + Setting.get('http_type')
"
systemctl restart zammad

cat <<EOF

Done. Zammad is listening on 127.0.0.1:3000 (app) and 127.0.0.1:6042 (websocket).

Next:
  1. In Plesk, for ${FQDN}: Apache & nginx Settings -> turn OFF "Proxy mode",
     paste plesk-nginx-directives.conf into "Additional nginx directives", apply.
  2. Issue a Let's Encrypt certificate for ${FQDN} in Plesk (SSL/TLS Certificates).
  3. Open https://${FQDN}/ once to run the getting-started wizard (admin account,
     organisation name, skip email channels).
  4. Run seed-demo.sh with the admin credentials to load the review data and
     mint the reviewer's API token.
EOF
