import SwiftUI
import CoreBluetooth
import Combine

// MARK: - Helper Extensions
extension Data {
    func toUInt16(at offset: Int) -> UInt16 {
        let subdata = self.subdata(in: offset..<(offset+2))
        return subdata.withUnsafeBytes { $0.load(as: UInt16.self) }
    }

    func toInt32(at offset: Int) -> Int32 {
        let subdata = self.subdata(in: offset..<(offset+4))
        return subdata.withUnsafeBytes { $0.load(as: Int32.self) }
    }

    func toFloat16(at offset: Int) -> Float {
        let uint16 = self.toUInt16(at: offset)

        let sign = (uint16 & 0x8000) >> 15
        let exponent = (uint16 & 0x7C00) >> 10
        let fraction = uint16 & 0x03FF

        let floatSign: UInt32 = UInt32(sign) << 31
        var floatExponent: UInt32
        var floatFraction: UInt32

        if exponent == 0 {
            if fraction == 0 {
                floatExponent = 0
                floatFraction = 0
            } else {
                var exponentInt = -14
                var frac = fraction
                while (frac & 0x0400) == 0 {
                    frac <<= 1
                    exponentInt -= 1
                }
                floatExponent = UInt32(exponentInt + 127) << 23
                floatFraction = UInt32(frac & ~0x0400) << 13
            }
        } else if exponent == 0x1F {
            if fraction == 0 {
                floatExponent = 0xFF << 23
                floatFraction = 0
            } else {
                floatExponent = 0xFF << 23
                floatFraction = UInt32(fraction) << 13
            }
        } else {
            floatExponent = UInt32(Int(exponent) - 15 + 127) << 23
            floatFraction = UInt32(fraction) << 13
        }

        let floatBits = floatSign | floatExponent | floatFraction
        return Float(bitPattern: floatBits)
    }
}

extension Binding {
    init(_ source: Binding<Value?>, replacingNilWith nilValue: Value) {
        self.init(
            get: { source.wrappedValue ?? nilValue },
            set: { newValue in source.wrappedValue = newValue }
        )
    }
}

// MARK: - Models

struct FlightSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var startTime: Date
    var endTime: Date?

    var duration: TimeInterval {
        if let endTime = endTime {
            return endTime.timeIntervalSince(startTime)
        } else {
            // If the segment is active, calculate duration to now
            return Date().timeIntervalSince(startTime)
        }
    }
}

struct Checklist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var items: [ChecklistItem]
}

struct ChecklistItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
}

struct CompletedChecklistItem: Identifiable, Codable, Hashable {
    let id: UUID // Corresponds to ChecklistItem's ID
    var text: String
    var isChecked: Bool
    var completionDate: Date?
}

struct FlightLog: Identifiable, Codable {
    let id: UUID
    var date: Date
    var aircraftID: UUID?
    var location: String
    var pilotInCommand: String
    var missionNotes: String
    var weather: WeatherData
    var pmtcBy: String?
    var visualObserver: String?
    var loggedRemoteIDs: [LoggedRemoteID]?
    var completedChecklist: [CompletedChecklistItem]
    var segments: [FlightSegment]

    var flightDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    init(id: UUID = UUID(), date: Date = Date(), aircraftID: UUID? = nil, location: String = "", pilotInCommand: String = "", missionNotes: String = "", weather: WeatherData = WeatherData(), pmtcBy: String? = nil, visualObserver: String? = nil, loggedRemoteIDs: [LoggedRemoteID]? = nil, completedChecklist: [CompletedChecklistItem] = [], segments: [FlightSegment] = []) {
        self.id = id
        self.date = date
        self.aircraftID = aircraftID
        self.location = location
        self.pilotInCommand = pilotInCommand
        self.missionNotes = missionNotes
        self.weather = weather
        self.pmtcBy = pmtcBy
        self.visualObserver = visualObserver
        self.loggedRemoteIDs = loggedRemoteIDs
        self.completedChecklist = completedChecklist
        self.segments = segments
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

struct TelemetryRecord: Codable, Hashable {
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

    init(from peripheral: CBPeripheral, rssi: NSNumber) {
        self.id = peripheral.identifier
        self.name = peripheral.name ?? "Drone \(String(peripheral.identifier.uuidString.prefix(4)))"
        self.rssi = rssi
    }

    func update(with advertisementData: [String: Any], rssi: NSNumber) {
        DispatchQueue.main.async {
            self.rssi = rssi
            guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
                  let remoteIDData = serviceData.first?.value else {
                return
            }
            self.parseODIDMessagePack(data: remoteIDData)
        }
    }

    private func parseODIDMessagePack(data: Data) {
        guard data.count > 2 else { return }
        var currentIndex = 2

        while currentIndex < data.count {
            guard currentIndex < data.count else { break }

            let messageHeader = data[currentIndex]
            let messageType = Int(messageHeader >> 4)
            let messageLength = 25

            guard currentIndex + messageLength <= data.count else {
                break
            }

            let messageData = data.subdata(in: currentIndex ..< (currentIndex + messageLength))

            switch messageType {
            case 0:
                if let newBasicID = self.parseBasicID(message: messageData) {
                    if newBasicID.idType == "FAA Registration ID" {
                        self.basicID = newBasicID
                    }
                }
            case 1:
                if let newLocation = self.parseLocation(message: messageData) {
                    self.location = newLocation
                }
            default:
                break
            }

            currentIndex += messageLength
        }
    }

    private func parseBasicID(message: Data) -> ODIDBasicID? {
        guard message.count == 25 else { return nil }

        let idTypeValue = message[1]
        var idType: String

        switch idTypeValue {
        case 0x12:
            idType = "Serial Number"
        case 0x22:
            idType = "FAA Registration ID"
        default:
            return nil
        }

        let uasIDBytes = message.subdata(in: 2..<22)
        let uasID = String(data: uasIDBytes, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\0", with: "") ?? "Invalid String"

        if uasID.isEmpty {
            return nil
        }
        return ODIDBasicID(idType: idType, uasID: uasID)
    }

    private func parseLocation(message: Data) -> ODIDLocation? {
        guard message.count >= 21 else { return nil }

        let status = "Airborne"
        let direction = Double(message.toUInt16(at: 2)) * 0.01
        let speedHorizontal = Double(message.toUInt16(at: 4)) * 0.25
        let speedVertical = Double(message[6]) * 0.5
        let latitude = Double(message.toInt32(at: 8)) / 1e7
        let longitude = Double(message.toInt32(at: 12)) / 1e7
        let altitudeGeodetic = Double(message.toFloat16(at: 16)) * 0.5 - 1000
        let height = Double(message.toFloat16(at: 18)) * 0.5 - 1000
        let heightType = message[1] & 0x01 == 1 ? "Above Ground" : "Above Takeoff"

        return ODIDLocation(status: status, direction: direction, speedHorizontal: speedHorizontal, speedVertical: speedVertical, latitude: latitude, longitude: longitude, altitudeGeodetic: altitudeGeodetic, height: height, heightType: heightType)
    }
}

// MARK: - Managers

class BluetoothScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var discoveredDevices: [RemoteIDDevice] = []
    @Published var isScanning = false
    private var centralManager: CBCentralManager!

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        isScanning = true
        let remoteIDServiceUUID = CBUUID(string: "0000FFFA-0000-1000-8000-00805F9B34FB")
        centralManager.scanForPeripherals(withServices: [remoteIDServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            isScanning = false
            print("Bluetooth is not available.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        DispatchQueue.main.async {
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[index].update(with: advertisementData, rssi: RSSI)
            } else {
                let newDevice = RemoteIDDevice(from: peripheral, rssi: RSSI)
                newDevice.update(with: advertisementData, rssi: RSSI)
                self.discoveredDevices.append(newDevice)
            }
        }
    }
}

// MARK: - ViewModels
class AppViewModel: ObservableObject {
    @Published var bluetoothScanner = BluetoothScanner()

    @Published var flightLogs: [FlightLog] = []
    @Published var isLoggingFlight = false
    @Published var activeLog: FlightLog = FlightLog()
    @Published var isSegmentActive = false
    @Published var telemetryTimer: Timer?
    @Published var drones: [Drone] = []
    @Published var checklists: [Checklist] = []

    private var updateTimer: Timer? // Timer to drive UI updates

    @Published var initialCertificateDate: Date {
        didSet { UserDefaults.standard.set(initialCertificateDate, forKey: certificateDateKey) }
    }
    @Published var lastRecurrencyDate: Date {
        didSet { UserDefaults.standard.set(lastRecurrencyDate, forKey: recurrencyDateKey) }
    }

    private var cancellables = Set<AnyCancellable>()

    private let logbookStorageKey = "Part107Logbook_Logs_v12"
    private let droneStorageKey = "Part107Logbook_Drones_v12"
    private let checklistStorageKey = "Part107Logbook_Checklists_v12"
    private let certificateDateKey = "Part107Logbook_CertDate_v12"
    private let recurrencyDateKey = "Part107Logbook_RecurrencyDate_v12"

    init() {
        self.initialCertificateDate = UserDefaults.standard.object(forKey: certificateDateKey) as? Date ?? Date()
        self.lastRecurrencyDate = UserDefaults.standard.object(forKey: recurrencyDateKey) as? Date ?? Date()
        loadLogs()
        loadDrones()
        loadChecklists()

        bluetoothScanner.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func startNewLog() {
        activeLog = FlightLog()
        activeLog.loggedRemoteIDs = []
        if let firstDrone = drones.first {
            activeLog.aircraftID = firstDrone.id
        }
        if let firstChecklist = checklists.first {
            activeLog.completedChecklist = firstChecklist.items.map {
                CompletedChecklistItem(id: $0.id, text: $0.text, isChecked: false)
            }
        }
        bluetoothScanner.startScanning()
        isLoggingFlight = true
        startTelemetryTimer()
    }

    func startTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordTelemetrySnapshot()
        }
    }

    func startNewSegment() {
        let newSegment = FlightSegment(id: UUID(), startTime: Date())
        activeLog.segments.append(newSegment)
        isSegmentActive = true
        startUpdateTimer()
    }

    func endCurrentSegment() {
        guard let lastSegmentIndex = activeLog.segments.indices.last, activeLog.segments[lastSegmentIndex].endTime == nil else { return }
        activeLog.segments[lastSegmentIndex].endTime = Date()
        isSegmentActive = false
        stopUpdateTimer()
    }

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // This just tells SwiftUI that the viewmodel has changed, so it should
            // re-render any views that depend on it (like our duration text).
            self?.objectWillChange.send()
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func recordTelemetrySnapshot() {
        let timestamp = Date()
        var updatedLoggedIDs = activeLog.loggedRemoteIDs ?? []

        for device in bluetoothScanner.discoveredDevices {
            if let index = updatedLoggedIDs.firstIndex(where: { $0.id == device.id }) {
                if let basicID = device.basicID {
                    updatedLoggedIDs[index].basicID = basicID
                }
                if let location = device.location {
                    let newRecord = TelemetryRecord(timestamp: timestamp, location: location, rssi: device.rssi.intValue)
                    updatedLoggedIDs[index].telemetry.append(newRecord)
                }
            } else {
                var newLoggedID = LoggedRemoteID(id: device.id, basicID: device.basicID, telemetry: [])
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
        if isSegmentActive {
            endCurrentSegment()
        }
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        stopUpdateTimer()

        isLoggingFlight = false
        bluetoothScanner.stopScanning()
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

    func saveChecklist(_ checklist: Checklist) {
        if let index = checklists.firstIndex(where: { $0.id == checklist.id }) {
            checklists[index] = checklist
        } else {
            checklists.append(checklist)
        }
        saveChecklists()
    }

    func deleteChecklist(at offsets: IndexSet) {
        checklists.remove(atOffsets: offsets)
        saveChecklists()
    }

    func loadChecklists() {
        guard let data = UserDefaults.standard.data(forKey: checklistStorageKey) else { return }
        do {
            checklists = try JSONDecoder().decode([Checklist].self, from: data)
        } catch {
            print("Error loading checklists: \(error.localizedDescription)")
        }
    }

    private func saveChecklists() {
        do {
            let data = try JSONEncoder().encode(checklists)
            UserDefaults.standard.set(data, forKey: checklistStorageKey)
        } catch {
            print("Error saving checklists: \(error.localizedDescription)")
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

            NavigationStack { ChecklistListView() }
                .tabItem { Label("Checklists", systemImage: "checklist") }

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

struct FlightLoggingView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Binding var log: FlightLog

    @State private var isUsingPMTC = false
    @State private var isUsingVO = false
    @State private var selectedChecklistID: UUID?

    var body: some View {
        NavigationView {
            Form {
                liveLoggingSection
                inFlightControlsSection
                flightSegmentsSection
                remoteIDSection
                checklistSection
                flightDetailsSection
                additionalCrewSection
                missionNotesSection
                weatherSection
            }
            .navigationTitle("New Flight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.stopLogging()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & End Flight", action: viewModel.stopLogging)
                }
            }
            .onAppear {
                if let firstItem = log.completedChecklist.first,
                   let checklist = viewModel.checklists.first(where: { $0.items.contains(where: { $0.id == firstItem.id }) }) {
                    selectedChecklistID = checklist.id
                }
            }
        }
    }

    // MARK: - Refactored View Sections

    private var liveLoggingSection: some View {
        Section("Live Flight Logging") {
            HStack {
                Text("Total Duration:")
                Spacer()
                Text(formatDuration(log.flightDuration))
                    .font(.system(.title, design: .monospaced))
                    // CORRECTED LINE: Replaced .tint with Color.accentColor
                    .foregroundStyle(viewModel.isSegmentActive ? .green : Color.accentColor)
            }
        }
    }

    private var inFlightControlsSection: some View {
        Section("In-Flight Controls") {
            HStack {
                Button(action: viewModel.startNewSegment) {
                    Text("Take Off")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSegmentActive)

                Button(action: viewModel.endCurrentSegment) {
                    Text("Land")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isSegmentActive)
            }
        }
    }
    
    private var flightSegmentsSection: some View {
        Section("Flight Segments") {
            if log.segments.isEmpty {
                Text("Press 'Take Off' to start a segment.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(log.segments.reversed()) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Takeoff:")
                                .fontWeight(.medium)
                            Text(segment.startTime, style: .time)
                            Spacer()
                            if let endTime = segment.endTime {
                                Text("Landing:")
                                    .fontWeight(.medium)
                                Text(endTime, style: .time)
                            } else {
                                Text("In Progress")
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }
                        }
                        Text("Duration: \(formatDuration(segment.duration))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var remoteIDSection: some View {
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
    }

    private var checklistSection: some View {
        Section("Pre-flight Checklist") {
            if viewModel.checklists.isEmpty {
                Text("No checklists available. Add one from the Checklists tab.")
                    .foregroundStyle(.secondary)
            } else {
                checklistPicker
                completedItemsList
            }
        }
    }

    private var checklistPicker: some View {
        Picker("Select Checklist", selection: $selectedChecklistID) {
            Text("None").tag(nil as UUID?)
            ForEach(viewModel.checklists) { checklist in
                Text(checklist.name).tag(checklist.id as UUID?)
            }
        }
        .onChange(of: selectedChecklistID) { _, newValue in
            updateCompletedChecklist(for: newValue)
        }
    }

    private var completedItemsList: some View {
        ForEach($log.completedChecklist) { $item in
            Button(action: {
                $item.isChecked.wrappedValue.toggle()
                if $item.isChecked.wrappedValue {
                    $item.completionDate.wrappedValue = Date()
                } else {
                    $item.completionDate.wrappedValue = nil
                }
            }) {
                HStack {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isChecked ? .green : .secondary)
                    Text(item.text)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    Spacer()
                    if let completionDate = item.completionDate {
                        Text(completionDate, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var flightDetailsSection: some View {
        Section("Flight Details") {
            Picker("Aircraft", selection: $log.aircraftID) {
                ForEach(viewModel.drones) { drone in
                    Text(drone.displayName).tag(drone.id as UUID?)
                }
            }
            TextField("Location (e.g., Park, City, State)", text: $log.location)
            TextField("Pilot in Command Name", text: $log.pilotInCommand)
        }
    }

    private var additionalCrewSection: some View {
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
    }

    private var missionNotesSection: some View {
        Section("Mission Notes") {
            TextEditor(text: $log.missionNotes)
                .frame(minHeight: 100)
        }
    }

    private var weatherSection: some View {
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

    private func updateCompletedChecklist(for checklistId: UUID?) {
        guard let id = checklistId, let checklist = viewModel.checklists.first(where: { $0.id == id }) else {
            log.completedChecklist = []
            return
        }
        log.completedChecklist = checklist.items.map {
            CompletedChecklistItem(id: $0.id, text: $0.text, isChecked: false, completionDate: nil)
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
                InfoRow(label: "Total Duration", value: formatDuration(log.flightDuration))
                InfoRow(label: "Pilot in Command", value: log.pilotInCommand)
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
                            Text("Duration: \(formatDuration(segment.duration))")
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

            if let rids = log.loggedRemoteIDs, !rids.isEmpty {
                Section("Detected Remote ID Telemetry") {
                    ForEach(rids) { rid in
                        DisclosureGroup {
                            ForEach(rid.telemetry, id: \.self) { record in
                                TelemetryRow(record: record)
                                    .padding(.vertical, 4)
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(rid.basicID?.uasID ?? "ID Unavailable").bold()
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
                InfoRow(label: "Raw METAR", value: log.weather.metar)
                InfoRow(label: "Decoded", value: log.weather.decodedMetar, multiline: true)
            }
        }
        .navigationTitle("Flight Details")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00:00"
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

// MARK: Checklist Views
struct ChecklistListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showAddChecklistSheet = false

    var body: some View {
        Group {
            if viewModel.checklists.isEmpty {
                ContentUnavailableView(
                    "No Checklists",
                    systemImage: "checklist",
                    description: Text("Tap the + button to create your first pre-flight checklist.")
                )
            } else {
                List {
                    ForEach(viewModel.checklists) { checklist in
                        NavigationLink(destination: ChecklistDetailView(checklist: checklist)) {
                            VStack(alignment: .leading) {
                                Text(checklist.name).font(.headline)
                                Text("\(checklist.items.count) items").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: viewModel.deleteChecklist)
                }
            }
        }
        .navigationTitle("Pre-flight Checklists")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddChecklistSheet.toggle() }) {
                    Image(systemName: "plus.circle.fill").font(.title)
                }
            }
        }
        .sheet(isPresented: $showAddChecklistSheet) {
            AddEditChecklistView(checklistToEdit: nil)
        }
    }
}

struct AddEditChecklistView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var checklist: Checklist
    let isEditing: Bool

    init(checklistToEdit: Checklist?) {
        if let existingChecklist = checklistToEdit {
            _checklist = State(initialValue: existingChecklist)
            isEditing = true
        } else {
            _checklist = State(initialValue: Checklist(id: UUID(), name: "", items: []))
            isEditing = false
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Checklist Details") {
                    TextField("Checklist Name", text: $checklist.name)
                }
                Section("Checklist Items") {
                    ForEach($checklist.items) { $item in
                        TextField("Checklist item", text: $item.text)
                    }
                    .onDelete { offsets in
                        checklist.items.remove(atOffsets: offsets)
                    }
                    Button("Add Item", systemImage: "plus") {
                        let newItem = ChecklistItem(id: UUID(), text: "")
                        checklist.items.append(newItem)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Checklist" : "Add Checklist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var checklistToSave = checklist
                        checklistToSave.items.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                        viewModel.saveChecklist(checklistToSave)
                        dismiss()
                    }
                    .disabled(checklist.name.isEmpty)
                }
            }
        }
    }
}

struct ChecklistDetailView: View {
    let checklist: Checklist
    @State private var showEditSheet = false

    var body: some View {
        Form {
            Section("Checklist Items") {
                if checklist.items.isEmpty {
                    Text("No items in this checklist.")
                } else {
                    ForEach(checklist.items) { item in
                        Text(item.text)
                    }
                }
            }
        }
        .navigationTitle(checklist.name)
        .toolbar {
            Button("Edit") { showEditSheet.toggle() }
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditChecklistView(checklistToEdit: checklist)
        }
    }
}


// MARK: Scanner Views
struct RemoteIDScannerView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedDevice: RemoteIDDevice?

    var body: some View {
        Group {
            if viewModel.bluetoothScanner.isScanning && viewModel.bluetoothScanner.discoveredDevices.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                    Text("Scanning for Drones...")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.bluetoothScanner.discoveredDevices.isEmpty {
                ContentUnavailableView {
                    Label("No Drones Found", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("No Remote ID signals detected. Ensure your drone is powered on and broadcasting.")
                }
            } else {
                List(viewModel.bluetoothScanner.discoveredDevices) { device in
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
        .onAppear(perform: viewModel.bluetoothScanner.startScanning)
        .onDisappear(perform: viewModel.bluetoothScanner.stopScanning)
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
