import SwiftUI

/// Main list view for all drones.
struct EquipmentListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showAddDroneSheet = false

    var body: some View {
        Group {
            if viewModel.drones.isEmpty {
                ContentUnavailableView(
                    "No Equipment",
                    systemImage: "airplane.circle",
                    description: Text("Tap the + button to add your first drone.")
                )
            } else {
                List {
                    ForEach(viewModel.drones) { drone in
                        NavigationLink(destination: DroneDetailView(drone: drone)) {
                            VStack(alignment: .leading) {
                                Text(drone.displayName).font(.headline)
                                Text(drone.faaRegistration).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: viewModel.deleteDrone)
                }
            }
        }
        .navigationTitle("My Equipment")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddDroneSheet.toggle() }) {
                    Image(systemName: "plus.circle.fill").font(.title)
                }
            }
        }
        .sheet(isPresented: $showAddDroneSheet) {
            AddEditDroneView(droneToEdit: nil)
        }
    }
}

/// A view for adding a new drone or editing an existing one.
struct AddEditDroneView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var drone: Drone
    let isEditing: Bool
    /// A closure to handle saving, used by the setup flow.
    var onSave: ((Drone) -> Void)?

    init(droneToEdit: Drone?, onSave: ((Drone) -> Void)? = nil) {
        if let existingDrone = droneToEdit {
            _drone = State(initialValue: existingDrone)
            isEditing = true
        } else {
            _drone = State(initialValue: Drone(id: UUID(), company: "", model: "", faaRegistration: "", remoteIdSerial: ""))
            isEditing = false
        }
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Drone Info") {
                    TextField("Company (e.g., DJI)", text: $drone.company)
                    TextField("Model (e.g., Mavic 3 Pro)", text: $drone.model)
                }
                Section("Identification") {
                    TextField("FAA Registration Number", text: $drone.faaRegistration)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                    TextField("Remote ID Serial Number (if applicable)", text: $drone.remoteIdSerial)
                }
            }
            .navigationTitle(isEditing ? "Edit Drone" : "Add Drone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let onSave = onSave {
                            onSave(drone)
                        } else {
                            viewModel.saveDrone(drone: drone)
                        }
                        dismiss()
                    }
                    .disabled(drone.company.isEmpty || drone.model.isEmpty || drone.faaRegistration.isEmpty)
                }
            }
        }
    }
}

/// A detailed, read-only view of a drone's information.
struct DroneDetailView: View {
    let drone: Drone
    @State private var showEditSheet = false

    var body: some View {
        Form {
            Section("Drone Info") {
                InfoRow(label: "Company", value: drone.company)
                InfoRow(label: "Model", value: drone.model)
            }
            Section("Identification") {
                InfoRow(label: "FAA Registration", value: drone.faaRegistration)
                InfoRow(label: "Remote ID Serial", value: drone.remoteIdSerial)
            }
        }
        .navigationTitle(drone.displayName)
        .toolbar {
            Button("Edit") { showEditSheet.toggle() }
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditDroneView(droneToEdit: drone)
        }
    }
}
