// The AI step: Google Gemini reads one person's weekly stats and decides how to frame the week.
// It is called through the REST API with a plain fetch, so there is nothing to install. To use another model or provider,
// replace callModel: it only has to return the JSON described by SCHEMA.

import { SUGGESTION_KINDS, TONES, WEEK_TYPES } from "./decision.ts";
import { forModel, type WeekStats } from "./stats.ts";

export interface ModelConfig {
  apiKey: string;
  model: string;
}

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

export function buildRequest(stats: WeekStats): Record<string, unknown> {
  return {
    systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
    // The stats hold only numbers and fixed words, so there is no user-written text that could carry instructions.
    contents: [{ role: "user", parts: [{ text: `Weekly stats (JSON):\n${JSON.stringify(forModel(stats))}` }] }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: SCHEMA,
      temperature: 0.6,
      maxOutputTokens: 2048,
    },
  };
}

/** The decision as the model returned it, not yet checked. Throws if the call or the JSON fails. */
export async function callModel(stats: WeekStats, config: ModelConfig, fetcher: typeof fetch = fetch): Promise<unknown> {
  const response = await fetcher(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(config.model)}:generateContent`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": config.apiKey },
      body: JSON.stringify(buildRequest(stats)),
      signal: AbortSignal.timeout(25_000),
    },
  );
  if (!response.ok) throw new Error(`Gemini ${response.status}: ${(await response.text()).slice(0, 300)}`);

  const body = await response.json();
  const text = body?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? "").join("") ?? "";
  if (!text) throw new Error(`Gemini returned no text (finish reason: ${body?.candidates?.[0]?.finishReason ?? "unknown"})`);
  return JSON.parse(text);
}
