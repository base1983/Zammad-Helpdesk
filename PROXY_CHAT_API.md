# Zammad Proxy — Chat API Specification

Server-side spec for the engineer-to-engineer chat used by the iOS app
(`ChatService.swift`). Deploy on `zammadproxy.world-ict.nl` alongside the
existing notification proxy. All endpoints live under `/api/chat/`.

The reference implementation of this spec (v4, MariaDB) lives in `proxy/` in
this repo: `chat.js` (the router), `server.js` (mounting + APNs) and
`retention.js` (cron cleanup). The Node/Express/sqlite listing further down is
kept as the portable illustration of the v1/v2 core.

**Protocol history.** v2 added end-to-end encryption with one key per *user*;
v3 added groups and attachments; **v4 moves to one key per *device*** so an
agent can use the app on an iPhone and an iPad at the same time. Read the v4
section at the bottom before the older sections — it supersedes them wherever
they disagree, in particular `public_key` on `chat_users` (now on
`chat_devices`) and the shape of `/register`, `/users`, `/messages` and
`/groups`.

## Authentication

Every request carries two headers:

| Header | Content |
|---|---|
| `Authorization` | `Token token=<zammad personal access token>` |
| `X-Zammad-Url` | The caller's Zammad instance URL, e.g. `https://helpdesk.example.com` |
| `X-Device-Id` | (v4) The calling device's stable id, so the proxy can return the key envelopes addressed to it |

The proxy validates the pair by calling `GET <X-Zammad-Url>/api/v1/users/me`
with the same Authorization header. A successful response proves the caller is
a real user on that instance and yields their Zammad user id. **Cache
validations for ~10 minutes** (keyed on a hash of url+token) to avoid hammering
the Zammad instance. Users are scoped per instance: two users only see each
other if they registered with the same normalized `X-Zammad-Url`.

Return `401` when validation fails, `404`-free (all endpoints exist), `400` on
malformed bodies.

## Endpoints

### POST /api/chat/register
Registers or refreshes the caller in the chat directory.

Request body:
```json
{
  "zammad_user_id": 5,
  "name": "Bas Jonkers",
  "email": "b@example.com",
  "proxy_user_id": "EXISTING-NOTIFICATION-PROXY-UUID-OR-EMPTY",
  "public_key": "BASE64-CURVE25519-PUBLIC-KEY"
}
```
`proxy_user_id` links the chat identity to the existing push registration so
chat pushes reuse the stored APNS device token. Empty string = no push.

`public_key` (v2) is the device's Curve25519 public key for end-to-end
encryption. Store it verbatim and return it in `users` and `conversations`
responses. Message bodies arriving with an `enc1:` prefix are ciphertext the
proxy cannot (and must not try to) decrypt.

Response `200`:
```json
{ "chat_user_id": 12 }
```

### GET /api/chat/users
All chat users registered on the caller's instance (including the caller —
the app filters itself out).

Response `200`:
```json
[
  { "id": 12, "zammad_user_id": 5, "name": "Bas Jonkers", "email": "b@example.com", "public_key": "..." },
  { "id": 13, "zammad_user_id": 8, "name": "Jane Doe", "email": "j@example.com", "public_key": "..." }
]
```
Include `public_key` (may be null for old clients) here and in the `partner`
objects of `/conversations`.

### GET /api/chat/conversations
Conversation summaries for the caller, newest first.

Response `200`:
```json
[
  {
    "partner": { "id": 13, "zammad_user_id": 8, "name": "Jane Doe", "email": "j@example.com" },
    "last_message": {
      "id": 341, "from_user_id": 13, "to_user_id": 12,
      "body": "Sure, assign it to me",
      "ticket_id": null, "ticket_number": null,
      "created_at": "2026-09-03T09:12:44Z"
    },
    "unread_count": 2
  }
]
```

### GET /api/chat/messages?with=13&since=341
Messages between the caller and user `with`, ascending by id. `since`
(optional) returns only messages with `id > since` — the app polls with this
every 5 seconds while a conversation is open. Cap at 200 messages per response.

Response `200`: array of message objects (same shape as `last_message` above).
`created_at` must be ISO 8601 UTC.

### POST /api/chat/messages
Send a message. `ticket_id`/`ticket_number` are optional (ticket handoffs).

Request body:
```json
{ "to_user_id": 13, "body": "Can you take this one?", "ticket_id": 486, "ticket_number": "14478" }
```
Response `200`: the created message object.

Side effect: if the recipient has a linked `proxy_user_id` with an APNS device
token, send a push. **Do not include the message body** — with end-to-end
encryption it is ciphertext anyway. Use a generic alert:
```json
{
  "aps": { "alert": { "title": "<sender name>", "body": "New message" }, "sound": "default" },
  "chat_from_user_id": 12,
  "ticketID": 486
}
```
`chat_from_user_id` lets the app open the conversation directly when the push
is tapped. Include `ticketID` only when the message references a ticket; the
app then opens the ticket instead.

### POST /api/chat/read
Marks all messages from `with_user_id` to the caller as read.

Request body: `{ "with_user_id": 13 }` → Response `200`: `{ "ok": true }`

## Suggested implementation (Node.js / Express / better-sqlite3)

```js
// chat.js — mount with app.use('/api/chat', require('./chat')(deps))
const express = require('express');
const crypto = require('crypto');
const Database = require('better-sqlite3');

module.exports = function createChatRouter({ sendPush /* (deviceToken, payload) */, lookupDeviceToken /* (proxyUserId) => token|null */ }) {
  const db = new Database('chat.sqlite');
  db.pragma('journal_mode = WAL');
  db.exec(`
    CREATE TABLE IF NOT EXISTS chat_users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      instance_url TEXT NOT NULL,
      zammad_user_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      email TEXT,
      proxy_user_id TEXT,
      public_key TEXT,
      UNIQUE(instance_url, zammad_user_id)
    );
    CREATE TABLE IF NOT EXISTS chat_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      from_user_id INTEGER NOT NULL,
      to_user_id INTEGER NOT NULL,
      body TEXT NOT NULL,
      ticket_id INTEGER,
      ticket_number TEXT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
      read_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_msg_pair ON chat_messages(from_user_id, to_user_id, id);
  `);

  const authCache = new Map(); // hash -> { userId, expires }

  function normalizeUrl(raw) {
    let url = (raw || '').trim().toLowerCase().replace(/\/+$/, '');
    if (!url.startsWith('http')) url = 'https://' + url;
    return url;
  }

  // Validate the Zammad token against the caller's own instance.
  async function authenticate(req, res, next) {
    try {
      const instanceUrl = normalizeUrl(req.get('X-Zammad-Url'));
      const authHeader = req.get('Authorization') || '';
      if (!instanceUrl || !authHeader.startsWith('Token ')) return res.status(401).end();

      const cacheKey = crypto.createHash('sha256').update(instanceUrl + authHeader).digest('hex');
      const cached = authCache.get(cacheKey);
      if (cached && cached.expires > Date.now()) {
        req.zammad = { instanceUrl, userId: cached.userId };
        return next();
      }

      const resp = await fetch(`${instanceUrl}/api/v1/users/me`, { headers: { Authorization: authHeader } });
      if (!resp.ok) return res.status(401).end();
      const me = await resp.json();

      authCache.set(cacheKey, { userId: me.id, expires: Date.now() + 10 * 60 * 1000 });
      req.zammad = { instanceUrl, userId: me.id };
      next();
    } catch (e) {
      res.status(401).end();
    }
  }

  function callerChatUser(req) {
    return db.prepare('SELECT * FROM chat_users WHERE instance_url = ? AND zammad_user_id = ?')
             .get(req.zammad.instanceUrl, req.zammad.userId);
  }

  const toUserJson = (u) => ({ id: u.id, zammad_user_id: u.zammad_user_id, name: u.name, email: u.email, public_key: u.public_key });
  const toMessageJson = (m) => ({
    id: m.id, from_user_id: m.from_user_id, to_user_id: m.to_user_id,
    body: m.body, ticket_id: m.ticket_id, ticket_number: m.ticket_number,
    created_at: m.created_at,
  });

  const router = express.Router();
  router.use(express.json());
  router.use(authenticate);

  router.post('/register', (req, res) => {
    const { name, email, proxy_user_id, public_key } = req.body || {};
    if (!name) return res.status(400).end();
    db.prepare(`
      INSERT INTO chat_users (instance_url, zammad_user_id, name, email, proxy_user_id, public_key)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(instance_url, zammad_user_id)
      DO UPDATE SET name = excluded.name, email = excluded.email,
                    proxy_user_id = excluded.proxy_user_id, public_key = excluded.public_key
    `).run(req.zammad.instanceUrl, req.zammad.userId, name, email || null, proxy_user_id || null, public_key || null);
    res.json({ chat_user_id: callerChatUser(req).id });
  });

  router.get('/users', (req, res) => {
    const users = db.prepare('SELECT * FROM chat_users WHERE instance_url = ? ORDER BY name')
                    .all(req.zammad.instanceUrl);
    res.json(users.map(toUserJson));
  });

  router.get('/conversations', (req, res) => {
    const me = callerChatUser(req);
    if (!me) return res.json([]);
    const partners = db.prepare(`
      SELECT DISTINCT CASE WHEN from_user_id = ? THEN to_user_id ELSE from_user_id END AS pid
      FROM chat_messages WHERE from_user_id = ? OR to_user_id = ?
    `).all(me.id, me.id, me.id);

    const result = partners.map(({ pid }) => {
      const partner = db.prepare('SELECT * FROM chat_users WHERE id = ?').get(pid);
      if (!partner || partner.instance_url !== me.instance_url) return null;
      const last = db.prepare(`
        SELECT * FROM chat_messages
        WHERE (from_user_id = ? AND to_user_id = ?) OR (from_user_id = ? AND to_user_id = ?)
        ORDER BY id DESC LIMIT 1
      `).get(me.id, pid, pid, me.id);
      const unread = db.prepare(
        'SELECT COUNT(*) AS c FROM chat_messages WHERE from_user_id = ? AND to_user_id = ? AND read_at IS NULL'
      ).get(pid, me.id).c;
      return { partner: toUserJson(partner), last_message: last ? toMessageJson(last) : null, unread_count: unread };
    }).filter(Boolean);

    result.sort((a, b) => (b.last_message?.id || 0) - (a.last_message?.id || 0));
    res.json(result);
  });

  router.get('/messages', (req, res) => {
    const me = callerChatUser(req);
    const partnerId = parseInt(req.query.with, 10);
    if (!me || !partnerId) return res.status(400).end();
    const since = parseInt(req.query.since, 10) || 0;
    const messages = db.prepare(`
      SELECT * FROM chat_messages
      WHERE ((from_user_id = ? AND to_user_id = ?) OR (from_user_id = ? AND to_user_id = ?)) AND id > ?
      ORDER BY id ASC LIMIT 200
    `).all(me.id, partnerId, partnerId, me.id, since);
    res.json(messages.map(toMessageJson));
  });

  router.post('/messages', async (req, res) => {
    const me = callerChatUser(req);
    const { to_user_id, body, ticket_id, ticket_number } = req.body || {};
    if (!me || !to_user_id || !body) return res.status(400).end();

    const recipient = db.prepare('SELECT * FROM chat_users WHERE id = ?').get(to_user_id);
    if (!recipient || recipient.instance_url !== me.instance_url) return res.status(400).end();

    const info = db.prepare(`
      INSERT INTO chat_messages (from_user_id, to_user_id, body, ticket_id, ticket_number)
      VALUES (?, ?, ?, ?, ?)
    `).run(me.id, to_user_id, body, ticket_id || null, ticket_number || null);
    const message = db.prepare('SELECT * FROM chat_messages WHERE id = ?').get(info.lastInsertRowid);

    // Push to the recipient via the existing APNS pipeline (best effort).
    if (recipient.proxy_user_id) {
      const deviceToken = lookupDeviceToken(recipient.proxy_user_id);
      if (deviceToken) {
        // Never put the body in the push — it's E2E-encrypted ciphertext.
        const payload = {
          aps: { alert: { title: me.name, body: 'New message' }, sound: 'default' },
          chat_from_user_id: me.id,
        };
        if (ticket_id) payload.ticketID = ticket_id;
        sendPush(deviceToken, payload).catch(() => {});
      }
    }

    res.json(toMessageJson(message));
  });

  router.post('/read', (req, res) => {
    const me = callerChatUser(req);
    const partnerId = parseInt(req.body?.with_user_id, 10);
    if (!me || !partnerId) return res.status(400).end();
    db.prepare(`
      UPDATE chat_messages SET read_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')
      WHERE from_user_id = ? AND to_user_id = ? AND read_at IS NULL
    `).run(partnerId, me.id);
    res.json({ ok: true });
  });

  return router;
};
```

Wire it into the existing proxy app:

```js
const createChatRouter = require('./chat');
app.use('/api/chat', createChatRouter({
  sendPush: yourExistingApnsSendFunction,          // (deviceToken, payloadObject) => Promise
  lookupDeviceToken: (proxyUserId) => { /* read from your existing registration store */ },
}));
```

## v3: Groups & attachments

### Message object changes

Messages gain optional fields (all snake_case on the wire):
`group_id` (set for group messages, `to_user_id` is then null), `from_user_name`
(sender display name, needed for group rendering), `attachment_id`,
`attachment_name`, `attachment_mime`.

### POST /api/chat/groups
Creates a group. The group key is end-to-end encrypted: the client generates it
and uploads one *wrapped* (sealed) copy per member. The proxy must store the
wrapped keys verbatim — it can never read them.

```json
{
  "name": "iOS Team",
  "member_ids": [12, 13, 14],
  "wrapped_keys": [
    { "user_id": 12, "wrapped_key": "BASE64" },
    { "user_id": 13, "wrapped_key": "BASE64" },
    { "user_id": 14, "wrapped_key": "BASE64" }
  ]
}
```
`member_ids` includes the creator. Response `200` — the group as seen by the
caller:
```json
{
  "id": 3,
  "name": "iOS Team",
  "creator_id": 12,
  "creator_public_key": "BASE64",
  "my_wrapped_key": "BASE64",
  "members": [ { ...chat user objects incl. public_key... } ]
}
```

### GET /api/chat/groups
All groups the caller is a member of, same shape as above (`my_wrapped_key` is
the wrapped key stored for the *caller*; `creator_public_key` comes from the
creator's directory entry — members unwrap with the creator↔member pairwise
key).

### Group messages
- `POST /api/chat/messages` accepts `group_id` instead of `to_user_id`.
- `GET /api/chat/messages?group=3&since=...` returns group messages (include
  `from_user_name`).
- Push: notify all group members except the sender. Payload includes
  `chat_group_id` (the app then opens the group conversation):
  `{"aps": {"alert": {"title": "<sender> @ <group name>", "body": "New message"}, "sound": "default"}, "chat_group_id": 3}`
- `POST /api/chat/read` accepts `{"group_id": 3}` — mark the group read for the
  caller (per-user read state, e.g. a `group_reads(group_id, user_id, last_read_message_id)`
  table). Unread counts per group feed into `/conversations`: messages newer
  than the caller's `last_read_message_id` that they didn't send themselves.
- Every group endpoint checks membership and answers `403` when the caller
  isn't a member. Group messages have `to_user_id = null`, so the direct-message
  queries must exclude them (`group_id IS NULL`) — otherwise a group message
  shows up as a bogus direct conversation.

### GET /api/chat/conversations (v3 shape)
Entries are either direct (`partner` set) or group (`group` set):
```json
[
  { "partner": { ... }, "group": null, "last_message": { ... }, "unread_count": 2 },
  { "partner": null, "group": { "id": 3, "name": "iOS Team", "creator_id": 12,
      "creator_public_key": "BASE64", "my_wrapped_key": "BASE64" },
    "last_message": { ... }, "unread_count": 5 }
]
```

### Attachments
Attachment blobs are encrypted client-side (ChaChaPoly with the conversation's
pairwise/group key) before upload — store and serve them opaquely.

- `POST /api/chat/attachments` `{"data": "BASE64-CIPHERTEXT", "filename": "x.jpg", "mime_type": "image/jpeg"}`
  → `{"id": 42}`. Enforce a size limit (~15 MB base64). Only the uploader's
  instance may fetch it.
  The JSON body parser must allow this much: a default `express.json()` caps
  bodies at 100 kB and would reject every upload with a 413. In `proxy/`, the
  chat router parses its own bodies with a 20 MB limit and `server.js` skips
  the global parser for `/api/chat`, so the larger limit stays scoped to chat.
- `GET /api/chat/attachments/:id` → `{"data": "BASE64-CIPHERTEXT", "filename": "...", "mime_type": "..."}`
- Consider a cron deleting attachments older than the message retention window.

Suggested tables:
```sql
CREATE TABLE chat_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, instance_url TEXT NOT NULL, name TEXT NOT NULL, creator_id INTEGER NOT NULL);
CREATE TABLE chat_group_members (group_id INTEGER, user_id INTEGER, wrapped_key TEXT, PRIMARY KEY (group_id, user_id));
CREATE TABLE chat_group_reads (group_id INTEGER, user_id INTEGER, last_read_message_id INTEGER, PRIMARY KEY (group_id, user_id));
CREATE TABLE chat_attachments (id INTEGER PRIMARY KEY AUTOINCREMENT, instance_url TEXT NOT NULL, data BLOB NOT NULL, filename TEXT, mime_type TEXT, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')));
-- chat_messages gains: group_id INTEGER, attachment_id INTEGER, attachment_name TEXT, attachment_mime TEXT
```

## v4: Per-device keys (multi-device)

Up to v3 a user had exactly one `public_key` and one `proxy_user_id`, both
overwritten by `/register`. Installing the app on a second device therefore
replaced the first device's encryption key *and* stole its push registration:
the original device could no longer read new messages and stopped getting
notifications. v4 fixes this by making the *device*, not the user, the unit that
owns a key.

### Schema

```sql
CREATE TABLE chat_devices (
  id INT AUTO_INCREMENT PRIMARY KEY,
  chat_user_id INT NOT NULL,
  device_id VARCHAR(64) NOT NULL,      -- client-generated, stable per install
  public_key TEXT NOT NULL,
  proxy_user_id VARCHAR(255),          -- this device's own push registration
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_user_device (chat_user_id, device_id)
);

CREATE TABLE chat_message_keys (
  message_id BIGINT NOT NULL,
  device_id INT NOT NULL,              -- chat_devices.id
  wrapped_key TEXT NOT NULL,
  PRIMARY KEY (message_id, device_id)
);

CREATE TABLE chat_group_device_keys (
  group_id INT NOT NULL,
  device_id INT NOT NULL,              -- chat_devices.id
  wrapped_key TEXT NOT NULL,
  wrapper_public_key TEXT NOT NULL,    -- whose key to run the ECDH against
  PRIMARY KEY (group_id, device_id)
);

-- chat_messages gains: sender_public_key TEXT NULL
```

`chat_users.public_key` and `chat_users.proxy_user_id` are dead in v4. They are
left in place rather than dropped so an upgrade can't lose data, but nothing
reads or writes them. `chat_group_members.wrapped_key` is likewise superseded by
`chat_group_device_keys`.

### How a direct message is encrypted

The v2/v3 scheme sealed the body directly with the pairwise ECDH key, which only
works when there is exactly one key per side. v4 uses the indirection groups
already used:

1. The sender generates a **random 256-bit content key** for this one message.
2. The body (and the attachment, if any) is sealed with that content key.
3. The content key is wrapped once per device that may read it: every device of
   the recipient, plus the sender's *other* devices, each wrapped with the
   pairwise ECDH key between the sending device and that device.
4. The message row stores the sending device's `sender_public_key`; each
   envelope goes in `chat_message_keys`.

Reading is the reverse: `GET /messages` returns the calling device's own
`wrapped_key` (joined on `X-Device-Id`), the device unwraps it against
`sender_public_key`, then opens the body. A device with no envelope for a
message gets `wrapped_key: null` and shows the "encrypted message" placeholder —
which is the expected outcome for messages sent before that device existed.

Group messages are unchanged in shape: they stay sealed with the long-lived
group key, which is now wrapped per device in `chat_group_device_keys`.

### POST /api/chat/register

```json
{
  "zammad_user_id": 5,
  "name": "Bas Jonkers",
  "email": "b@example.com",
  "proxy_user_id": "NOTIFICATION-PROXY-UUID-OR-EMPTY",
  "public_key": "BASE64-CURVE25519-PUBLIC-KEY",
  "device_id": "CLIENT-GENERATED-UUID"
}
```

Upserts the user (name/email only) and this device. `device_id` and
`public_key` are required; `400` without them. Response:

```json
{
  "chat_user_id": 12,
  "chat_device_id": 30,
  "devices": [ { "id": 30, "public_key": "..." }, { "id": 31, "public_key": "..." } ]
}
```

`devices` is every device of the caller, so the client can wrap outgoing
messages for its own other devices.

### GET /api/chat/users

`public_key` is gone; each user carries a `devices` array instead. An empty
array means the colleague has never opened the app and cannot be messaged.

```json
[
  { "id": 12, "zammad_user_id": 5, "name": "Bas Jonkers", "email": "b@example.com",
    "devices": [ { "id": 30, "public_key": "..." }, { "id": 31, "public_key": "..." } ] }
]
```

### POST /api/chat/messages

Direct messages gain two required fields:

```json
{
  "to_user_id": 13,
  "body": "enc1:BASE64…",
  "sender_public_key": "BASE64-CURVE25519-PUBLIC-KEY",
  "keys": [
    { "device_id": 40, "wrapped_key": "BASE64…" },
    { "device_id": 41, "wrapped_key": "BASE64…" },
    { "device_id": 31, "wrapped_key": "BASE64…" }
  ]
}
```

Reject with `400` when a direct message arrives without `sender_public_key` or
with an empty `keys` array — storing it would produce a message nobody can ever
read. Envelopes addressed to a device that belongs to neither the recipient nor
the sender are silently dropped. Group messages send neither field.

### GET /api/chat/messages, /api/chat/conversations

Every message object gains `sender_public_key` and `wrapped_key`, the latter
being *this* device's envelope (`LEFT JOIN chat_message_keys ON device_id =
<caller's device>`). Both are `null` for group messages.

### Groups

`POST /api/chat/groups` now takes device-addressed envelopes:

```json
{
  "name": "Network team",
  "member_ids": [12, 13],
  "wrapped_keys": [
    { "device_id": 30, "wrapped_key": "…", "wrapper_public_key": "…" },
    { "device_id": 40, "wrapped_key": "…", "wrapper_public_key": "…" }
  ]
}
```

`GET /api/chat/groups` returns `my_wrapped_key` + `wrapper_public_key` for the
calling device, and `devices_missing_keys`: member devices that hold no envelope
for this group yet.

### POST /api/chat/groups/:id/keys

```json
{ "wrapped_keys": [ { "device_id": 41, "wrapped_key": "…", "wrapper_public_key": "…" } ] }
```

Response: `{ "added": 1 }`.

The self-healing half of multi-device. A group key is long-lived, so a device
registered after the group was created would otherwise be locked out forever.
Any member that can already open the group re-wraps the key for the devices in
`devices_missing_keys`; the client does this automatically after `GET /groups`.

Two rules make this safe: the caller must be a member (they can only pass on a
key they could already open), and existing envelopes are never overwritten
(`ON DUPLICATE KEY UPDATE group_id = group_id`), so no member can swap the group
key out from under everyone else.

### Push

Push fans out to **every** device of each recipient, looked up from
`chat_devices.proxy_user_id`. The sending device is excluded. For direct
messages the sender's own other devices are deliberately not pushed — they pick
the message up on their next refresh, and a "new message" alert for something
you just sent reads as a bug.

### Retention

`retention.js` deletes `chat_message_keys` rows whose message is gone, along
with the existing message and orphaned-attachment sweeps.

## APNS environments (dev vs TestFlight/App Store)

The APNS host must match the build that registered the device token, or Apple
rejects the push with `400 BadDeviceToken` — the classic "pushes work from
Xcode but not on TestFlight" failure:

| Build | Token type | APNS host |
|---|---|---|
| Xcode run on device | Sandbox | `api.sandbox.push.apple.com` |
| TestFlight / App Store | Production | `api.push.apple.com` |

(The app's entitlement says `aps-environment: development`, but Xcode swaps it
to `production` automatically when archiving for distribution.)

Recommended: try production first and fall back to sandbox on
`BadDeviceToken`, so one code path serves both environments. A `.p8` signing
key (token-based auth) works for both hosts unchanged:

```js
async function sendPush(deviceToken, payload) {
  const result = await sendVia('api.push.apple.com', deviceToken, payload);
  if (result.status === 400 && result.reason === 'BadDeviceToken') {
    // Development build token — retry against the sandbox environment.
    return sendVia('api.sandbox.push.apple.com', deviceToken, payload);
  }
  return result;
}
```

With node-apn, keep two `Provider` instances (`production: true` and `false`)
and retry on the other when the first reports `BadDeviceToken`.

Note: a device that switches between an Xcode build and a TestFlight build
gets a *different* token type; the app re-registers on launch and when the
notifications toggle is flipped, so the stored token follows the installed
build.

## Operational notes

- **Retention:** a cron deletes messages older than e.g. 90 days
  (`retention.js`), and sweeps attachment blobs past the same window that no
  message references any more — blobs outlive their message row otherwise.
- **Rate limiting:** basic per-user limits (e.g. 60 sends/min) prevent abuse.
- **Privacy:** since v2 the proxy stores ciphertext only — message bodies
  (`enc1:` prefix), wrapped group keys and attachment blobs are all sealed by
  the client, so the proxy cannot read them. What it does see in the clear:
  who talked to whom and when, group names and membership, attachment
  filenames/MIME types, and any referenced ticket id/number. TLS covers
  transport.
- **Unregister:** when a device unregisters from notifications, keep the chat
  user row (history stays intact); pushes simply stop until they re-register.
