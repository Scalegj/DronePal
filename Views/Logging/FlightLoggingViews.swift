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


/// The main container view for the flight logging flow, managing the multi-step process.
struct FlightLoggingContainerView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    private enum LoggingStep: String {
        case preFlight = "Pre-Flight"
        case inFlight = "In-Flight"
        case review = "Review & Save"
    }
    
    @State private var currentStep: LoggingStep = .preFlight
    
    var body: some View {
        NavigationStack {
            Group {
                switch currentStep {
                case .preFlight:
                    PreFlightSetupView(
                        onProceed: { currentStep = .inFlight }
                    )
                case .inFlight:
                    InFlightLoggingView(
                        onProceed: {
                            if viewModel.isSegmentActive { viewModel.endCurrentSegment() }
                            currentStep = .review
                        }
                    )
                case .review:
                    PostFlightReviewView()
                }
            }
            .navigationTitle(currentStep.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive, action: viewModel.discardActiveLog)
                }
            }
        }
    }
}

/// The first step in logging a flight: setting up details and checklists.
private struct PreFlightSetupView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let onProceed: () -> Void
    
    @State private var isUsingPMTC = false
    @State private var isUsingVO = false
    @State private var selectedChecklistID: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                FlightDetailsSection(log: $viewModel.activeLog)
                AdditionalCrewSection(log: $viewModel.activeLog, isUsingPMTC: $isUsingPMTC, isUsingVO: $isUsingVO)
                checklistSection
                WeatherSection(weather: $viewModel.activeLog.weather) {
                    await viewModel.fetchWeather()
                }
                MissionNotesSection(notes: $viewModel.activeLog.missionNotes)
            }
            
            Button(action: onProceed) {
                Label("Start Flight", systemImage: "airplane.departure")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.thinMaterial)
        }
        .onAppear(perform: syncStateWithViewModel)
    }
    
    private var checklistSection: some View {
        Section("Pre-flight Checklist") {
            if viewModel.checklists.isEmpty {
                Text("No checklists available.").foregroundStyle(.secondary)
            } else {
                Picker("Select Checklist", selection: $selectedChecklistID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(viewModel.checklists) { Text($0.name).tag($0.id as UUID?) }
                }
                .onChange(of: selectedChecklistID) {
                    updateCompletedChecklist(for: selectedChecklistID)
                }
                
                ForEach($viewModel.activeLog.completedChecklist) { $item in
                    checklistRow(for: $item)
                }
            }
        }
    }
    
    private func checklistRow(for item: Binding<CompletedChecklistItem>) -> some View {
        Button(action: {
            item.wrappedValue.isChecked.toggle()
            item.wrappedValue.completionDate = item.wrappedValue.isChecked ? Date() : nil
        }) {
            HStack {
                Image(systemName: item.wrappedValue.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.wrappedValue.isChecked ? .green : .secondary)
                Text(item.wrappedValue.text)
                    .strikethrough(item.wrappedValue.isChecked)
                    .foregroundStyle(item.wrappedValue.isChecked ? .secondary : .primary)
                Spacer()
                if let completionDate = item.wrappedValue.completionDate {
                    Text(completionDate, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func updateCompletedChecklist(for checklistId: UUID?) {
        guard let id = checklistId, let checklist = viewModel.checklists.first(where: { $0.id == id }) else {
            viewModel.activeLog.completedChecklist = []
            return
        }
        viewModel.activeLog.completedChecklist = checklist.items.map {
            CompletedChecklistItem(id: $0.id, text: $0.text, isChecked: false, completionDate: nil)
        }
    }

    private func syncStateWithViewModel() {
        let log = viewModel.activeLog
        isUsingPMTC = !(log.pmtcBy?.isEmpty ?? true)
        isUsingVO = !(log.visualObserver?.isEmpty ?? true)
        
        if let firstItem = log.completedChecklist.first,
           let checklist = viewModel.checklists.first(where: { $0.items.contains(where: { $0.id == firstItem.id }) }) {
            selectedChecklistID = checklist.id
        }
    }
}

/// The second step: live logging of flight segments and telemetry.
private struct InFlightLoggingView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let onProceed: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                liveLoggingSection
                inFlightControlsSection
                flightSegmentsSection
                remoteIDSection
            }
            
            Button(action: onProceed) {
                Label("End Flight & Review", systemImage: "flag.checkered.2.crossed")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).padding().background(.thinMaterial)
        }
    }
    
    private var liveLoggingSection: some View {
        Section("Live Flight Logging") {
            HStack {
                Text("Total Duration:")
                Spacer()
                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    Text(Formatters.durationPositional.string(from: viewModel.activeLog.flightDuration) ?? "00:00:00")
                        .font(.system(.title2, design: .monospaced).bold())
                        .foregroundStyle(viewModel.isSegmentActive ? .green : Color.accentColor)
                }
            }
        }
    }
    
    private var inFlightControlsSection: some View {
        Section("In-Flight Controls") {
            HStack {
                Button(action: viewModel.startNewSegment) { Text("Take Off").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSegmentActive)

                Button(action: viewModel.endCurrentSegment) { Text("Land").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isSegmentActive)
            }
        }
    }
    
    private var flightSegmentsSection: some View {
        Section("Flight Segments") {
            if viewModel.activeLog.segments.isEmpty {
                Text("Press 'Take Off' to start the first segment.").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.activeLog.segments.reversed()) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Takeoff:").fontWeight(.medium)
                            Text(segment.startTime, style: .time)
                            Spacer()
                            if let endTime = segment.endTime {
                                Text("Landing:").fontWeight(.medium)
                                Text(endTime, style: .time)
                            } else {
                                Text("In Progress").bold().foregroundStyle(.green)
                            }
                        }
                        Text("Duration: \(Formatters.durationPositional.string(from: segment.duration) ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    private var remoteIDSection: some View {
        Section("Detected Remote IDs") {
            if !viewModel.activeLog.loggedRemoteIDs.isEmpty {
                ForEach(viewModel.activeLog.loggedRemoteIDs) { rid in
                    NavigationLink(destination: LoggedIDDetailView(loggedID: rid)) {
                        VStack(alignment: .leading) {
                            Text(rid.displayName).font(.headline)
                            if let last = rid.telemetry.last {
                                Text("RSSI: \(last.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning for nearby drones...")
                }.foregroundStyle(.secondary)
            }
        }
    }
}

/// The final step: reviewing and saving the completed flight log.
private struct PostFlightReviewView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    @State private var isUsingPMTC = false
    @State private var isUsingVO = false
    
    var body: some View {
        Form {
            Section("Flight Summary") {
                InfoRow(label: "Aircraft", value: viewModel.droneForID(viewModel.activeLog.aircraftID)?.displayName ?? "")
                InfoRow(label: "Location", value: viewModel.activeLog.location)
                InfoRow(label: "Date", value: viewModel.activeLog.date.formatted(date: .long, time: .shortened))
                InfoRow(label: "Total Duration", value: Formatters.durationPositional.string(from: viewModel.activeLog.flightDuration) ?? "")
            }
            
            FlightDetailsSection(log: $viewModel.activeLog)
            AdditionalCrewSection(log: $viewModel.activeLog, isUsingPMTC: $isUsingPMTC, isUsingVO: $isUsingVO)
            MissionNotesSection(notes: $viewModel.activeLog.missionNotes)
            WeatherSection(weather: $viewModel.activeLog.weather) {
                await viewModel.fetchWeather()
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Flight", action: viewModel.saveAndStopLogging).font(.headline)
            }
        }
        .onAppear {
             let log = viewModel.activeLog
             isUsingPMTC = !(log.pmtcBy?.isEmpty ?? true)
             isUsingVO = !(log.visualObserver?.isEmpty ?? true)
        }
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
                        // <-- FIXED: Explicitly add the user annotation to show the blue dot
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
                // <-- FIXED: Replaced icon with a more common one to prevent crashes
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
            
            Form {
                Section("Operation Details") {
                    HStack {
                        // <-- MODIFIED: Changed AGL units to feet
                        Text("Maximum AGL (feet)")
                        TextField("e.g., 400", text: $maxAGLText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
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
            
            if !drawnPoints.isEmpty {
                let region = MKCoordinateRegion(coordinates: drawnPoints)
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
    init(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { self.init(); return }

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
