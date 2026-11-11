// Writes TimeOut's weekly report and publishes it into the app (menu > Weekly report, on the iPhone app and the website).
// pg_cron wakes it (only when somebody is due) and it works out the rest from the database, so the same request is
// safe to repeat. Per person:
//   claim -> stats -> AI decides how to frame the week -> checks -> report saved for the apps to show
// Setup and testing steps: supabase/functions/weekly-report/README.md

import { DEFAULT_MODEL, writeDecision } from "./ai.ts";
import { buildReport } from "./report.ts";
import { computeStats, type WeekStats, type WorkUser } from "./stats.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} isn't set. See supabase/functions/weekly-report/README.md.`);
  return value;
}

async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  const response = await fetch(`${env("SUPABASE_URL")}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify(args),
  });
  if (!response.ok) throw new Error(`${name} failed: ${response.status} ${await response.text()}`);
  const text = await response.text();
  return (text ? JSON.parse(text) : null) as T;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  return x.reduce((diff, byte, i) => diff | (byte ^ y[i]), 0) === 0;
}

// MARK: One person's report

type Outcome = "published" | "dry_run" | "skipped" | "unavailable" | "failed";

interface Options {
  dryRun: boolean;
  force: boolean;
}

function writeWords(stats: WeekStats) {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  return writeDecision(stats, apiKey ? { apiKey, model: Deno.env.get("GEMINI_MODEL") ?? DEFAULT_MODEL } : null);
}

async function processUser(user: WorkUser, options: Options): Promise<Outcome> {
  const { userId, weekStart } = user;
  if (!await rpc<boolean>("timeout_weekly_report_claim", { p_user: userId, p_week: weekStart, p_force: options.force })) return "unavailable";

  const finish = (status: string, source: string | null, stats: unknown, decision: unknown, report: unknown, note: string | null) =>
    rpc("timeout_weekly_report_finish", {
      p_user: userId, p_week: weekStart, p_status: status, p_source: source,
      p_stats: stats, p_decision: decision, p_report: report, p_note: note,
    });

  try {
    const stats = computeStats(user);
    if (!stats.hasActivity) {
      await finish("skipped", null, stats, null, null, "no activity this week");
      return "skipped";
    }

    const { decision, source, note } = await writeWords(stats);
    if (decision.skip) {
      await finish("skipped", source, stats, decision, null, note ?? "the AI judged the week too thin to report");
      return "skipped";
    }

    const report = buildReport(weekStart, stats, decision);
    const status = options.dryRun ? "dry_run" : "published";
    await finish(status, source, stats, decision, report, note);
    return status;
  } catch (error) {
    // Letting go of the claim means a later run tries again.
    console.error(`Weekly report for ${userId} failed:`, error);
    await rpc("timeout_weekly_report_release", { p_user: userId, p_week: weekStart }).catch(() => {});
    return "failed";
  }
}

// MARK: The sweep

interface SweepRequest {
  userId?: string;
  weekStart?: string;
  dryRun?: boolean;
}

async function sweep(request: SweepRequest): Promise<Record<string, number>> {
  const testing = request.userId !== undefined;
  // Reports stay hidden (dry runs) until WEEKLY_REPORT_DRY_RUN is set to "false". Test runs for one person stay hidden
  // unless asked, which is how to read what the AI wrote before anyone sees it.
  const dryRun = request.dryRun ?? (testing ? true : Deno.env.get("WEEKLY_REPORT_DRY_RUN") !== "false");

  const people = await rpc<WorkUser[]>("timeout_weekly_report_work", {
    p_user: request.userId ?? null,
    p_week_start: request.weekStart ?? null,
  });

  const counts: Record<string, number> = { due: people.length };
  // One at a time: the AI's free plan is limited per minute, and one person's failure mustn't hold up the rest.
  for (const person of people) {
    const outcome = await processUser(person, { dryRun, force: testing });
    counts[outcome] = (counts[outcome] ?? 0) + 1;
  }
  return counts;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("POST only", { status: 405 });
  if (!sameSecret(request.headers.get("x-push-secret") ?? "", env("PUSH_WEBHOOK_SECRET"))) {
    return new Response("Unauthorized", { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const asked: SweepRequest = {};
  if (typeof body?.userId === "string") {
    if (!UUID.test(body.userId)) return new Response("userId isn't a valid id", { status: 400 });
    asked.userId = body.userId;
  }
  if (typeof body?.weekStart === "string") {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(body.weekStart)) return new Response("weekStart must be YYYY-MM-DD", { status: 400 });
    asked.weekStart = body.weekStart;
  }
  if (typeof body?.dryRun === "boolean") asked.dryRun = body.dryRun;

  try {
    return Response.json(await sweep(asked));
  } catch (error) {
    console.error("Weekly report sweep failed:", error);
    return Response.json({ error: "Sweep failed" }, { status: 500 });
  }
});
