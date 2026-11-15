Hello,

Thank you for the review and the clear guidance. We've updated the app and uploaded a new build.

**Guideline 5.1.1(iv): Screen Time permission request**

We changed the Screen Time message so it no longer pushes users to grant access:

- The button under our explanation now says "Continue" instead of "Allow Screen Time". Tapping it always goes straight to Apple's Screen Time prompt.
- We removed the "Skip for now" button from the onboarding screen that shows this message. Users can't close the message and put off the request. They see the explanation, tap Continue, and answer Apple's prompt. Onboarding then continues whether they allow or deny.
- If a user denies access, we respect that. We don't ask again. The app tells them that app limits need Screen Time access and gives them an "Open Settings" button so they can turn it on later. Everything else in the app keeps working without Screen Time access.

**Guideline 2.1: Information needed**

1. Does the app share any screen data with friend users?

No. TimeOut doesn't send any Screen Time data off the device, and friends can't see it. That includes which apps a user locks, their app usage, and their phone-time minutes. The app list comes from Apple's FamilyActivityPicker as opaque tokens, so TimeOut itself can't see which apps were chosen.

Accepted friends can only see in-app challenge stats: win-loss record, challenge minutes won or lost, active challenges, clean streak and tier. Users choose which of the record, minutes and challenges to share under Settings › Privacy ("What friends see"). People who aren't friends see nothing beyond username, photo and tier.

2. Before blocking apps, does it require the team member user's consent?

Yes, because only the user can block their own apps. TimeOut requests Screen Time authorization with `.individual` for the person using the device. That person picks their own apps in Apple's picker and turns limits on themselves. Friends and team members can't block, choose or change apps on anyone else's device. Teams are only a leaderboard that compares challenge results over a date range. Joining a team doesn't change any limits.

3. Once the team member request has been received, are users able to accept or deny the request?

Yes. Nobody can be added to a team without agreeing. In this build:

- Inviting a friend to a team sends an invite. It doesn't add them. The invite appears in Social › Teams under "Team invites" with two buttons, "Join team" and "Decline". The person only joins the roster if they tap Join team. If they decline, they're never added. Our server enforces this too: only the person themselves can put their own account on a team.
- When someone opens a team link, they see the team name and dates with two choices: "Add friend and join" or "Not now".
- Friend requests also have Accept and Decline. Users only become friends after the request is accepted.
- Members can leave a team at any time with "Leave team".

Being on a team never affects Screen Time, app limits or any other setting on the user's device.

To review, sign in with the demo account in the review notes. It already has a friend, a team ("Review Crew"), and a pending team invite ("Weekend Warriors") in Social › Teams, so you can try Join team and Decline.

Thank you,
Marcus Williams
