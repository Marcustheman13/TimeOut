// Sends TimeOut's weekly review email. pg_cron wakes it (only when somebody is due) and it works out the rest from
// the database, so the same request is safe to repeat. Per person:
//   claim -> stats -> AI decides how to frame the week -> checks -> email (Resend) -> record
// Setup and testing steps: supabase/functions/weekly-report/README.md

import { DEFAULT_MODEL, writeDecision } from "./ai.ts";
import { renderEmail } from "./email.ts";
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

// MARK: Unsubscribe links

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  return x.reduce((diff, byte, i) => diff | (byte ^ y[i]), 0) === 0;
}

/** Proves a link came from us without storing anything: a signature of the user's id, made with the webhook secret. */
async function unsubscribeToken(userId: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env("PUSH_WEBHOOK_SECRET")), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`weekly-report-unsubscribe:${userId}`));
  return [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function unsubscribeUrl(userId: string): Promise<string> {
  return `${env("SUPABASE_URL")}/functions/v1/weekly-report?u=${userId}&t=${await unsubscribeToken(userId)}`;
}

// Supabase serves Edge Function responses as plain text, so these are plain sentences, not a page.
// Email apps' own Unsubscribe buttons send a POST (RFC 8058); the link in the email is a GET. Both do the same thing.
async function unsubscribe(url: URL): Promise<Response> {
  const userId = url.searchParams.get("u") ?? "";
  const token = url.searchParams.get("t") ?? "";
  if (!UUID.test(userId) || !sameSecret(token, await unsubscribeToken(userId))) {
    return new Response("This unsubscribe link isn't valid.", { status: 400 });
  }
  try {
    await rpc("timeout_weekly_report_unsubscribe", { p_user: userId });
  } catch (error) {
    console.error("Unsubscribe failed:", error);
    return new Response("Something went wrong. Please try again in a minute.", { status: 500 });
  }
  return new Response("You're unsubscribed from TimeOut weekly reports.");
}

// MARK: One person's report

type Outcome = "sent" | "dry_run" | "skipped" | "unavailable" | "failed";

interface Options {
  dryRun: boolean;
  force: boolean;
}

function writeWords(stats: WeekStats) {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  return writeDecision(stats, apiKey ? { apiKey, model: Deno.env.get("GEMINI_MODEL") ?? DEFAULT_MODEL } : null);
}

async function sendEmail(user: WorkUser, subject: string, html: string, text: string, unsubscribe: string): Promise<string> {
  // Without a verified domain, Resend only delivers to the account owner. WEEKLY_REPORT_REDIRECT_TO sends every
  // email there instead (marked with who it was for), which is how to test before a domain is set up.
  const redirect = Deno.env.get("WEEKLY_REPORT_REDIRECT_TO");
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${env("RESEND_API_KEY")}`,
      "content-type": "application/json",
      // Resend ignores a repeat of the same key, so a crash right after sending can't send twice.
      "idempotency-key": `weekly-report-${user.userId}-${user.weekStart}`,
    },
    body: JSON.stringify({
      from: Deno.env.get("WEEKLY_REPORT_FROM") ?? "TimeOut <onboarding@resend.dev>",
      to: [redirect ?? user.email],
      subject: redirect ? `[test for ${user.userId.slice(0, 8)}] ${subject}` : subject,
      html,
      text,
      headers: { "List-Unsubscribe": `<${unsubscribe}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" },
    }),
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) throw new Error(`Resend ${response.status}: ${(await response.text()).slice(0, 300)}`);
  return (await response.json()).id as string;
}

async function processUser(user: WorkUser, options: Options): Promise<Outcome> {
  const { userId, weekStart } = user;
  if (!await rpc<boolean>("timeout_weekly_report_claim", { p_user: userId, p_week: weekStart, p_force: options.force })) return "unavailable";

  const finish = (status: string, source: string | null, stats: unknown, decision: unknown, subject: string | null, body: string | null, emailId: string | null, note: string | null) =>
    rpc("timeout_weekly_report_finish", {
      p_user: userId, p_week: weekStart, p_status: status, p_source: source,
      p_stats: stats, p_decision: decision, p_subject: subject, p_body: body, p_email_id: emailId, p_note: note,
    });

  try {
    const stats = computeStats(user);
    if (!stats.hasActivity) {
      await finish("skipped", null, stats, null, null, null, null, "no activity this week");
      return "skipped";
    }

    const { decision, source, note } = await writeWords(stats);
    if (decision.skip) {
      await finish("skipped", source, stats, decision, null, null, null, note ?? "the AI judged the week too thin to report");
      return "skipped";
    }

    const unsubscribe = await unsubscribeUrl(userId);
    const email = renderEmail({ name: user.name, stats, decision, unsubscribeUrl: unsubscribe });

    if (options.dryRun) {
      await finish("dry_run", source, stats, decision, email.subject, email.text, null, note);
      return "dry_run";
    }
    const emailId = await sendEmail(user, email.subject, email.html, email.text, unsubscribe);
    await finish("sent", source, stats, decision, email.subject, email.text, emailId, note);
    return "sent";
  } catch (error) {
    // Most likely the email provider was down. Letting go of the claim means a later run tries again.
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
  // Real sends are off until WEEKLY_REPORT_DRY_RUN is set to "false". Test runs for one person stay dry unless asked.
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
  const url = new URL(request.url);
  if (url.searchParams.has("u") && url.searchParams.has("t")) return await unsubscribe(url);

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
