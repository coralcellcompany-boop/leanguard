import express, { type Request, type Response, type NextFunction, type RequestHandler, type Router } from 'express';
import { endpoint, HttpError } from './shared/platform.js';
import { config } from './shared/config.js';
import { checkDatabase } from './database/postgres.js';
import { createRecordRouter } from './crud.js';
import { RecordValidationError } from './validation.js';
import { coachHandler, approveHandler } from './coach.js';
import { syncHandler, webhookHandler } from './subscriptions.js';
import { consentHandler, saveReminderHandler, deleteReminderHandler, healthHandler } from './records.js';
import { exportHandler, deleteHandler, downloadHandler } from './privacy.js';

type AsyncHandler = (req: Request, res: Response) => Promise<void>;
/** Counts real operations until their promises settle, including disconnected
 * callers, so abandoned exports cannot bypass process memory limits. */
export function limitConcurrent(handler: AsyncHandler, maximum: number): RequestHandler {
  let active = 0;
  return (req, res, next) => {
    if (active >= maximum) {
      res.set('Retry-After', '5').status(503).json({ error: 'busy', message: 'The service is busy. Try again shortly.' });
      return;
    }
    active++;
    void handler(req, res).catch(next).finally(() => { active--; });
  };
}

/** Per-process ingress protection complements transactional per-user AI quotas.
 * No health values, tokens, URLs, or user identities are recorded. */
export function ingressLimit(maximum = 300, windowMs = 60000): RequestHandler {
  const entries = new Map<string, { count: number; until: number }>();
  return (req, res, next) => {
    const now = Date.now(), key = req.ip ?? req.socket.remoteAddress ?? 'unknown';
    let entry = entries.get(key);
    if (!entry || entry.until <= now) {
      if (entries.size >= 10000) {
        for (const [address, record] of entries) if (record.until <= now) entries.delete(address);
        if (entries.size >= 10000) entries.delete(entries.keys().next().value!);
      }
      entry = { count: 0, until: now + windowMs }; entries.set(key, entry);
    }
    if (++entry.count > maximum) {
      res.set('Retry-After', String(Math.max(1, Math.ceil((entry.until - now) / 1000))));
      res.status(429).json({ error: 'rate_limited', message: 'Too many requests. Please try again shortly.' });
      return;
    }
    next();
  };
}

export type AppDependencies = {
  records?: Router;
  ready?: () => Promise<unknown>;
  actions?: Record<string, AsyncHandler>;
  download?: AsyncHandler;
  origins?: string[];
};

export function createApp(dependencies: AppDependencies = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.set('json escape', true);
  // Enable only behind the private Caddy hop. The API port must not be public.
  app.set('trust proxy', process.env.TRUST_PROXY_HOPS === '1' ? 1 : false);
  app.use((req, res, next) => {
    res.set({ 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'" });
    const origin = req.get('Origin');
    const allowed = dependencies.origins ?? config.allowedOrigins;
    if (origin && !allowed.includes(origin)) {
      res.status(403).json({ error: 'origin_not_allowed', message: 'This browser origin is not enabled.' }); return;
    }
    if (origin) {
      res.set('Access-Control-Allow-Origin', origin).vary('Origin');
      res.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    }
    if (req.method === 'OPTIONS') { res.status(204).end(); return; }
    next();
  });
  app.get('/health/live', (_req, res) => { res.json({ status: 'ok' }); });
  app.get('/health/ready', limitConcurrent(async (_req, res) => {
    try { await (dependencies.ready ?? checkDatabase)(); res.json({ status: 'ready' }); }
    catch { res.status(503).json({ status: 'unavailable' }); }
  }, 4));
  app.use('/v1', ingressLimit());
  app.use(express.json({ limit: 32000, strict: true, inflate: false }));
  app.use('/v1', dependencies.records ?? createRecordRouter());
  const actions = dependencies.actions ?? {
    coach: endpoint(coachHandler),
    approvePlan: endpoint(approveHandler),
    syncEntitlement: endpoint(syncHandler),
    recordConsent: endpoint(consentHandler),
    saveReminder: endpoint(saveReminderHandler),
    deleteReminder: endpoint(deleteReminderHandler),
    syncHealthActivity: endpoint(healthHandler),
    dataExport: endpoint(exportHandler),
    deleteAccount: endpoint(deleteHandler, { allowDeleting: true }),
    revenuecatWebhook: endpoint(webhookHandler, { authenticated: false }),
  };
  for (const [name, action] of Object.entries(actions)) {
    app.post(`/v1/${name}`, limitConcurrent(action, name === 'dataExport' ? 1 : 40));
    app.all(`/v1/${name}`, (_req, res) => { res.set('Allow', 'POST').status(405).json({ error: 'method_not_allowed' }); });
  }
  app.get('/v1/exports/:uid/:file', limitConcurrent(dependencies.download ?? downloadHandler, 8));
  app.use((_req, res) => { res.status(404).json({ error: 'not_found', message: 'This endpoint is unavailable.' }); });
  app.use((error: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (res.headersSent) { res.destroy(); return; }
    if (error instanceof HttpError || error instanceof RecordValidationError) {
      res.status(error.status).json({ error: error.code, message: error.message }); return;
    }
    const details = error as { type?: string; code?: string };
    if (details?.type === 'entity.too.large') { res.status(413).json({ error: 'body_too_large', message: 'The request must be smaller than 32 KB.' }); return; }
    if (['entity.parse.failed', 'encoding.unsupported', 'charset.unsupported'].includes(details?.type ?? '')) {
      res.status(400).json({ error: 'invalid_json', message: 'Send an uncompressed JSON object.' }); return;
    }
    if (details?.code === '42501') { res.status(403).json({ error: 'forbidden', message: 'This record cannot be changed by this account.' }); return; }
    if (['23503', '23514'].includes(details?.code ?? '')) { res.status(400).json({ error: 'invalid_record', message: 'Check the record and its related records.' }); return; }
    if (details?.code === '23505') { res.status(409).json({ error: 'conflict', message: 'Refresh your records and try again.' }); return; }
    console.error(JSON.stringify({ event: 'request_failed', category: 'unexpected' }));
    res.status(503).json({ error: 'temporarily_unavailable', message: 'The service is temporarily unavailable. Your saved data remains available.' });
  });
  return app;
}
