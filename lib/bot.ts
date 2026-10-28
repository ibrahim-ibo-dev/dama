import { legalMoves, opposite, previewMove, type Board, type Color, type Move } from "./game";

export type BotLevel = "easy" | "medium" | "hard";
export type BotAnalysis = { move: Move | null; score: number; depth: number; nodes: number };

const MATE = 100_000;
const MATE_THRESHOLD = MATE - 100;
const STOP = Symbol("search-budget");
const settings = {
  easy: { timeMs: 20, depth: 1, nodes: 1_000, extensions: 0 },
  medium: { timeMs: 250, depth: 5, nodes: 25_000, extensions: 2 },
  hard: { timeMs: 1_000, depth: 8, nodes: 100_000, extensions: 4 },
} as const;

type Counts = { white: number; black: number; whiteKing: boolean; blackKing: boolean };
type Entry = { depth: number; score: number; bound: "exact" | "lower" | "upper"; best: string };
const moveKey = (move: Move) => `${move.from}:${move.path.join(",")}`;
const boardKey = (board: Board, color: Color) => `${board.join(",")}:${color}`;

function randomSource(seed: number) {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b79f5;
    let value = state;
    value = Math.imul(value ^ value >>> 15, value | 1);
    value ^= value + Math.imul(value ^ value >>> 7, value | 61);
    return ((value ^ value >>> 14) >>> 0) / 4_294_967_296;
  };
}

function counts(board: Board): Counts {
  let white = 0, black = 0, whiteKing = false, blackKing = false;
  for (const piece of board) {
    if (piece > 0) { white++; whiteKing ||= piece === 2; }
    else if (piece < 0) { black++; blackKing ||= piece === -2; }
  }
  return { white, black, whiteKing, blackKing };
}

/** Complete a legal turn, including promotion after the last capture. */
function nextBoard(board: Board, move: Move): Board {
  const next = previewMove(board, move, move.path.length);
  const destination = move.path[move.path.length - 1];
  if (next[destination] === 1 && destination < 8) next[destination] = 2;
  else if (next[destination] === -1 && destination >= 56) next[destination] = -2;
  return next;
}

/** This follows playMove's terminal priority: pieces, blocked side, then the
 * single-piece rule. Repetition using previous turns stays with the Game owner;
 * this board-only API cannot know the match's pre-existing repetition history.
 */
function terminal(boardCounts: Counts, color: Color, moves: Move[], ply: number): number | null {
  const mine = boardCounts[color], theirs = boardCounts[opposite(color)];
  if (!mine && !theirs) return 0;
  if (!mine) return -MATE + ply;
  if (!theirs) return MATE - ply;
  if (!moves.length) return -MATE + ply;
  if (mine === 1 && theirs === 1) {
    if (boardCounts.whiteKing === boardCounts.blackKing) return 0;
    const winner: Color = boardCounts.whiteKing ? "white" : "black";
    return winner === color ? MATE - ply : -MATE + ply;
  }
  return null;
}

/** Material is dominant. Advancement, connected men, central squares, and king
 * freedom break otherwise equal choices without changing the legal rules.
 */
function evaluate(board: Board, color: Color, mobility: number): number {
  let whiteScore = 0;
  for (let square = 0; square < 64; square++) {
    const piece = board[square];
    if (!piece) continue;
    const sign = piece > 0 ? 1 : -1;
    const row = Math.floor(square / 8), col = square % 8;
    const center = 3.5 - Math.abs(3.5 - col);
    let value = Math.abs(piece) === 2 ? 350 : 100;
    value += center * (Math.abs(piece) === 2 ? 4 : 2);
    if (Math.abs(piece) === 1) {
      value += (piece > 0 ? 7 - row : row) * 5;
      if (col > 0 && Math.sign(board[square - 1]) === sign) value += 4;
      if (col < 7 && Math.sign(board[square + 1]) === sign) value += 4;
      const behind = square + (piece > 0 ? 8 : -8);
      if (behind >= 0 && behind < 64 && Math.sign(board[behind]) === sign) value += 3;
    } else {
      value += (3.5 - Math.abs(3.5 - row)) * 3;
      for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
        let r = row + dr, c = col + dc;
        while (r >= 0 && r < 8 && c >= 0 && c < 8 && board[r * 8 + c] === 0) { value += 1.3; r += dr; c += dc; }
      }
    }
    whiteScore += sign * value;
  }
  return Math.round((color === "white" ? whiteScore : -whiteScore) + Math.min(mobility, 32) * .7);
}

function rankMove(board: Board, move: Move): number {
  const piece = board[move.from], destination = move.path[move.path.length - 1];
  let score = move.captures.reduce((total, square) => total + (Math.abs(board[square]) === 2 ? 350 : 100), 0) * 10;
  if ((piece === 1 && destination < 8) || (piece === -1 && destination >= 56)) score += 700;
  const fromRow = Math.floor(move.from / 8), toRow = Math.floor(destination / 8);
  if (Math.abs(piece) === 1) score += (piece > 0 ? fromRow - toRow : toRow - fromRow) * 7;
  score += (3.5 - Math.abs(3.5 - destination % 8)) * 2;
  return score;
}

/** Run this synchronous search in a Worker. The search is bounded by both a
 * cooperative clock deadline and a node cap. Iterative deepening retains only
 * completed iterations, so an interrupted search still returns a legal move.
 * Easy intentionally samples legal moves; medium/hard are heuristic opponents,
 * not a solved or optimal strategy. Scores are from the requested color's view.
 */
export function chooseBotMove(
  board: Board,
  color: Color,
  level: BotLevel,
  options: { timeMs?: number; seed?: number } = {},
): BotAnalysis {
  const config = settings[level];
  const start = performance.now();
  const suppliedTime = options.timeMs;
  const budget = Math.max(0, Math.min(Number.isFinite(suppliedTime) ? suppliedTime! : config.timeMs, 2_000));
  const deadline = start + budget;
  const random = randomSource(options.seed ?? Math.floor(Math.random() * 4_294_967_296));
  const rootMoves = legalMoves(board, color);
  const ended = terminal(counts(board), color, rootMoves, 0);
  if (ended !== null) return { move: null, score: ended, depth: 0, nodes: 1 };

  const priorities = new Map(rootMoves.map(move => [moveKey(move), random()]));
  const ordered = (position: Board, moves: Move[], preferred?: string, root = false) => moves
    .map(move => ({ move, rank: (moveKey(move) === preferred ? 1_000_000 : 0) + rankMove(position, move) + (root ? priorities.get(moveKey(move)) || 0 : 0) }))
    .sort((a, b) => b.rank - a.rank).map(entry => entry.move);
  let rootOrder = ordered(board, rootMoves, undefined, true);
  let chosen = level === "easy" && random() < .8 ? rootMoves[Math.floor(random() * rootMoves.length)] : rootOrder[0];
  const fallbackBoard = nextBoard(board, chosen), fallbackMoves = legalMoves(fallbackBoard, opposite(color));
  let bestScore = -(terminal(counts(fallbackBoard), opposite(color), fallbackMoves, 1) ?? evaluate(fallbackBoard, opposite(color), fallbackMoves.length));
  let nodes = 2, completedDepth = 0;
  if (level === "easy") return { move: chosen, score: bestScore, depth: 1, nodes };
  if (rootMoves.length === 1) return { move: chosen, score: bestScore, depth: 1, nodes };

  const table = new Map<string, Entry>();
  function visit() {
    if (nodes >= config.nodes || performance.now() >= deadline) throw STOP;
    nodes++;
  }
  // Normalize mate distances in the table, since a transposition may be reached
  // at a different root distance in a later iteration.
  const toTable = (score: number, ply: number) => score > MATE_THRESHOLD ? score + ply : score < -MATE_THRESHOLD ? score - ply : score;
  const fromTable = (score: number, ply: number) => score > MATE_THRESHOLD ? score - ply : score < -MATE_THRESHOLD ? score + ply : score;

  function search(position: Board, turn: Color, depth: number, alpha: number, beta: number, ply: number, extensions: number): number {
    visit();
    const moves = legalMoves(position, turn);
    const end = terminal(counts(position), turn, moves, ply);
    if (end !== null) return end;
    const extending = depth <= 0 && extensions > 0 && moves[0].captures.length > 0;
    if (depth <= 0 && !extending) return evaluate(position, turn, moves.length);
    const key = depth > 0 ? boardKey(position, turn) : "";
    const cached = key ? table.get(key) : undefined;
    if (cached && cached.depth >= depth) {
      const score = fromTable(cached.score, ply);
      if (cached.bound === "exact") return score;
      if (cached.bound === "lower") alpha = Math.max(alpha, score);
      else beta = Math.min(beta, score);
      if (alpha >= beta) return score;
    }
    const originalAlpha = alpha, originalBeta = beta;
    let value = -Infinity, best = "";
    for (const move of ordered(position, moves, cached?.best)) {
      const score = -search(nextBoard(position, move), opposite(turn), Math.max(0, depth - 1), -beta, -alpha, ply + 1, extending ? extensions - 1 : extensions);
      if (score > value) { value = score; best = moveKey(move); }
      alpha = Math.max(alpha, score);
      if (alpha >= beta) break;
    }
    if (key && table.size < 25_000) table.set(key, {
      depth, score: toTable(value, ply), best,
      bound: value <= originalAlpha ? "upper" : value >= originalBeta ? "lower" : "exact",
    });
    return value;
  }

  for (let depth = 1; depth <= config.depth; depth++) {
    let iterationMove = rootOrder[0], iterationScore = -Infinity, alpha = -Infinity;
    try {
      for (const move of rootOrder) {
        const score = -search(nextBoard(board, move), opposite(color), depth - 1, -Infinity, -alpha, 1, config.extensions);
        if (score > iterationScore) { iterationScore = score; iterationMove = move; }
        alpha = Math.max(alpha, score);
      }
    } catch (error) {
      if (error !== STOP) throw error;
      break;
    }
    chosen = iterationMove; bestScore = iterationScore; completedDepth = depth;
    rootOrder = ordered(board, rootMoves, moveKey(chosen), true);
    if (bestScore > MATE_THRESHOLD) break;
  }
  return { move: chosen, score: bestScore, depth: completedDepth, nodes };
}
