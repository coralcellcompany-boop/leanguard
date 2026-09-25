import { createServer } from 'node:http';
import { createApp } from './app.js';
import { config, validateConfig } from './shared/config.js';
import { checkDatabase, closeDatabase } from './database/postgres.js';

async function main() {
  validateConfig();
  await checkDatabase();
  const server = createServer({ maxHeaderSize: 16384 }, createApp());
  server.requestTimeout = 35000;
  server.headersTimeout = 10000;
  server.keepAliveTimeout = 5000;
  server.maxRequestsPerSocket = 1000;
  server.setTimeout(330000, socket => socket.destroy());
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(config.port, process.env.HOST ?? '127.0.0.1', resolve);
  });
  console.log(JSON.stringify({ event: 'api_started' }));
  let stopping = false;
  const stop = () => {
    if (stopping) return;
    stopping = true;
    const deadline = setTimeout(() => { server.closeAllConnections(); process.exit(1); }, 30000).unref();
    server.close(() => {
      void closeDatabase().finally(() => { clearTimeout(deadline); process.exitCode = 0; });
    });
    server.closeIdleConnections();
  };
  process.once('SIGTERM', stop);
  process.once('SIGINT', stop);
}
main().catch(() => {
  console.error(JSON.stringify({ event: 'api_start_failed', message: 'Check backend configuration and PostgreSQL availability.' }));
  process.exitCode = 1;
  void closeDatabase();
});
