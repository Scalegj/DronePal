import SwiftUI

// FIX: Create a custom environment key to explicitly control navigation behavior.
// This is more reliable than checking device type or size class.

/// Defines the two types of navigation styles our app uses.
enum AppNavigationStyle {
    case stack
    case split
}

/// The definition of the environment key itself.
private struct NavigationStyleKey: EnvironmentKey {
    static let defaultValue: AppNavigationStyle = .stack
}

extension EnvironmentValues {
    /// The property that we will read from our views.
    var appNavigationStyle: AppNavigationStyle {
        get { self[NavigationStyleKey.self] }
        set { self[NavigationStyleKey.self] = newValue }
    }
}
