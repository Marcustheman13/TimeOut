# Requesting Family Controls (Distribution)

Development builds on your own phone already work. Apple has to approve the **distribution** version of
Family Controls before StakeTime can go out through TestFlight or the App Store. Approval can take days to weeks,
so request it early.

## Who submits it

The **Account Holder** of the Apple Developer team (`Q7845K7NU8`) has to submit it, signed in at
developer.apple.com. Go to **Account → Certificates, Identifiers & Profiles**, or search the developer site for
"Family Controls distribution request". Apple moves this page occasionally.

## Request it for all three bundle IDs

Every target that has the Family Controls capability needs its own approval:

| Target | Bundle ID |
|---|---|
| App | `com.marcuswilliams.staketime` |
| Lock monitor | `com.marcuswilliams.staketime.ScreenTimeMonitor` |
| Custom lock screen | `com.marcuswilliams.staketime.StakeTimeShield` |

## Suggested answers

Edit these to fit. The form asks what the app does and how it uses the Screen Time APIs.

**App name:** StakeTime

**Who uses it:** Individuals managing their own screen time (`.individual` authorization). This is not a
parental-control app and it doesn't manage other people's devices.

**What the app does:**
> StakeTime is a free sports-prediction game that helps people who struggle with sports-betting addiction get
> the excitement of betting without risking money. Instead of money, users stake minutes of their own daily
> screen time. Each user gets a 60-minute daily allowance. Winning picks add minutes to the next day's
> screen-time limit, and losing picks remove minutes. No real money is ever involved, and the app has no
> connection to any real sportsbook.

**How it uses Family Controls / Screen Time:**
> After the user grants individual authorization, they choose which apps and categories count toward their
> limit using FamilyActivityPicker. The app uses DeviceActivity to monitor usage of only those selected apps
> against the user's daily limit. When the limit is reached, a DeviceActivityMonitor extension applies a
> ManagedSettings shield to the selected apps until local midnight. A ShieldConfiguration extension shows
> a custom shield explaining the limit. Users can do a limited "emergency unlock" (15 minutes, a few times a
> day) that reduces the next day's limit. All data stays on the device in an App Group. We don't collect,
> transmit or sell any usage data or app selections.

**Why the capability is needed:**
> Setting a real screen-time limit that the user commits to in advance is the core of the product. It's
> what makes the stakes real without money. Without Family Controls the limit couldn't be enforced.

## After approval

Nothing changes in the code. Xcode's automatic signing picks up the distribution entitlement once Apple
enables it. Then archive the app (**Product → Archive**) and upload it to TestFlight as usual.
