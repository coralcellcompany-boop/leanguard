import path from "node:path";
import { readFileSync } from "node:fs";
const fileSecrets = new Map<string,string>();
export function environment(name: string, fallback = ""): string {
  const file = process.env[`${name}_FILE`];
  if (!file) return process.env[name] ?? fallback;
  if (!fileSecrets.has(file)) fileSecrets.set(file, readFileSync(file, "utf8").trim());
  return fileSecrets.get(file)!;
}
export const config = {
  get port() { return Number(process.env.PORT ?? 8080); },
  get databaseUrl() { return environment("DATABASE_URL"); },
  get databasePoolSize() { return Number(process.env.DATABASE_POOL_SIZE ?? 10); },
  get firebaseProjectId() { return process.env.FIREBASE_PROJECT_ID ?? "leanguard-a58ff"; },
  get allowedOrigins() { return (process.env.ALLOWED_ORIGINS ?? "").split(",").map(x => x.trim()).filter(Boolean); },
  get publicBaseUrl() { return (process.env.PUBLIC_BASE_URL ?? process.env.PUBLIC_API_URL ?? "http://localhost:8080").replace(/\/$/, ""); },
  get exportDirectory() { return path.resolve(process.env.EXPORT_DIRECTORY ?? "./data/exports"); },
  get storageRoot() { return path.resolve(process.env.STORAGE_ROOT ?? "./data"); },
  get exportSigningSecret() { return environment("EXPORT_SIGNING_SECRET"); },
  get production() { return process.env.NODE_ENV === "production"; },
};
export function validateConfig(): void {
  if (!config.databaseUrl || !/^postgres(?:ql)?:\/\//.test(config.databaseUrl)) throw new Error("DATABASE_URL must be a PostgreSQL connection URL.");
  if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) throw new Error("PORT is invalid.");
  if (!config.firebaseProjectId) throw new Error("FIREBASE_PROJECT_ID is required.");
  if (!Number.isInteger(config.databasePoolSize) || config.databasePoolSize < 2 || config.databasePoolSize > 50) throw new Error("DATABASE_POOL_SIZE must be an integer between 2 and 50.");
  let publicUrl: URL;
  try { publicUrl = new URL(config.publicBaseUrl); } catch { throw new Error("PUBLIC_BASE_URL must be a valid origin."); }
  if (!["http:", "https:"].includes(publicUrl.protocol) || !publicUrl.hostname || publicUrl.username || publicUrl.password || publicUrl.pathname !== "/" || publicUrl.search || publicUrl.hash) throw new Error("PUBLIC_BASE_URL must be an HTTP(S) origin without credentials, path, query or fragment.");
  if (config.production && publicUrl.protocol !== "https:") throw new Error("Production PUBLIC_BASE_URL must use HTTPS.");
  if (config.production && (process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.FUNCTIONS_EMULATOR)) throw new Error("Authentication emulators are forbidden in production.");
  if (config.production && config.exportSigningSecret.length < 32) throw new Error("EXPORT_SIGNING_SECRET must contain at least 32 characters.");
  if (config.allowedOrigins.includes("*")) throw new Error("ALLOWED_ORIGINS must list explicit origins.");
}
