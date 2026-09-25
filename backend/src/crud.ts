import { createHash } from 'node:crypto';
import { Router, type Request, type Response, type NextFunction } from 'express';
import { withUserDb, type Database } from './database/postgres.js';
import { body, hasPro, HttpError, identify, userTransaction, rows, type Identity } from './shared/platform.js';
import { pagination, readableTables, safeId, validateClientWrite, assertRecord, type RecordData } from './validation.js';

type OwnerDatabase = <T>(uid: string, operation: (database: Database) => Promise<T>) => Promise<T>;
type Dependencies = { identify: (req: Request) => Promise<Identity>; withUserDb: OwnerDatabase; userTransaction: typeof userTransaction };
const handle = (fn: (req: Request, res: Response) => Promise<void>) => (req: Request, res: Response, next: NextFunction) => { void fn(req, res).catch(next); };
const parameter = (req: Request, key: string) => {
  const value = req.params[key];
  assertRecord(typeof value === 'string' && safeId(value), 'Invalid record path.');
  return value;
};
const tableName = (req: Request) => {
  const table = parameter(req, 'table');
  if (!readableTables.has(table)) throw new HttpError(404, 'not_found', 'This record collection is unavailable.');
  return table;
};

/** Every operation runs under leanguard_user with app.uid set transactionally.
 * Row ownership and protected-table writes remain denied by PostgreSQL RLS. */
export function createRecordRouter(dependencies: Partial<Dependencies> = {}): Router {
  const deps: Dependencies = { identify, withUserDb, userTransaction, ...dependencies };
  const router = Router();
  router.get('/records/:table', handle(async (req, res) => {
    const { uid } = await deps.identify(req);
    const table = tableName(req), page = pagination(req.query);
    const records = await deps.withUserDb(uid, async database => {
      // The adapter adds owner/id tie breakers to the requested created_at order.
      const result = await database.collection('users').doc(uid).collection(table)
        .orderBy('created_at').offset(page.offset).limit(page.limit).get();
      return result.docs.map(document => document.data());
    });
    res.json({ records });
  }));
  router.put('/records/:table/:id', handle(async (req, res) => {
    const { uid } = await deps.identify(req);
    const table = tableName(req), id = parameter(req, 'id'), input = body(req);
    if (input.user_id !== uid) throw new HttpError(403, 'forbidden', 'You can only save your own records.');
    const result = await deps.withUserDb(uid, database => database.runTransaction(async tx => {
      const collection = database.collection('users').doc(uid);
      const ref = collection.collection(table).doc(id);
      const current = (await tx.get(ref)).data();
      const entitlement = (await tx.get(collection.collection('subscription_entitlements').doc('pro'))).data();
      // Natural-key upserts from another device preserve the existing row UUID
      // and creation time, matching the mobile offline reconciliation contract.
      const candidate: RecordData = { ...current, ...input, ...(current ? { id: current.id, created_at: current.created_at } : {}) };
      const validated = await validateClientWrite(table, id, candidate, {
        uid, pro: hasPro(entitlement), existing: current,
        parentExists: async (parentTable, parentId) => (await tx.get(collection.collection(parentTable).doc(parentId))).exists,
        // SERIALIZABLE predicate read prevents two devices from racing two
        // first starter plans into this owner's account.
        hasExistingPlan: async () => !(await tx.get(collection.collection('strength_plans').limit(1))).empty,
      });
      tx.set(ref, validated);
      return validated;
    }));
    res.json(result);
  }));
  router.put('/device-tokens', handle(async (req, res) => {
    const { uid } = await deps.identify(req), input = body(req);
    assertRecord(Object.keys(input).every(key => ['token', 'platform'].includes(key)));
    assertRecord(typeof input.token === 'string' && input.token.length >= 20 && input.token.length <= 4096 && ['ios', 'android'].includes(String(input.platform)));
    const id = createHash('sha256').update(input.token).digest('hex');
    const saved = await deps.userTransaction(uid, async tx => {
      const ref = rows(uid, 'device_tokens').doc(id);
      const existing = (await tx.get(ref)).data();
      const row = { id, user_id: uid, created_at: existing?.created_at ?? new Date().toISOString(), updated_at: new Date().toISOString(), token: input.token, platform: input.platform };
      tx.set(ref, row); return row;
    });
    res.json(saved);
  }));
  router.delete('/device-tokens/:id', handle(async (req, res) => {
    const { uid } = await deps.identify(req), id = parameter(req, 'id');
    assertRecord(/^[a-f0-9]{64}$/.test(id));
    await deps.userTransaction(uid, async tx => { tx.delete(rows(uid, 'device_tokens').doc(id)); });
    res.json({ deleted: true });
  }));
  return router;
}
