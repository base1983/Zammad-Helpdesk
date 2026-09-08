# Demo Zammad for App Review — zammaddemo.world-ict.nl

App Review cannot test the app without a Zammad server, so this directory sets
one up on web05 (the Plesk host that already runs the notification proxy),
under the `world-ict.nl` subscription, and fills it with review data.

Zammad is a Rails app with PostgreSQL and Redis behind it — not a PHP site — so
two of the four steps need Plesk admin and root. The other two run from a
laptop.

## Steps, in order

| # | Who | What |
| --- | --- | --- |
| 1 | Plesk admin | Create the subdomain `zammaddemo` under `world-ict.nl`. DNS for the zone is served by this same host (`ns1`/`ns2.world-ict.nl` → 85.10.150.95), so Plesk adds the A record itself. |
| 2 | root on web05 | `sudo -i`, then run `install-zammad.sh`. Installs PostgreSQL, Redis and Zammad, binds Zammad to loopback, removes the nginx site the package drops (Plesk owns nginx here), sets FQDN/https. |
| 3 | Plesk admin | On the subdomain: *Apache & nginx Settings* → **Proxy mode off**, paste `plesk-nginx-directives.conf` into *Additional nginx directives*. Then *SSL/TLS Certificates* → Let's Encrypt. Open `https://zammaddemo.world-ict.nl/`, complete the getting-started wizard (admin account, organisation name, skip the email channels). |
| 4 | anyone | `ZAMMAD_URL=… ADMIN_USER=… ADMIN_PASS=… REVIEW_PASS=… ./seed-demo.sh` — creates the reviewer and colleague agents, customers, eight tickets, and prints the reviewer's API token for `APP_STORE_LISTING.md` §8. |

## What the reviewer gets

- **Server URL** `https://zammaddemo.world-ict.nl`, **API token** with
  `ticket.agent` — exactly what the setup wizard's "API token" path asks for.
- Eight tickets across new / open / pending / closed, some assigned to them,
  some to a colleague, some unassigned, so every filter in the app shows
  something.
- A second agent ("Demo Colleague") to hand tickets off to and to chat with.
  **Chat contacts appear only after an agent has opened the app on that
  instance**, so sign the colleague in from your own phone once before
  submitting — otherwise the "chat contacts are pre-loaded" line in the review
  notes is false.

## Choices made

- **Elasticsearch 9, security left on.** The plan was to skip it — optional at
  runtime, and a demo this size searches fine without — but the Zammad `.deb`
  declares `elasticsearch | elasticsearch-oss` as a hard dependency, so apt
  refuses to install Zammad without it. ES 9 arrives with authentication and
  auto-generated TLS; the script keeps both, resets the `elastic` password once
  into `/root/.zammad-es-password`, hands it to Zammad, and trusts the generated
  CA so `es_ssl_verify` stays on. Heap is pinned to 1 GB.
- **Loopback only.** Zammad listens on `127.0.0.1:3000` (app) and `:6042`
  (websocket); Plesk's nginx is the only thing on the public interface. Redis is
  pinned to `127.0.0.1` too — it ships without authentication.
- **`X-Forwarded-Proto https`, hardcoded.** Plesk terminates TLS, so `$scheme`
  would read `http` at the app and trip Zammad's CSRF origin check.
- **Same host as the proxy.** web05 has 8 cores, 16 GB and 328 GB free; Zammad
  plus a 1 GB Elasticsearch heap idles around 2–2.5 GB. If the demo ever
  competes with the other vhosts, Zammad's official Docker Compose on a small
  VPS is the clean alternative — `seed-demo.sh` works unchanged against it.

## Keeping it alive

The instance has to answer for the whole review, and again for every
resubmission. Nothing here expires; the only thing that can take it down is
the host. `systemctl status zammad` is the health check.
