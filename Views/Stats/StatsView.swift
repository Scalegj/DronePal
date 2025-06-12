import SwiftUI

/// A dashboard view for displaying user statistics and accessing global settings.
struct StatsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showAddRoleSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Dashboard")
                        .font(.largeTitle.bold())
                        .padding([.horizontal, .top])

                    VStack(spacing: 16) {
                        StatCardView(
                            title: "Total Flight Time",
                            value: formatDuration(viewModel.totalFlightTime),
                            icon: "hourglass",
                            color: .blue
                        )
                        if viewModel.userSettings.pilotType == .part107 {
                            recurrencyCard
                        } else {
                            recreationalCard
                        }
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Pilot Information").font(.headline).foregroundStyle(.secondary)
                        StyledSection {
                            TextField("Pilot Name", text: $viewModel.userSettings.pilotName)
                            Divider()
                            Picker("Pilot Type", selection: $viewModel.userSettings.pilotType) {
                                ForEach(PilotType.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        if viewModel.userSettings.pilotType == .part107 {
                            Text("Part 107 Certificate Dates").font(.headline).foregroundStyle(.secondary)
                            StyledSection {
                                DatePicker("Initial Issue Date", selection: $viewModel.userSettings.part107InitialCertificateDate, displayedComponents: .date)
                                Divider()
                                DatePicker("Last Training/Exam Date", selection: $viewModel.userSettings.part107LastRecurrencyDate, displayedComponents: .date)
                            }
                        } else {
                            Text("Recreational Pilot (TRUST)").font(.headline).foregroundStyle(.secondary)
                            StyledSection {
                                DatePicker("TRUST Completion Date", selection: $viewModel.userSettings.recreationalTRUSTDate, displayedComponents: .date)
                            }
                        }

                        Text("Default Crew Roles").font(.headline).foregroundStyle(.secondary)
                        StyledSection {
                            ForEach(viewModel.userSettings.customCrewRoles) { role in
                                HStack {
                                    Text(role.name)
                                    Spacer()
                                    Button(action: {
                                        viewModel.deleteCrewRole(roleToDelete: role)
                                    }) {
                                        Image(systemName: "trash.circle.fill")
                                            .foregroundColor(.red)
                                            .imageScale(.large)
                                    }
                                    .buttonStyle(.plain)
                                }
                                if role.id != viewModel.userSettings.customCrewRoles.last?.id {
                                    Divider()
                                }
                            }
                            
                            // **FIX**: Styled this button to match the Pre-Flight screen.
                            Button(action: { showAddRoleSheet.toggle() }) {
                                HStack {
                                    Label("Add New Default Role", systemImage: "plus.circle.fill")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .foregroundColor(.accentColor) // Make text and icon blue
                            }
                            .padding(.top, 8)
                        }

                    }
                    .padding()
                }
                .padding(.bottom)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stats & Settings")
            .toolbar {
            }
            .onDisappear {
                viewModel.saveUserSettings()
            }
            .sheet(isPresented: $showAddRoleSheet) {
                AddNewRoleView()
            }
        }
    }
    
    @ViewBuilder
    private var recurrencyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Part 107 Recurrency", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                if let days = viewModel.daysUntilRecurrencyExpires, days <= 90 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(days <= 30 ? .red : .orange)
                }
            }
            if let days = viewModel.daysUntilRecurrencyExpires {
                Text("Your recurrent training is due in **\(days) days**.")
                    .font(.subheadline)
            }
            if let expirationDate = viewModel.recurrencyExpirationDate {
                Text("Expires on \(expirationDate.formatted(date: .long, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    @ViewBuilder
    private var recreationalCard: some View {
        StatCardView(
            title: "TRUST Certificate",
            value: "DOES NOT EXPIRE",
            icon: "checkmark.shield.fill",
            color: .green
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0h 0m"
    }
}

/// A dedicated sheet view for adding a new default crew role.
private struct AddNewRoleView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var newRoleName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("New Role Details")) {
                    TextField("Role Name (e.g., Sensor Operator)", text: $newRoleName)
                }
            }
            .navigationTitle("Add Default Role")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !newRoleName.isEmpty {
                            viewModel.addCrewRole(name: newRoleName)
                            dismiss()
                        }
                    }
                    .disabled(newRoleName.isEmpty)
                }
            }
        }
    }
}


private struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title, design: .rounded).bold())
            }
            Spacer()
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(color)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
