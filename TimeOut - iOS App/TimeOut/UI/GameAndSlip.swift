import SwiftUI

enum GameModel {
    static func open(_ id: String) {
        UIState.shared.openPage(.game(id))
        if Feed.game(id)?.eventID != nil { LiveFeed.shared.loadDetails(id) }
    }
}

// MARK: - Game detail (Screen 2)

struct GamePage: View {
    var id: String
    private var live: LiveFeed { .shared }
    private var ui: UIState { .shared }
    private var app: AppModel { .shared }
    @State private var flash = false

    var body: some View {
        let _ = live.version
        let _ = live.detailsVersion
        let _ = app.tick
        return Group {
            if let g = Feed.game(id) {
                let o = Feed.pointValue(id)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            Scoreboard(g: g)
                            GameBanner(g: g, o: o)
                            YourChallengesOnGame(g: g)
                            Markets(g: g, o: o, flash: flash).id("markets")
                            GameStats(g: g)
                            ResearchCard(g: g)
                        }
                        .padding(.top, 4).padding(.horizontal, 16).padding(.bottom, g.state == .live || g.state == .scheduled ? 90 : 40)
                    }
                    .scrollIndicators(.hidden)
                    .overlay(alignment: .bottom) { GameFab(g: g, o: o).padding(.horizontal, 16).padding(.bottom, 14) }
                    .onChange(of: ui.flashMarketsToken) {
                        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo("markets", anchor: .top) }
                        flash = true
                        Task { try? await Task.sleep(for: .milliseconds(1100)); withAnimation { flash = false } }
                        ui.toast(.info, "Choose a challenge", "Select an option to add it to your Daily Commitment.", ms: 2600)
                    }
                }
            } else {
                EmptyState(icon: .clock, title: "Loading the latest score…")
            }
        }
    }
}

struct Scoreboard: View {
    var g: Game
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(Sim.leagues[g.league]?.title ?? g.league)\(g.simulated ? " · Simulated" : "")")
                Spacer()
                Text("Away @ Home")
            }
            .font(.barlow(11.5, 700)).foregroundStyle(Theme.muted)
            .padding(.bottom, 12)
            HStack(alignment: .center, spacing: 6) {
                team(g.away)
                mid.frame(minWidth: 120)
                team(g.home)
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func team(_ t: Team) -> some View {
        VStack(spacing: 6) {
            TeamBadge(team: t, size: 52)
            Text(t.city.isEmpty || t.city == t.name ? t.name : "\(t.city) \(t.name)").font(.barlow(15, 800)).multilineTextAlignment(.center)
            if let r = t.rank { Text("#\(r)").font(.barlow(12)).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var mid: some View {
        if g.state == .live || g.state == .final {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(g.awayScore)").foregroundStyle(g.awayScore < g.homeScore ? Theme.text2 : Theme.text)
                    Text("–").font(.display(30, 900)).foregroundStyle(Theme.muted)
                    Text("\(g.homeScore)").foregroundStyle(g.homeScore < g.awayScore ? Theme.text2 : Theme.text)
                }
                .font(.display(50, 900)).monospacedDigit()
                .contentTransition(.numericText())
                HStack(spacing: 6) {
                    if g.state == .live { LiveTag(); Text(g.clock) } else { Text(g.statusText) }
                }
                .font(.barlow(13, 800)).foregroundStyle(Theme.text2)
            }
        } else if g.state == .postponed || g.state == .canceled {
            Tag(g.state == .canceled ? "Canceled" : "Postponed", .yellow, big: true)
        } else {
            VStack(spacing: 4) {
                Text(Fmt.time(g.start)).font(.display(26, 800))
                Text("\(Fmt.day(g.start)) · in \(Fmt.inTime(g.start - TO.now()))").font(.barlow(13, 800)).foregroundStyle(Theme.text2)
            }
        }
    }
}

struct GameBanner: View {
    var g: Game
    var o: PointValueBoard
    var body: some View {
        switch g.state {
        case .postponed:
            Note(.warn, icon: .alert, markdown: "**This game was postponed.** Related pledges will be returned in full and won't affect your record.")
        case .canceled:
            Note(.warn, icon: .alert, "This game was canceled. Related pledges will be returned.")
        case .final:
            let ot = g.ot.map { $0.label == "10" ? " (10 innings)" : " (OT)" } ?? ""
            Note(.plain, icon: .lock, markdown: "**Final: \(g.away.abbr) \(g.awayScore), \(g.home.abbr) \(g.homeScore)\(ot).** Challenges are closed on this game.")
        default:
            if o.suspended { Note(.plain, icon: .lock, "Challenges are closed for the final moments of this game.") }
        }
    }
}

struct YourChallengesOnGame: View {
    var g: Game
    var body: some View {
        let challenges = (Store.shared.data?.challenges ?? []).filter { $0.picks.contains { $0.gameId == g.id } }
            .sorted { ($0.status == "open" ? 0 : 1) < ($1.status == "open" ? 0 : 1) }
        if !challenges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your pledges on this game").eyebrow()
                ForEach(challenges) { ChallengeCard(challenge: $0, compact: true) }
            }
        }
    }
}

struct Markets: View {
    var g: Game
    var o: PointValueBoard
    var flash: Bool

    var body: some View {
        if g.state == .live || g.state == .scheduled {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Matchup Challenge").font(.barlow(17, 800))
                    Spacer()
                    Text("Targets refresh every 25 seconds").font(.barlow(11.5, 700)).foregroundStyle(Theme.muted)
                }
                ChallengeChoices(g: g, o: o, title: { sel in MatchupText.detailLabel(sel, g) })
                Text("Choose an option to add it to your Daily Commitment.").font(.barlow(11.5)).foregroundStyle(Theme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(flash ? Theme.accent : Theme.stroke, lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(flash ? Theme.accentSoft : .clear, lineWidth: 6).padding(-3))
        }
    }
}

struct GameStats: View {
    var g: Game
    var body: some View {
        if g.eventID != nil {
            let rows = LiveFeed.shared.stats(g)
            if rows.isEmpty {
                Text("ESPN live stats are not available for this game yet.").font(.barlow(13)).foregroundStyle(Theme.text2).card()
            } else {
                VStack(spacing: 14) {
                    HStack {
                        Text(g.state == .live ? "Live stats" : "Final stats").font(.barlow(17, 800))
                        Spacer()
                        HStack(spacing: 6) { TeamBadge(team: g.away, size: 18); Text("vs"); TeamBadge(team: g.home, size: 18) }
                            .font(.barlow(11.5, 700)).foregroundStyle(Theme.muted)
                    }
                    ForEach(rows, id: \.self) { r in
                        HStack(spacing: 10) {
                            Text(r.awayValue).font(.display(18, 800)).monospacedDigit().frame(width: 44, alignment: .leading)
                            Text(r.label).font(.barlow(12, 700)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                            Text(r.homeValue).font(.display(18, 800)).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .card()
            }
        }
    }
}

struct ResearchCard: View {
    var g: Game
    var body: some View {
        let teams = g.eventID != nil ? [g.away, g.home].filter { $0.rank != nil || $0.record != nil } : []
        if !teams.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("ESPN team information").font(.barlow(17, 800))
                ForEach(teams, id: \.abbr) { team in
                    HStack {
                        HStack(spacing: 6) { TeamBadge(team: team, size: 22); Text(team.name).font(.barlow(15, 700)) }
                        Spacer()
                        Text([team.rank.map { "#\($0)" }, team.record].compactMap { $0 }.joined(separator: " · ")).font(.barlow(13)).foregroundStyle(Theme.text2)
                    }
                }
            }
            .card()
        }
    }
}

/// Floating button: jumps to the challenge targets, or back to the commitment once there's a pick on it.
struct GameFab: View {
    var g: Game
    var o: PointValueBoard
    private var slip: Slip { .shared }
    var body: some View {
        if g.state == .live || g.state == .scheduled {
            let n = slip.picks.count
            Group {
                if n > 0 {
                    Button { slip.open() } label: { BtnLabel("Open Daily Commitment · \(n) choice\(n == 1 ? "" : "s")", icon: .target) }
                        .buttonStyle(.btn(.primary, full: true))
                } else {
                    Button { UIState.shared.flashMarkets() } label: {
                        BtnLabel(o.suspended ? "Challenges are closed" : "Choose a challenge", icon: o.suspended ? .lock : .target)
                    }
                    .buttonStyle(.btn(.primary, full: true))
                    .disabled(o.suspended)
                }
            }
            .shadow(color: .black.opacity(0.55), radius: 17, y: 14)
        }
    }
}

// MARK: - Daily commitment (Screen 3)

struct SlipSheet: View {
    private var slip: Slip { .shared }
    private var live: LiveFeed { .shared }
    private var net: Net { .shared }
    private var ui: UIState { .shared }

    var body: some View {
        let _ = live.version
        let _ = Races.shared.version
        return SheetFrame(slip.picks.count > 1 ? "\(slip.picks.count)-Pick Combo Goal" : "Single Matchup Pledge", close: { ui.closeSheet(.slip) }) {
            SlipBody()
        } foot: {
            SlipFoot()
        }
        .onAppear { slip.preparePledge() }
    }
}

struct SlipBody: View {
    private var slip: Slip { .shared }
    private var store: Store { .shared }
    @FocusState private var pledgeFocused: Bool

    var body: some View {
        let wl = store.wallet
        VStack(alignment: .leading, spacing: 8) { SlipPicks() }
        if wl.lockedOut || wl.balance <= 0 {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) { Icon(.lock, 14); Text("OUT OF PLEDGE MINUTES") }.font(.barlow(11.5, 700)).tracking(0.7).foregroundStyle(Theme.loss)
                Text("New challenges are blocked until midnight.").font(.barlow(15, 700)).padding(.top, 6)
                Countdown(target: TO.nextMidnight()).font(.display(36, 800)).padding(.top, 4)
                Text("Your available pledge minutes reset at midnight.").font(.barlow(13)).foregroundStyle(Theme.text2)
            }
            .card(border: Theme.loss.opacity(0.4))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Minutes to commit").font(.barlow(13, 700)).foregroundStyle(Theme.text2)
                HStack(spacing: 8) {
                    stepButton(.minus, -1).accessibilityLabel("One minute less")
                    ZStack(alignment: .trailing) {
                        TextField("", text: Binding(get: { slip.pledgeMinutes ?? "" }, set: { _ = slip.typed($0) }))
                            .focused($pledgeFocused)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.display(30, 900)).monospacedDigit()
                            .padding(.horizontal, 36)
                            .frame(height: 52)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(pledgeFocused ? Theme.accent : Theme.stroke, lineWidth: 1))
                            .accessibilityLabel("Minutes to commit")
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { pledgeFocused = false }.font(.barlow(16, 700)).foregroundStyle(Theme.accent)
                                }
                            }
                        Text("min").font(.barlow(14, 700)).foregroundStyle(Theme.text2).padding(.trailing, 14).allowsHitTesting(false)
                    }
                    stepButton(.plus, 1).accessibilityLabel("One minute more")
                }
                HStack(spacing: 6) {
                    ForEach([15, 30, 45], id: \.self) { v in
                        quick("\(v)m", on: slip.pledgeMinutes == "\(v)", disabled: v > wl.balance) { slip.quick(v) }
                    }
                    quick("Max Available", on: false, disabled: false) { slip.quick(wl.balance) }
                }
            }
            Note(.blue, icon: .info, markdown: "You're committing **tomorrow's phone time**. Minutes come from today's \(wl.balance) available minutes; successful challenges add to tomorrow's allowance.")
            if wl.boostsLeft > 0 {
                PerkRow(icon: .bolt, iconBg: Theme.blueSoft, iconFg: Theme.blue, title: "Allowance boost",
                        sub: "+10% earned minutes · \(wl.boostsLeft) left today (\(wl.tier.title) perk)", on: slip.boost) { slip.boost.toggle() }
            }
            if slip.picks.count > 1 && wl.insuranceLeft > 0 {
                PerkRow(icon: .shield, iconBg: Theme.purple.opacity(0.14), iconFg: Theme.purple, title: "Miss-one protection",
                        sub: "Miss one choice and recover your committed minutes · 1 per week", on: slip.insure) { slip.insure.toggle() }
            }
        }
        VStack(alignment: .leading, spacing: 8) { SlipSummary() }
    }

    private func stepButton(_ icon: IconName, _ d: Int) -> some View {
        Button { slip.step(d) } label: {
            Icon(icon, 20).foregroundStyle(Theme.text).frame(width: 48, height: 52)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.press)
    }

    private func quick(_ label: String, on: Bool, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.barlow(13.5, 800)).foregroundStyle(on ? Theme.accent : Theme.text)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Theme.accent : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.press)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

struct PerkRow: View {
    var icon: IconName
    var iconBg: Color
    var iconFg: Color
    var title: String
    var sub: String
    var on: Bool
    var toggle: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            LrIcon(icon: icon, bg: iconBg, fg: iconFg)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.barlow(15, 700))
                Text(sub).font(.barlow(11.5)).foregroundStyle(Theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SwitchView(isOn: on, action: toggle)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

struct SlipPicks: View {
    private var slip: Slip { .shared }
    var body: some View {
        let st = slip.status()
        if st.closed {
            Note(.red, icon: .alert, "A choice is no longer available (the game ended, was postponed, or challenges closed). Remove it to continue.")
        } else if st.changed {
            Note(.warn, icon: .alert, markdown: "A challenge target changed while your commitment was open. Review it, then accept the update to continue.")
        }
        ForEach(Array(slip.picks.enumerated()), id: \.element.selId) { i, pick in
            SlipPickRow(pick: pick, state: st.states.indices.contains(i) ? st.states[i] : Slip.PickState(sel: nil, closed: true, changed: false))
        }
        if slip.picks.count > 1 && !st.closed {
            HStack {
                Text("\(slip.picks.count)-pick Combo Goal · all choices count").font(.barlow(13, 700)).foregroundStyle(Theme.text2)
                Spacer()
                Text("\(String(format: "%.2f", slip.decimal))x").font(.display(19, 800)).foregroundStyle(Theme.accent)
            }
        }
    }
}

struct SlipPickRow: View {
    var pick: SlipPick
    var state: Slip.PickState

    var body: some View {
        let sel = state.sel
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title(sel)).font(.barlow(15.5, 700))
                Text(sub(sel)).font(.barlow(13)).foregroundStyle(Theme.text2)
                liveLine.padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if state.closed {
                Tag("Closed", .red)
            } else if state.changed, let sel {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(PointValueMath.multiplierText(pick.price)).font(.barlow(13)).strikethrough().foregroundStyle(Theme.muted)
                        Text(PointValueMath.multiplierText(sel.price)).font(.display(18, 900)).foregroundStyle(Theme.warn)
                    }
                    if sel.line != pick.line { Text("Challenge target changed").font(.barlow(11.5, 700)).foregroundStyle(Theme.warn) }
                }
            } else {
                Text(PointValueMath.multiplierText(pick.price)).font(.display(18, 900)).monospacedDigit().foregroundStyle(Theme.accent).multilineTextAlignment(.trailing)
            }
            Button { Slip.shared.remove(pick.selId) } label: { Icon(.x, 16).foregroundStyle(Theme.text).frame(width: 30, height: 30) }
                .buttonStyle(.press).padding(.top, -4).padding(.trailing, -6)
                .accessibilityLabel("Remove pick")
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(state.closed ? Theme.loss.opacity(0.5) : state.changed ? Theme.warn.opacity(0.6) : Theme.stroke, lineWidth: 1))
        .opacity(state.closed ? 0.85 : 1)
    }

    private func title(_ sel: Selection?) -> String {
        if pick.ref.hasPrefix("race-") { return sel.map { Races.shared.horse($0.horseId ?? Int($0.side)).name } ?? "Virtual race pick" }
        guard var s = sel else { return "" }
        if !state.changed { s.line = pick.line }
        return Sim.selectionLabel(s, Feed.game(pick.ref))
    }

    private func sub(_ sel: Selection?) -> String {
        if pick.ref.hasPrefix("race-") { return "Virtual Racing · Race #\(pick.ref.replacingOccurrences(of: "race-", with: ""))" }
        let g = Feed.game(pick.ref)
        return "\(g?.away.name ?? "") @ \(g?.home.name ?? "")"
    }

    @ViewBuilder private var liveLine: some View {
        if pick.ref.hasPrefix("race-") {
            let race = Races.shared.get(pick.ref)
            if race?.status == "running" { HStack(spacing: 6) { LiveTag(); Text("Race in progress").font(.barlow(11.5, 700)).foregroundStyle(Theme.text2) } }
            else if race?.status == "final" { Text("Race finished").font(.barlow(11.5, 700)).foregroundStyle(Theme.text2) }
        } else if let g = Feed.game(pick.ref) {
            switch g.state {
            case .live: HStack(spacing: 6) { LiveTag(); Text("\(g.away.abbr) \(g.awayScore) – \(g.home.abbr) \(g.homeScore) · \(g.clock)").font(.barlow(11.5, 700)).foregroundStyle(Theme.text2) }
            case .postponed: Text("Postponed").font(.barlow(11.5, 700)).foregroundStyle(Theme.warn)
            case .final: Text("Game over · \(g.statusText)").font(.barlow(11.5, 700)).foregroundStyle(Theme.text2)
            default: EmptyView()
            }
        }
    }
}

struct SlipSummary: View {
    private var slip: Slip { .shared }
    var body: some View {
        let n = slip.numbers()
        let wl = n.wl
        if !(wl.lockedOut || wl.balance <= 0) {
            let pledgeMinutes = n.pledgeMinutes ?? 0
            if slip.capped {
                Note(.red, icon: .alert, markdown: "**Not enough screen time.** You have \(wl.balance) min available today.")
            } else if let s = n.pledgeMinutes, s > wl.balance {
                Note(.red, icon: .alert, markdown: "**Not enough screen time.** You have \(wl.balance) min available today.")
            } else if let s = slip.pledgeMinutes, !s.isEmpty, (n.pledgeMinutes == nil || n.pledgeMinutes! < 1) {
                Note(.red, icon: .alert, "Enter a pledge of at least 1 minute.")
            }
            VStack(spacing: 6) {
                summaryRow("Committed Today", "\(n.valid ? pledgeMinutes : 0) min", Theme.text)
                summaryRow("Combined Target", "\(String(format: "%.2f", n.targetMultiplier))x", Theme.accent)
                summaryRow("Tomorrow's Projected Allowance", "\(wl.tomorrowLimit + (n.valid ? n.winnings : 0)) min", Theme.accent)
                if n.capApplied { Tag("Max Daily Cap Applied (\(Rules.maxAllowedMinutes)m max)", .yellow).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(12)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 8) {
                outcome("Earned Minutes", "+\(n.valid ? n.winnings : 0) min", "added to tomorrow's phone time", Theme.accent)
                outcome("If a challenge is missed", "−\(n.valid ? pledgeMinutes : 0) min", "from tomorrow's phone time", Theme.loss)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Available today after pledge").foregroundStyle(Theme.text2)
                Spacer()
                Text("\(n.valid ? max(wl.balance - pledgeMinutes, 0) : wl.balance) of \(wl.balance) min").font(.barlow(13, 700)).monospacedDigit()
            }
            .font(.barlow(13))
            if n.mult > 1 {
                HStack {
                    Text("Earned-minutes multiplier\(slip.boost ? " (streak + boost)" : " (clean streak)")").foregroundStyle(Theme.text2)
                    Spacer()
                    Text(Fmt.mult((n.mult * 1000).rounded() / 1000)).font(.barlow(13, 700)).foregroundStyle(Theme.accent)
                }
                .font(.barlow(13))
            }
            if let err = slip.error { FormError(err) }
        }
    }

    private func summaryRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.text2)
            Spacer()
            Text(value).font(.barlow(13, 700)).monospacedDigit().foregroundStyle(color)
        }
        .font(.barlow(13))
    }

    private func outcome(_ head: String, _ value: String, _ foot: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(head).font(.barlow(12, 700)).foregroundStyle(Theme.text2)
            Text(value).font(.display(26, 900)).monospacedDigit().foregroundStyle(color)
            Text(foot).font(.barlow(12, 700)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

struct SlipFoot: View {
    private var slip: Slip { .shared }
    private var net: Net { .shared }

    var body: some View {
        let st = slip.status()
        if !net.online {
            Note(.red, icon: .wifiOff, markdown: "**No internet connection.** New pledges pause until you're back online.")
            Button {} label: { BtnLabel("Waiting for connection", icon: .wifiOff) }.buttonStyle(.btn(full: true)).disabled(true)
        } else if st.closed {
            Button("Remove unavailable picks to continue") {}.buttonStyle(.btn(.primary, full: true)).disabled(true)
        } else if st.changed {
            Button("Accept updated target") { slip.acceptNewPointValue() }.buttonStyle(.btn(.warn, full: true))
        } else {
            let n = slip.numbers()
            if n.wl.lockedOut || n.wl.balance <= 0 {
                Button {} label: { BtnLabel("New pledges resume at midnight", icon: .lock) }.buttonStyle(.btn(full: true)).disabled(true)
            } else {
                Button(slip.picks.count > 1 ? "Lock In \(slip.picks.count)-Pick Combo Goal (\(n.pledgeMinutes ?? 0)m)" : "Confirm \(n.pledgeMinutes ?? 0)m Pledge") { slip.place() }
                    .buttonStyle(.btn(.primary, full: true)).disabled(!n.valid)
                if slip.picks.count < Rules.maxMatchupPicks {
                    Button { slip.addMore() } label: {
                        BtnLabel("Add another matchup choice", icon: .plus, iconSize: 16)
                    }
                    .buttonStyle(.btn(.quiet, .sm, full: true))
                }
            }
        }
    }
}

// MARK: - Combo builder

struct ComboPage: View {
    private var slip: Slip { .shared }
    private var live: LiveFeed { .shared }
    private var home: HomeModel { .shared }

    var body: some View {
        let _ = live.version
        let games = home.boardGames().filter { $0.state == .live || $0.state == .scheduled }
        let n = slip.picks.count
        let full = n >= Rules.maxMatchupPicks
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Note(.blue, icon: .info, markdown: "Pick up to \(Rules.maxMatchupPicks) sides from **different games**. Every pick has to win for the Combo Goal to pay.\(n > 0 ? " Games already on your commitment are highlighted." : "")")
                DayBar(inset: false)
                if full { Note(.warn, icon: .alert, "Your Combo Goal is full. Remove a pick on the commitment to add a different one.") }
                VStack(spacing: 14) {
                    let leagues = Sim.leagueOrder.filter { l in games.contains { $0.league == l } }
                    if leagues.isEmpty {
                        EmptyState(icon: .target, iconSize: 36, title: "No games open for challenges", text: "Check back when the next games start.")
                    }
                    ForEach(leagues, id: \.self) { l in
                        let lg = games.filter { $0.league == l }
                        LeagueHead(league: l, count: "\(lg.count) games", inset: false)
                        ForEach(lg) { GameCard(game: $0) }
                    }
                }
            }
            .padding(.top, 4).padding(.horizontal, 16).padding(.bottom, 90)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            Button { UIState.shared.closePage(.combo) } label: {
                HStack(spacing: 8) {
                    CountPill(n: n, bg: Theme.accentInk, fg: Theme.accent)
                    Text(n > 1 ? "Review \(n)-pick Combo Goal" : "Review challenge commitment")
                    if n > 1 { Spacer(); Text("\(String(format: "%.2f", slip.decimal))x").font(.display(19, 800)) }
                }
            }
            .buttonStyle(.btn(.primary, full: true))
            .disabled(n == 0)
            .shadow(color: .black.opacity(0.55), radius: 17, y: 14)
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }
}
