import Foundation
import Combine

/// The primary ViewModel for the application, responsible for state management and business logic.
/// This class acts as the "source of truth" for the views.
@MainActor
class AppViewModel: ObservableObject {
    // MARK: Published Properties
    @Published var bluetoothScanner = BluetoothScanner()
    
    @Published var flightLogs: [FlightLog] = []
    @Published var drones: [Drone] = []
    @Published var checklists: [Checklist] = []
    @Published var userSettings: UserSettings
    
    @Published var needsSetup: Bool = false
    @Published var isLoggingFlight = false
    @Published var activeLog = FlightLog()
    @Published var isSegmentActive = false

    private var telemetryTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.userSettings = Self.loadData(from: Constants.UserDefaultsKeys.userSettings) ?? UserSettings()
        loadAllData()
        
        self.needsSetup = !UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.setupCompleted)

        // Propagate changes from the scanner to this ViewModel's subscribers.
        bluetoothScanner.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
            
        // Clean up stale items from the trash on app launch.
        purgeStaleTrashedLogs()
    }

    // MARK: - Setup Flow
    func finalizeSetup(settings: UserSettings, drones: [Drone], hasDoneRecurrent: Bool) {
        var finalSettings = settings
        if finalSettings.pilotType == .part107 && !hasDoneRecurrent {
            finalSettings.part107LastRecurrencyDate = finalSettings.part107InitialCertificateDate
        }
        
        self.userSettings = finalSettings
        self.drones = drones
        saveUserSettings()
        saveDrones()
        
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.setupCompleted)
        needsSetup = false
    }

    // MARK: - Flight Logging
    func startNewLog() {
        activeLog = FlightLog()
        activeLog.pilotInCommand = userSettings.pilotName
        activeLog.aircraftID = drones.first?.id
        
        if let firstChecklist = checklists.first {
            activeLog.completedChecklist = firstChecklist.items.map {
                CompletedChecklistItem(id: $0.id, text: $0.text, isChecked: false)
            }
        }
        
        bluetoothScanner.startScanning()
        isLoggingFlight = true
        startTelemetryTimer()
    }
    
    func discardActiveLog() {
        if isSegmentActive { endCurrentSegment() }
        stopTelemetryTimer()
        
        activeLog.trashedDate = Date()
        saveLog(activeLog) // Save the trashed log
        
        isLoggingFlight = false
        bluetoothScanner.stopScanning()
    }

    func saveAndStopLogging() {
        if isSegmentActive { endCurrentSegment() }
        stopTelemetryTimer()
        isLoggingFlight = false
        bluetoothScanner.stopScanning()
        saveLog(activeLog)
    }

    func startNewSegment() {
        activeLog.segments.append(FlightSegment(id: UUID(), startTime: Date()))
        isSegmentActive = true
    }

    func endCurrentSegment() {
        guard let lastSegmentIndex = activeLog.segments.indices.last, activeLog.segments[lastSegmentIndex].endTime == nil else { return }
        activeLog.segments[lastSegmentIndex].endTime = Date()
        isSegmentActive = false
    }

    // MARK: - Data Persistence (CRUD Operations)
    
    func moveLogToTrash(at offsets: IndexSet) {
        let activeLogs = self.activeFlightLogs
        let logsToMove = offsets.map { activeLogs[$0] }
        
        for log in logsToMove {
            if let index = self.flightLogs.firstIndex(where: { $0.id == log.id }) {
                self.flightLogs[index].trashedDate = Date()
            }
        }
        saveLogs()
    }
    
    func restoreLogFromTrash(at offsets: IndexSet) {
        let trashed = self.trashedFlightLogs
        let logsToRestore = offsets.map { trashed[$0] }
        
        for log in logsToRestore {
            if let index = self.flightLogs.firstIndex(where: { $0.id == log.id }) {
                self.flightLogs[index].trashedDate = nil
            }
        }
        saveLogs()
    }
    
    func deleteLogPermanently(at offsets: IndexSet) {
        let trashed = self.trashedFlightLogs
        let idsToDelete = offsets.map { trashed[$0].id }
        self.flightLogs.removeAll { idsToDelete.contains($0.id) }
        saveLogs()
    }

    func saveDrone(drone: Drone) {
        if let index = drones.firstIndex(where: { $0.id == drone.id }) {
            drones[index] = drone
        } else {
            drones.append(drone)
        }
        saveDrones()
    }
    
    func saveChecklist(_ checklist: Checklist) {
        if let index = checklists.firstIndex(where: { $0.id == checklist.id }) {
            checklists[index] = checklist
        } else {
            checklists.append(checklist)
        }
        saveChecklists()
    }
    
    func deleteDrone(at offsets: IndexSet) {
        drones.remove(atOffsets: offsets)
        saveDrones()
    }
    
    func deleteChecklist(at offsets: IndexSet) {
        checklists.remove(atOffsets: offsets)
        saveChecklists()
    }
    
    // MARK: - Weather Service
    func fetchWeather() async {
        guard !activeLog.weather.icao.isEmpty else { return }
        let icao = activeLog.weather.icao.uppercased()
        guard let url = URL(string: "https://aviationweather.gov/api/data/metar?ids=\(icao)&format=json") else { return }

        var request = URLRequest(url: url)
        request.setValue("Part 107 Logbook App (Production)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let metarReports = try JSONDecoder().decode([MetarReport].self, from: data)
            
            if let report = metarReports.first {
                self.activeLog.weather.metar = report.rawOb
                self.activeLog.weather.decodedMetar = self.decodeMetar(raw: report.rawOb)
            } else {
                self.activeLog.weather.metar = "METAR not found for \(icao)"
                self.activeLog.weather.decodedMetar = "No data available."
            }
        } catch {
            AppLogger.network.error("Error fetching or parsing METAR for \(icao): \(error.localizedDescription)")
            self.activeLog.weather.metar = "Error fetching METAR."
            self.activeLog.weather.decodedMetar = "Could not parse response."
        }
    }
    
    // MARK: - Computed Properties & Helpers
    
    var activeFlightLogs: [FlightLog] {
        flightLogs.filter { $0.trashedDate == nil }
    }
    
    var trashedFlightLogs: [FlightLog] {
        flightLogs.filter { $0.trashedDate != nil }.sorted { $0.trashedDate! > $1.trashedDate! }
    }
    
    var totalFlightTime: TimeInterval {
        activeFlightLogs.reduce(0) { $0 + $1.flightDuration }
    }
    
    var recurrencyExpirationDate: Date? {
        guard userSettings.pilotType == .part107 else { return nil }
        return Calendar.current.date(byAdding: .month, value: 24, to: userSettings.part107LastRecurrencyDate)
    }

    var daysUntilRecurrencyExpires: Int? {
        guard let expirationDate = recurrencyExpirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }
    
    func droneForID(_ id: UUID?) -> Drone? {
        guard let id = id else { return nil }
        return drones.first { $0.id == id }
    }
    
    // MARK: - Private Methods
    
    private func purgeStaleTrashedLogs() {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let originalCount = self.flightLogs.count
        
        self.flightLogs.removeAll { log in
            guard let trashedDate = log.trashedDate else { return false }
            return trashedDate < thirtyDaysAgo
        }
        
        if self.flightLogs.count != originalCount {
            AppLogger.persistence.info("Purged \(originalCount - self.flightLogs.count) stale log(s) from trash.")
            saveLogs()
        }
    }

    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()
        // <-- FIXED: This closure now correctly dispatches its work to the main actor.
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordTelemetrySnapshot()
            }
        }
    }
    
    private func stopTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = nil
    }

    private func recordTelemetrySnapshot() {
        let timestamp = Date()
        var updatedLoggedIDs = activeLog.loggedRemoteIDs

        for device in bluetoothScanner.discoveredDevices.values {
            guard let location = device.location else { continue }
            
            let newRecord = TelemetryRecord(timestamp: timestamp, location: location, rssi: device.rssi.intValue)
            
            if let index = updatedLoggedIDs.firstIndex(where: { $0.id == device.id }) {
                updatedLoggedIDs[index].basicID = device.basicID
                updatedLoggedIDs[index].telemetry.append(newRecord)
            } else {
                updatedLoggedIDs.append(LoggedRemoteID(id: device.id, basicID: device.basicID, telemetry: [newRecord]))
            }
        }
        self.activeLog.loggedRemoteIDs = updatedLoggedIDs
    }
    
    private func saveLog(_ log: FlightLog) {
        if let index = self.flightLogs.firstIndex(where: { $0.id == log.id }) {
            self.flightLogs[index] = log
        } else {
            self.flightLogs.insert(log, at: 0)
        }
        saveLogs()
    }
    
    private func loadAllData() {
        flightLogs = Self.loadData(from: Constants.UserDefaultsKeys.logbookStorage) ?? []
        drones = Self.loadData(from: Constants.UserDefaultsKeys.droneStorage) ?? []
        checklists = Self.loadData(from: Constants.UserDefaultsKeys.checklistStorage) ?? []
    }
    
    private func saveLogs() { Self.saveData(self.flightLogs.sorted(by: { $0.date > $1.date }), to: Constants.UserDefaultsKeys.logbookStorage) }
    private func saveDrones() { Self.saveData(drones, to: Constants.UserDefaultsKeys.droneStorage) }
    private func saveChecklists() { Self.saveData(checklists, to: Constants.UserDefaultsKeys.checklistStorage) }
    func saveUserSettings() { Self.saveData(userSettings, to: Constants.UserDefaultsKeys.userSettings) }
    
    private static func saveData<T: Encodable>(_ data: T, to key: String) {
        do {
            let encodedData = try JSONEncoder().encode(data)
            UserDefaults.standard.set(encodedData, forKey: key)
        } catch {
            AppLogger.persistence.error("Failed to save data for key \(key): \(error.localizedDescription)")
        }
    }
    
    private static func loadData<T: Decodable>(from key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            AppLogger.persistence.error("Failed to load/decode data for key \(key): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func decodeMetar(raw: String) -> String {
        // This is a simplistic parser. For production, a more robust solution
        // like regex or a dedicated library would be better.
        var decodedParts: [String] = []
        var components = raw.split(separator: " ").map { String($0) }
        
        if !components.isEmpty { decodedParts.append("Station: \(components.removeFirst())") }
        // ... rest of original METAR parsing logic
        return decodedParts.joined(separator: "\n")
    }
}
