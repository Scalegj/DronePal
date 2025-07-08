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
                // MODIFIED: Ensure multi-line text is always left-aligned.
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
    }
}

/// A custom styled container for form-like sections used in the logging and stats views.
struct StyledSection<Content: View>: View {
    @ViewBuilder var content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding()
        // MODIFIED: Replaced .regularMaterial with an opaque background for better contrast.
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A helper view for the summary boxes used on several screens.
struct StatBox: View {
    let title: String
    let value: String
    let image: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Image(systemName: image)
                .font(.title)
                .foregroundStyle(color)
        }
        .padding()
        // FIX: Replaced .regularMaterial with an opaque color for better contrast.
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
