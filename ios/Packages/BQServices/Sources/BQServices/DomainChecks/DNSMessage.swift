import Foundation

enum DNSError: Error, Equatable {
    case invalidName
    case truncated
    case badPointer
    case nameTooLong
    case implausibleCounts
}

/// A DNS message (RFC 1035) with EDNS(0) (RFC 6891) — just enough for one DoH query and the
/// interpretation of its answer. Parsing is bounded: counts are checked against the message size,
/// names are limited to 255 octets and compression pointers must point backwards (no loops).
struct DNSMessage: Equatable {
    struct Question: Equatable {
        var name: String
        var type: UInt16
        var qclass: UInt16
    }

    struct Record: Equatable {
        var name: String
        var type: UInt16
        var rclass: UInt16
        var ttl: UInt32
        var data: [UInt8]
    }

    struct ExtendedError: Equatable {
        var infoCode: UInt16
        var text: String
    }

    static let typeA: UInt16 = 1
    static let typeSOA: UInt16 = 6
    static let typeOPT: UInt16 = 41
    static let classIN: UInt16 = 1
    static let rcodeNoError = 0
    static let rcodeNXDomain = 3
    static let optionEDE: UInt16 = 15
    static let optionPadding: UInt16 = 12

    var id: UInt16
    var flags: UInt16
    var questions: [Question]
    var answers: [Record]
    var authorities: [Record]
    var additionals: [Record]

    var isResponse: Bool { flags & 0x8000 != 0 }
    var opcode: Int { Int(flags >> 11 & 0x0F) }

    /// The full response code: the header's 4 bits plus the EDNS extended bits.
    var rcode: Int {
        let low = Int(flags & 0x000F)
        guard let opt = additionals.first(where: { $0.type == DNSMessage.typeOPT }) else { return low }
        return Int(opt.ttl >> 24) << 4 | low
    }

    /// Extended DNS Errors (RFC 8914) from the OPT record.
    var extendedErrors: [ExtendedError] {
        guard let opt = additionals.first(where: { $0.type == DNSMessage.typeOPT }) else { return [] }
        var errors: [ExtendedError] = []
        var i = 0
        let d = opt.data
        while i + 4 <= d.count {
            let code = UInt16(d[i]) << 8 | UInt16(d[i + 1])
            let length = Int(UInt16(d[i + 2]) << 8 | UInt16(d[i + 3]))
            guard i + 4 + length <= d.count else { break }
            if code == DNSMessage.optionEDE, length >= 2 {
                let info = UInt16(d[i + 4]) << 8 | UInt16(d[i + 5])
                let text = String(decoding: d[(i + 6)..<(i + 4 + length)], as: UTF8.self)
                errors.append(ExtendedError(infoCode: info, text: text))
            }
            i += 4 + length
        }
        return errors
    }

    // MARK: - Encoding

    /// A recursive query with an EDNS(0) OPT record (no client subnet) padded to a multiple of
    /// 128 octets (RFC 8467), so the name's length does not show in the encrypted size.
    static func query(name: String, type: UInt16, id: UInt16 = 0) throws(DNSError) -> [UInt8] {
        var m: [UInt8] = []
        m += be16(id) + be16(0x0100) + be16(1) + be16(0) + be16(0) + be16(1) // RD; QD=1, AR=1
        m += try encodeName(name)
        m += be16(type) + be16(classIN)
        // OPT: root name, type, UDP payload size, extended RCODE/version/flags = 0, RDATA.
        let fixed = m.count + 1 + 2 + 2 + 4 + 2 + 4 // + padding option header
        let padding = (128 - fixed % 128) % 128
        m += [0] + be16(typeOPT) + be16(1232) + [0, 0, 0, 0]
        m += be16(UInt16(4 + padding))
        m += be16(optionPadding) + be16(UInt16(padding)) + [UInt8](repeating: 0, count: padding)
        return m
    }

    /// Lower-case LDH labels, 1–63 octets each, 255 octets on the wire in total.
    static func encodeName(_ name: String) throws(DNSError) -> [UInt8] {
        var trimmed = name.lowercased()
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { throw .invalidName }
        var out: [UInt8] = []
        for label in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
            let bytes = Array(label.utf8)
            guard (1...63).contains(bytes.count),
                  bytes.allSatisfy({ ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D || $0 == 0x5F }) else {
                throw .invalidName
            }
            out.append(UInt8(bytes.count))
            out += bytes
        }
        out.append(0)
        guard out.count <= 255 else { throw .nameTooLong }
        return out
    }

    private static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }

    // MARK: - Parsing

    static func parse(_ bytes: [UInt8]) throws(DNSError) -> DNSMessage {
        guard bytes.count >= 12, bytes.count <= 65_535 else { throw .truncated }
        var reader = Reader(bytes: bytes, offset: 12)
        let counts = (0..<4).map { Int(UInt16(bytes[4 + $0 * 2]) << 8 | UInt16(bytes[5 + $0 * 2])) }
        // A question takes at least 5 octets, a record at least 11.
        guard counts[0] * 5 + (counts[1] + counts[2] + counts[3]) * 11 <= bytes.count - 12 else { throw .implausibleCounts }

        var questions: [Question] = []
        for _ in 0..<counts[0] {
            let name = try reader.name()
            let type = try reader.u16()
            let qclass = try reader.u16()
            questions.append(Question(name: name, type: type, qclass: qclass))
        }
        var sections: [[Record]] = [[], [], []]
        for section in 0..<3 {
            for _ in 0..<counts[section + 1] {
                let name = try reader.name()
                let type = try reader.u16()
                let rclass = try reader.u16()
                let ttl = try reader.u32()
                let length = Int(try reader.u16())
                let data = try reader.take(length)
                sections[section].append(Record(name: name, type: type, rclass: rclass, ttl: ttl, data: data))
            }
        }
        return DNSMessage(
            id: UInt16(bytes[0]) << 8 | UInt16(bytes[1]),
            flags: UInt16(bytes[2]) << 8 | UInt16(bytes[3]),
            questions: questions, answers: sections[0], authorities: sections[1], additionals: sections[2]
        )
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset: Int

        mutating func u16() throws(DNSError) -> UInt16 {
            guard offset + 2 <= bytes.count else { throw .truncated }
            defer { offset += 2 }
            return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        }

        mutating func u32() throws(DNSError) -> UInt32 {
            UInt32(try u16()) << 16 | UInt32(try u16())
        }

        mutating func take(_ count: Int) throws(DNSError) -> [UInt8] {
            guard count >= 0, offset + count <= bytes.count else { throw .truncated }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }

        /// A possibly compressed name. Each pointer must point before the position it was read at,
        /// so following pointers always terminates; the jump count is capped as well.
        mutating func name() throws(DNSError) -> String {
            var labels: [String] = []
            var position = offset
            var resume: Int?
            var wireLength = 0
            var jumps = 0
            while true {
                guard position < bytes.count else { throw .truncated }
                let length = Int(bytes[position])
                switch length & 0xC0 {
                case 0x00:
                    if length == 0 {
                        offset = resume ?? position + 1
                        return labels.isEmpty ? "." : labels.joined(separator: ".")
                    }
                    guard position + 1 + length <= bytes.count else { throw .truncated }
                    wireLength += length + 1
                    guard wireLength <= 255 else { throw .nameTooLong }
                    labels.append(String(decoding: bytes[(position + 1)...(position + length)], as: UTF8.self))
                    position += 1 + length
                case 0xC0:
                    guard position + 1 < bytes.count else { throw .truncated }
                    let target = (length & 0x3F) << 8 | Int(bytes[position + 1])
                    jumps += 1
                    guard target < position, jumps <= 64 else { throw .badPointer }
                    if resume == nil { resume = position + 2 }
                    position = target
                default:
                    throw .badPointer // 0x40 / 0x80 label types are not used
                }
            }
        }
    }
}
