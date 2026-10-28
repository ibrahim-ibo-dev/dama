"use client";

import { ArrowUpLeft, Bot, Check, ChevronLeft, CircleHelp, Coffee, Crown, Eye, Link2, LoaderCircle, LockKeyhole, Play, ShieldCheck, Sparkles, Users } from "lucide-react";
import { initialBoard } from "@/lib/game";
import GameBoard from "./game-board";
import "./bot-entry.css";

type BotLevel = "easy" | "medium" | "hard";
type EntryTab = "create" | "join" | "bot";
type Props = {
  name: string; setName: (value: string) => void; code: string; setCode: (value: string) => void;
  password: string; setPassword: (value: string) => void;
  tab: EntryTab; setTab: (tab: EntryTab) => void;
  botLevel: BotLevel; setBotLevel: (level: BotLevel) => void;
  joinRole: "player" | "spectator"; setJoinRole: (role: "player" | "spectator") => void;
  status: { mode: string; passwordRequired: boolean } | null;
  busy: boolean; error: string; onSubmit: (event: React.FormEvent) => void;
  onPractice: () => void; onRules: () => void; onPreferences: () => void; onRetry: () => void;
};

const levels: { value: BotLevel; label: string; description: string; bars: number }[] = [
  { value: "easy", label: "ئاسان", description: "بۆ دەستپێکردن", bars: 1 },
  { value: "medium", label: "مامناوەند", description: "بۆ ڕاهێنان", bars: 2 },
  { value: "hard", label: "بەهێز", description: "بۆ ڕکابەری", bars: 3 },
];

export default function Lobby(props: Props) {
  const solo = props.tab === "bot";
  const panelLabel = props.tab === "create" ? "create-tab" : props.tab === "join" ? "join-tab" : "bot-tab";
  return <main className="lobby-page">
    <section className="lobby-layout">
      <div className="hero-copy">
        <div className="hero-eyebrow"><span className="status-dot" /> بۆ ئەو دانیشتنانەی بیرمان دەکەون</div>
        <h1>دامەیەک لەگەڵ<br /><span>هاوڕێیەکی باش.</span><span className="title-spark" aria-hidden="true">✳</span></h1>
        <p className="hero-description">چا ئامادە بکە، لینکەکە بنێرە و پێکەوە یاری بکەن.<br />هەمان دامەی خۆمان؛ لە هەر شوێنێک کە بن.</p>
        <div className={"entry-card entry-card-with-bot" + (solo ? " solo-entry-card" : "")}>
          <div className="entry-tabs" role="tablist" aria-label="دەستپێکردنی یاری">
            <button role="tab" id="create-tab" aria-controls="entry-panel" aria-selected={props.tab === "create"} className={props.tab === "create" ? "active" : ""} onClick={() => props.setTab("create")}><span className="tab-dot" /> ڕوومێکی نوێ</button>
            <button role="tab" id="join-tab" aria-controls="entry-panel" aria-selected={props.tab === "join"} className={props.tab === "join" ? "active" : ""} onClick={() => props.setTab("join")}><Link2 size={15} /> چوونە ناو ڕووم</button>
            <button role="tab" id="bot-tab" aria-controls="entry-panel" aria-selected={solo} className={solo ? "active" : ""} onClick={() => props.setTab("bot")}><Bot size={16} /> لەگەڵ بۆت</button>
          </div>
          <form id="entry-panel" role="tabpanel" aria-labelledby={panelLabel} onSubmit={props.onSubmit}>
            <div className="entry-intro">
              <strong>{solo ? "هاوڕێیەک، هەمیشە ئامادەی یاری" : props.tab === "create" ? "شوێنێک بۆ تۆ و هاوڕێکانت" : "هاوڕێکەت چاوەڕێتە"}</strong>
              <span>{solo ? "بۆتەکە بە ئاستی خۆت هەڵبژێرە و زیرەکییەکەت تاقی بکەرەوە." : props.tab === "create" ? "ڕوومێکی تایبەت لە چەند چرکەیەکدا." : "کۆدی بانگهێشتەکەت بنووسە و پەیوەست بە."}</span>
            </div>
            {solo ? <div className="solo-entry">
              <div className="solo-matchup" aria-label="تۆ بە سپی بەرامبەر بۆت بە ڕەش">
                <div><span className="solo-avatar solo-human"><Users size={19} /></span><span><strong>تۆ</strong><small><i className="mini-disc white" /> بەردە سپییەکان</small></span></div>
                <span className="solo-versus latin" aria-hidden="true">VS</span>
                <div><span className="solo-avatar solo-bot"><Bot size={22} /></span><span><strong>بۆتی دامە</strong><small><i className="mini-disc black" /> بەردە ڕەشەکان</small></span></div>
              </div>
              <div className="solo-level-heading"><span>ئاستی بۆت</span><small>هەر کاتێک بتەوێت دەتوانیت بیگۆڕیت</small></div>
              <div className="solo-levels" role="group" aria-label="ئاستی بۆت هەڵبژێرە">
                {levels.map(level => <button type="button" key={level.value} aria-pressed={props.botLevel === level.value} className={"solo-level" + (props.botLevel === level.value ? " selected" : "")} onClick={() => props.setBotLevel(level.value)}>
                  <span className="solo-level-bars" aria-hidden="true">{[1, 2, 3].map(bar => <i key={bar} className={bar <= level.bars ? "filled" : ""} />)}</span>
                  <strong>{level.label}</strong><small>{level.description}</small>
                  {props.botLevel === level.value && <Check className="solo-level-check" size={12} />}
                </button>)}
              </div>
              <p className="solo-first-move"><span className="status-dot" /> سپی دەست پێ دەکات؛ یەکەم جووڵە بۆ تۆیە.</p>
            </div> : <>
              <label htmlFor="player-name">ناوەکەت <small>تا ٢٤ پیت</small></label>
              <div className="input-wrap"><Users size={18} /><input id="player-name" value={props.name} onChange={e => props.setName(e.target.value)} maxLength={24} required autoComplete="nickname" placeholder="بە چی ناوێک بانگت بکەین؟" /></div>
            </>}
            {props.tab === "join" && <>
              <label htmlFor="room-code">کۆدی ڕووم</label>
              <div className="input-wrap"><Link2 size={18} /><input id="room-code" value={props.code} onChange={e => props.setCode(e.target.value)} minLength={10} maxLength={10} className="code-input latin" dir="ltr" placeholder="ABCDEFG234" autoComplete="off" spellCheck={false} required /></div>
              <div className="role-options" role="group" aria-label="وەک چی پەیوەست دەبیت؟">
                <button type="button" className={props.joinRole === "player" ? "selected" : ""} aria-pressed={props.joinRole === "player"} onClick={() => props.setJoinRole("player")}><Crown size={17} /><span>یاریزان<small>شوێنی دووەم بۆ تۆیە</small></span>{props.joinRole === "player" && <Check size={15} />}</button>
                <button type="button" className={props.joinRole === "spectator" ? "selected" : ""} aria-pressed={props.joinRole === "spectator"} onClick={() => props.setJoinRole("spectator")}><Eye size={17} /><span>تماشاکەر<small>یاری ببینە و گفتوگۆ بکە</small></span>{props.joinRole === "spectator" && <Check size={15} />}</button>
              </div>
            </>}
            {!solo && props.status?.passwordRequired && <>
              <label htmlFor="site-password">وشەی نهێنی هاوڕێکان</label><div className="input-wrap"><LockKeyhole size={17} /><input id="site-password" type="password" autoComplete="current-password" placeholder="وشە نهێنییە هاوبەشەکەتان" value={props.password} onChange={e => props.setPassword(e.target.value)} maxLength={200} required /></div>
            </>}
            {props.error && <p className="error-message" role="alert">{props.error}</p>}
            {!solo && props.status?.mode === "unconfigured" && <div className="setup-notice">بۆ چالاککردنی یاری ئۆنڵاین، Upstash Redis لە Vercel پەیوەست بکە. ئێستا دەتوانیت یاری تاقی بکەیتەوە.</div>}
            {!solo && !props.status && <div className="status-retry"><span>پەیوەندی سێرڤەر دەپشکنرێت…</span><button type="button" onClick={props.onRetry}>دووبارە هەوڵ بدەوە</button></div>}
            <button className="primary-button start-button" disabled={props.busy || (!solo && (!props.status || props.status.mode === "unconfigured"))}>
              {props.busy ? <><LoaderCircle size={18} className="spin" /> {solo ? "تەختەکە ئامادە دەکرێت…" : "ڕوومەکە ئامادە دەکرێت…"}</> : <>{solo ? "یاری لەگەڵ بۆت دەست پێ بکە" : props.tab === "create" ? "ڕوومێک دروست بکە" : "بچۆ ناو ڕووم"}{solo ? <Bot size={20} /> : <ArrowUpLeft size={22} />}</>}
            </button>
            <div className="form-note">{solo ? <Bot size={13} /> : <ShieldCheck size={13} />}<span>{solo ? "بێ بانگهێشت و چاوەڕوانی · یاری لەسەر ئەم ئامێرە" : "بێ تۆمارکردن · بە لینکی تایبەت · تا ٤ کەس"}</span></div>
          </form>
        </div>
        <div className="hero-secondary"><button className="practice-link" onClick={props.onPractice}><span><Play size={13} fill="currentColor" /></span> تاقیکردنەوەی دوو کەسی <ChevronLeft size={14} /></button><button className="text-button" onClick={props.onRules}><CircleHelp size={15} /> یاساکان</button></div>
      </div>
      <div className="preview-scene"><div className="scene-grid" aria-hidden="true" /><span className="scene-circle" aria-hidden="true" /><div className="scene-topline"><span className="overline">THE TABLE IS YOURS</span><span className="scene-top-mark">✳</span></div><div className="preview-game"><div className="preview-player"><span className="avatar avatar-dark">هـ<span className="presence-dot online" /></span><div><strong>هاوڕێکەت</strong><small>ڕەش · ١٦ بەرد</small></div><span className="ready-tag"><span className="status-dot" /> ئامادەیە</span></div><GameBoard board={initialBoard()} onSquare={() => {}} decorative /><div className="preview-player preview-you"><span className="avatar avatar-white">ت</span><div><strong>تۆ</strong><small>سپی · ١٦ بەرد</small></div><span className="first-turn"><span className="mini-disc white" /> یەکەم جووڵە بۆ تۆیە</span></div></div><div className="scene-stamp"><Coffee size={19} /><span>بێ پەلە،<br /><strong>بە چێژەوە.</strong></span><span className="stamp-star">✦</span></div><div className="scene-bottomline"><span className="board-edition latin">CLASSIC 8 × 8</span><button onClick={props.onPreferences}>تەختەکەت هەڵبژێرە <ChevronLeft size={13} /></button></div></div>
    </section>
    <section className="lobby-features" aria-label="وردەکاری یاری"><Feature icon={<LockKeyhole size={21} />} title="دانیشتنێکی تایبەت" text="لینکەکە لەگەڵ هاوڕێکانت هاوبەش بکە." /><Feature icon={<Users size={21} />} title="دوو کەس یاری، دوو کەس تماشا" text="هەمووان لە یەک ڕوومدا، بە گفتوگۆوە." /><Feature icon={<Sparkles size={21} />} title="بە سەلیقەی خۆت" text="ڕووکارێکی شەو و سێ شێوەی تەختە." /><Feature icon={<Crown size={21} />} title="هەمان دامەی خۆمان" text="یاساکان خۆکارانە لەلایەن یارییەکەوە دەپارێزرێن." /></section>
    <section className="how-it-works"><div className="steps-intro"><span className="overline">LET’S PLAY</span><h2>دانیشتنەکە لێرە دەست پێ دەکات.</h2><p>هەموو شتێک ئامادەیە؛ تەنیا هاوڕێکەت بانگ بکە.</p></div><div className="steps-list">{[{ number: "01", title: "ڕوومێک بۆ خۆتان", text: "ناوەکەت بنووسە و ڕوومەکەت دروست بکە." }, { number: "02", title: "لینکێک بۆ هاوڕێکەت", text: "لینکی تایبەتەکە کۆپی بکە و بۆی بنێرە." }, { number: "03", title: "با زیرەکی دەست پێ بکات", text: "بەردێک هەڵبژێرە؛ ئەوە یەکەم جووڵەتە." }].map(step => <article className="step" key={step.number}><span className="step-number latin">{step.number}</span><div><strong>{step.title}</strong><p>{step.text}</p></div></article>)}</div></section>
  </main>;
}

function Feature({ icon, title, text }: { icon: React.ReactNode; title: string; text: string }) {
  return <article className="feature"><span className="feature-icon">{icon}</span><h2>{title}</h2><p>{text}</p></article>;
}
