import Foundation
import CoreBluetooth
import CoreLocation

// MARK: - Custom Codable Coordinate
// A codable struct to allow storing CLLocationCoordinate2D in UserDefaults
struct CodableCoordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    // Helper to convert to a CoreLocation coordinate
    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct AppData: Codable {
    var flightLogs: [FlightLog]
    var drones: [Drone]
    var checklists: [Checklist]
    var userSettings: UserSettings
    
    // Provides a clean, empty state for the first app launch
    static var empty: AppData {
        AppData(flightLogs: [], drones: [], checklists: [], userSettings: UserSettings())
    }
}

// MARK: - Flight Area Model
// A struct to hold the defined flight area details
struct FlightArea: Codable, Hashable {
    var boundary: [CodableCoordinate] // For the drawn polygon
    var maxAGL: Double // User-defined max altitude in meters
}


// MARK: - Device & Bluetooth Models

/// Represents a discovered Remote ID device, processing and exposing its data for the UI.
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

// MARK: - Application Data Models

enum PilotType: String, Codable, CaseIterable, Identifiable {
    case part107 = "Part 107"
    case recreational = "Recreational"
    var id: String { self.rawValue }
}

/// A struct to represent a user-defined crew role.
struct CrewRole: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}

struct UserSettings: Codable {
    var pilotName: String
    var pilotType: PilotType
    var part107InitialCertificateDate: Date
    var part107LastRecurrencyDate: Date
    var recreationalTRUSTDate: Date
    var customCrewRoles: [CrewRole]

    // **FIX START**: Implement custom decoder and encoder for UserSettings
    
    enum CodingKeys: String, CodingKey {
        case pilotName, pilotType, part107InitialCertificateDate, part107LastRecurrencyDate, recreationalTRUSTDate, customCrewRoles
    }

    // Default initializer
    init(pilotName: String = "", pilotType: PilotType = .part107, part107InitialCertificateDate: Date = Date(), part107LastRecurrencyDate: Date = Date(), recreationalTRUSTDate: Date = Date(), customCrewRoles: [CrewRole] = [
            CrewRole(id: UUID(), name: "Person Manipulating the Controls"),
            CrewRole(id: UUID(), name: "Visual Observer")
        ]) {
        self.pilotName = pilotName
        self.pilotType = pilotType
        self.part107InitialCertificateDate = part107InitialCertificateDate
        self.part107LastRecurrencyDate = part107LastRecurrencyDate
        self.recreationalTRUSTDate = recreationalTRUSTDate
        self.customCrewRoles = customCrewRoles
    }
    
    // Custom Decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pilotName = try container.decodeIfPresent(String.self, forKey: .pilotName) ?? ""
        pilotType = try container.decodeIfPresent(PilotType.self, forKey: .pilotType) ?? .part107
        part107InitialCertificateDate = try container.decodeIfPresent(Date.self, forKey: .part107InitialCertificateDate) ?? Date()
        part107LastRecurrencyDate = try container.decodeIfPresent(Date.self, forKey: .part107LastRecurrencyDate) ?? Date()
        recreationalTRUSTDate = try container.decodeIfPresent(Date.self, forKey: .recreationalTRUSTDate) ?? Date()
        
        // If 'customCrewRoles' key is missing, provide the default value.
        customCrewRoles = try container.decodeIfPresent([CrewRole].self, forKey: .customCrewRoles) ?? [
            CrewRole(id: UUID(), name: "Person Manipulating the Controls"),
            CrewRole(id: UUID(), name: "Visual Observer")
        ]
    }
    
    // Custom Encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pilotName, forKey: .pilotName)
        try container.encode(pilotType, forKey: .pilotType)
        try container.encode(part107InitialCertificateDate, forKey: .part107InitialCertificateDate)
        try container.encode(part107LastRecurrencyDate, forKey: .part107LastRecurrencyDate)
        try container.encode(recreationalTRUSTDate, forKey: .recreationalTRUSTDate)
        try container.encode(customCrewRoles, forKey: .customCrewRoles)
    }
    // **FIX END**
}


struct FlightSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var startTime: Date
    var endTime: Date?

    var duration: TimeInterval {
        endTime?.timeIntervalSince(startTime) ?? Date().timeIntervalSince(startTime)
    }
}

/// A struct to hold client and project information for a flight.
struct ClientInfo: Codable, Hashable {
    var clientName: String = ""
    var projectID: String = ""
    var contactInfo: String = ""
}

/// A struct to log a specific crew member for a flight.
struct LoggedCrewMember: Identifiable, Codable, Hashable {
    let id: UUID
    var roleName: String
    var personName: String
}

struct FlightLog: Identifiable, Codable {
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
    
    // Custom Codable implementation for backward compatibility
    
    enum CodingKeys: String, CodingKey {
        case id, date, aircraftID, location, pilotInCommand, missionNotes, weather
        case crew, clientInfo
        case loggedRemoteIDs, completedChecklist, segments, flightArea, trashedDate
        // Old keys for migration
        case pmtcBy, visualObserver
    }

    // Memberwise initializer for creating new logs in code
    init(id: UUID = UUID(), date: Date = Date(), aircraftID: UUID? = nil, location: String = "", pilotInCommand: String = "", missionNotes: String = "", weather: WeatherData = WeatherData(), crew: [LoggedCrewMember] = [], clientInfo: ClientInfo? = ClientInfo(), loggedRemoteIDs: [LoggedRemoteID] = [], completedChecklist: [CompletedChecklistItem] = [], segments: [FlightSegment] = [], flightArea: FlightArea? = nil, trashedDate: Date? = nil) {
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

    // Custom decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode all standard properties
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        aircraftID = try container.decodeIfPresent(UUID.self, forKey: .aircraftID)
        location = try container.decode(String.self, forKey: .location)
        pilotInCommand = try container.decode(String.self, forKey: .pilotInCommand)
        missionNotes = try container.decode(String.self, forKey: .missionNotes)
        weather = try container.decode(WeatherData.self, forKey: .weather)
        loggedRemoteIDs = try container.decode([LoggedRemoteID].self, forKey: .loggedRemoteIDs)
        completedChecklist = try container.decode([CompletedChecklistItem].self, forKey: .completedChecklist)
        segments = try container.decode([FlightSegment].self, forKey: .segments)
        flightArea = try container.decodeIfPresent(FlightArea.self, forKey: .flightArea)
        trashedDate = try container.decodeIfPresent(Date.self, forKey: .trashedDate)
        
        // Handle 'clientInfo' (new and optional)
        clientInfo = try container.decodeIfPresent(ClientInfo.self, forKey: .clientInfo)

        // Handle 'crew' by first checking for the new key, then falling back to migrate old keys
        if let decodedCrew = try? container.decodeIfPresent([LoggedCrewMember].self, forKey: .crew) {
            // New format data found, use it directly
            self.crew = decodedCrew
        } else {
            // 'crew' key not found, this is old data. Build the crew list from old properties.
            var migratedCrew: [LoggedCrewMember] = []
            if let pmtcName = try container.decodeIfPresent(String.self, forKey: .pmtcBy), !pmtcName.isEmpty {
                migratedCrew.append(LoggedCrewMember(id: UUID(), roleName: "Person Manipulating the Controls", personName: pmtcName))
            }
            if let voName = try container.decodeIfPresent(String.self, forKey: .visualObserver), !voName.isEmpty {
                migratedCrew.append(LoggedCrewMember(id: UUID(), roleName: "Visual Observer", personName: voName))
            }
            self.crew = migratedCrew
        }
    }
    
    // Custom encoder to satisfy the 'Encodable' conformance
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(aircraftID, forKey: .aircraftID)
        try container.encode(location, forKey: .location)
        try container.encode(pilotInCommand, forKey: .pilotInCommand)
        try container.encode(missionNotes, forKey: .missionNotes)
        try container.encode(weather, forKey: .weather)
        try container.encode(crew, forKey: .crew)
        try container.encodeIfPresent(clientInfo, forKey: .clientInfo)
        try container.encode(loggedRemoteIDs, forKey: .loggedRemoteIDs)
        try container.encode(completedChecklist, forKey: .completedChecklist)
        try container.encode(segments, forKey: .segments)
        try container.encodeIfPresent(flightArea, forKey: .flightArea)
        try container.encodeIfPresent(trashedDate, forKey: .trashedDate)
    }
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

struct Drone: Identifiable, Codable, Hashable {
    let id: UUID
    var company: String
    var model: String
    var faaRegistration: String
    var remoteIdSerial: String

    var displayName: String { "\(company) \(model)" }
}

struct Checklist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var items: [ChecklistItem]
    var isFavorite: Bool

    // We need a memberwise initializer because we are creating a custom decoder init
    init(id: UUID, name: String, items: [ChecklistItem], isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.items = items
        self.isFavorite = isFavorite
    }

    // CodingKeys for all properties
    enum CodingKeys: String, CodingKey {
        case id, name, items, isFavorite
    }

    // Custom decoder initializer to handle missing 'isFavorite' key in old data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.items = try container.decode([ChecklistItem].self, forKey: .items)
        
        // This is the fix: try to decode 'isFavorite', but if the key is not found,
        // default to 'false' instead of throwing an error.
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
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

struct WeatherData: Codable {
    var icao: String = ""
    var metar: String = "Not available"
    var decodedMetar: String = "No decoded data."
}

// Codable struct for parsing the METAR API response.
struct MetarReport: Codable {
    let rawOb: String
}

// MARK: - ODID Data Structures

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
