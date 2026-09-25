import { writeFile } from 'node:fs/promises';
import { validateConfig } from './shared/config.js';
import { checkDatabase, closeDatabase } from './database/postgres.js';
import { startJobLoop } from './shared/job-loop.js';
import { runJobs } from './jobs.js';

async function main() {
  validateConfig();
  await checkDatabase();
  const loop = startJobLoop({
    intervalMs: 5 * 60 * 1000,
    run: async () => {
      await runJobs();
      await writeFile('/tmp/leanguard-worker-heartbeat', String(Date.now()), { mode: 0o600 });
    },
    onFailure: () => console.error(JSON.stringify({ event: 'worker_cycle_failed' })),
  });
  let shuttingDown = false;
  const shutdown = async () => {
    if (shuttingDown) return;
    shuttingDown = true;
    const deadline = setTimeout(() => process.exit(1), 30000).unref();
    await loop.stop();
    await closeDatabase();
    clearTimeout(deadline);
  };
  process.once('SIGTERM', () => { void shutdown(); });
  process.once('SIGINT', () => { void shutdown(); });
  console.log(JSON.stringify({ event: 'worker_started' }));
}
main().catch(() => {
  console.error(JSON.stringify({ event: 'worker_start_failed', message: 'Check server configuration and PostgreSQL availability.' }));
  process.exitCode = 1;
  void closeDatabase();
});
