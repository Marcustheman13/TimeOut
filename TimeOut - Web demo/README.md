# TimeOut — app frontend

> **▶ Try the app:** [App view](https://marcustheman13.github.io/TimeOut/) · [Browser view](https://marcustheman13.github.io/TimeOut/web.html)
> Live ESPN odds and real accounts, nothing to install. It updates by itself when the web demo changes on `main`.

A working HTML/CSS/JS mockup of TimeOut, the sportsbook where you bet screen time instead of money.
It follows the group PRD and screen specs in `../docs/PRD - Prioritization & Design Sprint.pdf`.
For the backend, database and team setup, see the [main README](../README.md).

## Open it

- **Easiest: the live site.** <https://marcustheman13.github.io/TimeOut/> (app view) and <https://marcustheman13.github.io/TimeOut/web.html> (browser view). It uses live ESPN odds and Supabase accounts, and updates after changes are pushed to `main`.
- **With Supabase (normal):** serve the app over HTTP. Accounts use Supabase Auth; preferences, bets, and wallet transactions use the Supabase tables and RPCs.
- **Offline demo:** use the app with Supabase config removed. Accounts and state are then saved only in that browser.
- The interface fills the available viewport and can be wrapped in a native app shell.

## Two versions, one app

| | App version | Browser version |
| --- | --- | --- |
| Page | `index.html` (server: <http://localhost:3000>) | `web.html` (server: <http://localhost:3000/web>) |
| Single file | `dist/TimeOut.html` | `dist/TimeOut-web.html` |
| Layout | Full-screen app surface, tab bar, menu drawer, bottom sheets | Sidebar, wide content grid, bet slip docked on the right, dialogs instead of sheets. |

Both run the same JavaScript, so every feature works the same in each and your login carries over between them.
The browser layout lives in `css/web.css` and `js/web.js`, which only `web.html` loads. To change how a feature
works, edit the shared files in `js/`; to change only the browser layout, edit those two.

## Logging in

- **Try the demo account** on the welcome screen logs straight in. It comes with bet history, open bets, friends, a team and a pending friend request.
- Demo login: username `demo` (or `demo@timeout.app`), password `timeout123`.
- **Create account** asks for a username, email, password and an optional photo. You can then log in with either the username or the email.
- Supabase accounts use email and password. When email confirmation is enabled, confirm the signup email before logging in.
- Supabase stores screen-time bets, bet legs, and wallet ledger entries. The browser also keeps a local cache so the sports feed and app remain responsive.
- In offline mode, accounts are saved only in that browser. Two accounts made in the same browser can friend each other.

## What's in it

| Spec item | Where to find it |
| --- | --- |
| Today's and tomorrow's games | Home: the **Today / Tomorrow** picker under the sport filters. Tomorrow's odds load when you open it. |
| Home: balance + open bets at top, live feed by sport, 3-tap betting | Home tab. Tap any price, then **Place bet** (2 taps). A new price replaces the pick; closing the slip (✕) clears it. |
| Parlays | In the slip, **Add another pick for a parlay** opens a page of open games. Pick up to 3, then **Review parlay**. |
| Odds/scores refresh ≤ 30 s; odds change on an open slip needs re-confirm | Live odds refresh every 15 s. Slip shows old → new price and an **Accept new odds** button. |
| 60 min daily balance, resets at midnight; bets use tomorrow's time | Wallet card on Home, Menu > Screen time. |
| "Not enough screentime" + remaining balance | Bet slip. The stake can't go above today's balance; typing more snaps back to it and shows this message. |
| No connection | A red banner appears, and betting and login are paused until the connection returns. |
| Balance 0 → betting locked with midnight countdown | Home wallet card and bet slip. |
| Auto settlement, voids for postponed games | Bets settle seconds after a game ends. Postponed games void and refund. |
| Game detail: live score, stats, odds, your bets, research | Tap a team or **Stats & all odds** on any game. Tapping a price opens the slip; the floating **Make a bet** button jumps to the odds. |
| My Bets: open bets with live score/stats, history, record and share | My Bets tab. |
| Bet sharing image | **Share** on any bet. |
| Social: stats vs friends, username search, invite link, requests, teams with dates and privacy | Social tab. What friends see is in Menu > What friends can see. Requests shows when each was sent or received; sent requests can be sent again once an hour. |
| Screentime & settings: how it works, controls (confirmed), sports, account, notifications, emergency unlock | Menu (☰) at the top left. **Enforce app limits** can only be on while at least one app is locked. |
| Record / performance | Top of My Bets. |
| Sports simulations for days without sports | Sim League. |
| Emergency override with a penalty | Menu > Screen time > Emergency unlock: +15 min now, −30 min tomorrow, 2 per day, resets streak. |
| Pick which sports to follow | Onboarding and Menu > Sports on Home. |
| Prediction markets, to-do parlays | Home filter chips **Predictions** and **To-Do Parlays**. |
| Tiers and clean-streak multiplier (from the iOS app) | Status strip on Home, Menu > Tier & streak. |

Not included on purpose: monetization (per the team's call), real money, parlays over 3 picks.

## Notes

- Games use simulated scores and odds with real team names. Each game runs for 12 minutes.
- Odds are fair (no house cut), computed from the score and time left, the same model as the iOS prototype.
- `python3 build.py` rebuilds `dist/TimeOut.html` and `dist/TimeOut-web.html` after you edit anything in `css/` or `js/`.

# Supabase accounts and saved bets

The web demo uses Supabase Auth for email/password accounts, saves user preferences in `public.user_settings`, and stores sports bet tickets and legs in `public.bets` and `public.bet_legs`. Wallet balance changes go through Supabase RPC functions and the `wallets` / `wallet_transactions` tables.

1. The main schema and bet RPCs have been applied. Run [`../server/db/supabase-settings-migration.sql`](../server/db/supabase-settings-migration.sql) in **SQL Editor** to add the JSON settings field used for locked apps and other app preferences.
2. Run [`db/tier-system-migration.sql`](db/tier-system-migration.sql) in **SQL Editor** to persist locked-app settings, daily tier bonuses, odds boosts, and parlay insurance usage. It is safe to rerun after an earlier version.
3. Confirm **Email provider** is enabled under **Authentication → Providers**. Email confirmation is enabled, so new users must confirm their email before logging in.
   After **Create account**, the app shows a *Verify your email* page. It logs the new user in by itself as soon as the email is confirmed, and the link in the email also logs them straight in. For the link to come back to the app, add these under **Authentication → URL Configuration → Redirect URLs** (plus your real site's address once it's hosted):
   - `https://marcustheman13.github.io/TimeOut/**` (the live site)
   - `http://localhost:3000/**`
   - `http://localhost:8765/**` (only if you preview with the static server)
4. Serve this app over HTTP (`cd server && npm start`, then open `http://localhost:3000`). Supabase sign-in does not work from the serverless `file://` mode.

The frontend's publishable key is in `js/supabase-config.js`; publishable keys are intended to be public. The main schema enables row-level security, and the RPCs verify the signed-in owner before changing bets or wallet balances. Never put a Supabase secret/service-role key in this project or in browser code. The legacy local demo remains available only when Supabase is not configured.

Bet placement currently validates odds in the app and persists the resulting slip in the user's state. This is a screen-time betting demo; it does not move money or settle regulated wagers.
