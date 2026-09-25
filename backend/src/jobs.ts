import { pool, db } from './database/postgres.js';
import { dispatchReminderRows } from './notifications.js';
import { exportFiles } from './privacy.js';

/** Session advisory lock is released by PostgreSQL if a worker dies. Existing
 * per-delivery transaction leases also protect against retrying a send. */
export async function runJobs(): Promise<{ skipped: boolean }> {
  const client = await pool.connect();
  let locked = false;
  try {
    const result = await client.query('SELECT pg_try_advisory_lock($1, $2) AS locked', [190917, 1]);
    locked = result.rows[0].locked === true;
    if (!locked) return { skipped: true };
    await exportFiles().prune();
    // Keep deletion markers at least a day, beyond the lifetime of old ID tokens.
    let cursor;
    do {
      let query = db.collection('account_deletions').where('expires_at', '<=', new Date().toISOString()).orderBy('__name__').limit(100);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      for (const document of page.docs) await document.ref.delete();
      cursor = page.size === 100 ? page.docs.at(-1) : undefined;
    } while (cursor);
    if (process.env.PUSH_NOTIFICATIONS_ENABLED !== 'false') await dispatchReminderRows();
    return { skipped: false };
  } finally {
    if (locked) await client.query('SELECT pg_advisory_unlock($1, $2)', [190917, 1]).catch(() => undefined);
    client.release();
  }
}
