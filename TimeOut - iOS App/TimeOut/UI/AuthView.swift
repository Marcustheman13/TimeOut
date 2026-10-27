import PhotosUI
import SwiftUI

enum AuthScreen { case welcome, login, signup, verify, onboard }

/// Welcome, log in, create account, verify email and onboarding state (the web demo's auth.js).
@Observable
final class AuthModel {
    static let shared = AuthModel()

    var screen: AuthScreen = .welcome
    var errors: [String: String] = [:]
    var formError = ""
    var busy = false
    // Fields
    var loginEmail = ""
    var loginPassword = ""
    var signupUser = ""
    var signupEmail = ""
    var signupPassword = ""
    var signupConfirm = ""
    var photo: String?
    // Onboarding
    var step = 1
    var sports: [String] = []
    var locks: [String] = []
    // Verify email: the password stays in memory only, so this screen can log in by itself once the email is confirmed.
    var verifyEmail = ""
    @ObservationIgnored var verifyPassword = ""
    var verifySince: Date = .now
    var resentAt: Date = .now
    var checking = false
    var verifyNote = ""
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private static let pollSeconds: Double = 5
    private static let giveUpSeconds: Double = 30 * 60
    static let resendWait: Double = 60

    func show(_ s: AuthScreen) {
        if s != .verify { stopPolling(); verifyPassword = "" }
        screen = s
        errors = [:]
        formError = ""
        busy = false
        if s == .welcome { reset() }
    }

    private func reset() {
        loginEmail = ""; loginPassword = ""; signupUser = ""; signupEmail = ""; signupPassword = ""; signupConfirm = ""; photo = nil
    }

    func startOnboarding() {
        screen = .onboard
        step = 1
        sports = Store.shared.data?.settings.sports ?? Sim.realLeagues
        locks = []
    }

    private func showError(_ e: Error) {
        guard let e = e as? AppError else { formError = e.localizedDescription; return }
        errors.merge(e.fields) { _, b in b }
        formError = e.message
    }

    // MARK: Log in / sign up

    func login() async {
        errors = [:]; formError = ""
        guard Net.shared.online else { formError = "No internet connection. Check your Wi-Fi or data and try again."; return }
        busy = true
        defer { busy = false }
        do {
            if API.shared.configured {
                let user = try await API.shared.login(email: loginEmail, password: loginPassword)
                Store.shared.adoptServerUser(user, remote: try await API.shared.loadState())
                reset()
                AppModel.shared.boot()
                UIState.shared.toast(.win, "Logged in as @\(user.username)", "Your bets and settings are synced to Supabase.")
            } else {
                try Store.shared.login(loginEmail, loginPassword)
                reset()
                AppModel.shared.boot()
            }
        } catch {
            errors = [:]
            showError(error)
        }
    }

    func signup() async {
        errors = [:]; formError = ""
        guard Net.shared.online else { formError = "No internet connection. Check your Wi-Fi or data and try again."; return }
        if signupPassword != signupConfirm { errors["confirm"] = "Passwords don't match." }
        busy = true
        defer { busy = false }
        if API.shared.configured {
            do {
                if errors["confirm"] != nil { throw AppError(code: "invalid", message: "Fix the highlighted fields.") }
                let result = try await API.shared.register(username: signupUser.trimmingCharacters(in: .whitespaces),
                                                           email: signupEmail.trimmingCharacters(in: .whitespaces), password: signupPassword, photoUrl: photo)
                switch result {
                case .needsConfirmation(let email): startVerify(email, signupPassword)
                case .signedIn(let user, let state):
                    Store.shared.adoptServerUser(user, remote: state)
                    reset()
                    startOnboarding()
                }
            } catch { showError(error) }
            return
        }
        do {
            if errors["confirm"] != nil {
                // Still report the other field errors in the same pass.
                let s = Store.shared
                if let e = s.validateUsername(signupUser.trimmingCharacters(in: .whitespaces)) { errors["username"] = e }
                if let e = s.validateEmail(signupEmail.trimmingCharacters(in: .whitespaces)) { errors["email"] = e }
                if let e = Store.validatePassword(signupPassword) { errors["password"] = e }
                throw AppError(code: "invalid", message: "Fix the highlighted fields.")
            }
            let acc = try Store.shared.createAccount(username: signupUser, email: signupEmail, password: signupPassword, photo: photo)
            Store.shared.startSession(acc.id)
            reset()
            startOnboarding()
        } catch { showError(error) }
    }

    func demo() {
        guard !API.shared.configured else { return }
        guard Net.shared.online else { UIState.shared.toast(.loss, "No internet connection", "Check your Wi-Fi or data and try again."); return }
        Store.shared.loginDemo()
        AppModel.shared.boot()
    }

    // MARK: Verify email

    private func startVerify(_ email: String, _ password: String) {
        stopPolling()
        verifyEmail = email; verifyPassword = password
        verifySince = .now; resentAt = .now; checking = false; verifyNote = ""
        screen = .verify; errors = [:]; formError = ""
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollSeconds))
                guard screen == .verify else { return }
                await checkVerified(manual: false)
            }
        }
    }

    private func stopPolling() { pollTask?.cancel(); pollTask = nil }

    /// Tries to log in with the new account. Supabase refuses with "Email not confirmed" until the link is opened.
    func checkVerified(manual: Bool) async {
        guard !checking, !verifyEmail.isEmpty else { return }
        if !manual && Date().timeIntervalSince(verifySince) > Self.giveUpSeconds { return }
        checking = true
        defer { checking = false }
        do {
            let user = try await API.shared.login(email: verifyEmail, password: verifyPassword)
            stopPolling()
            verifyPassword = ""
            Store.shared.adoptServerUser(user, remote: try await API.shared.loadState())
            reset()
            AppModel.shared.boot()
            UIState.shared.toast(.win, "Email verified", "Welcome to TimeOut, @\(user.username).")
        } catch let e as AppError {
            if manual {
                formError = e.message.range(of: "confirm", options: .caseInsensitive) != nil
                    ? "Your email isn't confirmed yet. Open the link we sent, then try again." : e.message
            }
        } catch {}
    }

    func resend() async {
        guard Date().timeIntervalSince(resentAt) >= Self.resendWait else { return }
        do {
            try await API.shared.resendConfirmation(verifyEmail)
            resentAt = .now
            verifyNote = "Sent a new link to \(verifyEmail)."
            formError = ""
        } catch let e as AppError { formError = e.message } catch {}
    }

    func cancelVerify() {
        let email = verifyEmail
        show(.signup)
        signupEmail = email
    }

    // MARK: Onboarding

    func finishOnboarding(skip: Bool) {
        Store.shared.completeOnboarding(sports: sports, locks: skip ? nil : locks)
        AppModel.shared.boot()
        UIState.shared.toast(.win, "Welcome to TimeOut, @\(Store.shared.account?.username ?? "")",
                             "You have \(Store.shared.data?.wallet.balance ?? Rules.daily) betting minutes today. Tap any odds to start.")
    }
}

enum Auth {
    static func logout() {
        UIState.shared.drawerOpen = false
        Task {
            guard await UIState.shared.confirm("Log out?", "Your bets and settings stay saved on this device.", confirm: "Log out") else { return }
            Slip.shared.clear()
            if API.shared.configured { await API.shared.logout() }
            Store.shared.logout()
            AppModel.shared.boot()
        }
    }
}

struct AuthView: View {
    private var model: AuthModel { .shared }

    var body: some View {
        Group {
            switch model.screen {
            case .welcome: WelcomeScreen()
            case .login: LoginScreen()
            case .signup: SignupScreen()
            case .verify: VerifyScreen()
            case .onboard: OnboardScreen()
            }
        }
        .transition(.opacity)
    }
}

private struct AuthBack: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) { Icon(.chevL, 22).foregroundStyle(Theme.text).frame(width: 40, height: 40) }
            .buttonStyle(.press).padding(.leading, -10).accessibilityLabel("Back")
    }
}

private struct AuthScroll<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.top, 16).padding(.horizontal, 22).padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct AuthTitle: View {
    var title: String
    var sub: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.display(36, 900))
            if let sub { Text(sub).font(.barlow(14.5)).foregroundStyle(Theme.text2) }
        }
    }
}

// MARK: Welcome

struct WelcomeScreen: View {
    private var live: LiveFeed { .shared }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Ticker()
                Spacer(minLength: 0)
                BrandIcon(size: 64).padding(.bottom, 4)
                Wordmark(size: 64).lineLimit(1).minimumScaleFactor(0.6)
                Text("Bet your screen time, not your money.").font(.display(26, 700)).foregroundStyle(Theme.text).frame(maxWidth: 230, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    point(.hourglass, "60 betting minutes a day. Win and you get more phone time tomorrow.")
                    point(.radio, "Live scores and odds for NFL, NBA, MLB, NHL, college football and soccer.")
                    point(.users, "Compare screen-time records and compete on teams.")
                }
                .padding(.top, 8)
            }
            .padding(.top, 24).padding(.horizontal, 22).padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background {
                GeometryReader { geo in
                    ZStack {
                        RadialGradient(colors: [Theme.accent.opacity(0.22), .clear], center: UnitPoint(x: 0.8, y: 0.1), startRadius: 0, endRadius: 300)
                        RadialGradient(colors: [Theme.blue.opacity(0.12), .clear], center: UnitPoint(x: 0, y: 0.6), startRadius: 0, endRadius: 260)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()
            }
            VStack(spacing: 10) {
                Button("Log in") { AuthModel.shared.show(.login) }.buttonStyle(.btn(.primary, full: true))
                Button("Create account") { AuthModel.shared.show(.signup) }.buttonStyle(.btn(.ghost, full: true))
                if !API.shared.configured {
                    Button { AuthModel.shared.demo() } label: { BtnLabel("Try the demo account", icon: .flask, iconSize: 16) }.buttonStyle(.btn(.quiet, .sm, full: true))
                }
            }
            .padding(.top, 16).padding(.horizontal, 22).padding(.bottom, 30)
        }
        .onAppear { live.refresh() }
    }

    private func point(_ icon: IconName, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, 18).foregroundStyle(Theme.accent).padding(.top, 1)
            Text(text).font(.barlow(14.5, 600)).foregroundStyle(Theme.text2)
        }
    }
}

/// Live scores scrolling across the welcome screen.
struct Ticker: View {
    private var live: LiveFeed { .shared }
    @State private var width: CGFloat = 0

    var body: some View {
        let _ = live.version
        let games = Array(Feed.board().filter { $0.state == .live && !$0.simulated }.prefix(8))
        if !games.isEmpty {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let offset = width > 0 ? -CGFloat(t.truncatingRemainder(dividingBy: 32) / 32) * width : 0
                HStack(spacing: 8) {
                    row(games).background(GeometryReader { g in Color.clear.onAppear { width = g.size.width + 8 } })
                    row(games)
                }
                .offset(x: offset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 38)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            .accessibilityHidden(true)
        }
    }

    private func row(_ games: [Game]) -> some View {
        HStack(spacing: 8) {
            ForEach(games) { g in
                HStack(spacing: 6) {
                    LiveTag(text: "")
                    Text(g.away.abbr); Text("\(g.awayScore)").font(.display(15, 800)).foregroundStyle(Theme.text)
                    Text(g.home.abbr); Text("\(g.homeScore)").font(.display(15, 800)).foregroundStyle(Theme.text)
                    Text(g.clock).foregroundStyle(Theme.muted)
                }
                .font(.barlow(12.5, 700)).foregroundStyle(Theme.text2)
                .padding(.horizontal, 10).frame(height: 30)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                .fixedSize()
            }
        }
        .fixedSize()
    }
}

// MARK: Log in

struct LoginScreen: View {
    @Bindable private var model = AuthModel.shared

    var body: some View {
        AuthScroll {
            AuthBack { model.show(.welcome) }
            BrandIcon(size: 52)
            AuthTitle(title: "Welcome back", sub: "Log in with your email and password.")
            if !model.formError.isEmpty { FormError(model.formError) }
            FieldView(label: "Email", text: $model.loginEmail, err: model.errors["identifier"] ?? model.errors["email"], keyboard: .emailAddress, content: .emailAddress)
            FieldView(label: "Password", text: $model.loginPassword, secure: true, err: model.errors["password"], content: .password)
            Button(model.busy ? "Logging in…" : "Log in") { Task { await model.login() } }
                .buttonStyle(.btn(.primary, full: true)).disabled(model.busy)
            Button("Forgot password?") {
                Task {
                    _ = await UIState.shared.confirm("Reset your password", API.shared.configured
                        ? "Password reset emails aren't built yet. Create a new account, or log in on the website."
                        : "In this demo, accounts live only on this device, so there's no email reset. Create a new account or log in with the demo account.",
                        confirm: "OK", cancel: nil)
                }
            }
            .buttonStyle(.btn(.quiet, .sm, full: true))
            HRule()
            if !API.shared.configured {
                Button { model.demo() } label: { BtnLabel("Log in with the demo account", icon: .flask, iconSize: 16) }.buttonStyle(.btn(.ghost, full: true))
            }
            HStack(spacing: 4) {
                Text("New here?").foregroundStyle(Theme.text2)
                Button("Create an account") { model.show(.signup) }.foregroundStyle(Theme.accent).font(.barlow(13.5, 700))
            }
            .font(.barlow(13)).frame(maxWidth: .infinity)
        }
        .onSubmit { Task { await model.login() } }
    }
}

// MARK: Sign up

struct SignupScreen: View {
    @Bindable private var model = AuthModel.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var photoError: String?

    var body: some View {
        AuthScroll {
            AuthBack { model.show(.welcome) }
            BrandIcon(size: 52)
            AuthTitle(title: "Create your account", sub: "Friends find you by your username.")
            if !model.formError.isEmpty { FormError(model.formError) }
            HStack(spacing: 14) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Avatar(src: model.photo ?? TO.initialsAvatar(model.signupUser.isEmpty ? "?" : model.signupUser, "#1d2430"), size: 84)
                        .overlay(alignment: .bottomTrailing) {
                            Icon(.camera, 15).foregroundStyle(Theme.accentInk).frame(width: 30, height: 30).background(Theme.accent, in: Circle())
                                .overlay(Circle().stroke(Theme.bg, lineWidth: 3)).offset(x: 2, y: 2)
                        }
                }
                .accessibilityLabel("Profile photo")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Profile photo").font(.barlow(15, 700))
                    Text(model.photo != nil ? "Looking good. Tap to change it." : "Tap to add a photo. Optional, but it helps friends find you.").font(.barlow(13)).foregroundStyle(Theme.text2)
                    if let photoError { Text(photoError).font(.barlow(13, 700)).foregroundStyle(Theme.loss) }
                }
            }
            FieldView(label: "Username", text: Binding(get: { model.signupUser }, set: { model.signupUser = String($0.prefix(20)) }),
                      err: model.errors["username"], hint: "3–20 letters, numbers, dots or underscores", content: .username)
            FieldView(label: "Email", text: $model.signupEmail, err: model.errors["email"], keyboard: .emailAddress, content: .emailAddress)
            FieldView(label: "Password", text: $model.signupPassword, secure: true, err: model.errors["password"], hint: "At least 8 characters", content: .newPassword)
            FieldView(label: "Confirm password", text: $model.signupConfirm, secure: true, err: model.errors["confirm"], content: .newPassword)
            Button(model.busy ? "Creating account…" : "Create account") { Task { await model.signup() } }
                .buttonStyle(.btn(.primary, full: true)).disabled(model.busy)
            Text(API.shared.configured ? "Accounts and bets are saved securely with Supabase." : "Offline demo: accounts are saved on this device, not on a server.")
                .font(.barlow(11.5)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                Text("Already have an account?").foregroundStyle(Theme.text2)
                Button("Log in") { model.show(.login) }.foregroundStyle(Theme.accent).font(.barlow(13.5, 700))
            }
            .font(.barlow(13)).frame(maxWidth: .infinity)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let url = PhotoData.dataURL(from: data) {
                    model.photo = url; photoError = nil
                } else { photoError = "That image could not be read." }
            }
        }
    }
}

// MARK: Verify email

struct VerifyScreen: View {
    private var model: AuthModel { .shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let wait = max(0, AuthModel.resendWait - ctx.date.timeIntervalSince(model.resentAt))
            let stopped = ctx.date.timeIntervalSince(model.verifySince) > 30 * 60
            AuthScroll {
                AuthBack { model.cancelVerify() }
                Icon(.send, 30).foregroundStyle(Theme.accent).frame(width: 64, height: 64)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Verify your email").font(.display(36, 900))
                    (Text("We sent a confirmation link to ") + Text(model.verifyEmail).foregroundStyle(Theme.text).bold() + Text(". Open it to finish creating your account."))
                        .font(.barlow(14.5)).foregroundStyle(Theme.text2)
                }
                if !model.formError.isEmpty { FormError(model.formError) }
                if stopped {
                    Note(.plain, icon: .clock, "Still waiting. Once you've opened the link, tap the button below.")
                } else {
                    Note(.green) {
                        HStack(alignment: .top, spacing: 8) {
                            LiveTag(text: "").colorMultiply(Theme.accent).foregroundStyle(Theme.accent).padding(.top, 4)
                            Text("Waiting for you to confirm. You'll be logged in automatically as soon as you do.")
                        }
                    }
                }
                if !model.verifyNote.isEmpty { Text(model.verifyNote).font(.barlow(13)).foregroundStyle(Theme.text2).frame(maxWidth: .infinity) }
                Button(model.checking ? "Checking…" : "I've confirmed my email") { Task { await model.checkVerified(manual: true) } }
                    .buttonStyle(.btn(.primary, full: true)).disabled(model.checking)
                Button { Task { await model.resend() } } label: {
                    BtnLabel(wait > 0 ? "Resend email in \(Int(ceil(wait)))s" : "Resend email", icon: .refresh, iconSize: 16)
                }
                .buttonStyle(.btn(.ghost, full: true)).disabled(wait > 0)
                HStack(spacing: 4) {
                    Text("Can't find it? Check spam or promotions. Wrong email?").foregroundStyle(Theme.text2)
                    Button("Start over") { model.cancelVerify() }.foregroundStyle(Theme.accent).font(.barlow(13.5, 700))
                }
                .font(.barlow(13)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: Onboarding

struct OnboardScreen: View {
    @Bindable private var model = AuthModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { i in Capsule().fill(i <= model.step ? Theme.accent : Theme.raised).frame(height: 4) }
            }
            .padding(.top, 16).padding(.horizontal, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.step > 1 { AuthBack { model.step -= 1 } }
                    switch model.step {
                    case 1: stepOne
                    case 2: stepTwo
                    default: stepThree
                    }
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 8) {
                switch model.step {
                case 1:
                    Button("Next") { model.step += 1 }.buttonStyle(.btn(.primary, full: true))
                case 2:
                    Button(model.sports.isEmpty ? "Pick at least one" : "Next") { model.step += 1 }
                        .buttonStyle(.btn(.primary, full: true)).disabled(model.sports.isEmpty)
                default:
                    Button("Start betting") { model.finishOnboarding(skip: false) }.buttonStyle(.btn(.primary, full: true))
                    Button("Skip for now") { model.finishOnboarding(skip: true) }.buttonStyle(.btn(.quiet, .sm, full: true))
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 30)
        }
    }

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Here's the deal, @\(Store.shared.account?.username ?? "")").font(.display(36, 900))
            HowCard(n: 1, title: "You get 60 betting minutes a day", text: "They reset every night at midnight.")
            HowCard(n: 2, title: "You're betting tomorrow's phone time", text: "Win and tomorrow's limit goes up. Lose and it goes down.")
            HowCard(n: 3, title: "No money, ever", text: "Not now, not later. Bet screen time and build a clean streak.")
        }
    }

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 18) {
            AuthTitle(title: "Pick your sports", sub: "These show up on your Home feed. You can change them in Settings.")
            ListBox {
                ForEach(Sim.leagueOrder, id: \.self) { l in
                    let L = Sim.leagues[l]!
                    Button {
                        model.sports = model.sports.contains(l) ? model.sports.filter { $0 != l } : model.sports + [l]
                    } label: {
                        ListRow(L.title, sub: AttributedString(l == "sim" ? "Simulated games for days without sports" : L.sport.prefix(1).uppercased() + L.sport.dropFirst())) {
                            SportSquare(text: L.short)
                        } trailing: { CheckBox(on: model.sports.contains(l)) }
                    }
                    .buttonStyle(.press)
                }
            }
        }
    }

    private var stepThree: some View {
        let pts = Store.points(model.locks)
        return VStack(alignment: .leading, spacing: 18) {
            AuthTitle(title: "Lock your time-wasters", sub: "When today's phone time runs out, these apps lock. Lock more to reach a higher tier with bonus minutes and odds boosts.")
            HStack { Text("\(pts) lock points").font(.barlow(15, 700)); Spacer(); TierBadge(tierId: Store.tierForPoints(pts).id) }.card(12)
            ListBox {
                ForEach(Store.lockable.filter { $0.kind != "Website" }, id: \.id) { x in
                    Button {
                        model.locks = model.locks.contains(x.id) ? model.locks.filter { $0 != x.id } : model.locks + [x.id]
                    } label: {
                        ListRow(x.name, sub: AttributedString("\(x.kind) · \(x.pts) pt\(x.pts == 1 ? "" : "s")")) {
                            LrIcon(icon: x.kind == "Category" ? .grid : .phone, bg: Color(hex: x.color).opacity(0.13), fg: Color(hex: x.color))
                        } trailing: { CheckBox(on: model.locks.contains(x.id)) }
                    }
                    .buttonStyle(.press)
                }
            }
        }
    }
}
