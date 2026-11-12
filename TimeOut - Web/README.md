# TimeOut — app frontend

> **▶ Try the app:** <https://marcustheman13.github.io/TimeOut/> (resizes to fit phones, tablets and computers)
> Live ESPN point value and real accounts, nothing to install. It updates by itself when the web demo changes on `main`.

A working HTML/CSS/JS mockup of TimeOut, the sports challenge app where you pledge screen time instead of money.
It follows the group PRD and screen specs in `../docs/PRD - Prioritization & Design Sprint.pdf`.
For the backend, database and team setup, see the [main README](../README.md).

## Open it

- **Easiest: the live site.** <https://marcustheman13.github.io/TimeOut/>. It uses live ESPN point value and Supabase accounts, and updates after changes are pushed to `main`.
- **With Supabase (normal):** serve the app over HTTP. Accounts use Supabase Auth; preferences, challenges, and wallet transactions use the Supabase tables and RPCs.
- **Offline demo:** use the app with Supabase config removed. Accounts and state are then saved only in that browser.
- The interface fills the available viewport and can be wrapped in a native app shell.

## One page for every screen size

`index.html` (server: <http://localhost:3000>, single file: `dist/TimeOut.html`) adapts to the window:

| Width | Layout |
| --- | --- |
| 900 px and up | Sidebar, wide content grid, challenge slip docked on the right |
| 721–899 px | Icon sidebar, challenge slip opens as a dialog |
| 720 px and below | Menu button, single column, phone-sized controls |

The layout lives in `css/web.css` and `js/web.js`, loaded after the shared `css/app.css` and `js/` files. To change how a
feature works, edit the shared files in `js/`; to change only the layout, edit those two. `web.html` is kept only so old
links (and invite links) forward to the main page. The iPhone app is the native version of the phone layout.

## Logging in

- **Try the demo account** on the welcome screen logs straight in. It comes with challenge history, open challenges, friends, a team and a pending friend request.
- Demo login: username `demo` (or `demo@timeout.app`), password `timeout123`.
- **Create account** asks for a username, email, password and an optional photo. You can then log in with either the username or the email.
- Supabase accounts use email and password. When email confirmation is enabled, confirm the signup email before logging in.
- Supabase stores screen-time challenges, challenge picks, and wallet ledger entries. The browser also keeps a local cache so the sports feed and app remain responsive.
- In offline mode, accounts are saved only in that browser. Two accounts made in the same browser can friend each other.

## What's in it

| Spec item | Where to find it |
| --- | --- |
| Today's and tomorrow's games | Home: the **Today / Tomorrow** picker under the sport filters. Tomorrow's point value load when you open it. |
| Home: balance + open challenges at top, live feed by sport, 3-tap challenging | Home tab. Tap any price, then **Place challenge** (2 taps). A new price replaces the pick; closing the slip (✕) clears it. |
| Combos | In the slip, **Add another pick for a combo** opens a page of open games. Pick up to 3, then **Review combo**. |
| Point value/scores refresh ≤ 30 s; point value change on an open slip needs re-confirm | Live point values refresh every 15 s. Slip shows old → new price and an **Accept new point value** button. |
| 60 min daily balance, resets at midnight; challenges use tomorrow's time | Wallet card on Home, Menu > Screen time. |
| "Not enough screentime" + remaining balance | Challenge slip. The pledge can't go above today's balance; typing more snaps back to it and shows this message. |
| No connection | A red banner appears, and challenging and login are paused until the connection returns. |
| Balance 0 → challenging locked with midnight countdown | Home wallet card and challenge slip. |
| Auto resolution, voids for postponed games | Challenges resolve seconds after a game ends. Postponed games void and refund. |
| Game detail: live score, stats, point value, your challenges, research | Tap a team or **Stats & all point value** on any game. Tapping a price opens the slip; the floating **Make a challenge** button jumps to the point values. |
| My Challenges: open challenges with live score/stats, history, record and share | My Challenges tab. |
| Challenge sharing image | **Share** on any challenge. |
| Social: stats vs friends, username search, invite link, requests, teams with dates and privacy | Social tab. What friends see is in Menu > What friends can see. Requests shows when each was sent or received; sent requests can be sent again once an hour. |
| Screentime & settings: how it works, controls (confirmed), sports, account, notifications, emergency unlock | Menu (☰) at the top left. **Enforce app limits** can only be on while at least one app is locked. |
| Record / performance | Top of My Challenges. |
| Sports simulations for days without sports | Sim League. |
| Emergency override with a penalty | Menu > Screen time > Emergency unlock: +15 min now, −30 min tomorrow, 2 per day, resets streak. |
| Pick which sports to follow | Onboarding and Menu > Sports on Home. |
| Prediction markets, to-do combos | Home filter chips **Predictions** and **To-Do Combos**. |
| Tiers and clean-streak multiplier (from the iOS app) | Status strip on Home, Menu > Tier & streak. |

Not included on purpose: monetization (per the team's call), real money, combos over 3 picks.

## Notes

- Games use simulated scores and point value with real team names. Each game runs for 12 minutes.
- Point values are fair (no house cut), computed from the score and time left, the same model as the iOS prototype.
- `python3 build.py` rebuilds `dist/TimeOut.html` after you edit anything in `css/` or `js/`.

# Supabase accounts and saved challenges

The web demo uses Supabase Auth for email/password accounts, saves user preferences in `public.user_settings`, and stores sports challenge tickets and picks in `public.challenges` and `public.challenge_picks`. Wallet balance changes go through Supabase RPC functions and the `wallets` / `wallet_transactions` tables.

1. The main schema and challenge RPCs have been applied. Run [`../server/db/supabase-settings-migration.sql`](../server/db/supabase-settings-migration.sql) in **SQL Editor** to add the JSON settings field used for locked apps and other app preferences.
2. Run [`db/tier-system-migration.sql`](db/tier-system-migration.sql) in **SQL Editor** to persist locked-app settings, daily tier bonuses, point-value boosts, and combo protection usage. It is safe to rerun after an earlier version.
3. Confirm **Email provider** is enabled under **Authentication → Providers**. Email confirmation is enabled, so new users must confirm their email before logging in.
   After **Create account**, the app shows a *Verify your email* page. It logs the new user in by itself as soon as the email is confirmed, and the link in the email also logs them straight in. Signing up on `localhost` still sends that link to the live site, so opening it from Gmail does not try to load `localhost:3000`.

   In **Authentication → URL Configuration**:
   - Set **Site URL** to `https://marcustheman13.github.io/TimeOut/` (not `http://localhost:3000`). Supabase falls back to the Site URL when a redirect is missing, and that address is what the email uses.
   - Under **Redirect URLs**, keep:
     - `https://marcustheman13.github.io/TimeOut/**` (required; this is where confirmation links go)
     - `http://localhost:3000/**` and `http://localhost:8765/**` only if you still want those pages to be allowed redirects for other auth flows
4. Serve this app over HTTP (`cd server && npm start`, then open `http://localhost:3000`). Supabase sign-in does not work from the serverless `file://` mode.

## Website admin page

The website sidebar shows **Admin** to the `@easton.putnam`, `@time_out_account`, `@wrfairholm`, and `@obr0` accounts. To enable the page and its user-management actions, run [`../server/db/supabase-admin.sql`](../server/db/supabase-admin.sql) in Supabase SQL Editor after the main Supabase schema has been applied. The migration provisions the matching accounts that already exist; if any of those accounts are created later, rerun the migration to provision them. Authorization is checked by the database functions, and admin accounts cannot be deleted from the page. User email and password are not editable there; admins can edit usernames, display names, and avatar URLs.

The dashboard's four OKR metrics are backed by admin-only database RPCs in `supabase-admin.sql`. Rerun that SQL file after adding metric queries to install or update the functions.

The frontend's publishable key is in `js/supabase-config.js`; publishable keys are intended to be public. The main schema enables row-level security, and the RPCs verify the signed-in owner before changing challenges or wallet balances. Never put a Supabase secret/service-role key in this project or in browser code. The legacy local demo remains available only when Supabase is not configured.

Challenge placement currently validates point value in the app and persists the resulting slip in the user's state. This is a screen-time challenging demo; it does not move money or resolve regulated pledges.
