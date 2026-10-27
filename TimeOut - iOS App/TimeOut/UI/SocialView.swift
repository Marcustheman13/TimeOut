import SwiftUI

@Observable
final class SocialModel {
    static let shared = SocialModel()
    var tab = "board"
    var query = ""
    var remote: [Person] = []
    var searching = false
    @ObservationIgnored private var searchSeq = 0

    func search(_ q: String) {
        query = q
        remote = []
        searchSeq += 1
        let seq = searchSeq
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        searching = !trimmed.isEmpty
        guard searching else { return }
        Task {
            let rows = await API.shared.searchUsers(trimmed)
            guard seq == searchSeq else { return }
            searching = false
            remote = rows.map { Person(username: $0.username, name: $0.name, photo: $0.photo ?? TO.initialsAvatar($0.username), remote: true) }
        }
    }

    func peopleForQuery() -> [Person] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let me = Store.shared.account?.username.lowercased() else { return [] }
        var seen = Set<String>()
        var out: [Person] = []
        func push(_ p: Person) {
            let k = p.username.lowercased()
            if k.isEmpty || k == me || seen.contains(k) { return }
            seen.insert(k); out.append(p)
        }
        // Demo profiles and accounts on this device already have names and photos; a server row shouldn't replace them.
        let local = Store.shared.searchPeople(q)
        let localKeys = Set(local.map { $0.username.lowercased() })
        for p in remote where !localKeys.contains(p.username.lowercased()) { push(p) }
        for p in local { push(p) }
        return Array(out.prefix(8))
    }

    /// A profile for someone search found on the server, or a friend who isn't a demo account on this device.
    func personFor(_ username: String) -> Person? {
        if let known = Store.shared.person(username) { return known }
        let key = username.lowercased()
        let hit = remote.first { $0.username.lowercased() == key }
        guard let d = Store.shared.data else { return nil }
        let listed = hit != nil || d.friends.contains { $0.lowercased() == key } || d.requestsOut.contains { ($0.to ?? "").lowercased() == key }
            || d.requestsIn.contains { ($0.from ?? "").lowercased() == key }
        guard listed else { return nil }
        return Person(username: hit?.username ?? username, name: hit?.name ?? username, photo: hit?.photo ?? TO.initialsAvatar(username),
                      share: PrivacySettings(record: false, minutes: false, bets: false), remote: true)
    }

    func copyInvite() {
        let link = Invites.friendLink()
        _ = Clipboard.copy(link)
        UIState.shared.toast(.win, "Invite link copied", link, ms: 5000)
    }

    func addFriend(_ u: String) {
        let rel = Store.shared.relation(u)
        Store.shared.sendFriendRequest(u)
        UIState.shared.toast(.win, rel == "incoming" ? "You and @\(u) are now friends" : "Friend request sent to @\(u)")
    }
}

struct SocialView: View {
    private var store: Store { .shared }
    private var model: SocialModel { .shared }
    private var ui: UIState { .shared }
    private var app: AppModel { .shared }

    var body: some View {
        let _ = app.tick
        let reqCount = store.data?.requestsIn.count ?? 0
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    PageHead(title: "Social", text: "Compete with friends: compare screen-time records and join teams.")
                    VStack(spacing: 14) {
                        MeCard()
                        FindCard()
                        Seg {
                            SegButton(on: model.tab == "board", action: { model.tab = "board" }) { Text("Friends") }
                            SegButton(on: model.tab == "requests", action: { model.tab = "requests" }) {
                                Text("Requests")
                                if reqCount > 0 { CountPill(n: reqCount, bg: Theme.live, fg: .white).scaleEffect(0.9) }
                            }
                            SegButton(on: model.tab == "teams", action: {
                                model.tab = "teams"
                                Task { await store.refreshTeams() }
                            }) { Text("Teams") }
                        }
                        .gutter()
                        switch model.tab {
                        case "requests": RequestsList()
                        case "teams": TeamsList()
                        default: Leaderboard()
                        }
                    }
                }
                .padding(.bottom, 116)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: ui.scrollTopToken) { proxy.scrollTo("top", anchor: .top) }
        }
    }
}

struct MeCard: View {
    var body: some View {
        let st = Store.shared.myStats
        let wl = Store.shared.wallet
        let acc = Store.shared.account
        HStack(spacing: 14) {
            Avatar(src: acc?.photo ?? "", size: 64)
            VStack(alignment: .leading, spacing: 0) {
                Text("@\(acc?.username ?? "")").font(.barlow(17, 700))
                HStack(spacing: 6) {
                    TierBadge(tierId: wl.tier.id, sm: true)
                    HStack(spacing: 6) { Icon(.flame, 12); Text("\(wl.streak)-day streak") }.font(.barlow(11.5, 700)).foregroundStyle(wl.streak > 0 ? Theme.warn : Theme.muted)
                }
                .padding(.top, 5)
                HStack(spacing: 16) {
                    (Text("\(st.w)-\(st.l)").font(.barlow(13, 700)) + Text(" record").foregroundStyle(Theme.text2)).font(.barlow(13))
                    (Text(Fmt.signedMin(st.net)).font(.barlow(13, 700)).foregroundStyle(st.net > 0 ? Theme.accent : st.net < 0 ? Theme.loss : Theme.text)
                     + Text(" all time").foregroundStyle(Theme.text2)).font(.barlow(13))
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
        .gutter()
    }
}

struct FindCard: View {
    private var model: SocialModel { .shared }
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find friends").font(.barlow(17, 800))
            HStack {
                TextField("", text: Binding(get: { model.query }, set: { model.search($0) }), prompt: Text("Search by username").foregroundStyle(Theme.muted))
                    .focused($focused)
                    .font(.barlow(16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                Icon(.search, 18).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? Theme.accent : Theme.stroke, lineWidth: 1))
            SearchResults()
            HStack {
                Text("Or share your invite link").font(.barlow(13)).foregroundStyle(Theme.text2).lineLimit(1)
                Spacer()
                Button { model.copyInvite() } label: { BtnLabel("Copy link", icon: .link, iconSize: 14) }.buttonStyle(.btn(.ghost, .xs))
            }
            .padding(.top, 2)
        }
        .card()
        .gutter()
        .onReceive(NotificationCenter.default.publisher(for: .focusSocialSearch)) { _ in focused = true }
    }
}

extension Notification.Name {
    static let focusSocialSearch = Notification.Name("timeout.focusSocialSearch")
}

struct SearchResults: View {
    private var model: SocialModel { .shared }
    private var store: Store { .shared }

    var body: some View {
        let q = model.query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let results = model.peopleForQuery()
            if results.isEmpty {
                if model.searching {
                    Note(.plain, icon: .search) { Text("Searching usernames…").font(.barlow(13, 700)).foregroundStyle(Theme.text) }
                } else {
                    Note(.plain, icon: .search) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No one found with the username \"\(q)\".").foregroundStyle(Theme.text).font(.barlow(13, 700))
                            Text("They might not be on TimeOut yet. Send them your invite link instead.")
                            Button { model.copyInvite() } label: { BtnLabel("Copy invite link", icon: .link, iconSize: 14) }
                                .buttonStyle(.btn(.primary, .xs)).padding(.top, 5)
                        }
                    }
                }
            } else {
                ListBox {
                    ForEach(results, id: \.username) { p in
                        let rel = store.relation(p.username)
                        HStack(spacing: 12) {
                            Button { UIState.shared.openSheet(.profile(p.username)) } label: {
                                HStack(spacing: 10) {
                                    Avatar(src: p.photo)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("@\(p.username)").font(.barlow(15, 700)).lineLimit(1)
                                        Text("\(p.name)\(p.local ? " · on this device" : p.remote ? " · TimeOut account" : "")").font(.barlow(13)).foregroundStyle(Theme.text2).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.press)
                            switch rel {
                            case "friend": Tag("Friends", .green)
                            case "requested": Button("Requested") { store.cancelFriendRequest(p.username) }.buttonStyle(.btn(.ghost, .xs))
                            case "incoming": Button("Accept") { model.addFriend(p.username) }.buttonStyle(.btn(.primary, .xs))
                            default: Button { model.addFriend(p.username) } label: { BtnLabel("Add", icon: .userPlus, iconSize: 14) }.buttonStyle(.btn(.primary, .xs))
                            }
                        }
                        .padding(.vertical, 10).padding(.horizontal, 14)
                    }
                }
            }
        }
    }
}

struct Leaderboard: View {
    private var store: Store { .shared }
    var body: some View {
        if store.data?.friends.isEmpty ?? true {
            EmptyState(icon: .users, title: "Keep up with your friends",
                       text: "Compare screen-time records and build teams that compete for a week or a season. Add your first friend to get started.") {
                Button { SocialModel.shared.copyInvite() } label: { BtnLabel("Invite a friend", icon: .link, iconSize: 16) }.buttonStyle(.btn(.primary))
                Button("Search usernames instead") { NotificationCenter.default.post(name: .focusSocialSearch, object: nil) }.buttonStyle(.btn(.quiet, .sm))
            }
        } else {
            let rows = store.leaderboard()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Leaderboard · minutes won or lost").eyebrow()
                    Spacer()
                    Button("What friends see") { SettingsModel.open("privacy") }.font(.barlow(11.5, 700)).foregroundStyle(Theme.accent).buttonStyle(.press)
                }
                ListBox {
                    ForEach(Array(rows.enumerated()), id: \.element.username) { i, r in
                        Button { UIState.shared.openSheet(.profile(r.username)) } label: {
                            LeaderRowView(rank: r.share.minutes ? "\(i + 1)" : "–", photo: r.photo, name: r.me ? "You" : "@\(r.username)", me: r.me) {
                                TierBadge(tierId: r.tier, sm: true)
                                Text(r.share.record ? "\(r.w)-\(r.l)" : "Record private")
                                if r.streak > 0 { HStack(spacing: 6) { Icon(.flame, 11); Text("\(r.streak)") }.foregroundStyle(Theme.warn) }
                            } value: {
                                if r.share.minutes {
                                    Text(Fmt.signed(r.net)).foregroundStyle(r.net > 0 ? Theme.accent : r.net < 0 ? Theme.loss : Theme.text)
                                    Text("min").font(.barlow(11, 700)).foregroundStyle(Theme.muted)
                                } else {
                                    Text("Private").font(.display(14, 800)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .buttonStyle(.press)
                    }
                }
                Text("Friends only show the stats they've chosen to share.").font(.barlow(11.5)).foregroundStyle(Theme.muted)
            }
            .gutter()
        }
    }
}

/// `.lb-row`: rank, avatar, name with a sub-line, and a value on the right.
struct LeaderRowView<Sub: View, Value: View>: View {
    var rank: String
    var photo: String
    var name: String
    var me: Bool
    var sub: Sub
    var value: Value

    init(rank: String, photo: String, name: String, me: Bool, @ViewBuilder sub: () -> Sub, @ViewBuilder value: () -> Value) {
        self.rank = rank; self.photo = photo; self.name = name; self.me = me; self.sub = sub(); self.value = value()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(rank).font(.display(18, 900)).foregroundStyle(Theme.text2).frame(width: 22)
            Avatar(src: photo)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.barlow(14.5, 800)).lineLimit(1)
                HStack(spacing: 6) { sub }.font(.barlow(12)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) { value }.font(.display(19, 800)).monospacedDigit()
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(me ? Theme.accentSoft : .clear)
        .contentShape(Rectangle())
    }
}

struct RequestsList: View {
    private var store: Store { .shared }
    var body: some View {
        let d = store.data
        let incoming = d?.requestsIn ?? [], outgoing = d?.requestsOut ?? []
        if incoming.isEmpty && outgoing.isEmpty {
            EmptyState(icon: .bell, iconSize: 36, title: "You're all caught up", text: "Friend requests show up here.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !incoming.isEmpty {
                    Text("Friend requests").eyebrow()
                    ListBox {
                        ForEach(incoming) { r in
                            let from = r.from ?? ""
                            let p = store.person(from)
                            HStack(spacing: 12) {
                                Avatar(src: p?.photo ?? TO.initialsAvatar(from))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("@\(from)").font(.barlow(15, 700))
                                    Text("\(p != nil && p!.name != from ? "\(p!.name) · " : "")Received \(Fmt.ago(r.at))").font(.barlow(11.5)).foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Decline") { store.declineFriendRequest(r.id) }.buttonStyle(.btn(.ghost, .xs))
                                Button("Accept") {
                                    store.acceptFriendRequest(r.id)
                                    UIState.shared.toast(.win, "You and @\(from) are now friends")
                                }.buttonStyle(.btn(.primary, .xs))
                            }
                            .padding(.vertical, 10).padding(.horizontal, 14)
                        }
                    }
                }
                if !outgoing.isEmpty {
                    Text("Sent requests").eyebrow()
                    ListBox {
                        ForEach(outgoing) { r in
                            let to = r.to ?? ""
                            let p = store.person(to)
                            let wait = Store.resendWait(r)
                            HStack(spacing: 12) {
                                Avatar(src: p?.photo ?? TO.initialsAvatar(to))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("@\(to)").font(.barlow(15, 700))
                                    Text("Sent \(Fmt.ago(r.at)) · \(wait > 0 ? "send again in \(Fmt.inTime(wait))" : "waiting for them to accept")").font(.barlow(11.5)).foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 6) {
                                    if wait > 0 {
                                        Button {} label: { BtnLabel("Sent", icon: .check, iconSize: 13) }.buttonStyle(.btn(.ghost, .xs)).disabled(true)
                                    } else {
                                        Button {
                                            do {
                                                try store.resendFriendRequest(to)
                                                UIState.shared.toast(.win, "Request sent again to @\(to)", "You can send another one in an hour.")
                                            } catch let e as AppError { UIState.shared.toast(.warn, "Not yet", e.message) } catch {}
                                        } label: { BtnLabel("Send again", icon: .refresh, iconSize: 13) }.buttonStyle(.btn(.primary, .xs))
                                    }
                                    Button("Cancel") { store.cancelFriendRequest(to) }.buttonStyle(.btn(.quiet, .xs))
                                }
                            }
                            .padding(.vertical, 10).padding(.horizontal, 14)
                        }
                    }
                }
            }
            .gutter()
        }
    }
}

struct TeamsList: View {
    private var store: Store { .shared }
    var body: some View {
        let list = store.data?.teams ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text("Teams compete over the dates you pick. Whoever wins the most minutes in that stretch tops the team.").font(.barlow(13)).foregroundStyle(Theme.text2)
            HStack(spacing: 6) {
                Button { UIState.shared.openSheet(.teamNew) } label: { BtnLabel("Create a team", icon: .plus, iconSize: 16) }.buttonStyle(.btn(.primary, .sm))
                Button { UIState.shared.openSheet(.teamHow) } label: { BtnLabel("How teams work", icon: .info, iconSize: 16) }.buttonStyle(.btn(.ghost, .sm))
            }
            if list.isEmpty {
                EmptyState(icon: .trophy, iconSize: 36, title: "No teams yet", text: "Start one with a few friends and pick a start and end date.")
            }
            ForEach(list) { t in
                let status = Store.teamStatus(t)
                let standings = store.teamStandings(t)
                let myPlace = standings.firstIndex { $0.me }
                Button {
                    UIState.shared.openSheet(.team(t.id))
                    Task { await store.refreshTeams() }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(t.name).font(.barlow(16, 700))
                            Spacer()
                            switch status {
                            case "active": Tag("Ends in \(Fmt.inTime(TO.dayStart(t.end) + TO.DAY - TO.now()))", .green)
                            case "upcoming": Tag("Starts \(Fmt.date(TO.dayStart(t.start)))", .blue)
                            default: Tag("Ended")
                            }
                        }
                        HStack {
                            Text("\(Fmt.date(TO.dayStart(t.start))) – \(Fmt.date(TO.dayStart(t.end))) · \(t.members.count) members").font(.barlow(13)).foregroundStyle(Theme.text2)
                            Spacer()
                            HStack(spacing: -8) {
                                ForEach(Array(standings.prefix(5).enumerated()), id: \.offset) { _, s in
                                    Avatar(src: s.photo, size: 26).overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                                }
                            }
                        }
                        if status != "upcoming", !standings.isEmpty, let place = myPlace {
                            (Text("You're ") + Text(Fmt.ordinal(place + 1)).bold() + Text(" of \(standings.count) · leader ")
                             + Text(standings[0].me ? "you" : "@\(standings[0].username)").bold()).font(.barlow(13))
                        }
                    }
                    .foregroundStyle(Theme.text)
                    .card()
                }
                .buttonStyle(.press)
            }
        }
        .gutter()
    }
}

// MARK: - Profile sheet

struct ProfileSheet: View {
    var username: String
    private var store: Store { .shared }
    private var ui: UIState { .shared }

    var body: some View {
        let isMe = username == store.account?.username
        let p = isMe ? nil : SocialModel.shared.personFor(username)
        let rel = isMe ? "me" : store.relation(username)
        SheetFrame(isMe ? "Your profile" : "@\(username)", close: { ui.closeSheet(.profile(username)) }) {
            if !isMe && p == nil {
                Text("This person could not be found.").foregroundStyle(Theme.text2)
            } else {
                let st = isMe ? store.myStats : nil
                let share = isMe ? PrivacySettings() : p!.share
                let showAll = isMe || rel == "friend"
                let rec = isMe ? "\(st!.w)-\(st!.l)" : "\(p!.w)-\(p!.l)"
                let net = isMe ? st!.net : p!.net
                let tierId = isMe ? store.wallet.tier.id : p!.tier
                let streak = isMe ? store.wallet.streak : p!.streak
                HStack(spacing: 14) {
                    Avatar(src: isMe ? (store.account?.photo ?? "") : p!.photo, size: 96)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isMe ? "@\(username)" : p!.name).font(.barlow(20, 800))
                        if !isMe { Text("@\(username)").font(.barlow(13)).foregroundStyle(Theme.text2) }
                        HStack(spacing: 6) {
                            TierBadge(tierId: tierId, sm: true)
                            if streak > 0 { HStack(spacing: 6) { Icon(.flame, 12); Text("\(streak)-day streak") }.font(.barlow(11.5, 700)).foregroundStyle(Theme.warn) }
                        }
                        .padding(.top, 8)
                    }
                }
                if showAll {
                    RecordBig(items: [
                        (share.record ? rec : "Private", "Record", share.record ? Theme.text : Theme.muted),
                        (share.minutes ? Fmt.signed(net) : "Private", "Minutes won/lost", !share.minutes ? Theme.muted : net > 0 ? Theme.accent : net < 0 ? Theme.loss : Theme.text),
                        ("\(streak)d", "Clean streak", Theme.text),
                    ])
                } else {
                    Note(.plain, icon: .lock, "Add @\(username) as a friend to see their stats.")
                }
                if !isMe && showAll {
                    if share.bets {
                        let picks = store.sharedPicks(p!)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Open bets they're sharing").eyebrow()
                            if picks.isEmpty { Text("No open bets right now.").font(.barlow(13)).foregroundStyle(Theme.text2) }
                            ForEach(picks, id: \.self) { k in
                                HStack {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(k.label).font(.barlow(15, 700))
                                        Text(k.matchup).font(.barlow(13)).foregroundStyle(Theme.text2)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text(OddsMath.fmt(k.price)).font(.display(18, 800)).foregroundStyle(Theme.accent)
                                        Text("\(k.stake) min").font(.barlow(11.5)).foregroundStyle(Theme.muted)
                                    }
                                }
                                .card(12)
                            }
                        }
                    } else {
                        Text("\(p!.name) keeps their open bets private.").font(.barlow(13)).foregroundStyle(Theme.text2)
                    }
                }
                if isMe {
                    Button { SettingsModel.open("privacy") } label: { BtnLabel("Choose what friends can see", icon: .eye, iconSize: 16) }.buttonStyle(.btn(.ghost, .sm, full: true))
                }
            }
        } foot: {
            if !isMe && p != nil {
                switch rel {
                case "friend":
                    Button("Remove friend") {
                        Task {
                            guard await ui.confirm("Remove @\(username)?", "You can add them again later.", confirm: "Remove", kind: .danger) else { return }
                            store.removeFriend(username)
                            ui.closeSheet(.profile(username))
                        }
                    }.buttonStyle(.btn(.quiet, .sm, full: true))
                case "requested":
                    Button("Friend request sent · Cancel") { store.cancelFriendRequest(username) }.buttonStyle(.btn(.ghost, full: true))
                default:
                    Button { SocialModel.shared.addFriend(username) } label: {
                        BtnLabel(rel == "incoming" ? "Accept friend request" : "Add friend", icon: .userPlus)
                    }.buttonStyle(.btn(.primary, full: true))
                }
            }
        }
    }
}

// MARK: - Team sheets

struct TeamSheet: View {
    var id: String
    private var store: Store { .shared }
    private var ui: UIState { .shared }

    var body: some View {
        let t = store.data?.teams.first { $0.id == id }
        SheetFrame(t?.name ?? "Team", tall: true, close: { ui.closeSheet(.team(id)) }) {
            if let t {
                let status = Store.teamStatus(t)
                let rows = store.teamStandings(t)
                let invitable = (store.data?.friends ?? []).filter { f in !t.members.contains { Store.sameUser($0, f) } }
                let owner = Store.sameUser(t.owner, store.account?.username) ? "You own this team" : "Owned by @\(t.owner)"
                HStack {
                    HStack(spacing: 6) { Icon(.calendar, 14); Text("\(Fmt.date(TO.dayStart(t.start))) – \(Fmt.date(TO.dayStart(t.end)))") }
                    Spacer()
                    Text(status == "active" ? "Ends in \(Fmt.inTime(TO.dayStart(t.end) + TO.DAY - TO.now()))"
                         : status == "upcoming" ? "Starts in \(Fmt.inTime(TO.dayStart(t.start) - TO.now()))" : "Ended")
                }
                .font(.barlow(13)).foregroundStyle(Theme.text2)
                Text("\(owner) · \(t.members.count) on the roster").font(.barlow(13)).foregroundStyle(Theme.text2)
                ListBox {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        LeaderRowView(rank: r.hidden ? "–" : "\(i + 1)", photo: r.photo, name: r.me ? "You" : "@\(r.username)", me: r.me) {
                            Text("\(r.w)-\(r.l) during this team")
                        } value: {
                            if r.hidden {
                                Text("Private").font(.display(14, 800)).foregroundStyle(Theme.muted)
                            } else {
                                Text(Fmt.signed(r.net)).foregroundStyle(r.net > 0 ? Theme.accent : r.net < 0 ? Theme.loss : Theme.text)
                                Text("min").font(.barlow(11, 700)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                Text("Standings count screen-time bets placed between the start and end dates. Friend bets don't count.").font(.barlow(11.5)).foregroundStyle(Theme.muted)
                if !invitable.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invite more friends").font(.barlow(13, 700)).foregroundStyle(Theme.text2)
                        FlowLayout(spacing: 8) {
                            ForEach(invitable, id: \.self) { u in
                                if let p = SocialModel.shared.personFor(u) {
                                    PickFriend(photo: p.photo, name: u, on: false, plus: true) {
                                        store.inviteToTeam(t.id, [u])
                                        ui.toast(.win, "Invited @\(u)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } foot: {
            if let t {
                Button {
                    _ = store.ensureTeamKey(t.id)
                    if let team = store.data?.teams.first(where: { $0.id == t.id }) {
                        let link = Invites.teamLink(team)
                        _ = Clipboard.copy(link)
                        ui.toast(.win, "Team link copied", link, ms: 5000)
                    }
                } label: { BtnLabel("Copy team link", icon: .link, iconSize: 16) }.buttonStyle(.btn(.ghost, .sm, full: true))
                Button("Leave team") {
                    Task {
                        guard await ui.confirm("Leave this team?", "Your results stop counting toward its standings.", confirm: "Leave team", kind: .danger) else { return }
                        store.leaveTeam(t.id)
                        ui.closeSheet(.team(t.id))
                    }
                }.buttonStyle(.btn(.quiet, .sm, full: true))
            }
        }
    }
}

struct PickFriend: View {
    var photo: String
    var name: String
    var on: Bool
    var plus = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Avatar(src: photo, size: 30)
                if plus { Icon(.plus, 14) }
                Text(name).font(.barlow(13.5, 700))
            }
            .foregroundStyle(on ? Theme.accent : Theme.text)
            .padding(.leading, 4).padding(.trailing, 12).frame(height: 38)
            .background(on ? Theme.accentSoft : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Theme.accent : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.press)
    }
}

/// Wraps children onto new lines (`flex-wrap: wrap`).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

struct TeamHowSheet: View {
    var body: some View {
        SheetFrame("How teams work", close: { UIState.shared.closeSheet(.teamHow) }) {
            Text("Teams are how friends compete here without betting money. TimeOut puts screen time on the line instead of cash, and a team is the stretch of days you compare.")
                .font(.barlow(14.5)).foregroundStyle(Theme.text2)
            HowCard(n: 1, title: "Pick a name and the dates", text: "Create a team for a week or a season. You can start it on your own and invite people later.")
            HowCard(n: 2, title: "Minutes decide the standings", text: "Between the start and end dates, screen-time bets count. Whoever comes out ahead on minutes leads. A side bet with a friend does not count.")
            HowCard(n: 3, title: "Invite friends onto the roster", text: "Open the team and add a friend, or copy the team link. When they open it, you become friends and they join the roster.")
            HowCard(n: 4, title: "Leave whenever you want", text: "Leaving takes you off the standings. The team stays for everyone else.")
            Text("The team is saved on this device. When you're signed in, the roster is saved with your TimeOut account too, one member at a time, so it's still here the next time you open the app.")
                .font(.barlow(11.5)).foregroundStyle(Theme.muted)
        } foot: {
            Button("Got it") { UIState.shared.closeSheet(.teamHow) }.buttonStyle(.btn(.primary, full: true))
        }
    }
}

struct NewTeamSheet: View {
    @State private var name = ""
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var members: [String] = []
    @State private var errors: [String: String] = [:]
    private var store: Store { .shared }
    private var ui: UIState { .shared }

    var body: some View {
        SheetFrame("Create a team", tall: true, close: { ui.closeSheet(.teamNew) }) {
            FieldView(label: "Team name", text: Binding(get: { name }, set: { name = String($0.prefix(30)) }), placeholder: "Sunday Squad", err: errors["name"], autocap: true)
            HStack(alignment: .top, spacing: 10) {
                dateField("Start date", $start, errors["start"])
                dateField("End date", $end, errors["end"])
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Invite friends").font(.barlow(13, 700)).foregroundStyle(Theme.text2)
                let friends = store.data?.friends ?? []
                if friends.isEmpty {
                    Note(.plain, "No friends yet. You can still create the team and invite people later.")
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(friends, id: \.self) { u in
                            if let p = store.person(u) {
                                PickFriend(photo: p.photo, name: u, on: members.contains(u)) {
                                    if members.contains(u) { members.removeAll { $0 == u } } else { members.append(u) }
                                }
                            }
                        }
                    }
                }
            }
        } foot: {
            Button("Create team") { create() }.buttonStyle(.btn(.primary, full: true))
        }
    }

    private func dateField(_ label: String, _ value: Binding<Date>, _ err: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.barlow(13, 700)).foregroundStyle(Theme.text2)
            DatePicker("", selection: value, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).frame(height: 48)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(err != nil ? Theme.loss : Theme.stroke, lineWidth: 1))
            if let err { Text(err).font(.barlow(12.5, 600)).foregroundStyle(Theme.loss) }
        }
        .frame(maxWidth: .infinity)
    }

    private func create() {
        do {
            let t = try store.createTeam(name: name, start: TO.dayKey(TO.ms(start)), end: TO.dayKey(TO.ms(end)), members: members)
            ui.closeSheet(.teamNew)
            let invited = t.members.count - 1
            ui.toast(.win, "\(t.name) created", invited > 0 ? "\(invited) friend\(invited == 1 ? "" : "s") invited." : "You can invite friends from the team.")
            SocialModel.shared.tab = "teams"
        } catch let e as AppError {
            errors = e.fields
        } catch {}
    }
}

struct InviteSheet: View {
    var body: some View {
        let p = Invites.pending
        let who = (p?.invite.isEmpty ?? true) ? "Someone" : "@\(p!.invite)"
        let joining = p != nil && !p!.team.isEmpty && !p!.teamName.isEmpty
        SheetFrame(joining ? "Join \(p!.teamName)" : "Friend link", close: { UIState.shared.closeSheet(.invite) }) {
            if joining {
                let dates = !p!.start.isEmpty && !p!.end.isEmpty ? ", \(Fmt.date(TO.dayStart(p!.start))) – \(Fmt.date(TO.dayStart(p!.end)))" : ""
                (Text("\(who) invited you to ") + Text(p!.teamName).bold().foregroundStyle(Theme.text) + Text("\(dates). Joining also adds them as a friend. It is still screen time, not money."))
                    .font(.barlow(14.5)).foregroundStyle(Theme.text2)
            } else {
                Text("\(who) sent you their TimeOut link. Add them as a friend to compare screen time instead of betting money.")
                    .font(.barlow(14.5)).foregroundStyle(Theme.text2)
            }
        } foot: {
            Button(joining ? "Add friend and join" : "Add friend") { Invites.accept() }.buttonStyle(.btn(.primary, full: true))
            Button("Not now") { UIState.shared.closeSheet(.invite) }.buttonStyle(.btn(.quiet, .sm, full: true))
        }
    }
}
