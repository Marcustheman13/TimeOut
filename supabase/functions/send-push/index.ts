// Sends TimeOut's push notifications. Takes no instructions: each call works out what's due from the database,
// so the same request is safe to repeat. A trigger calls it for each friend request, and pg_cron calls it every minute.

import { type ApnsConfig, type ApnsResult, sendToDevice } from "./apns.ts";
import { type GameState, parseSummary, planChallenge, type PlannedPush, planRequest, summaryPath, type WorkChallenge, type WorkRequest } from "./plan.ts";

interface Device {
  userId: string;
  token: string;
  environment: string;
}

interface Work {
  devices: Device[];
  requests: WorkRequest[];
  challenges: WorkChallenge[];
}

const ESPN = "https://site.api.espn.com/apis/site/v2/sports";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} isn't set. See TimeOut - iOS App/Setup/PUSH_SETUP.md.`);
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

async function loadGames(challenges: WorkChallenge[]): Promise<Map<string, GameState>> {
  const paths = new Map<string, string>();
  for (const c of challenges) {
    if (c.status !== "pending") continue;
    for (const p of c.picks) {
      const path = summaryPath(p);
      if (path) paths.set(p.eventId, path);
    }
  }
  const games = new Map<string, GameState>();
  await Promise.all([...paths].map(async ([eventId, path]) => {
    try {
      const response = await fetch(`${ESPN}/${path}`, { signal: AbortSignal.timeout(8000) });
      if (!response.ok) {
        await response.body?.cancel();
        return;
      }
      const game = parseSummary(await response.json());
      if (game) games.set(eventId, game);
    } catch (error) {
      console.error(`ESPN ${eventId}:`, error);
    }
  }));
  return games;
}

async function deliver(config: ApnsConfig, push: PlannedPush, devices: Device[]): Promise<void> {
  if (!await rpc<boolean>("timeout_push_claim", { p_key: push.key, p_user: push.userId })) return;
  const results: ApnsResult[] = await Promise.all(devices.map(async (device) => {
    const result = await sendToDevice(config, device, push);
    if (result === "gone") await rpc("timeout_push_forget_device", { p_token: device.token });
    return result;
  }));
  if (results.includes("retry") && !results.includes("sent")) {
    await rpc("timeout_push_release", { p_key: push.key });
  }
}

async function sweep(scope: string): Promise<{ due: number }> {
  const work = await rpc<Work>("timeout_push_work", { p_scope: scope });
  const games = await loadGames(work.challenges);
  const planned = [
    ...work.requests.map(planRequest),
    ...work.challenges.map((c) => planChallenge(c, games)).filter((p): p is PlannedPush => p !== null),
  ];
  if (planned.length === 0) return { due: 0 };

  const config: ApnsConfig = {
    keyId: env("APNS_KEY_ID"),
    teamId: env("APNS_TEAM_ID"),
    privateKey: env("APNS_PRIVATE_KEY"),
    topic: Deno.env.get("APNS_TOPIC") ?? "com.marcuswilliams.staketime",
  };
  // One person's failure mustn't hold up everyone else's notifications.
  const settled = await Promise.allSettled(planned.map((push) => deliver(config, push, work.devices.filter((d) => d.userId === push.userId))));
  for (const result of settled) {
    if (result.status === "rejected") console.error("Push failed:", result.reason);
  }
  return { due: planned.length };
}

function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  return x.reduce((diff, byte, i) => diff | (byte ^ y[i]), 0) === 0;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("POST only", { status: 405 });
  if (!sameSecret(request.headers.get("x-push-secret") ?? "", env("PUSH_WEBHOOK_SECRET"))) {
    return new Response("Unauthorized", { status: 401 });
  }
  const scope = await request.json().then((b) => (b?.scope === "friends" ? "friends" : "all")).catch(() => "all");
  try {
    return Response.json(await sweep(scope));
  } catch (error) {
    console.error("Sweep failed:", error);
    return Response.json({ error: "Sweep failed" }, { status: 500 });
  }
});
