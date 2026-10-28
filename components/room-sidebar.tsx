"use client";

import { useEffect, useRef, useState } from "react";
import { Bot, Check, ChevronLeft, Copy, Eye, History, Link2, LockKeyhole, MessageCircle, Send, Share2, Trophy, Users } from "lucide-react";
import type { PublicRoom } from "@/lib/types";
import type { BotLevel } from "@/lib/bot";
import type { Game } from "@/lib/game";

const number = (value: number) => String(value).replace(/\d/g, n => "٠١٢٣٤٥٦٧٨٩"[+n]);
const quickMessages = ["👋 سڵاو هاوڕێ", "👏 دەست‌خۆش", "🤔 جووڵەیەکی جوان", "🤝 یارییەکی خۆش بوو"];

export default function RoomSidebar({ room, game, copied, shareAvailable, onCopy, onShare, onSend, chatBusy, connected, onRules, botLevel }: {
  room: PublicRoom | null; game: Omit<Game, "positions">; copied: boolean; shareAvailable: boolean;
  onCopy: () => void; onShare: () => void; onSend: (text: string) => Promise<boolean>;
  chatBusy: boolean; connected: boolean; onRules: () => void;
  botLevel?: BotLevel;
}) {
  const [tab, setTab] = useState<"history" | "chat">("history");
  const [draft, setDraft] = useState("");
  const [seen, setSeen] = useState(0);
  const list = useRef<HTMLDivElement>(null);
  const messages = room?.messages || [];
  const lastMessage = messages.at(-1);
  const unread = messages.filter(m => m.createdAt > seen && m.memberId !== room?.me).length;
  useEffect(() => {
    if (tab !== "chat") return;
    setSeen(lastMessage?.createdAt || 0);
    if (list.current) list.current.scrollTop = list.current.scrollHeight;
  }, [tab, lastMessage?.id, lastMessage?.createdAt]);
  async function send(event: React.FormEvent) {
    event.preventDefault();
    if (!draft.trim() || chatBusy) return;
    const submitted = draft;
    if (await onSend(submitted)) setDraft(current => current === submitted ? "" : current);
  }
  const players = room?.members.filter(m => m.role !== "spectator") || [];
  const spectators = room?.members.filter(m => m.role === "spectator") || [];

  return <aside className="game-sidebar">
    {botLevel && <section className="sidebar-card solo-opponent-card"><div className="solo-opponent-heading"><span><Bot size={29} /></span><div><span className="overline">ALWAYS UP FOR A GAME</span><h2>هاوڕێی بۆتی دامە</h2><small>ئاستی {botLevel === "easy" ? "ئاسان" : botLevel === "medium" ? "مامناوەند" : "بەهێز"}</small></div></div><p>{botLevel === "easy" ? "هەنگاو بە هەنگاو فێر ببە. بۆتەکە جووڵەی جۆراوجۆر دەکات و دەرفەتی ڕاهێنانت پێ دەدات." : botLevel === "medium" ? "ڕکابەرێکی هاوسەنگ بۆ ڕاهێنان. چەند جووڵەی داهاتوو لەبەرچاو دەگرێت." : "ئامادەی ڕکابەرییەکی بەهێز بە. بۆتەکە بە قووڵی لە جووڵەکان ورد دەبێتەوە."}</p><div className="solo-color-labels"><span><i className="mini-disc white" /> تۆ بە سپی</span><span><i className="mini-disc black" /> بۆت بە ڕەش</span></div><span className="solo-undo-note">دەتوانیت نۆرەکەت بگەڕێنیتەوە و جووڵەیەکی تر تاقی بکەیتەوە.</span></section>}
    {room && <section className="sidebar-card invite-card"><div className="card-heading"><span className="card-icon"><Link2 size={18} /></span><h2>دانیشتنەکە تەواو بکە</h2><LockKeyhole size={14} /></div><p>لینکەکە بۆ هاوڕێکەت بنێرە؛ دوو کەسی تریش دەتوانن تماشا بکەن.</p><div className="invite-input"><input aria-label="لینکی بانگهێشت" readOnly value={`${typeof window === "undefined" ? "" : window.location.origin}/?room=${room.code}`} dir="ltr" onFocus={e => e.target.select()} /><button onClick={onCopy} aria-label="کۆپیکردنی لینکی بانگهێشت">{copied ? <Check size={17} /> : <Copy size={17} />}</button></div><div className="invite-actions"><button className={`secondary-button ${copied ? "copied" : ""}`} onClick={onCopy}>{copied ? <Check size={16} /> : <Copy size={16} />}{copied ? "کۆپی کرا" : "کۆپیکردنی لینک"}</button>{shareAvailable && <button className="secondary-button share-button" onClick={onShare} aria-label="هاوبەشکردنی بانگهێشت"><Share2 size={17} /></button>}</div><div className="room-members"><div className="members-label"><Users size={14} /><span>لە دانیشتنەکەدا</span><b>{number(room.members.length)} / ٤</b></div><div className="member-list">{room.members.map(m => <div className="member-row" key={m.id}><span className={`member-avatar ${m.role === "white" ? "is-white" : m.role === "black" ? "is-black" : "is-spectator"}`}>{m.role === "spectator" ? <Eye size={12} /> : m.name[0]}</span><span>{m.name}{m.id === room.me && <small>تۆ</small>}</span><i className={`presence-light ${Date.now() - m.lastSeen < 50000 ? "online" : ""}`} aria-label={Date.now() - m.lastSeen < 50000 ? "پەیوەستە" : "پەیوەست نییە"} /></div>)}{players.length === 1 && <div className="member-row empty-seat"><span className="member-avatar"><Users size={12} /></span><span>شوێنێک بۆ هاوڕێکەت</span></div>}</div><span className="spectator-caption"><Eye size={13} /> {number(spectators.length)} لە ٢ شوێنی تماشاکەر گیراوە</span></div></section>}

    <section className="sidebar-card activity-card"><div className="activity-tabs" role="tablist" aria-label="چالاکییەکانی ڕووم"><button id="history-tab" role="tab" aria-selected={tab === "history"} aria-controls="activity-panel" className={tab === "history" ? "active" : ""} onClick={() => setTab("history")}><History size={16} /> جووڵەکان<span className="tab-count">{number(game.ply)}</span></button><button id="chat-tab" role="tab" aria-selected={tab === "chat"} aria-controls="activity-panel" className={tab === "chat" ? "active" : ""} onClick={() => setTab("chat")}><MessageCircle size={16} /> گفتوگۆ{unread > 0 && <span className="unread-count">{number(unread)}</span>}</button></div><div id="activity-panel" role="tabpanel" aria-labelledby={tab === "history" ? "history-tab" : "chat-tab"}>
      {tab === "history" ? game.history.length ? <div className="history-content"><div className="history-labels"><span>نۆرە</span><span>جووڵە</span><span>خواردن</span></div><ol className="move-history">{[...game.history].reverse().map((entry, i) => <li key={`${game.id}-${game.ply - i}`}><span className="move-number latin">{String(game.ply - i).padStart(2, "0")}</span><i className={`mini-disc ${entry.color}`} /><b className="latin" dir="ltr">{entry.label}</b><small className={entry.captures ? "capture-count" : "no-capture"}>{entry.captures ? `+${number(entry.captures)}` : "—"}</small></li>)}</ol><span className="history-footnote">تازەترین جووڵە لە سەرەوەیە</span></div> : <div className="activity-empty"><span className="empty-table"><i /><i /><i /><i /></span><h3>هەر دانیشتنێک، یەکەم جووڵەیەک</h3><p>جووڵەکانتان هەنگاو بە هەنگاو لێرە تۆمار دەکرێن.</p></div> : !room ? <div className="activity-empty"><MessageCircle size={29} /><h3>گفتوگۆ بۆ کاتی ئۆنڵاینە</h3><p>ڕوومێک دروست بکە تا لەگەڵ هاوڕێکانت قسە بکەیت.</p></div> : <div className="chat-content"><div className="chat-messages" ref={list} role="log" aria-label="پەیامەکانی ڕووم" aria-live="polite" aria-relevant="additions">{!messages.length ? <div className="chat-empty"><span>👋</span><strong>سڵاوێک، پێش یەکەم جووڵە</strong><p>یاریزان و تماشاکەران دەتوانن لێرە گفتوگۆ بکەن.</p></div> : messages.map(message => <article key={message.id} className={`chat-message ${message.memberId === room.me ? "my-message" : ""}`}><div className="message-meta"><strong>{message.memberId === room.me ? "تۆ" : message.name}</strong><time dateTime={new Date(message.createdAt).toISOString()}>{new Date(message.createdAt).toLocaleTimeString("ckb-IQ", { hour: "2-digit", minute: "2-digit" })}</time></div><p dir="auto">{message.text}</p></article>)}</div><div className="quick-messages" aria-label="وەڵامی خێرا">{quickMessages.map(text => <button key={text} onClick={() => void onSend(text)} disabled={chatBusy || !connected}>{text}</button>)}</div><form className="chat-form" onSubmit={send}><label className="sr-only" htmlFor="chat-message">پەیامێک بنووسە</label><input id="chat-message" autoComplete="off" placeholder="پەیامێک بۆ هاوڕێکانت…" value={draft} onChange={e => setDraft(e.target.value)} maxLength={240} disabled={!connected} /><button className="chat-send" disabled={chatBusy || !draft.trim() || !connected} aria-label="ناردنی پەیام"><Send size={17} /></button></form><div className="chat-caption"><LockKeyhole size={10} /><span>تەنیا بۆ ئەوانەی لەم ڕوومەدان · دوا ٤٠ پەیام</span></div></div>}
    </div></section>

    {room && <section className="sidebar-card series-card"><div className="card-heading"><span className="card-icon"><Trophy size={17} /></span><h2>ئەنجامی دانیشتن</h2><span className="subtle-label">دوا ٢٠ یاری</span></div><div className="series-players">{players.map(player => <div key={player.id}><span className={`member-avatar ${player.role === "white" ? "is-white" : "is-black"}`}>{player.name[0]}</span><span>{player.name}</span><strong className="latin">{room.results.filter(result => result.winnerId === player.id).length}</strong><small>بردنەوە</small></div>)}</div><div className="series-summary"><span>{number(room.results.length)} یاریی تەواوبوو</span><span><span className="equal-symbol">=</span> {number(room.results.filter(result => result.winnerId === null).length)} یەکسانی</span></div></section>}
    <button className="sidebar-help" onClick={onRules}><span><CrownIcon /> یاساکان لەبیرت چوو؟</span><span>سەیری ڕێنماییەکان بکە <ChevronLeft size={13} /></span></button>
  </aside>;
}

function CrownIcon() { return <span className="help-spark" aria-hidden="true">✳</span>; }
