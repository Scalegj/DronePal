import SwiftUI
import MapKit
import CoreLocation

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
        HStack {
            Text("Aircraft")
            Spacer()
            Menu {
                Button("No Aircraft Selected", action: { log.aircraftID = nil })
                ForEach(viewModel.drones) { drone in
                    Button(drone.displayName) { log.aircraftID = drone.id }
                }
            } label: {
                Text(viewModel.droneForID(log.aircraftID)?.displayName ?? "Select Aircraft")
                    .foregroundColor(.secondary)
            }
        }
        
        NavigationLink(destination: FlightAreaMapView(log: $log)) {
            HStack {
                Text("Location")
                Spacer()
                Text(log.location.isEmpty ? "Set Flight Area" : log.location)
                    .foregroundColor(log.location.isEmpty ? .accentColor : .secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        
        HStack {
            Text("Pilot in Command")
            TextField("Name", text: $log.pilotInCommand)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
    }
}

/// A reusable form section for adding/editing additional crew members.
struct AdditionalCrewSection: View {
    @Binding var crew: [LoggedCrewMember]
    @State private var showManageRolesSheet = false
    @EnvironmentObject private var viewModel: AppViewModel
    
    var body: some View {
        if !crew.isEmpty {
            ForEach(crew.indices, id: \.self) { index in
                HStack {
                    Text(crew[index].roleName)
                        .lineLimit(1)
                    TextField("Name", text: $crew[index].personName)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                }
            }
        }
        
        Button(action: { showManageRolesSheet.toggle() }) {
            HStack {
                Label("Manage Crew Roles", systemImage: "person.crop.circle.badge.plus")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .foregroundColor(.accentColor) // **FIX**: Make the text and icon blue
        }
        .sheet(isPresented: $showManageRolesSheet) {
            ManageCrewRolesView(crew: $crew)
        }
    }
}

/// A view for adding/removing crew roles for a specific flight.
struct ManageCrewRolesView: View {
    @Binding var crew: [LoggedCrewMember]
    @State private var temporaryRoleName: String = ""
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Current Flight Crew") {
                    if crew.isEmpty {
                        Text("No crew members assigned.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(crew) { member in
                        HStack {
                            Text(member.roleName)
                            Spacer()
                            if !viewModel.userSettings.customCrewRoles.contains(where: { $0.name == member.roleName }) {
                                Button("Make Default") {
                                    viewModel.addCrewRole(name: member.roleName)
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .onDelete { offsets in
                        crew.remove(atOffsets: offsets)
                    }
                }
                
                Section("Add from Defaults") {
                    ForEach(viewModel.userSettings.customCrewRoles.filter { role in
                        !crew.contains(where: { $0.roleName == role.name })
                    }) { role in
                        Button(action: {
                            crew.append(LoggedCrewMember(id: UUID(), roleName: role.name, personName: ""))
                        }) {
                            Label(role.name, systemImage: "plus.circle.fill")
                        }
                    }
                }
                
                Section("Add Temporary Role for this Flight") {
                    HStack {
                        TextField("Temporary Role Name", text: $temporaryRoleName)
                        Button("Add") {
                            if !temporaryRoleName.isEmpty {
                                crew.append(LoggedCrewMember(id: UUID(), roleName: temporaryRoleName, personName: ""))
                                temporaryRoleName = ""
                            }
                        }
                        .disabled(temporaryRoleName.isEmpty)
                    }
                }
            }
            .navigationTitle("Manage Flight Crew")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A reusable form section for entering client information.
struct ClientInfoSection: View {
    @Binding var clientInfo: ClientInfo?

    var body: some View {
        let nonOptionalClientInfo = Binding($clientInfo, default: ClientInfo())
        
        HStack {
            Text("Client Name")
            TextField("Name", text: nonOptionalClientInfo.clientName)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        HStack {
            Text("Project ID")
            TextField("ID / Name", text: nonOptionalClientInfo.projectID)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        HStack {
            Text("Contact Info")
            TextField("Email/Phone", text: nonOptionalClientInfo.contactInfo)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
    }
}


/// A reusable form section for editing mission notes.
struct MissionNotesSection: View {
    @Binding var notes: String
    
    var body: some View {
        TextField("Enter mission notes here...", text: $notes, axis: .vertical)
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
