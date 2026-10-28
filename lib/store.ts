import { Redis } from "@upstash/redis";
import type { Room } from "./types";

export class AppError extends Error {
  constructor(message: string, public status = 400) { super(message); }
}
const TTL = 24 * 60 * 60;
const url = process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL;
const token = process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN;
const redis = url && token ? new Redis({ url, token, automaticDeserialization: true }) : null;
const localAllowed = !process.env.VERCEL && process.env.NODE_ENV !== "production";
const globals = globalThis as typeof globalThis & {
  damaMemory?: Map<string, { room: Room; expires: number }>;
  damaLimits?: Map<string, { count: number; expires: number }>;
};
const memory = globals.damaMemory ??= new Map();
const limits = globals.damaLimits ??= new Map();
export const storageMode = () => redis ? "redis" : localAllowed ? "local" : "unconfigured";
function requireStorage() {
  if (!redis && !localAllowed) throw new AppError("بۆ یاری ئۆنڵاین، سەرەتا Upstash Redis لە Vercel پەیوەست بکە و Redeploy بکە.", 503);
}
const key = (code: string) => `dama:v1:room:${code}`;

export async function readRoom(code: string): Promise<Room | null> {
  requireStorage();
  if (redis) return redis.get<Room>(key(code));
  const entry = memory.get(code);
  if (!entry || entry.expires < Date.now()) { memory.delete(code); return null; }
  return structuredClone(entry.room);
}
export async function insertRoom(room: Room): Promise<boolean> {
  requireStorage();
  if (redis) return await redis.set(key(room.code), room, { ex: TTL, nx: true }) === "OK";
  if (memory.has(room.code)) return false;
  for (const [code, entry] of memory) if (entry.expires < Date.now()) memory.delete(code);
  memory.set(room.code, { room: structuredClone(room), expires: Date.now() + TTL * 1000 });
  return true;
}

/** A single atomic compare-and-swap protects joins, moves and rematches across
 * concurrent Vercel instances. No process-local production room state. */
async function compareAndSwap(room: Room, expected: number): Promise<boolean> {
  if (redis) {
    const saved = await redis.eval<(string | number)[], number>(
      `local raw = redis.call('GET', KEYS[1])
       if not raw or cjson.decode(raw).revision ~= tonumber(ARGV[1]) then return 0 end
       redis.call('SET', KEYS[1], ARGV[2], 'EX', ARGV[3])
       return 1`,
      [key(room.code)], [expected, JSON.stringify(room), TTL],
    );
    return saved === 1;
  }
  const current = memory.get(room.code);
  if (!current || current.expires < Date.now() || current.room.revision !== expected) return false;
  memory.set(room.code, { room: structuredClone(room), expires: Date.now() + TTL * 1000 });
  return true;
}
export async function updateRoom(code: string, update: (room: Room) => void): Promise<Room> {
  for (let attempt = 0; attempt < 8; attempt++) {
    const room = await readRoom(code);
    if (!room) throw new AppError("ڕوومەکە نەدۆزرایەوە یان ماوەکەی بەسەرچووە. ڕوومێکی نوێ دروست بکە.", 404);
    const expected = room.revision;
    update(room);
    room.revision++; room.updatedAt = Date.now();
    if (await compareAndSwap(room, expected)) return room;
  }
  throw new AppError("جووڵەکان هاوکات بوون. دووبارە هەوڵ بدەوە.", 409);
}

export async function rateLimit(bucket: string, maximum: number, seconds: number) {
  requireStorage();
  let count: number;
  if (redis) count = await redis.eval<(string | number)[], number>(
    "local n = redis.call('INCR', KEYS[1]); if n == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end; return n",
    [`dama:v1:limit:${bucket}`], [seconds],
  );
  else {
    for (const [id, entry] of limits) if (entry.expires < Date.now()) limits.delete(id);
    const entry = limits.get(bucket);
    const next = !entry || entry.expires < Date.now() ? { count: 1, expires: Date.now() + seconds * 1000 } : { ...entry, count: entry.count + 1 };
    limits.set(bucket, next); count = next.count;
  }
  if (count > maximum) throw new AppError("هەوڵەکان زۆرن. کەمێک چاوەڕێ بکە و دووبارە هەوڵ بدەوە.", 429);
}
