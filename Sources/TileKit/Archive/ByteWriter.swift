// Copyright (c) 2025-2026 ImmersiveMap contributors.
// SPDX-License-Identifier: MIT

import Foundation

/// Appends little-endian values to a growing byte buffer.
struct ByteWriter {
    private(set) var data = Data()

    var count: Int {
        data.count
    }

    mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    mutating func append(_ value: Float) {
        append(value.bitPattern)
    }

    mutating func append(_ value: Double) {
        append(value.bitPattern)
    }

    mutating func append(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func append(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    /// Zero bytes up to the next multiple of `alignment`.
    mutating func pad(toMultipleOf alignment: Int) {
        let remainder = data.count % alignment
        if remainder != 0 {
            data.append(Data(count: alignment - remainder))
        }
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

struct BakeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
