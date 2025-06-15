import Foundation

class PersistenceService {
    private var fileURL: URL?
    private var isSetup = false // Flag to ensure setup runs only once

    init() {
        // Initialization is now synchronous and does nothing.
        // The setup logic is deferred to the async setup() function.
    }

    /// Asynchronously determines the correct file URL (iCloud or local) for data storage.
    /// This must be called and awaited before any load/save operations.
    func setup() async {
        // Ensure this setup logic only ever runs once.
        guard !isSetup else { return }

        // 1. Try to get the URL for the app's iCloud container.
        guard let ubiquityContainerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            AppLogger.persistence.warning("iCloud container not available or not configured. Falling back to local storage.")
            await setupLocalFileURL()
            self.isSetup = true
            return
        }
        
        // 2. Standard practice is to store documents in a "Documents" subdirectory.
        let iCloudDocumentsURL = ubiquityContainerURL.appendingPathComponent("Documents")
        
        // 3. Create the "Documents" directory if it doesn't already exist.
        if !FileManager.default.fileExists(atPath: iCloudDocumentsURL.path) {
            do {
                try FileManager.default.createDirectory(at: iCloudDocumentsURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                AppLogger.persistence.error("Failed to create iCloud Documents directory: \(error). Falling back to local storage.")
                await setupLocalFileURL()
                self.isSetup = true
                return
            }
        }
        
        // 4. Set the final fileURL to our data file inside the iCloud Documents directory.
        let icloudFileURL = iCloudDocumentsURL.appendingPathComponent("DronePalData.json")
        await MainActor.run {
            self.fileURL = icloudFileURL
            AppLogger.persistence.info("Persistence successfully configured to use iCloud.")
        }
        self.isSetup = true
    }
    
    /// Fallback method to set up the local file URL if iCloud is unavailable.
    @MainActor
    private func setupLocalFileURL() {
        do {
            let localDocumentsDirectory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            self.fileURL = localDocumentsDirectory.appendingPathComponent("DronePalData.json")
        } catch {
            fatalError("Could not find local Documents directory: \(error)")
        }
    }

    /// Loads all app data from the JSON file.
    func load() -> AppData {
        guard let url = self.fileURL else {
            // This message will now only appear if setup() is not awaited properly.
            AppLogger.persistence.error("File URL not available during load. The setup() method must be awaited before loading.")
            return AppData.empty
        }

        do {
            let data = try Data(contentsOf: url)
            let appData = try JSONDecoder().decode(AppData.self, from: data)
            AppLogger.persistence.info("Successfully loaded data from \(url.path)")
            return appData
        } catch {
            AppLogger.persistence.warning("Could not load data, returning empty state. Error: \(error)")
            return AppData.empty
        }
    }

    /// Saves all app data to the JSON file on a background thread.
    func save(appData: AppData) {
        guard let url = self.fileURL else {
            AppLogger.persistence.error("File URL not available. Cannot save data.")
            return
        }

        Task(priority: .background) {
            do {
                let data = try JSONEncoder().encode(appData)
                try data.write(to: url, options: .atomic)
                AppLogger.persistence.info("Successfully saved data to \(url.path)")
            } catch {
                AppLogger.persistence.error("Failed to save data: \(error.localizedDescription)")
            }
        }
    }
}
