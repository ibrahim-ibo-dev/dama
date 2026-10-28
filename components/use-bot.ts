"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { BotAnalysis, BotLevel } from "@/lib/bot";
import type { Board, Color } from "@/lib/game";
import type { BotWorkerRequest, BotWorkerResponse } from "./bot.worker";

export class BotCancelledError extends Error {
  constructor() { super("Bot analysis was cancelled"); this.name = "AbortError"; }
}
export const isBotCancelled = (error: unknown): boolean => error instanceof Error && error.name === "AbortError";

type Job = {
  id: number;
  worker: Worker | null;
  timer: ReturnType<typeof setTimeout> | null;
  watchdog: ReturnType<typeof setTimeout> | null;
  reject: (error: Error) => void;
};

function disposeJob(job: Job) {
  if (job.worker) {
    job.worker.onmessage = null;
    job.worker.onerror = null;
    job.worker.onmessageerror = null;
    job.worker.terminate();
    job.worker = null;
  }
  if (job.timer !== null) clearTimeout(job.timer);
  if (job.watchdog !== null) clearTimeout(job.watchdog);
}

/** Each hook owns its worker and aborts old jobs before starting a new one.
 * A solo opponent and the private coach can therefore search independently. */
export function useBot(): {
  analyze: (board: Board, color: Color, level: BotLevel) => Promise<BotAnalysis>;
  cancel: () => void;
  thinking: boolean;
} {
  const mounted = useRef(true);
  const sequence = useRef(0);
  const activeJob = useRef<Job | null>(null);
  const [thinking, setThinking] = useState(false);

  const cancel = useCallback(() => {
    const job = activeJob.current;
    activeJob.current = null;
    if (job) { disposeJob(job); job.reject(new BotCancelledError()); }
    if (mounted.current) setThinking(false);
  }, []);

  useEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; cancel(); };
  }, [cancel]);

  const analyze = useCallback((board: Board, color: Color, level: BotLevel): Promise<BotAnalysis> => {
    cancel();
    if (!mounted.current) return Promise.reject(new BotCancelledError());
    setThinking(true);
    const snapshot = [...board];
    const id = ++sequence.current;

    return new Promise<BotAnalysis>((resolve, reject) => {
      const job: Job = { id, worker: null, timer: null, watchdog: null, reject };
      activeJob.current = job;

      const finish = (analysis?: BotAnalysis, error?: Error) => {
        if (activeJob.current !== job) return;
        activeJob.current = null;
        disposeJob(job);
        if (mounted.current) setThinking(false);
        if (error) reject(error);
        else if (analysis) resolve(analysis);
      };

      let fallbackStarted = false;
      const fallback = () => {
        if (activeJob.current !== job || fallbackStarted) return;
        fallbackStarted = true;
        disposeJob(job);
        // Give the UI a paint before a tightly bounded main-thread fallback.
        job.timer = setTimeout(() => {
          void (async () => {
            try {
              const { chooseBotMove } = await import("@/lib/bot");
              if (!mounted.current || activeJob.current !== job) return;
              const analysis = chooseBotMove(snapshot, color, level, { timeMs: level === "easy" ? 20 : 100 });
              if (!mounted.current || activeJob.current !== job) return;
              finish(analysis);
            } catch (error) {
              finish(undefined, error instanceof Error ? error : new Error("هەڵسەنگاندن سەرکەوتوو نەبوو."));
            }
          })();
        }, 40);
      };

      if (typeof Worker === "undefined") { fallback(); return; }
      try {
        const worker = new Worker(new URL("./bot.worker.ts", import.meta.url), { type: "module" });
        job.worker = worker;
        worker.onmessage = ({ data }: MessageEvent<BotWorkerResponse>) => {
          if (activeJob.current !== job || data.id !== id) return;
          if (data.ok) finish(data.analysis);
          else fallback();
        };
        worker.onerror = event => { event.preventDefault(); fallback(); };
        worker.onmessageerror = fallback;
        const request: BotWorkerRequest = { id, board: snapshot, color, level };
        worker.postMessage(request);
        job.watchdog = setTimeout(fallback, level === "hard" ? 6500 : 4500);
      } catch { fallback(); }
    });
  }, [cancel]);

  return { analyze, cancel, thinking };
}

export default useBot;
