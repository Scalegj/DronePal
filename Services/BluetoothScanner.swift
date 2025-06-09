import Foundation
import CoreBluetooth
import os

/// Manages Bluetooth scanning for Remote ID devices using CoreBluetooth.
class BluetoothScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    /// A dictionary for efficient O(1) lookup of discovered devices by their UUID.
    @Published private(set) var discoveredDevices: [UUID: RemoteIDDevice] = [:]
    /// A sorted array derived from the dictionary, optimized for direct use in SwiftUI lists.
    @Published private(set) var deviceListForUI: [RemoteIDDevice] = []
    @Published private(set) var isScanning = false
    
    private var centralManager: CBCentralManager!
    private var cleanupTimer: Timer?

    override init() {
        super.init()
        // Use a background queue for Bluetooth events to keep the main thread responsive.
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global(qos: .background))
        startCleanupTimer()
    }

    /// Starts scanning for peripherals advertising the Remote ID service.
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            AppLogger.bluetooth.warning("Cannot start scan: Bluetooth is not powered on.")
            return
        }
        DispatchQueue.main.async { self.isScanning = true }
        
        let serviceUUID = CBUUID(string: Constants.remoteIDServiceUUID)
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        AppLogger.bluetooth.info("Started scanning for Remote ID devices.")
    }

    /// Stops the active Bluetooth scan.
    func stopScanning() {
        centralManager.stopScan()
        DispatchQueue.main.async { self.isScanning = false }
        AppLogger.bluetooth.info("Stopped scanning.")
    }
    
    // MARK: - CBCentralManagerDelegate Conformance
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            AppLogger.bluetooth.log("Bluetooth is powered on.")
            startScanning()
        } else {
            AppLogger.bluetooth.warning("Bluetooth is not available. State: \(central.state.rawValue)")
            DispatchQueue.main.async { self.isScanning = false }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceID = peripheral.identifier
        
        // Updates must be dispatched to the main thread to safely modify published properties.
        DispatchQueue.main.async {
            if let existingDevice = self.discoveredDevices[deviceID] {
                existingDevice.update(with: advertisementData, rssi: RSSI)
            } else {
                AppLogger.bluetooth.log("Discovered new device: \(peripheral.identifier.uuidString)")
                let newDevice = RemoteIDDevice(from: peripheral, rssi: RSSI)
                self.discoveredDevices[deviceID] = newDevice
            }
            // Update the sorted array for the UI after any change.
            self.updateDeviceListForUI()
        }
    }
    
    // MARK: - Private Helpers
    
    /// Sets up a timer to periodically remove devices that haven't been seen recently.
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.cleanupStaleDevices()
        }
    }
    
    private func cleanupStaleDevices() {
        DispatchQueue.main.async {
            let now = Date()
            let staleDeviceIDs = self.discoveredDevices.filter { now.timeIntervalSince($0.value.lastUpdated) > 60.0 }.map { $0.key }
            
            if !staleDeviceIDs.isEmpty {
                AppLogger.bluetooth.log("Removing \(staleDeviceIDs.count) stale devices.")
                for id in staleDeviceIDs {
                    self.discoveredDevices.removeValue(forKey: id)
                }
                self.updateDeviceListForUI()
            }
        }
    }
    
    /// Updates the `deviceListForUI` array by sorting the values from the main dictionary.
    private func updateDeviceListForUI() {
        self.deviceListForUI = self.discoveredDevices.values.sorted { $0.name < $1.name }
    }
}

