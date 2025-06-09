import SwiftUI

/// A reusable view for displaying a labeled piece of information.
struct InfoRow: View {
    var label: String
    var value: String
    var multiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "N/A" : value)
                .font(multiline ? .footnote : .body)
                .lineLimit(multiline ? nil : 1)
        }
        .padding(.vertical, 4)
    }
}

/// A centralized place for date and time formatters to avoid re-creating them, which is inefficient.
enum Formatters {
    static let durationPositional: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    static let durationAbbreviated: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    static let telemetryTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

/// Determines the color for an RSSI value.
func rssiColor(_ rssi: Int) -> Color {
    switch rssi {
    case -60...0: return .green
    case -80 ..< -60: return .orange
    default: return .red
    }
}

