import SwiftUI

/// A helper to easily identify the current device type.
enum DeviceType {
    case iPhone
    case iPad
}

/// Determines the current device type based on the user interface idiom.
var currentDeviceType: DeviceType {
    UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
}

/// The root view of the application, which selects the appropriate UI for the device.
struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        if viewModel.isLoading {
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Syncing with iCloud...")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.needsSetup {
            SetupView()
        } else {
            // Display the appropriate main view based on the device type.
            switch currentDeviceType {
            case .iPad:
                iPadMainView()
            case .iPhone:
                iPhoneMainView()
            }
        }
    }
}

/// The main TabView-based interface for iPhone.
struct iPhoneMainView: View {
    var body: some View {
        TabView {
            NavigationStack { FlightLogListView(selectedLog: .constant(nil)) }
                .tabItem { Label("Logbook", systemImage: "book.closed.fill") }

            NavigationStack { EquipmentListView(selectedDrone: .constant(nil)) }
                .tabItem { Label("Equipment", systemImage: "airplane.circle.fill") }

            NavigationStack { ChecklistListView(selectedChecklist: .constant(nil)) }
                .tabItem { Label("Checklists", systemImage: "checklist") }

            NavigationStack { RemoteIDScannerView() }
                .tabItem { Label("Scanner", systemImage: "antenna.radiowaves.left.and.right") }

            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
        }
    }
}
