// Copyright (c) 2025-2026 ImmersiveMap contributors.
// SPDX-License-Identifier: MIT

import Foundation

/// What went wrong while the model archive was baked, in words for the
/// pipeline's log: a model that cannot be read, a texture that cannot be
/// encoded, an archive that cannot be written.
struct BakeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

extension Data {
    /// A little-endian `UInt32` at `offset` from the start of the data.
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(self[startIndex + offset + index]) << (8 * UInt32(index))
        }
        return value
    }
}
