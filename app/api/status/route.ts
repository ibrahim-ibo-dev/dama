import { json } from "@/lib/server";
import { storageMode } from "@/lib/store";
export const dynamic = "force-dynamic";
export function GET() { return json({ mode: storageMode(), passwordRequired: Boolean(process.env.SITE_PASSWORD) }); }
