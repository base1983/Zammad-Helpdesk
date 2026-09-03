// retention.js — delete chat messages older than the retention window.
// Run from cron (see crontab). Uses the same DB credentials as server.js.
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
        const result = await conn.query(
            'DELETE FROM chat_messages WHERE created_at < (UTC_TIMESTAMP() - INTERVAL ? DAY)',
            [RETENTION_DAYS]
        );
        const removed = Number(result.affectedRows || 0);
        console.log(`[${new Date().toISOString()}] chat retention: deleted ${removed} message(s) older than ${RETENTION_DAYS} days.`);
    } catch (err) {
        console.error(`[${new Date().toISOString()}] chat retention FAILED:`, err.message);
        process.exitCode = 1;
    } finally {
        if (conn) conn.release();
        await pool.end();
    }
})();
