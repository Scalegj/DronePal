import SwiftUI
import MapKit // MODIFIED: Imported to support MapKit views
import CoreLocation // MODIFIED: Imported to support CoreLocation types

// MODIFIED: Moved FlightAreaMapView and its dependencies here to fix scope issues.

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async {
            self.userLocation = locations.first
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get user location: \(error.localizedDescription)")
    }
}

// MARK: - Flight Area Map View
struct FlightAreaMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var log: FlightLog

    @StateObject private var locationManager = LocationManager()
    @State private var position: MapCameraPosition = .automatic
    @State private var initialLocationSet = false
    
    @State private var drawnPoints: [CLLocationCoordinate2D] = []
    @State private var maxAGLText: String = ""
    
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { reader in
                    Map(position: $position) {
                        UserAnnotation()
                        
                        if !drawnPoints.isEmpty {
                            MapPolygon(coordinates: drawnPoints)
                                .foregroundStyle(.blue.opacity(0.3))
                            MapPolygon(coordinates: drawnPoints)
                                .stroke(.blue, lineWidth: 2)
                        }
                        
                        ForEach(Array(drawnPoints.enumerated()), id: \.offset) { index, point in
                             Annotation("Point \(index + 1)", coordinate: point) {
                                Image(systemName: "\(index + 1).circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white, .blue)
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .onTapGesture { screenPoint in
                        if let location = reader.convert(screenPoint, from: .local) {
                            drawnPoints.append(location)
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                VStack {
                    HStack {
                        Spacer()
                        MapUserLocationButton()
                        MapPitchToggle()
                    }
                    .padding()
                    .buttonStyle(.borderedProminent)

                    Spacer()
                    bottomControlsView
                }
            }
            .navigationTitle("Define Flight Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveAndDismiss) {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(drawnPoints.count < 3 || isSaving)
                }
            }
            .onAppear(perform: onAppear)
            .onReceive(locationManager.$userLocation) { location in
                if let location, !initialLocationSet {
                    if log.flightArea == nil {
                        position = .region(MKCoordinateRegion(
                            center: location.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                        initialLocationSet = true
                    }
                }
            }
        }
    }

    private var bottomControlsView: some View {
        VStack {
            HStack {
                Button("Clear", systemImage: "trash") { drawnPoints.removeAll() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                
                Spacer()
                
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    if !drawnPoints.isEmpty { drawnPoints.removeLast() }
                }
                .buttonStyle(.bordered)
                .disabled(drawnPoints.isEmpty)
            }
            .padding([.horizontal, .top])
            
            StyledSection {
                HStack {
                    Text("Maximum AGL (feet)")
                    TextField("e.g., 400", text: $maxAGLText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding([.horizontal, .bottom])
        }
        .background(.thinMaterial)
    }
    
    private func onAppear() {
        setupFromLog()
        if log.flightArea == nil {
            locationManager.requestLocation()
        } else {
            initialLocationSet = true
        }
    }
    
    private func setupFromLog() {
        if let area = log.flightArea {
            self.drawnPoints = area.boundary.map { $0.clLocationCoordinate2D }
            self.maxAGLText = String(area.maxAGL)
            
            if !drawnPoints.isEmpty, let region = MKCoordinateRegion(coordinates: drawnPoints) {
                self.position = .region(region)
            }
        }
    }
    
    private func saveAndDismiss() {
        guard !isSaving else { return }
        isSaving = true
        
        let center = calculateCenter(of: drawnPoints)
        guard let validCenter = center else {
            isSaving = false; return
        }
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: validCenter.latitude, longitude: validCenter.longitude)) { placemarks, error in
            
            let locationString: String
            if let placemark = placemarks?.first {
                locationString = [placemark.name, placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            } else {
                locationString = String(format: "Area near %.4f, %.4f", validCenter.latitude, validCenter.longitude)
            }
            
            let codableCoords = drawnPoints.map { CodableCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            
            let newFlightArea = FlightArea(
                boundary: codableCoords,
                maxAGL: Double(maxAGLText) ?? 0.0
            )
            
            log.flightArea = newFlightArea
            log.location = locationString
            
            isSaving = false
            dismiss()
        }
    }
    
    private func calculateCenter(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coordinates.isEmpty else { return nil }
        
        let avgLat = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
        let avgLon = coordinates.reduce(0) { $0 + $1.longitude } / Double(coordinates.count)
        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
    }
}

// Helper to create a map region that fits all coordinates.
extension MKCoordinateRegion {
    init?(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return nil }

        var minLat = coordinates[0].latitude, maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude, maxLon = coordinates[0].longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.4, longitudeDelta: (maxLon - minLon) * 1.4)
        self.init(center: center, span: span)
    }
}

/// A reusable form section for editing core flight details.
struct FlightDetailsSection: View {
    @Binding var log: FlightLog
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        // MODIFIED: Replaced Picker with a Menu for a cleaner UI.
        HStack {
            Text("Aircraft")
            Spacer()
            Menu {
                // A Button is used for each item in the Menu.
                Button("No Aircraft Selected", action: { log.aircraftID = nil })
                ForEach(viewModel.drones) { drone in
                    Button(drone.displayName) { log.aircraftID = drone.id }
                }
            } label: {
                // The label shows the currently selected value.
                Text(viewModel.droneForID(log.aircraftID)?.displayName ?? "Select Aircraft")
                    .foregroundColor(.secondary)
            }
        }
        
        // MODIFIED: Adjusted text colors for clarity.
        NavigationLink(destination: FlightAreaMapView(log: $log)) {
            HStack {
                Text("Location")
                Spacer()
                Text(log.location.isEmpty ? "Set Flight Area" : log.location)
                    // Highlight "Set Flight Area" in accent color, otherwise use secondary color.
                    .foregroundColor(log.location.isEmpty ? .accentColor : .secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .foregroundStyle(.primary) // Prevents the "Location" label from turning blue.
        
        // MODIFIED: Updated label to be more descriptive as requested.
        HStack {
            Text("Pilot in Command: ")
                .font(.callout)
            TextField("Name", text: $log.pilotInCommand)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A reusable form section for adding/editing additional crew members.
struct AdditionalCrewSection: View {
    @Binding var log: FlightLog
    @Binding var isUsingPMTC: Bool
    @Binding var isUsingVO: Bool
    
    var body: some View {
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

/// A reusable form section for editing mission notes.
struct MissionNotesSection: View {
    @Binding var notes: String
    
    var body: some View {
        TextField("Enter mission notes here...", text: $notes, axis: .vertical)
             // MODIFIED: Removed the incorrect .lineLimit modifier.
            .frame(minHeight: 100, alignment: .top)
    }
}

/// A reusable form section for fetching and displaying weather data.
struct WeatherSection: View {
    @Binding var weather: WeatherData
    let fetchAction: () async -> Void
    
    var body: some View {
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
