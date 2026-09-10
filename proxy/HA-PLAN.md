# Making the proxy highly available — plan

The relay behind `zammadproxy.world-ict.nl` is one Node process under Passenger
on a shared Plesk host, with MariaDB on the same box, deployed by `scp`. This
plan gets it to "no single point of failure, automatic recovery, tested
backups, someone is told when it breaks" — and is honest about where
Kubernetes helps and where it just adds a second system to keep alive.

## 1. What actually breaks today, in order of likelihood × damage

| # | Risk | Effect | Notes |
| --- | --- | --- | --- |
| 1 | **No backups are known to exist** for the proxy database | Total loss of chat history, group keys, attachments; every agent silently loses push until they re-enable it | RPO today is "whenever Plesk last backed up", if ever. Fix before anything else. |
| 2 | **DNS for `world-ict.nl` runs on the proxy host** (`ns1`/`ns2` → 85.10.150.95) | If web05 is down, *nothing* under the domain resolves — proxy, demo, the company site, mail. HA of the proxy is meaningless while this stands | Independent of any runtime choice. |
| 3 | Single host, ~30 other vhosts, Passenger single process | Restart = seconds of 502; Plesk/OS update = minutes; hardware = hours-to-days | Deploys today are a `touch tmp/restart.txt` outage. |
| 4 | No monitoring | Outages are discovered by users | The retention log is the only thing that writes anywhere. |
| 5 | **Every agent's Zammad API token is stored in plaintext** in `registrations.zammadToken` — and the proxy never reads it | A database leak hands out write access to every customer's helpdesk | Pure liability. Drop the column. |
| 6 | Schema migrations run in-process at boot (`initSchema()`) | Fine for one process; two replicas booting together race on `ALTER TABLE` | Blocks any multi-replica setup until moved to a job. |
| 7 | Attachments as `LONGBLOB` in MariaDB (up to ~15 MB each) | Backups and replication carry gigabytes of ciphertext; DB is the scaling bottleneck | Belongs in object storage. |
| 8 | Per-process caches (`authCache`, `sendCounters`) | Harmless with one process; with N replicas the rate limit is N× looser and Zammad gets N× the auth calls | Acceptable at 2–3 replicas; note it, don't over-engineer. |
| 9 | App does not re-register push on launch, has no retries | After a DB restore, pushes stay dead until the user toggles the setting; a 30-second blip fails a send | Client-side change, cheap. |

What is *not* a risk: message content. It is end-to-end encrypted, and the
relay is genuinely just a relay.

## 2. What "highly available" should mean here

Users are helpdesk agents; the relay carries push notifications and chat, both
Premium features. A realistic, affordable target:

- **Availability 99.9 %** (≈ 45 min/month) for the API, measured externally.
- **RPO ≤ 24 h** for the database (nightly backup) — chat history is
  convenience, not record-keeping; registrations self-heal (see §4).
- **RTO ≤ 15 min** for a full rebuild from backup, and **seconds** for a single
  replica or node failure.
- **Zero-downtime deploys.**

Multi-region and five nines are not worth their cost for this workload.

## 3. Runtime options

All three need §4 first. Choose the runtime by how much you want to operate.

### A. Kubernetes (k3s on 3 Hetzner Cloud VMs, or a managed cluster)

- **Gives**: rolling deploys, self-healing pods, `PodDisruptionBudget`,
  Ingress with automatic TLS (cert-manager), `CronJob` for retention,
  `Job` for migrations, a clean secrets model, and a runtime you can move
  between providers.
- **Costs**: three nodes (~€5–15 each) + a load balancer (~€6) ≈ **€25–50/mo**
  for k3s; managed control planes (Scaleway Kapsule, OVH, DigitalOcean)
  add €0–30. Plus **your time**: certificates, node upgrades, etcd backups,
  CNI quirks, and the fact that the database still has to live *somewhere*
  HA — in-cluster MariaDB Galera is the hardest part of the whole stack.
- **Verdict**: worth it if you want Kubernetes as a skill or expect more
  services. For one Node app, it is a second system to keep alive.

### B. Two containers behind a provider load balancer + managed database

- Hetzner Cloud: 2 × CX22, a Load Balancer with health checks, and a managed
  Postgres/MariaDB (Hetzner has none yet — use Scaleway/DigitalOcean/Aiven
  managed MariaDB, or run MariaDB on a third VM with nightly snapshots).
  Or **Fly.io**: two machines in `ams`, built-in LB and TLS, managed Postgres
  with automated backups. ≈ **€20–40/mo**.
- **Gives**: the same "one node can die" guarantee, zero-downtime deploys via
  the LB, far less to operate.
- **Verdict**: the pragmatic choice for a one-person shop. Everything in §4 is
  identical, so switching to A later costs nothing but the manifests.

### C. Stay on Plesk, add a second Plesk host

Not recommended: Plesk's Node.js support is Passenger-only, no health checks,
no rolling restarts, and web05 remains a shared box with DNS on it.

## 4. Prerequisites (do these regardless of A or B)

Ordered so that each step is shippable on its own, with rough effort.

### Phase 0 — stop the bleeding (½ day, no code)

1. **Nightly `mysqldump` of the proxy DB to off-host storage** (Hetzner
   Storage Box / Backblaze), 30-day retention, and **restore it once** to
   prove it works. Until this is done nothing else matters.
2. **Uptime check** on `GET /api/chat/users` expecting 401 (that proves the
   app, its auth middleware and the DB pool are alive) — Uptime Kuma,
   Healthchecks.io, or Hetzner's own; alert to phone.
3. **Move DNS** for `world-ict.nl` to a real DNS provider (Hetzner DNS is free,
   Cloudflare too) or at minimum add a secondary NS on another host. Lower the
   TTL of `zammadproxy.world-ict.nl` to 300 s now — you will want that during
   the cutover in Phase 3.

### Phase 1 — make the proxy a 12-factor app (1–2 days)

4. **Config from environment**, not `config.json`: `DB_*`, `APNS_KEY`
   (the `.p8` contents, base64), `APNS_KEY_ID`, `APNS_TEAM_ID`,
   `APNS_BUNDLE_ID`, `PORT`. Keep `config.json` as a fallback for one release.
5. **`GET /healthz`** (process up) and **`GET /readyz`** (does `SELECT 1`
   against the pool, and are the APNs providers constructed). Load balancers
   and Kubernetes route only to ready replicas.
6. **Graceful shutdown**: on `SIGTERM` stop accepting, let in-flight requests
   finish (≤ 10 s), close the pool, exit 0. Today Passenger just kills it.
7. **Structured JSON logs** with a request id; keep `console.log` lines but
   make them parseable. Log to stdout only.
8. **Drop `registrations.zammadToken` and `zammadURL`** — never read, pure
   liability. Migration: `ALTER TABLE registrations DROP COLUMN …`; the app
   keeps sending them, the server ignores them.
9. **Dockerfile** (`node:24-alpine`, non-root, `HEALTHCHECK` → `/healthz`) and
   a `docker-compose.yml` with MariaDB for local development.
10. **CI on GitHub Actions**: `node --check`, the in-memory harness
    (Express + `node:sqlite`) that has exercised every proxy change so far —
    check it into `proxy/test/` instead of rebuilding it in a scratchpad — and
    a Docker build. Green CI becomes the precondition for deploy.

### Phase 2 — externalize state (2–3 days)

11. **Migrations as a separate step**: move `initSchema()` into
    `proxy/migrate.js`, run it as a `Job`/one-off container *before* the new
    version starts, guarded by `GET_LOCK('chat_migrate', 30)` so two runs
    cannot race. Replicas then never touch the schema.
12. **Attachments to object storage** (S3-compatible: Hetzner Object Storage,
    Backblaze B2, Cloudflare R2). `chat_attachments.data` becomes an object
    key; upload streams to the bucket, download returns a short-lived
    pre-signed URL (the client already treats the body as opaque
    ciphertext). Retention deletes objects with rows. One-off backfill script
    moves existing blobs.
13. **Shared rate limit and auth cache in Redis** — *optional*. With 2–3
    replicas the per-process versions are acceptable; add Redis only if the
    Zammad instances complain about `/users/me` traffic.
14. **Database**: managed MariaDB/Postgres with automated backups and a
    standby, or MariaDB on its own VM with nightly snapshots + the Phase 0
    dumps. If you ever switch to Postgres, the SQL is small enough
    (`ON DUPLICATE KEY UPDATE` → `ON CONFLICT`, `UTC_TIMESTAMP()` → `now() AT
    TIME ZONE 'UTC'`, `GET_LOCK` → `pg_advisory_lock`) — the harness already
    proves the router against a non-MariaDB engine.

### Phase 3 — the runtime (A: 3–5 days, B: 1–2 days)

15. For **A**: k3s, 3 nodes, `Deployment` with 2–3 replicas, `readinessProbe:
    /readyz`, `livenessProbe: /healthz`, `PodDisruptionBudget minAvailable: 1`,
    `Ingress` (nginx) + cert-manager Let's Encrypt, `Secret` for APNs/DB,
    `CronJob` for `retention.js`, `Job` for `migrate.js` as a pre-install
    hook, resource requests (~128 Mi / 0.1 CPU is plenty). Manifests in
    `proxy/deploy/k8s/`, applied by CI on tag.
16. For **B**: two machines, LB health check on `/readyz`, deploy = build
    image, start new, wait ready, stop old. Fly.io does this with one
    `fly deploy`.
17. **Cutover**: run the new stack in parallel against a *copy* of the DB,
    point a test hostname at it, run the harness against it end-to-end, then
    switch `zammadproxy.world-ict.nl` (TTL 300 s from Phase 0). Keep the
    Plesk instance untouched for a week as rollback. Because the app
    re-registers chat on every launch, registrations converge on their own.

### Phase 4 — resilience on the client (½ day, ships with the next app build)

18. **Re-register push on launch** when the setting is on, not only when it
    is toggled — then a DB restore or a host swap heals itself as agents open
    the app.
19. **Retry with backoff** on chat sends and registration (3 attempts,
    1/3/9 s) so a rolling deploy is invisible; queue an outgoing message
    locally when the relay is unreachable and show it as "pending".

### Phase 5 — prove it (½ day, repeat quarterly)

20. Kill a replica during a chat send; kill the DB primary; restore last
    night's dump into a fresh instance and point a test build at it. Write
    down how long each took. That number *is* your availability.

## 5. Recommendation

Do Phase 0 this week — it costs nothing and removes the two risks that would
actually hurt. Then Phase 1 and 2, which are code changes in this repo and
make the proxy portable. Only then pick the runtime: **B unless you want
Kubernetes for its own sake**; if you do, k3s on three small VMs with the
database *outside* the cluster is the version of A that a single operator can
keep alive. Phase 4 belongs in the next app release either way.

Total: about two working weeks of focused effort spread over a month, and
€25–50/month in hosting.
