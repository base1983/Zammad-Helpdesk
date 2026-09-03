const express = require('express');
const bodyParser = require('body-parser');
const apn = require('@parse/node-apn');
const fs = require('fs');
const path = require('path');
const mariadb = require('mariadb');

// --- Configuration ---
const PORT = process.env.PORT || 3000;

let config;
try {
    const configPath = path.join(__dirname, 'config.json');
    if (!fs.existsSync(configPath)) {
        console.error("Error: 'config.json' not found in the project directory.");
        process.exit(1);
    }
    const configFile = fs.readFileSync(configPath, 'utf8');
    config = JSON.parse(configFile);
} catch (error) {
    console.error("Error: Could not read or parse 'config.json'.", error);
    process.exit(1);
}

const { apnConfig, dbConfig } = config;

// --- APNs Setup ---
// A device token belongs to exactly one environment: TestFlight/App Store builds
// register PRODUCTION tokens (api.push.apple.com), Xcode-on-device builds register
// SANDBOX tokens (api.sandbox.push.apple.com). The wrong host is rejected with
// 400 BadDeviceToken. The same .p8 token-auth key works for both, so we keep a
// provider for each and, per send, try production first and fall back to sandbox
// on BadDeviceToken — one code path serves both environments.
let apnProviderProd, apnProviderSandbox;
try {
    const apnKey = fs.readFileSync(apnConfig.keyPath);
    const tokenAuth = { key: apnKey, keyId: apnConfig.keyId, teamId: apnConfig.teamId };
    apnProviderProd = new apn.Provider({ token: tokenAuth, production: true });
    apnProviderSandbox = new apn.Provider({ token: tokenAuth, production: false });
    console.log("Successfully initialized APNs Providers (production + sandbox).");
} catch (error) {
    console.error("---!! APNs Initialization Failed !! ---", error);
    process.exit(1);
}

// Send a notification, trying production first and retrying against sandbox when
// Apple reports BadDeviceToken (i.e. the token is actually a development token).
async function sendApns(notification, deviceToken) {
    let result = await apnProviderProd.send(notification, deviceToken);
    const badToken = result.failed.some(f =>
        String(f.status) === '400' && f.response && f.response.reason === 'BadDeviceToken'
    );
    if (badToken) {
        console.log('[APNs] BadDeviceToken on production — retrying via sandbox.');
        result = await apnProviderSandbox.send(notification, deviceToken);
    }
    return result;
}

// --- Database Setup ---
const pool = mariadb.createPool(dbConfig);

// --- Express App Setup ---
const app = express();
app.use(bodyParser.json());

// --- Chat helpers (shared with the chat router) ---
// Look up a registered device token by proxyUserID.
async function lookupDeviceToken(proxyUserID) {
    let conn;
    try {
        conn = await pool.getConnection();
        const rows = await conn.query("SELECT deviceToken FROM registrations WHERE proxyUserID = ?", [proxyUserID]);
        return rows.length > 0 ? rows[0].deviceToken : null;
    } catch (err) {
        console.error('[Chat] lookupDeviceToken failed:', err.message);
        return null;
    } finally {
        if (conn) conn.release();
    }
}

// Send a chat push via the existing APNs provider.
// message = { title, body, bodyLocKey, bodyLocArgs, payload }.
// When bodyLocKey is set, the body is sent as an APNS loc-key so the app
// localizes it on-device (per device language) via its Localizable.strings;
// `body` is only a fallback for clients missing the key. payload holds custom
// keys (chat_from_user_id and, when relevant, ticketID for DeepLinkManager).
async function sendChatPush(deviceToken, message) {
    const notification = new apn.Notification();
    notification.expiry = Math.floor(Date.now() / 1000) + 3600;
    notification.badge = 1;
    notification.sound = 'ping.aiff';
    notification.topic = apnConfig.bundleId;
    notification.payload = message.payload || {};
    if (message.title) notification.title = message.title;
    if (message.bodyLocKey) {
        notification.locKey = message.bodyLocKey;
        if (Array.isArray(message.bodyLocArgs) && message.bodyLocArgs.length) {
            notification.locArgs = message.bodyLocArgs;
        }
    } else {
        notification.body = message.body;
    }
    const result = await sendApns(notification, deviceToken);
    if (result.failed.length > 0) {
        console.error('[Chat][APNs] Failed deliveries:', JSON.stringify(result.failed));
    }
    return result;
}

// --- Chat router (engineer-to-engineer chat, see PROXY_CHAT_API.md) ---
const createChatRouter = require('./chat');
const chatRouter = createChatRouter({
    pool,
    sendPush: sendChatPush,
    lookupDeviceToken,
});
app.use('/api/chat', chatRouter);

// --- API Endpoints ---
app.post('/api/register', async (req, res) => {
    const { deviceToken, proxyUserID, zammadURL, zammadToken } = req.body;
    if (!deviceToken || !proxyUserID) {
        return res.status(400).json({ error: 'deviceToken and proxyUserID are required.' });
    }
    const sql = `
        INSERT INTO registrations (proxyUserID, deviceToken, zammadURL, zammadToken)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE deviceToken = ?, zammadURL = ?, zammadToken = ?;
    `;
    let conn;
    try {
        conn = await pool.getConnection();
        await conn.query(sql, [proxyUserID, deviceToken, zammadURL, zammadToken, deviceToken, zammadURL, zammadToken]);
        res.status(200).json({ message: 'Device registered successfully.' });
    } catch (err) {
        res.status(500).json({ error: 'Database error during registration.' });
    } finally {
        if (conn) conn.release();
    }
});

app.post('/api/unregister', async (req, res) => {
    const { proxyUserID } = req.body;
    if (!proxyUserID) {
        return res.status(400).json({ error: 'proxyUserID is required.' });
    }
    let conn;
    try {
        conn = await pool.getConnection();
        await conn.query("DELETE FROM registrations WHERE proxyUserID = ?", [proxyUserID]);
        res.status(200).json({ message: 'Device unregistered successfully.' });
    } catch (err) {
        res.status(500).json({ error: 'Database error during unregistration.' });
    } finally {
        if (conn) conn.release();
    }
});

// Webhook endpoint
app.post('/api/webhook/:proxyUserID', async (req, res) => {
    const { proxyUserID } = req.params;
    // We proberen data te pakken, maar voegen logging toe om te zien WAT Zammad stuurt
    const bodyData = req.body;
    console.log(`[Webhook] Raw Body received:`, JSON.stringify(bodyData).substring(0, 200) + "...");

    // 1. Probeer ticket/article te vinden (Standaard Zammad Payload)
    let ticket = bodyData.ticket;
    let article = bodyData.article;

    // 2. Fallback: Als het data in een wrapper zit (soms bij custom hooks)
    if (!ticket && bodyData.data && bodyData.data.ticket) {
        ticket = bodyData.data.ticket;
        article = bodyData.data.article;
    }

    console.log(`[Webhook] Processing for user: ${proxyUserID}`);

    // Database lookup voor deviceToken
    let conn;
    let registration;
    try {
        conn = await pool.getConnection();
        const rows = await conn.query("SELECT deviceToken FROM registrations WHERE proxyUserID = ?", [proxyUserID]);
        if (rows.length > 0) {
            registration = rows[0];
        }
    } catch (err) {
        console.error("[Webhook] Database lookup failed:", err);
        return res.status(500).json({ error: 'Database error.' });
    } finally {
        if (conn) conn.release();
    }
    
    if (!registration) {
        console.error(`[Webhook] No registration found for user: ${proxyUserID}`);
        return res.status(404).json({ error: 'User not registered.' });
    }

    // --- Notification Content Logic ---
    // Standaard waarden
    let title = 'Helpdesk Update';
    let body = 'Er is een update op een ticket.';
    let ticketId = null;
    let ticketNumber = null;

    // Check of we ticket data hebben
    if (ticket) {
        ticketId = ticket.id;
        ticketNumber = ticket.number;
        
        // CRUCIAAL VOOR JE APP: Het formaat "Ticket #12345"
        title = `Ticket #${ticket.number}: ${ticket.title || 'Update'}`;
    }

    if (article && article.body) {
        // Strip HTML tags
        body = article.body.replace(/<[^>]*>?/gm, '').trim();
        // Zorg dat de body niet te lang is voor een pushbericht
        if (body.length > 150) body = body.substring(0, 150) + '...';
    } else if (ticket && ticket.state) {
        body = `Status gewijzigd naar: ${ticket.state}`;
    }

    const notification = new apn.Notification();
    notification.expiry = Math.floor(Date.now() / 1000) + 3600;
    notification.badge = 1;
    notification.sound = 'ping.aiff';
    
    notification.alert = { title, body };

    // --- FIX: Payload Keys ---
    // We sturen nu zowel 'ticket_id' als 'id' mee.
    // Dit zorgt ervoor dat de Regex in je Swift app sowieso raak schiet.
    notification.payload = { 
        'ticket_id': ticketId, // Deze zoekt je Swift app
        'id': ticketId,
        'ticket_number': ticketNumber
    };
    
    notification.topic = apnConfig.bundleId;

    console.log(`[APNs] Sending to token: ${registration.deviceToken.substring(0, 10)}...`);
    console.log(`[APNs] Content: Title="${title}", PayloadID=${ticketId}`);

    try {
        const result = await sendApns(notification, registration.deviceToken);

        // Check op fouten van Apple (bijv. BadDeviceToken)
        if (result.failed.length > 0) {
            console.error('[APNs] Failed deliveries:', JSON.stringify(result.failed, null, 2));
            // Optioneel: Verwijder token uit DB als error "BadDeviceToken" is
        } else {
            console.log('[APNs] Sent successfully.');
        }
        
        res.status(200).json({ message: 'Webhook processed.' });
    } catch (err) {
        console.error('[APNs] CRITICAL Error:', err);
        res.status(500).json({ error: 'Failed to send notification.' });
    }
});
// --- Server Start ---
async function startServer() {
    let conn;
    try {
        conn = await pool.getConnection();
        console.log("Successfully connected to MariaDB.");
        await conn.query(`
            CREATE TABLE IF NOT EXISTS registrations (
                proxyUserID VARCHAR(255) NOT NULL PRIMARY KEY,
                deviceToken TEXT NOT NULL,
                zammadURL VARCHAR(255),
                zammadToken TEXT,
                createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        `);
        console.log("Database table 'registrations' is ready.");
    } catch (err) {
        console.error("Database setup failed:", err);
        process.exit(1);
    } finally {
        if (conn) conn.release();
    }

    // Ensure chat tables exist too.
    try {
        await chatRouter.initSchema();
    } catch (err) {
        console.error("Chat table setup failed:", err);
        process.exit(1);
    }

    app.listen(PORT, () => {
        console.log(`Proxy server listening on port ${PORT}`);
    }).on('error', (err) => {
        if (err.code === 'EADDRINUSE') {
            console.error(`Error: Port ${PORT} is already in use.`);
        } else {
            console.error('Server startup error:', err);
        }
        process.exit(1);
    });
}

startServer();

// --- Graceful Shutdown ---
process.on('SIGINT', () => {
    console.log('Shutting down...');
    apnProviderProd.shutdown();
    apnProviderSandbox.shutdown();
    pool.end();
    process.exit();
});

