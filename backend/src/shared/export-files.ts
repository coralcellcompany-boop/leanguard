import { createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdir, open, readdir, realpath, rm, stat } from "node:fs/promises";
import { createReadStream } from "node:fs";
import path from "node:path";

const UID = /^[A-Za-z0-9_-]{1,128}$/;
const FILE = /^[a-f0-9-]{36}\.json$/;
export const exportLifetimeMs = 24 * 60 * 60 * 1000;
export const downloadLifetimeMs = 10 * 60 * 1000;
export type ExportFileConfig = { directory: string; publicBaseUrl: string; signingSecret: string };

/** Private local volume. Nothing in this directory is served as static content. */
export class ExportFiles {
  constructor(readonly config: ExportFileConfig) {
    if (config.signingSecret.length < 32) throw new Error("EXPORT_SIGNING_SECRET must contain at least 32 characters.");
    const url = new URL(config.publicBaseUrl);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash || url.pathname !== '/') throw new Error("PUBLIC_BASE_URL must be an origin without a path.");
  }
  private async ownerDirectory(uid: string): Promise<string> {
    if (!UID.test(uid)) throw new Error("Invalid export owner.");
    await mkdir(this.config.directory, { recursive: true, mode: 0o700 });
    const root = await realpath(this.config.directory);
    const directory = path.join(root, uid);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    if (await realpath(directory) !== directory) throw new Error("Invalid export directory.");
    return directory;
  }
  async create(uid: string) {
    const name = `${randomUUID()}.json`;
    const destination = path.join(await this.ownerDirectory(uid), name);
    const handle = await open(destination, 'wx', 0o600);
    let closed = false;
    return {
      name,
      // Await writes: an export cannot queue unbounded disk buffers.
      write: async (text: string) => { await handle.writeFile(text); },
      finish: async () => { if (!closed) { await handle.sync(); await handle.close(); closed = true; } },
      discard: async () => { if (!closed) { await handle.close().catch(() => undefined); closed = true; } await rm(destination, { force: true }); },
    };
  }
  private signature(uid: string, name: string, expires: number): string {
    return createHmac('sha256', this.config.signingSecret).update(`leanguard-export-v1\n${uid}\n${name}\n${expires}`).digest('hex');
  }
  signedUrl(uid: string, name: string, now = Date.now()): string {
    if (!UID.test(uid) || !FILE.test(name)) throw new Error("Invalid export identifier.");
    const expires = now + downloadLifetimeMs;
    const url = new URL(`/v1/exports/${uid}/${name}`, this.config.publicBaseUrl);
    url.searchParams.set('expires', String(expires));
    url.searchParams.set('signature', this.signature(uid, name, expires));
    return url.toString();
  }
  verify(uid: string, name: string, expires: unknown, signature: unknown, now = Date.now()): boolean {
    if (!UID.test(uid) || !FILE.test(name) || typeof expires !== 'string' || !/^\d{13}$/.test(expires) || typeof signature !== 'string' || !/^[a-f0-9]{64}$/.test(signature)) return false;
    const expiry = Number(expires);
    if (expiry <= now || expiry > now + downloadLifetimeMs) return false;
    const expected = Buffer.from(this.signature(uid, name, expiry), 'hex');
    return timingSafeEqual(expected, Buffer.from(signature, 'hex'));
  }
  async read(uid: string, name: string) {
    if (!UID.test(uid) || !FILE.test(name)) throw new Error("Invalid export identifier.");
    const destination = path.join(await this.ownerDirectory(uid), name);
    if (await realpath(destination) !== destination) throw new Error("Invalid export file.");
    const info = await stat(destination);
    if (!info.isFile() || info.mtimeMs < Date.now() - exportLifetimeMs) throw new Error("Export expired.");
    return { stream: createReadStream(destination), bytes: info.size };
  }
  async removeOwner(uid: string): Promise<void> {
    if (!UID.test(uid)) throw new Error("Invalid export owner.");
    const root = path.resolve(this.config.directory);
    await rm(path.join(root, uid), { recursive: true, force: true });
  }
  async prune(now = Date.now()): Promise<number> {
    await mkdir(this.config.directory, { recursive: true, mode: 0o700 });
    let removed = 0;
    for (const owner of await readdir(this.config.directory, { withFileTypes: true })) {
      if (!owner.isDirectory() || !UID.test(owner.name)) continue;
      const directory = path.join(this.config.directory, owner.name);
      for (const file of await readdir(directory, { withFileTypes: true })) {
        if (!file.isFile() || !FILE.test(file.name)) continue;
        const destination = path.join(directory, file.name);
        const info = await stat(destination).catch(() => null);
        if (info && info.mtimeMs < now - exportLifetimeMs) {
          await rm(destination, { force: true }); removed++;
        }
      }
    }
    return removed;
  }
}
