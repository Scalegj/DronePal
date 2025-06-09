import SwiftUI

/// The main container for the multi-step setup process.
struct SetupView: View {
    @EnvironmentObject var viewModel: AppViewModel
    
    @State private var currentStep = 0
    @State private var settings = UserSettings()
    @State private var drones: [Drone] = []
    @State private var hasDoneRecurrent = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentStep.animation()) {
                SetupStep1_PilotType(settings: $settings).tag(0)
                SetupStep2_Dates(settings: $settings, hasDoneRecurrent: $hasDoneRecurrent).tag(1)
                SetupStep3_Equipment(drones: $drones).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.spring(), value: currentStep)
                    }
                }
                .padding(.top)

                HStack {
                    if currentStep > 0 {
                        Button("Back") { currentStep -= 1 }
                            .buttonStyle(.bordered)
                    }
                    
                    Spacer()

                    if currentStep < 2 {
                        Button("Next") { currentStep += 1 }
                            .buttonStyle(.borderedProminent)
                            .disabled(currentStep == 0 && settings.pilotName.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button("Finish Setup") {
                            viewModel.finalizeSetup(settings: settings, drones: drones, hasDoneRecurrent: hasDoneRecurrent)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(drones.isEmpty)
                    }
                }
                .padding()
            }
            .background(.thinMaterial)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

/// Setup Step 1: Collect pilot name and type.
private struct SetupStep1_PilotType: View {
    @Binding var settings: UserSettings
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Welcome!")
                        .font(.largeTitle.bold())
                    
                    Text("Let's get your pilot profile set up. This info will be used to auto-fill your flight logs.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section("Pilot Information") {
                TextField("Your Name (Pilot in Command)", text: $settings.pilotName)
            }
            
            Section("Pilot Type") {
                Picker("Select your pilot type", selection: $settings.pilotType) {
                    ForEach(PilotType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

/// Setup Step 2: Collect certification dates.
private struct SetupStep2_Dates: View {
    @Binding var settings: UserSettings
    @Binding var hasDoneRecurrent: Bool

    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.accentColor)

                    Text("Certification Dates")
                        .font(.largeTitle.bold())
                    
                    Text("Please enter the relevant dates for your pilot certification.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            
            if settings.pilotType == .part107 {
                Section(
                    header: Text("Part 107 Information"),
                    footer: Text("Your Part 107 certificate itself doesn't expire, but you must complete recurrent training every 24 calendar months to remain current.")
                ) {
                    DatePicker("Initial Certificate Date", selection: $settings.part107InitialCertificateDate, in: ...Date(), displayedComponents: .date)
                    
                    Toggle("I have completed recurrent training", isOn: $hasDoneRecurrent.animation())
                    
                    if hasDoneRecurrent {
                        DatePicker("Last Recurrency Date", selection: $settings.part107LastRecurrencyDate, in: ...Date(), displayedComponents: .date)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            } else {
                Section(
                    header: Text("Recreational Flyer Information"),
                    footer: Text("The Recreational UAS Safety Test (TRUST) does not expire.")
                ) {
                    DatePicker("TRUST Completion Date", selection: $settings.recreationalTRUSTDate, in: ...Date(), displayedComponents: .date)
                }
            }
        }
    }
}

/// Setup Step 3: Add initial equipment.
private struct SetupStep3_Equipment: View {
    @Binding var drones: [Drone]
    @State private var showAddSheet = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .center, spacing: 16) {
                    Image(systemName: "airplane.circle")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Your Equipment")
                        .font(.largeTitle.bold())
                    
                    Text("Add at least one drone to complete setup. This will be used to track flight time for each aircraft.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            
            Section(header: Text("My Drones")) {
                if drones.isEmpty {
                    ContentUnavailableView(
                        "No Drones Added",
                        systemImage: "shippingbox.circle",
                        description: Text("Tap 'Add New Drone' to get started.")
                    )
                    .padding(.vertical)
                } else {
                    ForEach(drones) { drone in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(drone.displayName)
                                .font(.headline)
                            Text("FAA Reg: \(drone.faaRegistration)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete { offsets in
                        drones.remove(atOffsets: offsets)
                    }
                }
            }
            
            Section {
                Button(action: { showAddSheet = true }) {
                    Label("Add New Drone", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditDroneView(droneToEdit: nil) { newDrone in
                drones.append(newDrone)
            }
        }
    }
}
