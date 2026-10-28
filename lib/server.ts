import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { newGame, opposite, playMove } from "./game";
import { AppError, insertRoom, rateLimit, readRoom, updateRoom } from "./store";
import type { Member, PublicRoom, Room, RoomAction } from "./types";

const hash = (value: string) => createHash("sha256").update(value).digest("hex");
export function validateCode(code: string) {
  const normalized = code.toUpperCase().replace(/[\s-]/g, "");
  if (!/^[A-HJ-NP-Z2-9]{10}$/.test(normalized)) throw new AppError("کۆدی ڕووم دەبێت ١٠ پیت و ژمارە بێت.");
  return normalized;
}
export function requestToken(request: Request) {
  const token = request.headers.get("x-player-token") || "";
  if (!/^[a-zA-Z0-9_-]{32,128}$/.test(token)) throw new AppError("تکایە دووبارە بچۆ ژوورەوە.", 401);
  return hash(token);
}
function member(room: Room, tokenHash: string): Member {
  const player = room.members.find(m => m.tokenHash === tokenHash);
  if (!player) throw new AppError("سەرەتا بچۆ ناو ڕوومەکە.", 403);
  return player;
}
/** Previously stored rooms remain usable after deploying the room details update. */
function roomDefaults(room: Room) {
  room.messages ??= [];
  room.results ??= [];
}
/** Capture the winner's stable identity before a rematch swaps player colors. */
function recordResult(room: Room) {
  if (!room.game.winner || room.results.some(result => result.gameId === room.game.id)) return;
  room.results.push({
    gameId: room.game.id,
    winnerId: room.game.winner === "draw" ? null : room.members.find(m => m.role === room.game.winner)?.id ?? null,
    reason: room.game.reason,
    finishedAt: Date.now(),
  });
  room.results = room.results.slice(-20);
}
export function publicRoom(room: Room, tokenHash: string): PublicRoom {
  const me = member(room, tokenHash);
  roomDefaults(room);
  const { positions: _positions, ...game } = room.game;
  return { ...room, game, members: room.members.map(({ tokenHash: _secret, ...m }) => m), me: me.id };
}
export async function readBody(request: Request): Promise<Record<string, unknown>> {
  const origin = request.headers.get("origin");
  if (origin) {
    const expectedHost = request.headers.get("host") || new URL(request.url).host;
    let allowed = false;
    try { const parsed = new URL(origin); allowed = ["https:", "http:"].includes(parsed.protocol) && parsed.host === expectedHost; } catch { /* Invalid Origin. */ }
    if (!allowed) throw new AppError("داواکاری ڕێگەپێنەدراوە.", 403);
  }
  const text = await request.text();
  if (text.length > 4096) throw new AppError("داواکارییەکە زۆر گەورەیە.", 413);
  try {
    const body: unknown = JSON.parse(text);
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
    return body as Record<string, unknown>;
  } catch { throw new AppError("داواکارییەکە دروست نییە."); }
}
export async function entryGuard(request: Request, body: Record<string, unknown>, create = false) {
  const ip = process.env.VERCEL ? request.headers.get("x-vercel-forwarded-for") || request.headers.get("x-forwarded-for") || "unknown" : "local";
  await rateLimit(`entry:${hash(ip)}`, 60, 60);
  if (create) await rateLimit(`create:${hash(ip)}`, 15, 3600);
  const password = process.env.SITE_PASSWORD;
  if (password) {
    const provided = typeof body.password === "string" ? body.password : "";
    if (!timingSafeEqual(Buffer.from(hash(provided)), Buffer.from(hash(password)))) throw new AppError("وشەی نهێنی دروست نییە.", 401);
  }
}
function playerName(body: Record<string, unknown>) {
  if (typeof body.name !== "string") throw new AppError("تکایە ناوت بنووسە.");
  const name = body.name.trim().replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, "");
  if (!name || name.length > 24) throw new AppError("ناوەکەت لە ١ بۆ ٢٤ پیت بێت.");
  return name;
}
export async function createRoom(body: Record<string, unknown>, tokenHash: string) {
  const name = playerName(body);
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = Array.from(randomBytes(10), byte => alphabet[byte % 32]).join("");
    const now = Date.now();
    const room: Room = {
      code, createdAt: now, updatedAt: now, revision: 0,
      members: [{ id: randomUUID(), name, role: "white", tokenHash, lastSeen: now }],
      game: newGame(randomUUID()), started: false, drawOffer: null, rematchVotes: [],
      messages: [], results: [],
    };
    if (await insertRoom(room)) return publicRoom(room, tokenHash);
  }
  throw new AppError("ڕووم دروست نەکرا. دووبارە هەوڵ بدەوە.", 503);
}
export async function joinRoom(code: string, body: Record<string, unknown>, tokenHash: string) {
  const name = playerName(body);
  if (body.role !== "player" && body.role !== "spectator") throw new AppError("جۆری چوونەژوورەوە دیاری بکە.");
  const room = await updateRoom(code, room => {
    roomDefaults(room);
    recordResult(room);
    const existing = room.members.find(m => m.tokenHash === tokenHash);
    if (existing) { existing.lastSeen = Date.now(); return; }
    if (room.members.length >= 4) throw new AppError("ڕوومەکە پڕە؛ زۆرترین ٤ کەس.", 409);
    const role = body.role === "spectator" ? "spectator" : "black";
    if (role === "black" && room.members.some(m => m.role === "black")) throw new AppError("هەردوو شوێنی یاریزان گیراون. وەک تماشاکەر بچۆ ژوورەوە.", 409);
    if (role === "spectator" && room.members.filter(m => m.role === "spectator").length >= 2) throw new AppError("هەردوو شوێنی تماشاکەر گیراون.", 409);
    room.members.push({ id: randomUUID(), name, role, tokenHash, lastSeen: Date.now() });
    if (role === "black") room.started = true;
  });
  return publicRoom(room, tokenHash);
}
export async function getRoom(code: string, tokenHash: string) {
  const room = await readRoom(code);
  if (!room) throw new AppError("ڕوومەکە نەدۆزرایەوە یان ماوەکەی بەسەرچووە.", 404);
  return publicRoom(room, tokenHash);
}
export async function actInRoom(code: string, body: Record<string, unknown>, tokenHash: string) {
  await rateLimit(`action:${tokenHash}`, 120, 60);
  const action = body as unknown as RoomAction;
  const room = await updateRoom(code, room => {
    const me = member(room, tokenHash);
    roomDefaults(room);
    recordResult(room);
    if (action.type === "leave") {
      if (me.role === "spectator") room.members = room.members.filter(m => m.id !== me.id);
      else {
        if (room.started && !room.game.winner) { room.game.winner = opposite(me.role); room.game.reason = "resign"; }
        me.lastSeen = 0;
      }
      recordResult(room);
      return;
    }
    me.lastSeen = Date.now();
    if (action.type === "heartbeat") return;
    if (action.type === "message") {
      if (typeof action.text !== "string" || action.text.length > 240) throw new AppError("پەیامەکەت دەبێت لە ١ بۆ ٢٤٠ پیت بێت.");
      const text = action.text.replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "").trim();
      if (!text) throw new AppError("سەرەتا پەیامێک بنووسە.");
      room.messages.push({ id: randomUUID(), memberId: me.id, name: me.name, text, createdAt: Date.now() });
      room.messages = room.messages.slice(-40);
      return;
    }
    if (me.role === "spectator") throw new AppError("تماشاکەر ناتوانێت جووڵە بکات.", 403);
    if (action.gameId !== room.game.id) throw new AppError("یارییەکی نوێ دەستی پێکردووە. دووبارە هەوڵ بدەوە.", 409);
    if (action.type === "rematch") {
      if (!room.game.winner) throw new AppError("سەرەتا یارییەکە تەواو بکەن.");
      if (!room.rematchVotes.includes(me.id)) room.rematchVotes.push(me.id);
      if (room.rematchVotes.length === 2) {
        room.members.forEach(m => { if (m.role !== "spectator") m.role = opposite(m.role); });
        room.game = newGame(randomUUID()); room.rematchVotes = []; room.drawOffer = null;
      }
      return;
    }
    if (!room.started || room.game.winner) throw new AppError("یارییەکە ئێستا چالاک نییە.", 409);
    if (action.type === "move") {
      if (me.role !== room.game.turn) throw new AppError("ئێستا نۆرەی تۆ نییە.", 409);
      if (!Number.isInteger(action.from) || !Array.isArray(action.path) || !action.path.length || action.path.length > 32 || !action.path.every(s => Number.isInteger(s) && s >= 0 && s < 64)) throw new AppError("جووڵەکە دروست نییە.");
      if (action.ply !== room.game.ply) throw new AppError("دۆخی یاری گۆڕاوە. دووبارە هەوڵ بدەوە.", 409);
      try { room.game = playMove(room.game, action.from, action.path); }
      catch (error) { throw new AppError(error instanceof Error ? error.message : "جووڵەکە دروست نییە."); }
      room.drawOffer = null;
    } else if (action.type === "resign") { room.game.winner = opposite(me.role); room.game.reason = "resign"; }
    else if (action.type === "draw") {
      if (room.drawOffer && room.drawOffer !== me.role) { room.game.winner = "draw"; room.game.reason = "agreement"; room.drawOffer = null; }
      else room.drawOffer = room.drawOffer === me.role ? null : me.role;
    } else if (action.type === "decline-draw") { room.drawOffer = null; }
    else throw new AppError("ئەم کردارە نەناسراوە.");
    recordResult(room);
  });
  if (action.type === "leave") return { left: true };
  return publicRoom(room, tokenHash);
}
export function json(data: unknown, status = 200) {
  return NextResponse.json(data, { status, headers: { "Cache-Control": "no-store, max-age=0" } });
}
export function errorResponse(error: unknown) {
  if (error instanceof AppError) return json({ error: error.message }, error.status);
  console.error("Dama API request failed:", error instanceof Error ? error.name : "UnknownError");
  return json({ error: "پەیوەندی بە سێرڤەر نەکرا. کەمێک دواتر دووبارە هەوڵ بدەوە." }, 503);
}
