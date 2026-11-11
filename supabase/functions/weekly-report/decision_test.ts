import { assertEquals } from "jsr:@std/assert@1";
import { classifyWeek, type Decision, fallbackDecision, numbersIn, validateDecision } from "./decision.ts";
import { computeStats, type WorkChallenge, type WorkUser } from "./stats.ts";

const WEEK = "2026-11-02";

const challenge = (day: string, status: WorkChallenge["status"], pledge: number, reward: number): WorkChallenge => ({
  day, status, pledge, reward, insured: false, leagues: ["nba"],
});

const statsFor = (over: Partial<WorkUser>) =>
  computeStats({
    userId: "u", email: "a@b.c", name: null, timezone: "America/Denver", weekStart: WEEK, enforce: true, minLimit: 0,
    streak: 0, usageByDay: {}, overridesByDay: {}, penaltyByDay: {}, challenges: [], ...over,
  });

// 5 of 6 days under the limit, and two challenge wins.
const goodWeek = () =>
  statsFor({
    usageByDay: { "2026-11-02": 30, "2026-11-03": 40, "2026-11-04": 50, "2026-11-05": 20, "2026-11-06": 35, "2026-11-07": 90 },
    challenges: [challenge("2026-11-03", "won", 10, 25), challenge("2026-11-05", "won", 10, 30)],
  });

const decision = (over: Partial<Record<string, unknown>> = {}) => ({
  skip: false,
  weekType: "crushed",
  tone: "celebratory",
  headline: "Five clean days",
  summary: "You stayed under your limit on 5 of 6 tracked days and won 2 challenges.",
  insight: "Saturday was your only slip, at 90 minutes.",
  suggestion: { kind: "keep_going", text: "Keep the same routine going." },
  ...over,
});

Deno.test("a good answer passes", () => {
  const result = validateDecision(decision(), goodWeek());
  assertEquals(result.ok, true);
});

Deno.test("an invented number is rejected", () => {
  const result = validateDecision(decision({ summary: "You stayed under your limit on 6 of 6 days and won 9 challenges." }), goodWeek());
  assertEquals(result, { ok: false, reason: "invented the number 9" });
});

Deno.test("unknown enums, empty text and over-long text are rejected", () => {
  const stats = goodWeek();
  assertEquals(validateDecision(decision({ weekType: "amazing" }), stats).ok, false);
  assertEquals(validateDecision(decision({ tone: "sarcastic" }), stats).ok, false);
  assertEquals(validateDecision(decision({ suggestion: { kind: "bet_more", text: "x" } }), stats).ok, false);
  assertEquals(validateDecision(decision({ headline: "   " }), stats).ok, false);
  assertEquals(validateDecision(decision({ insight: "a".repeat(300) }), stats).ok, false);
  assertEquals(validateDecision(null, stats).ok, false);
  assertEquals(validateDecision("hello", stats).ok, false);
});

Deno.test("links and markup are rejected", () => {
  const stats = goodWeek();
  assertEquals(validateDecision(decision({ insight: "See https://example.com for more." }), stats).ok, false);
  assertEquals(validateDecision(decision({ insight: "Nice <b>work</b>." }), stats).ok, false);
});

Deno.test("calling a losing week crushed is rejected", () => {
  const losing = statsFor({ challenges: [challenge("2026-11-03", "lost", 20, 0), challenge("2026-11-04", "lost", 15, 0)] });
  const result = validateDecision(decision({ summary: "A great 2 challenges.", insight: "Nice.", headline: "Great" }), losing);
  assertEquals(result, { ok: false, reason: "called a bad week crushed" });
});

Deno.test("a skip needs no text, and passes", () => {
  const empty = statsFor({});
  const result = validateDecision({ skip: true, weekType: "steady", tone: "calm", headline: "", summary: "", insight: "", suggestion: { kind: "keep_going", text: "" } }, empty);
  assertEquals(result.ok && result.decision.skip, true);
});

Deno.test("numbersIn finds whole numbers and decimals", () => {
  assertEquals(numbersIn("5 of 7 days, up 12.5% and 3 won"), [5, 7, 12.5, 3]);
  assertEquals(numbersIn("no digits"), []);
});

Deno.test("weeks are classified from the numbers", () => {
  assertEquals(classifyWeek(goodWeek()), "steady"); // 5 of 6 under is 83%, just short of "crushed" and well clear of "slipped"
  const great = statsFor({
    usageByDay: { "2026-11-02": 30, "2026-11-03": 40, "2026-11-04": 50 },
    challenges: [challenge("2026-11-03", "won", 10, 25)],
  });
  assertEquals(classifyWeek(great), "crushed");
  const risky = statsFor({
    challenges: [challenge("2026-11-02", "lost", 20, 0), challenge("2026-11-03", "lost", 20, 0), challenge("2026-11-04", "lost", 20, 0)],
  });
  assertEquals(classifyWeek(risky), "risky");
  const flat = statsFor({ challenges: [challenge("2026-11-02", "won", 10, 20), challenge("2026-11-03", "lost", 10, 0), challenge("2026-11-04", "tied", 10, 10)] });
  assertEquals(classifyWeek(flat), "steady");
});

Deno.test("the template's own words pass the same checks the AI's do", () => {
  const cases = [
    goodWeek(),
    statsFor({ challenges: [challenge("2026-11-03", "won", 10, 25), challenge("2026-11-04", "lost", 20, 0), challenge("2026-11-05", "tied", 5, 5)] }),
    statsFor({ usageByDay: { "2026-11-02": 30, "2026-10-26": 60 } }),
    statsFor({ usageByDay: { "2026-11-02": 80, "2026-11-03": 20 } }),
    statsFor({ challenges: [challenge("2026-11-02", "lost", 20, 0), challenge("2026-11-03", "lost", 20, 0), challenge("2026-11-04", "lost", 20, 0)] }),
  ];
  for (const stats of cases) {
    const fallback: Decision = fallbackDecision(stats);
    const result = validateDecision(fallback, stats);
    assertEquals(result.ok, true, JSON.stringify(result) + " " + fallback.summary);
  }
});

Deno.test("the template doesn't mention screen time when there is no usage", () => {
  const text = JSON.stringify(fallbackDecision(statsFor({ challenges: [challenge("2026-11-03", "won", 10, 25)] })));
  assertEquals(/blocked apps|tracked day|limit/i.test(text), false);
});
