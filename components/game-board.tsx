"use client";

import { useId, useLayoutEffect, useRef, useState, type KeyboardEvent } from "react";
import { Crown } from "lucide-react";
import { coordinate, pieceColor, type Board, type Move, type Piece } from "@/lib/game";
import "./board.css";

export type GameBoardProps = {
  board: Board;
  onSquare: (square: number) => void;
  flipped?: boolean;
  selected?: number | null;
  targets?: Set<number | undefined>;
  movable?: Set<number>;
  lastMove?: Move | null;
  disabled?: boolean;
  decorative?: boolean;
  showCoordinates?: boolean;
  showHints?: boolean;
};

type Token = { id: string; square: number; piece: Piece; captured?: boolean };
const emptyTargets = new Set<number>();
const colorNames = { white: "سپی", black: "ڕەش" };
const tokensFor = (board: Board, generation: number): Token[] => board.flatMap((piece, square) => piece ? [{ id: `${generation}-${square}`, piece, square }] : []);
const visualSquare = (square: number, flipped: boolean) => flipped ? 63 - square : square;

/** Tokens keep their identity between snapshots, so moves animate on the board
 * even when a new server snapshot arrives or a capture is previewed locally. */
export default function GameBoard({
  board,
  onSquare,
  flipped = false,
  selected = null,
  targets = emptyTargets,
  movable = emptyTargets,
  lastMove = null,
  disabled = true,
  decorative = false,
  showCoordinates = true,
  showHints = true,
}: GameBoardProps) {
  const [tokens, setTokens] = useState<Token[]>(() => tokensFor(board, 0));
  const tokensRef = useRef(tokens);
  const previousBoard = useRef([...board]);
  const generation = useRef(0);
  const cleanupTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const cellRefs = useRef(new Map<number, HTMLButtonElement>());
  const [focusedSquare, setFocusedSquare] = useState(board[40] ? 40 : 0);
  const boardId = useId().replace(/[^a-zA-Z0-9_-]/g, "");

  useLayoutEffect(() => {
    const previous = previousBoard.current;
    if (board.every((piece, square) => piece === previous[square])) return;
    previousBoard.current = [...board];
    generation.current++;
    if (cleanupTimer.current) clearTimeout(cleanupTimer.current);

    const current = tokensRef.current.filter(token => !token.captured);
    const changed = board.reduce<number>((total, piece, square) => total + Number(piece !== previous[square]), 0);
    // A new game can replace most of the board at once; it should settle cleanly.
    if (changed > 10) {
      const reset = tokensFor(board, generation.current);
      tokensRef.current = reset;
      setTokens(reset);
      return;
    }

    const stationary = current.filter(token => board[token.square] === token.piece);
    const remaining = current.filter(token => board[token.square] !== token.piece);
    const next = [...stationary];
    for (let square = 0; square < 64; square++) {
      const piece = board[square];
      if (!piece || stationary.some(token => token.square === square)) continue;
      const matching = remaining.filter(token => pieceColor(token.piece) === pieceColor(piece));
      const source = matching.find(token => token.square === lastMove?.from)
        || matching.find(token => token.piece === piece)
        || matching[0];
      if (source) {
        remaining.splice(remaining.indexOf(source), 1);
        next.push({ ...source, square, piece });
      } else next.push({ id: `${generation.current}-${square}`, square, piece });
    }
    const fading = remaining.map(token => ({ ...token, captured: true }));
    tokensRef.current = next;
    setTokens([...next, ...fading]);
    if (fading.length) cleanupTimer.current = setTimeout(() => setTokens(tokensRef.current), 240);
  }, [board, lastMove]);

  useLayoutEffect(() => () => {
    if (cleanupTimer.current) clearTimeout(cleanupTimer.current);
  }, []);

  function focusCell(square: number) {
    setFocusedSquare(square);
    cellRefs.current.get(square)?.focus({ preventScroll: true });
  }

  function keyboard(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    const delta = ({ ArrowLeft: -1, ArrowRight: 1, ArrowUp: -8, ArrowDown: 8 } as Record<string, number>)[event.key];
    let next: number | undefined;
    if (delta !== undefined) {
      next = index + delta;
      if (next < 0 || next > 63 || (Math.abs(delta) === 1 && Math.floor(next / 8) !== Math.floor(index / 8))) return;
    } else if (event.key === "Home") next = event.ctrlKey || event.metaKey ? 0 : Math.floor(index / 8) * 8;
    else if (event.key === "End") next = event.ctrlKey || event.metaKey ? 63 : Math.floor(index / 8) * 8 + 7;
    if (next === undefined) return;
    event.preventDefault();
    focusCell(visualSquare(next, flipped));
  }

  const letters = (flipped ? "hgfedcba" : "abcdefgh").split("");
  const ranks = Array.from({ length: 8 }, (_, i) => flipped ? i + 1 : 8 - i);
  const lastPath = lastMove ? [lastMove.from, ...lastMove.path] : [];
  const pathPoints = lastPath.map(square => {
    const index = visualSquare(square, flipped);
    return `${(index % 8) * 100 + 50},${Math.floor(index / 8) * 100 + 50}`;
  }).join(" ");
  const rovingSquare = focusedSquare;

  return <div
    className={`dama-board board-frame${decorative ? " dama-board--decorative decorative-board" : ""}${!showCoordinates ? " dama-board--no-coordinates" : ""}`}
    dir="ltr"
    data-board-disabled={disabled || undefined}
  >
    <div className="dama-board__coordinates dama-board__coordinates--top" aria-hidden="true">{letters.map(letter => <span key={letter}>{letter}</span>)}</div>
    <div className="dama-board__coordinates dama-board__coordinates--bottom" aria-hidden="true">{letters.map(letter => <span key={letter}>{letter}</span>)}</div>
    <div className="dama-board__coordinates dama-board__coordinates--left" aria-hidden="true">{ranks.map(rank => <span key={rank}>{rank}</span>)}</div>
    <div className="dama-board__coordinates dama-board__coordinates--right" aria-hidden="true">{ranks.map(rank => <span key={rank}>{rank}</span>)}</div>
    <div className="dama-board__surface">
      <div
        className="dama-board__grid board"
        role={decorative ? "img" : "grid"}
        aria-label="تەختەی دامە"
        aria-readonly={decorative ? undefined : disabled}
        aria-rowcount={decorative ? undefined : 8}
        aria-colcount={decorative ? undefined : 8}
        aria-describedby={decorative ? undefined : `${boardId}-instructions`}
      >
        {Array.from({ length: 8 }, (_, row) => <div key={row} className="dama-board__row" role={decorative ? undefined : "row"} aria-rowindex={decorative ? undefined : row + 1}>
          {Array.from({ length: 8 }, (_, col) => {
            const visualIndex = row * 8 + col;
            const square = visualSquare(visualIndex, flipped);
            const piece = board[square];
            const color = pieceColor(piece);
            const isTarget = targets.has(square);
            const isMovable = movable.has(square);
            const lastDestination = square === lastMove?.path.at(-1);
            const className = [
              "dama-board__cell",
              (Math.floor(square / 8) + square % 8) % 2 ? "dama-board__cell--dark" : "dama-board__cell--light",
              square === selected && "dama-board__cell--selected",
              lastPath.includes(square) && "dama-board__cell--last",
              isTarget && showHints && "dama-board__cell--target",
              isMovable && showHints && "dama-board__cell--movable",
            ].filter(Boolean).join(" ");
            const content = <>
              {isTarget && showHints && <span className="dama-board__target" aria-hidden="true" />}
              {isMovable && showHints && selected === null && <span className="dama-board__movable" aria-hidden="true" />}
              {lastDestination && <span className="dama-board__last-corner" aria-hidden="true" />}
              {square === lastMove?.from && !piece && <span className="dama-board__origin" aria-hidden="true" />}
            </>;
            if (decorative) return <span key={square} className={className}>{content}</span>;
            return <button
              key={square}
              ref={element => { if (element) cellRefs.current.set(square, element); else cellRefs.current.delete(square); }}
              type="button"
              className={className}
              role="gridcell"
              aria-colindex={col + 1}
              aria-selected={square === selected}
              aria-disabled={disabled}
              aria-label={`${coordinate(square)}: ${piece ? `${colorNames[color!]} ${Math.abs(piece) === 2 ? "دامە" : "بەرد"}` : "بەتاڵ"}${isTarget ? "، جووڵەی ڕێگەپێدراو" : ""}`}
              tabIndex={square === rovingSquare ? 0 : -1}
              onFocus={() => setFocusedSquare(square)}
              onClick={() => { setFocusedSquare(square); if (!disabled) onSquare(square); }}
              onKeyDown={event => keyboard(event, visualIndex)}
              data-square={square}
            >{content}</button>;
          })}
        </div>)}
      </div>
      {lastPath.length > 1 && <svg className="dama-board__path" viewBox="0 0 800 800" aria-hidden="true"><polyline points={pathPoints} /></svg>}
      <div className="dama-board__pieces" aria-hidden="true">{tokens.map(token => {
        const index = visualSquare(token.square, flipped);
        const color = pieceColor(token.piece);
        return <span key={token.id} className={`dama-token${token.captured ? " dama-token--captured" : ""}${token.square === selected ? " dama-token--selected" : ""}`} style={{ left: `${(index % 8) * 12.5}%`, top: `${Math.floor(index / 8) * 12.5}%` }}>
          <span className={`dama-piece dama-piece--${color}${Math.abs(token.piece) === 2 ? " dama-piece--king" : ""}`}>
            <span className="dama-piece__ring" />
            {Math.abs(token.piece) === 2 ? <Crown className="dama-piece__crown" size={25} strokeWidth={1.65} /> : <span className="dama-piece__seal" />}
          </span>
        </span>;
      })}</div>
    </div>
    <span className="dama-board__inlay" aria-hidden="true" />
    {!decorative && <span id={`${boardId}-instructions`} className="dama-board__sr-only">بە تیرەکان لە خانەکان بگەڕێ. بە ئینتەر یان بۆشایی بەردێک هەڵبژێرە و شوێنی جووڵە دیاری بکە. Home و End بۆ سەرەتا و کۆتایی ڕیز بەکاربهێنە.</span>}
  </div>;
}
