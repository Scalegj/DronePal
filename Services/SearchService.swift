import CoreSpotlight
import SwiftUI

/// A service to manage indexing and searching of flight logs using Core Spotlight.
class SearchService {

    /// Creates a searchable item attribute set for a given flight log.
    /// This maps the flight log's data to Core Spotlight attributes.
    private func attributeSet(for log: FlightLog) -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .data)
        attributeSet.title = log.location
        
        var keywords = [
            log.location,
            log.pilotInCommand,
            log.missionNotes,
            log.weather.icao,
            log.weather.metar,
            log.weather.decodedMetar
        ]
        
        if let clientInfo = log.clientInfo {
            keywords.append(clientInfo.clientName)
            keywords.append(clientInfo.projectID)
            keywords.append(clientInfo.contactInfo)
        }
        
        for crewMember in log.crew {
            keywords.append(crewMember.personName)
            keywords.append(crewMember.roleName)
        }
        
        attributeSet.contentDescription = """
        Flight on \(log.date.formatted(date: .long, time: .shortened))
        Pilot: \(log.pilotInCommand)
        Duration: \(Formatters.durationPositional.string(from: log.flightDuration) ?? "")
        """
        attributeSet.keywords = keywords.filter { !$0.isEmpty }
        
        return attributeSet
    }

    /// Indexes a single flight log in Core Spotlight.
    func index(log: FlightLog) {
        let attributeSet = attributeSet(for: log)
        
        let item = CSSearchableItem(
            uniqueIdentifier: log.id.uuidString,
            domainIdentifier: "com.scalegj.DronePal.flightlog",
            attributeSet: attributeSet
        )
        
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error = error {
                AppLogger.general.error("Error indexing flight log \(log.id): \(error.localizedDescription)")
            } else {
                AppLogger.general.info("Successfully indexed flight log \(log.id)")
            }
        }
    }

    /// Removes a single flight log from the Core Spotlight index.
    func deindex(log: FlightLog) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [log.id.uuidString]) { error in
            if let error = error {
                AppLogger.general.error("Error deindexing flight log \(log.id): \(error.localizedDescription)")
            } else {
                AppLogger.general.info("Successfully deindexed flight log \(log.id)")
            }
        }
    }
}
