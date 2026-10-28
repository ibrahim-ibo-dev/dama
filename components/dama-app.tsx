"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { ArrowLeft, Bot, Check, CheckCheck, CircleHelp, Copy, Crown, Expand, Flag, Handshake, LoaderCircle, LogOut, Moon, RotateCcw, Settings2, ShieldCheck, Sparkles, Sun, Undo2, Users, Volume2, VolumeX, WifiOff, X } from "lucide-react";
import { countPieces, legalMoves, newGame, opposite, pieceColor, playMove, previewMove, type Color, type Game } from "@/lib/game";
import type { PublicRoom, Role, RoomAction } from "@/lib/types";
import type { BotLevel } from "@/lib/bot";
import GameBoard from "./game-board";
import BoardFocus from "./board-focus";
import Lobby from "./lobby";
import Modal from "./modal";
import PreferencesDialog, { defaultPreferences, type Preferences } from "./preferences-dialog";
import RoomSidebar from "./room-sidebar";
import RulesDialog from "./rules-dialog";
import PrivateCoach from "./private-coach";
import { useBot } from "./use-bot";

type Status = { mode: "local" | "redis" | "unconfigured"; passwordRequired: boolean };
type Selection = { from: number; path: number[] } | null;
const number = (value: number) => String(value).replace(/\d/g, n => "٠١٢٣٤٥٦٧٨٩"[+n]);
const normalizeCode = (value: string) => value.toUpperCase().replace(/[^A-Z2-9]/g, "").slice(0, 10);
const inviteUrl = (code: string) => window.location.origin + "/?room=" + code;

async function api<T>(url: string, token: string, method = "GET", body?: unknown): Promise<T> {
  const response = await fetch(url, {
    method, cache: "no-store", headers: { "Content-Type": "application/json", "x-player-token": token },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(15000),
  });
  const data = await response.json().catch(() => ({ error: "سێرڤەر وەڵامی دروستی نەدایەوە. دووبارە هەوڵ بدەوە." }));
  if (!response.ok) throw Object.assign(new Error(data.error || "پەیوەندی بە سێرڤەر نەکرا."), { status: response.status });
  return data as T;
}
function messageFor(error: unknown) {
  return error instanceof Error && !["TypeError", "TimeoutError", "AbortError"].includes(error.name) ? error.message : "پەیوەندی پچڕا. ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵ بدەوە.";
}

export default function DamaApp() {
  const [token, setToken] = useState("");
  const [status, setStatus] = useState<Status | null>(null);
  const [name, setName] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [tab, setTab] = useState<"create" | "join" | "bot">("create");
  const [joinRole, setJoinRole] = useState<"player" | "spectator">("player");
  const [room, setRoom] = useState<PublicRoom | null>(null);
  const [practice, setPractice] = useState<Game | null>(null);
  const [practiceHistory, setPracticeHistory] = useState<Game[]>([]);
  const [practiceMode, setPracticeMode] = useState<"practice" | "bot">("practice");
  const [botLevel, setBotLevel] = useState<BotLevel>("medium");
  const [botRetry, setBotRetry] = useState(0);
  const [coachEnabled, setCoachEnabled] = useState(false);
  const [coachOpen, setCoachOpen] = useState(false);
  const [selection, setSelection] = useState<Selection>(null);
  const [busy, setBusy] = useState(false);
  const [chatBusy, setChatBusy] = useState(false);
  const [restoring, setRestoring] = useState(true);
  const [error, setError] = useState("");
  const [connected, setConnected] = useState(true);
  const [rules, setRules] = useState(false);
  const [settings, setSettings] = useState(false);
  const [confirm, setConfirm] = useState<"resign" | "leave" | "reset" | null>(null);
  const [preferences, setPreferences] = useState<Preferences>(defaultPreferences);
  const [copied, setCopied] = useState(false);
  const [toast, setToast] = useState("");
  const [flipped, setFlipped] = useState(false);
  const [boardOnly, setBoardOnly] = useState(false);
  const [shareAvailable, setShareAvailable] = useState(false);
  const roomRef = useRef(room);
  const preferencesRef = useRef(preferences);
  const audioRef = useRef<AudioContext | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const copyTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mutationRef = useRef(false);
  const roomEpoch = useRef(0);
  const coachHoldTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const { analyze: analyzeBot, cancel: cancelBot, thinking: botThinking } = useBot();
  roomRef.current = room;
  preferencesRef.current = preferences;

  const notify = useCallback((text: string) => {
    setToast(text);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(""), 3200);
  }, []);

  const beep = useCallback((finish = false) => {
    if (!preferencesRef.current.sound) return;
    try {
      const context = audioRef.current ??= new AudioContext();
      void context.resume();
      const tones = finish ? [440, 554.37, 659.25] : [390];
      tones.forEach((frequency, i) => {
        const oscillator = context.createOscillator(), gain = context.createGain(), start = context.currentTime + i * .09;
        oscillator.type = "sine"; oscillator.frequency.setValueAtTime(frequency, start);
        gain.gain.setValueAtTime(.045, start); gain.gain.exponentialRampToValueAtTime(.001, start + .15);
        oscillator.connect(gain); gain.connect(context.destination); oscillator.start(start); oscillator.stop(start + .16);
      });
    } catch { /* Sound is optional and needs a browser gesture. */ }
  }, []);

  const acceptRoom = useCallback((next: PublicRoom, context?: { code: string; epoch: number }) => {
    if (context && (roomRef.current?.code !== context.code || roomEpoch.current !== context.epoch)) return;
    const previous = roomRef.current;
    setConnected(true);
    if (previous?.code === next.code && previous.revision >= next.revision) return;
    if (previous?.code === next.code) {
      if (!previous.started && next.started) notify("هاوڕێکەت پەیوەست بوو؛ با یاری دەست پێ بکات.");
      if (previous.game.ply !== next.game.ply || previous.game.id !== next.game.id) { setSelection(null); beep(Boolean(next.game.winner)); }
      else if (!previous.game.winner && next.game.winner) beep(true);
      if (previous.game.id !== next.game.id) { setFlipped(false); notify("یارییەکی نوێ دەستی پێکرد؛ ڕەنگەکان گۆڕدران."); }
    }
    roomRef.current = next; setRoom(next);
  }, [beep, notify]);

  const refreshStatus = useCallback(async (identity: string) => {
    try { setStatus(await api<Status>("/api/status", identity)); setError(""); }
    catch (error) { setError(messageFor(error)); }
  }, []);

  useEffect(() => {
    let cancelled = false;
    async function initialize() {
      let identity = "";
      try {
        identity = sessionStorage.getItem("dama-token") || crypto.randomUUID();
        sessionStorage.setItem("dama-token", identity);
        setName(localStorage.getItem("dama-name") || "");
        const savedLevel = localStorage.getItem("dama-bot-level");
        if (savedLevel === "easy" || savedLevel === "medium" || savedLevel === "hard") setBotLevel(savedLevel);
        setCoachEnabled(localStorage.getItem("dama-private-coach") === "enabled");
        const legacySound = localStorage.getItem("dama-sound") !== "off";
        setPreferences(previous => ({ ...previous, sound: legacySound }));
        const saved = JSON.parse(localStorage.getItem("dama-preferences") || "null");
        if (saved && typeof saved === "object") setPreferences({
          theme: saved.theme === "dark" ? "dark" : "light",
          board: ["walnut", "olive", "slate"].includes(saved.board) ? saved.board : "walnut",
          sound: typeof saved.sound === "boolean" ? saved.sound : legacySound,
          coordinates: typeof saved.coordinates === "boolean" ? saved.coordinates : true,
          hints: typeof saved.hints === "boolean" ? saved.hints : true,
        });
      } catch { identity ||= crypto.randomUUID(); }
      setToken(identity);
      setShareAvailable(typeof navigator.share === "function");
      const queryCode = normalizeCode(new URLSearchParams(window.location.search).get("room") || "");
      if (queryCode) { setCode(queryCode); setTab("join"); }
      try { const next = await api<Status>("/api/status", identity); if (!cancelled) setStatus(next); }
      catch (error) { if (!cancelled) setError(messageFor(error)); }
      let savedCode = "";
      try { savedCode = sessionStorage.getItem("dama-room") || ""; } catch { /* Optional storage. */ }
      const restoreCode = queryCode || savedCode;
      if (restoreCode.length === 10) {
        try {
          const next = await api<PublicRoom>("/api/rooms/" + restoreCode, identity);
          if (!cancelled) {
            acceptRoom(next);
            try { sessionStorage.setItem("dama-room", next.code); } catch { /* Optional storage. */ }
            window.history.replaceState(null, "", "/?room=" + next.code);
          }
        } catch (error) {
          if (!cancelled) {
            const http = error as Error & { status?: number };
            if (http.status !== 403 && http.status !== 404) setError(messageFor(error));
            setCode(restoreCode); setTab("join");
          }
        }
      }
      if (!cancelled) setRestoring(false);
    }
    void initialize();
    return () => { cancelled = true; };
  }, [acceptRoom]);

  useEffect(() => { document.documentElement.dataset.theme = preferences.theme; }, [preferences.theme]);
  function updatePreferences(next: Preferences) {
    setPreferences(next);
    try { localStorage.setItem("dama-preferences", JSON.stringify(next)); } catch { /* Preferences work without storage. */ }
  }

  useEffect(() => {
    if (!room || !token) return;
    const roomCode = room.code;
    let stopped = false, polling = false, lastHeartbeat = 0;
    let timer: ReturnType<typeof setTimeout>;
    async function poll() {
      if (stopped || polling) return;
      if (document.visibilityState === "hidden") { timer = setTimeout(poll, 5000); return; }
      polling = true;
      const context = { code: roomCode, epoch: roomEpoch.current };
      try {
        const heartbeat = Date.now() - lastHeartbeat > 20000;
        const next = await api<PublicRoom>("/api/rooms/" + roomCode, token, heartbeat ? "PATCH" : "GET", heartbeat ? { type: "heartbeat" } : undefined);
        if (heartbeat) lastHeartbeat = Date.now();
        if (!stopped) acceptRoom(next, context);
      } catch { if (!stopped && roomRef.current?.code === context.code && roomEpoch.current === context.epoch) setConnected(false); }
      polling = false;
      if (!stopped) timer = setTimeout(poll, roomRef.current?.game.winner ? 4000 : 2000);
    }
    const wake = () => { clearTimeout(timer); if (!stopped) timer = setTimeout(poll, 100); };
    const offline = () => setConnected(false);
    timer = setTimeout(poll, 800);
    window.addEventListener("online", wake); window.addEventListener("offline", offline); document.addEventListener("visibilitychange", wake);
    return () => { stopped = true; clearTimeout(timer); window.removeEventListener("online", wake); window.removeEventListener("offline", offline); document.removeEventListener("visibilitychange", wake); };
  }, [room?.code, token, acceptRoom]);

  useEffect(() => () => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    if (copyTimer.current) clearTimeout(copyTimer.current);
    if (coachHoldTimer.current) clearTimeout(coachHoldTimer.current);
    void audioRef.current?.close();
  }, []);

  const me = room?.members.find(member => member.id === room.me);
  const game = practice || room?.game || null;
  const role: Role = practice ? "white" : me?.role || "spectator";
  const myColor: Color = role === "black" ? "black" : "white";
  const otherColor = opposite(myColor);
  const soloBot = Boolean(practice && practiceMode === "bot");
  const canPlay = Boolean(game && !game.winner && !busy && (practice ? practiceMode !== "bot" || practice.turn === "white" : room?.started && connected && role === game.turn));
  const moves = useMemo(() => game && !game.winner ? legalMoves(game.board, game.turn) : [], [game?.board, game?.turn, game?.winner]);
  const candidates = selection ? moves.filter(move => move.from === selection.from && selection.path.every((square, i) => move.path[i] === square)) : [];
  const displayBoard = selection?.path.length && candidates[0] && game ? previewMove(game.board, candidates[0], selection.path.length) : game?.board;
  const targets = new Set(candidates.map(move => move.path[selection?.path.length || 0]));
  const activeSquare = selection ? selection.path.at(-1) ?? selection.from : null;

  useEffect(() => {
    if (!practice || practiceMode !== "bot" || practice.turn !== "black" || practice.winner) return;
    const snapshot = practice;
    let active = true;
    const timer = setTimeout(() => {
      void analyzeBot(snapshot.board, "black", botLevel).then(analysis => {
        if (!active || !analysis.move) return;
        const move = analysis.move;
        const next = playMove(snapshot, move.from, move.path);
        setPracticeHistory(history => [...history, snapshot].slice(-80));
        setPractice(current => current?.id === snapshot.id && current.ply === snapshot.ply ? next : current);
        beep(Boolean(next.winner));
      }).catch(error => {
        if (active && !(error instanceof Error && error.name === "AbortError")) setError("بۆتەکە جووڵەکەی تەواو نەکرد. دووبارە هەوڵ بدەوە.");
      });
    }, 300);
    return () => { active = false; clearTimeout(timer); cancelBot(); };
  }, [practice?.id, practice?.ply, practiceMode, botLevel, botRetry, analyzeBot, cancelBot, beep]);

  const activateCoach = useCallback(() => {
    if (mutationRef.current) return;
    setCoachEnabled(true);
    try { localStorage.setItem("dama-private-coach", "enabled"); } catch { /* Private to this browser session. */ }
    if (game && role !== "spectator") { setBoardOnly(false); setSettings(false); setRules(false); setConfirm(null); setCoachOpen(true); }
    else notify("یارمەتیدەری تایبەت چالاک کرا؛ لە ناو یارییەکدا Alt + Shift + B دابگرە.");
  }, [game?.id, role, notify]);
  useEffect(() => {
    const shortcut = (event: KeyboardEvent) => {
      if (event.altKey && event.shiftKey && event.code === "KeyB" && !event.repeat) { event.preventDefault(); activateCoach(); }
    };
    window.addEventListener("keydown", shortcut);
    return () => window.removeEventListener("keydown", shortcut);
  }, [activateCoach]);
  function armCoach() { if (coachHoldTimer.current) clearTimeout(coachHoldTimer.current); coachHoldTimer.current = setTimeout(activateCoach, 1500); }
  function stopCoachHold() { if (coachHoldTimer.current) clearTimeout(coachHoldTimer.current); }

  function playCoachMove(move: { from: number; path: number[] }) {
    if (!game || !canPlay) return;
    setCoachOpen(false); setSelection(null);
    if (practice) {
      try { const next = playMove(practice, move.from, move.path); setPracticeHistory(history => [...history, practice].slice(-80)); setPractice(next); beep(Boolean(next.winner)); }
      catch { setError("دۆخی یاری گۆڕاوە؛ جارێکی تر جووڵەکە هەڵبسەنگێنە."); }
    } else void action({ type: "move", from: move.from, path: move.path, gameId: game.id, ply: game.ply });
  }

  async function enterRoom(event: React.FormEvent) {
    event.preventDefault();
    if (tab === "bot") { startPractice("bot"); return; }
    if (!token || mutationRef.current) return;
    mutationRef.current = true; setBusy(true); setError("");
    try {
      const next = await api<PublicRoom>(tab === "create" ? "/api/rooms" : "/api/rooms/" + normalizeCode(code), token, "POST", { name, password, role: joinRole });
      roomEpoch.current++;
      acceptRoom(next); setSelection(null); setFlipped(false);
      try { localStorage.setItem("dama-name", name.trim()); sessionStorage.setItem("dama-room", next.code); } catch { /* Optional storage. */ }
      window.history.replaceState(null, "", "/?room=" + next.code);
      window.scrollTo({ top: 0 });
      if (!next.started) notify("ڕوومەکەت ئامادەیە. لینکەکە بۆ هاوڕێکەت بنێرە.");
    } catch (error) { setError(messageFor(error)); }
    finally { mutationRef.current = false; setBusy(false); }
  }

  async function action(body: RoomAction) {
    const current = roomRef.current;
    if (!current || mutationRef.current) return;
    mutationRef.current = true; setBusy(true); setError("");
    try { acceptRoom(await api<PublicRoom>("/api/rooms/" + current.code, token, "PATCH", body)); }
    catch (error) {
      setError(messageFor(error)); setSelection(null);
      try { acceptRoom(await api<PublicRoom>("/api/rooms/" + current.code, token)); } catch { setConnected(false); }
    } finally { mutationRef.current = false; setBusy(false); }
  }

  async function sendMessage(text: string) {
    if (!room || chatBusy) return false;
    const context = { code: room.code, epoch: roomEpoch.current };
    setChatBusy(true);
    try { const next = await api<PublicRoom>("/api/rooms/" + room.code, token, "PATCH", { type: "message", text }); acceptRoom(next, context); return true; }
    catch (error) { if (roomRef.current?.code === context.code && roomEpoch.current === context.epoch) setError(messageFor(error)); return false; }
    finally { setChatBusy(false); }
  }

  function clickSquare(square: number) {
    if (!canPlay || !game) return;
    if (selection && targets.has(square)) {
      const path = [...selection.path, square];
      const complete = candidates.find(move => move.path.length === path.length && move.path[path.length - 1] === square);
      if (complete) {
        setSelection(null);
        if (practice) { setPracticeHistory(history => [...history, practice].slice(-80)); const next = playMove(practice, selection.from, path); setPractice(next); beep(Boolean(next.winner)); }
        else void action({ type: "move", from: selection.from, path, ply: game.ply, gameId: game.id });
      } else { setSelection({ ...selection, path }); beep(); }
    } else if (!selection?.path.length && pieceColor(game.board[square]) === game.turn && moves.some(move => move.from === square)) {
      setSelection(selection?.from === square ? null : { from: square, path: [] });
    }
  }

  function startPractice(mode: "practice" | "bot" = practiceMode) { if (mutationRef.current) return; cancelBot(); setPracticeMode(mode); setPractice(newGame(crypto.randomUUID())); setPracticeHistory([]); setSelection(null); setFlipped(false); setError(""); setCoachOpen(false); window.scrollTo({ top: 0 }); }
  function changeBotLevel(level: BotLevel) { if (level === botLevel) return; cancelBot(); setBotLevel(level); setError(""); try { localStorage.setItem("dama-bot-level", level); } catch { /* Browser preference only. */ } }
  function undoPractice() {
    let index = practiceHistory.length - 1;
    if (practiceMode === "bot") while (index >= 0 && practiceHistory[index].turn !== "white") index--;
    const previous = practiceHistory[index];
    if (!previous) return;
    cancelBot(); setPractice(previous); setPracticeHistory(history => history.slice(0, index)); setSelection(null); setError(""); beep();
  }
  async function copyInvite(onlyCode = false) {
    if (!room) return;
    try {
      await navigator.clipboard.writeText(onlyCode ? room.code : inviteUrl(room.code));
      if (!onlyCode) { setCopied(true); if (copyTimer.current) clearTimeout(copyTimer.current); copyTimer.current = setTimeout(() => setCopied(false), 2500); }
      notify(onlyCode ? "کۆدی ڕووم کۆپی کرا." : "لینکەکە کۆپی کرا؛ بۆ هاوڕێکەت بنێرە.");
    } catch { setError("کۆپی نەکرا. لینکەکە لە خانەی بانگهێشت هەڵبژێرە و کۆپی بکە."); }
  }
  async function shareInvite() {
    if (!room) return;
    if (!navigator.share) { await copyInvite(); return; }
    try { await navigator.share({ title: "دامە لەگەڵ هاوڕێکان", text: "با دامەیەک بکەین! ئەمە لینکی ڕوومەکەمانە:", url: inviteUrl(room.code) }); }
    catch (error) { if (!(error instanceof Error && error.name === "AbortError")) await copyInvite(); }
  }
  async function leave() {
    if (mutationRef.current) return;
    mutationRef.current = true; setBusy(true);
    try {
      if (room) {
        try { await api("/api/rooms/" + room.code, token, "PATCH", { type: "leave" }); }
        catch (error) { if (![403, 404].includes((error as { status?: number }).status || 0)) throw error; }
      }
      roomEpoch.current++;
      roomRef.current = null; setRoom(null); setPractice(null); setPracticeHistory([]); setSelection(null); setConfirm(null); setError(""); setCode(""); setTab("create"); setFlipped(false);
      setBoardOnly(false);
      cancelBot(); setCoachOpen(false); setPracticeMode("practice");
      try { sessionStorage.removeItem("dama-room"); } catch { /* Optional storage. */ }
      window.history.replaceState(null, "", "/"); window.scrollTo({ top: 0 });
    } catch (error) { setError(messageFor(error)); setConfirm(null); }
    finally { mutationRef.current = false; setBusy(false); }
  }
  function openBoardOnly() { flushSync(() => setBoardOnly(true)); }

  async function reconnect() {
    const current = roomRef.current;
    if (!current) return;
    const context = { code: current.code, epoch: roomEpoch.current };
    try { acceptRoom(await api<PublicRoom>("/api/rooms/" + current.code, token), context); }
    catch { if (roomRef.current?.code === context.code && roomEpoch.current === context.epoch) setError("هێشتا پەیوەندی بەردەست نییە."); }
  }

  const levelNames: Record<BotLevel, string> = { easy: "ئاسان", medium: "مامناوەند", hard: "بەهێز" };
  const playerName = (color: Color) => practice ? practiceMode === "bot" ? color === "white" ? name.trim() || "یاریزانی سپی" : "بۆت · " + levelNames[botLevel] : color === "white" ? "یاریزانی سپی" : "یاریزانی ڕەش" : room?.members.find(member => member.role === color)?.name || "چاوەڕوانی هاوڕێکەت…";
  const playerOnline = (color: Color) => Boolean(practice || Date.now() - (room?.members.find(member => member.role === color)?.lastSeen || 0) < 50000);
  const winnersName = game?.winner && game.winner !== "draw" ? playerName(game.winner) : "";
  const waiting = Boolean(room && !room.started);
  const gameTitle = game?.winner ? game.winner === "draw" ? "یارییەکی یەکسان، دانیشتنێکی خۆش" : winnersName + " بردییەوە!" : waiting ? "شوێنی هاوڕێکەت ئامادەیە" : practice ? "نۆرەی " + playerName(practice.turn) : role === "spectator" ? game ? "نۆرەی " + playerName(game.turn) : "" : canPlay ? "نۆرەی تۆیە؛ بیر بکەرەوە." : busy ? "جووڵەکەت دەنێردرێت…" : game ? "نۆرەی " + playerName(game.turn) : "";
  const gameHint = game?.winner ? game.reason === "resign" ? "یەکێک لە یاریزانەکان وازی هێنا." : game.reason === "repetition" ? "هەمان دۆخ سێ جار دووبارە بووەوە." : game.reason === "single-piece" ? "هەر یاریزانێک یەک بەردی ماوەتەوە." : game.reason === "blocked" ? "ڕێی هەموو جووڵەکانی بەرامبەر داخرا." : game.reason === "pieces" ? "هەموو بەردەکانی بەرامبەر خوران." : "هەردووکتان لەسەر یەکسانی ڕێککەوتن." : waiting ? "لینکەکە بنێرە؛ بە پەیوەستبوونی یاریزانی دووەم دەست پێ دەکەن." : role === "spectator" ? "جووڵەکان و گفتوگۆ خۆکارانە نوێ دەبنەوە." : canPlay ? moves[0]?.captures.length ? "خواردن ناچارییە؛ زنجیرەی " + number(moves[0].captures.length) + " بەردی هەڵبژێرە." : "بەردێک هەڵبژێرە، پاشان خانەی نیشانکراو دابگرە." : "کاتێک بۆ بیرکردنەوە لە جووڵەی داهاتووت.";
  const openRules = () => { setSettings(false); setRules(true); };
  const renderBoard = () => game && displayBoard ? <GameBoard board={displayBoard} onSquare={clickSquare} flipped={(role === "black") !== flipped} selected={activeSquare} targets={canPlay ? targets : new Set()} movable={canPlay && !selection ? new Set(moves.map(move => move.from)) : new Set()} lastMove={game.lastMove} disabled={!canPlay} showCoordinates={preferences.coordinates} showHints={preferences.hints} /> : null;

  return <div className="app-shell" data-board-theme={preferences.board}>
    <header className="site-header" inert={boardOnly}><a href="/" className="brand" aria-label="دامە — سەرەتا" onClick={event => { if (game) { event.preventDefault(); setConfirm("leave"); } }}><span className="brand-mark"><i /><i /><i /><i /></span><span><strong>دامە<span>.</span></strong><small>DAMA · FRIENDS EDITION</small></span></a><div className="header-center"><span className="header-star">✳</span><span>کاتێک بۆ هاوڕێکان</span><i /><small>یارییەکی کۆن، بیرەوەرییەکی نوێ</small></div><nav className="header-actions" aria-label="ڕێنمایی و ڕێکخستن"><button className="text-button header-help" onClick={openRules}><CircleHelp size={17} /><span>چۆن یاری بکەم؟</span></button><span className="header-divider" /><button className="icon-button theme-button" onClick={() => updatePreferences({ ...preferences, theme: preferences.theme === "light" ? "dark" : "light" })} aria-label={preferences.theme === "light" ? "چالاککردنی ڕووکاری شەو" : "چالاککردنی ڕووکاری ڕۆژ"}>{preferences.theme === "light" ? <Moon size={18} /> : <Sun size={18} />}</button><button className="icon-button" onClick={() => setSettings(true)} aria-label="ڕێکخستنی یاری"><Settings2 size={18} /></button></nav></header>

    {restoring ? <main className="loading-state"><div className="loading-emblem"><span className="loading-disc" /><span className="loading-disc second-disc" /></div><h1>تەختەکەت ئامادە دەکەین…</h1><p>تەنیا کەمێک؛ یارییەکی خۆش لە ڕێدایە.</p><LoaderCircle size={20} className="spin" /></main> : !game ? <Lobby name={name} setName={setName} code={code} setCode={value => setCode(normalizeCode(value))} password={password} setPassword={setPassword} tab={tab} setTab={next => { setTab(next); setError(""); }} joinRole={joinRole} setJoinRole={setJoinRole} botLevel={botLevel} setBotLevel={changeBotLevel} status={status} busy={busy} error={error} onSubmit={enterRoom} onPractice={() => startPractice("practice")} onRules={openRules} onPreferences={() => setSettings(true)} onRetry={() => void refreshStatus(token)} /> : <main className="room-page" inert={boardOnly}>
      <div className="room-toolbar"><button className="back-button" aria-label="گەڕانەوە بۆ سەرەتا" onClick={() => setConfirm("leave")}><ArrowLeft size={16} /><span>گەڕانەوە</span></button><div className="room-title"><span className="overline">{practice ? soloBot ? "SOLO MATCH" : "PRACTICE TABLE" : "YOUR PRIVATE TABLE"}</span><h1>{practice ? soloBot ? "ڕکابەری لەگەڵ بۆت" : "تەختەی تاقیکردنەوە" : "دانیشتنی هاوڕێکان"}</h1></div><div className="room-toolbar-end">{room && <button className="room-code-chip" onClick={() => void copyInvite(true)} aria-label="کۆپیکردنی کۆدی ڕووم"><span className="latin">{room.code}</span><Copy size={13} /></button>}<span className={"connection-badge" + (!connected && !practice ? " offline" : "")}>{practice ? <><Users size={13} /> لەسەر یەک ئامێر</> : connected ? <><span className="status-dot" /> پەیوەستە</> : <><WifiOff size={14} /> پەیوەندی پچڕاوە</>}</span></div></div>
      {practice && <div className={"practice-banner" + (soloBot ? " solo-banner" : "")}>{soloBot ? <Bot size={20} /> : <Sparkles size={17} />}<span><strong>{soloBot ? "یاریکردن لەگەڵ بۆت" : "بە ئاسوودەیی تاقی بکەرەوە."}</strong>{soloBot ? botThinking ? " بۆتەکە لە جووڵەکان ورد دەبێتەوە…" : " تۆ سپیت؛ بۆتەکە بە ڕەش یاری دەکات." : " نۆرە بە نۆرە هەردوو ڕەنگەکە بجووڵێنە؛ دەتوانیت جووڵەکانیش بگەڕێنیتەوە."}</span>{soloBot ? <div className="in-game-levels" role="group" aria-label="ئاستی بۆت">{(["easy", "medium", "hard"] as BotLevel[]).map(level => <button key={level} aria-pressed={level === botLevel} className={level === botLevel ? "selected" : ""} onClick={() => changeBotLevel(level)}>{levelNames[level]}</button>)}</div> : <span className="practice-label">تاقیکردنەوە</span>}</div>}
      {soloBot && practice?.turn === "black" && !practice.winner && !botThinking && error && <button className="secondary-button bot-retry" onClick={() => { setError(""); setBotRetry(value => value + 1); }}>دووبارە جووڵەی بۆت هەڵبسەنگێنە</button>}
      {!connected && room && <div className="disconnect-banner" role="status"><WifiOff size={18} /><div><strong>چاوەڕوانی پەیوەندییەکەتین</strong><p>دۆخی یاری پارێزراوە؛ بە گەڕانەوەی ئینتەرنێت خۆکارانە پەیوەست دەبیتەوە.</p></div><button className="secondary-button" onClick={() => void reconnect()}>دووبارە پەیوەست بە</button></div>}
      {error && <div className="error-message room-error" role="alert"><span>{error}</span><button className="icon-button" onClick={() => setError("")} aria-label="داخستنی هەڵە"><X size={15} /></button></div>}
      <div className="game-layout"><section className="playing-area" aria-label="تەختەی یاری"><div className={"match-status" + (game.winner ? " match-finished" : "")} aria-live="polite"><span className={"match-status-icon" + (!game.winner && !waiting ? " has-disc" : "")}>{game.winner ? game.winner === "draw" ? <Handshake size={24} /> : <Crown size={26} /> : waiting ? <Users size={23} /> : <span className={"mini-disc " + game.turn} />}</span><div><span className="overline">{game.winner ? "WELL PLAYED" : waiting ? "WAITING FOR A FRIEND" : "MOVE " + String(game.ply + 1).padStart(2, "0")}</span><h2>{gameTitle}</h2><p>{gameHint}</p></div>{game.winner && <span className="finish-spark" aria-hidden="true">✳</span>}</div>
        {game.winner && <div className="rematch-bar">{practice ? <button className="primary-button" onClick={() => startPractice(practiceMode)}><RotateCcw size={17} /> یارییەکی نوێ</button> : role !== "spectator" ? <button className="primary-button" disabled={busy || room?.rematchVotes.includes(room.me)} onClick={() => void action({ type: "rematch", gameId: game.id })}><RotateCcw size={17} />{room?.rematchVotes.includes(room.me) ? "چاوەڕوانی ڕەزامەندی هاوڕێکەت…" : room?.rematchVotes.length ? "قبوڵکردنی یارییەکی تر" : "با دانیشتنەکە بەردەوام بێت"}</button> : <span>چاوەڕوانی یارییەکی تری هاوڕێکان بە.</span>}{practice && practiceHistory.length > 0 && <button className="secondary-button" onClick={undoPractice}><Undo2 size={16} /> گەڕاندنەوە</button>}</div>}
        <PlayerCard color={otherColor} name={playerName(otherColor)} count={countPieces(game.board, otherColor)} kings={game.board.filter(p => pieceColor(p) === otherColor && Math.abs(p) === 2).length} captured={16 - countPieces(game.board, myColor)} active={Boolean((practice || room?.started) && !game.winner && game.turn === otherColor)} me={false} online={playerOnline(otherColor)} />
        <div className="board-wrap" aria-busy={busy}>{renderBoard()}{busy && <span className="board-saving"><LoaderCircle size={13} className="spin" /> جووڵەکە دەنێردرێت…</span>}</div>
        <PlayerCard color={myColor} name={playerName(myColor)} count={countPieces(game.board, myColor)} kings={game.board.filter(p => pieceColor(p) === myColor && Math.abs(p) === 2).length} captured={16 - countPieces(game.board, otherColor)} active={Boolean((practice || room?.started) && !game.winner && game.turn === myColor)} me={role !== "spectator"} online={playerOnline(myColor)} />
        <div className="board-controls"><div className="board-control-group"><button className="icon-button" onClick={() => { setFlipped(!flipped); setSelection(null); }} aria-label="گۆڕینی ئاراستەی تەختە" title="گۆڕینی ئاراستەی تەختە"><RotateCcw size={17} /></button><button className="icon-button" onClick={() => updatePreferences({ ...preferences, sound: !preferences.sound })} aria-label={preferences.sound ? "دەنگ بکوژێنەوە" : "دەنگ چالاک بکە"} aria-pressed={preferences.sound}>{preferences.sound ? <Volume2 size={17} /> : <VolumeX size={17} />}</button><button className="icon-button" onClick={() => setSettings(true)} aria-label="ڕێکخستنی تەختە"><Settings2 size={17} /></button><button className="board-focus-button" onClick={openBoardOnly} aria-label="گەورەکردنی تەنیا تەختەی دامە" title="تەنیا تەختە بە پڕشاشە"><Expand size={16} /><span>تەنیا تەختە</span></button></div><div className="board-control-group">{selection ? <button className="text-button cancel-selection" onClick={() => setSelection(null)}><X size={14} /> هەڵوەشاندنەوە</button> : null}{coachEnabled && role !== "spectator" && <button className="icon-button private-coach-trigger" onClick={() => setCoachOpen(true)} aria-label="یارمەتیدەری تایبەت"><Sparkles size={16} /></button>}{practice && <button className="icon-button" onClick={undoPractice} disabled={!practiceHistory.length} aria-label="گەڕاندنەوەی جووڵەی تاقیکردنەوە" title="گەڕاندنەوەی جووڵە"><Undo2 size={18} /></button>}</div></div>
        <div className="board-legend"><span><i className="legend-dot legal" /> جووڵەی ڕێگەپێدراو</span><span><i className="legend-dot previous" /> دوا جووڵە</span><span><ShieldCheck size={12} /> یاساکان خۆکارانە پارێزراون</span></div>
        {room?.drawOffer && !game.winner && <div className="draw-notice"><Handshake size={18} /><span>{room.drawOffer === role ? "داوای یەکسانیت نارد؛ چاوەڕوانی وەڵام بە." : playerName(room.drawOffer) + " داوای یەکسانی دەکات."}</span>{role !== "spectator" && room.drawOffer !== role && <div><button className="secondary-button" disabled={busy} onClick={() => void action({ type: "draw", gameId: game.id })}>قبوڵ دەکەم</button><button className="text-button" disabled={busy} onClick={() => void action({ type: "decline-draw", gameId: game.id })}>بەردەوام بین</button></div>}</div>}
        {!game.winner && <div className="game-controls"><span className="classic-label latin">TURKISH DAMA · 8 × 8</span>{practice ? <button className="text-button" onClick={() => setConfirm("reset")}><RotateCcw size={15} /> دەستپێکردنەوە</button> : role !== "spectator" && room?.started && <><button className="text-button" disabled={busy || !connected} onClick={() => void action({ type: "draw", gameId: game.id })}><Handshake size={16} />{room.drawOffer === role ? "هەڵوەشاندنەوەی داوا" : "داوای یەکسانی"}</button><button className="text-button resign-button" disabled={busy || !connected} onClick={() => setConfirm("resign")}><Flag size={15} /> وازهێنان</button></>}</div>}
      </section><RoomSidebar room={room} game={game} botLevel={soloBot ? botLevel : undefined} copied={copied} shareAvailable={shareAvailable} onCopy={() => void copyInvite()} onShare={() => void shareInvite()} onSend={sendMessage} chatBusy={chatBusy} connected={connected} onRules={openRules} /></div>
    </main>}

    <footer className="site-footer" inert={boardOnly}><div className="footer-brand"><button type="button" className="footer-star" aria-label="نیشانی دامە" onPointerDown={armCoach} onPointerUp={stopCoachHold} onPointerLeave={stopCoachHold} onPointerCancel={stopCoachHold} onContextMenu={event => event.preventDefault()}>✳</button><span>بیرەوەرییە باشەکان، لە دانیشتنە بچووکەکانەوە.</span></div><span className="footer-privacy"><ShieldCheck size={13} /> تایبەت بە تۆ و هاوڕێکانت</span><span className="footer-edition latin">MADE FOR GOOD COMPANY.</span></footer>
    {toast && <div className="toast" role="status"><span><CheckCheck size={17} /></span>{toast}<button onClick={() => setToast("")} aria-label="داخستنی ئاگادارکردنەوە"><X size={14} /></button></div>}
    {settings && <PreferencesDialog preferences={preferences} onChange={updatePreferences} onClose={() => setSettings(false)} />}
    {game && <BoardFocus open={boardOnly} onClose={() => setBoardOnly(false)} status={gameTitle + ". " + gameHint} canPlay={canPlay}>{renderBoard()}</BoardFocus>}
    {game && role !== "spectator" && <PrivateCoach open={coachOpen} onClose={() => setCoachOpen(false)} board={game.board} color={practiceMode === "practice" && practice ? game.turn : myColor} canPlay={canPlay} onPlay={playCoachMove} />}
    {rules && <RulesDialog onClose={() => setRules(false)} />}
    {confirm && <Modal title={confirm === "leave" ? "لە دانیشتنەکە دەچیتە دەرەوە؟" : confirm === "reset" ? "تەختەکە لە نوێوە ئامادە بکەین؟" : "لە یارییەکە واز دێنیت؟"} onClose={() => { if (!busy) setConfirm(null); }} className="confirm-modal"><span className="confirm-emblem">{confirm === "leave" ? <LogOut size={26} /> : confirm === "reset" ? <RotateCcw size={26} /> : <Flag size={26} />}</span><p className="modal-description">{confirm === "reset" ? "جووڵەکانی تاقیکردنەوە پاک دەبنەوە و هەردوو ڕەنگەکە لە سەرەتا دەست پێ دەکەن." : room?.started && !game?.winner && role !== "spectator" ? "یارییە چالاکەکە بە بردنەوەی هاوڕێکەت کۆتایی دێت. ئەنجامەکە لە دانیشتنەکەدا تۆمار دەکرێت." : "دەتوانیت هەر کاتێک بتەوێت، دانیشتنێکی نوێ دەست پێ بکەیت."}</p><div className="confirm-actions"><button className="secondary-button" onClick={() => setConfirm(null)} disabled={busy}>نەخێر، بەردەوام بین</button><button className="primary-button" disabled={busy} onClick={() => { if (confirm === "leave") void leave(); else if (confirm === "reset") { startPractice(); setConfirm(null); } else { setConfirm(null); if (game) void action({ type: "resign", gameId: game.id }); } }}>{busy ? <LoaderCircle size={18} className="spin" /> : <><Check size={17} /> بەڵێ، دڵنیام</>}</button></div></Modal>}
  </div>;
}

function PlayerCard({ color, name, count, kings, captured, active, me, online }: { color: Color; name: string; count: number; kings: number; captured: number; active: boolean; me: boolean; online: boolean }) {
  return <div className={"player-card" + (active ? " player-active" : "")}><span className={"avatar avatar-" + (color === "white" ? "white" : "dark")}>{name[0]}<span className={"presence-dot" + (online ? " online" : "")} /></span><div className="player-detail"><strong>{name}{me && <small>تۆ</small>}</strong><span>{color === "white" ? "سپی" : "ڕەش"}<i /> {number(count)} بەرد {kings > 0 && <><i /><Crown size={11} /> {number(kings)} دامە</>}</span></div><div className="player-captures" title="ژمارەی بەردە خوراوەکانی بەرامبەر"><span className="captured-stack" aria-hidden="true">{Array.from({ length: Math.min(captured, 4) }, (_, i) => <i key={i} className={"mini-disc " + opposite(color)} />)}</span><small>{captured ? number(captured) + " خواردووە" : "هێشتا خواردنی نییە"}</small></div>{active && <span className="turn-tag"><span className="status-dot" /> نۆرەی ئەوە</span>}</div>;
}
