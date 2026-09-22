/// Minimal protobuf wire-format reader/writer. Zwift messages are small and use only
/// varints (incl. zigzag `sint32`) and nested messages, so a full protobuf runtime isn't needed.
public enum ProtoWire {
    public enum Value: Equatable, Sendable {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes([UInt8])
        case fixed32(UInt32)
    }

    public struct Field: Equatable, Sendable {
        public let number: Int
        public let value: Value

        public var uint: UInt64? {
            if case .varint(let v) = value { return v }
            return nil
        }

        /// Decodes a zigzag-encoded `sint32`/`sint64`.
        public var sint: Int64? { uint.map(ProtoWire.unzigzag) }

        public var bytes: [UInt8]? {
            if case .bytes(let b) = value { return b }
            return nil
        }
    }

    // MARK: Decoding

    public static func readVarint(_ bytes: [UInt8], at offset: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard offset < bytes.count else { throw ParseError.truncated(needed: 1, available: 0) }
            let byte = bytes[offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { throw ParseError.malformed("varint too long") }
        }
    }

    public static func fields(_ bytes: [UInt8]) throws -> [Field] {
        var out: [Field] = []
        var i = 0
        while i < bytes.count {
            let key = try readVarint(bytes, at: &i)
            let number = Int(key >> 3)
            switch key & 0x7 {
            case 0:
                out.append(Field(number: number, value: .varint(try readVarint(bytes, at: &i))))
            case 1:
                guard i + 8 <= bytes.count else { throw ParseError.truncated(needed: 8, available: bytes.count - i) }
                var v: UInt64 = 0
                for k in 0..<8 { v |= UInt64(bytes[i + k]) << (8 * UInt64(k)) }
                i += 8
                out.append(Field(number: number, value: .fixed64(v)))
            case 2:
                let len = Int(try readVarint(bytes, at: &i))
                guard i + len <= bytes.count else { throw ParseError.truncated(needed: len, available: bytes.count - i) }
                out.append(Field(number: number, value: .bytes(Array(bytes[i..<i + len]))))
                i += len
            case 5:
                guard i + 4 <= bytes.count else { throw ParseError.truncated(needed: 4, available: bytes.count - i) }
                var v: UInt32 = 0
                for k in 0..<4 { v |= UInt32(bytes[i + k]) << (8 * UInt32(k)) }
                i += 4
                out.append(Field(number: number, value: .fixed32(v)))
            default:
                throw ParseError.malformed("unsupported wire type \(key & 0x7)")
            }
        }
        return out
    }

    public static func zigzag(_ v: Int64) -> UInt64 { UInt64(bitPattern: (v << 1) ^ (v >> 63)) }
    public static func unzigzag(_ v: UInt64) -> Int64 { Int64(bitPattern: v >> 1) ^ -Int64(bitPattern: v & 1) }

    // MARK: Encoding

    public static func varint(_ value: UInt64) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7f)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    public struct Writer: Sendable {
        public private(set) var bytes: [UInt8] = []
        public init() {}

        public mutating func uint(_ field: Int, _ value: UInt64) {
            bytes += ProtoWire.varint(UInt64(field) << 3 | 0)
            bytes += ProtoWire.varint(value)
        }

        public mutating func sint(_ field: Int, _ value: Int64) {
            uint(field, ProtoWire.zigzag(value))
        }

        public mutating func message(_ field: Int, _ message: Writer) {
            bytes += ProtoWire.varint(UInt64(field) << 3 | 2)
            bytes += ProtoWire.varint(UInt64(message.bytes.count))
            bytes += message.bytes
        }
    }
}
