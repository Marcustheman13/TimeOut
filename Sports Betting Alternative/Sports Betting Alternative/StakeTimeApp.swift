import SwiftUI

@main
struct StakeTimeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .backgroundTask(.appRefresh(BackgroundSettlement.taskID)) { [model] in
            await model.backgroundRefresh()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.start()
            case .background: model.didEnterBackground()
            default: break
            }
        }
    }
}
