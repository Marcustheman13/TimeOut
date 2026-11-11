// Builds the email from the stats and the decision. Layout and numbers come from code, the words come from the decision.
// Table layout and inline styles on purpose: that is what email apps render reliably.

import type { Decision, WeekType } from "./decision.ts";
import type { WeekStats } from "./stats.ts";

export interface RenderInput {
  name: string | null;
  stats: WeekStats;
  decision: Decision;
  unsubscribeUrl: string;
}

export interface RenderedEmail {
  subject: string;
  html: string;
  text: string;
}

// The app's own colors (Theme.swift), with the dark background kept to the header.
const INK = "#0a0d12";
const ACCENT: Record<WeekType, string> = { crushed: "#22d66e", steady: "#4fb3ff", slipped: "#ffc940", risky: "#ff5a5f" };
const LABEL: Record<WeekType, string> = { crushed: "Crushed it", steady: "Steady", slipped: "Tough week", risky: "Worth a look" };

export function esc(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

const signed = (n: number) => (n > 0 ? `+${n}` : `${n}`);

function firstName(name: string | null): string | null {
  const first = (name ?? "").trim().split(/\s+/)[0]?.slice(0, 30);
  return first || null;
}

interface Tile {
  label: string;
  value: string;
}

export function tilesFor(stats: WeekStats): Tile[] {
  const c = stats.challenges;
  const tiles: Tile[] = [];
  if (stats.usage) tiles.push({ label: "Days under limit", value: `${stats.usage.daysUnderLimit} of ${stats.usage.daysTracked}` });
  if (c.resolved > 0) {
    tiles.push({ label: "Challenge record", value: `${c.won}–${c.lost}` });
    tiles.push({ label: "Net minutes", value: signed(c.netMinutes) });
  }
  if (stats.usage) tiles.push({ label: "Daily average", value: `${stats.usage.averageMinutes} min` });
  if (stats.streakDays > 0 && tiles.length < 4) tiles.push({ label: "Clean-day streak", value: `${stats.streakDays}` });
  return tiles.slice(0, 4);
}

export function renderEmail({ name, stats, decision, unsubscribeUrl }: RenderInput): RenderedEmail {
  const accent = ACCENT[decision.weekType];
  const hello = firstName(name) ? `Hi ${firstName(name)},` : "Hi,";
  const subject = `Your TimeOut week: ${decision.headline}`.replace(/\s+/g, " ").slice(0, 120);
  const tiles = tilesFor(stats);

  const tileCells = tiles.map((t) => `
        <td align="center" style="padding:6px;">
          <div style="background:#f4f6f9;border-radius:12px;padding:14px 6px;">
            <div style="font-size:22px;font-weight:700;color:${INK};line-height:1.2;">${esc(t.value)}</div>
            <div style="font-size:12px;color:#5e687a;margin-top:4px;">${esc(t.label)}</div>
          </div>
        </td>`).join("");

  const dayRows = stats.hasUsage
    ? stats.days.map((d) => {
      const status = d.used === null ? "–" : d.overLimit ? "Over" : "Under";
      const color = d.used === null ? "#8c96a8" : d.overLimit ? "#d6383d" : "#139a4a";
      return `
        <tr>
          <td style="padding:8px 0;border-top:1px solid #e6eaf0;color:${INK};">${esc(d.weekday)}</td>
          <td align="right" style="padding:8px 0;border-top:1px solid #e6eaf0;color:${INK};">${d.used === null ? "–" : `${d.used} min`}</td>
          <td align="right" style="padding:8px 0;border-top:1px solid #e6eaf0;color:#5e687a;">${d.limit} min</td>
          <td align="right" style="padding:8px 0;border-top:1px solid #e6eaf0;font-weight:600;color:${color};">${status}</td>
        </tr>`;
    }).join("")
    : "";

  const dayTable = stats.hasUsage
    ? `
      <h2 style="font-size:15px;margin:28px 0 8px;color:${INK};">Day by day</h2>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:14px;">
        <tr>
          <td style="padding:0 0 6px;color:#8c96a8;font-size:12px;">Day</td>
          <td align="right" style="padding:0 0 6px;color:#8c96a8;font-size:12px;">Used</td>
          <td align="right" style="padding:0 0 6px;color:#8c96a8;font-size:12px;">Limit</td>
          <td align="right" style="padding:0 0 6px;color:#8c96a8;font-size:12px;"></td>
        </tr>${dayRows}
      </table>`
    : "";

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>${esc(subject)}</title>
</head>
<body style="margin:0;padding:0;background:#eef1f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#eef1f5;">
  <tr><td align="center" style="padding:24px 12px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;">
      <tr><td style="background:${INK};padding:22px 28px;">
        <div style="font-size:20px;font-weight:800;color:#f2f5f9;letter-spacing:0.2px;">Time<span style="color:#22d66e;">Out</span></div>
        <div style="font-size:13px;color:#8c96a8;margin-top:2px;">Your week in review</div>
      </td></tr>
      <tr><td style="padding:28px;">
        <div style="display:inline-block;background:${accent};color:${INK};font-size:12px;font-weight:700;padding:4px 10px;border-radius:999px;">${esc(LABEL[decision.weekType])}</div>
        <h1 style="font-size:24px;line-height:1.25;margin:12px 0 10px;color:${INK};">${esc(decision.headline)}</h1>
        <p style="font-size:15px;line-height:1.55;margin:0 0 6px;color:#2b3340;">${esc(hello)}</p>
        <p style="font-size:15px;line-height:1.55;margin:0 0 18px;color:#2b3340;">${esc(decision.summary)}</p>

        <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>${tileCells}
        </tr></table>

        <div style="margin:22px 0 0;padding:14px 16px;border-left:4px solid ${accent};background:#f8f9fb;border-radius:0 10px 10px 0;">
          <div style="font-size:12px;font-weight:700;color:#5e687a;text-transform:uppercase;letter-spacing:0.6px;">Worth noticing</div>
          <div style="font-size:15px;line-height:1.5;color:#2b3340;margin-top:4px;">${esc(decision.insight)}</div>
        </div>

        <div style="margin:14px 0 0;padding:14px 16px;border-left:4px solid ${INK};background:#f8f9fb;border-radius:0 10px 10px 0;">
          <div style="font-size:12px;font-weight:700;color:#5e687a;text-transform:uppercase;letter-spacing:0.6px;">Try this next week</div>
          <div style="font-size:15px;line-height:1.5;color:#2b3340;margin-top:4px;">${esc(decision.suggestion.text)}</div>
        </div>
        ${dayTable}
      </td></tr>
      <tr><td style="padding:18px 28px 26px;border-top:1px solid #e6eaf0;">
        <p style="font-size:12px;line-height:1.5;color:#8c96a8;margin:0;">You're getting this because you have a TimeOut account. TimeOut pledges phone minutes, never money.
        <a href="${esc(unsubscribeUrl)}" style="color:#5e687a;">Unsubscribe from weekly reports</a>.</p>
      </td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>`;

  const lines = [
    `${hello}`,
    "",
    decision.headline.toUpperCase(),
    decision.summary,
    "",
    ...tiles.map((t) => `${t.label}: ${t.value}`),
    "",
    `Worth noticing: ${decision.insight}`,
    `Try this next week: ${decision.suggestion.text}`,
  ];
  if (stats.hasUsage) {
    lines.push("", "Day by day:");
    for (const d of stats.days) lines.push(`${d.weekday}: ${d.used === null ? "no data" : `${d.used} of ${d.limit} min`}`);
  }
  lines.push("", "TimeOut pledges phone minutes, never money.", `Unsubscribe: ${unsubscribeUrl}`);

  return { subject, html, text: lines.join("\n") };
}
