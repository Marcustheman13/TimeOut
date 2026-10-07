# TimeOut — clickable web demo

A working HTML/CSS/JS mockup of TimeOut, the sportsbook where you bet screen time instead of money.
It follows the group PRD and screen specs in `../docs/PRD - Prioritization & Design Sprint.pdf`.
For the backend, database and team setup, see the [main README](../README.md).

## Open it

- **With the database (normal):** in `../server`, run `npm install` then `npm start`, and open <http://localhost:3000>. Accounts and login go through the API and are saved in PostgreSQL.
- **Offline demo:** double-click `index.html` (or `dist/TimeOut.html`, the same app in one file you can email or AirDrop). With no server, accounts are saved only in that browser.
- On a laptop it shows as a phone with a **tester console** beside it. On a real phone it fills the screen, and the tester console moves to **Menu (☰) > Tester tools**.

## Logging in

- **Try the demo account** on the welcome screen logs straight in. It comes with bet history, open bets, friends, a team, a pending friend request and a bet challenge.
- Demo login: username `demo` (or `demo@timeout.app`), password `timeout123`.
- **Create account** asks for a username, email, password and an optional photo. You can then log in with either the username or the email.
- With the server running, accounts live in the database and every login updates `last_login_at` and `login_count` (see Menu > Account). Seeded test accounts `mike_t`, `jess.plays` and `lily_k` also use `timeout123`.
- Bets, wallet, friends and settings are still saved in the browser you're using (localStorage), per account.
- In offline mode, accounts are saved only in that browser. Two accounts made in the same browser can friend each other and send each other challenges.

## What's in it

| Spec item | Where to find it |
| --- | --- |
| Home: balance + open bets at top, live feed by sport, 3-tap betting | Home tab. Tap any price, then **Place bet** (2 taps). |
| Odds/scores refresh ≤ 30 s; odds change on an open slip needs re-confirm | Live odds refresh every 15 s. Slip shows old → new price and an **Accept new odds** button. |
| 60 min daily balance, resets at midnight; bets use tomorrow's time | Wallet card on Home, Menu > Screen time. |
| "Not enough screentime" + remaining balance | Bet slip, when the stake is higher than your balance. |
| Balance 0 → betting locked with midnight countdown | Home wallet card and bet slip. |
| Auto settlement, voids for postponed games | Bets settle seconds after a game ends. Postponed games void and refund. |
| Game detail: live score, stats, odds, your bets, research | Tap a team or **Stats & all odds** on any game. |
| My Bets: open bets with live score/stats, history, record, share, send to friend | My Bets tab. |
| Bet sharing image + friend bets with a 100-character custom stake | **Share** and **Send to friend** on any bet, or **Friend bet** in the slip. |
| Social: stats vs friends, username search, invite link, requests, challenges, teams with dates, privacy | Social tab. What friends see is in Menu > What friends can see. |
| Screentime & settings: how it works, controls (confirmed), sports, account, notifications, emergency unlock | Menu (☰) at the top left. |
| Record / performance | Top of My Bets. |
| Sports simulations for days without sports | Sim League (turn on "no real games" in the tester console to see the empty state). |
| Emergency override with a penalty | Menu > Screen time > Emergency unlock: +15 min now, −30 min tomorrow, 2 per day, resets streak. |
| Pick which sports to follow | Onboarding and Menu > Sports on Home. |
| Prediction markets, to-do parlays | Home filter chips **Predictions** and **To-Do Parlays**. |
| Tiers and clean-streak multiplier (from the iOS app) | Status strip on Home, Menu > Tier & streak. |

Not included on purpose: monetization (per the team's call), real money, parlays over 3 picks.

## Tester console

Skip time, jump to 11:59 PM or past midnight, finish or postpone the games you bet on, move the odds on your slip,
simulate phone use, set your balance to 0, get a friend request or challenge, and reset data. It also has a checklist of
everything worth testing from the spec, which ticks itself off as you go.

## Notes

- All games are simulated with real team names. Each game is sped up to 12 minutes so testers can watch bets settle.
- Odds are fair (no house cut), computed from the score and time left, the same model as the iOS prototype.
- `python3 build.py` rebuilds `dist/TimeOut.html` after you edit anything in `css/` or `js/`.
