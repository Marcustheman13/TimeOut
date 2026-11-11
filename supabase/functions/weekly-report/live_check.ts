// Checks the AI step against the real Gemini API, the one thing the unit tests can't do. It sends four sample weeks through
// the same code the Edge Function uses and reports, for each, whether the AI's own words were accepted or the template
// had to step in. Costs a handful of free-tier requests and publishes nothing.
//
//   deno run --allow-net --allow-env --allow-read --allow-write supabase/functions/weekly-report/live_check.ts
//
// Options: --runs=3 (tries per week, to see how often the AI gets it right)  --json=out.json (saves the first report, as the apps would receive it)
// The key comes from GEMINI_API_KEY, or from a line GEMINI_API_KEY=... in supabase/functions/weekly-report/.env
// (git ignores .env files). GEMINI_MODEL picks another model.

import { DEFAULT_MODEL, writeDecision } from "./ai.ts";
import { buildReport } from "./report.ts";
import { computeStats, type WorkChallenge, type WorkUser } from "./stats.ts";

async function readKey(): Promise<string | null> {
  const fromEnv = Deno.env.get("GEMINI_API_KEY");
  if (fromEnv) return fromEnv;
  try {
    const file = await Deno.readTextFile(new URL("./.env", import.meta.url));
    return file.match(/^\s*GEMINI_API_KEY\s*=\s*["']?([^"'\s]+)/m)?.[1] ?? null;
  } catch {
    return null;
  }
}

const arg = (name: string) => Deno.args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const apiKey = await readKey();
if (!apiKey) {
  console.error("No Gemini key found. Create a free one at https://aistudio.google.com/apikey, then either run\n  export GEMINI_API_KEY=...\nor put GEMINI_API_KEY=... in supabase/functions/weekly-report/.env (git ignores it).");
  Deno.exit(2);
}
const model = Deno.env.get("GEMINI_MODEL") ?? DEFAULT_MODEL;
const runs = Math.max(1, Number(arg("runs") ?? 2));

// Step 1: is the model name real, and can it generate? (Free: this doesn't use generation quota.)
const info = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}`, { headers: { "x-goog-api-key": apiKey } });
if (!info.ok) {
  console.error(`Model "${model}" isn't available to this key (${info.status}).`);
  const list = await fetch("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200", { headers: { "x-goog-api-key": apiKey } });
  if (list.ok) {
    const names = ((await list.json()).models ?? [])
      .filter((m: { name: string; supportedGenerationMethods?: string[] }) => m.supportedGenerationMethods?.includes("generateContent") && /gemini/.test(m.name))
      .map((m: { name: string }) => m.name.replace("models/", ""));
    console.error(`Models you can use:\n  ${names.join("\n  ")}\nThen run again with GEMINI_MODEL=<one of those>.`);
  } else {
    console.error(`The key itself looks wrong (${list.status}).`);
  }
  Deno.exit(1);
}
console.log(`Model ${model} is available.\n`);

// Step 2: four different weeks.
const base = {
  userId: "check", timezone: "America/Denver", weekStart: "2026-11-02", enforce: true, minLimit: 0,
  overridesByDay: {}, penaltyByDay: {},
};
const won = (day: string, p: number, r: number, leagues = ["nba"]): WorkChallenge => ({ day, status: "won", pledge: p, reward: r, insured: false, leagues });
const lost = (day: string, p: number, leagues = ["nfl"]): WorkChallenge => ({ day, status: "lost", pledge: p, reward: 0, insured: false, leagues });

const weeks: { name: string; user: WorkUser }[] = [
  {
    name: "strong week with screen-time records",
    user: {
      ...base, streak: 4,
      usageByDay: { "2026-10-26": 58, "2026-10-27": 62, "2026-11-02": 30, "2026-11-03": 45, "2026-11-04": 52, "2026-11-05": 20, "2026-11-06": 41, "2026-11-07": 38, "2026-11-08": 33 },
      challenges: [won("2026-11-03", 10, 28), won("2026-11-05", 15, 40), lost("2026-11-07", 20)],
    },
  },
  {
    name: "rough week, challenges only (no screen-time records)",
    user: { ...base, streak: 0, usageByDay: {}, challenges: [won("2026-11-03", 10, 28), lost("2026-11-04", 10), lost("2026-11-05", 20), lost("2026-11-06", 15)] },
  },
  {
    name: "risky week: five losses and three emergency unlocks",
    user: {
      ...base, streak: 0,
      usageByDay: { "2026-11-02": 95, "2026-11-03": 88, "2026-11-04": 110, "2026-11-05": 72, "2026-11-06": 101 },
      overridesByDay: { "2026-11-03": 1, "2026-11-04": 1, "2026-11-06": 1 },
      challenges: [lost("2026-11-02", 20), lost("2026-11-03", 20), lost("2026-11-04", 25), lost("2026-11-05", 20), lost("2026-11-06", 30), won("2026-11-07", 10, 18)],
    },
  },
  { name: "thin week: one tie", user: { ...base, streak: 0, usageByDay: {}, challenges: [{ day: "2026-11-04", status: "tied", pledge: 10, reward: 10, insured: false, leagues: ["nba"] }] } },
];

let accepted = 0;
let total = 0;
let savedHtml = false;
for (const { name, user } of weeks) {
  console.log(`── ${name}`);
  const stats = computeStats(user);
  for (let run = 1; run <= runs; run++) {
    total++;
    const written = await writeDecision(stats, { apiKey, model });
    const d = written.decision;
    if (written.source === "ai") accepted++;
    console.log(`  run ${run}: ${written.source === "ai" ? "AI wrote it" : "TEMPLATE used"} (${written.attempts} call${written.attempts === 1 ? "" : "s"})${written.note ? `  [${written.note}]` : ""}`);
    if (run === 1) {
      console.log(`    ${d.weekType} / ${d.tone}${d.skip ? " / SKIP" : ""}\n    "${d.headline}"\n    ${d.summary}\n    Noticing: ${d.insight}\n    Next week (${d.suggestion.kind}): ${d.suggestion.text}`);
      const out = arg("json");
      if (out && !savedHtml && !d.skip) {
        await Deno.writeTextFile(out, JSON.stringify(buildReport(user.weekStart, stats, d), null, 2));
        console.log(`    (saved the report to ${out})`);
        savedHtml = true;
      }
    }
  }
  console.log();
}

console.log(`The AI's own words were used in ${accepted} of ${total} runs.`);
if (accepted < total) {
  console.log("Template runs aren't failures, they are the safety net working, but if it happens often the notes above say why.");
  Deno.exit(accepted === 0 ? 1 : 0);
}
