import Foundation

/// Centralized location for all application constants to prevent typos and ease configuration.
enum Constants {
    static let remoteIDServiceUUID = "0000FFFA-0000-1000-8000-00805F9B34FB"
    
    enum UserDefaultsKeys {
        // Increment version to avoid conflicts if data structures change significantly.
        private static let version = "_v14"
        static let logbookStorage = "Part107Logbook_Logs" + version
        static let droneStorage = "Part107Logbook_Drones" + version
        static let checklistStorage = "Part107Logbook_Checklists" + version
        static let userSettings = "Part107Logbook_UserSettings" + version
        static let setupCompleted = "Part107Logbook_SetupCompleted" + version
    }
}
