import SwiftUI

/// A fallback view for iOS 16 that mimics the behavior of `ContentUnavailableView`.
struct LegacyContentUnavailableView<Label: View, Description: View>: View {
    var label: Label
    var description: Description

    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description) {
        self.label = label()
        self.description = description()
    }

    var body: some View {
        VStack(spacing: 20) {
            label
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            description
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
