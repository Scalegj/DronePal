import SwiftUI

/// A dashboard view for displaying user statistics and accessing global settings.
struct StatsView: View {
    @EnvironmentObject var viewModel: AppViewModel

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
                                .onChange(of: viewModel.userSettings.pilotName) { viewModel.saveUserSettings() }
                            Divider()
                            Picker("Pilot Type", selection: $viewModel.userSettings.pilotType) {
                                ForEach(PilotType.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: viewModel.userSettings.pilotType) { viewModel.saveUserSettings() }
                        }
                        
                        if viewModel.userSettings.pilotType == .part107 {
                            Text("Part 107 Certificate Dates").font(.headline).foregroundStyle(.secondary)
                            StyledSection {
                                DatePicker("Initial Issue Date", selection: $viewModel.userSettings.part107InitialCertificateDate, displayedComponents: .date)
                                    .onChange(of: viewModel.userSettings.part107InitialCertificateDate) { viewModel.saveUserSettings() }
                                Divider()
                                DatePicker("Last Training/Exam Date", selection: $viewModel.userSettings.part107LastRecurrencyDate, displayedComponents: .date)
                                    .onChange(of: viewModel.userSettings.part107LastRecurrencyDate) { viewModel.saveUserSettings() }
                            }
                        } else {
                            Text("Recreational Pilot (TRUST)").font(.headline).foregroundStyle(.secondary)
                            StyledSection {
                                DatePicker("TRUST Completion Date", selection: $viewModel.userSettings.recreationalTRUSTDate, displayedComponents: .date)
                                    .onChange(of: viewModel.userSettings.recreationalTRUSTDate) { viewModel.saveUserSettings() }
                            }
                        }
                    }
                    .padding()
                }
                .padding(.bottom)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stats & Settings")
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
