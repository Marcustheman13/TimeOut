import SwiftUI

/// Virtual Racing: an animated 5-horse race. Tap a price to bet with the regular slip, or start a race to watch.
struct RacesView: View {
    private var races: Races { .shared }

    var body: some View {
        let _ = races.version
        let race = races.current
        let latest = races.latest
        return ScrollView {
            VStack(spacing: 14) {
                PageHead(title: "Virtual Racing", text: "Pick a winner and stake screen-time minutes using your regular bet slip.")
                    .padding(.bottom, -6)
                TimelineView(.animation(paused: race.status != "running")) { ctx in
                    let now = TO.ms(ctx.date)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 12) {
                            HStack(alignment: .top, spacing: 5) {
                                Tag(Races.statusText(race), race.status == "running" ? .red : .green)
                                Text("· 1,200m Cyber Turf Classic #\(race.number)").font(.barlow(12, 700)).foregroundStyle(Theme.text2)
                                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                            }
                            Spacer(minLength: 0)
                            Text(race.status == "running" ? "\(max(0, Int(ceil(((race.finishAt ?? now) - now) / 1000)))) sec" : "12 sec")
                                .font(.display(17, 900)).foregroundStyle(Theme.accent)
                        }
                        RaceTrack(race: race, now: now)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                            .accessibilityLabel("Animated virtual horse race")
                        HStack(alignment: .top, spacing: 10) {
                            HStack(spacing: 5) { Icon(.radio, 14); Text("Caller") }.foregroundStyle(Theme.accent)
                            Text(commentary(race, now)).foregroundStyle(Theme.text2)
                        }
                        .font(.barlow(12, 600))
                        Button(race.status == "open" ? "Start race now" : race.status == "running" ? "Race in progress" : "Race finished") { races.startForViewing() }
                            .buttonStyle(.btn(.primary, full: true))
                            .disabled(race.status != "open")
                    }
                    .onChange(of: race.status == "running" && now >= (race.finishAt ?? .infinity)) { _, done in
                        if done { AppModel.shared.tickNow(force: true) }
                    }
                }
                .card()
                .gutter()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Field odds").font(.barlow(17, 700))
                            Text("Tap a price to open your standard screen-time bet slip.").font(.barlow(13)).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Tag("5 runners")
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(Races.horses.enumerated()), id: \.element.id) { i, runner in
                            if i > 0 { HRule() }
                            let winner = race.status == "final" && race.winnerId == runner.id
                            HStack(spacing: 12) {
                                HStack(spacing: 10) {
                                    Text("#\(runner.number)").font(.display(17, 900)).foregroundStyle(Color(hex: runner.color))
                                        .frame(width: 38, height: 38)
                                        .background(Color(hex: runner.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color(hex: runner.color).opacity(0.65), lineWidth: 1))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(runner.name).font(.barlow(15, 700)).lineLimit(1).foregroundStyle(winner ? Theme.accent : Theme.text)
                                        Text("Form \(runner.form) · \(runner.jockey)").font(.barlow(11)).foregroundStyle(Theme.text2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                OddsButton(sel: races.selection(race, runner), suspended: race.status != "open", big: true, label: runner.name)
                                    .frame(width: 106)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    Note(.blue, icon: .info, "Place a bet to start the race with your pick, or start it now to watch without a bet. Bets use your regular screen-time balance.")
                }
                .card()
                .gutter()

                if let latest {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Last result · Race #\(latest.number)").eyebrow()
                        Text("\(races.horse(latest.winnerId).name) won").font(.display(22, 800))
                        Text((latest.order ?? []).enumerated().map { "\($0.offset + 1). \(races.horse($0.element).name)" }.joined(separator: " · "))
                            .font(.barlow(13)).foregroundStyle(Theme.text2)
                    }
                    .card()
                    .gutter()
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func commentary(_ race: Races.Race, _ now: Ms) -> String {
        switch race.status {
        case "running":
            guard let start = race.startedAt, let order = race.order else { return "The field is underway!" }
            let elapsed = now - start
            if elapsed < 2200 { return "The field is underway!" }
            let leader = order.enumerated().first { elapsed / (9400 + Double($0.offset) * 450) < 1 }?.element ?? order[0]
            let h = races.horse(leader)
            return "#\(h.number) \(h.name) is driving for the lead."
        default:
            return races.latest == nil ? "Welcome to Silicon Downs. Select a horse to add it to your bet slip." : "The previous race is official. Place your next screen-time bet."
        }
    }
}

/// The track: five lanes, start and finish lines, and running horses.
struct RaceTrack: View {
    var race: Races.Race
    var now: Ms

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h: CGFloat = 250
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(hex: "#0a0d12")))
            let top: CGFloat = 20, lane: CGFloat = 42, start: CGFloat = 40, finish = w - 36
            for i in 0..<Races.horses.count {
                let y = top + CGFloat(i) * lane
                ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: lane)), with: .color(Color(hex: i % 2 == 1 ? "#111720" : "#151d27")))
                var dash = Path(); dash.move(to: CGPoint(x: 0, y: y + lane)); dash.addLine(to: CGPoint(x: w, y: y + lane))
                ctx.stroke(dash, with: .color(Color(hex: "#283141")), style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
                ctx.draw(Text("\(i + 1)").font(.system(size: 11)).foregroundStyle(Color(hex: "#5e687a")), at: CGPoint(x: 15, y: y + 20), anchor: .center)
            }
            var startLine = Path(); startLine.move(to: CGPoint(x: start, y: top)); startLine.addLine(to: CGPoint(x: start, y: top + lane * 5))
            ctx.stroke(startLine, with: .color(Color(hex: "#8c96a8").opacity(0.6)), lineWidth: 1)
            var y = top
            while y < top + lane * 5 {
                ctx.fill(Path(CGRect(x: finish - 3, y: y, width: 5, height: 5)), with: .color(Color(hex: "#f2f5f9")))
                y += 9
            }
            let elapsed: Double = race.status == "running" ? max(0, now - (race.startedAt ?? now)) : race.status == "final" ? 12_000 : 0
            let order = race.order ?? Races.horses.map(\.id)
            for (idx, runner) in Races.horses.enumerated() {
                var progress: Double = 0
                if race.status == "running" || race.status == "final" {
                    let rank = order.firstIndex(of: runner.id) ?? 0
                    progress = min(1, elapsed / (9400 + Double(rank) * 450))
                }
                let x = start + CGFloat(progress) * (finish - start - 12)
                let cy = top + CGFloat(idx) * lane + lane / 2
                drawHorse(&ctx, x, cy, runner, elapsed)
            }
        }
    }

    private func drawHorse(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ runner: Races.Horse, _ elapsed: Double) {
        var c = ctx
        c.translateBy(x: x, y: y)
        let color = Color(hex: runner.color)
        c.fill(Path(ellipseIn: CGRect(x: -13, y: -7, width: 26, height: 14)), with: .color(color))
        var neck = Path(); neck.move(to: CGPoint(x: 8, y: -2)); neck.addLine(to: CGPoint(x: 17, y: -13)); neck.addLine(to: CGPoint(x: 22, y: -10)); neck.addLine(to: CGPoint(x: 19, y: -1)); neck.closeSubpath()
        c.fill(neck, with: .color(color))
        c.fill(Path(ellipseIn: CGRect(x: -3, y: -13, width: 6, height: 6)), with: .color(Color(hex: "#f2f5f9")))
        let swing = CGFloat(sin(elapsed / 90 + Double(runner.id))) * 7
        for (ax, dir) in [(-8.0, -1.0), (-3, 1), (6, -1), (10, 1)] as [(CGFloat, CGFloat)] {
            var leg = Path(); leg.move(to: CGPoint(x: ax, y: 4)); leg.addLine(to: CGPoint(x: ax + swing * dir, y: 15))
            c.stroke(leg, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        c.fill(Path(roundedRect: CGRect(x: -5, y: -4, width: 10, height: 8), cornerRadius: 2), with: .color(Color(hex: "#080d14")))
        c.draw(Text("\(runner.number)").font(.system(size: 7, weight: .bold)).foregroundStyle(.white), at: CGPoint(x: 0, y: 0), anchor: .center)
    }
}
