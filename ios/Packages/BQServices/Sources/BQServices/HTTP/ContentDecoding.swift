import BQCore
import Compression
import Foundation

/// The content codings `SafeFetcher` advertises and removes.
enum ContentCoding: Equatable {
    case identity, gzip, deflate, brotli

    /// Parses `Content-Encoding`. Stacked codings ("gzip, br") and unknown ones are not supported.
    static func parse(_ values: [String]) -> ContentCoding? {
        let codings = values
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0 != "identity" }
        switch codings {
        case []: return .identity
        case ["gzip"], ["x-gzip"]: return .gzip
        case ["deflate"]: return .deflate
        case ["br"]: return .brotli
        default: return nil
        }
    }
}

enum DecodingError: Error, Equatable {
    case invalidHeader
    case corruptData
    case checksumMismatch
    case sizeMismatch
    /// Bytes after the end of the coded data that are not another gzip member.
    case trailingData
    case tooManyMembers
}

/// Removes a content coding from a response body within an output cap.
///
/// Identity bodies are copied as they arrive. Coded bodies are collected (the caller caps the
/// collected bytes) and decoded once when the body ends, because their trailers must be checked at
/// the exact end of the coded data: gzip members (each CRC32 + ISIZE verified, every member decoded),
/// zlib (Adler-32 verified, nothing after it) and raw DEFLATE (nothing after it). Decoding stops at
/// the output cap, so a compression bomb costs at most the cap.
struct BodyDecoder {
    enum Completion: Equatable {
        /// The whole coded body was decoded and its checksums matched.
        case complete
        /// The output cap was reached; `output` holds the beginning.
        case truncated
        /// The body ended before the coded data did; `output` holds what could be decoded.
        case partial
    }

    static let maxGzipMembers = 64

    let coding: ContentCoding
    let maxOutput: Int
    private(set) var output: [UInt8] = []
    /// The output cap was reached (identity bodies: further input is ignored).
    private(set) var capped = false
    private var input: [UInt8] = []

    init(coding: ContentCoding, maxOutput: Int) {
        self.coding = coding
        self.maxOutput = maxOutput
    }

    mutating func append(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, !capped else { return }
        guard coding == .identity else {
            input += bytes
            return
        }
        let room = maxOutput - output.count
        output += bytes.prefix(room)
        if bytes.count > room { capped = true }
    }

    /// Decodes the collected body. `bodyComplete`: the HTTP framing ended normally, so the coded data
    /// must be complete and verified; otherwise what can be decoded is kept as `.partial`.
    mutating func finish(bodyComplete: Bool) throws(DecodingError) -> Completion {
        switch coding {
        case .identity:
            break
        case _ where input.isEmpty:
            break // an empty body is empty under every coding
        case .gzip:
            try gunzip(bodyComplete: bodyComplete)
        case .deflate:
            try inflateZlibOrRaw(bodyComplete: bodyComplete)
        case .brotli:
            try decodeBrotli(bodyComplete: bodyComplete)
        }
        if capped { return .truncated }
        return bodyComplete ? .complete : .partial
    }

    // MARK: gzip (RFC 1952)

    private mutating func gunzip(bodyComplete: Bool) throws(DecodingError) {
        var position = 0
        var members = 0
        while position < input.count {
            members += 1
            guard members <= BodyDecoder.maxGzipMembers else { throw .tooManyMembers }
            guard let header = try GzipHeader.length(of: input, from: position) else {
                if bodyComplete { throw .invalidHeader }
                return
            }
            let memberStart = output.count
            let result = try Inflate.decode(input, from: position + header, into: &output, windowStart: memberStart, maxOutput: maxOutput)
            if result.capped {
                capped = true
                return
            }
            guard let end = result.end, end + 8 <= input.count else {
                if bodyComplete { throw .corruptData } // framing says complete, gzip data is not
                return
            }
            let crc = BodyDecoder.littleEndian32(input, at: end)
            let size = BodyDecoder.littleEndian32(input, at: end + 4)
            guard Banking.crc32(Data(output[memberStart...])) == crc else { throw .checksumMismatch }
            guard UInt32(truncatingIfNeeded: output.count - memberStart) == size else { throw .sizeMismatch }
            position = end + 8
        }
    }

    // MARK: deflate (RFC 1950 zlib, or raw RFC 1951)

    private mutating func inflateZlibOrRaw(bodyComplete: Bool) throws(DecodingError) {
        guard input.count >= 2 else {
            if bodyComplete { throw .corruptData }
            return
        }
        let wrapped = ZlibHeader.isValid(input[0], input[1])
        if wrapped, input[1] & 0x20 != 0 { throw .invalidHeader } // preset dictionaries are not supported
        // "deflate" is often sent as raw DEFLATE; that is only assumed when there is no zlib header.
        let start = wrapped ? 2 : 0
        let result = try Inflate.decode(input, from: start, into: &output, windowStart: 0, maxOutput: maxOutput)
        if result.capped {
            capped = true
            return
        }
        guard let end = result.end else {
            if bodyComplete { throw .corruptData }
            return
        }
        var trailerEnd = end
        if wrapped {
            guard end + 4 <= input.count else {
                if bodyComplete { throw .corruptData }
                return
            }
            let adler = UInt32(input[end]) << 24 | UInt32(input[end + 1]) << 16 | UInt32(input[end + 2]) << 8 | UInt32(input[end + 3])
            guard Inflate.adler32(output[...]) == adler else { throw .checksumMismatch }
            trailerEnd = end + 4
        }
        guard trailerEnd == input.count else { throw .trailingData }
    }

    // MARK: br (RFC 7932)

    private mutating func decodeBrotli(bodyComplete: Bool) throws(DecodingError) {
        guard let stream = DecompressionStream(algorithm: COMPRESSION_BROTLI) else { throw .corruptData }
        let result = try stream.process(input, maxOutput: maxOutput + 1, final: true)
        output = Array(result.output.prefix(maxOutput))
        if result.output.count > maxOutput {
            capped = true
            return
        }
        guard bodyComplete else { return }
        guard result.ended else { throw .corruptData }
        // The decoder may read ahead, so this catches trailing bytes only when it left them unread.
        guard result.unread == 0 else { throw .trailingData }
    }

    private static func littleEndian32(_ b: [UInt8], at i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}

/// RFC 1952 member header: ID1 ID2 CM FLG MTIME(4) XFL OS [FEXTRA] [FNAME] [FCOMMENT] [FHCRC].
enum GzipHeader {
    /// The length of the header at `start` once all of it is present; nil while incomplete.
    static func length(of b: [UInt8], from start: Int = 0) throws(DecodingError) -> Int? {
        guard b.count - start >= 10 else {
            // Even a partial header must start like one.
            let partial = b[start...]
            if !partial.isEmpty, !zip(partial, [0x1F, 0x8B, 8]).allSatisfy({ $0 == $1 }) { throw .trailingData }
            return nil
        }
        guard b[start] == 0x1F, b[start + 1] == 0x8B else { throw start == 0 ? .invalidHeader : .trailingData }
        guard b[start + 2] == 8 else { throw .invalidHeader }
        let flags = b[start + 3]
        guard flags & 0xE0 == 0 else { throw .invalidHeader } // reserved bits
        var i = start + 10
        if flags & 0x04 != 0 { // FEXTRA
            guard b.count >= i + 2 else { return nil }
            i += 2 + (Int(b[i]) | Int(b[i + 1]) << 8)
            guard b.count >= i else { return nil }
        }
        for flag in [UInt8(0x08), 0x10] where flags & flag != 0 { // FNAME, FCOMMENT: zero-terminated
            guard let zero = b[i...].firstIndex(of: 0) else {
                guard b.count - i <= 4096 else { throw .invalidHeader }
                return nil
            }
            guard zero - i <= 4096 else { throw .invalidHeader }
            i = zero + 1
        }
        if flags & 0x02 != 0 { // FHCRC
            guard b.count >= i + 2 else { return nil }
            let crc16 = UInt16(b[i]) | UInt16(b[i + 1]) << 8
            guard UInt16(truncatingIfNeeded: Banking.crc32(Data(b[start..<i]))) == crc16 else { throw .invalidHeader }
            i += 2
        }
        return i - start
    }
}

/// RFC 1950 header: CM 8, window ≤ 32 KiB and the FCHECK multiple of 31.
enum ZlibHeader {
    static func isValid(_ cmf: UInt8, _ flg: UInt8) -> Bool {
        cmf & 0x0F == 8 && cmf >> 4 <= 7 && (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0
    }
}

/// A `compression_stream` decoder, used for Brotli.
final class DecompressionStream {
    private let stream: UnsafeMutablePointer<compression_stream>
    private let scratch: UnsafeMutablePointer<UInt8>
    private static let scratchSize = 64 * 1024

    init?(algorithm: compression_algorithm) {
        stream = .allocate(capacity: 1)
        scratch = .allocate(capacity: DecompressionStream.scratchSize)
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, algorithm) == COMPRESSION_STATUS_OK else {
            stream.deallocate()
            scratch.deallocate()
            return nil
        }
    }

    deinit {
        compression_stream_destroy(stream)
        stream.deallocate()
        scratch.deallocate()
    }

    struct Result {
        var output: [UInt8]
        /// The coded stream ended.
        var ended: Bool
        /// Input bytes the decoder did not consume.
        var unread: Int
    }

    /// Decodes `input`, producing at most `maxOutput` bytes (stops there). `final` marks the end of
    /// the input.
    func process(_ input: [UInt8], maxOutput: Int, final: Bool = false) throws(DecodingError) -> Result {
        var output: [UInt8] = []
        var ended = false
        var failed = false
        var unread = 0
        let flags = final ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
        let source = input.isEmpty ? [0] : input // a valid pointer; `src_size` says how much is input
        source.withUnsafeBufferPointer { src in
            stream.pointee.src_ptr = src.baseAddress!
            stream.pointee.src_size = input.count
            repeat {
                stream.pointee.dst_ptr = scratch
                stream.pointee.dst_size = DecompressionStream.scratchSize
                let status = compression_stream_process(stream, flags)
                let produced = DecompressionStream.scratchSize - stream.pointee.dst_size
                output.append(contentsOf: UnsafeBufferPointer(start: scratch, count: produced))
                if status == COMPRESSION_STATUS_END {
                    ended = true
                    break
                }
                if status != COMPRESSION_STATUS_OK {
                    failed = true
                    break
                }
                if output.count >= maxOutput { break }
            } while stream.pointee.src_size > 0 || stream.pointee.dst_size == 0
            unread = stream.pointee.src_size
        }
        if failed { throw .corruptData }
        return Result(output: output, ended: ended, unread: unread)
    }
}
