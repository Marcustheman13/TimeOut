import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { buildRequest, callModel, SCHEMA, writeDecision } from "./ai.ts";
import { fallbackDecision } from "./decision.ts";
import { buildReport, tilesFor } from "./report.ts";
import { computeStats, type WorkUser } from "./stats.ts";

const user: WorkUser = {
  userId: "u", timezone: "America/Denver", weekStart: "2026-11-02", enforce: true, minLimit: 0, streak: 3,
  usageByDay: { "2026-11-02": 30, "2026-11-03": 80 },
  overridesByDay: {}, penaltyByDay: {},
  challenges: [{ day: "2026-11-03", status: "won", pledge: 10, reward: 25, insured: false, leagues: ["nba"] }],
};
const stats = computeStats(user);

Deno.test("the report carries the words, the week range, the tiles and a day-by-day table", () => {
  const decision = fallbackDecision(stats);
  const report = buildReport("2026-11-02", stats, decision);
  assertEquals([report.version, report.weekStart, report.range], [1, "2026-11-02", "Nov 2 – Nov 8"]);
  assertEquals([report.headline, report.summary, report.insight], [decision.headline, decision.summary, decision.insight]);
  assertEquals(report.suggestion, decision.suggestion);
  assertEquals(report.tiles, tilesFor(stats));
  assertEquals(report.days?.length, 7);
  assertEquals(report.days?.[1], { weekday: "Tuesday", used: 80, limit: 60, status: "over" });
  assertEquals(report.days?.[0].status, "under");
  assertEquals(report.days?.[6].status, "none"); // the phone recorded nothing that day
});

Deno.test("the range handles a week that crosses a month and a year", () => {
  assertEquals(buildReport("2026-12-28", stats, fallbackDecision(stats)).range, "Dec 28 – Jan 3");
  assertEquals(buildReport("2026-10-26", stats, fallbackDecision(stats)).range, "Oct 26 – Nov 1");
});

Deno.test("no day-by-day table and no usage tiles when the phone hasn't synced usage", () => {
  const noUsage = computeStats({ ...user, usageByDay: {} });
  assertEquals(buildReport("2026-11-02", noUsage, fallbackDecision(noUsage)).days, null);
  assertEquals(tilesFor(noUsage).map((t) => t.label), ["Challenge record", "Net minutes", "Clean-day streak"]);
});

Deno.test("the Gemini request asks for JSON that matches the schema and carries only stats", () => {
  const body = buildRequest(stats) as { generationConfig: Record<string, unknown>; contents: { parts: { text: string }[] }[] };
  assertEquals(body.generationConfig.responseMimeType, "application/json");
  assertEquals(body.generationConfig.responseSchema, SCHEMA);
  const sent = body.contents[0].parts[0].text;
  assert(sent.includes('"daysUnderLimit":1'));
  for (const secret of ["2026-"]) assertEquals(sent.includes(secret), false, secret);
});

const reply = (status: number, body: unknown) => (() => Promise.resolve(new Response(typeof body === "string" ? body : JSON.stringify(body), { status }))) as unknown as typeof fetch;

Deno.test("callModel returns the parsed JSON and sends the key in a header, not the URL", async () => {
  let seen: { url: string; key: string | null } | undefined;
  const fake = ((url: string, init: RequestInit) => {
    seen = { url, key: new Headers(init.headers).get("x-goog-api-key") };
    return Promise.resolve(new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"skip":false}' }] } }] })));
  }) as unknown as typeof fetch;
  assertEquals(await callModel(stats, { apiKey: "KEY", model: "gemini-flash-lite-latest" }, fake), { skip: false });
  assertEquals(seen?.key, "KEY");
  assertEquals(seen?.url.includes("KEY"), false);
  assert(seen?.url.includes("gemini-flash-lite-latest:generateContent"));
});

Deno.test("callModel throws on a rate limit, an empty answer, and bad JSON, so the template takes over", async () => {
  await assertRejects(() => callModel(stats, { apiKey: "k", model: "m" }, reply(429, "quota")), Error, "Gemini 429");
  await assertRejects(() => callModel(stats, { apiKey: "k", model: "m" }, reply(200, { candidates: [{ finishReason: "SAFETY" }] })), Error, "no text");
  await assertRejects(() => callModel(stats, { apiKey: "k", model: "m" }, reply(200, { candidates: [{ content: { parts: [{ text: "not json" }] } }] })));
});

// MARK: writeDecision: the AI call, the checks, one retry, then the template

const good = {
  skip: false, weekType: "steady", tone: "calm", headline: "A steady week",
  summary: "You stayed under your limit on 1 of 2 tracked days and won 1 challenge.",
  insight: "Tuesday was your busiest day at 80 minutes.", suggestion: { kind: "keep_going", text: "Keep your routine going." },
};
const invented = { ...good, summary: "You won 9 challenges this week." };

/** A fetch that gives each call the next answer: a decision object, or a number for an HTTP error status. */
function answers(...list: (object | number)[]) {
  const requests: { contents: { role: string; parts: { text: string }[] }[] }[] = [];
  const fetcher = ((_url: string, init: RequestInit) => {
    requests.push(JSON.parse(String(init.body)));
    const next = list[Math.min(requests.length - 1, list.length - 1)];
    return Promise.resolve(
      typeof next === "number"
        ? new Response("error", { status: next })
        : Response.json({ candidates: [{ content: { parts: [{ text: JSON.stringify(next) }] } }] }),
    );
  }) as unknown as typeof fetch;
  return { fetcher, requests };
}
const waits: number[] = [];
const sleep = (ms: number) => { waits.push(ms); return Promise.resolve(); };
const config = { apiKey: "k", model: "m" };

Deno.test("writeDecision: a good first answer is used as it is", async () => {
  const { fetcher, requests } = answers(good);
  const written = await writeDecision(stats, config, { fetcher, sleep });
  assertEquals([written.source, written.attempts, written.note], ["ai", 1, null]);
  assertEquals(written.decision.headline, "A steady week");
  assertEquals(requests.length, 1);
});

Deno.test("writeDecision: a bad answer is sent back with the reason, and the corrected one is used", async () => {
  const { fetcher, requests } = answers(invented, good);
  const written = await writeDecision(stats, config, { fetcher, sleep });
  assertEquals([written.source, written.attempts], ["ai", 2]);
  assert(written.note?.includes("invented the number 9"));
  assertEquals(requests.length, 2);
  assertEquals(requests[1].contents.map((c) => c.role), ["user", "model", "user"]);
  assert(requests[1].contents[2].parts[0].text.includes("invented the number 9"));
});

Deno.test("writeDecision: two bad answers fall back to the template, with the reason", async () => {
  const { fetcher } = answers(invented);
  const written = await writeDecision(stats, config, { fetcher, sleep });
  assertEquals([written.source, written.attempts], ["fallback", 2]);
  assert(written.note?.includes("invented the number 9"));
  assert(written.decision.headline.length > 0);
});

Deno.test("writeDecision: a rate limit waits and tries again, with no feedback because there was no answer", async () => {
  waits.length = 0;
  const { fetcher, requests } = answers(429, good);
  const written = await writeDecision(stats, config, { fetcher, sleep });
  assertEquals([written.source, written.attempts], ["ai", 2]);
  assertEquals(waits, [4000]);
  assertEquals(requests[1].contents.length, 1);
});

Deno.test("writeDecision: an outage falls back to the template", async () => {
  const { fetcher } = answers(500);
  const written = await writeDecision(stats, config, { fetcher, sleep });
  assertEquals([written.source, written.attempts], ["fallback", 2]);
  assert(written.note?.includes("Gemini 500"));
});

Deno.test("writeDecision: no key means no call at all", async () => {
  const { fetcher, requests } = answers(good);
  const written = await writeDecision(stats, null, { fetcher, sleep });
  assertEquals([written.source, written.attempts, requests.length], ["fallback", 0, 0]);
});
