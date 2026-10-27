import Foundation
import Network
import Observation
import SwiftUI

/// Connectivity, like the web demo's `TO.net`.
@Observable
final class Net {
    static let shared = Net()
    private(set) var online = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    func start() {
        monitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            Task { @MainActor in
                let was = Net.shared.online
                Net.shared.online = up
                if was != up { AppModel.shared.netChanged() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "timeout.net"))
    }

    /// For actions that need a connection (placing bets). False, with a toast, when offline.
    func guardOnline() -> Bool {
        if online { return true }
        UIState.shared.toast(.loss, "No internet connection", "Betting is paused until you're back online.")
        return false
    }
}

enum ToastKind { case win, loss, warn, info }

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var kind: ToastKind
    var title: String
    var msg: String
}

/// Bottom sheets (the web demo's `ui.sheet`).
enum SheetKind: Hashable {
    case slip, share(String), how, locked, profile(String), team(String), teamNew, teamHow, invite, screenTimeApps

    var tall: Bool {
        switch self {
        case .locked, .team, .teamNew, .screenTimeApps: return true
        default: return false
        }
    }
}

/// Full-screen pages that slide in over the shell (`ui.openPage`).
enum PageKind: Hashable { case game(String), parlay, settings(String) }

struct ConfirmRequest: Identifiable {
    let id = UUID()
    var title: String
    var body: AttributedString
    var confirm = "Confirm"
    var cancel: String? = "Cancel"
    var kind: BtnKind = .primary
    var resolve: (Bool) -> Void
}

/// Everything layered over the app: sheets, pages, the menu drawer, dialogs and toasts.
@Observable
final class UIState {
    static let shared = UIState()

    var tab = "home"
    private(set) var sheets: [SheetKind] = []
    private(set) var pages: [PageKind] = []
    var drawerOpen = false
    var dialog: ConfirmRequest?
    private(set) var toasts: [Toast] = []
    /// Bumped to scroll the current tab to the top.
    private(set) var scrollTopToken = 0
    /// Bumped to scroll Home's feed to the filter bar.
    private(set) var scrollFilterToken = 0
    /// Bumped to jump to the game page's markets ("Make a bet").
    private(set) var flashMarketsToken = 0

    // MARK: Toasts

    func toast(_ kind: ToastKind, _ title: String, _ msg: String = "", ms: Double = 4200) {
        let t = Toast(kind: kind, title: title, msg: msg)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            toasts.append(t)
            while toasts.count > 3 { toasts.removeFirst() }
        }
        let id = t.id
        Task {
            try? await Task.sleep(for: .milliseconds(ms))
            dismissToast(id)
        }
    }

    func dismissToast(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.25)) { toasts.removeAll { $0.id == id } }
    }

    // MARK: Dialogs

    func confirm(_ title: String, _ body: AttributedString, confirm: String = "Confirm", cancel: String? = "Cancel", kind: BtnKind = .primary) async -> Bool {
        await withCheckedContinuation { cont in
            dialog = ConfirmRequest(title: title, body: body, confirm: confirm, cancel: cancel, kind: kind) { ok in
                cont.resume(returning: ok)
            }
        }
    }

    func confirm(_ title: String, _ markdown: String, confirm: String = "Confirm", cancel: String? = "Cancel", kind: BtnKind = .primary) async -> Bool {
        await self.confirm(title, md(markdown), confirm: confirm, cancel: cancel, kind: kind)
    }

    func resolveDialog(_ ok: Bool) {
        guard let d = dialog else { return }
        dialog = nil
        d.resolve(ok)
    }

    // MARK: Sheets

    func sheetOpen(_ kind: SheetKind) -> Bool { sheets.contains(kind) }
    func sheetOpen(where test: (SheetKind) -> Bool) -> Bool { sheets.contains(where: test) }

    func openSheet(_ kind: SheetKind) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            sheets.removeAll { $0 == kind }
            sheets.append(kind)
        }
    }

    /// Closes a sheet. `silent` skips its close behavior (closing the bet slip normally throws the picks away).
    func closeSheet(_ kind: SheetKind, silent: Bool = false) {
        guard sheets.contains(kind) else { return }
        withAnimation(.easeOut(duration: 0.22)) { sheets.removeAll { $0 == kind } }
        if !silent { onClose(kind) }
    }

    func closeAllSheets() {
        for s in sheets { closeSheet(s) }
    }

    private func onClose(_ kind: SheetKind) {
        switch kind {
        case .slip: Slip.shared.discard()
        case .invite: Invites.clear()
        default: break
        }
    }

    // MARK: Pages

    func pageOpen(_ kind: PageKind) -> Bool { pages.contains(kind) }
    var topPage: PageKind? { pages.last }

    func openPage(_ kind: PageKind) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.92)) {
            pages.removeAll { $0 == kind || (sameType($0, kind)) }
            pages.append(kind)
        }
    }

    private func sameType(_ a: PageKind, _ b: PageKind) -> Bool {
        switch (a, b) {
        case (.game, .game), (.settings, .settings), (.parlay, .parlay): return true
        default: return false
        }
    }

    func closePage(_ kind: PageKind, silent: Bool = false) {
        guard pages.contains(kind) else { return }
        withAnimation(.easeOut(duration: 0.24)) { pages.removeAll { $0 == kind } }
        if !silent, kind == .parlay, !Slip.shared.legs.isEmpty, !sheetOpen(.slip) { Slip.shared.open() }
    }

    func closeAllPages() {
        withAnimation(.easeOut(duration: 0.2)) { pages.removeAll() }
    }

    /// Switches tabs (closing pages and the drawer) and scrolls to the top.
    func go(_ tab: String) {
        closeAllPages()
        drawerOpen = false
        self.tab = tab
        scrollTopToken += 1
    }

    func scrollToFilters() { scrollFilterToken += 1 }
    func flashMarkets() { flashMarketsToken += 1 }
}

/// Minimal markdown (**bold**, line breaks) for dialog bodies.
func md(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}
