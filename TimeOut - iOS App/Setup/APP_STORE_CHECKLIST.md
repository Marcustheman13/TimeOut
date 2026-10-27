# Publishing TimeOut to the App Store

What's already handled in the project, and what the team still has to do before the first submission.

## Already done in the app

- **Builds for release.** `TimeOut.xcodeproj` archives for a real device (iOS 26.1+, iPhone only, portrait), version 1.0 build 1.
- **App icon** is a 1024×1024 PNG with no transparency.
- **Launch screen** uses the app's dark background, so there's no white flash on launch.
- **Privacy manifests** (`PrivacyInfo.xcprivacy`) are in the app and both extensions. They declare no tracking and the data the app collects:
  email address, user ID, profile photo and other user content (bets, teams), all for app functionality and linked to the account.
- **Encryption:** `ITSAppUsesNonExemptEncryption` is `NO`, because the app only uses HTTPS. App Store Connect won't ask the export-compliance question.
- **Account deletion** (Guideline 5.1.1(v)): Menu → Account → **Delete account** removes the account from Supabase and the device.
  It needs the SQL in step 1 below.
- **Password reset:** **Forgot password?** on the login screen emails a reset link through Supabase.
- **Notifications:** the app asks for permission after login, for bet results and the "5 minutes left" warning.
- **No money anywhere.** Bets use screen-time minutes only. There are no purchases, prizes or cash-out.

## What the team has to do

### 1. Turn on account deletion in Supabase (required)

Run [`server/db/supabase-delete-account.sql`](../../server/db/supabase-delete-account.sql) once in the TimeOut Supabase project's **SQL Editor**.
Until it's run, **Delete account** shows "Account deletion isn't set up on the server yet", and App Review will reject the app.

### 2. Get the Family Controls (Distribution) entitlement (required)

Real app blocking uses Apple's Screen Time APIs. Development builds work, but TestFlight and App Store builds can't be
signed until Apple approves **Family Controls (Distribution)** for all three bundle IDs:
`com.marcuswilliams.staketime`, `.ScreenTimeMonitor` and `.StakeTimeShield`.
Request it at <https://developer.apple.com/contact/request/family-controls-distribution> using the answers in
[`FAMILY_CONTROLS_REQUEST.md`](FAMILY_CONTROLS_REQUEST.md). Approval can take days to weeks, so start this first.

### 3. Create the app in App Store Connect

- **Bundle ID:** `com.marcuswilliams.staketime` (team `Q7845K7NU8`).
- **Name:** "TimeOut" may already be taken; something like "TimeOut: Screen Time Bets" works as a fallback.
- **Category:** Sports (primary), Lifestyle or Health & Fitness (secondary).

### 4. Age rating

In the age rating questionnaire, answer **Simulated Gambling: Frequent/Intense**. Betting is the core of the app, even
without money. That gives the app the highest age rating, which is expected for sports-betting-style apps.

### 5. Privacy policy and support URLs (required)

App Store Connect needs a **privacy policy URL** and a **support URL**. A simple page on the GitHub Pages site works.
The policy should say: accounts (email, username, optional photo) and bets, wallet and settings are stored in Supabase;
scores and odds come from ESPN; Screen Time app choices stay on the device (Apple keeps them private); no tracking, no ads,
no selling data; how to delete the account (in the app, Menu → Account).

### 6. App Privacy answers

Match the privacy manifest: **Email Address, User ID, Photos, Other User Content**, each *linked to the user*,
*not used for tracking*, purpose *App Functionality*.

### 7. App Review notes and a test account (required)

Reviewers need to log in. Create a TimeOut account just for them (confirm its email), lock at least one app in
onboarding, and put the email and password in **App Review Information**. Suggested note:

> TimeOut is a sports prediction game where users bet screen time, not money. Everyone gets 60 betting minutes a day;
> wins add phone time tomorrow and losses take it away. There are no purchases, prizes or real-money wagers.
> Scores and odds come from ESPN. Real app blocking uses the Family Controls framework: Menu → Screen time →
> "Block apps on this iPhone" asks for Screen Time permission and lets you pick the apps to block when today's phone time runs out.

### 8. Screenshots

Upload iPhone screenshots at **6.9"** (1320 × 2868), for example: Home, a game page, the bet slip, My Bets, Social.
The iPhone 17 Pro Max simulator produces the right size (Device → Screenshot, or ⌘S).

### 9. Archive and upload

In Xcode: pick **Any iOS Device (arm64)** → **Product → Archive** → **Distribute App → App Store Connect → Upload**.
Bump **Build** (`CURRENT_PROJECT_VERSION`) for every upload.

## Review risks to know about

- **Simulated gambling (Guideline 5.3):** the age rating and the "no money, no prizes" review note above are the main defense.
- **Team logos and ESPN data (Guideline 5.2, intellectual property):** game cards show team logos and odds from ESPN's
  public endpoints. App Review sometimes asks for proof of rights to show league and team marks. If that comes up,
  the quickest fix is hiding the logos (the colored team badges with abbreviations already work without them).
- **Screen Time without permission:** if a reviewer skips Screen Time permission, betting still works; only real blocking is off.
