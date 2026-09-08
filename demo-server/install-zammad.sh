#!/usr/bin/env bash
# install-zammad.sh — Zammad demo instance for App Review on a Plesk host.
#
# Target: web05.world-ict.net (Ubuntu 22.04, Plesk), serving
# https://zammaddemo.world-ict.nl. Run as root AFTER the subdomain exists in
# Plesk (see README.md — step 1). Idempotent: safe to re-run.
#
# What it does:
#   1. PostgreSQL 14 + Redis 6 from Ubuntu (both hard requirements of Zammad).
#   2. Elasticsearch 9 from Elastic's repository. The Zammad .deb declares
#      `elasticsearch | elasticsearch-oss` as a dependency, so it cannot be
#      skipped by package even though it is optional at runtime. ES 9 ships
#      with security on and TLS auto-generated; this keeps that and wires the
#      credentials into Zammad rather than switching security off.
#   3. Zammad from the official packager.io repository.
#   4. Binds the Rails server and websocket to 127.0.0.1 only; Plesk's nginx
#      proxies to them (see plesk-nginx-directives.conf).
#   5. Removes the nginx site the package drops into /etc/nginx/sites-enabled —
#      on a Plesk host that file would shadow Plesk's own vhosts.
#   6. Sets FQDN/https, connects Elasticsearch, builds the search index.

set -euo pipefail

FQDN="${FQDN:-zammaddemo.world-ict.nl}"
ES_PASS_FILE=/root/.zammad-es-password

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo -i)." >&2
    exit 1
fi
export DEBIAN_FRONTEND=noninteractive

echo "==> [1/6] PostgreSQL + Redis"
apt-get update -qq
apt-get install -y -qq curl apt-transport-https gnupg postgresql redis-server
systemctl enable --now postgresql redis-server

# Redis must only ever listen locally — it has no auth by default.
if ! grep -qE '^bind 127\.0\.0\.1' /etc/redis/redis.conf; then
    sed -i 's/^bind .*/bind 127.0.0.1 ::1/' /etc/redis/redis.conf
    systemctl restart redis-server
fi

echo "==> [2/6] Elasticsearch 9"
if [[ ! -f /usr/share/keyrings/elasticsearch-keyring.gpg ]]; then
    curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
        | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
    chmod 644 /usr/share/keyrings/elasticsearch-keyring.gpg
fi
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" \
    > /etc/apt/sources.list.d/elastic-9.x.list
apt-get update -qq
apt-get install -y -qq elasticsearch

# A demo does not need the default heap (half of RAM); 1 GB is plenty and keeps
# the host's other vhosts comfortable.
mkdir -p /etc/elasticsearch/jvm.options.d
cat > /etc/elasticsearch/jvm.options.d/zammad.options <<'EOF'
-Xms1g
-Xmx1g
EOF
# Zammad's recommended ceiling for attachment indexing.
grep -q '^http.max_content_length' /etc/elasticsearch/elasticsearch.yml \
    || echo 'http.max_content_length: 400mb' >> /etc/elasticsearch/elasticsearch.yml

systemctl daemon-reload
systemctl enable --now elasticsearch.service
echo "    waiting for Elasticsearch to come up (first start takes a while)..."
for _ in $(seq 1 90); do
    if curl -ks -o /dev/null https://127.0.0.1:9200/; then break; fi
    sleep 2
done

# ES 9 does not print the elastic password on install; reset it once,
# non-interactively, and keep it root-only so re-runs reuse it.
if [[ ! -s "$ES_PASS_FILE" ]]; then
    /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s > "$ES_PASS_FILE"
    chmod 600 "$ES_PASS_FILE"
fi
ES_PASS="$(tr -d '[:space:]' < "$ES_PASS_FILE")"
curl -fks -u "elastic:${ES_PASS}" https://127.0.0.1:9200/ >/dev/null \
    || { echo "Elasticsearch is up but the elastic password in $ES_PASS_FILE does not work." >&2; exit 1; }

echo "==> [3/6] Zammad repository + package"
if [[ ! -f /usr/share/keyrings/zammad.gpg ]]; then
    curl -fsSL "https://go.packager.io/srv/deb/zammad/zammad/gpg-key.gpg" \
        -o /usr/share/keyrings/zammad.gpg
    chmod 644 /usr/share/keyrings/zammad.gpg
fi
curl -fsSL "https://go.packager.io/srv/zammad/zammad/stable/installer/ubuntu/22.04.list" \
    -o /etc/apt/sources.list.d/zammad.list
apt-get update -qq
apt-get install -y -qq zammad

echo "==> [4/6] Bind to loopback; Plesk's nginx is the only public face"
zammad config:set ZAMMAD_BIND_IP=127.0.0.1
zammad config:set ZAMMAD_RAILS_PORT=3000
zammad config:set ZAMMAD_WEBSOCKET_PORT=6042
zammad config:set ZAMMAD_WEB_CONCURRENCY=2

echo "==> [5/6] Drop the package's own nginx site (Plesk owns nginx here)"
# The postinst writes a server block for 'localhost' on :80/:443. Under Plesk
# that either conflicts with the panel's default vhost or is never included —
# either way it must not be there.
rm -f /etc/nginx/sites-enabled/zammad.conf /etc/nginx/sites-available/zammad.conf
systemctl reload nginx 2>/dev/null || systemctl reload sw-nginx 2>/dev/null || true

echo "==> [6/6] Instance settings + Elasticsearch link"
systemctl enable --now zammad
# The first migration can take a minute; wait for the app to answer before
# touching settings through it.
for _ in $(seq 1 90); do
    if curl -fs -o /dev/null http://127.0.0.1:3000/api/v1/getting_started; then break; fi
    sleep 2
done
# `zammad run` hands its arguments to `sh -c`, which mangles inline Ruby with
# quotes and parentheses. So the Ruby goes into a file that `rails r` reads
# itself. Rails runs as the `zammad` user, which can read neither /root nor
# /etc/elasticsearch/certs, hence the staging copies under /opt/zammad/tmp.
STAGE=/opt/zammad/tmp/demo-setup
mkdir -p "$STAGE"
cp /etc/elasticsearch/certs/http_ca.crt "$STAGE/es_ca.crt"
cat > "$STAGE/configure.rb" <<EOF
Setting.set('fqdn', '${FQDN}')
Setting.set('http_type', 'https')
Setting.set('api_token_access', true)
Setting.set('es_url', 'https://localhost:9200')
Setting.set('es_user', 'elastic')
Setting.set('es_password', File.read('${STAGE}/es_password').strip)
# Trust the auto-generated ES CA so es_ssl_verify can stay on; skip on re-run.
cert = File.read('${STAGE}/es_ca.crt')
SSLCertificate.create!(certificate: cert) unless SSLCertificate.exists?(certificate: cert)
puts "fqdn=#{Setting.get('fqdn')} http_type=#{Setting.get('http_type')} es_url=#{Setting.get('es_url')}"
puts "es-ca: #{SSLCertificate.count} certificate(s) trusted"
EOF
printf '%s' "$ES_PASS" > "$STAGE/es_password"
chown -R zammad:zammad "$STAGE"
chmod 700 "$STAGE"
chmod 600 "$STAGE"/*
zammad run rails r "$STAGE/configure.rb"
rm -rf "$STAGE"

systemctl restart zammad
echo "    building the search index..."
zammad run rake zammad:searchindex:rebuild >/dev/null

cat <<EOF

Done. Zammad is listening on 127.0.0.1:3000 (app) and 127.0.0.1:6042 (websocket);
Elasticsearch on 127.0.0.1:9200 (elastic password in ${ES_PASS_FILE}, root-only).

Next:
  1. In Plesk, for ${FQDN}: Apache & nginx Settings -> turn OFF "Proxy mode",
     paste plesk-nginx-directives.conf into "Additional nginx directives", apply.
  2. Issue a Let's Encrypt certificate for ${FQDN} in Plesk (SSL/TLS Certificates).
  3. Open https://${FQDN}/ once to run the getting-started wizard (admin account,
     organisation name, skip email channels).
  4. Run seed-demo.sh with the admin credentials to load the review data and
     mint the reviewer's API token.
EOF
