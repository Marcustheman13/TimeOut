# Weekly report email

Every Monday morning (8am in the person's own timezone) TimeOut emails each user a short review of their week: challenge record, net minutes, and, once their phone has synced screen-time records, how they did against their limits. An AI step decides how to frame the week and writes the words. Code does all the arithmetic.

## How it works

```
pg_cron (hourly) ─► timeout_ping_weekly_report()      only calls out if somebody is due
                        │
                        ▼
              weekly-report Edge Function
   1. timeout_weekly_report_work   raw numbers for everyone due (SQL)
   2. claim                        one run per person per week (weekly_reports row)
   3. stats.ts                     all the arithmetic: days under limit, net minutes, vs last week
   4. ai.ts  (Gemini)              DECIDES the week type, tone, insight and suggestion, and writes the text
   5. decision.ts                  checks the AI's answer; falls back to a template if it fails
   6. email.ts + Resend            renders and sends the email, with an unsubscribe link
   7. finish                       records what happened in weekly_reports
```

**What the AI decides** (as JSON, not free text): `weekType` (crushed, steady, slipped or risky), `tone`, the one `insight` worth noticing, a `suggestion` with a kind, and `skip` when the week is too thin to report.

**What stops it going wrong** (`decision.ts`)

- Every number the AI writes must appear in the stats it was given. An invented number means the template writes that email instead.
- It can't call a losing week or an over-limit week "crushed".
- No links or markup, and length limits on every field.
- If an answer breaks a rule, the AI is told which one and gets **one retry**. A failed call (rate limit, outage) waits 4 seconds and retries once too.
- If that still fails, or Gemini has no key, the template writes the email. The email still goes out, and `weekly_reports.source` / `note` say why.
- The AI only ever sees numbers and fixed words. Never a name, email, date or any text a user typed.
- Real sends are **off** until you turn them on (see below). Until then every run is a dry run you can read in the table.

**Data it uses.** Challenges come from `challenges` and `challenge_picks`. Screen-time usage comes from `user_settings.shared_ledger`, which the iPhone app writes. If that is empty (the case for every account when this was written), the email covers challenges only and leaves out anything about screen time.

## Setup

Nothing here has been deployed. Do these in order.

### 1. Get the free keys

- **Gemini:** create an API key in [Google AI Studio](https://aistudio.google.com/apikey). The free tier needs no card. Check the current model names and limits there, and set `GEMINI_MODEL` if `gemini-2.5-flash` has been replaced.
- **Resend:** make an account at [resend.com](https://resend.com) and create an API key. Without a verified domain, Resend only delivers to the email address on your own Resend account. That's fine for testing (see step 4). To email real users you need a domain, verified under Resend → Domains.

### 2. Check the AI works (no database or deploy needed)

Put the Gemini key where only you can see it. Either `export GEMINI_API_KEY=...` in your terminal, or put the line `GEMINI_API_KEY=...` in `supabase/functions/weekly-report/.env` (git ignores it). Then:

```bash
deno run --allow-net --allow-env --allow-read --allow-write supabase/functions/weekly-report/live_check.ts --runs=3 --html=sample-email.html
```

It confirms the model name exists, then sends four sample weeks (a strong week, a rough week with no screen-time records, a risky week, a thin week) through the same code the Edge Function uses, three times each. For every run it says whether **the AI's own words were used** or the template stepped in, and why. `sample-email.html` is the first AI-written email, to open in a browser.

### 3. Update the database

In the Supabase SQL Editor for project `obegznrsxlbpmtbmqkll`, run `server/db/supabase-weekly-report.sql`. It turns on `pg_cron` and `pg_net` itself, and it is safe to rerun.

The hourly ping reads the Vault secret `push_webhook_secret` and does nothing until it exists. If you haven't made it yet (`select name from vault.secrets;` shows whether), make one and keep the value, since step 4 needs the same one:

```sql
select vault.create_secret('A_LONG_RANDOM_VALUE', 'push_webhook_secret');
```

(`openssl rand -hex 32` makes a good value.)

### 4. Deploy the function

From the repository root. `--no-verify-jwt` is needed because the database calls the function with `x-push-secret`, not a user's login. The function checks that secret itself.

```bash
npx supabase secrets set --project-ref obegznrsxlbpmtbmqkll GEMINI_API_KEY=THE_GEMINI_KEY RESEND_API_KEY=THE_RESEND_KEY PUSH_WEBHOOK_SECRET=THE_SAME_VALUE_AS_THE_VAULT_SECRET
```

```bash
npx supabase functions deploy weekly-report --project-ref obegznrsxlbpmtbmqkll --no-verify-jwt
```

| Secret | Needed | What it does |
| --- | --- | --- |
| `GEMINI_API_KEY` | Yes for AI | Without it, every email is written by the template. |
| `RESEND_API_KEY` | Yes to send | |
| `PUSH_WEBHOOK_SECRET` | Yes | Must match the Vault secret. Also signs unsubscribe links. |
| `GEMINI_MODEL` | No | Defaults to `gemini-2.5-flash`. |
| `WEEKLY_REPORT_FROM` | No | Defaults to `TimeOut <onboarding@resend.dev>`. Use your own domain once it's verified. |
| `WEEKLY_REPORT_DRY_RUN` | No | Real sending stays **off** until this is `false`. |
| `WEEKLY_REPORT_REDIRECT_TO` | No | Sends every email to this address instead, marked `[test for …]`. Use it to test before you have a domain. |

### 5. Try it on one person, any day of the week

Find a user id in Supabase (Authentication → Users), then ask for a report. A single-person run is a dry run unless you say otherwise, and it ignores the Monday schedule.

```bash
curl -X POST https://obegznrsxlbpmtbmqkll.supabase.co/functions/v1/weekly-report -H "x-push-secret: THE_SECRET" -H "content-type: application/json" -d '{"userId":"THE_USER_ID"}'
```

Read what it wrote:

```sql
select status, source, note, subject, body_text, decision, stats
from weekly_reports order by created_at desc limit 5;
```

When it looks right, send one for real to yourself. Set `WEEKLY_REPORT_REDIRECT_TO` to your own email first so nothing goes to the real user, then add `"dryRun":false` to the request above. To test a different week, add `"weekStart":"2026-11-02"` (a Monday).

### 6. Turn it on

`supabase secrets set WEEKLY_REPORT_DRY_RUN=false` (and unset `WEEKLY_REPORT_REDIRECT_TO`). The cron job is already scheduled by the SQL file. It does nothing outside Monday 8am to 8pm local time.

Dry-run rows count as handled for that week, so a user won't get an email for a week you only dry-ran. To release one: `delete from weekly_reports where user_id = '…' and week_start = '…';`

## Tests

```bash
deno test supabase/functions/weekly-report/
```

Covers the stats arithmetic, the checks on the AI's answer, the retry and fallback, the template, the email HTML, and the Gemini request. They need no network and no keys. They can't tell you whether the real Gemini behaves, which is what `live_check.ts` (step 2) is for.

## Known limits

- **Screen-time usage is empty today.** `shared_ledger` holds no usage for any account yet, so emails are challenge-only until the iPhone app syncs it. The first synced week switches the usage sections on by itself.
- **Timezones aren't synced.** `user_settings.timezone` exists but every account holds the default (`America/Denver`). Until the apps write the phone's timezone there, everyone gets their email at 8am Denver time.
- **No unsubscribe toggle in Settings yet.** Unsubscribing is by the email link only (stored in `weekly_report_optouts`). It isn't kept in `app_preferences` because the apps only save the keys they know and could wipe it. A Settings switch should call a function that removes the row.
- **The unsubscribe link takes effect on click.** Some mail security scanners open links, which can unsubscribe someone by mistake. Supabase serves Edge Function replies as plain text, so a confirmation page isn't possible without a separate page on the website.
- **Gemini's free tier is rate limited.** People are processed one at a time, 20 per hourly run. A rate-limited call just uses the template for that person.
- **Limits are estimated.** The server rebuilds each day's limit the way the app does (60, plus yesterday's results, minus penalties, plus emergency unlocks), so a day near its limit could differ slightly from what the app showed.
