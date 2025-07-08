import Foundation
import CoreBluetooth
import CoreLocation
import CloudKit

// MARK: - Protocol for CloudKit Compatibility
// Defines the common requirements for a model that can be synced with CloudKit.
protocol CloudKitSyncable: Identifiable where ID == UUID {
    var recordID: CKRecord.ID? { get set }
    static var recordType: String { get }
    init?(from record: CKRecord)
    var ckRecord: CKRecord { get }
}

// MARK: - Helper Models (No CloudKit Sync)
// These models are embedded within other objects. They only need to be Codable.

struct CodableCoordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct FlightArea: Codable, Hashable {
    var boundary: [CodableCoordinate]
    var maxAGL: Double
}

class RemoteIDDevice: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var rssi: NSNumber
    @Published var basicID: ODIDBasicID?
    @Published var location: ODIDLocation?
    @Published var lastUpdated: Date

    init(from peripheral: CBPeripheral, rssi: NSNumber) {
        self.id = peripheral.identifier
        self.name = peripheral.name ?? "Drone \(String(peripheral.identifier.uuidString.prefix(4)))"
        self.rssi = rssi
        self.lastUpdated = Date()
    }

    func update(with advertisementData: [String: Any], rssi: NSNumber) {
        self.rssi = rssi
        self.lastUpdated = Date()
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let remoteIDData = serviceData[CBUUID(string: Constants.remoteIDServiceUUID)] else {
            return
        }
        let (newBasicID, newLocation) = ODIDParser.parseMessagePack(data: remoteIDData)
        if let newBasicID = newBasicID { self.basicID = newBasicID }
        if let newLocation = newLocation { self.location = newLocation }
    }
}

enum PilotType: String, Codable, CaseIterable, Identifiable {
    case part107 = "Part 107"
    case recreational = "Recreational"
    var id: String { self.rawValue }
}

struct CrewRole: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}

struct FlightSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval {
        endTime?.timeIntervalSince(startTime) ?? Date().timeIntervalSince(startTime)
    }
}

struct ClientInfo: Codable, Hashable {
    var clientName: String = ""
    var projectID: String = ""
    var contactInfo: String = ""
}

struct LoggedCrewMember: Identifiable, Codable, Hashable {
    let id: UUID
    var roleName: String
    var personName: String
}

struct LoggedRemoteID: Identifiable, Codable, Hashable {
    let id: UUID
    var basicID: ODIDBasicID?
    var telemetry: [TelemetryRecord]
    var displayName: String { basicID?.uasID ?? "Unknown ID" }
}

struct TelemetryRecord: Codable, Hashable {
    let timestamp: Date
    let location: ODIDLocation
    let rssi: Int
}

struct ChecklistItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
}

struct CompletedChecklistItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var isChecked: Bool
    var completionDate: Date?
}

struct WeatherData: Codable, Hashable {
    var icao: String = ""
    var metar: String = "Not available"
    var decodedMetar: String = "No decoded data."
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

// MARK: - CloudKit Syncable Models

struct UserSettings: CloudKitSyncable {
    var recordID: CKRecord.ID?
    let id: UUID
    
    var pilotName: String
    var pilotType: PilotType
    var part107InitialCertificateDate: Date
    var part107LastRecurrencyDate: Date
    var recreationalTRUSTDate: Date
    var customCrewRoles: [CrewRole]

    static let recordType = "UserSettings"
    static let wellKnownRecordID = CKRecord.ID(recordName: "UserSettings-Singleton", zoneID: CloudKitService.customZoneID)

    init(recordID: CKRecord.ID? = wellKnownRecordID,
         id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
         pilotName: String = "",
         pilotType: PilotType = .part107,
         part107InitialCertificateDate: Date = Date(),
         part107LastRecurrencyDate: Date = Date(),
         recreationalTRUSTDate: Date = Date(),
         customCrewRoles: [CrewRole] = [
            CrewRole(id: UUID(), name: "Person Manipulating the Controls"),
            CrewRole(id: UUID(), name: "Visual Observer")
         ]) {
        self.recordID = recordID
        self.id = id
        self.pilotName = pilotName
        self.pilotType = pilotType
        self.part107InitialCertificateDate = part107InitialCertificateDate
        self.part107LastRecurrencyDate = part107LastRecurrencyDate
        self.recreationalTRUSTDate = recreationalTRUSTDate
        self.customCrewRoles = customCrewRoles
    }

    init?(from record: CKRecord) {
        guard
            record.recordID.zoneID == Self.wellKnownRecordID.zoneID,
            let idString = record["id"] as? String,
            let id = UUID(uuidString: idString),
            let pilotName = record["pilotName"] as? String,
            let pilotTypeRaw = record["pilotType"] as? String,
            let pilotType = PilotType(rawValue: pilotTypeRaw),
            let p107InitialDate = record["part107InitialCertificateDate"] as? Date,
            let p107RecurrencyDate = record["part107LastRecurrencyDate"] as? Date,
            let trustDate = record["recreationalTRUSTDate"] as? Date,
            let rolesData = record["customCrewRolesData"] as? Data,
            let customCrewRoles = try? JSONDecoder().decode([CrewRole].self, from: rolesData)
        else {
            return nil
        }
        self.init(recordID: record.recordID, id: id, pilotName: pilotName, pilotType: pilotType, part107InitialCertificateDate: p107InitialDate, part107LastRecurrencyDate: p107RecurrencyDate, recreationalTRUSTDate: trustDate, customCrewRoles: customCrewRoles)
    }

    var ckRecord: CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: self.recordID ?? Self.wellKnownRecordID)
        record["id"] = id.uuidString
        record["pilotName"] = pilotName
        record["pilotType"] = pilotType.rawValue
        record["part107InitialCertificateDate"] = part107InitialCertificateDate
        record["part107LastRecurrencyDate"] = part107LastRecurrencyDate
        record["recreationalTRUSTDate"] = recreationalTRUSTDate
        if let rolesData = try? JSONEncoder().encode(customCrewRoles) {
            record["customCrewRolesData"] = rolesData
        }
        return record
    }
}

// FIX: Added Hashable conformance
struct Drone: CloudKitSyncable, Hashable {
    var recordID: CKRecord.ID?
    let id: UUID
    var company: String
    var model: String
    var faaRegistration: String
    var remoteIdSerial: String

    var displayName: String { "\(company) \(model)" }
    static let recordType = "Drone"

    init(id: UUID = UUID(), recordID: CKRecord.ID? = nil, company: String, model: String, faaRegistration: String, remoteIdSerial: String) {
        self.id = id
        self.recordID = recordID
        self.company = company
        self.model = model
        self.faaRegistration = faaRegistration
        self.remoteIdSerial = remoteIdSerial
    }

    init?(from record: CKRecord) {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let company = record["company"] as? String,
              let model = record["model"] as? String,
              let faaRegistration = record["faaRegistration"] as? String,
              let remoteIdSerial = record["remoteIdSerial"] as? String
        else { return nil }
        self.init(id: id, recordID: record.recordID, company: company, model: model, faaRegistration: faaRegistration, remoteIdSerial: remoteIdSerial)
    }

    var ckRecord: CKRecord {
        let record = recordID != nil ?
            CKRecord(recordType: Self.recordType, recordID: recordID!) :
            CKRecord(recordType: Self.recordType, recordID: .init(recordName: id.uuidString, zoneID: CloudKitService.customZoneID))
        record["id"] = id.uuidString
        record["company"] = company as CKRecordValue
        record["model"] = model as CKRecordValue
        record["faaRegistration"] = faaRegistration as CKRecordValue
        record["remoteIdSerial"] = remoteIdSerial as CKRecordValue
        return record
    }
}

// FIX: Added Hashable conformance
struct Checklist: CloudKitSyncable, Hashable {
    var recordID: CKRecord.ID?
    let id: UUID
    var name: String
    var items: [ChecklistItem]
    var isFavorite: Bool

    static let recordType = "Checklist"

    init(id: UUID = UUID(), recordID: CKRecord.ID? = nil, name: String, items: [ChecklistItem], isFavorite: Bool = false) {
        self.id = id
        self.recordID = recordID
        self.name = name
        self.items = items
        self.isFavorite = isFavorite
    }

    init?(from record: CKRecord) {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["name"] as? String,
              let isFavorite = record["isFavorite"] as? Bool,
              let itemsData = record["itemsData"] as? Data,
              let items = try? JSONDecoder().decode([ChecklistItem].self, from: itemsData)
        else { return nil }
        self.init(id: id, recordID: record.recordID, name: name, items: items, isFavorite: isFavorite)
    }

    var ckRecord: CKRecord {
        let record = recordID != nil ?
            CKRecord(recordType: Self.recordType, recordID: recordID!) :
            CKRecord(recordType: Self.recordType, recordID: .init(recordName: id.uuidString, zoneID: CloudKitService.customZoneID))
        record["id"] = id.uuidString
        record["name"] = name
        record["isFavorite"] = isFavorite
        if let itemsData = try? JSONEncoder().encode(items) {
            record["itemsData"] = itemsData
        }
        return record
    }
}

// FIX: Added Hashable conformance
struct FlightLog: CloudKitSyncable, Hashable {
    var recordID: CKRecord.ID?
    let id: UUID
    var date: Date
    var aircraftID: UUID?
    var location: String
    var pilotInCommand: String
    var missionNotes: String
    var weather: WeatherData
    var crew: [LoggedCrewMember]
    var clientInfo: ClientInfo?
    var loggedRemoteIDs: [LoggedRemoteID]
    var completedChecklist: [CompletedChecklistItem]
    var segments: [FlightSegment]
    var flightArea: FlightArea?
    var trashedDate: Date?

    var flightDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
    static let recordType = "FlightLog"

    init(id: UUID = UUID(), recordID: CKRecord.ID? = nil, date: Date = Date(), aircraftID: UUID? = nil, location: String = "", pilotInCommand: String = "", missionNotes: String = "", weather: WeatherData = WeatherData(), crew: [LoggedCrewMember] = [], clientInfo: ClientInfo? = ClientInfo(), loggedRemoteIDs: [LoggedRemoteID] = [], completedChecklist: [CompletedChecklistItem] = [], segments: [FlightSegment] = [], flightArea: FlightArea? = nil, trashedDate: Date? = nil) {
        self.recordID = recordID
        self.id = id
        self.date = date
        self.aircraftID = aircraftID
        self.location = location
        self.pilotInCommand = pilotInCommand
        self.missionNotes = missionNotes
        self.weather = weather
        self.crew = crew
        self.clientInfo = clientInfo
        self.loggedRemoteIDs = loggedRemoteIDs
        self.completedChecklist = completedChecklist
        self.segments = segments
        self.flightArea = flightArea
        self.trashedDate = trashedDate
    }

    init?(from record: CKRecord) {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let date = record["date"] as? Date,
              let location = record["location"] as? String,
              let pilotInCommand = record["pilotInCommand"] as? String,
              let missionNotes = record["missionNotes"] as? String
        else { return nil }
        
        let weather: WeatherData = (try? record.decode(forKey: "weatherData")) ?? WeatherData()
        let crew: [LoggedCrewMember] = (try? record.decode(forKey: "crewData")) ?? []
        let loggedRemoteIDs: [LoggedRemoteID] = (try? record.decode(forKey: "loggedRemoteIDsData")) ?? []
        let completedChecklist: [CompletedChecklistItem] = (try? record.decode(forKey: "completedChecklistData")) ?? []
        let segments: [FlightSegment] = (try? record.decode(forKey: "segmentsData")) ?? []
        
        let clientInfo: ClientInfo? = try? record.decode(forKey: "clientInfoData")
        let flightArea: FlightArea? = try? record.decode(forKey: "flightAreaData")
        
        let aircraftIDString = record["aircraftID"] as? String
        let aircraftID = aircraftIDString != nil ? UUID(uuidString: aircraftIDString!) : nil
        let trashedDate = record["trashedDate"] as? Date
        
        self.init(id: id, recordID: record.recordID, date: date, aircraftID: aircraftID, location: location, pilotInCommand: pilotInCommand, missionNotes: missionNotes, weather: weather, crew: crew, clientInfo: clientInfo, loggedRemoteIDs: loggedRemoteIDs, completedChecklist: completedChecklist, segments: segments, flightArea: flightArea, trashedDate: trashedDate)
    }

    var ckRecord: CKRecord {
        let record = recordID != nil ?
            CKRecord(recordType: Self.recordType, recordID: recordID!) :
            CKRecord(recordType: Self.recordType, recordID: .init(recordName: id.uuidString, zoneID: CloudKitService.customZoneID))
        
        record["id"] = id.uuidString
        record["date"] = date
        record["location"] = location
        record["pilotInCommand"] = pilotInCommand
        record["missionNotes"] = missionNotes
        
        record["aircraftID"] = aircraftID?.uuidString
        record["trashedDate"] = trashedDate
        
        try? record.encode(weather, forKey: "weatherData")
        try? record.encode(crew, forKey: "crewData")
        try? record.encode(clientInfo, forKey: "clientInfoData")
        try? record.encode(loggedRemoteIDs, forKey: "loggedRemoteIDsData")
        try? record.encode(completedChecklist, forKey: "completedChecklistData")
        try? record.encode(segments, forKey: "segmentsData")
        try? record.encode(flightArea, forKey: "flightAreaData")
        
        return record
    }
}

// MARK: - CKRecord Codable Helpers
extension CKRecord {
    func encode<T: Encodable>(_ value: T?, forKey key: String) throws {
        guard let value = value else {
            self[key] = nil
            return
        }
        let data = try JSONEncoder().encode(value)
        self[key] = data as CKRecordValue
    }
    
    func decode<T: Decodable>(forKey key: String) throws -> T? {
        guard let data = self[key] as? Data else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
