import { createRoom, entryGuard, errorResponse, json, readBody, requestToken } from "@/lib/server";
export const runtime = "nodejs";
export async function POST(request: Request) {
  try {
    const token = requestToken(request);
    const body = await readBody(request);
    await entryGuard(request, body, true);
    return json(await createRoom(body, token), 201);
  } catch (error) { return errorResponse(error); }
}
