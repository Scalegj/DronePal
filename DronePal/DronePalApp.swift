import SwiftUI

@main
struct DronePalApp: App {
    /// The single instance of the AppViewModel, which acts as the source of truth for the app.
    /// It's created once here and passed into the environment.
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
