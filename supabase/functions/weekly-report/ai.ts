// The AI step: Google Gemini reads one person's weekly stats and decides how to frame the week.
// It is called through the REST API with a plain fetch, so there is nothing to install. To use another model or provider,
// replace callModel: it only has to return the JSON described by SCHEMA.

import { type Decision, fallbackDecision, SUGGESTION_KINDS, TONES, validateDecision, WEEK_TYPES } from "./decision.ts";
import { forModel, type WeekStats } from "./stats.ts";

export interface ModelConfig {
  apiKey: string;
  model: string;
}

export const DEFAULT_MODEL = "gemini-2.5-flash";

export const SYSTEM_PROMPT = `You write the weekly review email for TimeOut, an app where people pledge phone minutes (never money) on sports challenges and limit their time on apps they choose. Win a challenge and tomorrow's phone time goes up. Lose and it goes down.

You get one person's stats for the past week as JSON. Decide how to frame the week, then write it.

Decide:
- weekType: "crushed" (stayed under limits and came out ahead), "steady" (mixed or ordinary), "slipped" (went over limits or lost minutes), or "risky" (lots of losses in a row, or repeated emergency unlocks, which can mean chasing losses).
- tone: celebratory, encouraging, calm, or direct. Match the week. Be direct but kind for "risky".
- insight: the single most interesting thing in the data, not a list of everything.
- suggestion: one concrete thing to do next week, with a kind from the allowed list.
- skip: true only if there is essentially nothing to report.

Rules:
- Use only numbers that appear in the JSON, written as digits. Never invent, estimate, add up or round numbers yourself.
- If hasUsage is false, don't mention screen time or app limits at all. Talk about challenges only.
- Don't mention dates, names, money, dollars or gambling winnings. Minutes are the only currency.
- Don't shame the person. Don't give medical or financial advice. No links.
- Write to the person as "you". Keep it warm and short.
- Headline: under 90 characters. Summary: 2 or 3 sentences. Insight: one sentence. Suggestion text: one sentence.`;

export const SCHEMA = {
  type: "OBJECT",
  properties: {
    skip: { type: "BOOLEAN" },
    weekType: { type: "STRING", enum: [...WEEK_TYPES] },
    tone: { type: "STRING", enum: [...TONES] },
    headline: { type: "STRING" },
    summary: { type: "STRING" },
    insight: { type: "STRING" },
    suggestion: {
      type: "OBJECT",
      properties: {
        kind: { type: "STRING", enum: [...SUGGESTION_KINDS] },
        text: { type: "STRING" },
      },
      required: ["kind", "text"],
    },
  },
  required: ["skip", "weekType", "tone", "headline", "summary", "insight", "suggestion"],
};

/** An earlier answer that failed a check, and why, so the model can fix it on the second try. */
export interface Feedback {
  previous: unknown;
  reason: string;
}

export function buildRequest(stats: WeekStats, feedback?: Feedback): Record<string, unknown> {
  // The stats hold only numbers and fixed words, so there is no user-written text that could carry instructions.
  const contents: { role: string; parts: { text: string }[] }[] = [
    { role: "user", parts: [{ text: `Weekly stats (JSON):\n${JSON.stringify(forModel(stats))}` }] },
  ];
  if (feedback) {
    contents.push(
      { role: "model", parts: [{ text: JSON.stringify(feedback.previous) }] },
      { role: "user", parts: [{ text: `That answer was rejected: ${feedback.reason}. Answer again in the same format, using only numbers that appear in the stats.` }] },
    );
  }
  return {
    systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents,
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: SCHEMA,
      temperature: 0.6,
      // Room for the model's own thinking as well as the answer, which is only a few hundred tokens.
      maxOutputTokens: 4096,
    },
  };
}

/** The decision as the model returned it, not yet checked. Throws if the call or the JSON fails. */
export async function callModel(
  stats: WeekStats,
  config: ModelConfig,
  fetcher: typeof fetch = fetch,
  feedback?: Feedback,
): Promise<unknown> {
  const response = await fetcher(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(config.model)}:generateContent`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": config.apiKey },
      body: JSON.stringify(buildRequest(stats, feedback)),
      signal: AbortSignal.timeout(25_000),
    },
  );
  if (!response.ok) throw new Error(`Gemini ${response.status}: ${(await response.text()).slice(0, 300)}`);

  const body = await response.json();
  const text = body?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? "").join("") ?? "";
  if (!text) throw new Error(`Gemini returned no text (finish reason: ${body?.candidates?.[0]?.finishReason ?? "unknown"})`);
  return JSON.parse(text);
}

export interface Written {
  decision: Decision;
  source: "ai" | "fallback";
  /** How many times the AI was called. Zero means it wasn't (no key). */
  attempts: number;
  /** Why the template was used, or what the AI got wrong on the way to a good answer. Null when the first try was fine. */
  note: string | null;
}

export interface Deps {
  fetcher?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

/**
 * Asks the AI to decide the week and checks its answer. One retry: if the answer breaks a rule, the model is told which
 * one and tries again. If the call itself fails (rate limit, outage), it waits a few seconds and tries again. After two
 * failures the template writes the email, so a bad AI day never means a missing email.
 */
export async function writeDecision(stats: WeekStats, config: ModelConfig | null, deps: Deps = {}): Promise<Written> {
  if (!config) return { decision: fallbackDecision(stats), source: "fallback", attempts: 0, note: "GEMINI_API_KEY isn't set" };
  const fetcher = deps.fetcher ?? fetch;
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));

  let feedback: Feedback | undefined;
  let problem = "";
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const raw = await callModel(stats, config, fetcher, feedback);
      const checked = validateDecision(raw, stats);
      if (checked.ok) {
        return { decision: checked.decision, source: "ai", attempts: attempt, note: attempt > 1 ? `second try; first was: ${problem}` : null };
      }
      problem = `AI answer rejected: ${checked.reason}`;
      feedback = { previous: raw, reason: checked.reason };
    } catch (error) {
      problem = `AI call failed: ${String(error).slice(0, 200)}`;
      feedback = undefined;
      if (attempt < 2) await sleep(4000);
    }
  }
  return { decision: fallbackDecision(stats), source: "fallback", attempts: 2, note: problem };
}
