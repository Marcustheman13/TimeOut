// Turns one person's raw numbers from timeout_weekly_report_work into the week's stats.
// Everything the AI is allowed to say comes from here: it never does arithmetic, it only writes about these numbers.
// Plain TypeScript with no network calls, so it is easy to test.

// The same rules as the apps (Rules.daily and Rules.overrideMinutes in Models.swift).
const DAILY_MINUTES = 60;
const OVERRIDE_MINUTES = 15;

export interface WorkChallenge {
  day: string; // the local date it was graded, YYYY-MM-DD
  status: "won" | "lost" | "tied";
  pledge: number;
  reward: number;
  insured: boolean;
  leagues: string[];
}

export interface WorkUser {
  userId: string;
  timezone: string;
  weekStart: string; // the Monday, YYYY-MM-DD
  enforce: boolean;
  minLimit: number;
  streak: number;
  usageByDay: unknown;
  overridesByDay: unknown;
  penaltyByDay: unknown;
  challenges: WorkChallenge[];
}

export interface DayStat {
  weekday: string;
  /** Minutes on the blocked apps, or null when the phone didn't record that day. */
  used: number | null;
  limit: number;
  overLimit: boolean | null;
  emergencyUnlocks: number;
}

export interface UsageStats {
  daysTracked: number;
  daysUnderLimit: number;
  totalMinutes: number;
  averageMinutes: number;
  busiestDay: { weekday: string; minutes: number };
  calmestDay: { weekday: string; minutes: number };
  emergencyUnlocks: number;
  lastWeekAverageMinutes: number | null;
  changeVsLastWeekPercent: number | null;
}

export interface ChallengeStats {
  resolved: number;
  won: number;
  lost: number;
  tied: number;
  winRatePercent: number | null;
  netMinutes: number;
  bestWinMinutes: number;
  topLeague: string | null;
  lastWeekResolved: number;
  lastWeekWon: number;
  lastWeekNetMinutes: number;
}

export interface WeekStats {
  /** False until the phone has synced screen-time records, so the report must not talk about usage. */
  hasUsage: boolean;
  hasActivity: boolean;
  streakDays: number;
  usage: UsageStats | null;
  challenges: ChallengeStats;
  days: DayStat[];
}

const WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

export function addDays(day: string, n: number): string {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** day -> whole minutes, ignoring anything that isn't a plain number (the ledger is JSON the phones write). */
export function minutesByDay(value: unknown): Record<string, number> {
  const out: Record<string, number> = {};
  if (!value || typeof value !== "object" || Array.isArray(value)) return out;
  for (const [day, minutes] of Object.entries(value)) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(day) && typeof minutes === "number" && Number.isFinite(minutes) && minutes >= 0) {
      out[day] = Math.round(minutes);
    }
  }
  return out;
}

/** What a challenge did to the wallet: reward (which includes the pledge) minus the pledge. */
export function netOf(c: WorkChallenge): number {
  return c.reward - c.pledge;
}

const LEAGUE = /^[a-z0-9_-]{1,12}$/i;

function challengeStats(all: WorkChallenge[], weekStart: string): ChallengeStats {
  const weekEnd = addDays(weekStart, 6);
  const lastStart = addDays(weekStart, -7);
  const mine = all.filter((c) => c.day >= weekStart && c.day <= weekEnd);
  const last = all.filter((c) => c.day >= lastStart && c.day < weekStart);

  const won = mine.filter((c) => c.status === "won").length;
  const lost = mine.filter((c) => c.status === "lost").length;
  const decided = won + lost;

  const leagueCounts = new Map<string, number>();
  for (const c of mine) {
    for (const league of new Set(c.leagues)) {
      if (LEAGUE.test(league)) leagueCounts.set(league.toLowerCase(), (leagueCounts.get(league.toLowerCase()) ?? 0) + 1);
    }
  }
  const top = [...leagueCounts].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0];

  return {
    resolved: mine.length,
    won,
    lost,
    tied: mine.length - won - lost,
    winRatePercent: decided > 0 ? Math.round((won / decided) * 100) : null,
    netMinutes: mine.reduce((sum, c) => sum + netOf(c), 0),
    bestWinMinutes: Math.max(0, ...mine.filter((c) => c.status === "won").map(netOf)),
    topLeague: top ? top[0] : null,
    lastWeekResolved: last.length,
    lastWeekWon: last.filter((c) => c.status === "won").length,
    lastWeekNetMinutes: last.reduce((sum, c) => sum + netOf(c), 0),
  };
}

export function computeStats(user: WorkUser): WeekStats {
  const usage = minutesByDay(user.usageByDay);
  const overrides = minutesByDay(user.overridesByDay);
  const penalties = minutesByDay(user.penaltyByDay);

  const netByDay = new Map<string, number>();
  for (const c of user.challenges) netByDay.set(c.day, (netByDay.get(c.day) ?? 0) + netOf(c));

  // The limit works the way the app works it out: 60, plus the day before's results, minus emergency-unlock
  // penalties, never below the person's own floor, plus 15 minutes for each emergency unlock that day.
  const limitFor = (day: string) =>
    Math.max(DAILY_MINUTES + (netByDay.get(addDays(day, -1)) ?? 0) - (penalties[day] ?? 0), user.minLimit, 0) +
    (overrides[day] ?? 0) * OVERRIDE_MINUTES;

  const days: DayStat[] = WEEKDAYS.map((weekday, i) => {
    const day = addDays(user.weekStart, i);
    const used = day in usage ? usage[day] : null;
    const limit = limitFor(day);
    return { weekday, used, limit, overLimit: used === null ? null : used > limit, emergencyUnlocks: overrides[day] ?? 0 };
  });

  const tracked = days.filter((d) => d.used !== null);
  let usageStats: UsageStats | null = null;
  if (tracked.length > 0) {
    const minutes = tracked.map((d) => d.used as number);
    const total = minutes.reduce((a, b) => a + b, 0);
    const average = Math.round(total / tracked.length);
    const busiest = tracked.reduce((a, b) => ((b.used as number) > (a.used as number) ? b : a));
    const calmest = tracked.reduce((a, b) => ((b.used as number) < (a.used as number) ? b : a));

    const lastDays = WEEKDAYS.map((_, i) => addDays(user.weekStart, i - 7)).filter((day) => day in usage);
    const lastAverage = lastDays.length > 0 ? Math.round(lastDays.reduce((sum, day) => sum + usage[day], 0) / lastDays.length) : null;

    usageStats = {
      daysTracked: tracked.length,
      daysUnderLimit: tracked.filter((d) => d.overLimit === false).length,
      totalMinutes: total,
      averageMinutes: average,
      busiestDay: { weekday: busiest.weekday, minutes: busiest.used as number },
      calmestDay: { weekday: calmest.weekday, minutes: calmest.used as number },
      emergencyUnlocks: days.reduce((sum, d) => sum + d.emergencyUnlocks, 0),
      lastWeekAverageMinutes: lastAverage,
      changeVsLastWeekPercent: lastAverage && lastAverage > 0 ? Math.round(((average - lastAverage) / lastAverage) * 100) : null,
    };
  }

  const challenges = challengeStats(user.challenges, user.weekStart);
  return {
    hasUsage: usageStats !== null,
    hasActivity: usageStats !== null || challenges.resolved > 0,
    streakDays: Math.max(0, Math.round(user.streak)),
    usage: usageStats,
    challenges,
    days,
  };
}

/** What the AI gets to see. Only numbers and fixed words, no names or dates. */
export function forModel(stats: WeekStats): Record<string, unknown> {
  return {
    hasUsage: stats.hasUsage,
    streakDays: stats.streakDays,
    usage: stats.usage,
    challenges: stats.challenges,
    days: stats.hasUsage ? stats.days.map((d) => ({ weekday: d.weekday, used: d.used, limit: d.limit, overLimit: d.overLimit })) : undefined,
  };
}
