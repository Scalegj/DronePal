import Foundation
import Combine
import CloudKit

@MainActor
class AppViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var bluetoothScanner = BluetoothScanner()
    
    @Published var flightLogs: [FlightLog] = []
    @Published var drones: [Drone] = []
    @Published var checklists: [Checklist] = []
    @Published var userSettings: UserSettings = UserSettings()
    
    @Published var isLoading: Bool = true
    @Published var needsSetup: Bool = true
    @Published var isLoggingFlight = false
    @Published var activeLog = FlightLog()
    @Published var isSegmentActive = false

    // MARK: - Services and State
    private let cloudKitService = CloudKitService()
    private var telemetryTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to remote changes from CloudKitService
        cloudKitService.recordsChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changedRecords in
                self?.mergeRemoteChanges(changedRecords)
            }
            .store(in: &cancellables)
            
        cloudKitService.deletedRecordIDsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deletedIDs in
                self?.handleRemoteDeletions(deletedIDs)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.addObserver(forName: .cloudKitDataChanged, object: nil, queue: .main) { [weak self] _ in
            AppLogger.general.info("AppViewModel received CloudKit data change notification. Fetching changes.")
            guard let self = self else { return }
            
            Task {
                await self.cloudKitService.fetchDatabaseChanges()
            }
        }

        // Propagate changes from the bluetooth scanner
        bluetoothScanner.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
            
        // Initial data fetch from CloudKit
        Task {
            await cloudKitService.createZoneIfNeeded()
            await fetchAllData()
            await subscribeToAllChanges()
            self.isLoading = false
        }
    }
    
    // MARK: - CloudKit Data Operations
    
    private func fetchAllData() async {
        let fetchedDrones = await cloudKitService.fetchRecords(recordType: Drone.recordType)
        self.drones = fetchedDrones.compactMap { Drone(from: $0) }

        let fetchedChecklists = await cloudKitService.fetchRecords(recordType: Checklist.recordType)
        self.checklists = fetchedChecklists.compactMap { Checklist(from: $0) }
        
        let fetchedLogs = await cloudKitService.fetchRecords(recordType: FlightLog.recordType)
        self.flightLogs = fetchedLogs.compactMap { FlightLog(from: $0) }.sorted { $0.date > $1.date }

        if let settingsRecord = await cloudKitService.fetchRecord(withID: UserSettings.wellKnownRecordID) {
            if let settings = UserSettings(from: settingsRecord) {
                self.userSettings = settings
                self.needsSetup = settings.pilotName.trimmingCharacters(in: .whitespaces).isEmpty
            }
        } else {
            self.needsSetup = true
        }

        AppLogger.general.info("Initial fetch completed. Drones: \(self.drones.count), Logs: \(self.flightLogs.count)")
    }
    
    private func subscribeToAllChanges() async {
        await cloudKitService.subscribeToChanges(for: Drone.recordType)
        await cloudKitService.subscribeToChanges(for: Checklist.recordType)
        await cloudKitService.subscribeToChanges(for: FlightLog.recordType)
        await cloudKitService.subscribeToChanges(for: UserSettings.recordType)
    }
    
    private func mergeRemoteChanges(_ records: [CKRecord]) {
        for record in records {
            switch record.recordType {
            case Drone.recordType:
                if let updatedItem = Drone(from: record) { updateOrAppend(item: updatedItem, to: &drones) }
            case Checklist.recordType:
                 if let updatedItem = Checklist(from: record) { updateOrAppend(item: updatedItem, to: &checklists) }
            case FlightLog.recordType:
                 if let updatedItem = FlightLog(from: record) { updateOrAppend(item: updatedItem, to: &flightLogs) }
            case UserSettings.recordType:
                if record.recordID == UserSettings.wellKnownRecordID, let updatedSettings = UserSettings(from: record) {
                    self.userSettings = updatedSettings
                    self.needsSetup = updatedSettings.pilotName.trimmingCharacters(in: .whitespaces).isEmpty
                }
            default: break
            }
        }
    }
    
    private func handleRemoteDeletions(_ recordIDs: [CKRecord.ID]) {
        for recordID in recordIDs {
            drones.removeAll { $0.recordID == recordID }
            checklists.removeAll { $0.recordID == recordID }
            flightLogs.removeAll { $0.recordID == recordID }
        }
    }
    
    private func updateOrAppend<T: CloudKitSyncable>(item: T, to collection: inout [T]) {
        if let index = collection.firstIndex(where: { $0.id == item.id }) {
            collection[index] = item
        } else {
            collection.append(item)
        }
        if T.self == FlightLog.self {
            self.flightLogs.sort { $0.date > $1.date }
        }
    }
    
    // MARK: - Setup Flow
    func finalizeSetup(settings: UserSettings, drones: [Drone], hasDoneRecurrent: Bool) {
        var finalSettings = settings
        if finalSettings.pilotType == .part107 && !hasDoneRecurrent {
            finalSettings.part107LastRecurrencyDate = finalSettings.part107InitialCertificateDate
        }
        
        self.userSettings = finalSettings
        self.drones = drones
        self.needsSetup = false
        
        Task {
            await self.saveUserSettings()
            for drone in drones {
                // ** FIX **: Removed `record:` label
                await cloudKitService.save(drone.ckRecord)
            }
        }
    }

    // MARK: - Flight Logging
    func startNewLog() {
        activeLog = FlightLog()
        activeLog.pilotInCommand = userSettings.pilotName
        activeLog.aircraftID = drones.first?.id
        activeLog.crew = userSettings.customCrewRoles
            .filter { $0.name == "Person Manipulating the Controls" || $0.name == "Visual Observer" }
            .map { LoggedCrewMember(id: UUID(), roleName: $0.name, personName: "") }

        isLoggingFlight = true
        bluetoothScanner.startScanning()
        startTelemetryTimer()
    }
    
    func discardActiveLog() {
        if isSegmentActive { endCurrentSegment() }
        stopTelemetryTimer()
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

    // MARK: - CRUD Operations
    
    private func save<T: CloudKitSyncable>(_ item: T) async {
        // ** FIX **: Removed `record:` label
        await cloudKitService.save(item.ckRecord)
    }

    private func delete<T: CloudKitSyncable>(at offsets: IndexSet, from collection: inout [T]) {
        let itemsToDelete = offsets.map { collection[$0] }
        collection.remove(atOffsets: offsets)
        for item in itemsToDelete {
            guard let recordID = item.recordID else { continue }
            Task { await cloudKitService.delete(recordID: recordID) }
        }
    }

    func saveLog(_ log: FlightLog) {
        var logToSave = log
        logToSave.crew.removeAll { $0.personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        updateOrAppend(item: logToSave, to: &flightLogs)
        Task { await save(logToSave) }
    }
    
    func moveLogToTrash(at offsets: IndexSet) {
        let active = self.activeFlightLogs
        offsets.forEach { index in
            if let logToTrashIndex = flightLogs.firstIndex(where: { $0.id == active[index].id }) {
                var logToTrash = flightLogs[logToTrashIndex]
                logToTrash.trashedDate = Date()
                flightLogs[logToTrashIndex] = logToTrash
                Task { await save(logToTrash) }
            }
        }
    }
    
    func restoreLogFromTrash(at offsets: IndexSet) {
        let trashed = self.trashedFlightLogs
        offsets.forEach { index in
            if let logToRestoreIndex = flightLogs.firstIndex(where: { $0.id == trashed[index].id }) {
                var logToRestore = flightLogs[logToRestoreIndex]
                logToRestore.trashedDate = nil
                flightLogs[logToRestoreIndex] = logToRestore
                Task { await save(logToRestore) }
            }
        }
    }
    
    func deleteLogPermanently(at offsets: IndexSet) {
        let trashed = self.trashedFlightLogs
        let idsToDelete = offsets.map { trashed[$0].id }
        let logOffsetsToDelete = IndexSet(flightLogs.indices.filter { idsToDelete.contains(flightLogs[$0].id) })
        delete(at: logOffsetsToDelete, from: &flightLogs)
    }

    func saveDrone(_ drone: Drone) {
        updateOrAppend(item: drone, to: &drones)
        Task { await save(drone) }
    }
    func deleteDrone(at offsets: IndexSet) { delete(at: offsets, from: &drones) }
    
    func saveChecklist(_ checklist: Checklist) {
        updateOrAppend(item: checklist, to: &checklists)
        Task { await save(checklist) }
    }
    func deleteChecklist(at offsets: IndexSet) { delete(at: offsets, from: &checklists) }
    
    func toggleFavorite(for checklist: Checklist) {
        if let index = checklists.firstIndex(where: { $0.id == checklist.id }) {
            var updatedChecklist = checklist
            updatedChecklist.isFavorite.toggle()
            checklists[index] = updatedChecklist
            Task { await save(updatedChecklist) }
        }
    }
    
    func saveUserSettings() async {
        var settingsToSave = self.userSettings
        settingsToSave.recordID = UserSettings.wellKnownRecordID
        // ** FIX **: Removed `record:` label
        await cloudKitService.save(settingsToSave.ckRecord)
    }
    
    func addCrewRole(name: String) {
        let newRole = CrewRole(id: UUID(), name: name)
        userSettings.customCrewRoles.append(newRole)
        Task { await saveUserSettings() }
    }
    
    func deleteCrewRole(roleToDelete: CrewRole) {
        userSettings.customCrewRoles.removeAll { $0.id == roleToDelete.id }
        Task { await saveUserSettings() }
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
            struct MetarReport: Codable { let rawOb: String }
            let metarReports = try JSONDecoder().decode([MetarReport].self, from: data)
            if let report = metarReports.first {
                self.activeLog.weather.metar = report.rawOb
            } else {
                self.activeLog.weather.metar = "METAR not found for \(icao)"
            }
        } catch {
            AppLogger.network.error("Error fetching or parsing METAR for \(icao): \(error.localizedDescription)")
            self.activeLog.weather.metar = "Error fetching METAR."
        }
    }
    
    // MARK: - Computed Properties & Helpers
    var activeFlightLogs: [FlightLog] { flightLogs.filter { $0.trashedDate == nil } }
    var trashedFlightLogs: [FlightLog] { flightLogs.filter { $0.trashedDate != nil }.sorted { $0.trashedDate! > $1.trashedDate! } }
    var totalFlightTime: TimeInterval { activeFlightLogs.reduce(0) { $0 + $1.flightDuration } }
    var recurrencyExpirationDate: Date? {
        guard userSettings.pilotType == .part107 else { return nil }
        return Calendar.current.date(byAdding: .month, value: 24, to: userSettings.part107LastRecurrencyDate)
    }
    var daysUntilRecurrencyExpires: Int? {
        guard let expirationDate = recurrencyExpirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }
    func droneForID(_ id: UUID?) -> Drone? { drones.first { $0.id == id } }
    func mostFlownDrone() -> Drone? {
        let flightCounts = activeFlightLogs.reduce(into: [UUID: Int]()) { counts, log in
            guard let id = log.aircraftID else { return }; counts[id, default: 0] += 1
        }
        guard let topDroneID = flightCounts.max(by: { $0.value < $1.value })?.key else { return drones.first }
        return droneForID(topDroneID)
    }
    
    // MARK: - Private Methods
    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordTelemetrySnapshot() }
        }
    }
    private func stopTelemetryTimer() { telemetryTimer?.invalidate(); telemetryTimer = nil }
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
}
