import FamilyControls
import PhotosUI
import SwiftUI
import UIKit

enum SettingsModel {
    static let sections: [String: (title: String, icon: IconName)] = [
        "screentime": ("Screen time", .hourglass),
        "sports": ("Sports & races", .grid),
        "notifications": ("Notifications & privacy", .bell),
        "account": ("Account", .user),
    ]

    /// Older entry points still name sections that now live inside a combined page.
    static func canonical(_ section: String) -> String {
        switch section {
        case "status": return "screentime"
        case "races": return "sports"
        case "privacy": return "notifications"
        default: return section
        }
    }

    static func open(_ section: String) {
        let ui = UIState.shared
        ui.closeAllSheets()
        ui.drawerOpen = false
        ui.openPage(.settings(canonical(section)))
    }
}

enum HowItWorks {
    static func open() {
        UIState.shared.drawerOpen = false
        UIState.shared.openSheet(.how)
    }
}

// MARK: - Drawer

struct DrawerView: View {
    private var store: Store { .shared }
    private var ui: UIState { .shared }
    @State private var shown = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let wl = store.wallet
        let acc = store.account
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Theme.scrim.ignoresSafeArea().onTapGesture { close() }.opacity(shown ? 1 : 0)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Avatar(src: acc?.photo ?? "", size: 64)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("@\(acc?.username ?? "")").font(.barlow(17, 700)).lineLimit(1)
                            Text(acc?.email ?? "").font(.barlow(13)).foregroundStyle(Theme.text2).lineLimit(1)
                            TierBadge(tierId: wl.tier.id, sm: true).padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 18).padding(.horizontal, 18).padding(.bottom, 14)
                    HRule()
                    ScrollView {
                        VStack(spacing: 2) {
                            item("screentime", "\(wl.phoneLeft) min left")
                            item("sports", nil)
                            item("notifications", nil)
                            item("account", nil)
                            row(.help, "App walkthrough", nil) { HowItWorks.open() }
                            row(.info, "Help & support", nil) { openURL(API.supportURL) }
                            row(.shield, "Privacy policy", nil) { openURL(API.privacyURL) }
                            row(.logout, "Log out", nil) { Auth.logout() }
                        }
                        .padding(.top, 8).padding(.horizontal, 8).padding(.bottom, 20)
                    }
                }
                .frame(width: geo.size.width * 0.84)
                .frame(maxHeight: .infinity)
                .background(Theme.sheet.ignoresSafeArea())
                .overlay(alignment: .trailing) { VRule().ignoresSafeArea() }
                .offset(x: shown ? 0 : -geo.size.width)
                .gesture(DragGesture().onEnded { if $0.translation.width < -80 { close() } })
            }
        }
        .onAppear { withAnimation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.25)) { shown = true } }
        .accessibilityAddTraits(.isModal)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { shown = false }
        Task { try? await Task.sleep(for: .milliseconds(200)); ui.drawerOpen = false }
    }

    private func item(_ key: String, _ sub: String?) -> some View {
        let s = SettingsModel.sections[key]!
        return row(s.icon, s.title, sub) { SettingsModel.open(key) }
    }

    private func row(_ icon: IconName, _ title: String, _ sub: String?, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Icon(icon, 20).foregroundStyle(Theme.text2)
                Text(title).font(.barlow(15.5, 700)).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                if let sub { Text(sub).font(.barlow(12, 700)).foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, 12).frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
    }
}

// MARK: - Settings page

struct SettingsPage: View {
    var section: String
    private var app: AppModel { .shared }

    var body: some View {
        let _ = app.tick
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch section {
                case "screentime":
                    ScreenTimeSection()
                    Text("Tier & streak").eyebrow()
                    StatusSection()
                case "sports":
                    SportsSection()
                    Text("Virtual racing").eyebrow()
                    RacesView(embedded: true)
                case "notifications":
                    NotificationsSection()
                    Text("What friends can see").eyebrow()
                    PrivacySection()
                case "account": AccountSection()
                default: EmptyView()
                }
            }
            .padding(.top, 4).padding(.horizontal, 16).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// `brow`: a label on the left and a bold value on the right.
struct BRow: View {
    var label: String
    var value: String
    var color: Color = Theme.text
    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.text2)
            Spacer()
            Text(value).font(.barlow(13, 700)).monospacedDigit().foregroundStyle(color)
        }
        .font(.barlow(13))
    }
}

struct ScreenTimeSection: View {
    private var store: Store { .shared }
    private var ui: UIState { .shared }
    private var st: ScreenTime { .shared }

    var body: some View {
        let wl = store.wallet
        let s = store.data?.settings ?? Settings()
        let usedPct = min(100, Double(wl.used) / Double(max(wl.todayLimit, 1)) * 100)
        let overridesLeft = Rules.maxOverrides - wl.overridesUsed
        VStack(alignment: .leading, spacing: 8) {
            H2("How your screen time works")
            HowCard(n: 1, title: "\(Rules.daily) pledge minutes a day", text: "Your available minutes start at \(Rules.daily)\(wl.tier.bonus > 0 ? " (plus \(wl.tier.bonus) from your \(wl.tier.title) tier)" : "") and reset at midnight, your local time.")
            HowCard(n: 2, title: "Challenges affect tomorrow's phone time", text: "Successful challenges add minutes to tomorrow's allowance. Missed challenges subtract the committed minutes.")
            HowCard(n: 3, title: "The calculation", text: "Tomorrow's allowance = \(Rules.daily) min + today's earned minutes − emergency unlock adjustments.")
        }
        .card()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                H2("Today")
                Spacer()
                HStack(spacing: 4) { Text("Resets in"); Countdown(target: TO.nextMidnight()) }.font(.barlow(11.5, 700)).foregroundStyle(Theme.muted)
            }
            BRow(label: "Base limit", value: "\(Rules.daily) min")
            BRow(label: "Yesterday's challenges", value: Fmt.signedMin(wl.yesterdayNet), color: wl.yesterdayNet > 0 ? Theme.accent : wl.yesterdayNet < 0 ? Theme.loss : Theme.text)
            if wl.penaltyToday > 0 { BRow(label: "Emergency unlock penalty", value: "−\(wl.penaltyToday) min", color: Theme.loss) }
            if s.minLimit > 0 && Rules.daily + wl.yesterdayNet - wl.penaltyToday < s.minLimit { BRow(label: "Raised to your minimum", value: "\(s.minLimit) min") }
            if wl.emergencyToday > 0 { BRow(label: "Emergency unlocks used", value: "+\(wl.emergencyToday) min", color: Theme.warn) }
            HRule()
            BRow(label: "Phone time allowed today", value: "\(wl.todayLimit) min")
            Bar(pct: usedPct, color: wl.appsLocked ? Theme.loss : usedPct > 80 ? Theme.warn : Theme.accent, height: 8)
            HStack {
                Text("\(wl.used) min used on locked apps").foregroundStyle(Theme.text2)
                Spacer()
                Text(st.isEnforcing ? "\(wl.phoneLeft) min left" : "Limits are off").foregroundStyle(wl.appsLocked ? Theme.loss : Theme.text)
            }
            .font(.barlow(11.5, 700))
        }
        .card()

        VStack(alignment: .leading, spacing: 8) {
            H2("Tomorrow, so far")
            BRow(label: "Base limit", value: "\(Rules.daily) min")
            BRow(label: "Today's resolved challenges", value: Fmt.signedMin(wl.todayNet), color: wl.todayNet > 0 ? Theme.accent : wl.todayNet < 0 ? Theme.loss : Theme.text)
            if wl.penaltyTomorrow > 0 { BRow(label: "Emergency unlock penalty", value: "−\(wl.penaltyTomorrow) min", color: Theme.loss) }
            HRule()
            BRow(label: "Tomorrow's phone time", value: "\(wl.tomorrowLimit) min",
                 color: wl.tomorrowLimit > Rules.daily ? Theme.accent : wl.tomorrowLimit < Rules.daily ? Theme.loss : Theme.text)
            if wl.atRisk > 0 { Text("\(wl.atRisk) min in open challenges will change this when they resolve.").font(.barlow(11.5)).foregroundStyle(Theme.muted) }
        }
        .card()

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Icon(.unlock, 18).foregroundStyle(Theme.warn).frame(width: 36, height: 36).background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    H2("Emergency unlock")
                    Text("\(overridesLeft) of \(Rules.maxOverrides) left today").font(.barlow(13)).foregroundStyle(Theme.text2)
                }
            }
            Text("Need your phone right now? Get \(Rules.overrideMinutes) more minutes today. It costs \(Rules.overridePenalty) minutes from tomorrow's limit and resets your clean streak.")
                .font(.barlow(13)).foregroundStyle(Theme.text2)
            Button(overridesLeft > 0 ? "Unlock \(Rules.overrideMinutes) minutes now" : "No unlocks left today") { emergency() }
                .buttonStyle(.btn(.warn, full: true)).disabled(overridesLeft <= 0)
        }
        .card(border: Theme.warn.opacity(0.35))

        VStack(alignment: .leading, spacing: 8) {
            Text("Controls").eyebrow()
            ListBox {
                ListRow("Enforce app limits", sub: st.setupStep == .allow || st.setupStep == .pick ? coloredSub("Set up Screen Time below to turn this on", Theme.warn) : AttributedString("Blocks your chosen apps when today's phone time runs out")) {
                    LrIcon(icon: .shield)
                } trailing: {
                    SwitchView(isOn: st.isEnforcing) { toggleEnforce(!st.isEnforcing) }
                }
                Button { ui.openSheet(.screenTimeApps) } label: {
                    ListRow("Locked apps & sites", sub: AttributedString(deviceSummary)) {
                        LrIcon(icon: .lock)
                    } trailing: { Icon(.chevR, 18).foregroundStyle(Theme.muted) }
                }
                .buttonStyle(.press)
                VStack(alignment: .leading, spacing: 4) {
                    ListRow("Minimum phone time per day", sub: AttributedString("Losses can't push your limit below this")) { LrIcon(icon: .clock) } trailing: { EmptyView() }
                        .padding(.bottom, -14)
                    Seg {
                        ForEach([0, 15, 30], id: \.self) { v in
                            SegButton(on: s.minLimit == v, action: { setMinLimit(v) }) { Text(v > 0 ? "\(v) min" : "None") }
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ListRow("Warn me when phone time is low", sub: AttributedString("Shows a heads-up before apps lock")) { LrIcon(icon: .bell) } trailing: { EmptyView() }
                        .padding(.bottom, -14)
                    Seg {
                        ForEach([5, 10, 15], id: \.self) { v in
                            SegButton(on: s.lowWarn == v, action: {
                                store.updateSettings { $0.lowWarn = v }
                                ScreenTime.shared.sync()
                            }) { Text("\(v) min left") }
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
            Text("Changes to limits ask you to confirm first, so nothing changes by accident.").font(.barlow(11.5)).foregroundStyle(Theme.muted)
        }
    }

    private var deviceSummary: String {
        switch st.status {
        case .approved: return st.hasSelection ? "\(st.selectionSummary) · \(store.lockPoints(store.data ?? store.freshData(TO.now()))) lock points" : "Choose the apps Screen Time blocks"
        case .denied: return "Screen Time access is off"
        case .notDetermined: return "Allow Screen Time to block apps for real"
        }
    }

    private func coloredSub(_ s: String, _ c: Color) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = c
        return a
    }

    private func emergency() {
        Task {
            let wl = store.wallet
            var body = AttributedString("You'll get \(Rules.overrideMinutes) more minutes of phone time today.\n\n")
            var cost = AttributedString("It costs \(Rules.overridePenalty) minutes from tomorrow's limit")
            cost.foregroundColor = Theme.loss
            cost.inlinePresentationIntent = .stronglyEmphasized
            body += cost
            body += AttributedString("\(wl.streak > 0 ? " and ends your \(wl.streak)-day clean streak" : ""). You have \(Rules.maxOverrides - wl.overridesUsed) of \(Rules.maxOverrides) unlocks left today.")
            guard st.isEnforcing else {
                ui.toast(.info, "Nothing is blocked yet", "Set up Screen Time first. Emergency unlocks lift a real block.")
                return
            }
            guard await ui.confirm("Unlock \(Rules.overrideMinutes) minutes now?", body, confirm: "Unlock now", kind: .warn) else { return }
            do {
                try store.useEmergencyUnlock()
                ScreenTime.shared.emergencyUnlock()
                ScreenTime.shared.sync()
                ui.toast(.warn, "+\(Rules.overrideMinutes) min unlocked", "Tomorrow's limit dropped by \(Rules.overridePenalty) min.")
            } catch let e as AppError {
                ui.toast(.loss, "No unlocks left", e.message)
            } catch {}
        }
    }

    private func toggleEnforce(_ want: Bool) {
        Task {
            if want && (st.status != .approved || !st.hasSelection) {
                ui.openSheet(.screenTimeApps)
                return
            }
            // The same rule as removing apps: a limit that's already been hit can't be dodged by switching it off.
            if !want && st.isShieldActive && !st.isOverrideActive {
                _ = await ui.confirm("Your apps are locked right now", "Limits can't be turned off while they're blocking your apps. Use an emergency unlock, or turn limits off after midnight.", confirm: "OK", cancel: nil)
                return
            }
            let ok = want
                ? await ui.confirm("Turn app limits on?", "Your locked apps will close when today's phone time runs out.", confirm: "Turn on")
                : await ui.confirm("Turn app limits off?", "Your locked apps won't close anymore. Your tier drops to Rookie and today won't count as a clean day.", confirm: "Turn off", kind: .danger)
            guard ok else { return }
            store.setEnforce(want)
            ScreenTime.shared.sync()
        }
    }

    private func setMinLimit(_ v: Int) {
        guard v != store.data?.settings.minLimit else { return }
        Task {
            let body = v > 0 ? "No matter how many challenges you lose, you'll always get at least **\(v) minutes** of phone time a day." : "Losses will be able to take your phone time all the way to 0 minutes."
            guard await ui.confirm("Change your minimum phone time?", body, confirm: "Change it") else { return }
            store.updateSettings { $0.minLimit = v }
            ScreenTime.shared.sync()
        }
    }
}

struct StatusSection: View {
    private var store: Store { .shared }
    var body: some View {
        let wl = store.wallet
        let t = wl.tier
        let idx = Store.tiers.firstIndex(of: t) ?? 0
        let next = idx + 1 < Store.tiers.count ? Store.tiers[idx + 1] : nil
        VStack(alignment: .leading, spacing: 14) {
            HStack { H2("Your tier"); Spacer(); TierBadge(tierId: t.id) }
            if let next {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(wl.points) lock point\(wl.points == 1 ? "" : "s")").font(.barlow(13, 700))
                        Spacer()
                        Text("\(next.min - wl.points) more for \(next.title)").font(.barlow(13)).foregroundStyle(Theme.text2)
                    }
                    Bar(pct: Double(wl.points - t.min) / Double(next.min - t.min) * 100, color: Color(hex: next.color))
                }
            } else {
                Text("Top tier. \(wl.points) lock points.").font(.barlow(15, 700)).foregroundStyle(Color(hex: t.color))
            }
            if store.data?.settings.enforce != true {
                Note(.warn, icon: .info, "App limits are off, so your lock points don't count. Turn them on in Screen time.")
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Store.tiers.dropFirst(), id: \.id) { r in
                    let reached = idx >= (Store.tiers.firstIndex(of: r) ?? 0)
                    HStack(alignment: .top, spacing: 10) {
                        Icon(reached ? .check : r.icon, 18).foregroundStyle(reached ? Color(hex: r.color) : Theme.muted).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Text(r.title).font(.barlow(15, 700)).foregroundStyle(reached ? Theme.text : Theme.text2)
                                Text("\(r.min)+ pts").font(.barlow(11.5, 700)).foregroundStyle(Theme.muted)
                            }
                            Text(Store.tierPerks(r).joined(separator: " · ")).font(.barlow(13)).foregroundStyle(reached ? Theme.text2 : Theme.muted)
                        }
                    }
                }
            }
            Text("Lock more of your real screen time to climb. Apps and websites are 1 point; whole categories (like Social) are 3.").font(.barlow(11.5)).foregroundStyle(Theme.muted)
            Button { UIState.shared.openSheet(.screenTimeApps) } label: { BtnLabel("Choose locked apps", icon: .lock, iconSize: 16) }.buttonStyle(.btn(.ghost, .sm, full: true))
        }
        .card()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Icon(.flame, 20).foregroundStyle(wl.streak > 0 ? Theme.warn : Theme.muted)
                    Text(wl.streak > 0 ? "\(wl.streak)-day clean streak" : "No clean streak yet").font(.barlow(16, 700))
                }
                Spacer()
                if wl.multiplier > 1 { Tag("Wins \(Fmt.mult(wl.multiplier))", .green, big: true) }
            }
            if let ms = Store.nextStreakMilestone(wl.streak) {
                Bar(pct: Double(wl.streak) / Double(ms.days) * 100, color: Theme.warn)
                Text("\(ms.days - wl.streak) more clean day\(ms.days - wl.streak == 1 ? "" : "s") for \(Fmt.mult(ms.mult)) earned minutes.").font(.barlow(13, 700)).foregroundStyle(Theme.text2)
            } else {
                Text("Max multiplier reached. Keep it going.").font(.barlow(13, 700)).foregroundStyle(Theme.accent)
            }
            Text("A clean day means limits were on, you stayed under your phone time, and you didn't use an emergency unlock. Earned minutes get ×1.1 at 3 days and ×1.25 at 7. An emergency unlock resets the streak.")
                .font(.barlow(13)).foregroundStyle(Theme.text2)
        }
        .card()
    }
}

struct SportsSection: View {
    private var store: Store { .shared }
    var body: some View {
        let s = store.data?.settings.sports ?? []
        Text("Choose what shows up on your Home feed. You can change this any time.").font(.barlow(13)).foregroundStyle(Theme.text2)
        ListBox {
            ForEach(Sim.leagueOrder.filter { $0 != "sim" }, id: \.self) { l in
                let L = Sim.leagues[l]!
                let on = s.contains(l)
                ListRow(L.title, sub: AttributedString(L.sport.prefix(1).uppercased() + L.sport.dropFirst())) {
                    SportSquare(text: L.short)
                } trailing: {
                    SwitchView(isOn: on) { toggle(l, !on) }
                }
                .onTapGesture { toggle(l, !on) }
            }
        }
    }

    private func toggle(_ id: String, _ on: Bool) {
        let cur = store.data?.settings.sports ?? []
        let next = on ? Sim.leagueOrder.filter { $0 != "sim" && (cur.contains($0) || $0 == id) } : cur.filter { $0 != id && $0 != "sim" }
        store.updateSettings { $0.sports = next }
        store.setFeedFilter("all")
        LiveFeed.shared.refresh(force: true)
        LiveFeed.shared.refreshUpcoming()
    }
}

struct NotificationsSection: View {
    private var store: Store { .shared }
    var body: some View {
        let n = store.data?.settings.notify ?? NotifySettings()
        let notifier = Notifier.shared
        switch notifier.access {
        case .allowed, .unknown:
            Text("Banners while TimeOut is open, and iPhone notifications when it isn't.").font(.barlow(13)).foregroundStyle(Theme.text2)
        case .notDetermined:
            Note(.blue, icon: .bell) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Turn on notifications to hear about results and friend requests when TimeOut is closed.")
                    Button("Turn on notifications") { Task { await notifier.requestIfNeeded() } }.buttonStyle(.btn(.primary, .xs))
                }
            }
        case .denied:
            Note(.warn, icon: .bell) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are off for TimeOut in iPhone Settings, so these only show while the app is open.")
                    Button("Open iPhone Settings") { openSettings() }.buttonStyle(.btn(.primary, .xs))
                }
            }
        }
        ListBox {
            row(.target, "Challenge results", "When a matchup challenge is completed", n.resolved) { v in store.updateSettings { $0.notify.resolved = v } }
            row(.userPlus, "Friend requests", "When someone adds or accepts you", n.friends) { v in store.updateSettings { $0.notify.friends = v } }
            row(.phone, "Low phone time", "Before your locked apps close", n.lowTime) { v in
                store.updateSettings { $0.notify.lowTime = v }
                ScreenTime.shared.sync()
            }
        }
        Text("Challenge results and friend requests usually arrive within about a minute, even when TimeOut is closed.")
            .font(.barlow(11.5)).foregroundStyle(Theme.muted)
            .onAppear { Task { await notifier.refreshAccess() } }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func row(_ icon: IconName, _ title: String, _ sub: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        ListRow(title, sub: AttributedString(sub)) { LrIcon(icon: icon) } trailing: { SwitchView(isOn: on) { set(!on) } }
            .onTapGesture { set(!on) }
    }
}

struct PrivacySection: View {
    private var store: Store { .shared }
    var body: some View {
        let p = store.data?.settings.privacy ?? PrivacySettings()
        Text("Friends only see what you turn on here. Anything off shows as \"Private\" to them.").font(.barlow(13)).foregroundStyle(Theme.text2)
        ListBox {
            row(.chart, "My record", "Wins and losses", p.record) { v in store.updateSettings { $0.privacy.record = v } }
            row(.hourglass, "Minutes won or lost", "Your leaderboard number", p.minutes) { v in store.updateSettings { $0.privacy.minutes = v } }
            row(.target, "My active challenges", "Picks you currently have open", p.challenges) { v in store.updateSettings { $0.privacy.challenges = v } }
        }
    }

    private func row(_ icon: IconName, _ title: String, _ sub: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        ListRow(title, sub: AttributedString(sub)) { LrIcon(icon: icon) } trailing: { SwitchView(isOn: on) { set(!on) } }
            .onTapGesture { set(!on) }
    }
}

struct AccountSection: View {
    private var store: Store { .shared }
    private var ui: UIState { .shared }
    @State private var username = ""
    @State private var email = ""
    @State private var current = ""
    @State private var newPassword = ""
    @State private var errors: [String: String] = [:]
    @State private var photoItem: PhotosPickerItem?
    @State private var loaded = false
    @State private var deleting = false

    var body: some View {
        let a = store.account
        let server = a?.server
        Group {
            HStack(spacing: 14) {
                if server == nil {
                    PhotosPicker(selection: $photoItem, matching: .images) { photo(a?.photo ?? "", camera: true) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Profile photo").font(.barlow(15, 700))
                        Text("Tap the photo to change it.").font(.barlow(13)).foregroundStyle(Theme.text2)
                    }
                } else {
                    PhotosPicker(selection: $photoItem, matching: .images) { photo(a?.photo ?? "", camera: true) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("@\(a?.username ?? "")").font(.barlow(15, 700))
                        Text(a?.email ?? "").font(.barlow(13)).foregroundStyle(Theme.text2)
                    }
                }
            }
            if let server {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) { Icon(.check, 16); Text("Your account is synced").font(.barlow(15, 700)) }
                    HStack { Text("User ID").foregroundStyle(Theme.text2); Spacer(); Text(server.id).font(.barlow(15, 700)).lineLimit(1).truncationMode(.middle) }
                    HStack { Text("Member since").foregroundStyle(Theme.text2); Spacer(); Text(Fmt.date(LiveFeed.parseDate(server.createdAt) ?? TO.now())).font(.barlow(15, 700)) }
                }
                .card()
            }
            VStack(alignment: .leading, spacing: 14) {
                if server != nil { H2("Profile") }
                FieldView(label: "Username", text: $username, err: errors["username"], content: .username)
                FieldView(label: "Email", text: $email, err: errors["email"], keyboard: .emailAddress, content: .emailAddress)
                Button("Save changes") { save() }.buttonStyle(.btn(.primary, full: true))
            }
            .card()
            VStack(alignment: .leading, spacing: 14) {
                H2("Change password")
                if server == nil {
                    FieldView(label: "Current password", text: $current, secure: true, err: errors["currentPassword"], content: .password)
                }
                FieldView(label: "New password", text: $newPassword, secure: true, err: errors["newPassword"], hint: "At least 8 characters", content: .newPassword)
                Button("Update password") { updatePassword() }.buttonStyle(.btn(.ghost, full: true))
            }
            .card()
            VStack(spacing: 8) {
                Button { Auth.logout() } label: { BtnLabel("Log out", icon: .logout) }.buttonStyle(.btn(.ghost, full: true))
                Button { deleteAccount() } label: { Text(deleting ? "Deleting account…" : "Delete account").foregroundStyle(Theme.loss) }
                    .buttonStyle(.btn(.quiet, full: true)).disabled(deleting)
                if server == nil {
                    Text("This account is stored only on this device.").font(.barlow(11.5)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            username = a?.username ?? ""
            email = a?.email ?? ""
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let url = PhotoData.dataURL(from: data) else {
                    ui.toast(.loss, "That image could not be read."); return
                }
                do {
                    if store.account?.server != nil { try await API.shared.updateProfile(.init(photoUrl: url)) }
                    try store.updateAccount(.init(photo: url))
                    ui.toast(.win, "Photo updated")
                } catch { ui.toast(.loss, "Couldn't update your photo", AppError.friendly(error)) }
            }
        }
    }

    private func photo(_ src: String, camera: Bool) -> some View {
        Avatar(src: src, size: 84)
            .overlay(alignment: .bottomTrailing) {
                if camera {
                    Icon(.camera, 15).foregroundStyle(Theme.accentInk).frame(width: 30, height: 30).background(Theme.accent, in: Circle())
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 3)).offset(x: 2, y: 2)
                }
            }
    }

    private func save() {
        errors = [:]
        Task {
            do {
                if store.account?.server != nil { try await API.shared.updateProfile(.init(username: username, email: email)) }
                try store.updateAccount(.init(username: username, email: email))
                ui.toast(.win, "Account saved")
            } catch let e as AppError {
                errors = e.fields
                if e.fields.isEmpty { ui.toast(.loss, "Couldn't save your changes", e.message) }
            } catch { ui.toast(.loss, "Couldn't save your changes", AppError.friendly(error)) }
        }
    }

    private func updatePassword() {
        errors = [:]
        Task {
            do {
                if let invalid = Store.validatePassword(newPassword) { throw AppError(code: "invalid", message: invalid, fields: ["newPassword": invalid]) }
                if store.account?.server != nil { try await API.shared.updateProfile(.init(password: newPassword)) }
                else { try store.updateAccount(.init(currentPassword: current, newPassword: newPassword)) }
                current = ""; newPassword = ""
                ui.toast(.win, "Password updated")
            } catch let e as AppError {
                errors = e.fields
                if e.fields.isEmpty { ui.toast(.loss, "Couldn't update your password", e.message) }
            } catch { ui.toast(.loss, "Couldn't update your password", AppError.friendly(error)) }
        }
    }

    private func deleteAccount() {
        Task {
            let server = store.account?.server != nil
            let body = server
                ? "This permanently deletes your TimeOut account, challenges, wallet and settings from TimeOut's servers and this device, and takes you off your teams. It can't be undone."
                : "This removes your account, challenges and friends from this device. It can't be undone."
            guard await ui.confirm("Delete your account?", body, confirm: "Delete account", kind: .danger) else { return }
            if server {
                deleting = true
                defer { deleting = false }
                do { try await API.shared.deleteAccount() } catch {
                    ui.toast(.loss, "Couldn't delete your account", AppError.friendly(error))
                    return
                }
            }
            ScreenTime.shared.accountGone()
            store.deleteAccount()
            Slip.shared.clear()
            AppModel.shared.boot()
        }
    }
}

// MARK: - Sheets

struct HowItWorksSheet: View {
    var body: some View {
        SheetFrame("App walkthrough", tall: true, close: { UIState.shared.closeSheet(.how) }) {
            WalkthroughPager { UIState.shared.closeSheet(.how) }
                .frame(height: 520)
        }
    }
}

/// The real iPhone block list: Apple's Screen Time permission, then Apple's app picker. Used by the sheet and onboarding.
struct ScreenTimeSetupCard: View {
    private var st: ScreenTime { .shared }
    private var store: Store { .shared }
    @State private var showPicker = false

    var body: some View {
        let step = st.setupStep
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                stepRow(1, "Allow Screen Time", "You approve it with Face ID or your passcode.", done: st.status == .approved, active: step == .allow)
                HRule()
                stepRow(2, "Choose the apps to block", st.hasSelection ? st.selectionSummary : "Apple keeps the list private: TimeOut only sees how many you picked.", done: st.hasSelection, active: step == .pick)
                HRule()
                stepRow(3, "Limits turn on", "Your chosen apps lock when today's phone time runs out.", done: step == .done, active: step == .turnOn)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))

            if st.status == .denied {
                Note(.warn, icon: .alert, "Screen Time access is off. Tap Allow Screen Time to try again, or turn it on for TimeOut in iPhone Settings › Screen Time.")
            }
            if let err = st.lastError {
                FormError(err)
                #if targetEnvironment(simulator)
                Note(.blue, icon: .info, "Blocking apps needs a real iPhone. The Simulator can't block anything.")
                #endif
            }
            if step == .done {
                Note(.green, icon: .check, "You're set. \(st.selectionSummary) lock when today's \(store.wallet.todayLimit) min run out.")
            }
            if let pending = st.pendingRemovalSummary {
                Note(.warn, icon: .clock, "\(pending) leave the list at midnight. Removals wait a day so a limit can't be dodged.")
            }
            if st.isShieldActive && !st.isOverrideActive { Note(.red, icon: .lock, "Today's limit is reached: your chosen apps are blocked until midnight.") }
            if st.isOverrideActive, let until = st.overrideUntil { Note(.warn, icon: .unlock, "Emergency unlock until \(Fmt.time(TO.ms(until))).") }

            primaryButton(step)
        }
        .familyActivityPicker(isPresented: $showPicker, selection: Binding(get: { st.draft }, set: { st.draft = $0 }))
        .onChange(of: showPicker) { _, open in if !open { st.applyDraft() } }
    }

    @ViewBuilder private func primaryButton(_ step: ScreenTime.SetupStep) -> some View {
        switch step {
        case .allow:
            Button("Allow Screen Time") {
                Task {
                    await st.requestAuthorization()
                    // Go straight to the next step, so setup stays one flow.
                    if st.status == .approved && !st.hasSelection { openPicker() }
                }
            }
            .buttonStyle(.btn(.primary, full: true))
        case .pick:
            Button { openPicker() } label: { BtnLabel("Choose apps to block", icon: .lock) }.buttonStyle(.btn(.primary, full: true))
        case .turnOn:
            Button("Turn limits on") {
                store.setEnforce(true)
                st.sync()
            }
            .buttonStyle(.btn(.primary, full: true))
        case .done:
            Button { openPicker() } label: { BtnLabel("Change apps", icon: .lock) }.buttonStyle(.btn(.ghost, full: true))
        }
    }

    private func openPicker() {
        st.prepareDraft()
        showPicker = true
    }

    private func stepRow(_ n: Int, _ title: String, _ sub: String, done: Bool, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if done { Icon(.check, 15).foregroundStyle(Theme.accentInk) }
                else { Text("\(n)").font(.display(16, 900)).foregroundStyle(active ? Theme.accentInk : Theme.text2) }
            }
            .frame(width: 28, height: 28)
            .background(done || active ? Theme.accent : Theme.raised, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.barlow(15, 700)).foregroundStyle(done || active ? Theme.text : Theme.text2)
                Text(sub).font(.barlow(12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}

/// Setup and the block list, opened from the Home banner and Settings.
struct ScreenTimeAppsSheet: View {
    private var ui: UIState { .shared }

    var body: some View {
        SheetFrame("Locked apps & sites", tall: true, close: { ui.closeSheet(.screenTimeApps) }) {
            Text("TimeOut uses Apple's Screen Time to actually block the apps you choose when today's phone time runs out. The more you lock, the higher your tier.")
                .font(.barlow(13)).foregroundStyle(Theme.text2)
            ScreenTimeSetupCard()
        }
    }
}
