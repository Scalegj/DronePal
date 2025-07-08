import SwiftUI

/// The main container view for the iPad, with robust adaptive navigation.
struct iPadMainView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    // State to manage the selected item in each list for landscape mode.
    @State private var selectedLog: FlightLog?
    @State private var selectedDrone: Drone?
    @State private var selectedChecklist: Checklist?

    var body: some View {
        GeometryReader { geometry in
            TabView {
                // MARK: - Logbook Tab
                adaptiveLogbookView(geometry: geometry)
                    .tabItem { Label("Logbook", systemImage: "book.closed.fill") }

                // MARK: - Equipment Tab
                adaptiveEquipmentView(geometry: geometry)
                    .tabItem { Label("Equipment", systemImage: "airplane.circle.fill") }

                // MARK: - Checklists Tab
                adaptiveChecklistView(geometry: geometry)
                    .tabItem { Label("Checklists", systemImage: "checklist") }
                
                // MARK: - Scanner Tab
                NavigationStack {
                    RemoteIDScannerView()
                }
                .tabItem { Label("Scanner", systemImage: "antenna.radiowaves.left.and.right") }

                // MARK: - Stats Tab
                NavigationStack {
                    StatsView()
                }
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
            }
        }
        .sheet(isPresented: $viewModel.isLoggingFlight) {
            FlightLoggingContainerView()
        }
    }
    
    /// Returns the correct navigation view for the Logbook tab based on orientation.
    @ViewBuilder
    private func adaptiveLogbookView(geometry: GeometryProxy) -> some View {
        if geometry.size.height > geometry.size.width {
            NavigationStack {
                FlightLogListView(selectedLog: .constant(nil))
            }
            // FIX: Set the environment value to ensure the list knows it's in a stack.
            .environment(\.appNavigationStyle, .stack)
        } else {
            NavigationSplitView {
                FlightLogListView(selectedLog: $selectedLog)
            } detail: {
                if let log = selectedLog {
                    FlightDetailView(log: log)
                } else {
                    Text("Select a flight to see its details.")
                        .foregroundStyle(.secondary)
                }
            }
            .environment(\.appNavigationStyle, .split)
        }
    }
    
    /// Returns the correct navigation view for the Equipment tab.
    @ViewBuilder
    private func adaptiveEquipmentView(geometry: GeometryProxy) -> some View {
        if geometry.size.height > geometry.size.width {
            NavigationStack {
                EquipmentListView(selectedDrone: .constant(nil))
            }
            .environment(\.appNavigationStyle, .stack)
        } else {
            NavigationSplitView {
                EquipmentListView(selectedDrone: $selectedDrone)
            } detail: {
                if let drone = selectedDrone {
                    DroneDetailView(drone: drone)
                } else {
                    Text("Select a drone to see its details.")
                        .foregroundStyle(.secondary)
                }
            }
            .environment(\.appNavigationStyle, .split)
        }
    }
    
    /// Returns the correct navigation view for the Checklists tab.
    @ViewBuilder
    private func adaptiveChecklistView(geometry: GeometryProxy) -> some View {
        if geometry.size.height > geometry.size.width {
            NavigationStack {
                ChecklistListView(selectedChecklist: .constant(nil))
            }
            .environment(\.appNavigationStyle, .stack)
        } else {
            NavigationSplitView {
                ChecklistListView(selectedChecklist: $selectedChecklist)
            } detail: {
                if let checklist = selectedChecklist {
                    ChecklistDetailView(checklist: checklist)
                } else {
                    Text("Select a checklist to see its details.")
                        .foregroundStyle(.secondary)
                }
            }
            .environment(\.appNavigationStyle, .split)
        }
    }
}
