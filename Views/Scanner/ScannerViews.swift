import SwiftUI

/// A view dedicated to scanning for and displaying nearby Remote ID devices.
struct RemoteIDScannerView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedDevice: RemoteIDDevice?

    var body: some View {
        Group {
            if viewModel.bluetoothScanner.isScanning && viewModel.bluetoothScanner.deviceListForUI.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                    Text("Scanning for Drones...").foregroundStyle(.secondary)
                }
            } else if viewModel.bluetoothScanner.deviceListForUI.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView {
                        Label("No Drones Found", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("No broadcasting Remote ID signals detected. Ensure your drone is powered on and broadcasting.")
                    }
                } else {
                    LegacyContentUnavailableView {
                        Label("No Drones Found", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("No broadcasting Remote ID signals detected. Ensure your drone is powered on and broadcasting.")
                    }
                }
            } else {
                List(viewModel.bluetoothScanner.deviceListForUI) { device in
                    Button(action: { selectedDevice = device }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right.circle").font(.title).foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(device.name).font(.headline)
                                Text(device.basicID?.uasID ?? "ID: N/A").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .font(.subheadline)
                                .foregroundStyle(rssiColor(device.rssi.intValue))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .navigationTitle("Remote ID Scanner")
        .onAppear {
            if !viewModel.isLoggingFlight { viewModel.bluetoothScanner.startScanning() }
        }
        .onDisappear {
            if !viewModel.isLoggingFlight { viewModel.bluetoothScanner.stopScanning() }
        }
        .sheet(item: $selectedDevice) { device in
            RemoteIDDetailView(device: device)
        }
    }
}

/// A sheet view showing the live telemetry details for a selected device from the scanner.
struct RemoteIDDetailView: View {
    @ObservedObject var device: RemoteIDDevice
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Identification") {
                    InfoRow(label: "Broadcast Name", value: device.name)
                    InfoRow(label: "ID Type", value: device.basicID?.idType ?? "N/A")
                    InfoRow(label: "Registration Number", value: device.basicID?.uasID ?? "N/A")
                }
                Section("Live Telemetry") {
                    InfoRow(label: "Signal Strength (RSSI)", value: "\(device.rssi) dBm")
                    if let location = device.location {
                        InfoRow(label: "Coordinates", value: String(format: "%.4f, %.4f", location.latitude, location.longitude))
                        InfoRow(label: "Altitude (AGL)", value: String(format: "%.1f m", location.height ?? 0.0))
                        InfoRow(label: "Ground Speed", value: String(format: "%.1f m/s", location.speedHorizontal))
                        InfoRow(label: "Heading", value: "\(Int(location.direction))°")
                    } else {
                        InfoRow(label: "Coordinates", value: "N/A")
                    }
                }
            }
            .navigationTitle("Remote ID Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
