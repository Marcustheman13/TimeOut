import FamilyControls
import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false
    @State private var confirmOverride = false
    @State private var overrideError: String?
    @State private var confirmReset = false
    @State private var editingSports = false

    var body: some View {
        @Bindable var screenTime = model.screenTime
        let book = model.book

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    todayCard
                    StatusCard()
                    sportsCard
                    screenTimeCard
                    if screenTime.isShieldActive || screenTime.isOverrideActive {
                        overrideCard
                    }
                    howItWorks
                    #if DEBUG
                    debugCard
                    Button("Reset all data", role: .destructive) { confirmReset = true }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 8)
                    #endif
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Account")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(isPresented: $editingSports) {
                SportsPickerView()
                    .presentationBackground(Theme.background)
            }
            .familyActivityPicker(isPresented: $showPicker, selection: $screenTime.draft)
            .onChange(of: showPicker) { _, showing in
                // Commitment lock rules are applied when the picker closes.
                if !showing {
                    screenTime.applyDraft()
                    model.syncScreenTime()
                }
            }
            .onAppear { screenTime.refreshStatus() }
            .alert("Emergency unlock?", isPresented: $confirmOverride) {
                Button("Unlock \(BetBook.overrideMinutes) min", role: .destructive) {
                    overrideError = model.emergencyUnlock()
                }
                Button("Stay locked", role: .cancel) {}
            } message: {
                Text("Unlocks your limited apps for \(BetBook.overrideMinutes) minutes. It costs \(BetBook.overridePenalty) minutes of tomorrow's screen time. \(BetBook.maxOverridesPerDay - book.overridesUsedToday) left today.")
            }
            #if DEBUG
            .alert("Reset all data?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { model.book.resetAll(); model.syncScreenTime() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears every bet and resets your balance to \(BetBook.dailyAllowance) minutes. Debug builds only.")
            }
            #endif
        }
    }

    // MARK: Today

    /// Phone time left today, front and center, with betting balance and tomorrow's limit underneath.
    private var todayCard: some View {
        let book = model.book
        let screenTime = model.screenTime
        let limit = book.todayLimit
        let used = screenTime.isShieldActive ? limit : min(screenTime.usedToday, limit)
        let left = max(limit - used, 0)
        let tracking = screenTime.isEnforcing
        let fraction = limit > 0 ? Double(left) / Double(limit) : 0
        let ringColor = !tracking ? Theme.textMuted : left == 0 ? Theme.loss : left <= 10 ? Theme.warning : Theme.accent
        let tomorrowDelta = book.tomorrowLimit - BetBook.dailyAllowance

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Theme.raised, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: tracking ? fraction : 1)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.snappy, value: fraction)
                    VStack(spacing: -2) {
                        Text("\(tracking ? left : limit)")
                            .font(.display(36, weight: .black))
                            .contentTransition(.numericText())
                        Text("MIN")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 6) {
                    Text(tracking ? "PHONE TIME LEFT TODAY" : "PHONE LIMIT TODAY")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.textSecondary)
                    if tracking {
                        Text(left == 0 ? "Locked until midnight" : "\(left) of \(limit) min left")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(left == 0 ? Theme.loss : .white)
                        Text("\(used) min used on limited apps")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("\(limit) min")
                            .font(.system(size: 20, weight: .heavy))
                        Text("Connect Screen Time below to track and enforce it.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.warning)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill")
                        Text("Resets in")
                        MidnightCountdown(font: .system(size: 12, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                miniStat("BETTING BALANCE", book.isLockedOut ? "Locked" : "\(book.balance) min",
                         detail: "to bet today", color: book.isLockedOut ? Theme.loss : Theme.accent)
                miniStat("TOMORROW'S LIMIT", "\(book.tomorrowLimit) min",
                         detail: tomorrowDelta == 0 ? "no change yet" : "\(tomorrowDelta.signedMinutes) from bets",
                         color: tomorrowDelta > 0 ? Theme.win : tomorrowDelta < 0 ? Theme.loss : .white)
            }

            if tracking {
                Text("Usage updates every 5 minutes, then every minute near your limit.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .card(padding: 16)
    }

    private func miniStat(_ title: String, _ value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.textMuted)
            Text(value).font(.display(24, weight: .black)).foregroundStyle(color)
            Text(detail).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.raised, in: .rect(cornerRadius: 12))
    }

    // MARK: Sports

    private var sportsCard: some View {
        Button {
            editingSports = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your sports").font(.system(size: 16, weight: .heavy))
                    Text(model.sports.ordered.map(\.title).joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .card()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Screen Time setup

    private var screenTimeCard: some View {
        let screenTime = model.screenTime
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Screen Time enforcement").font(.system(size: 16, weight: .heavy))
                Spacer()
                Text(screenTime.isEnforcing ? "ON" : "OFF")
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(screenTime.isEnforcing ? .black : .white)
                    .background(screenTime.isEnforcing ? Theme.accent : Theme.raised, in: .capsule)
            }

            Text("When you hit your daily limit, the apps you pick below get locked until midnight.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            if screenTime.isEnforcing {
                commitmentLock
            }

            switch screenTime.status {
            case .approved:
                Button {
                    screenTime.prepareDraft()
                    showPicker = true
                } label: {
                    HStack {
                        Label("Apps to limit", systemImage: "apps.iphone")
                        Spacer()
                        Text(screenTime.selectionSummary).foregroundStyle(Theme.textSecondary)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textMuted)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(12)
                    .background(Theme.raised, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                if let removal = screenTime.pendingRemovalSummary {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Removing \(removal) at midnight")
                                .font(.system(size: 13, weight: .bold))
                            Text("They stay locked for the rest of today.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Undo") {
                            screenTime.cancelPendingRemoval()
                        }
                        .font(.system(size: 13, weight: .bold))
                    }
                    .padding(12)
                    .background(Theme.warning.opacity(0.1), in: .rect(cornerRadius: 12))
                }
                if !screenTime.hasSelection {
                    Text("Pick at least one app or category to turn on limits.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                }
            case .notDetermined, .denied:
                Button {
                    Task {
                        await screenTime.requestAuthorization()
                        model.syncScreenTime()
                    }
                } label: {
                    Text(screenTime.status == .denied ? "Screen Time access denied. Try again" : "Connect Screen Time")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.accent, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            if let error = screenTime.lastError {
                Text(error)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.loss)
            }
        }
        .card()
    }

    private var commitmentLock: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Commitment lock is on")
                    .font(.system(size: 14, weight: .heavy))
                Text("Add apps anytime. Removing apps waits until midnight. Turning off Screen Time access forfeits the day's betting.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    // MARK: Emergency override

    private var overrideCard: some View {
        let screenTime = model.screenTime
        let book = model.book
        return VStack(alignment: .leading, spacing: 10) {
            Label(screenTime.isOverrideActive ? "Emergency unlock active" : "Limit reached. Apps locked", systemImage: screenTime.isOverrideActive ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(screenTime.isOverrideActive ? Theme.warning : Theme.loss)

            if let until = screenTime.overrideUntil, screenTime.isOverrideActive {
                Text("Apps lock again at \(until.formatted(date: .omitted, time: .shortened)).")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Need your phone for something important? An emergency unlock gives you \(BetBook.overrideMinutes) minutes but costs \(BetBook.overridePenalty) minutes of tomorrow's limit.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    confirmOverride = true
                } label: {
                    Text(book.canOverride ? "Emergency Unlock (\(BetBook.maxOverridesPerDay - book.overridesUsedToday) left)" : "No unlocks left today")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(book.canOverride ? Theme.loss : Theme.raised, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!book.canOverride)
            }
            if let overrideError {
                Text(overrideError).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.loss)
            }
        }
        .card()
    }

    // MARK: Debug

    #if DEBUG
    private var debugCard: some View {
        let book = model.book
        return VStack(alignment: .leading, spacing: 10) {
            Label("Testing (debug builds only)", systemImage: "wrench.and.screwdriver.fill")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.warning)
            Text("Temporarily set today's phone limit so you can watch the lock kick in without waiting an hour.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach([1, 2, 5], id: \.self) { minutes in
                    debugChip("\(minutes) min", selected: book.debugTodayLimit == minutes) {
                        book.debugTodayLimit = minutes
                        model.syncScreenTime()
                    }
                }
                debugChip("Real", selected: book.debugTodayLimit == nil) {
                    book.debugTodayLimit = nil
                    model.syncScreenTime()
                }
            }
        }
        .card()
    }

    private func debugChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? .black : .white)
                .background(selected ? Theme.warning : Theme.raised, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: Explainer

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How \(Theme.brand) works").font(.system(size: 16, weight: .heavy))
            step("hourglass", "You get \(BetBook.dailyAllowance) minutes to bet every day. It resets at midnight.")
            step("sportscourt.fill", "Bet those minutes on real games, or on Sim Hoops when nothing's on.")
            step("arrow.up.arrow.down", "Wins add minutes to tomorrow's phone limit. Losses take them away.")
            step("person.2.fill", "Bet friends for dishes, coffee or bragging rights instead.")
            step("dollarsign.circle", "No real money, ever. Odds are fair, with no house edge.")
        }
        .card()
    }

    private func step(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
