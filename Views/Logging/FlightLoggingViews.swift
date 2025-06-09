import SwiftUI

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
                // <-- FIXED: Updated to modern onChange syntax.
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
