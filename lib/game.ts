export type Color = "white" | "black";
export type Piece = 0 | 1 | 2 | -1 | -2;
export type Board = Piece[];
export type Move = { from: number; path: number[]; captures: number[] };
export type Game = {
  id: string;
  board: Board;
  turn: Color;
  ply: number;
  winner: Color | "draw" | null;
  reason: "pieces" | "blocked" | "resign" | "agreement" | "repetition" | "single-piece" | null;
  lastMove: Move | null;
  history: { color: Color; label: string; captures: number }[];
  positions: Record<string, number>;
};

export const opposite = (color: Color): Color => color === "white" ? "black" : "white";
export const pieceColor = (piece: Piece): Color | null => piece > 0 ? "white" : piece < 0 ? "black" : null;
const inside = (row: number, col: number) => row >= 0 && row < 8 && col >= 0 && col < 8;
const positionKey = (board: Board, turn: Color) => `${board.join(",")}:${turn}`;
export const coordinate = (square: number) => `${"abcdefgh"[square % 8]}${8 - Math.floor(square / 8)}`;

export function initialBoard(): Board {
  return Array.from({ length: 64 }, (_, index) => {
    const row = Math.floor(index / 8);
    return row === 1 || row === 2 ? -1 : row === 5 || row === 6 ? 1 : 0;
  });
}

export function newGame(id: string): Game {
  const board = initialBoard();
  return { id, board, turn: "white", ply: 0, winner: null, reason: null, lastMove: null, history: [], positions: { [positionKey(board, "white")]: 1 } };
}

type Direction = readonly [number, number];
function directions(piece: Piece): Direction[] {
  const forward = piece > 0 ? -1 : 1;
  return Math.abs(piece) === 2 ? [[-1, 0], [1, 0], [0, -1], [0, 1]] : [[forward, 0], [0, -1], [0, 1]];
}

/** Enumerate complete capture chains. Captured pieces disappear immediately;
 * a man remains a man until its entire turn ends. A king cannot reverse 180°.
 */
function captureChains(board: Board, square: number, piece: Piece, previous?: Direction): Move[] {
  const result: Move[] = [];
  const row = Math.floor(square / 8), col = square % 8;
  for (const [dr, dc] of directions(piece)) {
    if (previous && dr === -previous[0] && dc === -previous[1]) continue;
    let r = row + dr, c = col + dc;
    const king = Math.abs(piece) === 2;
    if (king) while (inside(r, c) && board[r * 8 + c] === 0) { r += dr; c += dc; }
    if (!inside(r, c)) continue;
    const victim = r * 8 + c;
    if (board[victim] === 0 || pieceColor(board[victim]) === pieceColor(piece)) continue;
    r += dr; c += dc;
    while (inside(r, c) && board[r * 8 + c] === 0) {
      const landing = r * 8 + c;
      const next = [...board];
      next[square] = 0; next[victim] = 0; next[landing] = piece;
      const rest = captureChains(next, landing, piece, [dr, dc]);
      if (!rest.length) result.push({ from: square, path: [landing], captures: [victim] });
      else for (const chain of rest) result.push({ from: square, path: [landing, ...chain.path], captures: [victim, ...chain.captures] });
      if (!king) break;
      r += dr; c += dc;
    }
  }
  return result;
}

export function legalMoves(board: Board, color: Color): Move[] {
  const captures: Move[] = [];
  for (let square = 0; square < 64; square++) {
    if (pieceColor(board[square]) === color) captures.push(...captureChains(board, square, board[square]));
  }
  if (captures.length) {
    const maximum = Math.max(...captures.map(move => move.captures.length));
    return captures.filter(move => move.captures.length === maximum);
  }
  const moves: Move[] = [];
  for (let square = 0; square < 64; square++) {
    const piece = board[square];
    if (pieceColor(piece) !== color) continue;
    for (const [dr, dc] of directions(piece)) {
      let r = Math.floor(square / 8) + dr, c = square % 8 + dc;
      while (inside(r, c) && board[r * 8 + c] === 0) {
        moves.push({ from: square, path: [r * 8 + c], captures: [] });
        if (Math.abs(piece) !== 2) break;
        r += dr; c += dc;
      }
    }
  }
  return moves;
}

export function previewMove(board: Board, move: Move, steps: number): Board {
  const next = [...board];
  const piece = next[move.from];
  next[move.from] = 0;
  for (const captured of move.captures.slice(0, steps)) next[captured] = 0;
  next[move.path[steps - 1]] = piece;
  return next;
}

export function playMove(game: Game, from: number, path: number[]): Game {
  if (game.winner) throw new Error("یارییەکە کۆتایی هاتووە.");
  const move = legalMoves(game.board, game.turn).find(candidate => candidate.from === from && candidate.path.length === path.length && candidate.path.every((square, i) => square === path[i]));
  if (!move) throw new Error("ئەم جووڵەیە ڕێگەپێدراو نییە. ئەگەر خواردن هەبێت، زۆرترین بەرد بخۆ.");
  const board = previewMove(game.board, move, move.path.length);
  const destination = move.path.at(-1)!;
  if (board[destination] === 1 && destination < 8) board[destination] = 2;
  if (board[destination] === -1 && destination >= 56) board[destination] = -2;
  const turn = opposite(game.turn);
  const next: Game = {
    ...game, board, turn, ply: game.ply + 1, lastMove: move,
    history: [...game.history, { color: game.turn, label: [move.from, ...move.path].map(coordinate).join(move.captures.length ? " × " : " → "), captures: move.captures.length }].slice(-100),
    positions: move.captures.length || board[destination] !== game.board[from] || (Math.abs(game.board[from]) === 1 && Math.floor(from / 8) !== Math.floor(destination / 8)) ? {} : { ...game.positions },
  };
  const key = positionKey(board, turn);
  next.positions[key] = (next.positions[key] || 0) + 1;
  if (!board.some(piece => pieceColor(piece) === turn)) { next.winner = game.turn; next.reason = "pieces"; }
  else if (!legalMoves(board, turn).length) { next.winner = game.turn; next.reason = "blocked"; }
  else {
    const white = board.filter(p => p > 0), black = board.filter(p => p < 0);
    if (white.length === 1 && black.length === 1) {
      next.winner = Math.abs(white[0]) === Math.abs(black[0]) ? "draw" : white[0] === 2 ? "white" : "black";
      next.reason = "single-piece";
    } else if (next.positions[key] >= 3) { next.winner = "draw"; next.reason = "repetition"; }
  }
  return next;
}

export function countPieces(board: Board, color: Color) {
  return board.filter(piece => pieceColor(piece) === color).length;
}
