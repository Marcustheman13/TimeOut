import SwiftUI

/// Auth or the app, plus everything layered on top (the web demo's #screen with #layer and #toasts).
struct RootView: View {
    private var app: AppModel { .shared }
    private var ui: UIState { .shared }
    private var net: Net { .shared }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if !app.ready {
                BrandIcon(size: 72)
            } else if app.inShell {
                ShellView()
            } else {
                AuthView()
            }
            OverlayLayer()
            if !net.online { NetBanner() }
            ToastHost()
        }
        .foregroundStyle(Theme.text)
        .font(.barlow(15))
    }
}

/// The phone layout: top bar, the current tab, the slip bar and the floating tab bar.
struct ShellView: View {
    private var ui: UIState { .shared }

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ZStack {
                switch ui.tab {
                case "bets": MyBetsView()
                case "social": SocialView()
                default: HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                SlipBar()
                TabBar()
            }
            .padding(.bottom, 14)
        }
    }
}

struct TopBar: View {
    private var store: Store { .shared }
    private var ui: UIState { .shared }

    var body: some View {
        let wl = store.wallet
        let locked = wl.lockedOut || wl.balance <= 0
        HStack(spacing: 8) {
            Button { ui.drawerOpen = true } label: {
                Icon(.menu, 22).foregroundStyle(Theme.text).frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) {
                        if wl.appsLocked {
                            Circle().fill(Theme.live).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Theme.bg, lineWidth: 2)).padding(7)
                        }
                    }
            }
            .buttonStyle(.press)
            .accessibilityLabel("Menu and settings")
            .frame(width: 44, alignment: .leading)
            HStack(spacing: 7) {
                BrandMark(size: 18).foregroundStyle(Theme.accent)
                Wordmark(size: 25)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { SettingsModel.open("screentime") } label: {
                HStack(spacing: 5) {
                    Icon(locked ? .lock : .hourglass, 15)
                    Text(locked ? "Locked" : "\(wl.balance) min").font(.barlow(14, 800)).monospacedDigit()
                }
                .foregroundStyle(locked ? Theme.loss : Theme.accentInk)
                .padding(.horizontal, 12).frame(height: 32)
                .background(locked ? Theme.raised : Theme.accent, in: Capsule())
            }
            .buttonStyle(.press)
            .accessibilityLabel(locked ? "Betting locked until midnight" : "\(wl.balance) minutes available to bet")
        }
        .padding(.leading, 8).padding(.trailing, 14)
        .frame(height: 52)
    }
}

/// "TIMEOUT" in the italic condensed display face, OUT in green.
struct Wordmark: View {
    var size: CGFloat
    var body: some View {
        (Text("TIME").foregroundStyle(Theme.text) + Text("OUT").foregroundStyle(Theme.accent))
            .font(.display(size, 900, italic: true))
            .tracking(size * 0.02)
    }
}

/// The floating pill tab bar.
struct TabBar: View {
    private var ui: UIState { .shared }
    private var store: Store { .shared }

    var body: some View {
        let d = store.data
        let open = d?.bets.filter { $0.status == "open" && ($0.kind == "sports" || $0.kind == "race") && !$0.legs.isEmpty
            && $0.legs.allSatisfy { $0.kind == "race" || $0.kind == "game" || ($0.kind == "sports" && $0.gameId != nil) } }.count ?? 0
        let social = d?.requestsIn.count ?? 0
        HStack(spacing: 4) {
            tab("home", "Home", .home, badge: 0, green: false)
            tab("bets", "My Bets", .ticket, badge: open, green: true)
            tab("social", "Social", .users, badge: social, green: false)
        }
        .padding(6)
        .frame(height: 70)
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(LinearGradient(colors: [Color(red: 44 / 255, green: 50 / 255, blue: 60 / 255).opacity(0.94),
                                                   Color(red: 30 / 255, green: 35 / 255, blue: 43 / 255).opacity(0.94)], startPoint: .top, endPoint: .bottom))
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.09), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 18)
        .padding(.horizontal, 14)
    }

    private func tab(_ key: String, _ label: String, _ icon: IconName, badge: Int, green: Bool) -> some View {
        let on = ui.tab == key
        return Button {
            ui.closeAllSheets()
            ui.go(key)
        } label: {
            VStack(spacing: 4) {
                Icon(icon, 23)
                Text(label).font(.display(14, 800)).tracking(0.14)
            }
            .foregroundStyle(on ? Theme.accent : Theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if on {
                    Capsule().fill(Color(red: 5 / 255, green: 7 / 255, blue: 10 / 255).opacity(0.85))
                        .overlay(Capsule().stroke(.black.opacity(0.5), lineWidth: 1).blur(radius: 1).offset(y: 1).mask(Capsule()))
                }
            }
            .overlay(alignment: .top) {
                if badge > 0 {
                    Text("\(badge)").font(.barlow(11, 800))
                        .foregroundStyle(green ? Theme.accentInk : .white)
                        .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                        .background(green ? Theme.accent : Theme.live, in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 30 / 255, green: 35 / 255, blue: 43 / 255), lineWidth: 2))
                        .offset(x: 17, y: 4)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The bar above the tab bar while picks are on a closed slip ("Bet Slip" / "Finalize Parlay").
struct SlipBar: View {
    private var slip: Slip { .shared }
    private var ui: UIState { .shared }
    private var live: LiveFeed { .shared }

    var body: some View {
        let _ = live.version
        let showParlay = slip.parlayMode && slip.legs.count > 1 && !ui.sheetOpen(.slip)
        let showSlip = !slip.legs.isEmpty && !slip.parlayMode && !ui.sheetOpen(.slip)
        if showParlay || showSlip {
            let st = slip.status()
            let price = OddsMath.fmt(OddsMath.fromDecimal(slip.decimal))
            Button { slip.open() } label: {
                HStack(spacing: 10) {
                    Text("\(slip.legs.count)").font(.barlow(13, 900))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 26, height: 26)
                        .background(showParlay ? Theme.accentInk.opacity(0.15) : Theme.accent, in: Circle())
                    Text(showParlay ? "Finalize Parlay" : "Bet Slip").font(.barlow(15, 800))
                    Spacer(minLength: 0)
                    if showParlay {
                        Text(st.closed ? "Pick unavailable" : st.changed ? "Odds changed" : price).font(.display(19, 900))
                    } else if st.changed || st.closed {
                        HStack(spacing: 4) { Icon(.alert, 15); Text(st.closed ? "Pick unavailable" : "Odds changed") }
                            .font(.barlow(13, 800)).foregroundStyle(Theme.warn)
                    } else {
                        Text(price).font(.display(19, 900)).foregroundStyle(Theme.accent)
                    }
                }
                .foregroundStyle(showParlay ? Theme.accentInk : Theme.text)
                .padding(.leading, 12).padding(.trailing, 16)
                .frame(height: 54)
                .background(showParlay ? Theme.accent : Theme.raised2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(showParlay ? .clear : Color(hex: "#3a4557"), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
            }
            .buttonStyle(.press)
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel(showParlay ? "Finalize \(slip.legs.count) pick parlay" : "Open bet slip")
        }
    }
}

// MARK: - Overlays

struct OverlayLayer: View {
    private var ui: UIState { .shared }

    var body: some View {
        ZStack {
            ForEach(ui.pages, id: \.self) { page in
                PageHost(kind: page)
                    .zIndex(Double(ui.pages.firstIndex(of: page) ?? 0))
                    .transition(.move(edge: .trailing))
            }
            if ui.drawerOpen {
                DrawerView().zIndex(50).transition(.opacity)
            }
            ForEach(ui.sheets, id: \.self) { sheet in
                SheetHost(kind: sheet)
                    .zIndex(100 + Double(ui.sheets.firstIndex(of: sheet) ?? 0))
                    .transition(.opacity)
            }
            if let dialog = ui.dialog {
                DialogView(request: dialog).zIndex(200).transition(.opacity)
            }
        }
    }
}

/// A full-screen page (game detail, parlay builder, a settings section).
struct PageHost: View {
    var kind: PageKind
    private var ui: UIState { .shared }
    @State private var dragX: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { close() } label: { Icon(.chevL, 22).foregroundStyle(Theme.text).frame(width: 40, height: 40) }
                    .buttonStyle(.press).accessibilityLabel("Back").frame(width: 44)
                Text(title).font(.barlow(17, 800)).lineLimit(1).frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            content
        }
        .background(Theme.bg)
        .offset(x: dragX)
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { v in if v.startLocation.x < 30 && v.translation.width > 0 { dragX = v.translation.width } }
                .onEnded { v in
                    if v.startLocation.x < 30 && v.translation.width > 110 { close() }
                    withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
                }
        )
    }

    private func close() { ui.closePage(kind) }

    private var title: String {
        switch kind {
        case .game(let id):
            guard let g = Feed.game(id) else { return "" }
            return "\(g.away.abbr) @ \(g.home.abbr)"
        case .parlay: return "Build a parlay"
        case .settings(let s): return SettingsModel.sections[s]?.title ?? ""
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .game(let id): GamePage(id: id)
        case .parlay: ParlayPage()
        case .settings(let s): SettingsPage(section: s)
        }
    }
}

/// A bottom sheet with its scrim: grab handle, title, close button, scrolling body and an optional footer.
struct SheetFrame<Body: View, Foot: View>: View {
    var title: String
    var tall = false
    var close: () -> Void
    var content: Body
    var foot: Foot
    var hasFoot: Bool

    init(_ title: String, tall: Bool = false, close: @escaping () -> Void, @ViewBuilder body: () -> Body, @ViewBuilder foot: () -> Foot) {
        self.title = title; self.tall = tall; self.close = close; self.content = body(); self.foot = foot(); self.hasFoot = Foot.self != EmptyView.self
    }

    @State private var appeared = false
    @State private var dragY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Theme.scrim.ignoresSafeArea().onTapGesture { close() }
                    .opacity(appeared ? 1 : 0)
                VStack(spacing: 0) {
                    Capsule().fill(Theme.raised2).frame(width: 38, height: 5).padding(.top, 8).padding(.bottom, 2)
                    HStack(spacing: 10) {
                        Text(title).font(.display(26, 900)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: close) { Icon(.x, 20).foregroundStyle(Theme.text).frame(width: 40, height: 40) }
                            .buttonStyle(.press).accessibilityLabel("Close")
                    }
                    .padding(.top, 6).padding(.leading, 18).padding(.trailing, 12).padding(.bottom, 10)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { dragY = max(0, $0.translation.height) }.onEnded { v in
                        if v.translation.height > 110 { close() }
                        withAnimation(.easeOut(duration: 0.2)) { dragY = 0 }
                    })
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) { content }
                            .padding(.horizontal, 16).padding(.bottom, 22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    if hasFoot {
                        VStack(spacing: 10) { foot }
                            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, max(22, geo.safeAreaInsets.bottom))
                            .frame(maxWidth: .infinity)
                            .background(Theme.sheet)
                            .overlay(alignment: .top) { HRule() }
                    } else {
                        Color.clear.frame(height: geo.safeAreaInsets.bottom)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: tall ? (geo.size.height + geo.safeAreaInsets.bottom) * 0.9 : nil)
                .frame(maxHeight: (geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom) * 0.9)
                .fixedSize(horizontal: false, vertical: !tall)
                .background(Theme.sheet, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1).mask(VStack { Rectangle().frame(height: 30); Spacer() })
                }
                .shadow(color: .black.opacity(0.45), radius: 25, y: -20)
                .offset(y: appeared ? dragY : geo.size.height)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onAppear { withAnimation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.28)) { appeared = true } }
    }
}

extension SheetFrame where Foot == EmptyView {
    init(_ title: String, tall: Bool = false, close: @escaping () -> Void, @ViewBuilder body: () -> Body) {
        self.init(title, tall: tall, close: close, body: body, foot: { EmptyView() })
    }
}

struct SheetHost: View {
    var kind: SheetKind
    var body: some View {
        switch kind {
        case .slip: SlipSheet()
        case .share(let id): ShareSheet(betId: id)
        case .how: HowItWorksSheet()
        case .locked: LockedAppsSheet()
        case .profile(let u): ProfileSheet(username: u)
        case .team(let id): TeamSheet(id: id)
        case .teamNew: NewTeamSheet()
        case .teamHow: TeamHowSheet()
        case .invite: InviteSheet()
        case .screenTimeApps: ScreenTimeAppsSheet()
        }
    }
}

/// In-app confirm dialog.
struct DialogView: View {
    var request: ConfirmRequest
    private var ui: UIState { .shared }

    var body: some View {
        ZStack {
            Theme.scrim.ignoresSafeArea().onTapGesture { ui.resolveDialog(false) }
            VStack(alignment: .leading, spacing: 12) {
                Text(request.title).font(.barlow(19, 800)).foregroundStyle(Theme.text)
                Text(request.body).font(.barlow(14.5)).foregroundStyle(Theme.text2).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let cancel = request.cancel {
                        Button(cancel) { ui.resolveDialog(false) }.buttonStyle(.btn(.ghost, full: true))
                    }
                    Button(request.confirm) { ui.resolveDialog(true) }.buttonStyle(.btn(request.kind, full: true))
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 330)
            .background(Theme.dialog, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 30)
            .padding(24)
        }
    }
}

struct ToastHost: View {
    private var ui: UIState { .shared }
    private var net: Net { .shared }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(ui.toasts) { t in
                ToastView(toast: t)
                    .onTapGesture { ui.dismissToast(t.id) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, net.online ? 10 : 66)
        .zIndex(300)
    }
}

struct ToastView: View {
    var toast: Toast
    var body: some View {
        let (icon, color): (IconName, Color) = {
            switch toast.kind {
            case .win: return (.check, Theme.accent)
            case .loss: return (.x, Theme.loss)
            case .warn: return (.alert, Theme.warn)
            case .info: return (.info, Theme.blue)
            }
        }()
        HStack(alignment: .top, spacing: 12) {
            Icon(icon, 20).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(.barlow(14.5, 800)).foregroundStyle(Theme.text)
                if !toast.msg.isEmpty { Text(toast.msg).font(.barlow(13)).foregroundStyle(Theme.text2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(toast.kind == .info ? Theme.stroke : color.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 17, y: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Red banner while offline; the slip refuses bets until the connection returns.
struct NetBanner: View {
    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Icon(.wifiOff, 17)
                Text(md("**No internet connection.** Betting is paused until you're back online.")).font(.barlow(13, 600))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10).padding(.horizontal, 14)
            .background(Theme.loss, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
            .padding(.horizontal, 10).padding(.top, 8)
            Spacer()
        }
        .zIndex(250)
        .accessibilityAddTraits(.isStaticText)
    }
}
