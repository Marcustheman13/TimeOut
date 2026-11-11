// Builds the report the apps show, from the stats and the AI's decision. The numbers and layout hints come from code;
// the words come from the decision. The apps only draw this, so the website and the iPhone app can't disagree.

import type { Decision, SuggestionKind, WeekType } from "./decision.ts";
import { addDays, type WeekStats } from "./stats.ts";

export interface Tile {
  label: string;
  value: string;
}

export interface ReportDay {
  weekday: string;
  /** Minutes on the blocked apps, or null when the phone didn't record that day. */
  used: number | null;
  limit: number;
  status: "under" | "over" | "none";
}

export interface Report {
  version: 1;
  weekStart: string; // the Monday, YYYY-MM-DD
  range: string; // "Nov 2 – Nov 8", ready to show
  weekType: WeekType;
  label: string; // short badge text for the week type
  tone: string;
  headline: string;
  summary: string;
  insight: string;
  suggestion: { kind: SuggestionKind; text: string };
  tiles: Tile[];
  /** The day-by-day table, or null when the phone hasn't recorded screen time yet. */
  days: ReportDay[] | null;
}

const LABEL: Record<WeekType, string> = { crushed: "Crushed it", steady: "Steady", slipped: "Tough week", risky: "Worth a look" };
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const signed = (n: number) => (n > 0 ? `+${n}` : `${n}`);

function shortDate(day: string): string {
  const [, month, date] = day.split("-").map(Number);
  return `${MONTHS[month - 1]} ${date}`;
}

export function tilesFor(stats: WeekStats): Tile[] {
  const c = stats.challenges;
  const tiles: Tile[] = [];
  if (stats.usage) tiles.push({ label: "Days under limit", value: `${stats.usage.daysUnderLimit} of ${stats.usage.daysTracked}` });
  if (c.resolved > 0) {
    tiles.push({ label: "Challenge record", value: `${c.won}–${c.lost}` });
    tiles.push({ label: "Net minutes", value: signed(c.netMinutes) });
  }
  if (stats.usage) tiles.push({ label: "Daily average", value: `${stats.usage.averageMinutes} min` });
  if (stats.streakDays > 0 && tiles.length < 4) tiles.push({ label: "Clean-day streak", value: `${stats.streakDays}` });
  return tiles.slice(0, 4);
}

export function buildReport(weekStart: string, stats: WeekStats, decision: Decision): Report {
  return {
    version: 1,
    weekStart,
    range: `${shortDate(weekStart)} – ${shortDate(addDays(weekStart, 6))}`,
    weekType: decision.weekType,
    label: LABEL[decision.weekType],
    tone: decision.tone,
    headline: decision.headline,
    summary: decision.summary,
    insight: decision.insight,
    suggestion: { kind: decision.suggestion.kind, text: decision.suggestion.text },
    tiles: tilesFor(stats),
    days: stats.hasUsage
      ? stats.days.map((d) => ({
        weekday: d.weekday,
        used: d.used,
        limit: d.limit,
        status: d.used === null ? "none" : d.overLimit ? "over" : "under",
      }))
      : null,
  };
}
