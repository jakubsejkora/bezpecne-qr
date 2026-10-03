import Foundation

/// Why a response could not be parsed (RFC 9112).
enum HTTPParseError: Error, Equatable {
    case emptyResponse
    case headerTooLarge
    case tooManyHeaders
    case invalidStatusLine
    case unsupportedVersion
    case invalidHeaderField
    /// A header line starting with whitespace (obsolete line folding).
    case obsFold
    /// A CR not followed by LF.
    case bareCR
    case invalidContentLength
    case conflictingContentLength
    case transferEncodingWithContentLength
    case transferEncodingInHTTP10
    case unsupportedTransferEncoding
    case invalidChunk
    case tooManyInterimResponses
    case switchingProtocols
    /// The connection closed before the header section was complete.
    case incompleteHead
    /// The connection closed before the framed body was complete.
    case prematureEOF
}

/// A strict, incremental HTTP/1.1 response parser for a single response to a GET.
///
/// Feed it bytes as they arrive (any fragmentation) and call `finish()` at end of stream. It skips
/// 1xx interim responses, decodes chunked framing (extensions and trailers are validated and
/// dropped), honours Content-Length and read-until-close framing, and rejects syntax that browsers
/// and intermediaries could read differently: obs-fold, bare CR, invalid field names or values,
/// conflicting Content-Length and Transfer-Encoding combined with Content-Length.
struct HTTPResponseParser {
    struct Limits {
        /// Status lines and header fields of all responses, interim ones and trailers included.
        var maxHeaderBytes = 32 * 1024
        var maxHeaderFields = 256
        var maxInterimResponses = 8
        /// A chunk-size line including extensions.
        var maxChunkLineBytes = 4 * 1024
    }

    struct Head: Equatable {
        var minorVersion: Int
        var status: Int
        var reason: String
        var headers: HTTPHeaders
        var framing: Framing
    }

    enum Framing: Equatable {
        case none
        case contentLength(Int)
        case chunked
        case untilClose
    }

    enum Event: Equatable {
        case head(Head)
        case body([UInt8])
        case end
    }

    private enum State: Equatable {
        case head
        case fixed(remaining: Int)
        case chunkSize
        case chunkData(remaining: Int)
        case chunkDataEnd
        case trailers
        case untilClose
        case done
    }

    private let limits: Limits
    private var state = State.head
    private var buffer: [UInt8] = []
    private var index = 0
    private var headerBytes = 0
    private var interimResponses = 0
    private var receivedAnything = false
    /// Where the search for the end of the header section resumes.
    private var headScan = 0

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    var isComplete: Bool { state == .done }
    var headReceived: Bool { state != .head }

    /// Consumes `bytes`. Events produced before an error stay in `events`.
    mutating func feed(_ bytes: some Collection<UInt8>, into events: inout [Event]) throws(HTTPParseError) {
        if !bytes.isEmpty { receivedAnything = true }
        guard state != .done else { return } // bytes after the message are discarded
        buffer.append(contentsOf: bytes)
        defer { compact() }
        try drain(into: &events)
    }

    /// Signals end of stream.
    mutating func finish(into events: inout [Event]) throws(HTTPParseError) {
        try drain(into: &events)
        switch state {
        case .done:
            return
        case .untilClose:
            state = .done
            events.append(.end)
        case .head:
            throw receivedAnything ? .incompleteHead : .emptyResponse
        default:
            throw .prematureEOF
        }
    }

    // MARK: - State machine

    private mutating func drain(into events: inout [Event]) throws(HTTPParseError) {
        while true {
            switch state {
            case .head:
                guard let end = findHeadEnd() else {
                    if headerBytes + (buffer.count - index) > limits.maxHeaderBytes { throw .headerTooLarge }
                    return
                }
                let length = end - index
                headerBytes += length
                guard headerBytes <= limits.maxHeaderBytes else { throw .headerTooLarge }
                let head = try HTTPResponseParser.parseHead(buffer[index..<end], limits: limits)
                index = end
                headScan = index
                if (100..<200).contains(head.status) {
                    if head.status == 101 { throw .switchingProtocols }
                    interimResponses += 1
                    guard interimResponses <= limits.maxInterimResponses else { throw .tooManyInterimResponses }
                    continue
                }
                events.append(.head(head))
                switch head.framing {
                case .none:
                    state = .done
                    events.append(.end)
                    return
                case .contentLength(let n): state = .fixed(remaining: n)
                case .chunked: state = .chunkSize
                case .untilClose: state = .untilClose
                }

            case .fixed(let remaining):
                let take = min(remaining, buffer.count - index)
                if take > 0 {
                    events.append(.body(Array(buffer[index..<index + take])))
                    index += take
                }
                if remaining - take == 0 {
                    state = .done
                    events.append(.end)
                    return
                }
                state = .fixed(remaining: remaining - take)
                return

            case .chunkSize:
                guard let line = try readLine(max: limits.maxChunkLineBytes, error: .invalidChunk) else { return }
                let size = try HTTPResponseParser.parseChunkSize(line)
                state = size == 0 ? .trailers : .chunkData(remaining: size)

            case .chunkData(let remaining):
                let take = min(remaining, buffer.count - index)
                if take > 0 {
                    events.append(.body(Array(buffer[index..<index + take])))
                    index += take
                }
                guard remaining - take == 0 else {
                    state = .chunkData(remaining: remaining - take)
                    return
                }
                state = .chunkDataEnd

            case .chunkDataEnd:
                guard let line = try readLine(max: 2, error: .invalidChunk) else { return }
                guard line.isEmpty else { throw .invalidChunk }
                state = .chunkSize

            case .trailers:
                let budget = limits.maxHeaderBytes - headerBytes
                guard let line = try readLine(max: max(0, budget), error: .headerTooLarge) else { return }
                headerBytes += line.count + 2
                guard headerBytes <= limits.maxHeaderBytes else { throw .headerTooLarge }
                if line.isEmpty {
                    state = .done
                    events.append(.end)
                    return
                }
                // Trailer fields are validated like header fields and then dropped.
                _ = try HTTPResponseParser.parseField(line)

            case .untilClose:
                if index < buffer.count {
                    events.append(.body(Array(buffer[index...])))
                    index = buffer.count
                }
                return

            case .done:
                index = buffer.count
                return
            }
        }
    }

    /// The index just past the blank line ending the header section, if it has arrived.
    private mutating func findHeadEnd() -> Int? {
        var i = max(headScan, index)
        while i < buffer.count {
            if buffer[i] == 0x0A {
                // The section ends at LF LF or LF CR LF; wait for more bytes when undecided.
                guard i + 1 < buffer.count else { break }
                if buffer[i + 1] == 0x0A { return i + 2 }
                if buffer[i + 1] == 0x0D {
                    guard i + 2 < buffer.count else { break }
                    if buffer[i + 2] == 0x0A { return i + 3 }
                }
            }
            i += 1
        }
        headScan = i
        return nil
    }

    /// Reads one line terminated by LF (an optional CR before it is removed). Nil when the line has
    /// not fully arrived; throws `error` when it is longer than `max`.
    private mutating func readLine(max: Int, error: HTTPParseError) throws(HTTPParseError) -> ArraySlice<UInt8>? {
        let limit = Swift.min(buffer.count, index + max + 2)
        var i = index
        while i < limit {
            if buffer[i] == 0x0A {
                var line = buffer[index..<i]
                if line.last == 0x0D { line = line.dropLast() }
                guard !line.contains(0x0D) else { throw .bareCR }
                index = i + 1
                return line
            }
            i += 1
        }
        if buffer.count - index > max + 1 { throw error }
        return nil
    }

    private mutating func compact() {
        guard index > 0 else { return }
        buffer.removeFirst(index)
        headScan = Swift.max(0, headScan - index)
        index = 0
    }

    // MARK: - Head

    static func parseHead(_ bytes: ArraySlice<UInt8>, limits: Limits) throws(HTTPParseError) -> Head {
        var lines: [ArraySlice<UInt8>] = []
        var start = bytes.startIndex
        for i in bytes.indices where bytes[i] == 0x0A {
            var line = bytes[start..<i]
            if line.last == 0x0D { line = line.dropLast() }
            guard !line.contains(0x0D) else { throw .bareCR }
            lines.append(line)
            start = i + 1
        }
        // The last line is the empty line that ends the section.
        guard let statusLine = lines.first, statusLine.count > 0, lines.last?.isEmpty == true else { throw .invalidStatusLine }
        let (minor, status, reason) = try parseStatusLine(statusLine)

        var headers = HTTPHeaders()
        let fieldLines = lines.dropFirst().dropLast()
        guard fieldLines.count <= limits.maxHeaderFields else { throw .tooManyHeaders }
        for line in fieldLines {
            if line.first == 0x20 || line.first == 0x09 { throw .obsFold }
            let (name, value) = try parseField(line)
            headers.append(name: name, value: value)
        }
        let framing = try framing(status: status, minorVersion: minor, headers: headers)
        return Head(minorVersion: minor, status: status, reason: reason, headers: headers, framing: framing)
    }

    /// `HTTP/1.x SP 3DIGIT [SP reason]`. A missing reason (with or without the space) is accepted.
    static func parseStatusLine(_ line: ArraySlice<UInt8>) throws(HTTPParseError) -> (Int, Int, String) {
        let b = Array(line)
        guard b.count >= 12, Array(b[0..<5]) == Array("HTTP/".utf8), b[6] == 0x2E,
              isDigit(b[5]), isDigit(b[7]) else { throw .invalidStatusLine }
        guard b[5] == 0x31 else { throw .unsupportedVersion } // major version 1 only
        guard b[8] == 0x20, isDigit(b[9]), isDigit(b[10]), isDigit(b[11]) else { throw .invalidStatusLine }
        let status = Int(b[9] - 0x30) * 100 + Int(b[10] - 0x30) * 10 + Int(b[11] - 0x30)
        guard (100...599).contains(status) else { throw .invalidStatusLine }
        var reason = ""
        if b.count > 12 {
            guard b[12] == 0x20 else { throw .invalidStatusLine }
            let rest = b[13...]
            guard rest.allSatisfy({ $0 == 0x09 || ($0 >= 0x20 && $0 != 0x7F) }) else { throw .invalidStatusLine }
            reason = decodeFieldValue(rest)
        }
        return (Int(b[7] - 0x30), status, reason)
    }

    /// `field-name ":" OWS field-value OWS`, with a token name and no control characters in the value.
    static func parseField(_ line: ArraySlice<UInt8>) throws(HTTPParseError) -> (String, String) {
        guard let colon = line.firstIndex(of: 0x3A), colon > line.startIndex else { throw .invalidHeaderField }
        let name = line[line.startIndex..<colon]
        guard name.allSatisfy(isTokenChar) else { throw .invalidHeaderField }
        var value = line[(colon + 1)...]
        while let f = value.first, f == 0x20 || f == 0x09 { value = value.dropFirst() }
        while let l = value.last, l == 0x20 || l == 0x09 { value = value.dropLast() }
        // VCHAR, obs-text, SP and HTAB only; NUL, CR, LF, other controls and DEL are rejected.
        guard value.allSatisfy({ $0 == 0x09 || ($0 >= 0x20 && $0 != 0x7F) }) else { throw .invalidHeaderField }
        return (String(decoding: name, as: UTF8.self), decodeFieldValue(value))
    }

    /// Field values are octets; UTF-8 when valid, otherwise ISO-8859-1.
    static func decodeFieldValue(_ bytes: some Collection<UInt8>) -> String {
        if let s = String(validating: bytes, as: UTF8.self) { return s }
        return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    // MARK: - Framing (RFC 9112 §6.3)

    static func framing(status: Int, minorVersion: Int, headers: HTTPHeaders) throws(HTTPParseError) -> Framing {
        if (100..<200).contains(status) || status == 204 || status == 304 { return .none }
        let transferEncodings = headers.values("transfer-encoding")
        let contentLengths = headers.values("content-length")
        if !transferEncodings.isEmpty {
            guard minorVersion >= 1 else { throw .transferEncodingInHTTP10 }
            guard contentLengths.isEmpty else { throw .transferEncodingWithContentLength }
            let codings = transferEncodings
                .flatMap { $0.split(separator: ",") }
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            guard codings == ["chunked"] else { throw .unsupportedTransferEncoding }
            return .chunked
        }
        if !contentLengths.isEmpty {
            var lengths = Set<Int>()
            for value in contentLengths.flatMap({ $0.split(separator: ",", omittingEmptySubsequences: false) }) {
                let v = value.trimmingCharacters(in: .whitespaces)
                guard !v.isEmpty, v.count <= 15, v.utf8.allSatisfy(isDigit), let n = Int(v) else { throw .invalidContentLength }
                lengths.insert(n)
            }
            guard lengths.count == 1, let n = lengths.first else { throw .conflictingContentLength }
            return n == 0 ? .none : .contentLength(n)
        }
        return .untilClose
    }

    /// `1*HEXDIG [BWS ";" chunk-ext]`. The size must fit comfortably in an Int.
    static func parseChunkSize(_ line: ArraySlice<UInt8>) throws(HTTPParseError) -> Int {
        var size = 0
        var digits = 0
        var i = line.startIndex
        while i < line.endIndex, let d = hexValue(line[i]) {
            digits += 1
            guard digits <= 15 else { throw .invalidChunk }
            size = size * 16 + d
            i += 1
        }
        guard digits > 0 else { throw .invalidChunk }
        var rest = line[i...]
        while let f = rest.first, f == 0x20 || f == 0x09 { rest = rest.dropFirst() }
        if let f = rest.first {
            guard f == 0x3B else { throw .invalidChunk } // ';' starts the extensions
            guard rest.allSatisfy({ $0 == 0x09 || ($0 >= 0x20 && $0 != 0x7F) }) else { throw .invalidChunk }
        }
        return size
    }

    // MARK: - Character classes

    static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

    static func hexValue(_ b: UInt8) -> Int? {
        switch b {
        case 0x30...0x39: return Int(b - 0x30)
        case 0x41...0x46: return Int(b - 0x41 + 10)
        case 0x61...0x66: return Int(b - 0x61 + 10)
        default: return nil
        }
    }

    /// RFC 9110 tchar.
    static func isTokenChar(_ b: UInt8) -> Bool {
        switch b {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        case 0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B, 0x2D, 0x2E, 0x5E, 0x5F, 0x60, 0x7C, 0x7E: return true
        default: return false
        }
    }
}
