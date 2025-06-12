import Foundation

class PersistenceService {
    private var fileURL: URL

    init() {
        do {
            let documentsDirectory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            self.fileURL = documentsDirectory.appendingPathComponent("DronePalData.json")
        } catch {
            // This is a critical error. If we can't get the documents directory, the app can't function.
            fatalError("Could not find Documents directory: \(error)")
        }
    }

    /// Loads all app data from the JSON file.
    func load() -> AppData {
        do {
            // Add `self.` to explicitly reference the instance's fileURL property.
            let data = try Data(contentsOf: self.fileURL)
            let appData = try JSONDecoder().decode(AppData.self, from: data)
            AppLogger.persistence.info("Successfully loaded data from \(self.fileURL.lastPathComponent)")
            return appData
        } catch {
            AppLogger.persistence.warning("Could not load data, returning empty state. Error: \(error)")
            // If the file doesn't exist or is corrupt, return a default empty state.
            return AppData.empty
        }
    }

    /// Saves all app data to the JSON file on a background thread to avoid UI hangs.
    func save(appData: AppData) {
        // **FIX**: Run the save operation on a background thread to avoid blocking the UI.
        Task(priority: .background) {
            do {
                let data = try JSONEncoder().encode(appData)
                try data.write(to: self.fileURL, options: .atomic)
                AppLogger.persistence.info("Successfully saved data to \(self.fileURL.lastPathComponent)")
            } catch {
                AppLogger.persistence.error("Failed to save data: \(error.localizedDescription)")
            }
        }
    }
}
