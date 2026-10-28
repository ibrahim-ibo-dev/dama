import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { actInRoom, createRoom, entryGuard, getRoom, joinRoom, readBody, requestToken, validateCode } from "../lib/server";
import { legalMoves } from "../lib/game";

test("private rooms: concurrent joins, authorization, atomic moves and agreed rematch", async () => {
  const host = randomUUID(), friend = randomUUID(), observer = randomUUID(), fourth = randomUUID();
  const created = await createRoom({ name: "یاریزان" }, host);
  assert.match(created.code, /^[A-HJ-NP-Z2-9]{10}$/);
  assert.equal(JSON.stringify(created).includes(host), false);
  await assert.rejects(() => getRoom(created.code, "stranger"));
  const results = await Promise.allSettled([
    joinRoom(created.code, { name: "هاوڕێ", role: "player" }, friend),
    joinRoom(created.code, { name: "تماشاکەر", role: "spectator" }, observer),
    joinRoom(created.code, { name: "تماشاکەری دووەم", role: "spectator" }, fourth),
  ]);
  assert.ok(results.every(result => result.status === "fulfilled"));
  const room = await getRoom(created.code, host);
  assert.equal(room.members.length, 4); assert.equal(room.started, true);
  assert.equal(room.members.filter(m => m.role === "black").length, 1);
  await assert.rejects(() => joinRoom(created.code, { name: "پێنجەم", role: "spectator" }, randomUUID()));
  const move = legalMoves(room.game.board, "white")[0];
  const action = { type: "move" as const, from: move.from, path: move.path, ply: 0, gameId: room.game.id };
  await assert.rejects(() => actInRoom(room.code, action, observer));
  await assert.rejects(() => actInRoom(room.code, action, friend));
  const simultaneous = await Promise.allSettled([actInRoom(room.code, action, host), actInRoom(room.code, action, host)]);
  assert.equal(simultaneous.filter(result => result.status === "fulfilled").length, 1);
  const moved = await getRoom(room.code, host);
  assert.equal(moved.game.ply, 1); assert.equal(moved.game.turn, "black");
  await actInRoom(room.code, { type: "draw", gameId: room.game.id }, host);
  const drawn = await actInRoom(room.code, { type: "draw", gameId: room.game.id }, friend);
  assert.ok("game" in drawn && drawn.game.winner === "draw");
  await actInRoom(room.code, { type: "rematch", gameId: room.game.id }, host);
  await actInRoom(room.code, { type: "rematch", gameId: room.game.id }, friend);
  const rematch = await getRoom(room.code, host);
  assert.notEqual(rematch.game.id, room.game.id);
  assert.equal(rematch.game.ply, 0); assert.equal(rematch.game.winner, null);
  assert.equal(rematch.members.find(m => m.id === rematch.me)?.role, "black");
  await assert.rejects(() => actInRoom(room.code, action, host));
  await actInRoom(room.code, { type: "leave" }, observer);
  const freed = await getRoom(room.code, host);
  assert.equal(freed.members.length, 3);
  await assert.rejects(() => getRoom(room.code, observer));
});

test("concurrent competitors for second player seat cannot both join", async () => {
  const host = randomUUID();
  const room = await createRoom({ name: "host" }, host);
  const joins = await Promise.allSettled(Array.from({ length: 4 }, (_, i) => joinRoom(room.code, { name: `friend-${i}`, role: "player" }, randomUUID())));
  assert.equal(joins.filter(result => result.status === "fulfilled").length, 1);
  assert.equal((await getRoom(room.code, host)).members.length, 2);
});

test("same-origin requests work behind Next's wildcard listener and reject foreign origins", async () => {
  const request = (origin: string, text = '{"name":"test"}') => new Request("http://0.0.0.0:3000/api/rooms", { method: "POST", headers: { host: "localhost:3000", origin }, body: text });
  assert.deepEqual(await readBody(request("http://localhost:3000")), { name: "test" });
  await assert.rejects(() => readBody(request("https://other.example")));
  await assert.rejects(() => readBody(request("null")));
  await assert.rejects(() => readBody(request("http://localhost:3000", "[]")));
  await assert.rejects(() => readBody(request("http://localhost:3000", "x".repeat(5000))));
  assert.throws(() => requestToken(new Request("http://localhost")));
  assert.throws(() => validateCode("bad"));
});

test("optional shared password rejects wrong passwords and accepts the configured one", async () => {
  const previous = process.env.SITE_PASSWORD;
  process.env.SITE_PASSWORD = "test-only-shared-password";
  try {
    const request = new Request("http://localhost:3000/api/rooms");
    await assert.rejects(() => entryGuard(request, { password: "wrong" }));
    await assert.rejects(() => entryGuard(request, {}));
    await entryGuard(request, { password: "test-only-shared-password" });
  } finally {
    if (previous === undefined) delete process.env.SITE_PASSWORD;
    else process.env.SITE_PASSWORD = previous;
  }
});
