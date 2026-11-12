import SwiftUI

/// The app walkthrough: shown once after sign-up, and any time from the menu. Keep in step with TO.WALKTHROUGH on the web.
struct WalkthroughPage {
    var icon: IconName
    var title: String
    var text: String
    var points: [String]

    static let all: [WalkthroughPage] = [
        .init(icon: .hourglass, title: "Pledge minutes, not money", text: "You get 60 pledge minutes every day. They reset at midnight.",
              points: ["Pick a game and call the outcome.", "Pledge some of your minutes on it.", "No money changes hands, ever."]),
        .init(icon: .target, title: "Win to earn, miss to lose", text: "Results are settled automatically when the game ends.",
              points: ["Win: your pledge comes back with bonus minutes added to tomorrow's phone time.", "Miss: those minutes come off tomorrow's phone time.", "Postponed game: your minutes are returned."]),
        .init(icon: .target, title: "New to sports picks?", text: "Every game has three ways to play. Pick a tab, then tap one of the two choices.",
              points: ["Match Winner: just pick which team wins the game.", "Margin: pick a team to win by at least a set number of points (\u{201C}win by 7+\u{201D}), or to win or lose by less than it (\u{201C}stay within 7\u{201D}).", "Total Points: guess if both teams' scores added together end up over or under the number shown.", "Not sure? Match Winner is the simplest place to start."]),
        .init(icon: .chart, title: "What 1.54x and 2.54x mean", text: "The number on each choice shows how many minutes you get back if you're right.",
              points: ["Multiply your pledge by it: 10 minutes at 1.54x comes back as about 15 minutes.", "Target (2x or less): the favorite. More likely to win, smaller reward.", "Bonus (over 2x): the underdog. Less likely, but a bigger reward.", "Picking more than one choice combines them into one Combined Target. Bigger reward, but every pick has to win.", "Numbers can change before kickoff as the game looks more or less even."]),
        .init(icon: .lock, title: "Set up Screen Time", text: "TimeOut turns your daily allowance into a real limit on your phone.",
              points: ["Tap Allow Screen Time and approve with Face ID or your passcode.", "Choose the apps to block. Apple keeps the list private.", "When today's minutes run out, those apps lock until midnight.", "The website shows the same minutes and stays in sync with your phone."]),
        .init(icon: .users, title: "Play with friends", text: "Challenges are better with people watching.",
              points: ["Find friends by username or send them your invite link.", "Accept requests under Social \u{2192} Requests; they move straight to Friends.", "Compare records on the leaderboard (you choose what you share).", "Start a team and race over a week."]),
        .init(icon: .flame, title: "Tiers and streaks", text: "The more apps you lock, the higher your tier.",
              points: ["Higher tiers unlock bonus minutes and allowance boosts.", "Keep a winning streak to climb faster.", "Change your locked apps any time in Settings."]),
        .init(icon: .bell, title: "You're set", text: "Same account on the website and the iPhone app.",
              points: ["Pledges, friends and minutes stay in sync everywhere.", "Turn notifications on to hear about results and friend requests.", "Reopen this walkthrough any time from the menu."]),
    ]
}

/// Swipeable walkthrough pages with Back / Next. `onFinish` runs after the last page (or Skip when `skippable`).
struct WalkthroughPager: View {
    var finishLabel = "Got it"
    var skippable = false
    var onFinish: () -> Void
    @State private var index = 0
    private let pages = WalkthroughPage.all

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Icon(p.icon, 30).foregroundStyle(Theme.accent)
                                .frame(width: 60, height: 60)
                                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            Text(p.title).font(.display(30, 900)).padding(.top, 6)
                            Text(p.text).font(.barlow(16)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(p.points, id: \.self) { t in
                                    HStack(alignment: .top, spacing: 10) {
                                        Icon(.check, 15).foregroundStyle(Theme.accent).padding(.top, 3)
                                        Text(t).font(.barlow(15)).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4).padding(.bottom, 8)
                    }
                    .scrollIndicators(.hidden)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule().fill(i == index ? Theme.accent : Theme.raised).frame(width: i == index ? 20 : 7, height: 7)
                }
            }
            .padding(.vertical, 14)
            .animation(.easeOut(duration: 0.2), value: index)
            HStack(spacing: 10) {
                if index > 0 { Button("Back") { withAnimation { index -= 1 } }.buttonStyle(.btn(.ghost)) }
                Button(index == pages.count - 1 ? finishLabel : "Next") {
                    if index == pages.count - 1 { onFinish() } else { withAnimation { index += 1 } }
                }
                .buttonStyle(.btn(.primary, full: true))
            }
            if skippable { Button("Skip walkthrough") { onFinish() }.buttonStyle(.btn(.quiet, .sm, full: true)).padding(.top, 6) }
        }
    }
}
