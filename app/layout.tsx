import type { Metadata, Viewport } from "next";
import "@fontsource/noto-sans-arabic/400.css";
import "@fontsource/noto-sans-arabic/500.css";
import "@fontsource/noto-sans-arabic/600.css";
import "@fontsource/noto-sans-arabic/700.css";
import "@fontsource/manrope/500.css";
import "@fontsource/manrope/700.css";
import "./globals.css";

export const metadata: Metadata = {
  title: "دامە | کاتێک بۆ هاوڕێکان",
  description: "دامەی کوردی بە ئۆنڵاین لەگەڵ هاوڕێکانت. ڕوومێک دروست بکە، لینکەکە بنێرە و یاری بکەن.",
  robots: { index: false, follow: false },
  icons: { icon: "/icon.svg" },
};
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#f6f4ee" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ckb" dir="rtl"><body>{children}</body></html>;
}
