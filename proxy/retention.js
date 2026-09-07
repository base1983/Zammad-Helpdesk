// retention.js — delete chat messages (and their attachments) older than the
// retention window. Run from cron (see crontab). Uses the same DB credentials
// as server.js.
//
//   /opt/plesk/node/24/bin/node retention.js
//
// Retention window in days (default 90) can be overridden with CHAT_RETENTION_DAYS.

const path = require('path');
const mariadb = require('mariadb');

const RETENTION_DAYS = parseInt(process.env.CHAT_RETENTION_DAYS, 10) || 90;

(async () => {
    const cfg = require(path.join(__dirname, 'config.json')).dbConfig;
    const pool = mariadb.createPool(cfg);
    let conn;
    try {
        conn = await pool.getConnection();
        const messages = await conn.query(
            'DELETE FROM chat_messages WHERE created_at < (UTC_TIMESTAMP() - INTERVAL ? DAY)',
            [RETENTION_DAYS]
        );
        // v4: per-device body keys are meaningless once their message is gone.
        const keys = await conn.query(
            'DELETE FROM chat_message_keys WHERE message_id NOT IN (SELECT id FROM chat_messages)'
        );
        // Attachment blobs outlive their message row, so sweep the orphans too.
        // (Only past the retention window, so a blob uploaded moments before its
        // message row is written is never caught mid-send.)
        const attachments = await conn.query(`
            DELETE FROM chat_attachments
            WHERE created_at < (UTC_TIMESTAMP() - INTERVAL ? DAY)
              AND id NOT IN (SELECT attachment_id FROM chat_messages WHERE attachment_id IS NOT NULL)
        `, [RETENTION_DAYS]);
        const removed = Number(messages.affectedRows || 0);
        const blobs = Number(attachments.affectedRows || 0);
        const staleKeys = Number(keys.affectedRows || 0);
        console.log(`[${new Date().toISOString()}] chat retention: deleted ${removed} message(s), ${staleKeys} orphaned message key(s) and ${blobs} orphaned attachment(s) older than ${RETENTION_DAYS} days.`);
    } catch (err) {
        console.error(`[${new Date().toISOString()}] chat retention FAILED:`, err.message);
        process.exitCode = 1;
    } finally {
        if (conn) conn.release();
        await pool.end();
    }
})();
