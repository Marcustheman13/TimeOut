# Turning on real Screen Time limits

The app builds and runs without any of this. Accounts, bets, settlement and stats all work in the
Simulator, exactly like the web demo. These steps connect it to Apple's Screen Time so running out of
phone time actually blocks your apps.

Needs: the paid developer team already set on the project (`Q7845K7NU8`) and a real iPhone on iOS 26.1+.
Screen Time APIs do nothing in the Simulator.

## 1. What's already in the project

`TimeOut.xcodeproj` has three targets, all signed with the team above:

| Target | Bundle ID | Job |
|---|---|---|
| `TimeOut` | `com.marcuswilliams.staketime` | The app |
| `TimeOutMonitor` | `com.marcuswilliams.staketime.ScreenTimeMonitor` | Device Activity Monitor extension |
| `TimeOutShield` | `com.marcuswilliams.staketime.StakeTimeShield` | Custom lock screen |

The bundle IDs keep their original names on purpose, so the Family Controls entitlement and App Group
(`group.marcuswilliams.staketime`) stay valid. All three targets have the **Family Controls** and **App Groups**
capabilities in their `.entitlements` files.

## 2. Run it

1. Plug in your iPhone, pick it as the run destination, press **Run**.
2. Lock at least one app in **Menu → Screen time → Locked apps & sites** (this is the same list as the web
   demo and decides your tier). **Enforce app limits** turns on with it.
3. **Menu → Screen time → Block apps on this iPhone** → **Allow Screen Time** → approve with Face ID/passcode.
4. Tap **Choose apps to block** and pick the real apps or categories (e.g. Social, Games, Entertainment).

From then on the apps you picked are blocked when today's phone time runs out. Usage on them counts toward
"Phone time left" on Home.

## 3. Test it

Make today's limit small: lose a bet or two (or set **Minimum phone time** to None), then use one of the
blocked apps until the limit is reached. It locks with TimeOut's custom lock screen. **Emergency unlock** in
Screen time lifts the block for 15 minutes (costs 30 minutes tomorrow, 2 per day).

## How the pieces talk

| Piece | Job |
|---|---|
| `TimeOut/Services/ScreenTime.swift` (app) | Asks permission, stores the app picks, registers a daily schedule with usage checkpoints and one event at today's limit, applies emergency unlocks |
| `TimeOutMonitor/DeviceActivityMonitorExtension.swift` | Records usage, blocks apps when the limit event fires, lifts the block at midnight and registers the new day's limit, re-blocks when an unlock window ends |
| `TimeOutShield/ShieldConfigurationExtension.swift` | Draws the custom lock screen: tomorrow's limit and W-L record |
| `AppModel.backgroundRefresh()` (app) | Asks iOS to wake the app, refreshes scores, settles bets and sends a notification |
| App Group `UserDefaults` | Shared state: the app picks, today's and tomorrow's limits, usage, record, whether the limit was reached, unlock end time |

The app writes both today's and tomorrow's limit on every refresh, so at midnight the extension can
switch to the new limit even if the app hasn't been opened.

Removing apps from the block list waits until midnight while limits are running, so a limit can't be
dodged halfway through the day. Adding apps blocks them right away.

Background settlement is best-effort: iOS decides when to wake the app (usually within an hour or two,
less often in Low Power Mode, and never if the user swipes TimeOut away in the app switcher or turns off
Background App Refresh for it). Opening the app always settles immediately.

## Changing IDs

If you change the bundle ID or App Group, update the group string in **three** places:
`ScreenTimeShared.appGroup` in `TimeOut/Services/ScreenTime.swift`, and `Shared.appGroup` in
`TimeOutMonitor/DeviceActivityMonitorExtension.swift` and `TimeOutShield/ShieldConfigurationExtension.swift`.
Also update all three `.entitlements` files.

## Before TestFlight / App Store

Development builds work with just the capability. To distribute, Apple must approve the
**Family Controls (Distribution)** entitlement for all three bundle IDs. See `FAMILY_CONTROLS_REQUEST.md`
for drafted answers.
