import { chooseBotMove, type BotAnalysis, type BotLevel } from "@/lib/bot";
import type { Board, Color } from "@/lib/game";

export type BotWorkerRequest = { id: number; board: Board; color: Color; level: BotLevel };
export type BotWorkerResponse =
  | { id: number; ok: true; analysis: BotAnalysis }
  | { id: number; ok: false; error: string };

const workerScope = self as unknown as {
  onmessage: ((event: MessageEvent<BotWorkerRequest>) => void) | null;
  postMessage: (response: BotWorkerResponse) => void;
};
const searchBudgets: Record<BotLevel, number> = { easy: 30, medium: 300, hard: 1100 };

workerScope.onmessage = ({ data }) => {
  try {
    const analysis = chooseBotMove(data.board, data.color, data.level, { timeMs: searchBudgets[data.level] });
    workerScope.postMessage({ id: data.id, ok: true, analysis });
  } catch (error) {
    workerScope.postMessage({ id: data.id, ok: false, error: error instanceof Error ? error.message : "Bot analysis failed" });
  }
};
