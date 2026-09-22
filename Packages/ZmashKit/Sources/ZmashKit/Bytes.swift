import Foundation

public enum ParseError: Error, Equatable, Sendable {
    case truncated(needed: Int, available: Int)
    case malformed(String)
}

public extension Sequence where Element == UInt8 {
    /// `"0a ff 12"` style hex dump.
    var hex: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

/// Little-endian cursor over a byte buffer, as used by the Bluetooth SIG GATT specs.
public struct ByteReader: Sendable {
    public let bytes: [UInt8]
    public private(set) var offset = 0

    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    public init(_ data: Data) { self.bytes = Array(data) }

    public var remaining: Int { bytes.count - offset }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard remaining >= n else { throw ParseError.truncated(needed: n, available: remaining) }
        defer { offset += n }
        return bytes[offset..<offset + n]
    }

    public mutating func uint8() throws -> UInt8 { try take(1).first! }

    public mutating func uint16() throws -> UInt16 {
        let b = try take(2)
        return UInt16(b[b.startIndex]) | UInt16(b[b.startIndex + 1]) << 8
    }

    public mutating func int16() throws -> Int16 { Int16(bitPattern: try uint16()) }

    public mutating func uint24() throws -> UInt32 {
        let b = try take(3)
        return UInt32(b[b.startIndex]) | UInt32(b[b.startIndex + 1]) << 8 | UInt32(b[b.startIndex + 2]) << 16
    }

    public mutating func uint32() throws -> UInt32 {
        let lo = UInt32(try uint16())
        let hi = UInt32(try uint16())
        return lo | hi << 16
    }

    public mutating func skip(_ n: Int) throws { _ = try take(n) }
}

/// Little-endian byte builder.
public struct ByteWriter: Sendable {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func uint8(_ v: UInt8) { bytes.append(v) }
    public mutating func uint16(_ v: UInt16) { bytes += [UInt8(v & 0xff), UInt8(v >> 8)] }
    public mutating func int16(_ v: Int16) { uint16(UInt16(bitPattern: v)) }
}
