// fcm.js — Firebase Cloud Messaging (HTTP v1) sender for Android devices.
//
// Dependency-free on purpose: the proxy deploy is a file copy, so this uses
// only Node's own `crypto` and global `fetch` (Node 18+) instead of pulling in
// firebase-admin. It signs a service-account JWT, exchanges it for an OAuth
// access token (cached until shortly before it expires) and posts messages to
// the FCM v1 endpoint.
//
// Android registrations are stored in the same `registrations.deviceToken`
// column as APNs tokens, prefixed with "fcm:". That keeps chat.js and the
// schema untouched: server.js looks at the prefix and routes to APNs or here.
//
// Messages are sent as *data* messages (no `notification` block): the Android
// app builds the notification itself, so it can localise chat text on the
// device and attach the same routing keys iOS reads (ticketID,
// chat_from_user_id, chat_group_id) in every app state.

const crypto = require('crypto');
const fs = require('fs');

const FCM_PREFIX = 'fcm:';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

function isFcmToken(deviceToken) {
    return typeof deviceToken === 'string' && deviceToken.startsWith(FCM_PREFIX);
}

const b64url = (input) => Buffer.from(input).toString('base64url');

// `fcmConfig` is config.json's optional "fcm" block:
//   { "serviceAccountPath": "/path/to/firebase-service-account.json" }
// Returns null when it is absent, so the proxy keeps running for iOS without it.
function createFcmSender(fcmConfig, { fetchImpl = fetch, now = () => Date.now() } = {}) {
    if (!fcmConfig || !fcmConfig.serviceAccountPath) return null;

    const account = JSON.parse(fs.readFileSync(fcmConfig.serviceAccountPath, 'utf8'));
    const { client_email: clientEmail, private_key: privateKey, project_id: projectId } = account;
    const tokenUri = account.token_uri || 'https://oauth2.googleapis.com/token';
    if (!clientEmail || !privateKey || !projectId) {
        throw new Error('FCM service account file lacks client_email, private_key or project_id.');
    }

    let cached = null; // { accessToken, expiresAt }

    async function accessToken() {
        if (cached && cached.expiresAt - 60_000 > now()) return cached.accessToken;
        const iat = Math.floor(now() / 1000);
        const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
        const claims = b64url(JSON.stringify({
            iss: clientEmail, scope: SCOPE, aud: tokenUri, iat, exp: iat + 3600,
        }));
        const signature = crypto.createSign('RSA-SHA256').update(`${header}.${claims}`).sign(privateKey, 'base64url');
        const resp = await fetchImpl(tokenUri, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                assertion: `${header}.${claims}.${signature}`,
            }).toString(),
        });
        if (!resp.ok) throw new Error(`FCM auth failed: HTTP ${resp.status}`);
        const json = await resp.json();
        cached = { accessToken: json.access_token, expiresAt: now() + (json.expires_in || 3600) * 1000 };
        return cached.accessToken;
    }

    // deviceToken may carry the "fcm:" prefix. `data` values are stringified
    // (FCM data payloads are string→string) and null/undefined keys dropped.
    // Resolves to { ok, status, unregistered, error }; never rejects on an FCM
    // answer, only on a programming error.
    async function send(deviceToken, data) {
        const token = isFcmToken(deviceToken) ? deviceToken.slice(FCM_PREFIX.length) : deviceToken;
        const stringData = {};
        for (const [key, value] of Object.entries(data || {})) {
            if (value !== null && value !== undefined) stringData[key] = String(value);
        }
        try {
            const resp = await fetchImpl(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
                method: 'POST',
                headers: {
                    Authorization: `Bearer ${await accessToken()}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    message: { token, data: stringData, android: { priority: 'HIGH', ttl: '3600s' } },
                }),
            });
            if (resp.ok) return { ok: true, status: resp.status };
            const text = await resp.text();
            // 404 UNREGISTERED: the app was uninstalled or the token rotated.
            const unregistered = resp.status === 404 || /UNREGISTERED/.test(text);
            if (resp.status === 401) cached = null;
            return { ok: false, status: resp.status, unregistered, error: text.slice(0, 300) };
        } catch (err) {
            return { ok: false, status: 0, unregistered: false, error: err.message };
        }
    }

    return { send, projectId };
}

module.exports = { createFcmSender, isFcmToken, FCM_PREFIX };
