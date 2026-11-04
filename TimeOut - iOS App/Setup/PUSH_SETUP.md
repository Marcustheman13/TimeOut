# Push notification setup

Friend requests and challenge results reach the phone within about a minute, even with TimeOut closed.

## How it works

- **Friend requests:** a new row in `friend_requests` calls the `send-push` Edge Function straight away.
- **Challenge results:** a closed app can't resolve a challenge, so the database doesn't change when its game ends. `pg_cron` runs `send-push` every minute, and it checks ESPN for each open challenge. It also picks up results saved from another device.
- **The result itself:** the app still resolves challenges and works out the wallet, as it always has. The server only sends the notification, so a difference in the server's grading could word a notification wrongly but can't change anyone's minutes. It grades with the same rules as the app: `Sim.gradeScore` and `Store.outcome`, copied to `supabase/functions/send-push/plan.ts`. **If those rules change, change both.**
- **Settings:** `app_preferences.notify.friends` and `notify.resolved` are checked before sending.
- **Not covered:** to-do and race challenges only exist on the device. They still use local notifications.

## Setup

These need doing once, in this order. Only the first three need an Apple or Supabase login.

### 1. Create the APNs key

1. In [Apple Developer → Keys](https://developer.apple.com/account/resources/authkeys/list), add a key with **Apple Push Notifications service (APNs)** ticked. Set its environment to **Sandbox & Production**.
2. Download the `.p8` file. Apple only lets you do this once, so keep it safe and never commit it.
3. Note the **Key ID**. The Team ID is `Q7845K7NU8`.

### 2. Turn on the capability

Open the project in Xcode, select the **TimeOut** target, and check **Signing & Capabilities**. Push Notifications should be listed, from `TimeOut.entitlements`. If signing shows an error, press **Try Again** so Xcode adds it to the `com.marcuswilliams.staketime` App ID.

### 3. Update the database

In the Supabase SQL Editor for project `obegznrsxlbpmtbmqkll`:

1. Run `server/db/apply-all-november-2026.sql` if it hasn't been run. **iOS builds from before the November 2026 rename stop syncing challenges after this.**
2. Run `server/db/supabase-push.sql`.
3. Make a long random secret (`openssl rand -hex 32`) and store it. Sending stays off until this exists:

   ```sql
   select vault.create_secret('THE_SECRET', 'push_webhook_secret');
   ```

### 4. Deploy the function

From the repository root:

```bash
npx supabase login
```

```bash
npx supabase secrets set --project-ref obegznrsxlbpmtbmqkll APNS_KEY_ID=THE_KEY_ID APNS_TEAM_ID=Q7845K7NU8 PUSH_WEBHOOK_SECRET=THE_SECRET APNS_PRIVATE_KEY="$(cat /path/to/AuthKey_THE_KEY_ID.p8)"
```

```bash
npx supabase functions deploy send-push --project-ref obegznrsxlbpmtbmqkll --no-verify-jwt
```

`--no-verify-jwt` is needed because the database calls it with `x-push-secret` instead of a user's login. The function checks that secret itself.

## Test it on a real iPhone

The simulator isn't enough. Build from Xcode to the phone, allow notifications, then swipe TimeOut away.

1. **Friend request:** from another account, send this one a request. It should arrive within seconds.
2. **Challenge result:** place a challenge on a game that's about to end, then close the app. It should arrive within about a minute of ESPN marking the game final.
3. **Settings:** turn each one off in TimeOut's Settings, open and close the app so the change saves, and repeat. Nothing should arrive.
4. **Sign out:** sign out and send another request. Nothing should arrive.

## If nothing arrives

- Is there a row for the phone? `select user_id, environment, updated_at from device_tokens;`
- Did the database reach the function? `select status_code, error_msg, created from net._http_response order by created desc limit 10;`
- What did Apple say? Look at the function's logs in the Supabase dashboard:
  - `InvalidProviderToken`: wrong key, Key ID or Team ID.
  - `BadDeviceToken`: wrong environment. Builds from Xcode are `sandbox`, and TestFlight and the App Store are `production`.
  - `TopicDisallowed`: the key's team doesn't own the bundle ID.
- Anything already sent is recorded in `push_log`. Delete its row to send it again.

## Tests

```bash
deno test supabase/functions/send-push/plan_test.ts
```
