import SwiftUI

@main
struct DronePalApp: App {
    /// The single instance of the AppViewModel, which acts as the source of truth for the app.
    @StateObject private var viewModel = AppViewModel()
    
    // Use the delegate adaptor to integrate the AppDelegate for push notifications.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
