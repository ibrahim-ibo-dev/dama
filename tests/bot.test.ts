import test from "node:test";
import assert from "node:assert/strict";
import { chooseBotMove, type BotLevel } from "../lib/bot";
import { initialBoard, legalMoves, newGame, playMove, type Board, type Piece } from "../lib/game";

const boardWith = (pieces: Record<number, Piece>): Board => Object.assign(Array<Piece>(64).fill(0), pieces);
const moveKey = (move: { from: number; path: number[] } | null) => move ? `${move.from}:${move.path.join(",")}` : "none";

test("every difficulty returns a legal complete turn for either color without mutating the board", () => {
  const board = initialBoard(), original = [...board];
  for (const color of ["white", "black"] as const) for (const level of ["easy", "medium", "hard"] as const) {
    const analysis = chooseBotMove(board, color, level, { timeMs: 25, seed: 23 });
    assert.ok(analysis.move, `${level}/${color}`);
    assert.ok(legalMoves(board, color).some(move => moveKey(move) === moveKey(analysis.move)));
    assert.ok(Number.isFinite(analysis.score));
    assert.ok(analysis.nodes > 0);
    const next = playMove({ ...newGame("bot-test"), board, turn: color }, analysis.move.from, analysis.move.path);
    assert.equal(next.ply, 1);
  }
  assert.deepEqual(board, original);
});

test("bots obey mandatory global maximum captures and return the whole chain", () => {
  const board = boardWith({ 48: 1, 40: -1, 24: -1, 54: 1, 46: -1 });
  for (const level of ["easy", "medium", "hard"] as BotLevel[]) {
    const analysis = chooseBotMove(board, "white", level, { seed: 17 });
    assert.equal(analysis.move?.from, 48);
    assert.deepEqual(analysis.move?.path, [32, 16]);
    assert.deepEqual(analysis.move?.captures, [40, 24]);
  }
});

test("search avoids both immediate capture traps when a safe alternative exists", () => {
  // Forward to d5 lets d6 capture the only white man; right to e4 lets
  // e5 do the same. c4 is the only move that keeps white in the game.
  const board = boardWith({ 35: 1, 19: -1, 28: -1, 7: -1 });
  for (const level of ["medium", "hard"] as const) {
    const result = chooseBotMove(board, "white", level, { timeMs: 100, seed: 5 });
    assert.equal(result.move?.from, 35);
    assert.deepEqual(result.move?.path, [34], level);
    assert.ok(result.depth >= 2);
  }
});

test("search recognizes promotion and values capturing a king over an ordinary man", () => {
  const promotion = chooseBotMove(boardWith({ 8: 1, 47: -1, 55: -1 }), "white", "medium", { timeMs: 80, seed: 19 });
  assert.deepEqual(promotion.move?.path, [0]);
  const capture = chooseBotMove(boardWith({ 43: 1, 35: -2, 44: -1, 7: -1 }), "white", "hard", { timeMs: 100, seed: 19 });
  assert.deepEqual(capture.move?.captures, [35]);
});

test("terminal, missing-piece and blocked positions return no move", () => {
  assert.equal(chooseBotMove(boardWith({}), "white", "hard").move, null);
  assert.equal(chooseBotMove(boardWith({ 40: 1 }), "white", "medium").move, null);
  const blocked = boardWith({ 40: 1, 56: -1, 57: -1, 58: -1, 59: -1, 60: -1, 61: -1, 62: -1, 63: -1 });
  const result = chooseBotMove(blocked, "black", "hard");
  assert.equal(result.move, null); assert.ok(result.score < -90_000);
  const winnerBlocked = [...blocked]; winnerBlocked[40] = 0;
  assert.ok(chooseBotMove(winnerBlocked, "black", "hard").score > 90_000);
  const draw = chooseBotMove(boardWith({ 40: 1, 15: -1 }), "white", "hard");
  assert.equal(draw.move, null); assert.equal(draw.score, 0);
  const kingWins = chooseBotMove(boardWith({ 40: 2, 15: -1 }), "white", "hard");
  assert.equal(kingWins.move, null); assert.ok(kingWins.score > 90_000);
});

test("easy's seed is repeatable while different seeds create varied legal choices", () => {
  const board = initialBoard();
  const first = chooseBotMove(board, "white", "easy", { seed: 42 });
  assert.deepEqual(chooseBotMove(board, "white", "easy", { seed: 42 }), first);
  const choices = new Set(Array.from({ length: 16 }, (_, seed) => moveKey(chooseBotMove(board, "white", "easy", { seed }).move)));
  assert.ok(choices.size > 3);
});

test("tiny and zero search budgets still return legal moves promptly", () => {
  const board = initialBoard();
  const start = performance.now();
  for (const timeMs of [0, 1, 10]) {
    const analysis = chooseBotMove(board, "white", "hard", { timeMs, seed: 9 });
    assert.ok(analysis.move);
    assert.ok(legalMoves(board, "white").some(move => moveKey(move) === moveKey(analysis.move)));
    assert.ok(analysis.nodes <= 100_000);
    if (timeMs === 0) assert.equal(analysis.depth, 0);
  }
  assert.ok(performance.now() - start < 800, "bounded work must not turn into an unbounded search");
});
