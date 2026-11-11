// What the AI decides about a week, the checks its answer must pass, and the plain template used when it fails.
// The AI is a step inside the pipeline, not in charge of it: nothing it writes goes out unless it passes validateDecision.

import { forModel, type WeekStats } from "./stats.ts";

export const WEEK_TYPES = ["crushed", "steady", "slipped", "risky"] as const;
export const TONES = ["celebratory", "encouraging", "calm", "direct"] as const;
export const SUGGESTION_KINDS = ["keep_going", "smaller_pledges", "tighten_limit", "ease_limit", "invite_friend", "take_a_break"] as const;

export type WeekType = typeof WEEK_TYPES[number];
export type Tone = typeof TONES[number];
export type SuggestionKind = typeof SUGGESTION_KINDS[number];

export interface Decision {
  /** True when the week is too thin to say anything useful. No email goes out. */
  skip: boolean;
  weekType: WeekType;
  tone: Tone;
  headline: string;
  summary: string;
  insight: string;
  suggestion: { kind: SuggestionKind; text: string };
}

const LIMITS = { headline: 90, summary: 450, insight: 240, suggestion: 240 };

/** Every number in the stats the AI was shown, plus 7 for "days in a week". Anything else it writes is invented. */
export function allowedNumbers(stats: WeekStats): Set<number> {
  const allowed = new Set<number>([7]);
  const walk = (value: unknown) => {
    if (typeof value === "number" && Number.isFinite(value)) {
      allowed.add(Math.abs(value));
    } else if (Array.isArray(value)) {
      value.forEach(walk);
    } else if (value && typeof value === "object") {
      Object.values(value).forEach(walk);
    }
  };
  walk(forModel(stats));
  return allowed;
}

export function numbersIn(text: string): number[] {
  return (text.match(/\d+(?:\.\d+)?/g) ?? []).map(Number);
}

function clean(value: unknown): string {
  // deno-lint-ignore no-control-regex
  return typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim() : "";
}

function underLimitRate(stats: WeekStats): number | null {
  return stats.usage ? stats.usage.daysUnderLimit / stats.usage.daysTracked : null;
}

export type Validation = { ok: true; decision: Decision } | { ok: false; reason: string };

export function validateDecision(raw: unknown, stats: WeekStats): Validation {
  if (!raw || typeof raw !== "object") return { ok: false, reason: "not an object" };
  const r = raw as Record<string, unknown>;

  const weekType = r.weekType as WeekType;
  const tone = r.tone as Tone;
  if (!WEEK_TYPES.includes(weekType)) return { ok: false, reason: "unknown weekType" };
  if (!TONES.includes(tone)) return { ok: false, reason: "unknown tone" };
  const s = (r.suggestion ?? {}) as Record<string, unknown>;
  const kind = s.kind as SuggestionKind;
  if (!SUGGESTION_KINDS.includes(kind)) return { ok: false, reason: "unknown suggestion kind" };

  const skip = r.skip === true;
  const headline = clean(r.headline);
  const summary = clean(r.summary);
  const insight = clean(r.insight);
  const suggestion = clean(s.text);
  if (!skip) {
    for (const [name, text] of [["headline", headline], ["summary", summary], ["insight", insight], ["suggestion", suggestion]] as const) {
      if (!text) return { ok: false, reason: `${name} is empty` };
      if (text.length > LIMITS[name]) return { ok: false, reason: `${name} is too long` };
      if (/https?:|www\.|[<>]/i.test(text)) return { ok: false, reason: `${name} has a link or markup` };
    }

    // Every number it writes has to be one it was given.
    const allowed = allowedNumbers(stats);
    for (const n of numbersIn([headline, summary, insight, suggestion].join(" "))) {
      if (!allowed.has(n)) return { ok: false, reason: `invented the number ${n}` };
    }

    // The decision can't contradict the numbers: calling a losing or over-limit week "crushed" is wrong.
    const rate = underLimitRate(stats);
    if (weekType === "crushed" && (stats.challenges.netMinutes < 0 || (rate !== null && rate < 0.6))) {
      return { ok: false, reason: "called a bad week crushed" };
    }
  }

  return { ok: true, decision: { skip, weekType, tone, headline, summary, insight, suggestion: { kind, text: suggestion } } };
}

// MARK: The template used when the AI is down, over its free limit, or answers with something that fails the checks

export function classifyWeek(stats: WeekStats): WeekType {
  const c = stats.challenges;
  const rate = underLimitRate(stats);
  if (c.lost >= 3 && c.netMinutes <= -30) return "risky";
  if ((stats.usage?.emergencyUnlocks ?? 0) >= 3) return "risky";
  if (c.netMinutes < 0 || (rate !== null && rate < 0.5)) return "slipped";
  // With screen-time records, staying under the limit is the signal. Without them, the person has to be ahead.
  const ahead = rate === null ? c.netMinutes > 0 && c.won > c.lost : rate >= 0.85 && c.netMinutes >= 0 && c.won >= c.lost;
  return ahead ? "crushed" : "steady";
}

const TONE_FOR: Record<WeekType, Tone> = { crushed: "celebratory", steady: "calm", slipped: "encouraging", risky: "direct" };

const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;

export function fallbackDecision(stats: WeekStats): Decision {
  const weekType = classifyWeek(stats);
  const c = stats.challenges;
  const u = stats.usage;
  const net = c.netMinutes >= 0 ? `+${c.netMinutes}` : `${c.netMinutes}`;

  const headline = {
    crushed: "A strong week",
    steady: "A steady week",
    slipped: "A tougher week",
    risky: "A week worth a closer look",
  }[weekType];

  const parts: string[] = [];
  if (u) parts.push(`You stayed under your limit on ${u.daysUnderLimit} of ${plural(u.daysTracked, "tracked day")}, averaging ${u.averageMinutes} minutes a day on your blocked apps.`);
  if (c.resolved > 0) parts.push(`Your ${plural(c.resolved, "challenge")} finished ${c.won}-${c.lost}${c.tied ? ` with ${c.tied} tied` : ""}, for ${net} minutes overall.`);
  if (parts.length === 0) parts.push("Not much happened this week.");

  let insight: string;
  if (u && u.changeVsLastWeekPercent !== null && u.changeVsLastWeekPercent !== 0) {
    insight = u.changeVsLastWeekPercent < 0
      ? `Your daily average on blocked apps is down ${Math.abs(u.changeVsLastWeekPercent)}% from last week.`
      : `Your daily average on blocked apps is up ${u.changeVsLastWeekPercent}% from last week.`;
  } else if (u) {
    insight = `${u.busiestDay.weekday} was your busiest day at ${u.busiestDay.minutes} minutes, and ${u.calmestDay.weekday} was your calmest at ${u.calmestDay.minutes}.`;
  } else if (c.resolved > 0 && c.winRatePercent !== null) {
    insight = `You won ${c.winRatePercent}% of the challenges that were decided.`;
  } else {
    insight = "Turn on app limits to see your screen time here next week.";
  }

  const suggestion: Decision["suggestion"] = {
    crushed: { kind: "keep_going" as const, text: "Keep the same routine going. It's clearly working." },
    steady: { kind: "keep_going" as const, text: "Keep your routine going and see if you can beat this week." },
    slipped: { kind: "smaller_pledges" as const, text: "Try smaller pledges next week so one bad night costs you less." },
    risky: { kind: "take_a_break" as const, text: "Consider sitting out a few challenges next week and letting your minutes build back up." },
  }[weekType];

  return { skip: false, weekType, tone: TONE_FOR[weekType], headline, summary: parts.join(" "), insight, suggestion };
}
