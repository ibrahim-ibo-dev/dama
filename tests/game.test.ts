import test from "node:test";
import assert from "node:assert/strict";
import { countPieces, initialBoard, legalMoves, newGame, playMove, type Board, type Piece } from "../lib/game";

const boardWith = (pieces: Record<number, Piece>): Board => Object.assign(Array<Piece>(64).fill(0), pieces);
test("Turkish setup: 16 men per side, empty back ranks and center", () => {
  const board = initialBoard();
  assert.equal(countPieces(board, "white"), 16); assert.equal(countPieces(board, "black"), 16);
  for (const row of [0, 3, 4, 7]) assert.ok(board.slice(row * 8, row * 8 + 8).every(p => p === 0));
  assert.equal(legalMoves(board, "white").length, 8);
});
test("men move forward or sideways, never backward or diagonally", () => {
  const moves = legalMoves(boardWith({ 35: 1 }), "white");
  assert.deepEqual(moves.map(m => m.path[0]).sort((a,b) => a-b), [27, 34, 36]);
});
test("capture is mandatory and only globally longest complete chains are legal", () => {
  const board = boardWith({ 48: 1, 40: -1, 24: -1, 54: 1, 46: -1 });
  const moves = legalMoves(board, "white");
  assert.equal(moves.length, 1); assert.equal(moves[0].from, 48);
  assert.deepEqual(moves[0].path, [32, 16]); assert.deepEqual(moves[0].captures, [40, 24]);
});
test("a man can turn sideways between captures, captured men disappear", () => {
  const board = boardWith({ 43: 1, 35: -1, 28: -1 });
  const move = legalMoves(board, "white")[0];
  assert.deepEqual(move.path, [27, 29]);
  const next = playMove({ ...newGame("test"), board }, 43, [27, 29]);
  assert.equal(next.board[35], 0); assert.equal(next.board[28], 0); assert.equal(next.board[29], 1);
});
test("kings fly and can choose different empty landing squares", () => {
  const board = boardWith({ 56: 2, 32: -1 });
  assert.deepEqual(legalMoves(board, "white").map(m => m.path[0]).sort((a,b) => a-b), [0, 8, 16, 24]);
});
test("a flying king cannot reverse 180 degrees in a capture chain", () => {
  const moves = legalMoves(boardWith({ 27: 2, 25: -1, 29: -1 }), "white");
  assert.ok(moves.length > 1);
  assert.ok(moves.every(m => m.captures.length === 1));
});
test("promotion happens at end of turn, never midway through a chain", () => {
  const board = boardWith({ 18: 1, 10: -1, 3: -1, 7: -1 });
  const moves = legalMoves(board, "white");
  assert.equal(moves[0].captures.length, 2);
  assert.deepEqual(moves[0].path, [2, 4]);
  const next = playMove({ ...newGame("test"), board }, 18, [2,4]);
  assert.equal(next.board[4], 2);
  assert.equal(next.board[7], -1);
});
test("rejects partial capture chains and illegal moves without changing input", () => {
  const game = { ...newGame("test"), board: boardWith({ 48: 1, 40: -1, 24: -1 }) };
  const before = JSON.stringify(game);
  assert.throws(() => playMove(game, 48, [32]));
  assert.throws(() => playMove(game, 48, [49]));
  assert.equal(JSON.stringify(game), before);
});
test("capturing final opponent wins; blocked opponent also loses", () => {
  const game = { ...newGame("test"), board: boardWith({ 40: 1, 32: -1 }) };
  assert.equal(playMove(game, 40, [24]).winner, "white");
  const blocked = { ...newGame("test"), board: boardWith({ 40: 1, 56: -1, 57: -1, 58: -1, 59: -1, 60: -1, 61: -1, 62: -1, 63: -1 }) };
  const result = playMove(blocked, 40, [32]);
  assert.equal(result.winner, "white"); assert.equal(result.reason, "blocked");
});
test("single piece endgame: equal rank draws, king beats lone man", () => {
  const draw = playMove({ ...newGame("test"), board: boardWith({ 40: 1, 15: -1 }) }, 40, [32]);
  assert.equal(draw.winner, "draw");
  const kingWins = playMove({ ...newGame("test"), board: boardWith({ 40: 2, 15: -1 }) }, 40, [32]);
  assert.equal(kingWins.winner, "white");
});
test("sideways repetition is recorded even when ordinary men move", () => {
  let game = { ...newGame("test"), board: boardWith({ 48: 1, 55: 1, 8: -1, 15: -1 }) };
  for (let cycle = 0; cycle < 3 && !game.winner; cycle++) {
    for (const [from,to] of [[48,49],[8,9],[49,48],[9,8]]) {
      if (!game.winner) game = playMove(game, from, [to]);
    }
  }
  assert.equal(game.winner, "draw"); assert.equal(game.reason, "repetition");
});
