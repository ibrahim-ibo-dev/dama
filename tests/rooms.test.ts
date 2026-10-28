import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { actInRoom, createRoom, entryGuard, getRoom, joinRoom, readBody, requestToken, validateCode } from "../lib/server";
import { legalMoves } from "../lib/game";
import { readRoom, updateRoom } from "../lib/store";
import type { Room } from "../lib/types";

async function friendsRoom() {
  const host = randomUUID(), friend = randomUUID();
  const created = await createRoom({ name: "یاریزان" }, host);
  await joinRoom(created.code, { name: "هاوڕێ", role: "player" }, friend);
  return { host, friend, room: await getRoom(created.code, host) };
}

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

test("room messages use server identity, allow spectators, and validate plain text", async () => {
  const { host, friend, room } = await friendsRoom();
  const observer = randomUUID();
  const joined = await joinRoom(room.code, { name: "بینەر", role: "spectator" }, observer);
  assert.deepEqual(joined.messages, []);
  assert.deepEqual(joined.results, []);
  await assert.rejects(() => actInRoom(room.code, { type: "message", text: "hello" }, randomUUID()), { status: 403 });
  for (const text of ["", "   ", "\u202e\u0000", "x".repeat(241), 123]) {
    await assert.rejects(() => actInRoom(room.code, { type: "message", text }, host));
  }
  await actInRoom(room.code, { type: "message", text: "  سڵاو\u202e\u0000!  ", name: "spoofed", memberId: "spoofed" }, observer);
  let current = await getRoom(room.code, host);
  assert.equal(current.messages[0].text, "سڵاو!");
  assert.equal(current.messages[0].name, "بینەر");
  assert.equal(current.messages[0].memberId, joined.me);
  assert.ok(current.messages[0].createdAt <= Date.now());
  assert.ok(!JSON.stringify(current).includes(observer));
  await actInRoom(room.code, { type: "resign", gameId: room.game.id }, friend);
  await actInRoom(room.code, { type: "message", text: "دەست‌خۆش!" }, observer);
  current = await getRoom(room.code, host);
  assert.equal(current.messages.length, 2);
  assert.equal(current.results.length, 1);
  await actInRoom(room.code, { type: "leave" }, observer);
  await assert.rejects(() => actInRoom(room.code, { type: "message", text: "not a member now" }, observer), { status: 403 });
});

test("chat keeps only the newest forty messages and survives rematches", async () => {
  const { host, friend, room } = await friendsRoom();
  for (let i = 0; i < 45; i++) await actInRoom(room.code, { type: "message", text: `message-${i}` }, host);
  let current = await getRoom(room.code, friend);
  assert.equal(current.messages.length, 40);
  assert.equal(current.messages[0].text, "message-5");
  assert.equal(current.messages.at(-1)?.text, "message-44");
  assert.equal(new Set(current.messages.map(message => message.id)).size, 40);
  await actInRoom(room.code, { type: "resign", gameId: room.game.id }, friend);
  await actInRoom(room.code, { type: "rematch", gameId: room.game.id }, host);
  await actInRoom(room.code, { type: "rematch", gameId: room.game.id }, friend);
  current = await getRoom(room.code, host);
  assert.equal(current.messages.length, 40);
  assert.equal(current.messages.at(-1)?.text, "message-44");
});

test("move wins, resignations, leaving, and agreed draws each record one stable result", async () => {
  for (const finish of ["move", "resign", "leave", "draw"] as const) {
    const { host, friend, room } = await friendsRoom();
    const hostId = room.me, friendId = room.members.find(member => member.role === "black")!.id;
    if (finish === "move") {
      await updateRoom(room.code, stored => { stored.game.board.fill(0); stored.game.board[40] = 1; stored.game.board[32] = -1; });
      await actInRoom(room.code, { type: "move", from: 40, path: [24], ply: 0, gameId: room.game.id }, host);
    } else if (finish === "draw") {
      await actInRoom(room.code, { type: "draw", gameId: room.game.id }, host);
      await actInRoom(room.code, { type: "draw", gameId: room.game.id }, friend);
    } else if (finish === "leave") await actInRoom(room.code, { type: "leave" }, host);
    else await actInRoom(room.code, { type: "resign", gameId: room.game.id }, friend);
    await Promise.all([0, 1, 2].map(() => actInRoom(room.code, { type: "heartbeat" }, friend)));
    const current = await getRoom(room.code, friend);
    assert.equal(current.results.length, 1, finish);
    assert.equal(current.results[0].gameId, room.game.id);
    assert.equal(current.results[0].winnerId, finish === "draw" ? null : finish === "leave" ? friendId : hostId);
    assert.equal(current.results[0].reason, finish === "move" ? "pieces" : finish === "draw" ? "agreement" : "resign");
  }
});

test("match results survive color swaps and remain bounded to twenty games", async () => {
  const { host, friend, room } = await friendsRoom();
  const hostId = room.me;
  let current = room;
  for (let i = 0; i < 22; i++) {
    const gameId = current.game.id;
    await actInRoom(room.code, { type: "resign", gameId }, friend);
    current = await getRoom(room.code, host);
    assert.equal(current.results.at(-1)?.winnerId, hostId);
    if (i < 21) {
      await actInRoom(room.code, { type: "rematch", gameId }, host);
      await actInRoom(room.code, { type: "rematch", gameId }, friend);
      current = await getRoom(room.code, host);
      assert.equal(current.members.find(member => member.id === hostId)?.role, i % 2 === 0 ? "black" : "white");
    }
  }
  assert.equal(current.results.length, 20);
  assert.ok(current.results.every(result => result.winnerId === hostId));
  assert.ok(!current.results.some(result => result.gameId === room.game.id));
});

test("rooms from older deployments acquire chat and result defaults without resetting play", async () => {
  const { host, friend, room } = await friendsRoom();
  await updateRoom(room.code, stored => {
    delete (stored as Partial<Room>).messages;
    delete (stored as Partial<Room>).results;
  });
  const before = await getRoom(room.code, host);
  assert.deepEqual(before.messages, []); assert.deepEqual(before.results, []);
  assert.equal(before.game.id, room.game.id);
  await actInRoom(room.code, { type: "message", text: "still here" }, host);
  await actInRoom(room.code, { type: "resign", gameId: room.game.id }, friend);
  const stored = await readRoom(room.code);
  assert.equal(stored?.messages.length, 1);
  assert.equal(stored?.results.length, 1);
  assert.equal(stored?.results[0].winnerId, room.me);
});
