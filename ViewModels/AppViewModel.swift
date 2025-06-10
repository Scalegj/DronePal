import Foundation
import Combine

/// The primary ViewModel for the application, responsible for state management and business logic.
/// This class acts as the "source of truth" for the views, loading from and saving to a single JSON file.
@MainActor
class AppViewModel: ObservableObject {
    // MARK: Published Properties
    @Published var bluetoothScanner = BluetoothScanner()
    
    // These properties represent the entire state of the app's user-created data.
    @Published var flightLogs: [FlightLog] = []
    @Published var drones: [Drone] = []
    @Published var checklists: [Checklist] = []
    @Published var userSettings: UserSettings = UserSettings()
    
    // Properties managing the live state of the UI and flight logging.
    @Published var needsSetup: Bool = false
    @Published var isLoggingFlight = false
    @Published var activeLog = FlightLog()
    @Published var isSegmentActive = false

    private let persistenceService = PersistenceService()
    private var telemetryTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load all data from the JSON file on startup.
        loadData()
        
        // UserDefaults is still appropriate for simple, non-critical flags like this.
        self.needsSetup = !UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.setupCompleted)

        // Propagate changes from the scanner to this ViewModel's subscribers.
        bluetoothScanner.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
            
        // Clean up stale items from the trash on app launch.
        purgeStaleTrashedLogs()
    }
    
    // MARK: - Data Persistence
    
    /// Loads the entire application state from the JSON file via the PersistenceService.
    private func loadData() {
        let appData = persistenceService.load()
        self.flightLogs = appData.flightLogs
        self.drones = appData.drones
        self.checklists = appData.checklists
        self.userSettings = appData.userSettings
    }
    
    /// Collects the entire application state and saves it to the JSON file.
    /// This is the single source of truth for saving data.
    private func saveData() {
        let currentData = AppData(
            flightLogs: self.flightLogs,
            drones: self.drones,
            checklists: self.checklists,
            userSettings: self.userSettings
        )
        persistenceService.save(appData: currentData)
    }

    // MARK: - Setup Flow
    func finalizeSetup(settings: UserSettings, drones: [Drone], hasDoneRecurrent: Bool) {
        var finalSettings = settings
        if finalSettings.pilotType == .part107 && !hasDoneRecurrent {
            finalSettings.part107LastRecurrencyDate = finalSettings.part107InitialCertificateDate
        }
        
        self.userSettings = finalSettings
        self.drones = drones
        
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.setupCompleted)
        needsSetup = false
        
        saveData()
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
        isLoggingFlight = false
        bluetoothScanner.stopScanning()
        // No save here, the log was never added to the main array.
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
    
    private func saveLog(_ log: FlightLog) {
        if let index = self.flightLogs.firstIndex(where: { $0.id == log.id }) {
            self.flightLogs[index] = log
        } else {
            // Sort by date descending when inserting a new log.
            self.flightLogs.append(log)
            self.flightLogs.sort { $0.date > $1.date }
        }
        saveData()
    }
    
    func moveLogToTrash(at offsets: IndexSet) {
        let activeLogs = self.activeFlightLogs
        let logsToMove = offsets.map { activeLogs[$0] }
        
        for log in logsToMove {
            if let index = self.flightLogs.firstIndex(where: { $0.id == log.id }) {
                self.flightLogs[index].trashedDate = Date()
            }
        }
        saveData()
    }
    
    func restoreLogFromTrash(at offsets: IndexSet) {
        let trashed = self.trashedFlightLogs
        let logsToRestore = offsets.map { trashed[$0] }
        
        for log in logsToRestore {
            if let index = self.flightLogs.firstIndex(where: { $0.id == log.id }) {
                self.flightLogs[index].trashedDate = nil
            }
        }
        saveData()
    }
    
    func deleteLogPermanently(at offsets: IndexSet) {
        let trashed = self.trashedFlightLogs
        let idsToDelete = offsets.map { trashed[$0].id }
        self.flightLogs.removeAll { idsToDelete.contains($0.id) }
        saveData()
    }

    func saveDrone(drone: Drone) {
        if let index = drones.firstIndex(where: { $0.id == drone.id }) {
            drones[index] = drone
        } else {
            drones.append(drone)
        }
        saveData()
    }
    
    func saveChecklist(_ checklist: Checklist) {
        if let index = checklists.firstIndex(where: { $0.id == checklist.id }) {
            checklists[index] = checklist
        } else {
            checklists.append(checklist)
        }
        saveData()
    }
    
    func toggleFavorite(for checklist: Checklist) {
        if let index = checklists.firstIndex(where: { $0.id == checklist.id }) {
            checklists[index].isFavorite.toggle()
            saveData()
        }
    }
    
    func saveUserSettings() {
        // This function now simply triggers a save of the entire app's data.
        saveData()
    }
    
    func deleteDrone(at offsets: IndexSet) {
        drones.remove(atOffsets: offsets)
        saveData()
    }
    
    func deleteChecklist(at offsets: IndexSet) {
        checklists.remove(atOffsets: offsets)
        saveData()
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
    
    var favoriteChecklistCount: Int {
        checklists.filter { $0.isFavorite }.count
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
    
    func mostFlownDrone() -> Drone? {
        // CORRECTION: Explicitly define the dictionary type to resolve ambiguity.
        let flightCounts = activeFlightLogs.reduce(into: [UUID: Int]()) { counts, log in
            guard let id = log.aircraftID else { return }
            counts[id, default: 0] += 1
        }
        
        // Find the drone ID with the highest count
        guard let topDroneID = flightCounts.max(by: { $0.value < $1.value })?.key else {
            return drones.first
        }
        
        return droneForID(topDroneID)
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
            saveData()
        }
    }

    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()
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
    
    private func decodeMetar(raw: String) -> String {
        // This is a simplistic parser. For production, a more robust solution
        // like regex or a dedicated library would be better.
        var decodedParts: [String] = []
        let components = raw.split(separator: " ").map { String($0) }
        
        if !components.isEmpty {
            // Simplified logic as the original was incomplete
            decodedParts.append("Station: \(components.first ?? "N/A")")
        }
        return decodedParts.joined(separator: "\n")
    }
}
