import SwiftUI

/// A view for displaying user statistics and editing global settings.
struct StatsView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Flight Time") {
                HStack {
                    Text("Total Logged Time")
                    Spacer()
                    Text(formatDuration(viewModel.totalFlightTime))
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section("Pilot Settings") {
                TextField("Pilot Name", text: $viewModel.userSettings.pilotName)
                    // <-- FIXED: Updated to modern onChange syntax.
                    .onChange(of: viewModel.userSettings.pilotName) {
                        viewModel.saveUserSettings()
                    }
                
                Picker("Pilot Type", selection: $viewModel.userSettings.pilotType) {
                    ForEach(PilotType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                // <-- FIXED: Updated to modern onChange syntax.
                .onChange(of: viewModel.userSettings.pilotType) {
                    viewModel.saveUserSettings()
                }
            }

            if viewModel.userSettings.pilotType == .part107 {
                part107Section
            } else {
                recreationalSection
            }
        }
        .navigationTitle("Stats & Settings")
    }
    
    private var part107Section: some View {
        Group {
            Section("Part 107 Certificate") {
                DatePicker(
                    "Initial Issue Date",
                    selection: $viewModel.userSettings.part107InitialCertificateDate,
                    displayedComponents: .date
                )
                // <-- FIXED: Updated to modern onChange syntax.
                .onChange(of: viewModel.userSettings.part107InitialCertificateDate) {
                    viewModel.saveUserSettings()
                }
                InfoRow(label: "Status", value: "Certificate does not expire.")
            }

            Section("Recurrent Training") {
                DatePicker(
                    "Last Training/Exam Date",
                    selection: $viewModel.userSettings.part107LastRecurrencyDate,
                    displayedComponents: .date
                )
                // <-- FIXED: Updated to modern onChange syntax.
                .onChange(of: viewModel.userSettings.part107LastRecurrencyDate) {
                    viewModel.saveUserSettings()
                }
                
                if let expirationDate = viewModel.recurrencyExpirationDate, let daysRemaining = viewModel.daysUntilRecurrencyExpires {
                    InfoRow(label: "Training Expires On", value: expirationDate.formatted(date: .long, time: .omitted))
                    HStack {
                        if daysRemaining <= 0 {
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            Text("Recurrent Training Expired").bold().foregroundStyle(.red)
                        } else if daysRemaining <= 90 {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text("\(daysRemaining) days remaining").bold().foregroundStyle(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("\(daysRemaining) days remaining").bold()
                        }
                    }
                }
            }
        }
    }
    
    private var recreationalSection: some View {
        Section("Recreational Pilot (TRUST)") {
            DatePicker(
                "TRUST Completion Date",
                selection: $viewModel.userSettings.recreationalTRUSTDate,
                displayedComponents: .date
            )
            // <-- FIXED: Updated to modern onChange syntax.
            .onChange(of: viewModel.userSettings.recreationalTRUSTDate) {
                viewModel.saveUserSettings()
            }
            InfoRow(label: "Status", value: "The Recreational UAS Safety Test (TRUST) does not expire.")
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        return formatter.string(from: duration) ?? "0 hours"
    }
}
