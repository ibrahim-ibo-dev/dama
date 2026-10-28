"use client";

import { ArrowDown, ArrowLeft, ArrowRight, ArrowUp, ArrowUpLeft, Crown, Handshake, Keyboard, Trophy } from "lucide-react";
import Modal from "./modal";

export default function RulesDialog({ onClose }: { onClose: () => void }) {
  return <Modal title="جووڵەیەکی بچووک، بیرکردنەوەیەکی گەورە" onClose={onClose} className="rules-modal">
    <p className="modal-description">دامەی کوردی / تورکی · تەختەی ٨ × ٨ · ١٦ بەرد بۆ هەر یاریزان. سپی یەکەم جووڵە دەکات.</p>
    <div className="rules-diagrams"><div><div className="movement-diagram"><ArrowUp className="direction-up" size={20} /><ArrowLeft className="direction-left" size={20} /><span className="rule-disc" /><ArrowRight className="direction-right" size={20} /></div><strong>بەردی ئاسایی</strong><span>پێشەوە، ڕاست و چەپ</span></div><div><div className="movement-diagram"><ArrowUp className="direction-up" size={20} /><ArrowLeft className="direction-left" size={20} /><span className="rule-disc"><Crown size={18} /></span><ArrowRight className="direction-right" size={20} /><ArrowDown className="direction-down" size={20} /></div><strong>دامە</strong><span>هەر چوار ئاراستە، بە ڕاستی</span></div></div>
    <div className="rule-details"><article><span className="rule-index">01</span><div><h3>یەک هەڵبژێرە، یەک بجووڵێنە</h3><p>بەردێک دابگرە، پاشان خانەی نیشانکراو هەڵبژێرە. بەردی ئاسایی یەک خانە دەجووڵێت؛ بۆ دواوە یان بە لار ناجووڵێت و ناخوات.</p></div></article><article><span className="rule-index">02</span><div><h3>خواردن ناچارییە؛ زۆرترین بەرد بخۆ</h3><p>بەسەر بەردی بەرامبەر باز بدە و لە خانەی بەتاڵ بنیشە. ئەگەر چەند ڕێگایەک هەبوو، زۆرترین ژمارە هەڵبژێرە. خواردنی زنجیرەیی تا کۆتایی بەردەوام بکە؛ بەردی خوراو یەکسەر لادەبرێت.</p></div></article><article><span className="rule-index">03</span><div><h3>بەردەکەت بکە بە دامە</h3><p>بەردەکەت لە کۆتایی نۆرەکەدا بگاتە ڕیزی دواوەی بەرامبەر، دەبێتە دامە. دامە چەند خانەیەک دەجووڵێت و دەخوات؛ لە نێوان دوو خواردندا ناتوانێت یەکسەر ١٨٠ پلە بگەڕێتەوە.</p></div></article></div>
    <div className="rules-outcomes"><div><Trophy size={18} /><strong>بردنەوە</strong><p>هەموو بەردەکانی بەرامبەر بخۆ یان ڕێی هەموو جووڵەکانی ببەستە.</p></div><div><Handshake size={19} /><strong>یەکسانی</strong><p>بە ڕەزامەندی هەردووک، یان سێ جار دووبارەبوونەوەی هەمان دۆخ. یەک بەرد بەرامبەر یەک بەرد یەکسانن؛ دامە بەرامبەر ئاسایی دەباتەوە.</p></div></div>
    <div className="keyboard-note"><Keyboard size={17} /><span>بە دوگمەکانی تیر ئاراستەکان بگۆڕە؛ بە Enter بەرد و خانە هەڵبژێرە.</span></div><button className="primary-button modal-done" onClick={onClose}>تێگەیشتم، با یاری بکەین <ArrowUpLeft size={19} /></button>
  </Modal>;
}
