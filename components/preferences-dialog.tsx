"use client";

import { Check, Grid2X2, Lightbulb, Moon, Sun, Volume2 } from "lucide-react";
import Modal from "./modal";

export type Preferences = { theme: "light" | "dark"; board: "walnut" | "olive" | "slate"; sound: boolean; coordinates: boolean; hints: boolean };
export const defaultPreferences: Preferences = { theme: "light", board: "walnut", sound: true, coordinates: true, hints: true };

export default function PreferencesDialog({ preferences, onChange, onClose }: {
  preferences: Preferences; onChange: (next: Preferences) => void; onClose: () => void;
}) {
  return <Modal title="بە شێوەی خۆت یاری بکە" onClose={onClose} className="preferences-modal">
    <p className="modal-description">ئەو ڕووکار و وردەکارییانە هەڵبژێرە کە بۆ تۆ ئاسوودەترن. هەڵبژاردنەکانت لەسەر ئەم ئامێرە دەپارێزرێن.</p>
    <fieldset className="preference-section"><legend>ڕووناکی ڕووکار</legend><div className="appearance-options">{([{ id: "light", label: "ڕۆژ", icon: Sun }, { id: "dark", label: "شەو", icon: Moon }] as const).map(option => <button type="button" key={option.id} className={preferences.theme === option.id ? "chosen" : ""} aria-pressed={preferences.theme === option.id} onClick={() => onChange({ ...preferences, theme: option.id })}><option.icon size={19} /><span>{option.label}</span>{preferences.theme === option.id && <Check size={16} />}</button>)}</div></fieldset>
    <fieldset className="preference-section"><legend>شێوەی تەختە</legend><div className="board-theme-options">{([{ id: "walnut", label: "داری گوێز" }, { id: "olive", label: "زەیتوون" }, { id: "slate", label: "بەردی شین" }] as const).map(option => <button type="button" key={option.id} aria-pressed={preferences.board === option.id} className={preferences.board === option.id ? "chosen" : ""} onClick={() => onChange({ ...preferences, board: option.id })}><span className={`theme-swatch swatch-${option.id}`}><i /><i /><i /><i /></span><span>{option.label}</span>{preferences.board === option.id && <Check size={14} />}</button>)}</div></fieldset>
    <div className="preference-switches"><PreferenceSwitch icon={<Volume2 size={18} />} title="دەنگی جووڵەکان" description="دەنگێکی نەرم لەگەڵ هەر جووڵەیەک" checked={preferences.sound} onChange={() => onChange({ ...preferences, sound: !preferences.sound })} /><PreferenceSwitch icon={<Grid2X2 size={18} />} title="پیت و ژمارەی خانەکان" description="ئاسانتر شوێنی بەردەکان بناسەوە" checked={preferences.coordinates} onChange={() => onChange({ ...preferences, coordinates: !preferences.coordinates })} /><PreferenceSwitch icon={<Lightbulb size={18} />} title="ئاماژەی جووڵەکان" description="شوێنە ڕێگەپێدراوەکان ڕوون بکەرەوە" checked={preferences.hints} onChange={() => onChange({ ...preferences, hints: !preferences.hints })} /></div>
    <button className="primary-button modal-done" onClick={onClose}><Check size={17} /> تەواو، ئامادەم</button>
  </Modal>;
}

function PreferenceSwitch({ icon, title, description, checked, onChange }: { icon: React.ReactNode; title: string; description: string; checked: boolean; onChange: () => void }) {
  return <button type="button" className="preference-switch" role="switch" aria-checked={checked} aria-label={title} onClick={onChange}><span className="preference-icon">{icon}</span><span className="switch-label"><strong>{title}</strong><small>{description}</small></span><span className={`switch-track ${checked ? "is-on" : ""}`}><span /></span></button>;
}
