import type { Color, Game } from "./game";

export type Role = Color | "spectator";
export type Member = { id: string; name: string; role: Role; tokenHash: string; lastSeen: number };
export type RoomMessage = { id: string; memberId: string; name: string; text: string; createdAt: number };
export type MatchResult = { gameId: string; winnerId: string | null; reason: Game["reason"]; finishedAt: number };
export type Room = {
  code: string;
  createdAt: number;
  updatedAt: number;
  revision: number;
  members: Member[];
  game: Game;
  started: boolean;
  drawOffer: Color | null;
  rematchVotes: string[];
  messages: RoomMessage[];
  results: MatchResult[];
};
export type PublicRoom = Omit<Room, "members" | "game"> & {
  members: Omit<Member, "tokenHash">[];
  game: Omit<Game, "positions">;
  me: string;
};
export type RoomAction =
  | { type: "move"; from: number; path: number[]; ply: number; gameId: string }
  | { type: "resign"; gameId: string }
  | { type: "draw"; gameId: string }
  | { type: "decline-draw"; gameId: string }
  | { type: "rematch"; gameId: string }
  | { type: "message"; text: string }
  | { type: "heartbeat" }
  | { type: "leave" };
