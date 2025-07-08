import SwiftUI
import MapKit

/// The main list view for displaying all flight logs.
struct FlightLogListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var selectedLog: FlightLog?
    
    @Environment(\.appNavigationStyle) private var navigationStyle
    
    @State private var showTrashSheet = false

    var body: some View {
        Group {
            if viewModel.groupedFlightLogs.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView("No Flights Logged", systemImage: "airplane.departure", description: Text("Tap the + button to add your first flight log."))
                } else {
                    LegacyContentUnavailableView {
                        Label("No Flights Logged", systemImage: "airplane.departure")
                    } description: {
                        Text("Tap the + button to add your first flight log.")
                    }
                }
            } else {
                List {
                    ForEach(viewModel.groupedFlightLogs) { section in
                        Section(header: Text(section.title).font(.headline)) {
                            ForEach(section.logs) { log in
                                // FIX: Removed the .listRowInsets modifier to allow the row to fill the available width.
                                NavigationLink(value: log) {
                                   FlightLogRowView(log: log)
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) // Adjust vertical padding if needed, but keep horizontal at 0.
                            }
                            .onDelete { indexSet in
                                let logsToDelete = indexSet.map { section.logs[$0] }
                                for log in logsToDelete {
                                    viewModel.moveLogToTrash(log: log)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Flight Logbook")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if currentDeviceType == .iPad {
                    Button(action: { showTrashSheet.toggle() }) {
                        Image(systemName: "trash")
                    }
                } else {
                    NavigationLink(destination: TrashView()) {
                        Image(systemName: "trash")
                    }
                }
                
                Button(action: viewModel.startNewLog) {
                    Image(systemName: "plus.circle.fill").font(.title)
                }
                .disabled(viewModel.drones.isEmpty)
            }
        }
        .sheet(isPresented: $showTrashSheet) {
            NavigationView {
                TrashView()
            }
        }
        .sheet(isPresented: $viewModel.isLoggingFlight) {
            FlightLoggingContainerView()
        }
        .navigationDestination(for: FlightLog.self) { log in
            FlightDetailView(log: log)
        }
    }
}

/// A vibrant, gradient-based card view for flight logs.
struct FlightLogRowView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let log: FlightLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(viewModel.droneForID(log.aircraftID)?.displayName ?? "Unknown Aircraft")
                        .font(.title3.bold())
                    Text(log.location)
                        .font(.caption)
                        .opacity(0.8)
                }
                Spacer()
                Image(systemName: "airplane.departure")
                    .font(.largeTitle)
                    .opacity(0.3)
            }

            Spacer()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Text("DATE")
                        .font(.caption2.weight(.semibold))
                        .opacity(0.8)
                    Text(log.date, style: .date)
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("DURATION")
                        .font(.caption2.weight(.semibold))
                        .opacity(0.8)
                    Text(Formatters.durationAbbreviated.string(from: log.flightDuration) ?? "0s")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding()
        .frame(height: 120)
        .foregroundColor(.white)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.blue, .accentColor.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

/// A new view to display and manage trashed flight logs.
struct TrashView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.trashedFlightLogs.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "Trash is Empty",
                        systemImage: "trash.slash.fill",
                        description: Text("Discarded flights will appear here. Items are automatically deleted after 30 days.")
                    )
                } else {
                    LegacyContentUnavailableView {
                        Label("Trash is Empty", systemImage: "trash.slash.fill")
                    } description: {
                        Text("Discarded flights will appear here. Items are automatically deleted after 30 days.")
                    }
                }
            } else {
                List {
                    ForEach(viewModel.trashedFlightLogs) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.droneForID(log.aircraftID)?.displayName ?? "Unknown Aircraft")
                                .font(.headline)
                            Text(log.location)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if let trashedDate = log.trashedDate {
                                Text("Discarded: \(trashedDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    if let index = viewModel.trashedFlightLogs.firstIndex(where: { $0.id == log.id }) {
                                        viewModel.restoreLogFromTrash(at: IndexSet(integer: index))
                                    }
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward.circle.fill")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    if let index = viewModel.trashedFlightLogs.firstIndex(where: { $0.id == log.id }) {
                                        viewModel.deleteLogPermanently(at: IndexSet(integer: index))
                                    }
                                }
                            } label: {
                                Label("Delete", systemImage: "xmark.bin.fill")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// A detailed, read-only view of a completed flight log.
struct FlightDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let log: FlightLog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Flight Information").font(.headline).foregroundStyle(.secondary)
                StyledSection {
                    InfoRow(label: "Aircraft", value: viewModel.droneForID(log.aircraftID)?.displayName ?? "N/A")
                    Divider()
                    InfoRow(label: "Location", value: log.location)
                    Divider()
                    InfoRow(label: "Date", value: log.date.formatted(date: .long, time: .shortened))
                    Divider()
                    InfoRow(label: "Total Duration", value: Formatters.durationPositional.string(from: log.flightDuration) ?? "00:00:00")
                    Divider()
                    InfoRow(label: "Pilot in Command", value: log.pilotInCommand)
                }

                if let clientInfo = log.clientInfo, !clientInfo.clientName.isEmpty {
                    Text("Client & Project").font(.headline).foregroundStyle(.secondary)
                    StyledSection {
                        InfoRow(label: "Client Name", value: clientInfo.clientName)
                        Divider()
                        InfoRow(label: "Project ID", value: clientInfo.projectID)
                        Divider()
                        InfoRow(label: "Contact Info", value: clientInfo.contactInfo)
                    }
                }
                
                if let flightArea = log.flightArea, !flightArea.boundary.isEmpty {
                    Text("Flight Area").font(.headline).foregroundStyle(.secondary)
                    StyledSection {
                        if #available(iOS 17.0, *) {
                            if let region = MKCoordinateRegion(coordinates: flightArea.boundary.map { $0.clLocationCoordinate2D }) {
                                Map(initialPosition: .region(region)) {
                                    let coordinates = flightArea.boundary.map { $0.clLocationCoordinate2D }
                                    MapPolygon(coordinates: coordinates)
                                        .foregroundStyle(.blue.opacity(0.3))
                                    MapPolygon(coordinates: coordinates)
                                        .stroke(.blue, lineWidth: 2)
                                }
                                .frame(height: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .allowsHitTesting(false)
                            }
                        } else {
                            var points = flightArea.boundary.map { $0.clLocationCoordinate2D }
                            LegacyMapView(drawnPoints: .constant(points), userLocation: .constant(nil), isInteractive: false)
                                .frame(height: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .disabled(true)
                        }
                        
                        Divider()
                        InfoRow(label: "Max AGL", value: "\(Int(flightArea.maxAGL)) ft")
                    }
                }

                if !log.segments.isEmpty {
                    Text("Flight Segments").font(.headline).foregroundStyle(.secondary)
                    StyledSection {
                        ForEach(log.segments) { segment in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Takeoff: \(segment.startTime.formatted(date: .omitted, time: .standard))")
                                    Spacer()
                                    if let endTime = segment.endTime {
                                        Text("Landing: \(endTime.formatted(date: .omitted, time: .standard))")
                                    }
                                }
                                Text("Duration: \(Formatters.durationPositional.string(from: segment.duration) ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if segment.id != log.segments.last?.id { Divider() }
                        }
                    }
                }

                if !log.crew.isEmpty {
                    Text("Additional Crew").font(.headline).foregroundStyle(.secondary)
                    StyledSection {
                        ForEach(log.crew) { member in
                            InfoRow(label: member.roleName, value: member.personName)
                            if member.id != log.crew.last?.id { Divider() }
                        }
                    }
                }

                if !log.completedChecklist.isEmpty {
                    Text("Pre-flight Checklist").font(.headline).foregroundStyle(.secondary)
                    StyledSection {
                        ForEach(log.completedChecklist) { item in
                            HStack {
                                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "x.circle.fill")
                                    .foregroundStyle(item.isChecked ? .green : .red)
                                Text(item.text)
                                    .strikethrough(item.isChecked)
                                Spacer()
                                if let completionDate = item.completionDate {
                                    Text(completionDate, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if item.id != log.completedChecklist.last?.id { Divider() }
                        }
                    }
                }

                if !log.loggedRemoteIDs.isEmpty {
                    Text("Detected Remote ID Telemetry").font(.headline).foregroundStyle(.secondary)
                    StyledSection {
                        ForEach(log.loggedRemoteIDs) { rid in
                            NavigationLink(destination: LoggedIDDetailView(loggedID: rid)) {
                               HStack {
                                   VStack(alignment: .leading) {
                                       Text(rid.displayName).bold()
                                       Text("Telemetry Points: \(rid.telemetry.count)")
                                           .font(.caption)
                                           .foregroundStyle(.secondary)
                                   }
                                   Spacer()
                                   Image(systemName: "chevron.right").foregroundStyle(.secondary)
                               }
                            }
                            .foregroundStyle(.primary)
                            if rid.id != log.loggedRemoteIDs.last?.id { Divider() }
                        }
                    }
                }
                
                Text("Mission Notes").font(.headline).foregroundStyle(.secondary)
                StyledSection {
                    Text(log.missionNotes.isEmpty ? "No notes." : log.missionNotes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Weather Conditions").font(.headline).foregroundStyle(.secondary)
                StyledSection {
                    InfoRow(label: "Raw METAR", value: log.weather.metar, multiline: true)
                    Divider()
                    InfoRow(label: "Decoded", value: log.weather.decodedMetar, multiline: true)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Flight Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A view showing the full telemetry log for a single detected drone.
struct LoggedIDDetailView: View {
    let loggedID: LoggedRemoteID

    var body: some View {
        Form {
            Section("Identification") {
                InfoRow(label: "Registration / Serial Number", value: loggedID.basicID?.uasID ?? "N/A")
                InfoRow(label: "ID Type", value: loggedID.basicID?.idType ?? "N/A")
            }

            Section("Full Telemetry Log (\(loggedID.telemetry.count) records)") {
                List(loggedID.telemetry, id: \.self) { record in
                    TelemetryRow(record: record)
                }
            }
        }
        .navigationTitle(loggedID.basicID?.uasID ?? "Log Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A single row in the telemetry log view.
struct TelemetryRow: View {
    let record: TelemetryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(Formatters.telemetryTime.string(from: record.timestamp))
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text("\(record.rssi) dBm")
                    .font(.caption)
                    .foregroundColor(rssiColor(record.rssi))
            }
            Text(String(format: "Lat: %.5f, Lon: %.5f", record.location.latitude, record.location.longitude))
            Text(String(format: "Alt (AGL): %.1f m, Speed: %.1f m/s, Hdg: %d°", record.location.height ?? 0, record.location.speedHorizontal, Int(record.location.direction)))
        }
        .font(.footnote)
    }
}
