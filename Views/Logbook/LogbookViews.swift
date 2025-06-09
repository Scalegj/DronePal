import SwiftUI
import MapKit // <-- ADDED: To display the map

/// The main list view for displaying all flight logs.
struct FlightLogListView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.activeFlightLogs.isEmpty {
                ContentUnavailableView("No Flights Logged", systemImage: "airplane.departure", description: Text("Tap the + button to add your first flight log."))
            } else {
                List {
                    ForEach(viewModel.activeFlightLogs) { log in
                        NavigationLink(destination: FlightDetailView(log: log)) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(viewModel.droneForID(log.aircraftID)?.displayName ?? "Unknown Aircraft")
                                    .font(.headline)
                                Text(log.location)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Image(systemName: "calendar")
                                    Text(log.date, style: .date)
                                    Spacer()
                                    Image(systemName: "clock")
                                    Text(Formatters.durationAbbreviated.string(from: log.flightDuration) ?? "0s")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .onDelete(perform: viewModel.moveLogToTrash)
                }
            }
        }
        .navigationTitle("Flight Logbook")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                HStack {
                    NavigationLink(destination: TrashView()) {
                        Image(systemName: "trash")
                    }
                    
                    Button(action: viewModel.startNewLog) {
                        Image(systemName: "plus.circle.fill").font(.title)
                    }
                    .disabled(viewModel.drones.isEmpty)
                }
            }
        }
        .sheet(isPresented: $viewModel.isLoggingFlight) {
            FlightLoggingContainerView()
        }
    }
}

/// A new view to display and manage trashed flight logs.
struct TrashView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.trashedFlightLogs.isEmpty {
                ContentUnavailableView(
                    "Trash is Empty",
                    systemImage: "trash.slash.fill",
                    description: Text("Discarded flights will appear here. Items are automatically deleted after 30 days.")
                )
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
        Form {
            Section("Flight Information") {
                InfoRow(label: "Aircraft", value: viewModel.droneForID(log.aircraftID)?.displayName ?? "N/A")
                InfoRow(label: "Location", value: log.location)
                InfoRow(label: "Date", value: log.date.formatted(date: .long, time: .shortened))
                InfoRow(label: "Total Duration", value: Formatters.durationPositional.string(from: log.flightDuration) ?? "00:00:00")
                InfoRow(label: "Pilot in Command", value: log.pilotInCommand)
            }

            if let flightArea = log.flightArea, !flightArea.boundary.isEmpty {
                Section("Flight Area") {
                    // <-- FIX: Safely unwrap the failable initializer.
                    if let region = MKCoordinateRegion(coordinates: flightArea.boundary.map { $0.clLocationCoordinate2D }) {
                        Map(initialPosition: .region(region)) {
                            let coordinates = flightArea.boundary.map { $0.clLocationCoordinate2D }
                            MapPolygon(coordinates: coordinates)
                                .foregroundStyle(.blue.opacity(0.3))
                            MapPolygon(coordinates: coordinates)
                                .stroke(.blue, lineWidth: 2)
                        }
                        .frame(height: 250)
                        .listRowInsets(EdgeInsets())
                        .allowsHitTesting(false)

                        InfoRow(label: "Max AGL", value: "\(Int(flightArea.maxAGL)) ft")
                    }
                }
            }

            if !log.segments.isEmpty {
                Section("Flight Segments") {
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
                    }
                }
            }

            if (log.pmtcBy != nil && !log.pmtcBy!.isEmpty) || (log.visualObserver != nil && !log.visualObserver!.isEmpty) {
                Section("Additional Crew") {
                    if let pmtc = log.pmtcBy, !pmtc.isEmpty { InfoRow(label: "PMTC By", value: pmtc) }
                    if let vo = log.visualObserver, !vo.isEmpty { InfoRow(label: "Visual Observer", value: vo) }
                }
            }

            if !log.completedChecklist.isEmpty {
                Section("Pre-flight Checklist") {
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
                    }
                }
            }

            if !log.loggedRemoteIDs.isEmpty {
                Section("Detected Remote ID Telemetry") {
                    ForEach(log.loggedRemoteIDs) { rid in
                        NavigationLink(destination: LoggedIDDetailView(loggedID: rid)) {
                           VStack(alignment: .leading) {
                               Text(rid.displayName).bold()
                               Text("Telemetry Points: \(rid.telemetry.count)")
                                   .font(.caption)
                                   .foregroundStyle(.secondary)
                           }
                        }
                    }
                }
            }

            Section("Mission Notes") {
                Text(log.missionNotes.isEmpty ? "No notes." : log.missionNotes)
            }

            Section("Weather Conditions") {
                InfoRow(label: "Raw METAR", value: log.weather.metar, multiline: true)
                InfoRow(label: "Decoded", value: log.weather.decodedMetar, multiline: true)
            }
        }
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
