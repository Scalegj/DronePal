import SwiftUI

extension Binding {
    /// Creates a non-optional `Binding` from an optional one, providing a default value.
    /// This is useful for SwiftUI controls that require non-optional bindings (e.g., TextField)
    /// when the underlying model property is optional.
    init(_ source: Binding<Value?>, default defaultValue: Value) {
        self.init(
            get: { source.wrappedValue ?? defaultValue },
            set: { newValue in source.wrappedValue = newValue }
        )
    }
}
