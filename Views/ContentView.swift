import SwiftUI

/// The root view of the application, containing the main TabView.
struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        // FIX: Add a loading view to prevent the setup screen from flashing on launch.
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
            TabView {
                NavigationStack { FlightLogListView() }
                    .tabItem { Label("Logbook", systemImage: "book.closed.fill") }

                NavigationStack { EquipmentListView() }
                    .tabItem { Label("Equipment", systemImage: "airplane.circle.fill") }

                NavigationStack { ChecklistListView() }
                    .tabItem { Label("Checklists", systemImage: "checklist") }

                NavigationStack { RemoteIDScannerView() }
                    .tabItem { Label("Scanner", systemImage: "antenna.radiowaves.left.and.right") }

                NavigationStack { StatsView() }
                    .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
            }
        }
    }
}
