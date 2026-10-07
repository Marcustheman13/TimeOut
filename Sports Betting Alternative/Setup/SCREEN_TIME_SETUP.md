# Turning on real Screen Time limits

The app builds and runs without any of this. The balance, bets, settlement and stats all work in the
Simulator. These steps connect it to Apple's Screen Time so a lost bet actually locks your apps.

Needs: the paid developer team already set on the project (`Q7845K7NU8`) and a real iPhone on iOS 26.1+.
Screen Time APIs do nothing in the Simulator.

## 1. Main app capabilities

1. Open `Sports Betting Alternative.xcodeproj` in Xcode.
2. Select the **Sports Betting Alternative** target → **Signing & Capabilities**.
3. Check the bundle ID is `com.marcuswilliams.staketime` (change it if Xcode says it's taken, see *Changing IDs* below).
4. Click **+ Capability** → add **Family Controls**.
5. Click **+ Capability** → add **App Groups** → click **+** → enter `group.marcuswilliams.staketime`.

## 2. Add the monitor extension

This small background piece locks apps when you hit your limit and resets things at midnight, even when the app is closed.

1. **File → New → Target…** → search **Device Activity Monitor Extension** → Next.
2. Product Name: `ScreenTimeMonitor`. Leave "Embed in Application" set to the app → **Finish**.
   If asked to activate the scheme, choose **Don't Activate** (you run the app, not the extension).
3. Open the new `ScreenTimeMonitor/DeviceActivityMonitorExtension.swift` Xcode created and replace **all** of
   its contents with `Setup/DeviceActivityMonitorExtension.swift` from this folder.
4. Select the **ScreenTimeMonitor** target:
   - **General → Minimum Deployments**: iOS **26.1**
   - **Signing & Capabilities**: same Team, then **+ Capability → Family Controls** and
     **+ Capability → App Groups** with the same `group.marcuswilliams.staketime` box checked.

## 3. Run it

1. Plug in your iPhone, pick it as the run destination, press **Run**.
2. In the app: **Account → Connect Screen Time** → approve with Face ID/passcode.
3. Tap **Apps to limit** and pick the apps or categories that count (e.g. Social, Games, Entertainment).
   Enforcement shows **ON** once something is picked.

## 4. Test it without waiting an hour

Debug builds show a **Testing** card on the Account screen. Tap **1 min**, then use one of the limited apps
for a minute. It should lock with StakeTime's custom lock screen. Back in StakeTime, Account then shows
**Limit reached** and the **Emergency Unlock** button (15 minutes, costs 30 minutes tomorrow, 2 per day).
Tap **Real** to go back to the actual limit.

## How the pieces talk

| Piece | Job |
|---|---|
| `ScreenTimeManager.swift` (app) | Asks permission, stores the app picks, registers a daily schedule with one usage event at today's limit, applies emergency unlocks |
| `DeviceActivityMonitorExtension` | Locks apps when the event fires, lifts the lock at midnight and registers the new day's limit, re-locks when an unlock window ends |
| `StakeTimeShield` (`ShieldConfigurationExtension`) | Draws the custom lock screen: today's limit, tomorrow's limit, W-L record |
| `BackgroundSettlement.swift` (app) | Asks iOS to wake the app while bets are open, settles them, updates limits and sends a notification |
| App Group `UserDefaults` | Shared state: the app picks, today's and tomorrow's limits, record, whether the limit was reached, unlock end time |

The app writes both today's and tomorrow's limit on every refresh, so at midnight the extension can
switch to the new limit even if the app hasn't been opened.

Background settlement is best-effort: iOS decides when to wake the app (usually within an hour or two,
less often in Low Power Mode, and never if the user swipes StakeTime away in the app switcher or turns off
Background App Refresh for it). Opening the app always settles immediately.

## Changing IDs

If you change the bundle ID or App Group, update the group string in **three** places:
`ScreenTimeShared.appGroup` in `Services/ScreenTimeManager.swift`, and `Shared.appGroup` in
`ScreenTimeMonitor/DeviceActivityMonitorExtension.swift` and `StakeTimeShield/ShieldConfigurationExtension.swift`.
Also update all three `.entitlements` files.

## Before TestFlight / App Store

Development builds work with just the capability. To distribute, Apple must approve the
**Family Controls (Distribution)** entitlement for all three bundle IDs. See `FAMILY_CONTROLS_REQUEST.md`
for drafted answers.
