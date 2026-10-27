import SwiftUI

@main
struct TimeOutApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { AppModel.shared.handle(url: $0) }
        }
        .backgroundTask(.appRefresh(AppModel.backgroundTaskID)) {
            await AppModel.shared.backgroundRefresh()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: AppModel.shared.start()
            case .background: AppModel.shared.didEnterBackground()
            default: break
            }
        }
    }
}
