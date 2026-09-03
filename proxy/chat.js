// chat.js — engineer-to-engineer chat router for the Zammad notification proxy.
// Mounted from server.js:  app.use('/api/chat', createChatRouter({ pool, sendPush, lookupDeviceToken }))
//
// Adapted from PROXY_CHAT_API.md to this deployment: MariaDB (shared pool) instead
// of sqlite, and the existing APNs provider from server.js. See PROXY_CHAT_API.md
// in the iOS app repo for the client contract (ChatService.swift).

const express = require('express');
const crypto = require('crypto');

module.exports = function createChatRouter({ pool, sendPush, lookupDeviceToken }) {
    // Simple in-process cache of validated Zammad tokens (url+token -> zammad user id).
    const authCache = new Map(); // cacheKey -> { userId, expires }
    const AUTH_TTL_MS = 10 * 60 * 1000;

    // Basic per-user send rate limiting (60 sends / minute).
    const sendCounters = new Map(); // chatUserId -> { count, windowStart }
    const SEND_LIMIT = 60;
    const SEND_WINDOW_MS = 60 * 1000;

    function normalizeUrl(raw) {
        let url = (raw || '').trim().toLowerCase().replace(/\/+$/, '');
        if (!url) return '';
        if (!url.startsWith('http')) url = 'https://' + url;
        return url;
    }

    // Ensure the chat tables exist. Called once at startup from server.js.
    async function initSchema() {
        let conn;
        try {
            conn = await pool.getConnection();
            await conn.query(`
                CREATE TABLE IF NOT EXISTS chat_users (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    instance_url VARCHAR(255) NOT NULL,
                    zammad_user_id INT NOT NULL,
                    name VARCHAR(255) NOT NULL,
                    email VARCHAR(255),
                    proxy_user_id VARCHAR(255),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uniq_instance_user (instance_url, zammad_user_id)
                )
            `);
            await conn.query(`
                CREATE TABLE IF NOT EXISTS chat_messages (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    from_user_id INT NOT NULL,
                    to_user_id INT NOT NULL,
                    body TEXT NOT NULL,
                    ticket_id INT,
                    ticket_number VARCHAR(64),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    read_at TIMESTAMP NULL,
                    INDEX idx_msg_pair (from_user_id, to_user_id, id)
                )
            `);
            console.log("[Chat] Tables 'chat_users' and 'chat_messages' are ready.");
        } finally {
            if (conn) conn.release();
        }
    }

    // ISO 8601 UTC, matching the app's .iso8601 decoder.
    function isoUTC(value) {
        if (!value) return null;
        const d = (value instanceof Date) ? value : new Date(value);
        return d.toISOString().replace(/\.\d{3}Z$/, 'Z');
    }

    const toUserJson = (u) => ({
        id: u.id,
        zammad_user_id: u.zammad_user_id,
        name: u.name,
        email: u.email,
    });

    const toMessageJson = (m) => ({
        id: Number(m.id),
        from_user_id: m.from_user_id,
        to_user_id: m.to_user_id,
        body: m.body,
        ticket_id: m.ticket_id != null ? Number(m.ticket_id) : null,
        ticket_number: m.ticket_number != null ? String(m.ticket_number) : null,
        created_at: isoUTC(m.created_at),
    });

    // Validate the caller's Zammad token against their own instance.
    async function authenticate(req, res, next) {
        try {
            const instanceUrl = normalizeUrl(req.get('X-Zammad-Url'));
            const authHeader = req.get('Authorization') || '';
            if (!instanceUrl || !authHeader.startsWith('Token ')) return res.status(401).end();

            const cacheKey = crypto.createHash('sha256').update(instanceUrl + '|' + authHeader).digest('hex');
            const cached = authCache.get(cacheKey);
            if (cached && cached.expires > Date.now()) {
                req.zammad = { instanceUrl, userId: cached.userId };
                return next();
            }

            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), 10000);
            let resp;
            try {
                resp = await fetch(`${instanceUrl}/api/v1/users/me`, {
                    headers: { Authorization: authHeader },
                    signal: controller.signal,
                });
            } finally {
                clearTimeout(timer);
            }
            if (!resp.ok) return res.status(401).end();
            const me = await resp.json();
            if (!me || typeof me.id !== 'number') return res.status(401).end();

            authCache.set(cacheKey, { userId: me.id, expires: Date.now() + AUTH_TTL_MS });
            req.zammad = { instanceUrl, userId: me.id };
            next();
        } catch (e) {
            console.error('[Chat] auth error:', e.message);
            res.status(401).end();
        }
    }

    async function callerChatUser(req) {
        let conn;
        try {
            conn = await pool.getConnection();
            const rows = await conn.query(
                'SELECT * FROM chat_users WHERE instance_url = ? AND zammad_user_id = ?',
                [req.zammad.instanceUrl, req.zammad.userId]
            );
            return rows[0] || null;
        } finally {
            if (conn) conn.release();
        }
    }

    const router = express.Router();
    router.use(express.json());
    router.use(authenticate);

    // POST /register — upsert the caller in the chat directory.
    router.post('/register', async (req, res) => {
        const { name, email, proxy_user_id } = req.body || {};
        if (!name) return res.status(400).json({ error: 'name is required.' });
        let conn;
        try {
            conn = await pool.getConnection();
            await conn.query(`
                INSERT INTO chat_users (instance_url, zammad_user_id, name, email, proxy_user_id)
                VALUES (?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE name = VALUES(name), email = VALUES(email), proxy_user_id = VALUES(proxy_user_id)
            `, [req.zammad.instanceUrl, req.zammad.userId, name, email || null, proxy_user_id || null]);
            const rows = await conn.query(
                'SELECT id FROM chat_users WHERE instance_url = ? AND zammad_user_id = ?',
                [req.zammad.instanceUrl, req.zammad.userId]
            );
            res.json({ chat_user_id: rows[0].id });
        } catch (err) {
            console.error('[Chat] register error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // GET /users — all chat users on the caller's instance.
    router.get('/users', async (req, res) => {
        let conn;
        try {
            conn = await pool.getConnection();
            const users = await conn.query(
                'SELECT * FROM chat_users WHERE instance_url = ? ORDER BY name',
                [req.zammad.instanceUrl]
            );
            res.json(users.map(toUserJson));
        } catch (err) {
            console.error('[Chat] users error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // GET /conversations — summaries for the caller, newest first.
    router.get('/conversations', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            if (!me) return res.json([]);
            conn = await pool.getConnection();
            const partners = await conn.query(`
                SELECT DISTINCT CASE WHEN from_user_id = ? THEN to_user_id ELSE from_user_id END AS pid
                FROM chat_messages WHERE from_user_id = ? OR to_user_id = ?
            `, [me.id, me.id, me.id]);

            const result = [];
            for (const { pid } of partners) {
                const prows = await conn.query('SELECT * FROM chat_users WHERE id = ?', [pid]);
                const partner = prows[0];
                if (!partner || partner.instance_url !== me.instance_url) continue;
                const lrows = await conn.query(`
                    SELECT * FROM chat_messages
                    WHERE (from_user_id = ? AND to_user_id = ?) OR (from_user_id = ? AND to_user_id = ?)
                    ORDER BY id DESC LIMIT 1
                `, [me.id, pid, pid, me.id]);
                const urows = await conn.query(
                    'SELECT COUNT(*) AS c FROM chat_messages WHERE from_user_id = ? AND to_user_id = ? AND read_at IS NULL',
                    [pid, me.id]
                );
                result.push({
                    partner: toUserJson(partner),
                    last_message: lrows[0] ? toMessageJson(lrows[0]) : null,
                    unread_count: Number(urows[0].c),
                });
            }
            result.sort((a, b) => (b.last_message?.id || 0) - (a.last_message?.id || 0));
            res.json(result);
        } catch (err) {
            console.error('[Chat] conversations error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // GET /messages?with=13&since=341 — messages between caller and partner, ascending.
    router.get('/messages', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            const partnerId = parseInt(req.query.with, 10);
            if (!me || !partnerId) return res.status(400).json({ error: 'with is required.' });
            const since = parseInt(req.query.since, 10) || 0;
            conn = await pool.getConnection();
            const messages = await conn.query(`
                SELECT * FROM chat_messages
                WHERE ((from_user_id = ? AND to_user_id = ?) OR (from_user_id = ? AND to_user_id = ?)) AND id > ?
                ORDER BY id ASC LIMIT 200
            `, [me.id, partnerId, partnerId, me.id, since]);
            res.json(messages.map(toMessageJson));
        } catch (err) {
            console.error('[Chat] messages error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // POST /messages — send a message (optionally referencing a ticket).
    router.post('/messages', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            const { to_user_id, body, ticket_id, ticket_number } = req.body || {};
            if (!me || !to_user_id || !body) return res.status(400).json({ error: 'to_user_id and body are required.' });

            // Rate limit per sender.
            const now = Date.now();
            const counter = sendCounters.get(me.id);
            if (!counter || now - counter.windowStart > SEND_WINDOW_MS) {
                sendCounters.set(me.id, { count: 1, windowStart: now });
            } else {
                counter.count += 1;
                if (counter.count > SEND_LIMIT) return res.status(429).json({ error: 'Rate limit exceeded.' });
            }

            conn = await pool.getConnection();
            const rrows = await conn.query('SELECT * FROM chat_users WHERE id = ?', [to_user_id]);
            const recipient = rrows[0];
            if (!recipient || recipient.instance_url !== me.instance_url) {
                return res.status(400).json({ error: 'Invalid recipient.' });
            }

            const info = await conn.query(`
                INSERT INTO chat_messages (from_user_id, to_user_id, body, ticket_id, ticket_number)
                VALUES (?, ?, ?, ?, ?)
            `, [me.id, to_user_id, body, ticket_id || null, ticket_number || null]);
            const insertedId = Number(info.insertId);
            const mrows = await conn.query('SELECT * FROM chat_messages WHERE id = ?', [insertedId]);
            const message = mrows[0];

            // Best-effort push via the existing APNs pipeline.
            if (recipient.proxy_user_id) {
                try {
                    const deviceToken = await lookupDeviceToken(recipient.proxy_user_id);
                    if (deviceToken) {
                        const payload = { chat_from_user_id: me.id };
                        if (ticket_id) payload.ticketID = ticket_id;
                        sendPush(deviceToken, {
                            title: me.name,
                            body: String(body).length > 150 ? String(body).substring(0, 150) + '...' : String(body),
                            payload,
                        }).catch((e) => console.error('[Chat] push failed:', e.message));
                    }
                } catch (e) {
                    console.error('[Chat] push lookup failed:', e.message);
                }
            }

            res.json(toMessageJson(message));
        } catch (err) {
            console.error('[Chat] send error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // POST /read — mark messages from with_user_id to caller as read.
    router.post('/read', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            const partnerId = parseInt(req.body?.with_user_id, 10);
            if (!me || !partnerId) return res.status(400).json({ error: 'with_user_id is required.' });
            conn = await pool.getConnection();
            await conn.query(
                'UPDATE chat_messages SET read_at = UTC_TIMESTAMP() WHERE from_user_id = ? AND to_user_id = ? AND read_at IS NULL',
                [partnerId, me.id]
            );
            res.json({ ok: true });
        } catch (err) {
            console.error('[Chat] read error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    router.initSchema = initSchema;
    return router;
};
