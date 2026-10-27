# TimeOut: App Store listing, version 1.0

Copy each section into the matching field in App Store Connect. Character counts are checked against Apple's limits.

## App name (30 max)

```
TimeOut: Bet Screen Time
```

## Subtitle (30 max)

```
Sports picks, no money ever
```

## Promotional text (170 max)

Shown above the description. You can change it any time without a new app review.

```
Bet your screen time, not your money. Pick winners with live odds, win back phone time for tomorrow, and climb the leaderboard with friends.
```

## Description (4,000 max)

```
TimeOut is a sports prediction game where you bet screen time instead of money.

Everyone gets 60 betting minutes a day. Win a bet and the minutes you win are added to tomorrow's phone time. Lose and they come off it. The stakes feel real, but nobody ever loses a dollar. There are no purchases, no deposits and no prizes, ever.

LIVE SCORES AND ODDS
• Pro and college football, basketball, baseball, hockey and soccer
• Moneylines, spreads and totals, refreshed while games are live
• Today's and tomorrow's games, with stats for every matchup

BET IN TWO TAPS
• Tap a price, then Place bet
• Build parlays with up to 10 picks across different games
• See exactly what you win or lose before you confirm
• Bets settle on their own when games end, and postponed games are voided with your stake returned

YOUR SCREEN TIME, ON THE LINE
• Lock the apps that eat your day, like social media, video and games
• When today's phone time runs out, TimeOut blocks them with Apple's Screen Time
• Emergency unlocks are there if you really need them, but they cost you tomorrow
• Turn on a minimum so losses can never take your phone time below a floor you choose

TIERS AND STREAKS
• Lock more apps to climb from Rookie to Hall of Fame
• Higher tiers earn bonus betting minutes, odds boosts and parlay insurance
• Stay under your limit for clean days in a row and your winnings get multiplied

COMPETE WITH FRIENDS
• Find friends by username or share your invite link
• Compare records on a leaderboard ranked by minutes won
• Start a team for a week or a season and see who comes out on top
• Choose exactly what friends can see

ALSO INSIDE
• Virtual horse racing for when there's no game on
• Shareable bet cards to post your picks anywhere
• Your bets and settings sync between the app and the TimeOut website

TimeOut is built for people who love sports and the thrill of making a pick, without the money or the damage. No cash, no prizes, no house edge.

Scores and odds are provided for entertainment. Real app blocking requires Screen Time permission on your iPhone.
```

## Keywords (100 max, comma-separated, no spaces)

```
screen time,sports,picks,odds,parlay,football,basketball,predictions,app limits,focus,habit,friends
```

## What's New in This Version (4,000 max)

For version 1.0, App Store shows this as the first release notes.

```
Welcome to TimeOut! The first release includes:
• Live scores and odds for football, basketball, baseball, hockey and soccer
• Single bets and parlays with screen-time stakes
• Real app blocking with Apple's Screen Time when your phone time runs out
• Tiers, clean-day streaks, odds boosts and parlay insurance
• Friends, leaderboards and teams
• Virtual horse racing
```

## TestFlight: What to Test (4,000 max)

Paste this into the build's **Test Details** in TestFlight.

```
Thanks for testing TimeOut 1.0!

Log in with the test account below, or create your own account (you'll need to confirm your email).

Please try:
1. Home: browse today's and tomorrow's games, switch sports, and open a game's "Stats & all odds".
2. Place a single bet: tap any price, pick a stake, tap Place bet. Check it appears in My Bets.
3. Build a parlay: tap Build parlay, pick 2 or more games, then Finalize Parlay.
4. My Bets: watch open bets update while games are live, and check results after games end.
5. Social: search for a friend's username, send a request, and create a team.
6. Menu > Screen time: lock apps, allow Screen Time, choose apps to block, and try an emergency unlock.
7. Menu > Virtual Racing: start a race or bet on one.
8. Log out and back in on the TimeOut website with the same account. Your bets should be there.

Known limitations:
• Bet results arrive after each game ends, so some bets stay open for a few hours.
• Real app blocking only works on a physical iPhone, not in the simulator.

Send feedback with a screenshot from TestFlight (take a screenshot, then tap Share Beta Feedback).
```

## App Review Information

**Sign-in required:** Yes

| Field | Value |
|---|---|
| User name | `marcusdanielwill@gmail.com` |
| Password | `test_account_pass` |

**Notes for the reviewer:**

```
TimeOut is a sports prediction game where users bet screen time, not money. Everyone gets 60 betting minutes a day; wins add phone time tomorrow and losses take it away. There are no purchases, deposits, prizes or real-money wagers of any kind.

Scores and odds come from ESPN's public scoreboard data and are shown for entertainment.

Real app blocking uses the Family Controls framework: Menu > Screen time > "Block apps on this iPhone" asks for Screen Time permission and lets the user pick the apps that get blocked when today's phone time runs out. Betting works without granting Screen Time permission.

The demo account above already has open bets, friends and a team. Account deletion is in Menu > Account > Delete account.
```

## Other App Store Connect fields

| Field | Value |
|---|---|
| Primary category | Sports |
| Secondary category | Lifestyle |
| Age rating | Answer **Simulated Gambling: Frequent/Intense** |
| Copyright | `2026 TimeOut` (or your team's name) |
| Privacy policy URL | Needed before submitting (see `Setup/APP_STORE_CHECKLIST.md`) |
| Support URL | Needed before submitting |

## Screenshots

In `Screenshots/`, 6.9" iPhone size (1320 × 2868), ready to upload in this order:

1. `01-home.png`: balance, tier and open bets
2. `02-games.png`: live game feed with odds
3. `03-bet-slip.png`: bet slip (+455 underdog, win 46 minutes)
4. `04-game.png`: game page with your bet and all markets
5. `05-my-bets.png`: record and an open parlay
6. `06-friends.png`: friends leaderboard
7. `07-tier-streak.png`: tiers and perks
8. `08-welcome.png`: welcome screen
