import FamilyControls
import PhotosUI
import SwiftUI

enum SettingsModel {
    static let sections: [String: (title: String, icon: IconName)] = [
        "screentime": ("Screen time", .hourglass),
        "races": ("Virtual Racing", .target),
        "status": ("Tier & streak", .trophy),
        "sports": ("Sports on Home", .grid),
        "notifications": ("Notifications", .bell),
        "privacy": ("What friends can see", .eye),
        "account": ("Account", .user),
    ]

    static func open(_ section: String) {
        let ui = UIState.shared
        ui.closeAllSheets()
        ui.drawerOpen = false
        ui.openPage(.settings(section))
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
                            item("races", nil)
                            item("status", wl.streak > 0 ? "\(wl.streak)-day streak" : nil)
                            item("sports", nil)
                            item("notifications", nil)
                            item("privacy", nil)
                            item("account", nil)
                            row(.help, "How TimeOut works", nil) { HowItWorks.open() }
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
        return Group {
            if section == "races" {
                RacesView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch section {
                        case "screentime": ScreenTimeSection()
                        case "status": StatusSection()
                        case "sports": SportsSection()
                        case "notifications": NotificationsSection()
                        case "privacy": PrivacySection()
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
            HowCard(n: 1, title: "\(Rules.daily) betting minutes a day", text: "Your betting balance starts at \(Rules.daily) minutes\(wl.tier.bonus > 0 ? " (plus \(wl.tier.bonus) from your \(wl.tier.title) tier)" : "") and resets at midnight, your local time.")
            HowCard(n: 2, title: "You bet tomorrow's phone time", text: "Every minute you win is added to tomorrow's limit. Every minute you lose comes off it.")
            HowCard(n: 3, title: "The math", text: "Tomorrow's limit = \(Rules.daily) min + today's bet results − emergency unlock penalties.")
        }
        .card()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                H2("Today")
                Spacer()
                HStack(spacing: 4) { Text("Resets in"); Countdown(target: TO.nextMidnight()) }.font(.barlow(11.5, 700)).foregroundStyle(Theme.muted)
            }
            BRow(label: "Base limit", value: "\(Rules.daily) min")
            BRow(label: "Yesterday's bets", value: Fmt.signedMin(wl.yesterdayNet), color: wl.yesterdayNet > 0 ? Theme.accent : wl.yesterdayNet < 0 ? Theme.loss : Theme.text)
            if wl.penaltyToday > 0 { BRow(label: "Emergency unlock penalty", value: "−\(wl.penaltyToday) min", color: Theme.loss) }
            if s.minLimit > 0 && Rules.daily + wl.yesterdayNet - wl.penaltyToday < s.minLimit { BRow(label: "Raised to your minimum", value: "\(s.minLimit) min") }
            if wl.emergencyToday > 0 { BRow(label: "Emergency unlocks used", value: "+\(wl.emergencyToday) min", color: Theme.warn) }
            HRule()
            BRow(label: "Phone time allowed today", value: "\(wl.todayLimit) min")
            Bar(pct: usedPct, color: wl.appsLocked ? Theme.loss : usedPct > 80 ? Theme.warn : Theme.accent, height: 8)
            HStack {
                Text("\(wl.used) min used on locked apps").foregroundStyle(Theme.text2)
                Spacer()
                Text(s.enforce ? "\(wl.phoneLeft) min left" : "Limits are off").foregroundStyle(wl.appsLocked ? Theme.loss : Theme.text)
            }
            .font(.barlow(11.5, 700))
        }
        .card()

        VStack(alignment: .leading, spacing: 8) {
            H2("Tomorrow, so far")
            BRow(label: "Base limit", value: "\(Rules.daily) min")
            BRow(label: "Today's settled bets", value: Fmt.signedMin(wl.todayNet), color: wl.todayNet > 0 ? Theme.accent : wl.todayNet < 0 ? Theme.loss : Theme.text)
            if wl.penaltyTomorrow > 0 { BRow(label: "Emergency unlock penalty", value: "−\(wl.penaltyTomorrow) min", color: Theme.loss) }
            HRule()
            BRow(label: "Tomorrow's phone time", value: "\(wl.tomorrowLimit) min",
                 color: wl.tomorrowLimit > Rules.daily ? Theme.accent : wl.tomorrowLimit < Rules.daily ? Theme.loss : Theme.text)
            if wl.atRisk > 0 { Text("\(wl.atRisk) min in open bets will change this when they settle.").font(.barlow(11.5)).foregroundStyle(Theme.muted) }
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
                ListRow("Enforce app limits", sub: s.lockedApps.isEmpty ? coloredSub("Lock at least one app or site below to turn this on", Theme.warn) : AttributedString("Blocks your locked apps when today's phone time runs out")) {
                    LrIcon(icon: .shield)
                } trailing: {
                    SwitchView(isOn: s.enforce && !s.lockedApps.isEmpty) { toggleEnforce(!(s.enforce && !s.lockedApps.isEmpty)) }
                }
                Button { ui.openSheet(.locked) } label: {
                    ListRow("Locked apps & sites", sub: AttributedString("\(s.lockedApps.count) locked · \(store.lockPoints(store.data ?? store.freshData(TO.now()))) lock points")) {
                        LrIcon(icon: .lock)
                    } trailing: { Icon(.chevR, 18).foregroundStyle(Theme.muted) }
                }
                .buttonStyle(.press)
                Button { ui.openSheet(.screenTimeApps) } label: {
                    ListRow("Block apps on this iPhone", sub: AttributedString(deviceSummary)) {
                        LrIcon(icon: .phone)
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
                            SegButton(on: s.lowWarn == v, action: { store.updateSettings { $0.lowWarn = v } }) { Text("\(v) min left") }
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
        case .approved: return st.hasSelection ? "\(st.selectionSummary) blocked at your limit" : "Pick the apps Screen Time blocks"
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
            if want && (store.data?.settings.lockedApps.isEmpty ?? true) {
                if await ui.confirm("Lock an app first", "App limits need at least one locked app, site or category to block. Choose what TimeOut locks when your phone time runs out, and limits turn on with it.", confirm: "Choose apps", cancel: "Not now") {
                    ui.openSheet(.locked)
                }
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
            let body = v > 0 ? "No matter how many bets you lose, you'll always get at least **\(v) minutes** of phone time a day." : "Losses will be able to take your phone time all the way to 0 minutes."
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
            Button { UIState.shared.openSheet(.locked) } label: { BtnLabel("Choose locked apps", icon: .lock, iconSize: 16) }.buttonStyle(.btn(.ghost, .sm, full: true))
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
                Text("\(ms.days - wl.streak) more clean day\(ms.days - wl.streak == 1 ? "" : "s") for \(Fmt.mult(ms.mult)) winnings.").font(.barlow(13, 700)).foregroundStyle(Theme.text2)
            } else {
                Text("Max multiplier reached. Keep it going.").font(.barlow(13, 700)).foregroundStyle(Theme.accent)
            }
            Text("A clean day means limits were on, you stayed under your phone time, and you didn't use an emergency unlock. Winnings get ×1.1 at 3 days and ×1.25 at 7. An emergency unlock resets the streak.")
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
        Text("These show as banners at the top of the screen.").font(.barlow(13)).foregroundStyle(Theme.text2)
        ListBox {
            row(.ticket, "Bet results", "When a bet wins, loses or is voided", n.settled) { v in store.updateSettings { $0.notify.settled = v } }
            row(.userPlus, "Friend requests", "When someone adds or accepts you", n.friends) { v in store.updateSettings { $0.notify.friends = v } }
            row(.phone, "Low phone time", "Before your locked apps close", n.lowTime) { v in store.updateSettings { $0.notify.lowTime = v } }
        }
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
            row(.ticket, "My open bets", "Picks you currently have open", p.bets) { v in store.updateSettings { $0.privacy.bets = v } }
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
                    HStack(spacing: 6) { Icon(.check, 16); Text("Connected to Supabase").font(.barlow(15, 700)) }
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
                } catch { ui.toast(.loss, (error as? AppError)?.message ?? error.localizedDescription) }
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
            } catch let e as AppError { errors = e.fields } catch { ui.toast(.loss, error.localizedDescription) }
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
            } catch let e as AppError { errors = e.fields } catch { ui.toast(.loss, error.localizedDescription) }
        }
    }

    private func deleteAccount() {
        Task {
            let server = store.account?.server != nil
            let body = server
                ? "This permanently deletes your TimeOut account, bets, wallet and settings from TimeOut's servers and this device, and takes you off your teams. It can't be undone."
                : "This removes your account, bets and friends from this device. It can't be undone."
            guard await ui.confirm("Delete your account?", body, confirm: "Delete account", kind: .danger) else { return }
            if server {
                deleting = true
                defer { deleting = false }
                do { try await API.shared.deleteAccount() } catch {
                    ui.toast(.loss, "Couldn't delete your account", (error as? AppError)?.message ?? error.localizedDescription)
                    return
                }
            }
            store.deleteAccount()
            Slip.shared.clear()
            AppModel.shared.boot()
        }
    }
}

// MARK: - Sheets

struct HowItWorksSheet: View {
    var body: some View {
        SheetFrame("How TimeOut works", close: { UIState.shared.closeSheet(.how) }) {
            HowCard(n: 1, title: "Bet screen time, not money", text: "You get \(Rules.daily) betting minutes every day. They reset at midnight.")
            HowCard(n: 2, title: "Winning buys you phone time", text: "Win a bet and the minutes you win are added to tomorrow's phone time. Lose and they come off it.")
            HowCard(n: 3, title: "Bets settle on their own", text: "When a game ends, your bet pays out within minutes. Postponed games are voided and you get your stake back.")
            HowCard(n: 4, title: "Out of minutes? Wait for midnight", text: "At 0 minutes, betting locks until the reset. Emergency unlocks exist, but they cost you tomorrow.")
        } foot: {
            Button("Got it") { UIState.shared.closeSheet(.how) }.buttonStyle(.btn(.primary, full: true))
        }
    }
}

struct LockedAppsSheet: View {
    @State private var draft: [String] = Store.shared.data?.settings.lockedApps ?? []
    private var store: Store { .shared }
    private var ui: UIState { .shared }

    var body: some View {
        let pts = Store.points(draft)
        let t = Store.tierForPoints(store.data?.settings.enforce == true ? pts : 0)
        SheetFrame("Locked apps & sites", tall: true, close: { ui.closeSheet(.locked) }) {
            Text("These are the apps TimeOut blocks when your phone time runs out. The more you lock, the higher your tier.").font(.barlow(13)).foregroundStyle(Theme.text2)
            HStack { Text("\(pts) lock points").font(.barlow(15, 700)); Spacer(); TierBadge(tierId: t.id) }.card(12)
            group("Categories · 3 pts each", "Category")
            group("Apps · 1 pt each", "App")
            group("Websites · 1 pt each", "Website")
        } foot: {
            Button("Save locked apps") { save() }.buttonStyle(.btn(.primary, full: true))
        }
    }

    @ViewBuilder private func group(_ title: String, _ kind: String) -> some View {
        Text(title).eyebrow()
        ListBox {
            ForEach(Store.lockable.filter { $0.kind == kind }, id: \.id) { x in
                Button { draft = draft.contains(x.id) ? draft.filter { $0 != x.id } : draft + [x.id] } label: {
                    ListRow(x.name, sub: AttributedString("\(x.note.map { "\($0) · " } ?? "")\(x.pts) pt\(x.pts == 1 ? "" : "s")")) {
                        LrIcon(icon: kind == "Category" ? .grid : kind == "Website" ? .globe : .phone, bg: Color(hex: x.color).opacity(0.13), fg: Color(hex: x.color))
                    } trailing: { CheckBox(on: draft.contains(x.id)) }
                }
                .buttonStyle(.press)
            }
        }
    }

    private func save() {
        Task {
            let before = store.data?.settings.lockedApps ?? []
            let removed = before.filter { !draft.contains($0) }
            let oldTier = store.tier(store.data ?? store.freshData(TO.now()))
            let willEnforce = !draft.isEmpty && ((store.data?.settings.enforce ?? false) || before.isEmpty)
            let newTier = Store.tierForPoints(willEnforce ? Store.points(draft) : 0)
            var body = "\(draft.count) apps, sites and categories will be locked when your phone time runs out."
            if newTier.id != oldTier.id { body += "\n\nYour tier changes from **\(oldTier.title)** to **\(newTier.title)**." }
            if !removed.isEmpty { body += "\n\nUnlocked apps stop counting right away." }
            if draft.isEmpty && store.data?.settings.enforce == true { body += "\n\n**App limits turn off** because nothing is locked." }
            if !draft.isEmpty && before.isEmpty { body += "\n\nApp limits turn on." }
            guard await ui.confirm("Update locked apps?", body, confirm: "Save") else { return }
            store.setLockedApps(draft)
            ui.closeSheet(.locked)
            ui.toast(.win, "Locked apps updated", "You're \(store.wallet.tier.title) now.")
            ScreenTime.shared.sync()
        }
    }
}

/// The real iPhone block list, chosen with Apple's Screen Time picker.
struct ScreenTimeAppsSheet: View {
    private var st: ScreenTime { .shared }
    private var ui: UIState { .shared }
    @State private var showPicker = false

    var body: some View {
        SheetFrame("Block apps on this iPhone", tall: true, close: { ui.closeSheet(.screenTimeApps) }) {
            Text("TimeOut uses Apple's Screen Time to actually block the apps you choose when today's phone time runs out. Apple keeps the list private: TimeOut only sees how many you picked.")
                .font(.barlow(13)).foregroundStyle(Theme.text2)
            switch st.status {
            case .approved:
                Note(.green, icon: .check, "Screen Time access is on.")
            case .denied:
                Note(.red, icon: .alert, "Screen Time access is off. Turn it on for TimeOut in Settings › Screen Time, or tap Allow below.")
            case .notDetermined:
                Note(.blue, icon: .info, "Allow Screen Time access so TimeOut can block apps. You approve it with Face ID or your passcode.")
            }
            if st.status == .approved {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Blocked at your limit").foregroundStyle(Theme.text2); Spacer(); Text(st.selectionSummary).font(.barlow(13, 700)) }.font(.barlow(13))
                    if let pending = st.pendingRemovalSummary {
                        Note(.warn, icon: .clock, "\(pending) leave the list at midnight. Removals wait a day so a limit can't be dodged.")
                    }
                    if st.isShieldActive && !st.isOverrideActive { Note(.red, icon: .lock, "Today's limit is reached: your chosen apps are blocked until midnight.") }
                    if st.isOverrideActive, let until = st.overrideUntil { Note(.warn, icon: .unlock, "Emergency unlock until \(Fmt.time(TO.ms(until))).") }
                    if store.data?.settings.enforce != true { Note(.warn, icon: .info, "Enforce app limits is off, so nothing is blocked. Turn it on in Screen time.") }
                }
                .card()
            }
            if let err = st.lastError { FormError(err) }
        } foot: {
            if st.status == .approved {
                Button { st.prepareDraft(); showPicker = true } label: { BtnLabel("Choose apps to block", icon: .lock) }.buttonStyle(.btn(.primary, full: true))
            } else {
                Button("Allow Screen Time") { Task { await st.requestAuthorization() } }.buttonStyle(.btn(.primary, full: true))
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: Binding(get: { st.draft }, set: { st.draft = $0 }))
        .onChange(of: showPicker) { _, open in if !open { st.applyDraft() } }
    }

    private var store: Store { .shared }
}
