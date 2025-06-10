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

struct UserSettings: Codable {
    var pilotName: String = ""
    var pilotType: PilotType = .part107
    var part107InitialCertificateDate: Date = Date()
    var part107LastRecurrencyDate: Date = Date()
    var recreationalTRUSTDate: Date = Date()
}

struct FlightSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var startTime: Date
    var endTime: Date?

    var duration: TimeInterval {
        endTime?.timeIntervalSince(startTime) ?? Date().timeIntervalSince(startTime)
    }
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
    var loggedRemoteIDs: [LoggedRemoteID]
    var completedChecklist: [CompletedChecklistItem]
    var segments: [FlightSegment]
    var flightArea: FlightArea?
    var trashedDate: Date?

    var flightDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
    
    init(id: UUID = UUID(), date: Date = Date(), aircraftID: UUID? = nil, location: String = "", pilotInCommand: String = "", missionNotes: String = "", weather: WeatherData = WeatherData(), pmtcBy: String? = nil, visualObserver: String? = nil, loggedRemoteIDs: [LoggedRemoteID] = [], completedChecklist: [CompletedChecklistItem] = [], segments: [FlightSegment] = [], flightArea: FlightArea? = nil, trashedDate: Date? = nil) {
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
        self.flightArea = flightArea
        self.trashedDate = trashedDate
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
