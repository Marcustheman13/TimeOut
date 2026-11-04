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
                        ui.toast(.info, "Pick a price", "Tap any point value and your challenge slip opens with it.", ms: 2600)
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
            Note(.warn, icon: .alert, markdown: "**This game was postponed.** All challenges on it are void, and every pledge has been returned in full. It no longer counts toward anyone's record.")
        case .canceled:
            Note(.warn, icon: .alert, "This game was canceled. Challenges on it will be voided.")
        case .final:
            let ot = g.ot.map { $0.label == "10" ? " (10 innings)" : " (OT)" } ?? ""
            Note(.plain, icon: .lock, markdown: "**Final: \(g.away.abbr) \(g.awayScore), \(g.home.abbr) \(g.homeScore)\(ot).** This pick is closed on this game.")
        default:
            if o.suspended { Note(.plain, icon: .lock, "This pick is closed for the final moments of this game.") }
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
                Text("Your challenges on this game").eyebrow()
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
            let Sp = Sim.sports[g.sport]!
            let name: (String) -> String = { side in side == "home" ? g.home.name : side == "away" ? g.away.name : "Draw" }
            if o.winner.isEmpty && o.margin.isEmpty && o.total.isEmpty && false {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Pick a side").font(.barlow(17, 800))
                        Spacer()
                        Text("ESPN point values refresh every 25 seconds").font(.barlow(11.5, 700)).foregroundStyle(Theme.muted)
                    }
                    if o.winner.isEmpty {
                        market("Winner · who wins") { Tag("Winner N/A") }
                    } else {
                        block("Winner · who wins", o.winner) { name($0.side) }
                        if g.sport == "soccer" && !o.winner.contains(where: { $0.side == "draw" }) { market("Draw") { Tag("N/A") } }
                    }
                    if !o.margin.isEmpty { block("\(Sp.marginLabel) · win by more than the number", o.margin) { name($0.side) } }
                    if !o.total.isEmpty { block("Total \(Sp.unit) · both teams combined", o.total) { $0.side == "higher" ? "Above" : "Below" } }
                    Text("ESPN prices. Tap a price to add it to your challenge slip.").font(.barlow(11.5)).foregroundStyle(Theme.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(flash ? Theme.accent : Theme.stroke, lineWidth: 1))
                .shadow(color: flash ? Theme.accentSoft : .clear, radius: 0, x: 0, y: 0)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(flash ? Theme.accentSoft : .clear, lineWidth: 6).padding(-3))
            }
        }
    }

    private func market<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.barlow(13, 800)).tracking(0.78).foregroundStyle(Theme.text2)
            content()
        }
    }

    private func block(_ title: String, _ sels: [Selection], label: @escaping (Selection) -> String) -> some View {
        market(title) {
            // `repeat(auto-fit, minmax(90px, 1fr))`: two or three options share the row equally.
            HStack(spacing: 8) {
                ForEach(sels, id: \.id) { s in
                    PointValueButton(sel: s, suspended: o.suspended, move: o.move[s.id], big: true, label: label(s))
                }
            }
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

/// Floating button: jumps to the point values, or back to the slip once there's a pick on it.
struct GameFab: View {
    var g: Game
    var o: PointValueBoard
    private var slip: Slip { .shared }
    var body: some View {
        if g.state == .live || g.state == .scheduled {
            let n = slip.picks.count
            Group {
                if n > 0 {
                    Button { slip.open() } label: { BtnLabel("Open challenge slip · \(n) pick\(n == 1 ? "" : "s")", icon: .ticket) }
                        .buttonStyle(.btn(.primary, full: true))
                } else {
                    Button { UIState.shared.flashMarkets() } label: {
                        BtnLabel(o.suspended ? "This pick is closed on this game" : "Make a challenge", icon: o.suspended ? .lock : .ticket)
                    }
                    .buttonStyle(.btn(.primary, full: true))
                    .disabled(o.suspended)
                }
            }
            .shadow(color: .black.opacity(0.55), radius: 17, y: 14)
        }
    }
}

// MARK: - Challenge slip (Screen 3)

struct SlipSheet: View {
    private var slip: Slip { .shared }
    private var live: LiveFeed { .shared }
    private var net: Net { .shared }
    private var ui: UIState { .shared }

    var body: some View {
        let _ = live.version
        let _ = Races.shared.version
        return SheetFrame(slip.picks.count > 1 ? "Combo · \(slip.picks.count) picks" : "Challenge Slip", close: { ui.closeSheet(.slip) }) {
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
                HStack(spacing: 6) { Icon(.lock, 14); Text("OUT OF CHALLENGING MINUTES") }.font(.barlow(11.5, 700)).tracking(0.7).foregroundStyle(Theme.loss)
                Text("New challenges are blocked until midnight.").font(.barlow(15, 700)).padding(.top, 6)
                Countdown(target: TO.nextMidnight()).font(.display(36, 800)).padding(.top, 4)
                Text("Your pledge balance resets at midnight.").font(.barlow(13)).foregroundStyle(Theme.text2)
            }
            .card(border: Theme.loss.opacity(0.4))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Minutes to pledge").font(.barlow(13, 700)).foregroundStyle(Theme.text2)
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
                            .accessibilityLabel("Minutes to pledge")
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
                    ForEach([5, 10, 15, 30], id: \.self) { v in
                        quick("\(v)", on: slip.pledgeMinutes == "\(v)", disabled: v > wl.balance) { slip.quick(v) }
                    }
                    quick("Max", on: false, disabled: false) { slip.quick(wl.balance) }
                }
            }
            Note(.blue, icon: .info, markdown: "You're pledging **tomorrow's phone time**. Pledges come out of today's \(wl.balance) challenge minutes; wins add to tomorrow's limit and losses take away from it.")
            if wl.boostsLeft > 0 {
                PerkRow(icon: .bolt, iconBg: Theme.blueSoft, iconFg: Theme.blue, title: "Use a point-value boost",
                        sub: "+10% winnings · \(wl.boostsLeft) left today (\(wl.tier.title) perk)", on: slip.boost) { slip.boost.toggle() }
            }
            if slip.picks.count > 1 && wl.insuranceLeft > 0 {
                PerkRow(icon: .shield, iconBg: Theme.purple.opacity(0.14), iconFg: Theme.purple, title: "Combo protection",
                        sub: "Miss by one pick and get your pledge back · 1 per week", on: slip.insure) { slip.insure.toggle() }
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
            Note(.red, icon: .alert, "A pick is no longer available (the game ended, was postponed, or the pick closed). Remove it to continue.")
        } else if st.changed {
            Note(.warn, icon: .alert, markdown: "The point values changed while your slip was open. Check the new point value, then tap **Accept new point value** to continue.")
        }
        ForEach(Array(slip.picks.enumerated()), id: \.element.selId) { i, pick in
            SlipPickRow(pick: pick, state: st.states.indices.contains(i) ? st.states[i] : Slip.PickState(sel: nil, closed: true, changed: false))
        }
        if slip.picks.count > 1 && !st.closed {
            HStack {
                Text("\(slip.picks.count)-pick combo · every pick must win").font(.barlow(13, 700)).foregroundStyle(Theme.text2)
                Spacer()
                Text(PointValueMath.fmt(PointValueMath.fromDecimal(slip.decimal))).font(.display(19, 800)).foregroundStyle(Theme.accent)
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
                        Text(PointValueMath.fmt(pick.price)).font(.barlow(14)).strikethrough().foregroundStyle(Theme.muted)
                        Text(PointValueMath.fmt(sel.price)).font(.display(20, 900)).foregroundStyle(Theme.warn)
                    }
                    if sel.line != pick.line { Text("Line moved").font(.barlow(11.5, 700)).foregroundStyle(Theme.warn) }
                }
            } else {
                Text(PointValueMath.fmt(pick.price)).font(.display(20, 900)).monospacedDigit().foregroundStyle(Theme.accent)
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
                Note(.red, icon: .alert, markdown: "**Not enough screentime.** You have \(wl.balance) min left to challenge today, so that's the most you can pledge.")
            } else if let s = n.pledgeMinutes, s > wl.balance {
                Note(.red, icon: .alert, markdown: "**Not enough screentime.** You have \(wl.balance) min left to challenge today.")
            } else if let s = slip.pledgeMinutes, !s.isEmpty, (n.pledgeMinutes == nil || n.pledgeMinutes! < 1) {
                Note(.red, icon: .alert, "Enter a pledge of at least 1 minute.")
            }
            HStack(spacing: 8) {
                outcome("If you win", "+\(n.valid ? n.winnings : 0) min", "added to tomorrow's phone time", Theme.accent)
                outcome("If you lose", "−\(n.valid ? pledgeMinutes : 0) min", "taken from tomorrow's phone time", Theme.loss)
            }
            HStack {
                Text("Challenging balance after this challenge").foregroundStyle(Theme.text2)
                Spacer()
                Text("\(n.valid ? max(wl.balance - pledgeMinutes, 0) : wl.balance) of \(wl.balance) min").font(.barlow(13, 700)).monospacedDigit()
            }
            .font(.barlow(13))
            if n.mult > 1 {
                HStack {
                    Text("Winnings multiplier\(slip.boost ? " (streak + boost)" : " (clean streak)")").foregroundStyle(Theme.text2)
                    Spacer()
                    Text(Fmt.mult((n.mult * 1000).rounded() / 1000)).font(.barlow(13, 700)).foregroundStyle(Theme.accent)
                }
                .font(.barlow(13))
            }
            if let err = slip.error { FormError(err) }
        }
    }

    private func outcome(_ head: String, _ value: String, _ foot: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(head).font(.barlow(12, 700)).foregroundStyle(Theme.text2)
            Text(value).font(.display(26, 900)).monospacedDigit().foregroundStyle(color)
            Text(foot).font(.barlow(12, 700)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Note(.red, icon: .wifiOff, markdown: "**No internet connection.** Challenging is paused until you're back online, because point value can't update.")
            Button {} label: { BtnLabel("Waiting for connection", icon: .wifiOff) }.buttonStyle(.btn(full: true)).disabled(true)
        } else if st.closed {
            Button("Remove unavailable picks to continue") {}.buttonStyle(.btn(.primary, full: true)).disabled(true)
        } else if st.changed {
            Button("Accept new point value") { slip.acceptNewPointValue() }.buttonStyle(.btn(.warn, full: true))
        } else {
            let n = slip.numbers()
            if n.wl.lockedOut || n.wl.balance <= 0 {
                Button {} label: { BtnLabel("Challenging locked until midnight", icon: .lock) }.buttonStyle(.btn(full: true)).disabled(true)
            } else {
                Button(n.valid ? "Place challenge · \(n.pledgeMinutes!) min" : "Place challenge") { slip.place() }
                    .buttonStyle(.btn(.primary, full: true)).disabled(!n.valid)
                if slip.picks.count < Rules.maxPicks {
                    Button { slip.addMore() } label: {
                        BtnLabel(slip.comboMode ? "Add another pick" : "Add another pick for a combo", icon: .plus, iconSize: 16)
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
        let full = n >= Rules.maxPicks
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Note(.blue, icon: .info, markdown: "Pick up to \(Rules.maxPicks) sides from **different games**. Every pick has to win for the combo to pay.\(n > 0 ? " Games already on your slip are highlighted." : "")")
                DayBar(inset: false)
                if full { Note(.warn, icon: .alert, "Your combo is full. Remove a pick on the slip to add a different one.") }
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
                    Text(n > 1 ? "Review \(n)-pick combo" : "Review challenge slip")
                    if n > 1 { Spacer(); Text(PointValueMath.fmt(PointValueMath.fromDecimal(slip.decimal))).font(.display(19, 800)) }
                }
            }
            .buttonStyle(.btn(.primary, full: true))
            .disabled(n == 0)
            .shadow(color: .black.opacity(0.55), radius: 17, y: 14)
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }
}
