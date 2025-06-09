import SwiftUI

/// A reusable form section for editing core flight details.
struct FlightDetailsSection: View {
    @Binding var log: FlightLog
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Section("Flight Details") {
            Picker("Aircraft", selection: $log.aircraftID) {
                Text("No Aircraft Selected").tag(nil as UUID?)
                ForEach(viewModel.drones) { drone in
                    Text(drone.displayName).tag(drone.id as UUID?)
                }
            }
            TextField("Location", text: $log.location)
            TextField("Pilot in Command", text: $log.pilotInCommand)
        }
    }
}

/// A reusable form section for adding/editing additional crew members.
struct AdditionalCrewSection: View {
    @Binding var log: FlightLog
    @Binding var isUsingPMTC: Bool
    @Binding var isUsingVO: Bool
    
    var body: some View {
        Section("Additional Crew") {
            Toggle("PMTC Performed?", isOn: $isUsingPMTC.animation())
            if isUsingPMTC {
                TextField("PMTC Performed By", text: Binding($log.pmtcBy, default: ""))
            }
            Toggle("Visual Observer Used?", isOn: $isUsingVO.animation())
            if isUsingVO {
                TextField("Visual Observer Name", text: Binding($log.visualObserver, default: ""))
            }
        }
    }
}

/// A reusable form section for editing mission notes.
struct MissionNotesSection: View {
    @Binding var notes: String
    
    var body: some View {
        Section("Mission Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .padding(.leading, -4) // Align with TextField
        }
    }
}

/// A reusable form section for fetching and displaying weather data.
struct WeatherSection: View {
    @Binding var weather: WeatherData
    let fetchAction: () async -> Void
    
    var body: some View {
        Section("Weather") {
            HStack {
                TextField("Airport ICAO (e.g., KLAX)", text: $weather.icao)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .font(.system(.body, design: .monospaced))
            
                Button("Fetch") {
                    Task { await fetchAction() }
                }
                .disabled(weather.icao.count != 4)
            }
            InfoRow(label: "Raw METAR", value: weather.metar, multiline: true)
            InfoRow(label: "Decoded METAR", value: weather.decodedMetar, multiline: true)
        }
    }
}
