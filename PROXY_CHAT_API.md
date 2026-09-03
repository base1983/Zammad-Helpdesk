# Zammad Proxy — Chat API Specification

Server-side spec for the engineer-to-engineer chat used by the iOS app
(`ChatService.swift`). Deploy on `zammadproxy.world-ict.nl` alongside the
existing notification proxy. All endpoints live under `/api/chat/`.

## Authentication

Every request carries two headers:

| Header | Content |
|---|---|
| `Authorization` | `Token token=<zammad personal access token>` |
| `X-Zammad-Url` | The caller's Zammad instance URL, e.g. `https://helpdesk.example.com` |

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
  "proxy_user_id": "EXISTING-NOTIFICATION-PROXY-UUID-OR-EMPTY"
}
```
`proxy_user_id` links the chat identity to the existing push registration so
chat pushes reuse the stored APNS device token. Empty string = no push.

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
  { "id": 12, "zammad_user_id": 5, "name": "Bas Jonkers", "email": "b@example.com" },
  { "id": 13, "zammad_user_id": 8, "name": "Jane Doe", "email": "j@example.com" }
]
```

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
token, send a push:
```json
{
  "aps": { "alert": { "title": "<sender name>", "body": "<message body>" }, "sound": "default" },
  "chat_from_user_id": 12,
  "ticketID": 486
}
```
Including `ticketID` (only when the message references a ticket) lets the
app's existing DeepLinkManager open the ticket from the notification.

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

  const toUserJson = (u) => ({ id: u.id, zammad_user_id: u.zammad_user_id, name: u.name, email: u.email });
  const toMessageJson = (m) => ({
    id: m.id, from_user_id: m.from_user_id, to_user_id: m.to_user_id,
    body: m.body, ticket_id: m.ticket_id, ticket_number: m.ticket_number,
    created_at: m.created_at,
  });

  const router = express.Router();
  router.use(express.json());
  router.use(authenticate);

  router.post('/register', (req, res) => {
    const { name, email, proxy_user_id } = req.body || {};
    if (!name) return res.status(400).end();
    db.prepare(`
      INSERT INTO chat_users (instance_url, zammad_user_id, name, email, proxy_user_id)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(instance_url, zammad_user_id)
      DO UPDATE SET name = excluded.name, email = excluded.email, proxy_user_id = excluded.proxy_user_id
    `).run(req.zammad.instanceUrl, req.zammad.userId, name, email || null, proxy_user_id || null);
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
        const payload = {
          aps: { alert: { title: me.name, body }, sound: 'default' },
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

## Operational notes

- **Retention:** consider a cron that deletes messages older than e.g. 90 days.
- **Rate limiting:** basic per-user limits (e.g. 60 sends/min) prevent abuse.
- **Privacy:** message bodies are stored in plaintext on the proxy; mention
  this in the app's privacy policy. TLS covers transport.
- **Unregister:** when a device unregisters from notifications, keep the chat
  user row (history stays intact); pushes simply stop until they re-register.
