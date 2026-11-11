import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { buildRequest, callModel, SCHEMA } from "./ai.ts";
import { fallbackDecision } from "./decision.ts";
import { esc, renderEmail, tilesFor } from "./email.ts";
import { computeStats, type WorkUser } from "./stats.ts";

const user: WorkUser = {
  userId: "u", email: "a@b.c", name: "Sam Lee", timezone: "America/Denver", weekStart: "2026-11-02", enforce: true, minLimit: 0, streak: 3,
  usageByDay: { "2026-11-02": 30, "2026-11-03": 80 },
  overridesByDay: {}, penaltyByDay: {},
  challenges: [{ day: "2026-11-03", status: "won", pledge: 10, reward: 25, insured: false, leagues: ["nba"] }],
};
const stats = computeStats(user);

Deno.test("escaping covers the characters that break HTML", () => {
  assertEquals(esc(`<script>"x" & 'y'</script>`), "&lt;script&gt;&quot;x&quot; &amp; &#39;y&#39;&lt;/script&gt;");
});

Deno.test("the email greets by first name, carries the headline, and links unsubscribe", () => {
  const decision = fallbackDecision(stats);
  const email = renderEmail({ name: "Sam Lee", stats, decision, unsubscribeUrl: "https://x.test/f?u=1&t=2" });
  assertEquals(email.subject, `Your TimeOut week: ${decision.headline}`);
  assert(email.html.includes("Hi Sam,"));
  assert(email.html.includes("https://x.test/f?u=1&amp;t=2"));
  assert(email.text.includes("Unsubscribe: https://x.test/f?u=1&t=2"));
  assert(email.html.includes("Tuesday")); // the day-by-day table, since there is usage
});

Deno.test("words written by the AI can't inject markup", () => {
  const decision = { ...fallbackDecision(stats), headline: `<img src=x onerror=alert(1)>`, summary: `"><script>1</script>` };
  const email = renderEmail({ name: `<b>Sam</b>`, stats, decision, unsubscribeUrl: "https://x.test" });
  assertEquals(email.html.includes("<img"), false);
  assertEquals(email.html.includes("<script"), false);
  assertEquals(email.html.includes("<b>Sam"), false);
});

Deno.test("no day-by-day table and no usage tiles when the phone hasn't synced usage", () => {
  const noUsage = computeStats({ ...user, usageByDay: {} });
  const email = renderEmail({ name: null, stats: noUsage, decision: fallbackDecision(noUsage), unsubscribeUrl: "https://x.test" });
  assertEquals(email.html.includes("Day by day"), false);
  assert(email.html.includes("Hi,"));
  assertEquals(tilesFor(noUsage).map((t) => t.label), ["Challenge record", "Net minutes", "Clean-day streak"]);
});

Deno.test("the Gemini request asks for JSON that matches the schema and carries only stats", () => {
  const body = buildRequest(stats) as { generationConfig: Record<string, unknown>; contents: { parts: { text: string }[] }[] };
  assertEquals(body.generationConfig.responseMimeType, "application/json");
  assertEquals(body.generationConfig.responseSchema, SCHEMA);
  const sent = body.contents[0].parts[0].text;
  assert(sent.includes('"daysUnderLimit":1'));
  for (const secret of ["Sam", "a@b.c", "2026-"]) assertEquals(sent.includes(secret), false, secret);
});

const reply = (status: number, body: unknown) => (() => Promise.resolve(new Response(typeof body === "string" ? body : JSON.stringify(body), { status }))) as unknown as typeof fetch;

Deno.test("callModel returns the parsed JSON and sends the key in a header, not the URL", async () => {
  let seen: { url: string; key: string | null } | undefined;
  const fake = ((url: string, init: RequestInit) => {
    seen = { url, key: new Headers(init.headers).get("x-goog-api-key") };
    return Promise.resolve(new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"skip":false}' }] } }] })));
  }) as unknown as typeof fetch;
  assertEquals(await callModel(stats, { apiKey: "KEY", model: "gemini-2.5-flash" }, fake), { skip: false });
  assertEquals(seen?.key, "KEY");
  assertEquals(seen?.url.includes("KEY"), false);
  assert(seen?.url.includes("gemini-2.5-flash:generateContent"));
});

Deno.test("callModel throws on a rate limit, an empty answer, and bad JSON, so the template takes over", async () => {
  await assertRejects(() => callModel(stats, { apiKey: "k", model: "m" }, reply(429, "quota")), Error, "Gemini 429");
  await assertRejects(() => callModel(stats, { apiKey: "k", model: "m" }, reply(200, { candidates: [{ finishReason: "SAFETY" }] })), Error, "no text");
  await assertRejects(() => callModel(stats, { apiKey: "k", model: "m" }, reply(200, { candidates: [{ content: { parts: [{ text: "not json" }] } }] })));
});
