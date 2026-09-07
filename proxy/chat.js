// chat.js — engineer-to-engineer chat router for the Zammad notification proxy.
// Mounted from server.js:  app.use('/api/chat', createChatRouter({ pool, sendPush, lookupDeviceToken }))
//
// Adapted from PROXY_CHAT_API.md to this deployment: MariaDB (shared pool) instead
// of sqlite, and the existing APNs provider from server.js. See PROXY_CHAT_API.md
// in the iOS app repo for the client contract (ChatService.swift).
//
// Protocol level: v3 — direct messages, groups and attachments. Bodies, group
// keys and attachment blobs are end-to-end encrypted by the client; the proxy
// stores them verbatim and can never read them.

const express = require('express');
const crypto = require('crypto');

// Attachment blobs arrive base64-encoded inside the JSON body. 10 MB of raw
// data (the app's own limit) is ~13.4 MB of base64, so cap a little above that.
const MAX_ATTACHMENT_BASE64 = 15 * 1024 * 1024;
const JSON_BODY_LIMIT = '20mb';

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

    // Run a schema migration that is expected to fail once it has been applied
    // (duplicate column / duplicate index). Anything else is a real error.
    async function migrate(conn, sql, description) {
        try {
            await conn.query(sql);
            console.log(`[Chat] Migration applied: ${description}.`);
        } catch (e) {
            if (/duplicate column|duplicate key name/i.test(e.message)) return;
            throw e;
        }
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
                    public_key TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE KEY uniq_instance_user (instance_url, zammad_user_id)
                )
            `);
            // Migration: add public_key to a pre-existing table (v2, E2E encryption).
            await migrate(conn, 'ALTER TABLE chat_users ADD COLUMN public_key TEXT', "chat_users.public_key");

            await conn.query(`
                CREATE TABLE IF NOT EXISTS chat_messages (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    from_user_id INT NOT NULL,
                    to_user_id INT NULL,
                    group_id INT NULL,
                    body TEXT NOT NULL,
                    ticket_id INT,
                    ticket_number VARCHAR(64),
                    attachment_id BIGINT NULL,
                    attachment_name VARCHAR(255) NULL,
                    attachment_mime VARCHAR(128) NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    read_at TIMESTAMP NULL,
                    INDEX idx_msg_pair (from_user_id, to_user_id, id),
                    INDEX idx_msg_group (group_id, id)
                )
            `);
            // Migrations for a pre-existing v2 table (group + attachment support).
            await migrate(conn, 'ALTER TABLE chat_messages ADD COLUMN group_id INT NULL', 'chat_messages.group_id');
            await migrate(conn, 'ALTER TABLE chat_messages ADD COLUMN attachment_id BIGINT NULL', 'chat_messages.attachment_id');
            await migrate(conn, 'ALTER TABLE chat_messages ADD COLUMN attachment_name VARCHAR(255) NULL', 'chat_messages.attachment_name');
            await migrate(conn, 'ALTER TABLE chat_messages ADD COLUMN attachment_mime VARCHAR(128) NULL', 'chat_messages.attachment_mime');
            await migrate(conn, 'ALTER TABLE chat_messages ADD INDEX idx_msg_group (group_id, id)', 'chat_messages idx_msg_group');
            // Group messages have no recipient — to_user_id must be nullable.
            // Only ALTER when it isn't already: MODIFY rebuilds the table, and
            // chat_messages is the one table that actually grows.
            const nullable = await conn.query(`
                SELECT IS_NULLABLE FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'chat_messages' AND COLUMN_NAME = 'to_user_id'
            `);
            if (nullable[0] && String(nullable[0].IS_NULLABLE).toUpperCase() === 'NO') {
                await conn.query('ALTER TABLE chat_messages MODIFY COLUMN to_user_id INT NULL');
                console.log('[Chat] Migration applied: chat_messages.to_user_id is now nullable.');
            }

            await conn.query(`
                CREATE TABLE IF NOT EXISTS chat_groups (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    instance_url VARCHAR(255) NOT NULL,
                    name VARCHAR(255) NOT NULL,
                    creator_id INT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_group_instance (instance_url)
                )
            `);
            await conn.query(`
                CREATE TABLE IF NOT EXISTS chat_group_members (
                    group_id INT NOT NULL,
                    user_id INT NOT NULL,
                    wrapped_key TEXT,
                    PRIMARY KEY (group_id, user_id),
                    INDEX idx_group_member_user (user_id)
                )
            `);
            await conn.query(`
                CREATE TABLE IF NOT EXISTS chat_group_reads (
                    group_id INT NOT NULL,
                    user_id INT NOT NULL,
                    last_read_message_id BIGINT NOT NULL DEFAULT 0,
                    PRIMARY KEY (group_id, user_id)
                )
            `);
            await conn.query(`
                CREATE TABLE IF NOT EXISTS chat_attachments (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    instance_url VARCHAR(255) NOT NULL,
                    uploader_id INT NOT NULL,
                    data LONGBLOB NOT NULL,
                    filename VARCHAR(255),
                    mime_type VARCHAR(128),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_attachment_instance (instance_url)
                )
            `);
            console.log("[Chat] Tables are ready (users, messages, groups, group members/reads, attachments).");
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

    const num = (v) => (v != null ? Number(v) : null);

    const toUserJson = (u) => ({
        id: Number(u.id),
        zammad_user_id: u.zammad_user_id,
        name: u.name,
        email: u.email,
        public_key: u.public_key != null ? u.public_key : null,
    });

    const toMessageJson = (m) => ({
        id: Number(m.id),
        from_user_id: Number(m.from_user_id),
        to_user_id: num(m.to_user_id),
        group_id: num(m.group_id),
        from_user_name: m.from_user_name != null ? m.from_user_name : null,
        body: m.body,
        ticket_id: num(m.ticket_id),
        ticket_number: m.ticket_number != null ? String(m.ticket_number) : null,
        attachment_id: num(m.attachment_id),
        attachment_name: m.attachment_name != null ? m.attachment_name : null,
        attachment_mime: m.attachment_mime != null ? m.attachment_mime : null,
        created_at: isoUTC(m.created_at),
    });

    // Every message SELECT joins the sender so group rendering has a display name.
    const MESSAGE_SELECT = `
        SELECT m.*, u.name AS from_user_name
        FROM chat_messages m
        LEFT JOIN chat_users u ON u.id = m.from_user_id
    `;

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

    // --- Group helpers ---------------------------------------------------

    async function isGroupMember(conn, groupId, userId) {
        const rows = await conn.query(
            'SELECT 1 AS ok FROM chat_group_members WHERE group_id = ? AND user_id = ?',
            [groupId, userId]
        );
        return rows.length > 0;
    }

    // The group as seen by one member: their own wrapped key plus the creator's
    // public key (members unwrap with the creator<->member pairwise key).
    async function groupJson(conn, group, viewerId) {
        const members = await conn.query(`
            SELECT u.*, m.wrapped_key
            FROM chat_group_members m
            JOIN chat_users u ON u.id = m.user_id
            WHERE m.group_id = ?
            ORDER BY u.name
        `, [group.id]);

        const creatorId = Number(group.creator_id);
        let creator = members.find((m) => Number(m.id) === creatorId);
        if (!creator) {
            const rows = await conn.query('SELECT * FROM chat_users WHERE id = ?', [creatorId]);
            creator = rows[0] || null;
        }
        const mine = members.find((m) => Number(m.id) === Number(viewerId));

        return {
            id: Number(group.id),
            name: group.name,
            creator_id: creatorId,
            creator_public_key: creator && creator.public_key != null ? creator.public_key : null,
            my_wrapped_key: mine && mine.wrapped_key != null ? mine.wrapped_key : null,
            members: members.map(toUserJson),
        };
    }

    async function groupsForUser(conn, userId) {
        return conn.query(`
            SELECT g.* FROM chat_groups g
            JOIN chat_group_members m ON m.group_id = g.id
            WHERE m.user_id = ?
            ORDER BY g.id
        `, [userId]);
    }

    async function lastReadMessageId(conn, groupId, userId) {
        const rows = await conn.query(
            'SELECT last_read_message_id FROM chat_group_reads WHERE group_id = ? AND user_id = ?',
            [groupId, userId]
        );
        return rows[0] ? Number(rows[0].last_read_message_id) : 0;
    }

    // --- Push helpers ----------------------------------------------------

    // Best-effort push; never rejects, so a failed delivery can't fail a send.
    async function pushTo(recipient, message) {
        if (!recipient || !recipient.proxy_user_id) return;
        try {
            const deviceToken = await lookupDeviceToken(recipient.proxy_user_id);
            if (!deviceToken) return;
            await sendPush(deviceToken, message);
        } catch (e) {
            console.error('[Chat] push failed:', e.message);
        }
    }

    const router = express.Router();
    // Attachments are posted as base64 inside the JSON body, so this router
    // needs a much larger limit than the proxy's default parser.
    router.use(express.json({ limit: JSON_BODY_LIMIT }));
    router.use(authenticate);

    // POST /register — upsert the caller in the chat directory.
    router.post('/register', async (req, res) => {
        const { name, email, proxy_user_id, public_key } = req.body || {};
        if (!name) return res.status(400).json({ error: 'name is required.' });
        let conn;
        try {
            conn = await pool.getConnection();
            await conn.query(`
                INSERT INTO chat_users (instance_url, zammad_user_id, name, email, proxy_user_id, public_key)
                VALUES (?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE name = VALUES(name), email = VALUES(email), proxy_user_id = VALUES(proxy_user_id), public_key = VALUES(public_key)
            `, [req.zammad.instanceUrl, req.zammad.userId, name, email || null, proxy_user_id || null, public_key || null]);
            const rows = await conn.query(
                'SELECT id FROM chat_users WHERE instance_url = ? AND zammad_user_id = ?',
                [req.zammad.instanceUrl, req.zammad.userId]
            );
            res.json({ chat_user_id: Number(rows[0].id) });
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

    // GET /conversations — direct and group summaries for the caller, newest first.
    router.get('/conversations', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            if (!me) return res.json([]);
            conn = await pool.getConnection();

            const result = [];

            // Direct conversations (group messages carry no partner).
            const partners = await conn.query(`
                SELECT DISTINCT CASE WHEN from_user_id = ? THEN to_user_id ELSE from_user_id END AS pid
                FROM chat_messages
                WHERE group_id IS NULL AND (from_user_id = ? OR to_user_id = ?)
            `, [me.id, me.id, me.id]);

            for (const { pid } of partners) {
                if (pid == null) continue;
                const prows = await conn.query('SELECT * FROM chat_users WHERE id = ?', [pid]);
                const partner = prows[0];
                if (!partner || partner.instance_url !== me.instance_url) continue;
                const lrows = await conn.query(`
                    ${MESSAGE_SELECT}
                    WHERE m.group_id IS NULL
                      AND ((m.from_user_id = ? AND m.to_user_id = ?) OR (m.from_user_id = ? AND m.to_user_id = ?))
                    ORDER BY m.id DESC LIMIT 1
                `, [me.id, pid, pid, me.id]);
                const urows = await conn.query(
                    'SELECT COUNT(*) AS c FROM chat_messages WHERE group_id IS NULL AND from_user_id = ? AND to_user_id = ? AND read_at IS NULL',
                    [pid, me.id]
                );
                result.push({
                    partner: toUserJson(partner),
                    group: null,
                    last_message: lrows[0] ? toMessageJson(lrows[0]) : null,
                    unread_count: Number(urows[0].c),
                });
            }

            // Group conversations.
            const groups = await groupsForUser(conn, me.id);
            for (const group of groups) {
                const lrows = await conn.query(`
                    ${MESSAGE_SELECT}
                    WHERE m.group_id = ?
                    ORDER BY m.id DESC LIMIT 1
                `, [group.id]);
                const lastRead = await lastReadMessageId(conn, group.id, me.id);
                const urows = await conn.query(
                    'SELECT COUNT(*) AS c FROM chat_messages WHERE group_id = ? AND from_user_id <> ? AND id > ?',
                    [group.id, me.id, lastRead]
                );
                result.push({
                    partner: null,
                    group: await groupJson(conn, group, me.id),
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

    // POST /groups — create a group. wrapped_keys are opaque to the proxy.
    router.post('/groups', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            if (!me) return res.status(400).json({ error: 'Not registered for chat.' });
            const { name, member_ids, wrapped_keys } = req.body || {};
            if (!name || !Array.isArray(member_ids) || member_ids.length === 0) {
                return res.status(400).json({ error: 'name and member_ids are required.' });
            }

            // The creator is always a member, even if the client forgot to list them.
            const memberIds = [...new Set(member_ids.map((id) => parseInt(id, 10)).filter(Boolean).concat(Number(me.id)))];

            conn = await pool.getConnection();
            const members = await conn.query(
                `SELECT * FROM chat_users WHERE id IN (${memberIds.map(() => '?').join(',')})`,
                memberIds
            );
            if (members.length !== memberIds.length ||
                members.some((m) => m.instance_url !== me.instance_url)) {
                return res.status(400).json({ error: 'Invalid members.' });
            }

            const wrappedFor = new Map();
            for (const entry of Array.isArray(wrapped_keys) ? wrapped_keys : []) {
                const userId = parseInt(entry?.user_id, 10);
                if (userId && typeof entry.wrapped_key === 'string') wrappedFor.set(userId, entry.wrapped_key);
            }

            await conn.beginTransaction();
            try {
                const info = await conn.query(
                    'INSERT INTO chat_groups (instance_url, name, creator_id) VALUES (?, ?, ?)',
                    [me.instance_url, String(name).slice(0, 255), me.id]
                );
                const groupId = Number(info.insertId);
                for (const id of memberIds) {
                    await conn.query(
                        'INSERT INTO chat_group_members (group_id, user_id, wrapped_key) VALUES (?, ?, ?)',
                        [groupId, id, wrappedFor.get(id) || null]
                    );
                }
                await conn.commit();

                const grows = await conn.query('SELECT * FROM chat_groups WHERE id = ?', [groupId]);
                res.json(await groupJson(conn, grows[0], me.id));
            } catch (e) {
                await conn.rollback();
                throw e;
            }
        } catch (err) {
            console.error('[Chat] create group error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // GET /groups — every group the caller belongs to.
    router.get('/groups', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            if (!me) return res.json([]);
            conn = await pool.getConnection();
            const groups = await groupsForUser(conn, me.id);
            const result = [];
            for (const group of groups) result.push(await groupJson(conn, group, me.id));
            res.json(result);
        } catch (err) {
            console.error('[Chat] groups error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // GET /messages?with=13&since=341 — direct messages, ascending.
    // GET /messages?group=3&since=341 — group messages, ascending.
    router.get('/messages', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            const partnerId = parseInt(req.query.with, 10);
            const groupId = parseInt(req.query.group, 10);
            if (!me || (!partnerId && !groupId)) {
                return res.status(400).json({ error: 'with or group is required.' });
            }
            const since = parseInt(req.query.since, 10) || 0;
            conn = await pool.getConnection();

            let messages;
            if (groupId) {
                if (!(await isGroupMember(conn, groupId, me.id))) {
                    return res.status(403).json({ error: 'Not a member of this group.' });
                }
                messages = await conn.query(`
                    ${MESSAGE_SELECT}
                    WHERE m.group_id = ? AND m.id > ?
                    ORDER BY m.id ASC LIMIT 200
                `, [groupId, since]);
            } else {
                messages = await conn.query(`
                    ${MESSAGE_SELECT}
                    WHERE m.group_id IS NULL
                      AND ((m.from_user_id = ? AND m.to_user_id = ?) OR (m.from_user_id = ? AND m.to_user_id = ?))
                      AND m.id > ?
                    ORDER BY m.id ASC LIMIT 200
                `, [me.id, partnerId, partnerId, me.id, since]);
            }
            res.json(messages.map(toMessageJson));
        } catch (err) {
            console.error('[Chat] messages error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // POST /messages — send a direct (to_user_id) or group (group_id) message.
    router.post('/messages', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            const { to_user_id, group_id, body, ticket_id, ticket_number,
                    attachment_id, attachment_name, attachment_mime } = req.body || {};
            if (!me || (!to_user_id && !group_id) || !body) {
                return res.status(400).json({ error: 'body and one of to_user_id / group_id are required.' });
            }

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

            // An attachment must exist and belong to the caller's instance.
            let attachmentId = null;
            if (attachment_id) {
                attachmentId = parseInt(attachment_id, 10);
                const arows = await conn.query('SELECT instance_url FROM chat_attachments WHERE id = ?', [attachmentId]);
                if (!arows[0] || arows[0].instance_url !== me.instance_url) {
                    return res.status(400).json({ error: 'Invalid attachment.' });
                }
            }

            let recipient = null;
            let group = null;
            if (group_id) {
                const groupId = parseInt(group_id, 10);
                const grows = await conn.query('SELECT * FROM chat_groups WHERE id = ?', [groupId]);
                group = grows[0];
                if (!group || group.instance_url !== me.instance_url || !(await isGroupMember(conn, groupId, me.id))) {
                    return res.status(403).json({ error: 'Not a member of this group.' });
                }
            } else {
                const rrows = await conn.query('SELECT * FROM chat_users WHERE id = ?', [to_user_id]);
                recipient = rrows[0];
                if (!recipient || recipient.instance_url !== me.instance_url) {
                    return res.status(400).json({ error: 'Invalid recipient.' });
                }
            }

            const info = await conn.query(`
                INSERT INTO chat_messages
                    (from_user_id, to_user_id, group_id, body, ticket_id, ticket_number,
                     attachment_id, attachment_name, attachment_mime)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            `, [
                me.id,
                group ? null : recipient.id,
                group ? group.id : null,
                body,
                ticket_id || null,
                ticket_number || null,
                attachmentId,
                attachmentId ? (attachment_name || null) : null,
                attachmentId ? (attachment_mime || null) : null,
            ]);
            const insertedId = Number(info.insertId);
            const mrows = await conn.query(`${MESSAGE_SELECT} WHERE m.id = ?`, [insertedId]);
            const message = mrows[0];

            // Best-effort push via the existing APNs pipeline. Never put the
            // message body in the push — it's E2E-encrypted ciphertext. The body
            // is sent as an APNS loc-key so the app localizes it on-device;
            // `body` is only a fallback for clients missing the key.
            if (group) {
                const recipients = await conn.query(`
                    SELECT u.* FROM chat_group_members m
                    JOIN chat_users u ON u.id = m.user_id
                    WHERE m.group_id = ? AND u.id <> ? AND u.proxy_user_id IS NOT NULL
                `, [group.id, me.id]);
                const payload = { chat_group_id: Number(group.id) };
                if (ticket_id) payload.ticketID = ticket_id;
                const push = {
                    title: `${me.name} @ ${group.name}`,
                    bodyLocKey: 'chat_new_message',
                    body: 'New message',
                    payload,
                };
                // Fire and forget — the sender shouldn't wait on APNs.
                Promise.all(recipients.map((r) => pushTo(r, push))).catch(() => {});
            } else {
                const payload = { chat_from_user_id: Number(me.id) };
                if (ticket_id) payload.ticketID = ticket_id;
                pushTo(recipient, {
                    title: me.name,
                    bodyLocKey: 'chat_new_message',
                    body: 'New message',
                    payload,
                });
            }

            res.json(toMessageJson(message));
        } catch (err) {
            console.error('[Chat] send error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // POST /read — mark a direct conversation (with_user_id) or a group
    // (group_id) as read for the caller.
    router.post('/read', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            const partnerId = parseInt(req.body?.with_user_id, 10);
            const groupId = parseInt(req.body?.group_id, 10);
            if (!me || (!partnerId && !groupId)) {
                return res.status(400).json({ error: 'with_user_id or group_id is required.' });
            }
            conn = await pool.getConnection();

            if (groupId) {
                if (!(await isGroupMember(conn, groupId, me.id))) {
                    return res.status(403).json({ error: 'Not a member of this group.' });
                }
                const rows = await conn.query('SELECT MAX(id) AS maxId FROM chat_messages WHERE group_id = ?', [groupId]);
                const maxId = rows[0]?.maxId != null ? Number(rows[0].maxId) : 0;
                await conn.query(`
                    INSERT INTO chat_group_reads (group_id, user_id, last_read_message_id)
                    VALUES (?, ?, ?)
                    ON DUPLICATE KEY UPDATE last_read_message_id = GREATEST(last_read_message_id, VALUES(last_read_message_id))
                `, [groupId, me.id, maxId]);
            } else {
                await conn.query(
                    'UPDATE chat_messages SET read_at = UTC_TIMESTAMP() WHERE group_id IS NULL AND from_user_id = ? AND to_user_id = ? AND read_at IS NULL',
                    [partnerId, me.id]
                );
            }
            res.json({ ok: true });
        } catch (err) {
            console.error('[Chat] read error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // POST /attachments — store an encrypted blob, return its id.
    router.post('/attachments', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            const { data, filename, mime_type } = req.body || {};
            if (!me || typeof data !== 'string' || !data) {
                return res.status(400).json({ error: 'data is required.' });
            }
            if (data.length > MAX_ATTACHMENT_BASE64) {
                return res.status(413).json({ error: 'Attachment too large.' });
            }
            const buffer = Buffer.from(data, 'base64');
            if (buffer.length === 0) return res.status(400).json({ error: 'Invalid base64 data.' });

            conn = await pool.getConnection();
            const info = await conn.query(`
                INSERT INTO chat_attachments (instance_url, uploader_id, data, filename, mime_type)
                VALUES (?, ?, ?, ?, ?)
            `, [me.instance_url, me.id, buffer, filename ? String(filename).slice(0, 255) : null,
                mime_type ? String(mime_type).slice(0, 128) : null]);
            res.json({ id: Number(info.insertId) });
        } catch (err) {
            console.error('[Chat] attachment upload error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    // GET /attachments/:id — the encrypted blob, base64 encoded.
    router.get('/attachments/:id', async (req, res) => {
        let conn;
        try {
            const me = await callerChatUser(req);
            const id = parseInt(req.params.id, 10);
            if (!me || !id) return res.status(400).json({ error: 'Invalid attachment id.' });
            conn = await pool.getConnection();
            const rows = await conn.query('SELECT * FROM chat_attachments WHERE id = ?', [id]);
            const attachment = rows[0];
            // Scoped per instance, like every other chat object.
            if (!attachment || attachment.instance_url !== me.instance_url) {
                return res.status(404).json({ error: 'Attachment not found.' });
            }
            res.json({
                data: Buffer.from(attachment.data).toString('base64'),
                filename: attachment.filename,
                mime_type: attachment.mime_type,
            });
        } catch (err) {
            console.error('[Chat] attachment download error:', err);
            res.status(500).json({ error: 'Database error.' });
        } finally {
            if (conn) conn.release();
        }
    });

    router.initSchema = initSchema;
    return router;
};
