import SwiftUI
import ParkLifeCore

@main
struct ParkLifeApp: App {

    @StateObject private var session = GameSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.light)
        }
    }
}
