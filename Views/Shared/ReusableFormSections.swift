import SwiftUI
import MapKit
import CoreLocation

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: CLLocation?
    override init() { super.init(); manager.delegate = self }
    func requestLocation() { manager.requestWhenInUseAuthorization(); manager.requestLocation() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { self.userLocation = locations.first }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { print("Location error: \(error.localizedDescription)") }
}

// MARK: - Legacy Map View for iOS 16
struct LegacyMapView: UIViewRepresentable {
    @Binding var drawnPoints: [CLLocationCoordinate2D]
    @Binding var userLocation: CLLocation?
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(); mapView.delegate = context.coordinator; mapView.showsUserLocation = true
        let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(gestureRecognizer)
        return mapView
    }
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeOverlays(uiView.overlays)
        if !drawnPoints.isEmpty { uiView.addOverlay(MKPolygon(coordinates: &drawnPoints, count: drawnPoints.count)) }
        if let location = userLocation, !context.coordinator.initialLocationSet {
            uiView.setRegion(MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)), animated: true)
            context.coordinator.initialLocationSet = true
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LegacyMapView; var initialLocationSet = false
        init(_ parent: LegacyMapView) { self.parent = parent }
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let mapView = gesture.view as! MKMapView
            let coordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            parent.drawnPoints.append(coordinate)
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor.blue.withAlphaComponent(0.3); renderer.strokeColor = .blue; renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer()
        }
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) { parent.userLocation = userLocation.location }
    }
}

// MARK: - iOS 17+ Map View Content
@available(iOS 17.0, *)
private struct FlightAreaMapViewContent: View {
    @Binding var log: FlightLog; @ObservedObject var locationManager: LocationManager
    @Binding var drawnPoints: [CLLocationCoordinate2D]; @Binding var initialLocationSet: Bool
    @State private var position: MapCameraPosition = .automatic
    var body: some View {
        MapReader { reader in
            Map(position: $position) {
                UserAnnotation()
                if !drawnPoints.isEmpty {
                    MapPolygon(coordinates: drawnPoints).foregroundStyle(.blue.opacity(0.3))
                    MapPolygon(coordinates: drawnPoints).stroke(.blue, lineWidth: 2)
                }
                ForEach(Array(drawnPoints.enumerated()), id: \.offset) { index, point in
                     Annotation("Point \(index + 1)", coordinate: point) {
                        Image(systemName: "\(index + 1).circle.fill").font(.title2).foregroundStyle(.white, .blue).shadow(radius: 2)
                    }
                }
            }
            .onTapGesture { screenPoint in
                if let location = reader.convert(screenPoint, from: .local) { drawnPoints.append(location) }
            }
            .onReceive(locationManager.$userLocation) { location in
                if let location, !initialLocationSet {
                    if log.flightArea == nil {
                        position = .region(MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                        initialLocationSet = true
                    }
                }
            }
            .onAppear {
                if let area = log.flightArea, !area.boundary.isEmpty, let region = MKCoordinateRegion(coordinates: area.boundary.map({$0.clLocationCoordinate2D})) {
                    position = .region(region)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Flight Area Map View
struct FlightAreaMapView: View {
    @Environment(\.dismiss) private var dismiss; @Binding var log: FlightLog
    @StateObject private var locationManager = LocationManager(); @State private var initialLocationSet = false
    @State private var drawnPoints: [CLLocationCoordinate2D] = []; @State private var maxAGLText: String = ""
    @State private var isSaving = false
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if #available(iOS 17.0, *) {
                    FlightAreaMapViewContent(log: $log, locationManager: locationManager, drawnPoints: $drawnPoints, initialLocationSet: $initialLocationSet)
                } else {
                    LegacyMapView(drawnPoints: $drawnPoints, userLocation: $locationManager.userLocation).ignoresSafeArea(edges: .bottom)
                }
                VStack {
                    if #available(iOS 17.0, *) {
                        HStack { Spacer(); MapUserLocationButton(); MapPitchToggle() }.padding().buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    bottomControlsView
                }
            }
            .navigationTitle("Define Flight Area").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveAndDismiss) { if isSaving { ProgressView() } else { Text("Save") } }.disabled(drawnPoints.count < 3 || isSaving)
                }
            }
            .onAppear(perform: onAppear)
        }
    }
    private var bottomControlsView: some View {
        VStack {
            HStack {
                Button("Clear", systemImage: "trash") { drawnPoints.removeAll() }.buttonStyle(.bordered).tint(.red)
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") { if !drawnPoints.isEmpty { drawnPoints.removeLast() } }.buttonStyle(.bordered).disabled(drawnPoints.isEmpty)
            }.padding([.horizontal, .top])
            StyledSection {
                HStack { Text("Maximum AGL (feet)"); TextField("e.g., 400", text: $maxAGLText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }.padding([.horizontal, .bottom])
        }.background(.thinMaterial)
    }
    private func onAppear() {
        if let area = log.flightArea {
            self.drawnPoints = area.boundary.map { $0.clLocationCoordinate2D }
            self.maxAGLText = String(area.maxAGL)
        }
        if log.flightArea == nil { locationManager.requestLocation() } else { initialLocationSet = true }
    }
    private func saveAndDismiss() {
        guard !isSaving else { return }; isSaving = true
        guard let validCenter = calculateCenter(of: drawnPoints) else { isSaving = false; return }
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: validCenter.latitude, longitude: validCenter.longitude)) { placemarks, error in
            let locationString = (placemarks?.first.flatMap { [ $0.name, $0.locality, $0.administrativeArea ].compactMap { $0 }.joined(separator: ", ") }) ?? String(format: "Area near %.4f, %.4f", validCenter.latitude, validCenter.longitude)
            log.flightArea = FlightArea(boundary: drawnPoints.map { CodableCoordinate(latitude: $0.latitude, longitude: $0.longitude) }, maxAGL: Double(maxAGLText) ?? 0.0)
            log.location = locationString; isSaving = false; dismiss()
        }
    }
    private func calculateCenter(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coordinates.isEmpty else { return nil }
        let avgLat = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
        let avgLon = coordinates.reduce(0) { $0 + $1.longitude } / Double(coordinates.count)
        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
    }
}

extension MKCoordinateRegion {
    init?(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return nil }
        var minLat = coordinates[0].latitude, maxLat = coordinates[0].latitude; var minLon = coordinates[0].longitude, maxLon = coordinates[0].longitude
        for coordinate in coordinates { minLat = min(minLat, coordinate.latitude); maxLat = max(maxLat, coordinate.latitude); minLon = min(minLon, coordinate.longitude); maxLon = max(maxLon, coordinate.longitude) }
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
        HStack { Text("Aircraft"); Spacer()
            Menu {
                Button("No Aircraft Selected") { log.aircraftID = nil }
                ForEach(viewModel.drones) { drone in Button(drone.displayName) { log.aircraftID = drone.id } }
            } label: { Text(viewModel.droneForID(log.aircraftID)?.displayName ?? "Select Aircraft").foregroundColor(.secondary) }
        }
        NavigationLink(destination: FlightAreaMapView(log: $log)) {
            HStack { Text("Location"); Spacer(); Text(log.location.isEmpty ? "Set Flight Area" : log.location).foregroundColor(log.location.isEmpty ? .accentColor : .secondary).multilineTextAlignment(.trailing).lineLimit(1) }
        }.foregroundStyle(.primary)
        HStack { Text("Pilot in Command"); TextField("Name", text: $log.pilotInCommand).multilineTextAlignment(.trailing).lineLimit(1) }
    }
}

/// A reusable form section for adding/editing additional crew members.
struct AdditionalCrewSection: View {
    @Binding var crew: [LoggedCrewMember]
    @State private var showManageRolesSheet = false
    var body: some View {
        if !crew.isEmpty {
            ForEach($crew) { $member in
                HStack {
                    Text(member.roleName).lineLimit(1)
                    TextField("Name", text: $member.personName).multilineTextAlignment(.trailing).lineLimit(1)
                }
            }
        }
        Button(action: { showManageRolesSheet.toggle() }) {
            HStack { Label("Manage Crew Roles", systemImage: "person.crop.circle.badge.plus"); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundColor(.secondary.opacity(0.5)) }
            .foregroundColor(.accentColor)
        }.sheet(isPresented: $showManageRolesSheet) { ManageCrewRolesView(crew: $crew) }
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
                    if crew.isEmpty { Text("No crew members assigned.").foregroundStyle(.secondary) }
                    ForEach(crew) { member in
                        HStack {
                            Text(member.roleName); Spacer()
                            if !viewModel.userSettings.customCrewRoles.contains(where: { $0.name == member.roleName }) {
                                Button("Make Default") { viewModel.addCrewRole(name: member.roleName) }.buttonStyle(.borderless).foregroundColor(.accentColor)
                            }
                        }
                    }.onDelete { offsets in crew.remove(atOffsets: offsets) }
                }
                Section("Add from Defaults") {
                    ForEach(viewModel.userSettings.customCrewRoles.filter { role in !crew.contains(where: { $0.roleName == role.name }) }) { role in
                        Button(action: { crew.append(LoggedCrewMember(id: UUID(), roleName: role.name, personName: "")) }) {
                            Label(role.name, systemImage: "plus.circle.fill")
                        }
                    }
                }
                Section("Add Temporary Role for this Flight") {
                    HStack {
                        TextField("Temporary Role Name", text: $temporaryRoleName)
                        Button("Add") { if !temporaryRoleName.isEmpty { crew.append(LoggedCrewMember(id: UUID(), roleName: temporaryRoleName, personName: "")); temporaryRoleName = "" } }.disabled(temporaryRoleName.isEmpty)
                    }
                }
            }.navigationTitle("Manage Flight Crew")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// A reusable form section for entering client information.
struct ClientInfoSection: View {
    @Binding var clientInfo: ClientInfo?
    var body: some View {
        let nonOptionalClientInfo = Binding($clientInfo, default: ClientInfo())
        HStack { Text("Client Name"); TextField("Name", text: nonOptionalClientInfo.clientName).multilineTextAlignment(.trailing).lineLimit(1) }
        HStack { Text("Project ID"); TextField("ID / Name", text: nonOptionalClientInfo.projectID).multilineTextAlignment(.trailing).lineLimit(1) }
        HStack { Text("Contact Info"); TextField("Email/Phone", text: nonOptionalClientInfo.contactInfo).multilineTextAlignment(.trailing).lineLimit(1) }
    }
}

/// A reusable form section for editing mission notes.
struct MissionNotesSection: View {
    @Binding var notes: String
    var body: some View {
        TextField("Enter mission notes here...", text: $notes, axis: .vertical).frame(minHeight: 100, alignment: .top)
    }
}

/// A reusable form section for fetching and displaying weather data.
struct WeatherSection: View {
    @Binding var weather: WeatherData
    let fetchAction: () async -> Void
    var body: some View {
        HStack {
            TextField("Airport ICAO (e.g., KLAX)", text: $weather.icao).autocapitalization(.allCharacters).disableAutocorrection(true).font(.system(.body, design: .monospaced))
            Button("Fetch") { Task { await fetchAction() } }.disabled(weather.icao.count != 4)
        }
        InfoRow(label: "Raw METAR", value: weather.metar, multiline: true)
        InfoRow(label: "Decoded METAR", value: weather.decodedMetar, multiline: true)
    }
}
