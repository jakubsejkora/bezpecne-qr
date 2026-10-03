import Foundation

/// An RFC 1951 DEFLATE decoder after Mark Adler's puff.c: small, strict and bit-exact.
///
/// It exists because the end of a DEFLATE stream must be known exactly: the gzip trailer
/// (CRC32 + ISIZE), the zlib Adler-32 and any further gzip member start right after it. The
/// Compression framework reads ahead past the end, so it cannot say where the stream ended.
///
/// Bits are loaded one byte at a time and only when needed, so the end position is exact. Output is
/// capped, and back-references may not reach before `windowStart` (the start of the current gzip
/// member). Every table index is checked; malformed input throws instead of trapping.
enum Inflate {
    struct Result: Equatable {
        /// Index of the first byte after the final block; nil when the input ended first.
        var end: Int?
        /// The output cap was reached before the stream ended.
        var capped: Bool
    }

    private enum Stop: Error {
        case needInput
        case capped
        case invalid
    }

    /// Decodes the stream starting at `start`, appending to `output` (at most `maxOutput` bytes in
    /// total). Throws `corruptData` for streams that are not valid DEFLATE.
    static func decode(_ input: [UInt8], from start: Int, into output: inout [UInt8], windowStart: Int,
                       maxOutput: Int) throws(DecodingError) -> Result {
        var reader = BitReader(input: input, index: start)
        do throws(Stop) {
            var last = false
            repeat {
                last = try reader.bits(1) == 1
                switch try reader.bits(2) {
                case 0: try stored(&reader, &output, maxOutput: maxOutput)
                case 1: try codes(&reader, &output, Fixed.literals, Fixed.distances, windowStart: windowStart, maxOutput: maxOutput)
                case 2: try dynamic(&reader, &output, windowStart: windowStart, maxOutput: maxOutput)
                default: throw Stop.invalid
                }
            } while !last
            return Result(end: reader.index, capped: false)
        } catch {
            switch error {
            case .needInput: return Result(end: nil, capped: false)
            case .capped: return Result(end: nil, capped: true)
            case .invalid: throw .corruptData
            }
        }
    }

    // MARK: - Bits

    private struct BitReader {
        let input: [UInt8]
        /// The next byte to load.
        var index: Int
        var buffer: UInt32 = 0
        /// Bits in `buffer`: 0…7 between calls.
        var count = 0

        /// The next `n` (≤ 16) bits, least significant first.
        mutating func bits(_ n: Int) throws(Stop) -> Int {
            var value = buffer
            while count < n {
                guard index < input.count else { throw .needInput }
                value |= UInt32(input[index]) << UInt32(count)
                index += 1
                count += 8
            }
            buffer = value >> UInt32(n)
            count -= n
            return Int(value & ((1 << UInt32(n)) - 1))
        }

        /// Drops the rest of the current byte (before a stored block).
        mutating func alignToByte() {
            buffer = 0
            count = 0
        }
    }

    // MARK: - Huffman codes

    private static let maxBits = 15

    /// A canonical Huffman code: the number of codes of each length and the symbols ordered by code.
    private struct Huffman {
        var count = [Int](repeating: 0, count: Inflate.maxBits + 1)
        var symbol: [Int]

        /// Builds the code from code lengths (each 0…15). Returns nil for an over-subscribed set;
        /// `incomplete` tells whether codes are left unused.
        init?(lengths: ArraySlice<Int>, incomplete: inout Bool) {
            symbol = [Int](repeating: 0, count: lengths.count)
            for length in lengths {
                guard (0...Inflate.maxBits).contains(length) else { return nil }
                count[length] += 1
            }
            incomplete = false
            if count[0] == lengths.count { return } // no codes: decoding any symbol fails
            var left = 1
            for length in 1...Inflate.maxBits {
                left <<= 1
                left -= count[length]
                if left < 0 { return nil }
            }
            incomplete = left > 0
            var offsets = [Int](repeating: 0, count: Inflate.maxBits + 1)
            for length in 1..<Inflate.maxBits { offsets[length + 1] = offsets[length] + count[length] }
            for (i, length) in lengths.enumerated() where length != 0 {
                symbol[offsets[length]] = i
                offsets[length] += 1
            }
        }

        /// Decodes one symbol, reading one bit at a time (so nothing is read ahead).
        func decode(_ reader: inout BitReader) throws(Stop) -> Int {
            var code = 0, first = 0, index = 0
            for length in 1...Inflate.maxBits {
                code |= try reader.bits(1)
                let n = count[length]
                if code - n < first {
                    let i = index + (code - first)
                    guard i >= 0, i < symbol.count else { throw .invalid }
                    return symbol[i]
                }
                index += n
                first = (first + n) << 1
                code <<= 1
            }
            throw .invalid
        }
    }

    private enum Fixed {
        static let literals: Huffman = {
            var lengths = [Int](repeating: 8, count: 288)
            for i in 144..<256 { lengths[i] = 9 }
            for i in 256..<280 { lengths[i] = 7 }
            var incomplete = false
            return Huffman(lengths: lengths[...], incomplete: &incomplete)!
        }()

        static let distances: Huffman = {
            var incomplete = false
            return Huffman(lengths: [Int](repeating: 5, count: 30)[...], incomplete: &incomplete)!
        }()
    }

    // MARK: - Blocks

    private static func stored(_ reader: inout BitReader, _ output: inout [UInt8], maxOutput: Int) throws(Stop) {
        reader.alignToByte()
        let input = reader.input
        let i = reader.index
        guard i + 4 <= input.count else { throw .needInput }
        let length = Int(input[i]) | Int(input[i + 1]) << 8
        let complement = Int(input[i + 2]) | Int(input[i + 3]) << 8
        guard length == ~complement & 0xFFFF else { throw .invalid }
        reader.index = i + 4
        let available = min(length, input.count - reader.index)
        let n = min(available, maxOutput - output.count)
        output.append(contentsOf: input[reader.index..<reader.index + n])
        reader.index += n
        if n < length { throw n < available ? .capped : .needInput }
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                                     35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                                      3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                                       257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                                       8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                                        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    /// Literals and length/distance pairs until the end-of-block symbol.
    private static func codes(_ reader: inout BitReader, _ output: inout [UInt8], _ literals: Huffman, _ distances: Huffman,
                              windowStart: Int, maxOutput: Int) throws(Stop) {
        while true {
            let symbol = try literals.decode(&reader)
            if symbol < 256 {
                guard output.count < maxOutput else { throw .capped }
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let l = symbol - 257
                guard l < lengthBase.count else { throw .invalid }
                let length = lengthBase[l] + (try reader.bits(lengthExtra[l]))
                let d = try distances.decode(&reader)
                guard d < distanceBase.count else { throw .invalid }
                let distance = distanceBase[d] + (try reader.bits(distanceExtra[d]))
                guard distance <= output.count - windowStart else { throw .invalid } // before the stream's start
                let n = min(length, maxOutput - output.count)
                var from = output.count - distance
                for _ in 0..<n {
                    output.append(output[from])
                    from += 1
                }
                if n < length { throw .capped }
            }
        }
    }

    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static func dynamic(_ reader: inout BitReader, _ output: inout [UInt8], windowStart: Int, maxOutput: Int) throws(Stop) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeLengthCount = try reader.bits(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else { throw .invalid }

        var lengths = [Int](repeating: 0, count: 19)
        for i in 0..<codeLengthCount { lengths[codeLengthOrder[i]] = try reader.bits(3) }
        var incomplete = false
        guard let lengthCode = Huffman(lengths: lengths[...], incomplete: &incomplete), !incomplete else { throw .invalid }

        // Literal/length and distance code lengths, run-length coded.
        let total = literalCount + distanceCount
        lengths = [Int](repeating: 0, count: total)
        var index = 0
        while index < total {
            let symbol = try lengthCode.decode(&reader)
            if symbol < 16 {
                lengths[index] = symbol
                index += 1
                continue
            }
            var value = 0
            let repeats: Int
            switch symbol {
            case 16:
                guard index > 0 else { throw .invalid }
                value = lengths[index - 1]
                repeats = 3 + (try reader.bits(2))
            case 17:
                repeats = 3 + (try reader.bits(3))
            default:
                repeats = 11 + (try reader.bits(7))
            }
            guard index + repeats <= total else { throw .invalid }
            for _ in 0..<repeats {
                lengths[index] = value
                index += 1
            }
        }
        guard lengths[256] != 0 else { throw .invalid } // no end-of-block code

        // An incomplete code is allowed only for a single code of length 1.
        guard let literals = Huffman(lengths: lengths[0..<literalCount], incomplete: &incomplete),
              !incomplete || literalCount == literals.count[0] + literals.count[1] else { throw .invalid }
        guard let distances = Huffman(lengths: lengths[literalCount...], incomplete: &incomplete),
              !incomplete || distanceCount == distances.count[0] + distances.count[1] else { throw .invalid }
        try codes(&reader, &output, literals, distances, windowStart: windowStart, maxOutput: maxOutput)
    }

    // MARK: - Checksums

    /// Adler-32 (RFC 1950).
    static func adler32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let end = min(i + 5552, bytes.endIndex) // keeps the sums below 2^32 before reducing
            while i < end {
                a += UInt32(bytes[i])
                b += a
                i += 1
            }
            a %= 65521
            b %= 65521
        }
        return b << 16 | a
    }
}
