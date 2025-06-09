import Foundation
import os

/// A centralized logger for consistent, subsystem-based logging. This is the standard
/// for production apps on Apple platforms, providing better performance and filtering
/// capabilities than `print()`.
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    
    /// Logger for Bluetooth-related events (scanning, parsing, connecting).
    static let bluetooth = Logger(subsystem: subsystem, category: "Bluetooth")
    
    /// Logger for data persistence events (saving/loading from UserDefaults).
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    
    /// Logger for network requests, like fetching METAR data.
    static let network = Logger(subsystem: subsystem, category: "Network")
    
    /// A general-purpose logger for other events.
    static let general = Logger(subsystem: subsystem, category: "General")
}
