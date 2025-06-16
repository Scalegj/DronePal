import SwiftUI
import MapKit
import CoreLocation

// MODIFIED: Removed the LocationManager, FlightAreaMapView, and MKCoordinateRegion extension, as they have been moved to ReusableFormSections.swift

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
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                switch currentStep {
                case .preFlight:
                    PreFlightSetupView(
                        onProceed: { withAnimation(.easeInOut) { currentStep = .inFlight } }
                    )
                case .inFlight:
                    InFlightLoggingView(
                        onProceed: {
                            if viewModel.isSegmentActive { viewModel.endCurrentSegment() }
                            withAnimation(.easeInOut) { currentStep = .review }
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


/// A helper for prominent, styled action buttons
private struct ActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .padding()
                .background(color.gradient)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: color.opacity(0.4), radius: 10, y: 5)
        }
        .padding([.horizontal, .bottom])
    }
}


/// The first step in logging a flight: setting up details and checklists.
private struct PreFlightSetupView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let onProceed: () -> Void
    
    @State private var selectedChecklistID: UUID?
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Flight Details").font(.headline).foregroundStyle(.secondary)
                    StyledSection { FlightDetailsSection(log: $viewModel.activeLog) }
                    
                    Text("Client & Project").font(.headline).foregroundStyle(.secondary)
                    StyledSection { ClientInfoSection(clientInfo: $viewModel.activeLog.clientInfo) }
                    
                    Text("Additional Crew").font(.headline).foregroundStyle(.secondary)
                    StyledSection { AdditionalCrewSection(crew: $viewModel.activeLog.crew) }
                    
                    Text("Pre-flight Checklist").font(.headline).foregroundStyle(.secondary)
                    StyledSection { checklistSection }

                    Text("Weather").font(.headline).foregroundStyle(.secondary)
                    StyledSection { WeatherSection(weather: $viewModel.activeLog.weather) { await viewModel.fetchWeather() } }

                    Text("Mission Notes").font(.headline).foregroundStyle(.secondary)
                    StyledSection { MissionNotesSection(notes: $viewModel.activeLog.missionNotes) }
                }
                .padding()
            }
            
            ActionButton(title: "Start Flight", systemImage: "airplane.departure", color: .accentColor, action: onProceed)
        }
        .onAppear(perform: syncStateWithViewModel)
    }
    
    private var checklistSection: some View {
        Group {
            if viewModel.checklists.isEmpty {
                Text("No checklists available.").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Checklist")
                    Spacer()
                    Menu {
                        Button("None") { selectedChecklistID = nil }
                        ForEach(viewModel.checklists) { checklist in
                            Button(checklist.name) { selectedChecklistID = checklist.id }
                        }
                    } label: {
                        Text(viewModel.checklists.first(where: { $0.id == selectedChecklistID })?.name ?? "Select Checklist")
                            .foregroundColor(.secondary)
                    }
                }
                // --- START CORRECTION ---
                // Using the explicit 'perform' label to avoid ambiguity and ensure
                // the iOS 14+ version of onChange is used.
                .onChange(of: selectedChecklistID, perform: { newValue in
                    updateCompletedChecklist(for: newValue)
                })
                // --- END CORRECTION ---
                
                if selectedChecklistID != nil && !viewModel.activeLog.completedChecklist.isEmpty {
                    Divider()
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
        if let firstItem = viewModel.activeLog.completedChecklist.first,
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
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    liveLoggingCard
                    
                    Text("In-Flight Controls").font(.headline).foregroundStyle(.secondary)
                    StyledSection { inFlightControlsSection }
                    
                    Text("Flight Segments").font(.headline).foregroundStyle(.secondary)
                    StyledSection { flightSegmentsSection }
                    
                    Text("Detected Remote IDs").font(.headline).foregroundStyle(.secondary)
                    StyledSection { remoteIDSection }
                }
                .padding()
            }
            ActionButton(title: "End Flight & Review", systemImage: "flag.checkered.2.crossed", color: .blue, action: onProceed)
        }
    }
    
    private var liveLoggingCard: some View {
        VStack(spacing: 16) {
            Text("LIVE FLIGHT LOGGING")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))
            
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Text(Formatters.durationPositional.string(from: viewModel.activeLog.flightDuration) ?? "00:00:00")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            
            Text(viewModel.isSegmentActive ? "Segment In Progress" : "Landed")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background((viewModel.isSegmentActive ? Color.green : Color.orange).opacity(0.5))
                .clipShape(Capsule())
                .animation(.easeInOut, value: viewModel.isSegmentActive)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .shadow(color: .accentColor.opacity(0.4), radius: 10, y: 5)
    }
    
    private var inFlightControlsSection: some View {
        HStack(spacing: 16) {
            Button(action: viewModel.startNewSegment) {
                Label("Take Off", systemImage: "arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(viewModel.isSegmentActive)

            Button(action: viewModel.endCurrentSegment) {
                Label("Land", systemImage: "arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!viewModel.isSegmentActive)
        }
    }
    
    private var flightSegmentsSection: some View {
        Group {
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
                    if segment.id != viewModel.activeLog.segments.reversed().last?.id {
                        Divider()
                    }
                }
            }
        }
    }
    
    private var remoteIDSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.activeLog.loggedRemoteIDs.isEmpty {
                ForEach(viewModel.activeLog.loggedRemoteIDs) { rid in
                    NavigationLink(destination: LoggedIDDetailView(loggedID: rid)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rid.displayName).font(.headline)
                                if let last = rid.telemetry.last {
                                    Text("RSSI: \(last.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.primary)
                    
                    if rid.id != viewModel.activeLog.loggedRemoteIDs.last?.id {
                        Divider()
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning for nearby drones...")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The final step: reviewing and saving the completed flight log.
private struct PostFlightReviewView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Flight Summary").font(.headline).foregroundStyle(.secondary)
                    StyledSection {
                        InfoRow(label: "Aircraft", value: viewModel.droneForID(viewModel.activeLog.aircraftID)?.displayName ?? "")
                        Divider()
                        InfoRow(label: "Location", value: viewModel.activeLog.location)
                        Divider()
                        InfoRow(label: "Date", value: viewModel.activeLog.date.formatted(date: .long, time: .shortened))
                        Divider()
                        InfoRow(label: "Total Duration", value: Formatters.durationPositional.string(from: viewModel.activeLog.flightDuration) ?? "")
                    }
                    
                    Text("Flight Details").font(.headline).foregroundStyle(.secondary)
                    StyledSection { FlightDetailsSection(log: $viewModel.activeLog) }

                    Text("Client & Project").font(.headline).foregroundStyle(.secondary)
                    StyledSection { ClientInfoSection(clientInfo: $viewModel.activeLog.clientInfo) }
                    
                    Text("Additional Crew").font(.headline).foregroundStyle(.secondary)
                    StyledSection { AdditionalCrewSection(crew: $viewModel.activeLog.crew) }
                    
                    Text("Mission Notes").font(.headline).foregroundStyle(.secondary)
                    StyledSection { MissionNotesSection(notes: $viewModel.activeLog.missionNotes) }
                    
                    Text("Weather").font(.headline).foregroundStyle(.secondary)
                    StyledSection { WeatherSection(weather: $viewModel.activeLog.weather) { await viewModel.fetchWeather() } }
                }
                .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Flight", action: viewModel.saveAndStopLogging).bold()
            }
        }
    }
}
