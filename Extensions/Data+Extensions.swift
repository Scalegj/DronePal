import Foundation

extension Data {
    /// Reads a value of a specified type from a specific byte offset without creating a subdata object.
    /// This is more efficient as it avoids intermediate memory allocations.
    /// - Parameters:
    ///   - type: The type of data to read (e.g., `UInt16.self`).
    ///   - offset: The byte offset to start reading from.
    /// - Returns: The decoded value.
    func read<T>(as type: T.Type, at offset: Int) -> T {
        self.withUnsafeBytes { $0.load(fromByteOffset: offset, as: T.self) }
    }

    /// Converts a 16-bit half-precision float (represented as a UInt16) to a standard 32-bit Float.
    /// Uses the native `Float16` type on iOS 14+ for optimal performance and accuracy.
    /// - Parameter offset: The byte offset where the 16-bit float begins.
    /// - Returns: A standard `Float`.
    func toFloat16(at offset: Int) -> Float {
        let uint16 = read(as: UInt16.self, at: offset)
        if #available(iOS 14.0, macOS 11.0, *) {
            return Float(Float16(bitPattern: uint16))
        } else {
            // Manual fallback for older OS versions. This logic correctly handles
            // normal numbers, subnormals, zero, infinity, and NaN.
            let sign = (uint16 & 0x8000) >> 15
            let exponent = (uint16 & 0x7C00) >> 10
            let fraction = uint16 & 0x03FF

            if exponent == 0 {
                if fraction == 0 { return 0.0 * (sign == 1 ? -1 : 1) } // Signed zero
                // Subnormal number
                var frac = Float(fraction) / 1024.0
                var exp = -14
                while frac < 1.0 {
                    frac *= 2.0
                    exp -= 1
                }
                return (sign == 1 ? -1 : 1) * frac * pow(2, Float(exp))
            } else if exponent == 0x1F {
                return fraction == 0 ? (sign == 1 ? -.infinity : .infinity) : .nan
            }
            // Normal number
            let S = Float(sign == 1 ? -1 : 1)
            let E = Float(Int(exponent) - 15)
            let F = 1.0 + Float(fraction) / 1024.0
            return S * F * pow(2, E)
        }
    }
}
