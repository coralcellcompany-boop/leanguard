import pg, { type PoolClient } from "pg";
import { config } from "../shared/config.js";
import { HttpError } from "../shared/errors.js";
export type DocumentData = Record<string, any>;
export const pool = new pg.Pool({ connectionString: config.databaseUrl || undefined, max: config.databasePoolSize, connectionTimeoutMillis: 5000, idleTimeoutMillis: 30000, application_name: "leanguard-api" });
pool.on("error", () => console.error(JSON.stringify({event:"database_connection_error"})));
const safePart = (value: string) => { if (!value || value.length > 256 || value.includes("/") || value.includes("\0")) throw new Error("Invalid record key"); return value; };
const field = (value: string) => { if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(value)) throw new Error("Invalid field"); return value; };
const clone = <T>(value:T):T => structuredClone(value);
export async function sqlTransaction<T>(role: "leanguard_service" | "leanguard_user", uid: string | undefined, operation: (client: PoolClient) => Promise<T>): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const client = await pool.connect();
    try {
      await client.query("BEGIN ISOLATION LEVEL SERIALIZABLE");
      await client.query(`SET LOCAL ROLE ${role}`);
      await client.query("SET LOCAL statement_timeout = '15s'");
      await client.query("SET LOCAL lock_timeout = '10s'");
      if (uid !== undefined) await client.query("SELECT set_config('app.uid',$1,true)", [uid]);
      const result = await operation(client);
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      if (["40001", "40P01"].includes((error as {code?:string}).code ?? "") && attempt < 10) {
        await new Promise(resolve => setTimeout(resolve, Math.min(250, 5 * 2 ** attempt) + Math.random() * 20));
      } else throw error;
    } finally { client.release(); }
  }
}
export class DocumentSnapshot {
  constructor(public readonly ref: DocumentReference, private readonly value?: DocumentData) {}
  get id() { return this.ref.id; }
  get exists() { return this.value !== undefined; }
  data(): DocumentData | undefined { return this.value === undefined ? undefined : clone(this.value); }
}
export class QueryDocumentSnapshot extends DocumentSnapshot {
  override data(): DocumentData { return super.data()!; }
}
export class QuerySnapshot {
  constructor(public readonly docs: QueryDocumentSnapshot[]) {}
  get size() { return this.docs.length; }
  get empty() { return this.size === 0; }
}
type Filter = {key:string; operator:string; value:unknown};
export class Query {
  constructor(public readonly database: Database, public readonly collectionName: string, public readonly owner: string | null, protected filters: Filter[] = [], protected ordering: {key:string; direction:"asc"|"desc"} = {key:"__name__",direction:"asc"}, protected take = 10000, protected skip = 0, protected cursor?: DocumentSnapshot, protected projection?: string[]) {}
  protected copy() { return new Query(this.database, this.collectionName, this.owner, [...this.filters], {...this.ordering}, this.take, this.skip, this.cursor, this.projection); }
  where(key:string, operator:string, value:unknown) { if (!["==",">=",">","<=","<","!=","in","array-contains"].includes(operator)) throw new Error("Unsupported query operator"); field(key); const q=this.copy(); q.filters.push({key,operator,value}); return q; }
  orderBy(key:string,direction:"asc"|"desc"="asc") { field(key); if (!["asc","desc"].includes(direction)) throw new Error("Invalid order"); const q=this.copy(); q.ordering={key,direction}; return q; }
  limit(count:number) { if (!Number.isInteger(count)||count<1||count>10000) throw new Error("Invalid query limit"); const q=this.copy(); q.take=count; return q; }
  offset(count:number) { if (!Number.isInteger(count)||count<0||count>1000000) throw new Error("Invalid offset"); const q=this.copy(); q.skip=count; return q; }
  startAfter(snapshot:DocumentSnapshot) { if (snapshot.ref.table !== this.collectionName || (this.owner !== null && snapshot.ref.owner !== this.owner)) throw new Error("Invalid query cursor"); const q=this.copy(); q.cursor=snapshot; return q; }
  select(...fields:string[]) { fields.forEach(field); const q=this.copy(); q.projection=fields; return q; }
  async get():Promise<QuerySnapshot> { return this.database.execute(async client => {
    const params:unknown[]=[this.collectionName]; const clauses=["collection=$1"];
    const bind=(value:unknown)=>{params.push(value);return `$${params.length}`;};
    if(this.owner!==null) clauses.push(`owner=${bind(this.owner)}`);
    for(const f of this.filters) {
      const key=`${bind(f.key)}::text`;
      if(f.operator==="in") { if(!Array.isArray(f.value)||f.value.length>100) throw new Error("Invalid in filter"); clauses.push(`data->${key}=ANY(${bind(f.value.map(x=>JSON.stringify(x)))}::jsonb[])`); }
      else if(f.operator==="array-contains") clauses.push(`data->${key} @> ${bind(JSON.stringify([f.value]))}::jsonb`);
      else clauses.push(`data->${key} ${f.operator==="=="?"=":f.operator==="!="?"<>":f.operator} ${bind(JSON.stringify(f.value))}::jsonb`);
    }
    const direction=this.ordering.direction.toUpperCase();
    const nameOrder=this.ordering.key==="__name__";
    const expr=nameOrder?"owner, id":`data->${bind(this.ordering.key)}::text`;
    if(this.cursor) {
      const comparison=this.ordering.direction==="asc"?">":"<";
      if(nameOrder) clauses.push(`(owner,id) ${comparison} (${bind(this.cursor.ref.owner)},${bind(this.cursor.id)})`);
      else clauses.push(`(${expr},owner,id) ${comparison} (${bind(JSON.stringify(this.cursor.data()?.[this.ordering.key]))}::jsonb,${bind(this.cursor.ref.owner)},${bind(this.cursor.id)})`);
    }
    const order=nameOrder?`owner ${direction},id ${direction}`:`${expr} ${direction},owner ${direction},id ${direction}`;
    const result=await client.query(`SELECT owner,id,data FROM app_records WHERE ${clauses.join(" AND ")} ORDER BY ${order} LIMIT ${bind(this.take)} OFFSET ${bind(this.skip)}`,params);
    return new QuerySnapshot(result.rows.map(row=>{
      const data=this.projection?Object.fromEntries(this.projection.filter(key=>key in row.data).map(key=>[key,row.data[key]])):row.data;
      return new QueryDocumentSnapshot(new DocumentReference(this.database,this.collectionName,row.owner,row.id),data);
    }));
  }); }
}
export class CollectionReference extends Query {
  get parent(): DocumentReference | null { return this.owner ? new DocumentReference(this.database,"users","",this.owner) : null; }
  doc(id:string=crypto.randomUUID()) { return new DocumentReference(this.database,this.collectionName,this.owner??"",safePart(id)); }
}
export class DocumentReference {
  constructor(public readonly database:Database, public readonly table:string, public readonly owner:string, public readonly id:string) { safePart(table);safePart(id); }
  get path() { return this.owner?`users/${this.owner}/${this.table}/${this.id}`:`${this.table}/${this.id}`; }
  get parent() { return new CollectionReference(this.database,this.table,this.owner); }
  collection(table:string) { if(this.table!=="users"||this.owner!=="") throw new Error("Only per-user collections are supported"); return new CollectionReference(this.database,safePart(table),this.id); }
  async get():Promise<DocumentSnapshot> { return this.database.execute(async client=>{const result=await client.query("SELECT data FROM app_records WHERE collection=$1 AND owner=$2 AND id=$3",[this.table,this.owner,this.id]);return new DocumentSnapshot(this,result.rows[0]?.data);}); }
  async set(data:DocumentData, options:{merge?:boolean}={}) { return this.database.write(this,"set",data,options.merge??false); }
  async create(data:DocumentData) { return this.database.write(this,"create",data); }
  async update(data:DocumentData) { return this.database.write(this,"update",data); }
  async delete() { return this.database.write(this,"delete"); }
}
export class Transaction {
  private writes:Array<()=>Promise<unknown>>=[];
  constructor(public readonly database:Database) {}
  get(ref:DocumentReference):Promise<DocumentSnapshot>;
  get(ref:Query):Promise<QuerySnapshot>;
  get(ref:DocumentReference|Query):Promise<DocumentSnapshot|QuerySnapshot> { return ref instanceof DocumentReference?new DocumentReference(this.database,ref.table,ref.owner,ref.id).get():this.database.bindQuery(ref).get(); }
  set(ref:DocumentReference,data:DocumentData,options:{merge?:boolean}={}) { this.writes.push(()=>this.database.write(ref,"set",data,options.merge));return this; }
  create(ref:DocumentReference,data:DocumentData) { this.writes.push(()=>this.database.write(ref,"create",data));return this; }
  update(ref:DocumentReference,data:DocumentData) { this.writes.push(()=>this.database.write(ref,"update",data));return this; }
  delete(ref:DocumentReference) { this.writes.push(()=>this.database.write(ref,"delete"));return this; }
  async flush() { for(const write of this.writes) await write(); this.writes=[]; }
}
export class Database {
  constructor(private readonly client?:PoolClient, public readonly scopedUid?:string) {}
  collection(table:string) { return new CollectionReference(this,safePart(table),""); }
  collectionGroup(table:string) { return new Query(this,safePart(table),null); }
  bindQuery(query:Query):Query { return Object.assign(Object.create(Object.getPrototypeOf(query)),query,{database:this}); }
  execute<T>(fn:(client:PoolClient)=>Promise<T>):Promise<T> { return this.client?fn(this.client):sqlTransaction("leanguard_service",undefined,fn); }
  async write(ref:DocumentReference,mode:"set"|"create"|"update"|"delete",data?:DocumentData,merge=false):Promise<void> { await this.execute(async client=>{
    if (this.scopedUid!==undefined && ref.owner!==this.scopedUid) throw new Error("Record owner mismatch");
    const key=[ref.table,ref.owner,ref.id];
    if(mode==="delete") { await client.query("DELETE FROM app_records WHERE collection=$1 AND owner=$2 AND id=$3",key); return; }
    const serialized=JSON.stringify(data);
    if(!data||typeof data!=="object"||Array.isArray(data)||Buffer.byteLength(serialized)>524288) throw new Error("Invalid record data");
    if(ref.owner&&data.user_id!==undefined&&data.user_id!==ref.owner) throw new Error("Record owner mismatch");
    if(mode==="update") { const result=await client.query("UPDATE app_records SET data=data||$4::jsonb,updated_at=clock_timestamp() WHERE collection=$1 AND owner=$2 AND id=$3",[...key,serialized]); if(result.rowCount===0) throw Object.assign(new Error("Record not found"),{code:"not_found"}); }
    else if(mode==="set" && this.scopedUid!==undefined) {
      // Avoid INSERT triggers on an existing row: expired subscribers may edit
      // their existing measurement without being treated as creating a Pro one.
      const existing=await client.query("SELECT 1 FROM app_records WHERE collection=$1 AND owner=$2 AND id=$3",key);
      if(existing.rowCount) await client.query(`UPDATE app_records SET data=${merge?"data||$4::jsonb":"$4::jsonb"},updated_at=clock_timestamp() WHERE collection=$1 AND owner=$2 AND id=$3`,[...key,serialized]);
      else await client.query("INSERT INTO app_records(collection,owner,id,data) VALUES($1,$2,$3,$4::jsonb)",[...key,serialized]);
    } else { const conflict=mode==="create"?"":` ON CONFLICT(collection,owner,id) DO UPDATE SET data=${merge?"app_records.data||EXCLUDED.data":"EXCLUDED.data"},updated_at=clock_timestamp()`; await client.query(`INSERT INTO app_records(collection,owner,id,data) VALUES($1,$2,$3,$4::jsonb)${conflict}`,[...key,serialized]); }
  }); }
  async runTransaction<T>(operation:(tx:Transaction)=>Promise<T>):Promise<T> { return this.execute(async client=>{const tx=new Transaction(new Database(client,this.scopedUid)); const result=await operation(tx);await tx.flush();return result;}); }
  async recursiveDelete(ref:DocumentReference) { if(ref.table!=="users"||ref.owner) throw new Error("Only user deletion is supported"); await this.execute(client=>client.query("DELETE FROM app_records WHERE owner=$1",[ref.id])); }
  async terminate() { await closeDatabase(); }
}
export const db=new Database();
export async function withUserDb<T>(uid:string,fn:(database:Database)=>Promise<T>):Promise<T> { safePart(uid);return sqlTransaction("leanguard_user",uid,client=>fn(new Database(client,uid))); }
export async function withUserSql<T>(uid:string,fn:(client:PoolClient)=>Promise<T>):Promise<T> { safePart(uid);return sqlTransaction("leanguard_user",uid,fn); }
export async function checkDatabase() { return db.execute(async client=>{
  await client.query("SELECT collection FROM app_records LIMIT 0");
  if(config.production) {
    const role=await client.query("SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=session_user");
    const owner=await client.query("SELECT pg_get_userbyid(relowner)=session_user AS owns FROM pg_class WHERE oid='app_records'::regclass");
    if(role.rows[0]?.rolsuper||role.rows[0]?.rolbypassrls||owner.rows[0]?.owns) throw new Error("Runtime database login must not own tables or bypass RLS.");
  }
  return true;
}); }
// Lifecycle locks use separate sessions so holders never consume the query
// connection needed by their own export/deletion handlers. Never wait on an
// advisory lock while retaining a query-pool connection.
const lifecyclePool = new pg.Pool({ connectionString: config.databaseUrl || undefined, max: 4, connectionTimeoutMillis: 3000, idleTimeoutMillis: 10000, application_name: "leanguard-lifecycle" });
lifecyclePool.on("error", () => console.error(JSON.stringify({event:"lifecycle_connection_error"})));
export async function withOwnerLifecycleLock<T>(uid:string, operation:(signal:AbortSignal)=>Promise<T>):Promise<T> {
  safePart(uid);
  const client = await lifecyclePool.connect().catch(() => { throw new HttpError(503,"account_busy","Account operations are busy. Try again shortly."); });
  const controller = new AbortController();
  let locked = false, broken = false;
  const lost = () => { broken=true; controller.abort(new HttpError(503,"lifecycle_interrupted","The account operation was interrupted. Try again shortly.")); };
  client.on("error", lost);
  try {
    const result = await client.query("SELECT pg_try_advisory_lock(190918, hashtext($1)) AS locked",[uid]).catch(() => { lost(); throw controller.signal.reason; });
    locked = result.rows[0].locked === true;
    if(!locked) throw new HttpError(409,"account_busy","Another operation for this account is in progress. Try again shortly.");
    const value = await operation(controller.signal);
    controller.signal.throwIfAborted();
    return value;
  } finally {
    if(locked && !broken) await client.query("SELECT pg_advisory_unlock(190918, hashtext($1))",[uid]).catch(() => { broken=true; });
    client.off("error",lost);
    client.release(broken);
  }
}
export async function closeDatabase() { await Promise.all([pool.end(),lifecyclePool.end()]); }
