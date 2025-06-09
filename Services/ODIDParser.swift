import Foundation

/// A dedicated service to parse Open Drone ID (ODID) message packs from Bluetooth advertisement data.
/// This parser correctly handles variable-length messages as defined by the ASTM F3411 standard.
struct ODIDParser {
    
    private enum MessagePayload {
        case basicID(ODIDBasicID)
        case location(ODIDLocation)
        case unsupported
    }

    /// Parses a full message pack and returns the latest valid Basic ID and Location data found.
    static func parseMessagePack(data: Data) -> (basicID: ODIDBasicID?, location: ODIDLocation?) {
        var latestBasicID: ODIDBasicID?
        var latestLocation: ODIDLocation?

        // Per standard, skip the first 2 bytes of the service data.
        var currentIndex = 2
        while currentIndex < data.count {
            guard let message = parseNextMessage(from: data, at: currentIndex) else {
                AppLogger.bluetooth.warning("Failed to parse ODID message at index \(currentIndex). Stopping.")
                break
            }

            switch message.payload {
            case .basicID(let id): latestBasicID = id
            case .location(let loc): latestLocation = loc
            case .unsupported: break
            }
            
            currentIndex += message.bytesConsumed
        }
        return (latestBasicID, latestLocation)
    }

    private static func parseNextMessage(from data: Data, at index: Int) -> (payload: MessagePayload, bytesConsumed: Int)? {
        guard index < data.count else { return nil }

        let messageHeader = data[index]
        let messageType = Int(messageHeader >> 4)
        
        var messageLength: Int
        var payload: MessagePayload = .unsupported
        
        switch messageType {
        case 0: // Basic ID
            messageLength = 25 // Use literal value
            guard index + messageLength <= data.count else { return nil }
            let messageData = data.subdata(in: index ..< (index + messageLength))
            if let id = parseBasicID(message: messageData) { payload = .basicID(id) }
            
        case 1: // Location
            messageLength = 25 // Use literal value
            guard index + messageLength <= data.count else { return nil }
            let messageData = data.subdata(in: index ..< (index + messageLength))
            if let loc = parseLocation(message: messageData) { payload = .location(loc) }
            
        default:
            AppLogger.bluetooth.debug("Unsupported ODID message type encountered: \(messageType)")
            return nil // Stop parsing if we hit a message type we don't understand.
        }
        
        return (payload, messageLength)
    }

    private static func parseBasicID(message: Data) -> ODIDBasicID? {
        // Use literal value in guard statement
        guard message.count == 25 else { return nil }

        let idTypeValue = message[1]
        let idType: String
        switch idTypeValue {
        case 0x1: idType = "Serial Number"
        case 0x2: idType = "FAA Registration ID"
        default: return nil
        }

        let uasIDBytes = message.subdata(in: 2..<22)
        let uasID = String(data: uasIDBytes, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "") ?? ""
        
        return uasID.isEmpty ? nil : ODIDBasicID(idType: idType, uasID: uasID)
    }

    private static func parseLocation(message: Data) -> ODIDLocation? {
        // Use literal value in guard statement
        guard message.count >= 25 else { return nil }

        // Scaling factors and offsets are per the ASTM F3411-22a / ASD-STAN prEN 4709-002 standards.
        let status = "Airborne"
        let direction = Double(message.read(as: UInt16.self, at: 2)) * 0.01 // Degrees
        let speedHorizontal = Double(message.read(as: UInt16.self, at: 4)) * 0.25 // m/s
        let speedVertical = Double(message.read(as: Int8.self, at: 6)) * 0.5 // m/s
        let latitude = Double(message.read(as: Int32.self, at: 8)) / 1e7 // Degrees
        let longitude = Double(message.read(as: Int32.self, at: 12)) / 1e7 // Degrees
        let altitudeGeodetic = message.toFloat16(at: 16) * 0.5 - 1000 // meters
        let height = message.toFloat16(at: 18) * 0.5 - 1000 // meters
        let heightType = message[1] & 0x01 == 1 ? "Above Ground" : "Above Takeoff"

        return ODIDLocation(status: status, direction: direction, speedHorizontal: speedHorizontal, speedVertical: speedVertical, latitude: latitude, longitude: longitude, altitudeGeodetic: Double(altitudeGeodetic), height: Double(height), heightType: heightType)
    }
}
