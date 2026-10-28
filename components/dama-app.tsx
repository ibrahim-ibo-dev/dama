"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ArrowLeft, ArrowUpLeft, Check, ChevronLeft, CircleHelp, Copy, Crown, Eye, Flag, Handshake, Link2, LoaderCircle, LockKeyhole, LogOut, RotateCcw, ShieldCheck, Sparkles, Users, Volume2, VolumeX, Wifi, WifiOff, X } from "lucide-react";
import { coordinate, countPieces, initialBoard, legalMoves, newGame, pieceColor, playMove, previewMove, type Board, type Color, type Game, type Move } from "@/lib/game";
import type { PublicRoom, Role, RoomAction } from "@/lib/types";

type Status = { mode: "local" | "redis" | "unconfigured"; passwordRequired: boolean };
type DisplayGame = Omit<Game, "positions">;
type Selection = { from: number; path: number[] } | null;
const names = { white: "سپی", black: "ڕەش", spectator: "تماشاکەر" };
const numerals = (value: number | string) => String(value).replace(/\d/g, n => "٠١٢٣٤٥٦٧٨٩"[Number(n)]);
const roomUrl = (code: string) => `${window.location.origin}/?room=${code}`;
const normalizeCode = (value: string) => value.toUpperCase().replace(/[^A-Z2-9]/g, "").slice(0, 10);

async function api<T>(url: string, token: string, method = "GET", body?: unknown): Promise<T> {
  const response = await fetch(url, {
    method, cache: "no-store", headers: { "Content-Type": "application/json", "x-player-token": token },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(15000),
  });
  const data = await response.json();
  if (!response.ok) throw Object.assign(new Error(data.error || "پەیوەندی بە سێرڤەر نەکرا."), { status: response.status });
  return data as T;
}

export default function DamaApp() {
  const [token, setToken] = useState("");
  const [status, setStatus] = useState<Status | null>(null);
  const [name, setName] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [tab, setTab] = useState<"create" | "join">("create");
  const [joinRole, setJoinRole] = useState<"player" | "spectator">("player");
  const [room, setRoom] = useState<PublicRoom | null>(null);
  const [practice, setPractice] = useState<Game | null>(null);
  const [selection, setSelection] = useState<Selection>(null);
  const [busy, setBusy] = useState(false);
  const [restoring, setRestoring] = useState(true);
  const [error, setError] = useState("");
  const [connected, setConnected] = useState(true);
  const [rules, setRules] = useState(false);
  const [confirm, setConfirm] = useState<"resign" | "leave" | null>(null);
  const [copied, setCopied] = useState(false);
  const [sound, setSound] = useState(true);
  const roomRef = useRef(room);
  const soundRef = useRef(sound);
  const audioRef = useRef<AudioContext | null>(null);
  const noticeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  roomRef.current = room;
  soundRef.current = sound;

  const beep = useCallback(() => {
    if (!soundRef.current) return;
    try {
      const ctx = audioRef.current ??= new AudioContext();
      void ctx.resume();
      const oscillator = ctx.createOscillator(), gain = ctx.createGain();
      oscillator.type = "sine"; oscillator.frequency.setValueAtTime(430, ctx.currentTime);
      oscillator.frequency.exponentialRampToValueAtTime(220, ctx.currentTime + .07);
      gain.gain.setValueAtTime(.07, ctx.currentTime); gain.gain.exponentialRampToValueAtTime(.001, ctx.currentTime + .1);
      oscillator.connect(gain); gain.connect(ctx.destination); oscillator.start(); oscillator.stop(ctx.currentTime + .1);
    } catch { /* Browsers can block sound until the first user gesture. */ }
  }, []);

  const acceptRoom = useCallback((next: PublicRoom) => {
    const previous = roomRef.current;
    if (previous && previous.code === next.code && previous.revision > next.revision) return;
    if (previous && (previous.game.ply !== next.game.ply || previous.game.id !== next.game.id)) { setSelection(null); beep(); }
    setRoom(next); roomRef.current = next; setConnected(true);
  }, [beep]);

  useEffect(() => {
    let cancelled = false;
    async function initialize() {
      let identity = "";
      try {
        identity = sessionStorage.getItem("dama-token") || crypto.randomUUID();
        sessionStorage.setItem("dama-token", identity);
        setName(localStorage.getItem("dama-name") || "");
        setSound(localStorage.getItem("dama-sound") !== "off");
      } catch { identity = crypto.randomUUID(); }
      setToken(identity);
      const queryCode = normalizeCode(new URLSearchParams(window.location.search).get("room") || "");
      if (queryCode) { setCode(queryCode); setTab("join"); }
      try {
        const result = await api<Status>("/api/status", identity);
        if (!cancelled) setStatus(result);
      } catch { if (!cancelled) setError("پەیوەندی بە سێرڤەر نەکرا. پەڕەکە نوێ بکەرەوە."); }
      let saved = "";
      try { saved = sessionStorage.getItem("dama-room") || ""; } catch { /* Storage is optional. */ }
      const restoreCode = queryCode || saved;
      if (restoreCode.length === 10) {
        try { const next = await api<PublicRoom>(`/api/rooms/${restoreCode}`, identity); if (!cancelled) acceptRoom(next); }
        catch (error) {
          const http = error as Error & { status?: number };
          if (!cancelled && http.status !== 403 && http.status !== 404) setError("گەڕانەوە بۆ ڕووم سەرکەوتوو نەبوو. بە هەمان کۆد دووبارە بچۆ ژوورەوە.");
          if (!cancelled) { setCode(restoreCode); setTab("join"); }
        }
      }
      if (!cancelled) setRestoring(false);
    }
    void initialize();
    return () => { cancelled = true; };
  }, [acceptRoom]);

  useEffect(() => {
    if (!room || !token) return;
    const roomCode = room.code;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout>;
    let lastHeartbeat = 0;
    let polling = false;
    async function poll() {
      if (stopped || polling) return;
      if (document.visibilityState === "hidden") { timer = setTimeout(poll, 5000); return; }
      polling = true;
      try {
        const heartbeat = Date.now() - lastHeartbeat > 20000;
        const next = await api<PublicRoom>(`/api/rooms/${roomCode}`, token, heartbeat ? "PATCH" : "GET", heartbeat ? { type: "heartbeat" } : undefined);
        if (heartbeat) lastHeartbeat = Date.now();
        if (!stopped) acceptRoom(next);
      } catch { if (!stopped) setConnected(false); }
      polling = false;
      if (!stopped) timer = setTimeout(poll, roomRef.current?.game.winner ? 4000 : 2000);
    }
    const wake = () => { clearTimeout(timer); if (!stopped) timer = setTimeout(poll, 100); };
    timer = setTimeout(poll, 1000);
    window.addEventListener("online", wake);
    document.addEventListener("visibilitychange", wake);
    return () => { stopped = true; clearTimeout(timer); window.removeEventListener("online", wake); document.removeEventListener("visibilitychange", wake); };
  }, [room?.code, token, acceptRoom]);

  useEffect(() => {
    if (!rules && !confirm) return;
    const previous = document.activeElement as HTMLElement | null;
    const dialog = document.querySelector<HTMLElement>("[role=dialog]");
    const focusable = () => Array.from(dialog?.querySelectorAll<HTMLElement>("button, a, input, [tabindex='0']") || []);
    focusable()[0]?.focus();
    function keyboard(event: KeyboardEvent) {
      if (event.key === "Escape") { setRules(false); setConfirm(null); }
      if (event.key === "Tab") {
        const elements = focusable(), first = elements[0], last = elements.at(-1);
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
      }
    }
    document.addEventListener("keydown", keyboard);
    const old = document.body.style.overflow; document.body.style.overflow = "hidden";
    return () => { document.removeEventListener("keydown", keyboard); document.body.style.overflow = old; previous?.focus(); };
  }, [rules, confirm]);

  useEffect(() => () => { if (noticeTimer.current) clearTimeout(noticeTimer.current); void audioRef.current?.close(); }, []);

  const me = room?.members.find(m => m.id === room.me);
  const game: DisplayGame | null = practice || room?.game || null;
  const role: Role = practice ? practice.turn : me?.role || "spectator";
  const canPlay = Boolean(game && !game.winner && !busy && (practice || (room?.started && connected && role === game.turn)));
  const moves = useMemo(() => game && !game.winner ? legalMoves(game.board, game.turn) : [], [game?.board, game?.turn, game?.winner]);
  const candidates = selection ? moves.filter(move => move.from === selection.from && selection.path.every((square, i) => move.path[i] === square)) : [];
  const displayBoard = selection?.path.length && candidates[0] && game ? previewMove(game.board, candidates[0], selection.path.length) : game?.board || initialBoard();
  const targets = new Set(candidates.map(move => move.path[selection?.path.length || 0]));
  const activeSquare = selection ? selection.path.at(-1) ?? selection.from : null;

  async function enterRoom(event: React.FormEvent) {
    event.preventDefault();
    if (!token || busy) return;
    setBusy(true); setError("");
    try {
      const next = await api<PublicRoom>(tab === "create" ? "/api/rooms" : `/api/rooms/${normalizeCode(code)}`, token, "POST", { name, password, role: joinRole });
      acceptRoom(next); setSelection(null);
      try { localStorage.setItem("dama-name", name.trim()); sessionStorage.setItem("dama-room", next.code); } catch { /* Storage is optional. */ }
      window.history.replaceState(null, "", `/?room=${next.code}`);
    } catch (error) { setError(error instanceof Error ? error.message : "هەڵەیەک ڕوویدا."); }
    finally { setBusy(false); }
  }

  async function action(body: RoomAction) {
    if (!room || busy) return;
    setBusy(true); setError("");
    try { const next = await api<PublicRoom>(`/api/rooms/${room.code}`, token, "PATCH", body); acceptRoom(next); }
    catch (error) {
      setError(error instanceof Error ? error.message : "پەیوەندی پچڕا. دووبارە هەوڵ بدەوە.");
      setSelection(null);
      try { acceptRoom(await api<PublicRoom>(`/api/rooms/${room.code}`, token)); } catch { setConnected(false); }
    } finally { setBusy(false); }
  }

  function clickSquare(square: number) {
    if (!canPlay || !game) return;
    if (selection && targets.has(square)) {
      const path = [...selection.path, square];
      const complete = candidates.find(move => move.path.length === path.length && move.path[path.length - 1] === square);
      if (complete) {
        setSelection(null);
        if (practice) { setPractice(playMove(practice, selection.from, path)); beep(); }
        else void action({ type: "move", from: selection.from, path, ply: game.ply, gameId: game.id });
      } else { setSelection({ ...selection, path }); beep(); }
    } else if (!selection?.path.length && pieceColor(game.board[square]) === game.turn && moves.some(move => move.from === square)) {
      setSelection(selection?.from === square ? null : { from: square, path: [] });
    }
  }

  async function copyInvite() {
    if (!room) return;
    try {
      await navigator.clipboard.writeText(roomUrl(room.code)); setCopied(true);
      if (noticeTimer.current) clearTimeout(noticeTimer.current);
      noticeTimer.current = setTimeout(() => setCopied(false), 2400);
    } catch { setError("کۆپی نەکرا. لینکەکە لە خانەی بانگهێشت دیاری و کۆپی بکە."); }
  }
  async function leave() {
    if (room) {
      setBusy(true);
      try { await api(`/api/rooms/${room.code}`, token, "PATCH", { type: "leave" }); }
      catch { setError("چوونەدەرەوە سەرکەوتوو نەبوو. دووبارە هەوڵ بدەوە."); setBusy(false); setConfirm(null); return; }
    }
    setRoom(null); roomRef.current = null; setPractice(null); setSelection(null); setConfirm(null); setError(""); setBusy(false);
    setCode(""); setTab("create");
    try { sessionStorage.removeItem("dama-room"); } catch { /* Storage is optional. */ }
    window.history.replaceState(null, "", "/");
  }
  function toggleSound() {
    setSound(!sound);
    try { localStorage.setItem("dama-sound", sound ? "off" : "on"); } catch { /* Storage is optional. */ }
  }

  const playerName = (color: Color) => practice ? color === "white" ? "یاریزانی سپی" : "یاریزانی ڕەش" : room?.members.find(m => m.role === color)?.name || "چاوەڕوانی هاوڕێکەت…";
  let gameTitle = "چاوەڕوانی هاوڕێکەتین";
  if (game?.winner) gameTitle = game.winner === "draw" ? "یارییەکی یەکسان 🤝" : `${playerName(game.winner)} بردییەوە!`;
  else if (practice || room?.started) gameTitle = role === "spectator" ? `نۆرەی ${playerName(game!.turn)}` : canPlay ? "نۆرەی تۆیە" : busy ? "جووڵەکە دەنێردرێت…" : `نۆرەی ${playerName(game!.turn)}`;

  return <div className="app-shell">
    <header className="site-header">
      <a href="/" className="brand" onClick={event => { if (room || practice) { event.preventDefault(); setConfirm("leave"); } }} aria-label="دامە — سەرەتا">
        <span className="brand-mark"><i /><i /><i /><i /></span>
        <span><strong>دامە<span className="brand-dot">.</span></strong><small>DAMA WITH FRIENDS</small></span>
      </a>
      <span className="header-note"><span className="tiny-star">✳</span> کاتێک بۆ هاوڕێکان</span>
      <div className="header-actions"><button className="text-button rules-button" onClick={() => setRules(true)}><CircleHelp size={17} /><span>چۆن یاری بکەم؟</span></button><span className="header-divider" /><button className="icon-button" onClick={toggleSound} aria-label={sound ? "دەنگ بکوژێنەوە" : "دەنگ چالاک بکە"} aria-pressed={sound}>{sound ? <Volume2 size={19} /> : <VolumeX size={19} />}</button></div>
    </header>

    {restoring ? <main className="loading-state"><LoaderCircle className="spin" /><p>دامەکەت ئامادە دەکەین…</p></main> : !game ? <main>
      <section className="lobby-layout">
        <div className="hero-copy">
          <div className="eyebrow"><span className="status-dot" /> ڕوومێکی تایبەت، یارییەکی خۆش</div>
          <h1>هەمان یاریی کۆن،<br /><span>دانیشتنێکی نوێ.</span></h1>
          <p className="hero-description">چا ئامادە بکە و هاوڕێکەت بانگ بکە.<br />دامەی کوردی، ئەمجارە بە ئۆنڵاین و لە هەر شوێنێک.</p>
          <div className="entry-card">
            <div className="entry-tabs" role="tablist" aria-label="چوونە ناو یاری"><button role="tab" aria-selected={tab === "create"} className={tab === "create" ? "active" : ""} onClick={() => { setTab("create"); setError(""); }}>ڕوومێکی نوێ</button><button role="tab" aria-selected={tab === "join"} className={tab === "join" ? "active" : ""} onClick={() => { setTab("join"); setError(""); }}>چوونە ناو ڕووم</button></div>
            <form onSubmit={enterRoom}>
              <label htmlFor="player-name">ناوەکەت</label>
              <div className="input-wrap"><Users size={18} /><input id="player-name" placeholder="بە چی ناوێک بانگت بکەین؟" value={name} onChange={event => setName(event.target.value)} maxLength={24} required autoComplete="nickname" /></div>
              {tab === "join" && <><label htmlFor="room-code">کۆدی ڕووم</label><div className="input-wrap"><Link2 size={18} /><input id="room-code" className="latin code-input" placeholder="ABCDEFG234" value={code} onChange={event => setCode(normalizeCode(event.target.value))} minLength={10} maxLength={10} required autoComplete="off" dir="ltr" spellCheck={false} /></div><div className="role-options"><button type="button" className={joinRole === "player" ? "selected" : ""} onClick={() => setJoinRole("player")}><span className="mini-disc" /> یاریزان</button><button type="button" className={joinRole === "spectator" ? "selected" : ""} onClick={() => setJoinRole("spectator")}><Eye size={16} /> تماشاکەر</button></div></>}
              {status?.passwordRequired && <><label htmlFor="site-password">وشەی نهێنی هاوڕێکان</label><div className="input-wrap"><LockKeyhole size={17} /><input id="site-password" type="password" value={password} onChange={event => setPassword(event.target.value)} required maxLength={200} autoComplete="current-password" placeholder="وشە نهێنییە هاوبەشەکەتان" /></div></>}
              {error && <div className="error-message" role="alert">{error}</div>}
              {status?.mode === "unconfigured" && <div className="setup-notice">بۆ یاری ئۆنڵاین، Upstash Redis لە Vercel پەیوەست بکە. تا ئەو کاتە دەتوانیت یاری تاقی بکەیتەوە.</div>}
              <button className="primary-button" disabled={busy || !token || !status || status.mode === "unconfigured"}>{busy ? <LoaderCircle size={19} className="spin" /> : <>{tab === "create" ? "ڕوومێک دروست بکە" : "بچۆ ناو ڕووم"}<ArrowUpLeft size={21} /></>}</button>
              <p className="form-note"><LockKeyhole size={12} /> {tab === "create" ? "بێ تۆمارکردن؛ تەنیا تۆ و ئەوانەی لینکیان هەیە." : "کۆدەکە لە هاوڕێکەت وەربگرە و پەیوەست بە."}</p>
            </form>
          </div>
          <div className="hero-footnote"><span className="friend-avatars"><i>ئ</i><i>ش</i><i>ت</i></span><span>دوو یاریزان، دوو تماشاکەر،<br /><strong>یەک دانیشتنی خۆش.</strong></span></div>
        </div>
        <div className="preview-scene">
          <span className="scene-orbit orbit-one" /><span className="scene-orbit orbit-two" />
          <div className="preview-caption"><span className="caption-line" /><span>یارییەکی سادە. بیرەوەرییەکی خۆش.</span><span className="caption-line" /></div>
          <div className="preview-game"><div className="preview-player"><span className="avatar avatar-dark">هـ</span><div><strong>هاوڕێکەت</strong><span>ڕەش · ١٦ بەرد</span></div><span className="waiting-label"><span /> ئامادەیە</span></div>
            <GameBoard board={initialBoard()} onSquare={() => {}} decorative />
            <div className="preview-player bottom-player"><span className="avatar avatar-white">ت</span><div><strong>تۆ</strong><span>سپی · ١٦ بەرد</span></div><span className="your-turn-label">یەکەم جووڵە بۆ تۆیە</span></div>
          </div>
          <button className="practice-link" onClick={() => { setPractice(newGame(crypto.randomUUID())); setError(""); setSelection(null); }}><RotateCcw size={15} /> پێش یاری، تاقی بکەرەوە <ChevronLeft size={15} /></button>
          <span className="scene-spark spark-one">✳</span><span className="scene-spark spark-two">✦</span>
        </div>
      </section>
      <section className="how-it-works" aria-label="دەستپێکردن"><div className="steps-intro"><span className="eyebrow-small">لە سێ هەنگاودا</span><h2>با یاری دەست پێ بکات.</h2></div><div className="step"><span className="step-number">01</span><div><strong>ڕوومێک دروست بکە</strong><p>ناوەکەت بنووسە، هەر ئەوەندە.</p></div></div><div className="step"><span className="step-number">02</span><div><strong>هاوڕێکەت بانگ بکە</strong><p>لینکی تایبەتی ڕوومەکەی بۆ بنێرە.</p></div></div><div className="step"><span className="step-number">03</span><div><strong>نۆرەی زیرەکیی تۆیە</strong><p>بەردێک هەڵبژێرە و یاری دەست پێ بکە.</p></div></div></section>
    </main> : <main className="room-page">
      <div className="room-toolbar"><button className="text-button" onClick={() => setConfirm("leave")}><ArrowLeft size={17} /> گەڕانەوە</button><div className="room-heading"><span>{practice ? "یاریی تاقیکردنەوە" : "ڕوومی هاوڕێکان"}</span>{room && <button className="room-code-chip latin" onClick={copyInvite}>{room.code} {copied ? <Check size={14} /> : <Copy size={14} />}</button>}</div><span className={`connection-badge ${!connected && !practice ? "offline" : ""}`}>{practice ? <><Users size={14} /> لەسەر یەک ئامێر</> : connected ? <><Wifi size={14} /> پەیوەستە</> : <><WifiOff size={14} /> هەوڵی پەیوەندی…</>}</span></div>
      {practice && <div className="practice-banner"><Sparkles size={17} /><span>ئەمە تاقیکردنەوەیە لەسەر یەک ئامێر؛ نۆرە بە نۆرە هەردوو ڕەنگەکە بجووڵێنە. بۆ ئۆنڵاین ڕوومێک دروست بکە.</span></div>}
      {error && <div className="error-message room-error" role="alert">{error}<button onClick={() => setError("")} aria-label="داخستن"><X size={15} /></button></div>}
      <div className="game-layout"><section className="playing-area" aria-label="تەختەی یاری">
        <PlayerBar color={role === "black" ? "white" : "black"} name={playerName(role === "black" ? "white" : "black")} count={countPieces(game.board, role === "black" ? "white" : "black")} active={Boolean((practice || room?.started) && !game.winner && game.turn === (role === "black" ? "white" : "black"))} me={false} online={practice ? true : Date.now() - (room?.members.find(m => m.role === (role === "black" ? "white" : "black"))?.lastSeen || 0) < 50000} />
        <GameBoard board={displayBoard} onSquare={clickSquare} flipped={role === "black"} selected={activeSquare} targets={canPlay ? targets : new Set()} movable={canPlay && !selection ? new Set(moves.map(m => m.from)) : new Set()} lastMove={game.lastMove} disabled={!canPlay} />
        <PlayerBar color={role === "black" ? "black" : "white"} name={playerName(role === "black" ? "black" : "white")} count={countPieces(game.board, role === "black" ? "black" : "white")} active={Boolean((practice || room?.started) && !game.winner && game.turn === (role === "black" ? "black" : "white"))} me={role !== "spectator"} online={practice ? true : Date.now() - (room?.members.find(m => m.role === (role === "black" ? "black" : "white"))?.lastSeen || 0) < 50000} />
      </section><aside className="game-sidebar">
        <section className={`turn-card ${game.winner ? "finished-card" : ""}`} aria-live="polite"><div className="turn-card-icon">{game.winner ? game.winner === "draw" ? <Handshake size={24} /> : <Crown size={26} /> : room && !room.started ? <Users size={24} /> : <span className={`mini-disc ${game.turn}`} />}</div><span className="eyebrow-small">{game.winner ? "کۆتایی یاری" : room && !room.started ? "هەموو شتێک ئامادەیە" : `جووڵەی ${numerals(game.ply + 1)}`}</span><h2>{gameTitle}</h2><p>{game.winner ? game.reason === "resign" ? "یەکێک لە یاریزانەکان وازی هێنا." : game.reason === "repetition" ? "هەمان دۆخ سێ جار دووبارە بووەوە." : game.reason === "single-piece" ? "هەر یاریزانێک تەنیا یەک بەردی ماوەتەوە." : "دانیشتنێکی تر؟ هەردووکتان دەتوانن دووبارە یاری بکەن." : room && !room.started ? "لینکەکە بۆ هاوڕێکەت بنێرە؛ بە پەیوەستبوونی ئەو یاری دەست پێ دەکات." : role === "spectator" ? "تۆ تماشاکەریت؛ جووڵەکان خۆکارانە نوێ دەبنەوە." : canPlay ? moves[0]?.captures.length ? `خواردن ناچارییە؛ ${numerals(moves[0].captures.length)} بەرد بخۆ.` : "بەردێک هەڵبژێرە، پاشان شوێنی نیشانکراو دابگرە." : "بیر لە جووڵەی داهاتووت بکەرەوە."}</p>
          {selection && <button className="text-button cancel-selection" onClick={() => setSelection(null)}><RotateCcw size={14} /> هەڵوەشاندنەوەی هەڵبژاردن</button>}
          {game.winner && (practice ? <button className="primary-button" onClick={() => { setPractice(newGame(crypto.randomUUID())); setSelection(null); }}><RotateCcw size={17} /> یارییەکی نوێ</button> : role !== "spectator" && <button className="primary-button" disabled={busy || room?.rematchVotes.includes(room.me)} onClick={() => void action({ type: "rematch", gameId: game.id })}><RotateCcw size={17} />{room?.rematchVotes.includes(room.me) ? "چاوەڕوانی ڕەزامەندی هاوڕێکەت…" : room?.rematchVotes.length ? "قبوڵکردنی یارییەکی تر" : "با دووبارە یاری بکەین"}</button>)}
        </section>
        {room && <section className="sidebar-card invite-card"><div className="card-heading"><Link2 size={17} /><h3>هاوڕێکەت بانگ بکە</h3><LockKeyhole size={14} /></div><p>ئەم لینکە تەنیا لەگەڵ هاوڕێکانت هاوبەش بکە.</p><div className="invite-input"><input aria-label="لینکی بانگهێشت" value={typeof window !== "undefined" ? roomUrl(room.code) : ""} readOnly dir="ltr" onFocus={event => event.target.select()} /><button onClick={copyInvite} aria-label="کۆپیکردنی لینکی بانگهێشت">{copied ? <Check size={18} /> : <Copy size={18} />}</button></div><button className={`secondary-button copy-button ${copied ? "copied" : ""}`} onClick={copyInvite}>{copied ? <><Check size={16} /> لینکەکە کۆپی کرا</> : <><Copy size={16} /> کۆپیکردنی لینک</>}</button><div className="spectators"><Eye size={15} /><span>تماشاکەران</span><span className="spectator-count">{numerals(room.members.filter(m => m.role === "spectator").length)} / ٢</span></div>{room.members.filter(m => m.role === "spectator").map(m => <div key={m.id} className="spectator-name"><span className={`status-dot ${Date.now() - m.lastSeen > 50000 ? "inactive" : ""}`} />{m.name}{m.id === room.me && <small>(تۆ)</small>}</div>)}</section>}
        <section className="sidebar-card history-card"><div className="card-heading"><RotateCcw size={16} /><h3>جووڵەکان</h3><span className="history-count">{numerals(game.ply)}</span></div>{!game.history.length ? <div className="empty-history"><span className="empty-history-dots">•••</span><p>هەر یارییەکی خۆش بە جووڵەیەک دەست پێ دەکات.</p></div> : <ol className="move-history">{game.history.slice(-10).map((entry, index, list) => <li key={`${game.id}-${game.ply - list.length + index}`}><span>{numerals(game.ply - list.length + index + 1)}.</span><i className={`mini-disc ${entry.color}`} /><b className="latin" dir="ltr">{entry.label}</b>{entry.captures > 0 && <small>+{numerals(entry.captures)}</small>}</li>)}</ol>}</section>
        {!game.winner && (practice ? <button className="text-button sidebar-rule" onClick={() => { setPractice(newGame(crypto.randomUUID())); setSelection(null); }}><RotateCcw size={16} /> دەستپێکردنەوەی تاقیکردنەوە</button> : role !== "spectator" && room?.started && <div className="game-controls"><button className="secondary-button" disabled={busy} onClick={() => void action({ type: "draw", gameId: game.id })}><Handshake size={16} />{room?.drawOffer === role ? "هەڵوەشاندنەوەی داوا" : room?.drawOffer ? "قبوڵکردنی یەکسانی" : "داوای یەکسانی"}</button><button className="secondary-button resign-button" disabled={busy} onClick={() => setConfirm("resign")}><Flag size={15} /> وازهێنان</button></div>)}
        {room?.drawOffer && !game.winner && <div className="draw-notice">{room.drawOffer === role ? "داوای یەکسانیت نارد؛ چاوەڕوانی وەڵامی هاوڕێکەت بە." : `${playerName(room.drawOffer)} داوای یەکسانی دەکات.`}{role !== "spectator" && room.drawOffer !== role && <button onClick={() => void action({ type: "decline-draw", gameId: game.id })}>ڕەتکردنەوە</button>}</div>}
        <button className="text-button sidebar-rule" onClick={() => setRules(true)}><CircleHelp size={16} /> یاساکانی دامە</button>
      </aside></div>
    </main>}

    <footer className="site-footer"><span>دروستکراوە بۆ دانیشتنە بچووکەکان<span className="footer-star">✳</span></span><span><ShieldCheck size={14} /> تایبەت بە تۆ و هاوڕێکانت</span><span className="latin footer-edition">DAMA · THE FRIENDS EDITION</span></footer>

    {rules && <div className="modal-backdrop" onClick={event => { if (event.target === event.currentTarget) setRules(false); }}><section className="modal rules-modal" role="dialog" aria-modal="true" aria-labelledby="rules-title"><button className="icon-button modal-close" onClick={() => setRules(false)} aria-label="داخستن"><X size={20} /></button><span className="modal-emblem"><Crown size={28} /></span><span className="eyebrow-small">سادەیە؛ بەڵام زیرەکی دەوێت</span><h2 id="rules-title">چۆن دامە بکەین؟</h2><p className="modal-intro">دامەی کوردی / تورکی · تەختەی ٨ × ٨ · ١٦ بەرد بۆ هەر کەس</p><ol className="rules-list"><li><strong>جووڵەی بەرد</strong><p>یەک خانە بۆ پێشەوە، ڕاست یان چەپ. بەردی ئاسایی بۆ دواوە یان بە لار ناجووڵێت و ناخوات. سپی دەست پێ دەکات.</p></li><li><strong>خواردن ناچارییە</strong><p>بەسەر بەردی بەرامبەر باز بدە و لە خانەی بەتاڵ بنیشە. ئەگەر چەند ڕێگایەک هەبوو، ئەوە هەڵبژێرە کە زۆرترین بەرد دەخوات. تا تەواوبوونی زنجیرەکە بەردەکە بەردەوام بکە.</p></li><li><strong>بەردەکەت بکە بە دامە</strong><p>بەردەکەت لە کۆتایی نۆرەکەدا بگاتە دوا ڕیزی بەرامبەر، دەبێتە دامە. دامە بە ڕاستی لە هەر چوار ئاراستەدا چەند خانەیەک دەجووڵێت و دەخوات؛ لە زنجیرەی خواردندا ناتوانێت یەکسەر ١٨٠ پلە بگەڕێتەوە.</p></li><li><strong>بردنەوە و یەکسانی</strong><p>هەموو بەردەکانی بەرامبەر بخۆ یان ڕێی جووڵەکانی ببەستە. سێ جار دووبارەبوونەوەی هەمان دۆخ یەکسانییە. ئەگەر هەر کەس یەک بەردی مابێت، یەکسانن؛ بەڵام دامە بەرامبەر بە بەردی ئاسایی دەباتەوە. دەتوانن بە ڕەزامەندی هەردووکتانیش یەکسان بن.</p></li></ol><button className="primary-button" onClick={() => setRules(false)}>تێگەیشتم، با یاری بکەین <ArrowUpLeft size={18} /></button></section></div>}
    {confirm && <div className="modal-backdrop"><section className="modal confirm-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-title"><button className="icon-button modal-close" onClick={() => setConfirm(null)} aria-label="داخستن"><X size={20} /></button><span className="modal-emblem">{confirm === "leave" ? <LogOut size={25} /> : <Flag size={25} />}</span><h2 id="confirm-title">{confirm === "leave" ? "لە ڕوومەکە دەچیتە دەرەوە؟" : "لە یارییەکە واز دێنیت؟"}</h2><p>{room?.started && !game?.winner && role !== "spectator" ? "یارییەکە بە بردنەوەی هاوڕێکەت کۆتایی دێت." : "دەتوانیت هەر کاتێک بیەوێت یارییەکی نوێ دەست پێ بکەیت."}</p><div className="confirm-actions"><button className="secondary-button" onClick={() => setConfirm(null)}>نەخێر، دەمێنمەوە</button><button className="primary-button" disabled={busy} onClick={() => { if (confirm === "leave") void leave(); else { setConfirm(null); if (game) void action({ type: "resign", gameId: game.id }); } }}>{busy ? <LoaderCircle className="spin" size={18} /> : "بەڵێ، دڵنیام"}</button></div></section></div>}
  </div>;
}

function PlayerBar({ color, name, count, active, me, online }: { color: Color; name: string; count: number; active: boolean; me: boolean; online: boolean }) {
  return <div className={`player-bar ${active ? "player-active" : ""}`}><span className={`avatar avatar-${color === "white" ? "white" : "dark"}`}>{name[0]}<span className={`presence-dot ${online ? "online" : ""}`} /></span><div className="player-detail"><strong>{name}{me && <small>تۆ</small>}</strong><span>{names[color]} · {numerals(count)} بەرد</span></div>{active ? <span className="turn-tag"><span className="status-dot" /> نۆرەی ئەوە</span> : <span className={`mini-disc ${color}`} />}</div>;
}

function GameBoard({ board, onSquare, flipped = false, selected = null, targets = new Set(), movable = new Set(), lastMove = null, disabled = true, decorative = false }: { board: Board; onSquare: (square: number) => void; flipped?: boolean; selected?: number | null; targets?: Set<number | undefined>; movable?: Set<number>; lastMove?: Move | null; disabled?: boolean; decorative?: boolean }) {
  const squares = Array.from({ length: 64 }, (_, i) => flipped ? 63 - i : i);
  function keyboard(event: React.KeyboardEvent<HTMLButtonElement>, index: number) {
    const delta = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -8, ArrowDown: 8 }[event.key];
    if (delta === undefined) return;
    const next = index + delta;
    if (next < 0 || next >= 64 || (Math.abs(delta) === 1 && Math.floor(next / 8) !== Math.floor(index / 8))) return;
    event.preventDefault();
    const parent = event.currentTarget.parentElement;
    (parent?.children[next] as HTMLButtonElement)?.focus();
  }
  return <div className={`board-frame ${decorative ? "decorative-board" : ""}`} dir="ltr"><div className="board-coordinates coordinates-top" aria-hidden="true">{(flipped ? "hgfedcba" : "abcdefgh").split("").map(letter => <span key={letter}>{letter}</span>)}</div><div className="board-coordinates coordinates-side" aria-hidden="true">{Array.from({ length: 8 }, (_, i) => <span key={i}>{flipped ? i + 1 : 8 - i}</span>)}</div><div className="board" role={decorative ? "img" : "grid"} aria-label="تەختەی دامە" aria-readonly={decorative || disabled}>{squares.map((square, visualIndex) => {
    const piece = board[square], color = pieceColor(piece);
    const highlighted = lastMove && (square === lastMove.from || square === lastMove.path.at(-1));
    const className = `square ${(Math.floor(square / 8) + square % 8) % 2 ? "square-dark" : "square-light"} ${square === selected ? "square-selected" : ""} ${targets.has(square) ? "square-target" : ""} ${highlighted ? "square-last" : ""} ${movable.has(square) ? "square-movable" : ""}`;
    const content = <>{piece !== 0 && <span className={`piece piece-${color} ${Math.abs(piece) === 2 ? "piece-king" : ""}`}>{Math.abs(piece) === 2 && <Crown size={23} strokeWidth={1.7} />}</span>}{targets.has(square) && <span className="target-dot" />}</>;
    return decorative ? <div key={square} className={className}>{content}</div> : <button type="button" key={square} role="gridcell" aria-selected={square === selected} aria-label={`${coordinate(square)}: ${piece ? `${names[color!]} ${Math.abs(piece) === 2 ? "دامە" : "بەرد"}` : "بەتاڵ"}${targets.has(square) ? "، جووڵەی ڕێگەپێدراو" : ""}`} aria-disabled={disabled} className={className} onClick={() => onSquare(square)} onKeyDown={event => keyboard(event, visualIndex)}>{content}</button>;
  })}</div><div className="board-coordinates coordinates-bottom" aria-hidden="true">{(flipped ? "hgfedcba" : "abcdefgh").split("").map(letter => <span key={letter}>{letter}</span>)}</div></div>;
}
