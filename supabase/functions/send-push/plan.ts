// Decides what to send. No network here, so it can all be tested.
// The grading mirrors Feed.grade, Sim.gradeScore and Store.outcome in the iOS app.
// The device stays in charge of a challenge's real result: this only ever words a notification.

export interface WorkPick {
  eventId: string;
  league: string | null;
  matchup: string | null;
  market: string;
  side: string | null;
  line: number | null;
  price: number | null;
  result: string | null;
}

export interface WorkChallenge {
  id: string;
  userId: string;
  status: string;
  pledgeMinutes: number;
  rewardMinutes: number | null;
  insured: boolean | null;
  multiplier: number | null;
  picks: WorkPick[];
}

export interface WorkRequest {
  key: string;
  userId: string;
  username: string;
}

export interface GameState {
  state: "final" | "void" | "pending";
  home: number;
  away: number;
}

export interface PlannedPush {
  key: string;
  userId: string;
  title: string;
  body: string;
  tab: "social" | "challenges";
  // Matches the id of the iPhone's own notification, so the two replace each other rather than doubling up.
  collapseId: string;
}

const MAX_ALLOWED_MINUTES = 120; // Rules.maxAllowedMinutes

const LEAGUE_PATHS: Record<string, string> = {
  nfl: "football/nfl",
  ncaaf: "football/college-football",
  nba: "basketball/nba",
  mlb: "baseball/mlb",
  nhl: "hockey/nhl",
  epl: "soccer/eng.1",
};

// Stored ids look like espn-nba-401909907. Anything else is a practice game ESPN has never heard of.
export function espnEventId(id: string): string | null {
  return id.match(/(?:^|-)(\d+)$/)?.[1] ?? null;
}

export function summaryPath(pick: Pick<WorkPick, "league" | "eventId">): string | null {
  const path = pick.league ? LEAGUE_PATHS[pick.league] : undefined;
  const event = espnEventId(pick.eventId);
  return path && event ? `${path}/summary?event=${event}` : null;
}

// deno-lint-ignore no-explicit-any
export function parseSummary(json: any): GameState | null {
  const comp = json?.header?.competitions?.[0];
  const status = comp?.status?.type;
  const home = comp?.competitors?.find((c: { homeAway?: string }) => c.homeAway === "home");
  const away = comp?.competitors?.find((c: { homeAway?: string }) => c.homeAway === "away");
  if (!status || !home || !away) return null;
  const name = String(status.name ?? "");
  const scores = { home: Number(home.score) || 0, away: Number(away.score) || 0 };
  if (["POSTPONED", "CANCELED", "CANCELLED", "ABANDONED", "FORFEIT"].some((s) => name.includes(s))) {
    return { state: "void", ...scores };
  }
  return { state: status.state === "post" ? "final" : "pending", ...scores };
}

export function gradeScore(market: string, side: string, line: number | null, H: number, A: number): string {
  switch (market) {
    case "winner":
      if (side === "draw") return H === A ? "won" : "lost";
      if (H === A) return "lost";
      return (side === "home") === (H > A) ? "won" : "lost";
    case "margin": {
      const m = (side === "home" ? H - A : A - H) + (line ?? 0);
      return m > 0 ? "won" : m < 0 ? "lost" : "tie";
    }
    case "total": {
      const total = H + A;
      if (line !== null && total === line) return "tie";
      return (side === "higher") === (total > (line ?? 0)) ? "won" : "lost";
    }
    default:
      return "pending";
  }
}

function gradePick(pick: WorkPick, game: GameState | undefined): string {
  if (!game || game.state === "pending") return "pending";
  if (game.state === "void") return "void";
  return gradeScore(pick.market, pick.side ?? "", pick.line, game.home, game.away);
}

function decimal(price: number): number {
  return price > 0 ? 1 + price / 100 : 1 + 100 / Math.abs(price);
}

export interface Outcome {
  status: "open" | "won" | "lost" | "tie" | "void";
  reward: number;
  insurancePaid: boolean;
}

export function outcome(c: Pick<WorkChallenge, "pledgeMinutes" | "insured" | "multiplier">, results: { result: string; price: number | null }[]): Outcome {
  const lost = results.filter((r) => r.result === "lost").length;
  const pending = results.some((r) => r.result === "pending");
  if (lost > 0) {
    if (c.insured) {
      if (pending) return { status: "open", reward: 0, insurancePaid: false };
      if (lost === 1) return { status: "tie", reward: c.pledgeMinutes, insurancePaid: true };
    }
    return { status: "lost", reward: 0, insurancePaid: false };
  }
  if (pending) return { status: "open", reward: 0, insurancePaid: false };
  const won = results.filter((r) => r.result === "won");
  if (won.length === 0) {
    return { status: results.every((r) => r.result === "void") ? "void" : "tie", reward: c.pledgeMinutes, insurancePaid: false };
  }
  const dec = won.reduce((product, r) => product * decimal(r.price ?? 100), 1);
  const raw = Math.round(c.pledgeMinutes * dec);
  const reward = c.pledgeMinutes + Math.round((raw - c.pledgeMinutes) * (c.multiplier ?? 1));
  return { status: "won", reward: Math.min(reward, MAX_ALLOWED_MINUTES), insurancePaid: false };
}

function fmtLine(line: number, signed = true): string {
  const body = Number.isInteger(line) ? String(line) : line.toFixed(1);
  return signed && line > 0 ? `+${body}` : body;
}

export function pickLabel(p: Pick<WorkPick, "market" | "side" | "line" | "matchup">): string {
  const matchup = p.matchup ?? "";
  const teams = matchup.split(" @ ");
  const team = p.side === "away" ? teams[0] : p.side === "home" && teams.length > 1 ? teams[teams.length - 1] : null;
  switch (p.market) {
    case "winner":
      return team ? `${team} to win` : "Draw";
    case "margin":
      return `${team ?? ""} ${fmtLine(p.line ?? 0)}`;
    case "total":
      return `Combined score ${p.side === "higher" ? "above" : "below"} ${fmtLine(p.line ?? 0, false)}`;
    default:
      return matchup;
  }
}

function challengeTitle(c: WorkChallenge): string {
  if (c.picks.length > 1) return `${c.picks.length}-pick Combo Goal`;
  return c.picks[0] ? pickLabel(c.picks[0]) : "Challenge";
}

function resultPush(c: WorkChallenge, o: Outcome): PlannedPush {
  const title = challengeTitle(c);
  const base = { key: `challenge:${c.id}`, userId: c.userId, tab: "challenges" as const, collapseId: c.id };
  if (o.status === "won") {
    return { ...base, title: `Challenge complete: ${title}`, body: `+${o.reward - c.pledgeMinutes} earned minutes added to tomorrow's phone time.` };
  }
  if (o.status === "lost") {
    return { ...base, title: `Challenge missed: ${title}`, body: `${c.pledgeMinutes} committed minutes deducted from tomorrow's phone time.` };
  }
  const why = o.insurancePaid
    ? "Miss-one protection returned your minutes."
    : o.status === "void"
    ? "The game was postponed."
    : "It finished exactly on the target.";
  return { ...base, title: `Challenge returned: ${title}`, body: `${why} ${c.pledgeMinutes} minutes are available again.` };
}

// The result another device already saved, in the app's words.
function savedOutcome(c: WorkChallenge): Outcome {
  const reward = c.rewardMinutes ?? 0;
  switch (c.status) {
    case "won":
      return { status: "won", reward, insurancePaid: false };
    case "lost":
      return { status: "lost", reward, insurancePaid: false };
    case "voided":
    case "cancelled":
      return { status: "void", reward, insurancePaid: false };
    default:
      return { status: "tie", reward, insurancePaid: Boolean(c.insured) && c.picks.some((p) => p.result === "loss") };
  }
}

export function planRequest(r: WorkRequest): PlannedPush {
  return {
    key: r.key,
    userId: r.userId,
    title: `@${r.username} sent you a friend request`,
    body: "Open Social to accept it.",
    tab: "social",
    collapseId: `request-${r.username}`,
  };
}

// Null while the challenge is still being played.
export function planChallenge(c: WorkChallenge, games: Map<string, GameState>): PlannedPush | null {
  if (c.status !== "pending") return resultPush(c, savedOutcome(c));
  const results = c.picks.map((p) => ({ result: gradePick(p, games.get(p.eventId)), price: p.price }));
  if (results.length === 0) return null;
  const o = outcome(c, results);
  return o.status === "open" ? null : resultPush(c, o);
}
