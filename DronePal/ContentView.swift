import SwiftUI
import CoreBluetooth
import Combine
// MODIFICATION: Import the new Charts framework for data visualization.
import Charts
// MODIFICATION: Import the flutter-opendroneid library.
import flutter_opendroneid

// MARK: - Helper Extensions
extension Binding {
    init(_ source: Binding<Value?>, replacingNilWith nilValue: Value) {
        self.init(
            get: { source.wrappedValue ?? nilValue },
            set: { newValue in source.wrappedValue = newValue }
        )
    }
}

// MARK: - Models

struct FlightLog: Identifiable, Codable {
    let id: UUID
    var date: Date
    var aircraftID: UUID?
    var location: String
    var pilotInCommand: String
    var flightDuration: TimeInterval
    var missionNotes: String
    var weather: WeatherData
    var pmtcBy: String?
    var visualObserver: String?
    var loggedRemoteIDs: [LoggedRemoteID]?
    
    init(id: UUID = UUID(), date: Date = Date(), aircraftID: UUID? = nil, location: String = "", pilotInCommand: String = "", flightDuration: TimeInterval = 0, missionNotes: String = "", weather: WeatherData = WeatherData(), pmtcBy: String? = nil, visualObserver: String? = nil, loggedRemoteIDs: [LoggedRemoteID]? = nil) {
        self.id = id
        self.date = date
        self.aircraftID = aircraftID
        self.location = location
        self.pilotInCommand = pilotInCommand
        self.flightDuration = flightDuration
        self.missionNotes = missionNotes
        self.weather = weather
        self.pmtcBy = pmtcBy
        self.visualObserver = visualObserver
        self.loggedRemoteIDs = loggedRemoteIDs
    }
}

struct LoggedRemoteID: Identifiable, Codable, Hashable {
    let id: UUID // Peripheral identifier
    var basicID: ODIDBasicID?
    var telemetry: [TelemetryRecord]
    
    var displayName: String {
        basicID?.uasID ?? "Unknown ID"
    }
}

struct TelemetryRecord: Identifiable, Codable, Hashable {
    // MODIFICATION: Add identifiable conformance for use in Chart ForEach
    var id: Date { timestamp }
    let timestamp: Date
    let location: ODIDLocation
    let rssi: Int
}

struct Drone: Identifiable, Codable, Hashable {
    let id: UUID
    var company: String
    var model: String
    var faaRegistration: String
    var remoteIdSerial: String
    
    var displayName: String {
        "\(company) \(model)"
    }
}

struct WeatherData: Codable {
    var icao: String = ""
    var metar: String = "Not available"
    var decodedMetar: String = "No decoded data."
}

struct MetarReport: Codable {
    let rawOb: String
}

// MODIFICATION: These structs are now Codable and Hashable to be used in the app's data models.
// The properties are also adapted to be compatible with the flutter_opendroneid library's data structures.
struct ODIDBasicID: Codable, Hashable {
    var idType: String
    var uasID: String
}

struct ODIDLocation: Codable, Hashable {
    var status: String
    var direction: Double
    var speedHorizontal: Double
    var speedVertical: Double
    var latitude: Double
    var longitude: Double
    var altitudeGeodetic: Double
    var height: Double?
    var heightType: String
}

class RemoteIDDevice: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var rssi: NSNumber
    
    @Published var basicID: ODIDBasicID?
    @Published var location: ODIDLocation?

    init(from aircraft: Aircraft) {
        self.id = UUID(uuidString: aircraft.macAddress) ?? UUID()
        self.name = aircraft.macAddress // Or any other identifier from `aircraft`
        self.rssi = NSNumber(value: aircraft.rssi)
        
        if let basicIdData = aircraft.basicId {
            self.basicID = ODIDBasicID(
                idType: basicIdData.uasId.type.toString(),
                uasID: String(bytes: basicIdData.uasId.id, encoding: .utf8) ?? ""
            )
        }
        
        if let locationData = aircraft.location {
            self.location = ODIDLocation(
                status: locationData.status.toString(),
                direction: locationData.direction?.doubleValue ?? 0.0,
                speedHorizontal: locationData.speedHorizontal?.doubleValue ?? 0.0,
                speedVertical: locationData.speedVertical?.doubleValue ?? 0.0,
                latitude: locationData.latitude?.doubleValue ?? 0.0,
                longitude: locationData.longitude?.doubleValue ?? 0.0,
                altitudeGeodetic: locationData.altitudeGeo?.doubleValue ?? 0.0,
                height: locationData.height?.doubleValue,
                heightType: locationData.heightType.toString()
            )
        }
    }
}

// MARK: - Managers

// MODIFICATION: This new manager class will handle all the logic related to the flutter-opendroneid library.
class OpenDroneIDManager: NSObject, ObservableObject {
    @Published var discoveredDevices: [RemoteIDDevice] = []
    @Published var isScanning = false
    
    private let openDroneIdPlugin = SwiftFlutterOpendroneidPlugin()
    private var aircraftStreamHandler: AircraftStreamHandler?

    override init() {
        super.init()
        aircraftStreamHandler = AircraftStreamHandler { [weak self] aircraft in
            self?.handleAircraftUpdate(aircraft)
        }
        openDroneIdPlugin.setAircraftStreamHandler(handler: aircraftStreamHandler!)
    }
    
    func startScanning() {
        openDroneIdPlugin.startScan()
        isScanning = true
    }
    
    func stopScanning() {
        openDroneIdPlugin.stopScan()
        isScanning = false
    }
    
    private func handleAircraftUpdate(_ aircraft: Aircraft) {
        DispatchQueue.main.async {
            let newDevice = RemoteIDDevice(from: aircraft)
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == newDevice.id }) {
                self.discoveredDevices[index] = newDevice
            } else {
                self.discoveredDevices.append(newDevice)
            }
        }
    }
}

class AircraftStreamHandler: NSObject, FlutterStreamHandler {
    private let onAircraftReceived: (Aircraft) -> Void
    
    init(onAircraftReceived: @escaping (Aircraft) -> Void) {
        self.onAircraftReceived = onAircraftReceived
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // Not used in this implementation
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        // Not used in this implementation
        return nil
    }
    
    func onAircraftUpdate(_ aircraft: Aircraft) {
        onAircraftReceived(aircraft)
    }
}

// MARK: - ViewModels
class AppViewModel: ObservableObject {
    // MODIFICATION: The BluetoothScanner is replaced with the OpenDroneIDManager.
    @Published var openDroneIDManager = OpenDroneIDManager()

    @Published var flightLogs: [FlightLog] = []
    @Published var isLoggingFlight = false
    @Published var activeLog: FlightLog = FlightLog()
    @Published var timer: Timer?
    @Published var telemetryTimer: Timer?
    @Published var drones: [Drone] = []
    
    @Published var initialCertificateDate: Date {
        didSet { UserDefaults.standard.set(initialCertificateDate, forKey: certificateDateKey) }
    }
    @Published var lastRecurrencyDate: Date {
        didSet { UserDefaults.standard.set(lastRecurrencyDate, forKey: recurrencyDateKey) }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private let logbookStorageKey = "Part107Logbook_Logs_v10"
    private let droneStorageKey = "Part107Logbook_Drones_v10"
    private let certificateDateKey = "Part107Logbook_CertDate_v10"
    private let recurrencyDateKey = "Part107Logbook_RecurrencyDate_v10"

    init() {
        self.initialCertificateDate = UserDefaults.standard.object(forKey: certificateDateKey) as? Date ?? Date()
        self.lastRecurrencyDate = UserDefaults.standard.object(forKey: recurrencyDateKey) as? Date ?? Date()
        loadLogs()
        loadDrones()
        
        openDroneIDManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
    
    func startNewLog() {
        activeLog = FlightLog()
        activeLog.loggedRemoteIDs = []
        if let firstDrone = drones.first {
            activeLog.aircraftID = firstDrone.id
        }
        openDroneIDManager.startScanning()
        isLoggingFlight = true
        startTimer()
    }
    
    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.activeLog.flightDuration += 1 }
        
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordTelemetrySnapshot()
        }
    }
    
    // MODIFICATION: The recordTelemetrySnapshot function is updated to use the data from the OpenDroneIDManager.
    func recordTelemetrySnapshot() {
        let timestamp = Date()
        var updatedLoggedIDs = activeLog.loggedRemoteIDs ?? []

        for device in openDroneIDManager.discoveredDevices {
            if let index = updatedLoggedIDs.firstIndex(where: { $0.id == device.id }) {
                if let basicID = device.basicID {
                    updatedLoggedIDs[index].basicID = basicID
                }
                
                if let location = device.location {
                    let newRecord = TelemetryRecord(timestamp: timestamp, location: location, rssi: device.rssi.intValue)
                    updatedLoggedIDs[index].telemetry.append(newRecord)
                }
                
            } else {
                var newLoggedID = LoggedRemoteID(
                    id: device.id,
                    basicID: device.basicID,
                    telemetry: []
                )
                
                if let location = device.location {
                    let newRecord = TelemetryRecord(timestamp: timestamp, location: location, rssi: device.rssi.intValue)
                    newLoggedID.telemetry.append(newRecord)
                }
                
                updatedLoggedIDs.append(newLoggedID)
            }
        }

        if updatedLoggedIDs != activeLog.loggedRemoteIDs {
            activeLog.loggedRemoteIDs = updatedLoggedIDs
        }
    }
    
    func stopLogging() {
        timer?.invalidate()
        timer = nil
        
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        
        isLoggingFlight = false
        openDroneIDManager.stopScanning()
        saveLog(activeLog)
    }

    func saveLog(_ log: FlightLog) {
        if let index = flightLogs.firstIndex(where: { $0.id == log.id }) {
            flightLogs[index] = log
        } else {
            flightLogs.insert(log, at: 0)
        }
        
        do {
            let data = try JSONEncoder().encode(flightLogs)
            UserDefaults.standard.set(data, forKey: logbookStorageKey)
        } catch {
            print("Error saving logs: \(error.localizedDescription)")
        }
    }
    
    func loadLogs() {
        guard let data = UserDefaults.standard.data(forKey: logbookStorageKey) else { return }
        do {
            flightLogs = try JSONDecoder().decode([FlightLog].self, from: data)
        } catch {
            print("Error loading logs: \(error.localizedDescription)")
        }
    }
    
    func deleteLog(at offsets: IndexSet) {
        flightLogs.remove(atOffsets: offsets)
        saveLogs()
    }
    
    private func saveLogs() {
        do {
            let data = try JSONEncoder().encode(flightLogs)
            UserDefaults.standard.set(data, forKey: logbookStorageKey)
        } catch {
            print("Error saving logs: \(error.localizedDescription)")
        }
    }
    
    func droneForID(_ id: UUID?) -> Drone? {
        guard let id = id else { return nil }
        return drones.first { $0.id == id }
    }
    
    func saveDrone(drone: Drone) {
        if let index = drones.firstIndex(where: { $0.id == drone.id }) {
            drones[index] = drone
        } else {
            drones.append(drone)
        }
        saveDrones()
    }
    
    func loadDrones() {
        guard let data = UserDefaults.standard.data(forKey: droneStorageKey) else { return }
        do {
            drones = try JSONDecoder().decode([Drone].self, from: data)
        } catch {
            print("Error loading drones: \(error.localizedDescription)")
        }
    }
    
    func deleteDrone(at offsets: IndexSet) {
        drones.remove(atOffsets: offsets)
        saveDrones()
    }

    private func saveDrones() {
        do {
            let data = try JSONEncoder().encode(drones)
            UserDefaults.standard.set(data, forKey: droneStorageKey)
        } catch {
            print("Error saving drones: \(error.localizedDescription)")
        }
    }
    
    func fetchWeather() {
        guard !activeLog.weather.icao.isEmpty else { return }
        let icao = activeLog.weather.icao.uppercased()
        guard let url = URL(string: "https://aviationweather.gov/api/data/metar?ids=\(icao)&format=json") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Part 107 Logbook App", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data else {
                print("No data received: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                let metarReports = try JSONDecoder().decode([MetarReport].self, from: data)
                
                DispatchQueue.main.async {
                    if let report = metarReports.first {
                        self.activeLog.weather.metar = report.rawOb
                        self.activeLog.weather.decodedMetar = self.decodeMetar(raw: report.rawOb)
                    } else {
                        self.activeLog.weather.metar = "METAR not found for \(icao)"
                        self.activeLog.weather.decodedMetar = "No data available."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.activeLog.weather.metar = "Error fetching METAR for \(icao)"
                    self.activeLog.weather.decodedMetar = "Could not parse response."
                }
                print("Error fetching or parsing METAR: \(error.localizedDescription)")
            }
        }.resume()
    }

    private func decodeMetar(raw: String) -> String {
        var decodedParts: [String] = []
        var components = raw.split(separator: " ").map { String($0) }

        if !components.isEmpty { decodedParts.append("Station: \(components.removeFirst())") }

        if !components.isEmpty, components.first!.hasSuffix("Z") {
            let timeComponent = components.removeFirst()
            let day = timeComponent.prefix(2)
            let hour = timeComponent.dropFirst(2).prefix(2)
            let minute = timeComponent.dropFirst(4).prefix(2)
            decodedParts.append("Time: Day \(day) at \(hour):\(minute) Zulu")
        }
        
        if let index = components.firstIndex(of: "AUTO") {
            decodedParts.append("Report Type: Automated")
            components.remove(at: index)
        }
        
        if let windComponent = components.first(where: { $0.contains("KT") || $0.contains("MPS") }) {
            if let index = components.firstIndex(of: windComponent) {
                let unit = windComponent.contains("KT") ? "knots" : "m/s"
                let direction = String(windComponent.prefix(3))
                let speedString = String(windComponent.dropFirst(3).prefix(2))
                var windDesc = "Wind: From \(direction)° at \(speedString) \(unit)"
                if let gustIndex = windComponent.firstIndex(of: "G") {
                    let gustSpeed = String(windComponent[windComponent.index(after: gustIndex)...].dropLast(2))
                        windDesc += ", gusting to \(gustSpeed) \(unit)"
                }
                decodedParts.append(windDesc)
                components.remove(at: index)
            }
        }

        if let visibComponent = components.first(where: { $0.hasSuffix("SM") }) {
            if let index = components.firstIndex(of: visibComponent) {
                decodedParts.append("Visibility: \(visibComponent.dropLast(2)) statute miles")
                components.remove(at: index)
            }
        } else if let visibComponent = components.first(where: { $0.count == 4 && Int($0) != nil }) {
            if let index = components.firstIndex(of: visibComponent) {
                if visibComponent == "9999" {
                    decodedParts.append("Visibility: 10km or more")
                } else {
                    decodedParts.append("Visibility: \(visibComponent) meters")
                }
                components.remove(at: index)
            }
        } else if let cavokIndex = components.firstIndex(of: "CAVOK") {
            decodedParts.append("Ceiling and Visibility OK")
            components.remove(at: cavokIndex)
        }
        
        return decodedParts.joined(separator: "\n")
    }
    
    var totalFlightTime: TimeInterval {
        flightLogs.reduce(0) { $0 + $1.flightDuration }
    }
    
    var recurrencyExpirationDate: Date {
        Calendar.current.date(byAdding: .month, value: 24, to: lastRecurrencyDate)!
    }
    
    var daysUntilRecurrencyExpires: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: recurrencyExpirationDate).day ?? 0
    }
}


// MARK: - Views

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    
    var body: some View {
        TabView {
            NavigationStack { FlightLogListView() }
                .tabItem { Label("Logbook", systemImage: "book.closed.fill") }
            
            NavigationStack { EquipmentListView() }
                .tabItem { Label("Equipment", systemImage: "airplane.circle.fill") }
            
            NavigationStack { RemoteIDScannerView() }
                .tabItem { Label("Scanner", systemImage: "antenna.radiowaves.left.and.right") }
            
            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
        }
        .environmentObject(viewModel)
    }
}

// MARK: Logbook Views
struct FlightLogListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    var body: some View {
        Group {
            if viewModel.flightLogs.isEmpty {
                ContentUnavailableView("No Flights Logged", systemImage: "airplane.departure", description: Text("Tap the + button to add your first flight log."))
            } else {
                List {
                    ForEach(viewModel.flightLogs) { log in
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
                                    Text(formatDuration(log.flightDuration))
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .onDelete(perform: viewModel.deleteLog)
                }
            }
        }
        .navigationTitle("Flight Logbook")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: viewModel.startNewLog) {
                    Image(systemName: "plus.circle.fill").font(.title)
                }
                .disabled(viewModel.drones.isEmpty)
            }
        }
        .sheet(isPresented: $viewModel.isLoggingFlight) {
            FlightLoggingView(log: $viewModel.activeLog)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}

// MODIFICATION: This view is enhanced with charts and first/last seen times.
struct LoggedIDDetailView: View {
    let loggedID: LoggedRemoteID

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }

    var body: some View {
        Form {
            Section("Summary") {
                InfoRow(label: "Registration / Serial Number", value: loggedID.basicID?.uasID ?? "N/A")
                InfoRow(label: "ID Type", value: loggedID.basicID?.idType ?? "N/A")
                if let firstSeen = loggedID.telemetry.first?.timestamp {
                    InfoRow(label: "First Seen", value: timeFormatter.string(from: firstSeen))
                }
                if let lastSeen = loggedID.telemetry.last?.timestamp {
                    InfoRow(label: "Last Seen", value: timeFormatter.string(from: lastSeen))
                }
            }

            if !loggedID.telemetry.isEmpty {
                Section("Telemetry Charts") {
                    DisclosureGroup("Signal Strength (RSSI)") {
                        Chart(loggedID.telemetry) {
                            LineMark(
                                x: .value("Time", $0.timestamp),
                                y: .value("RSSI", $0.rssi)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)
                            
                            AreaMark(
                                x: .value("Time", $0.timestamp),
                                y: .value("RSSI", $0.rssi)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                        }
                        .chartYAxisLabel("dBm")
                        .frame(height: 150)
                        .padding(.top)
                    }
                    
                    DisclosureGroup("Altitude (AGL)") {
                        Chart(loggedID.telemetry) {
                            LineMark(
                                x: .value("Time", $0.timestamp),
                                y: .value("Altitude", $0.location.height ?? 0)
                            )
                            .foregroundStyle(.green)
                            .interpolationMethod(.catmullRom)
                        }
                        .chartYAxisLabel("Meters")
                        .frame(height: 150)
                        .padding(.top)
                    }
                    
                    DisclosureGroup("Ground Speed") {
                        Chart(loggedID.telemetry) {
                            LineMark(
                                x: .value("Time", $0.timestamp),
                                y: .value("Speed", $0.location.speedHorizontal)
                            )
                            .foregroundStyle(.orange)
                            .interpolationMethod(.catmullRom)
                        }
                        .chartYAxisLabel("m/s")
                        .frame(height: 150)
                        .padding(.top)
                    }
                }
            }
            
            Section("Full Telemetry Log (\(loggedID.telemetry.count) records)") {
                List(loggedID.telemetry) { record in
                    TelemetryRow(record: record)
                }
            }
        }
        .navigationTitle(loggedID.basicID?.uasID ?? "Log Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}


struct FlightLoggingView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var log: FlightLog
    
    @State private var isUsingPMTC = false
    @State private var isUsingVO = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Live Flight Logging") {
                    HStack {
                        Text("Duration:")
                        Spacer()
                        Text(formatDuration(log.flightDuration))
                            .font(.system(.title, design: .monospaced))
                            .foregroundStyle(.tint)
                    }
                }
                
                Section("Detected Remote IDs") {
                    if let loggedIDs = log.loggedRemoteIDs, !loggedIDs.isEmpty {
                        ForEach(loggedIDs) { rid in
                            NavigationLink(destination: LoggedIDDetailView(loggedID: rid)) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(rid.basicID?.uasID ?? "ID Unavailable")
                                            .font(.headline)
                                        if let lastRecord = rid.telemetry.last {
                                            Text("RSSI: \(lastRecord.rssi) dBm")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } else {
                        Text("Scanning for nearby drones...")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Flight Details") {
                    Picker("Aircraft", selection: $log.aircraftID) {
                        ForEach(viewModel.drones) { drone in
                            Text(drone.displayName).tag(drone.id as UUID?)
                        }
                    }
                    TextField("Location (e.g., Park, City, State)", text: $log.location)
                    TextField("Pilot in Command Name", text: $log.pilotInCommand)
                }
                
                Section("Additional Crew") {
                    Toggle("PMTC Performed?", isOn: $isUsingPMTC.animation())
                    if isUsingPMTC {
                        TextField("PMTC Performed By", text: Binding($log.pmtcBy, replacingNilWith: ""))
                    }
                    Toggle("Visual Observer Used?", isOn: $isUsingVO.animation())
                    if isUsingVO {
                        TextField("Visual Observer Name", text: Binding($log.visualObserver, replacingNilWith: ""))
                    }
                }
                
                Section("Mission Notes") {
                    TextEditor(text: $log.missionNotes)
                        .frame(minHeight: 100)
                }
                
                Section("Weather") {
                    HStack {
                        TextField("Airport ICAO Code", text: $log.weather.icao)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .font(.system(.body, design: .monospaced))
                        
                        Button("Fetch", action: viewModel.fetchWeather)
                            .disabled(log.weather.icao.count != 4)
                    }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Raw METAR").font(.caption).foregroundStyle(.secondary)
                        Text(log.weather.metar)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Decoded METAR").font(.caption).foregroundStyle(.secondary)
                        Text(log.weather.decodedMetar)
                    }.padding(.top, 5)

                }
            }
            .navigationTitle("New Flight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") {
                    viewModel.openDroneIDManager.stopScanning()
                    viewModel.isLoggingFlight = false
                } }
                ToolbarItem(placement: .confirmationAction) { Button("Save & End Flight", action: viewModel.stopLogging) }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00:00"
    }
}

struct FlightDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let log: FlightLog
    
    var body: some View {
        Form {
            Section("Flight Information") {
                InfoRow(label: "Aircraft", value: viewModel.droneForID(log.aircraftID)?.displayName ?? "N/A")
                InfoRow(label: "Location", value: log.location)
                InfoRow(label: "Date", value: log.date.formatted(date: .long, time: .shortened))
                InfoRow(label: "Duration", value: formatDuration(log.flightDuration))
                InfoRow(label: "Pilot in Command", value: log.pilotInCommand)
            }
            
            if (log.pmtcBy != nil && !log.pmtcBy!.isEmpty) || (log.visualObserver != nil && !log.visualObserver!.isEmpty) {
                Section("Additional Crew") {
                    if let pmtc = log.pmtcBy, !pmtc.isEmpty { InfoRow(label: "PMTC By", value: pmtc) }
                    if let vo = log.visualObserver, !vo.isEmpty { InfoRow(label: "Visual Observer", value: vo) }
                }
            }
            
            if let rids = log.loggedRemoteIDs, !rids.isEmpty {
                Section("Detected Remote ID Telemetry") {
                    ForEach(rids) { rid in
                        NavigationLink(destination: LoggedIDDetailView(loggedID: rid)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rid.basicID?.uasID ?? "ID Unavailable").bold()
                                Text("Telemetry Points: \(rid.telemetry.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            
            Section("Mission Notes") {
                Text(log.missionNotes.isEmpty ? "No notes." : log.missionNotes)
            }

            Section("Weather Conditions") {
                InfoRow(label: "Raw METAR", value: log.weather.metar)
                InfoRow(label: "Decoded", value: log.weather.decodedMetar, multiline: true)
            }
        }
        .navigationTitle("Flight Details")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: duration) ?? "N/A"
    }
}

struct TelemetryRow: View {
    let record: TelemetryRecord
    
    private static var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(Self.timeFormatter.string(from: record.timestamp))
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text("\(record.rssi) dBm")
                    .font(.caption)
                    .foregroundColor(rssiColor(NSNumber(value: record.rssi)))
            }
            
            Text(String(format: "Lat: %.5f, Lon: %.5f", record.location.latitude, record.location.longitude))
            Text(String(format: "Alt (AGL): %.1f m, Speed: %.1f m/s, Hdg: %d°", record.location.height ?? 0, record.location.speedHorizontal, Int(record.location.direction)))
        }
        .font(.footnote)
    }
    
    func rssiColor(_ rssi: NSNumber) -> Color {
        switch rssi.intValue {
        case -60...0: return .green
        case -80 ..< -60: return .orange
        default: return .red
        }
    }
}


// MARK: Equipment Views
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
struct AddEditDroneView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var drone: Drone
    let isEditing: Bool
    
    init(droneToEdit: Drone?) {
        if let existingDrone = droneToEdit {
            _drone = State(initialValue: existingDrone)
            isEditing = true
        } else {
            _drone = State(initialValue: Drone(id: UUID(), company: "", model: "", faaRegistration: "", remoteIdSerial: ""))
            isEditing = false
        }
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
                    TextField("Remote ID Serial Number", text: $drone.remoteIdSerial)
                }
            }
            .navigationTitle(isEditing ? "Edit Drone" : "Add Drone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveDrone(drone: drone)
                        dismiss()
                    }
                }
            }
        }
    }
}
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


// MARK: Scanner Views
// MODIFICATION: The RemoteIDScannerView is updated to use the OpenDroneIDManager.
struct RemoteIDScannerView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedDevice: RemoteIDDevice?

    var body: some View {
        Group {
            if viewModel.openDroneIDManager.isScanning && viewModel.openDroneIDManager.discoveredDevices.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                    Text("Scanning for Drones...")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.openDroneIDManager.discoveredDevices.isEmpty {
                ContentUnavailableView {
                    Label("No Drones Found", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("No Remote ID signals detected. Ensure your drone is powered on and broadcasting.")
                }
            } else {
                List(viewModel.openDroneIDManager.discoveredDevices) { device in
                    Button(action: { selectedDevice = device }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right.circle")
                                .foregroundStyle(.blue)
                                .font(.title)
                            VStack(alignment: .leading) {
                                Text(device.name).font(.headline)
                                Text(device.basicID?.uasID ?? "ID: N/A")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .font(.subheadline)
                                .foregroundStyle(rssiColor(device.rssi))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .navigationTitle("Remote ID Scanner")
        .onAppear {
              viewModel.openDroneIDManager.startScanning()
        }
        .onDisappear(perform: viewModel.openDroneIDManager.stopScanning)
        .sheet(item: $selectedDevice) { device in
            RemoteIDDetailView(device: device)
        }
    }

    func rssiColor(_ rssi: NSNumber) -> Color {
        switch rssi.intValue {
        case -60...0: return .green
        case -80 ..< -60: return .orange
        default: return .red
        }
    }
}

struct RemoteIDDetailView: View {
    @ObservedObject var device: RemoteIDDevice
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Identification") {
                    InfoRow(label: "Broadcast Name", value: device.name)
                    InfoRow(label: "ID Type", value: device.basicID?.idType ?? "N/A")
                    InfoRow(label: "Registration Number", value: device.basicID?.uasID ?? "N/A")
                }
                
                Section("Telemetry") {
                    InfoRow(label: "Signal Strength (RSSI)", value: "\(device.rssi) dBm")
                    if let location = device.location {
                        InfoRow(label: "Coordinates", value: String(format: "%.4f, %.4f", location.latitude, location.longitude))
                        InfoRow(label: "Altitude (AGL)", value: String(format: "%.1f m", location.height ?? 0.0))
                        InfoRow(label: "Ground Speed", value: String(format: "%.1f m/s", location.speedHorizontal))
                        InfoRow(label: "Heading", value: "\(Int(location.direction))°")
                    } else {
                        InfoRow(label: "Coordinates", value: "N/A")
                        InfoRow(label: "Altitude (AGL)", value: "N/A")
                        InfoRow(label: "Ground Speed", value: "N/A")
                        InfoRow(label: "Heading", value: "N/A")
                    }
                }
            }
            .navigationTitle("Remote ID Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: Stats View
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

            Section("Part 107 Certificate") {
                DatePicker(
                    "Initial Issue Date",
                    selection: $viewModel.initialCertificateDate,
                    displayedComponents: .date
                )
                InfoRow(label: "Status", value: "Certificate does not expire.")
            }
            
            Section("Recurrent Training") {
                DatePicker(
                    "Last Training/Exam Date",
                    selection: $viewModel.lastRecurrencyDate,
                    displayedComponents: .date
                )
                
                VStack(alignment: .leading) {
                    Text("Training Expires On")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.recurrencyExpirationDate, style: .date)
                        .bold()
                }
                
                HStack {
                    if viewModel.daysUntilRecurrencyExpires <= 0 {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text("Recurrent Training Expired")
                            .bold()
                            .foregroundStyle(.red)
                    } else if viewModel.daysUntilRecurrencyExpires <= 90 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(viewModel.daysUntilRecurrencyExpires) days remaining")
                            .bold()
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(viewModel.daysUntilRecurrencyExpires) days remaining")
                            .bold()
                    }
                }
            }
        }
        .navigationTitle("Pilot Stats")
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        return formatter.string(from: duration) ?? "0 hours"
    }
}


// MARK: - Helper Views
struct InfoRow: View {
    var label: String
    var value: String
    var multiline: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(multiline ? .footnote : .body)
        }
        .padding(.vertical, 4)
    }
}
