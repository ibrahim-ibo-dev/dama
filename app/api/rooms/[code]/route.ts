import { actInRoom, entryGuard, errorResponse, getRoom, joinRoom, json, readBody, requestToken, validateCode } from "@/lib/server";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Context = { params: Promise<{ code: string }> };
export async function GET(request: Request, context: Context) {
  try { return json(await getRoom(validateCode((await context.params).code), requestToken(request))); }
  catch (error) { return errorResponse(error); }
}
export async function POST(request: Request, context: Context) {
  try {
    const token = requestToken(request), code = validateCode((await context.params).code);
    const body = await readBody(request);
    await entryGuard(request, body);
    return json(await joinRoom(code, body, token));
  } catch (error) { return errorResponse(error); }
}
export async function PATCH(request: Request, context: Context) {
  try {
    const token = requestToken(request), code = validateCode((await context.params).code);
    return json(await actInRoom(code, await readBody(request), token));
  } catch (error) { return errorResponse(error); }
}
