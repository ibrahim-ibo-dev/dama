"use client";

import { useEffect, useRef, useState } from "react";
import { ArrowUpLeft, Layers3, LoaderCircle, RotateCcw, Sparkles, Target } from "lucide-react";
import { coordinate, legalMoves, type Board, type Color, type Move } from "@/lib/game";
import type { BotAnalysis } from "@/lib/bot";
import Modal from "./modal";
import useBot, { isBotCancelled } from "./use-bot";
import "./private-coach.css";

export type PrivateCoachProps = {
  open: boolean;
  onClose: () => void;
  board: Board;
  color: Color;
  canPlay: boolean;
  onPlay: (move: Move) => void;
};
const numerals = (value: number | string) => String(value).replace(/\d/g, digit => "٠١٢٣٤٥٦٧٨٩"[Number(digit)]);
type Suggestion = { position: string; analysis: BotAnalysis };

export default function PrivateCoach({ open, onClose, board, color, canPlay, onPlay }: PrivateCoachProps) {
  const { analyze, cancel, thinking } = useBot();
  const [suggestion, setSuggestion] = useState<Suggestion | null>(null);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  const position = `${color}:${board.join(",")}`;
  const latest = useRef({ open, canPlay, position, board, color });
  latest.current = { open, canPlay, position, board, color };

  useEffect(() => {
    cancel();
    setSuggestion(null);
    setError("");
    if (!open || !canPlay) return;
    let current = true;
    const snapshot = latest.current;
    void analyze([...snapshot.board], snapshot.color, "hard").then(analysis => {
      if (!current || !latest.current.open || !latest.current.canPlay || latest.current.position !== snapshot.position) return;
      setSuggestion({ position: snapshot.position, analysis });
    }).catch(reason => {
      if (!current || isBotCancelled(reason)) return;
      setError("هەڵسەنگاندن سەرکەوتوو نەبوو. دووبارە هەوڵ بدەوە.");
    });
    return () => { current = false; cancel(); };
  }, [open, canPlay, position, retry, analyze, cancel]);

  if (!open) return null;
  const current = suggestion?.position === position ? suggestion.analysis : null;
  const move = current?.move;
  const searching = thinking || (canPlay && !current && !error);

  function playSuggestion() {
    const state = latest.current;
    if (!state.open || !state.canPlay || thinking || !suggestion || suggestion.position !== state.position || !suggestion.analysis.move) return;
    const proposed = suggestion.analysis.move;
    const legal = legalMoves(state.board, state.color).find(candidate => candidate.from === proposed.from && candidate.path.length === proposed.path.length && candidate.path.every((square, i) => square === proposed.path[i]));
    if (!legal) { setSuggestion(null); setRetry(value => value + 1); return; }
    cancel();
    onPlay(legal);
    onClose();
  }

  return <Modal title="یارمەتیدەری تایبەت" onClose={() => { cancel(); onClose(); }} className="private-coach">
    <p className="private-coach__intro">تەختەکە هەڵدەسەنگێنێت و جووڵەیەکی بەهێز پێشنیار دەکات.</p>
    <div className={`private-coach__result${searching ? " private-coach__result--thinking" : ""}`} aria-live="polite" aria-busy={searching}>
      <span className="private-coach__emblem">{searching ? <LoaderCircle className="spin" size={25} /> : <Sparkles size={25} />}</span>
      {!canPlay ? <><h3>چاوەڕوانی نۆرەی تۆیە</h3><p>کاتێک نۆرەت هات، پێشنیارەکە ئامادە دەبێت.</p></> : searching ? <><h3>لە جووڵەکان ورد دەبێتەوە…</h3><p>چەند نۆرەی داهاتوو هەڵدەسەنگێنێت.</p></> : error ? <><h3>دووبارە هەوڵ بدەوە</h3><p>{error}</p></> : move ? <><span className="private-coach__label">بەهێزترین پێشنیاری دۆزراوە</span><h3 className="private-coach__move latin" dir="ltr">{[move.from, ...move.path].map(coordinate).join(move.captures.length ? " × " : " → ")}</h3><p>{move.captures.length ? `${numerals(move.captures.length)} بەرد دەخوات` : "جووڵەیەکی بەبێ خواردن"}</p></> : <><h3>جووڵەیەکی ڕێگەپێدراو نییە</h3><p>دۆخی یارییەکە بپشکنە.</p></>}
    </div>
    {current && move && !thinking && <div className="private-coach__metrics"><div><Target size={16} /><span>بەردی خوراو</span><strong>{numerals(move.captures.length)}</strong></div><div><Layers3 size={16} /><span>قووڵایی گەڕان</span><strong>{numerals(current.depth)}</strong></div><div><Sparkles size={16} /><span>دۆخی هەڵسەنگێنراو</span><strong>{numerals(current.nodes.toLocaleString("en-US"))}</strong></div></div>}
    <div className="private-coach__actions"><button type="button" className="primary-button" disabled={!canPlay || thinking || !move || suggestion?.position !== position} onClick={playSuggestion}>ئەم جووڵەیە بکە <ArrowUpLeft size={18} /></button><button type="button" className="secondary-button" disabled={!canPlay || thinking} onClick={() => setRetry(value => value + 1)}><RotateCcw size={16} /> دووبارە هەڵسەنگێنە</button></div>
    <p className="private-coach__note">پێشنیارەکە بە گەڕانێکی سنووردار لەسەر ئەم ئامێرە هەڵسەنگێنراوە.</p>
  </Modal>;
}
