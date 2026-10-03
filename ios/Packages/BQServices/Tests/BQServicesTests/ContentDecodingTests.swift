import BQCore
import Foundation
import Testing
@testable import BQServices

/// DEFLATE streams made with Python's zlib (stored, fixed and dynamic blocks).
enum DeflateFixtures {
    static let text = Array("Předplatné 99 Kč/týden, účtováno operátorem. ".utf8)
    static let secret = Array("zadejte cislo karty ".utf8)

    /// `text` × 3, fixed Huffman codes (Z_FIXED), with back-references.
    static let fixedText = hex("0b383a3335a52027b124eff04a054b4b05ef23bdfa2587f7a6a4e6e9281cde75a4b724bfecf0c2bc7c85fc82d4a2c30b4bf28b5273f51402e8a60900")
    /// `text`, one stored block (level 0).
    static let storedText = hex("013500caff50c5996564706c61746ec3a9203939204bc48d2f74c3bd64656e2c20c3bac48d746f76c3a16e6f206f706572c3a1746f72656d2e20")
    /// `text` × 20 + bytes 0…255 × 4, dynamic Huffman codes.
    static let dynamicText = hex("0b383a3335a52027b124eff04a054b4b05ef23bdfa2587f7a6a4e6e9281cde75a4b724bfecf0c2bc7c85fc82d4a2c30b4bf28b5273f5140246358d6a1ad534523431303231b3b0b2b173707271f3f0f2f10b080a098b888a894b484a49cbc8cac92b282a29aba8aaa96b686a69ebe8eae91b181a199b989a995b585a59dbd8dad93b383a39bbb8bab97b787a79fbf8faf9070406058784868547444645c7c4c6c527242625a7a4a6a567646665e7e4e6e5171416159794969557545655d7d4d6d537343635b7b4b6b577747675f7f4f6f54f983869f294a9d3a6cf98396bf69cb9f3e62f58b868f192a5cb96af58b96af59ab5ebd66fd8b869f396addbb6efd8b96bf79ebdfbf61f3878e8f091a3c78e9f3879eaf499b3e7ce5fb878e9f295abd7aedfb879ebf69dbbf7ee3f78f8e8f193a7cf9ebf78f9eaf59bb7efde7ff8f8e9f397afdfbefff8f9ebf79fbffffe8ffa7fd4ff23d9ff00")
    static var dynamicPlain: [UInt8] { Array((0..<20).flatMap { _ in text }) + Array((0..<4).flatMap { _ in (0...255).map { UInt8($0) } }) }
    /// `secret` × 2 compressed with `secret` as a preset dictionary: its first match points before
    /// the start of the stream.
    static let dictRef = hex("ab22520c00")
    /// gzip members "<p>Menu dne</p>" and "<p>Zadejte cislo karty</p>".
    static let twoMembers = hex("1f8b0800000000000003b329b0f34dcd2b5548c94bb5d12fb003001bd935310f0000001f8b0800000000000003b329b08b4a4c49cd2a495548ce2ccec957c84e2c2aa9b4d12fb00300d5f9cea51a000000")
    /// A member with `secret`, then a member whose stream refers back into the first member.
    static let memberThenDictRef = hex("1f8b0800000000000003ab4a4c49cd2a495548ce2ccec957c84e2c2aa954000083c6a03e140000001f8b0800000000000003ab22520c00aef9c63b28000000")
}

@Suite("DEFLATE decoder")
struct InflateTests {
    private func inflate(_ input: [UInt8], max: Int = 1 << 22) throws(DecodingError) -> ([UInt8], Inflate.Result) {
        var output: [UInt8] = []
        let result = try Inflate.decode(input, from: 0, into: &output, windowStart: 0, maxOutput: max)
        return (output, result)
    }

    @Test func storedFixedAndDynamicBlocks() throws {
        let text = DeflateFixtures.text
        for (stream, plain) in [(DeflateFixtures.storedText, text), (DeflateFixtures.fixedText, text + text + text),
                                (DeflateFixtures.dynamicText, DeflateFixtures.dynamicPlain), ([0x03, 0x00], [])] {
            let (output, result) = try inflate(stream)
            #expect(output == plain)
            #expect(result == Inflate.Result(end: stream.count, capped: false))
        }
    }

    @Test func theEndIsExact() throws {
        // Whatever follows the stream is not consumed: `end` points at the first byte after it.
        for stream in [DeflateFixtures.storedText, DeflateFixtures.fixedText, DeflateFixtures.dynamicText] {
            let (_, result) = try inflate(stream + [0xDE, 0xAD, 0xBE, 0xEF, 0x1F, 0x8B])
            #expect(result.end == stream.count)
        }
    }

    @Test(arguments: [0, 1, 100, 5_000, 70_000, 300_000])
    func agreesWithTheSystemEncoder(size: Int) throws {
        var rng = SeededRandom(seed: UInt64(size) + 1)
        let data = (0..<size).map { i in i % 7 == 0 ? UInt8.random(in: 0...255, using: &rng) : UInt8(65 + i % 26) }
        let stream = Fixtures.deflate(data)
        let (output, result) = try inflate(stream)
        #expect(output == data)
        #expect(result.end == stream.count)
    }

    @Test func truncatedInputGivesPartialOutput() throws {
        let stream = Fixtures.deflate(Array(String(repeating: "abcdefghij", count: 2000).utf8))
        let (output, result) = try inflate(Array(stream.prefix(stream.count / 2)))
        #expect(result == Inflate.Result(end: nil, capped: false))
        #expect(!output.isEmpty)
        #expect(Array(String(repeating: "abcdefghij", count: 2000).utf8).starts(with: output))
    }

    @Test func outputIsCapped() throws {
        let zeros = [UInt8](repeating: 0, count: 10 * 1024 * 1024)
        let (output, result) = try inflate(Fixtures.deflate(zeros), max: 300_000)
        #expect(output.count == 300_000)
        #expect(result.capped)
        let (stored, storedResult) = try inflate(DeflateFixtures.storedText, max: 10)
        #expect(stored == Array(DeflateFixtures.text.prefix(10)))
        #expect(storedResult.capped)
    }

    @Test func referencesBeforeTheStreamStartAreRejected() throws {
        #expect(throws: DecodingError.corruptData) { try inflate(DeflateFixtures.dictRef) }
        // Also when earlier output exists (another gzip member): the window starts at the stream.
        var output = DeflateFixtures.secret
        #expect(throws: DecodingError.corruptData) {
            try Inflate.decode(DeflateFixtures.dictRef, from: 0, into: &output, windowStart: output.count, maxOutput: 1 << 20)
        }
    }

    @Test func invalidStreams() {
        let invalid: [[UInt8]] = [
            [0x07],                                   // final block, reserved type 3
            [0x01, 0x05, 0x00, 0x00, 0x00],           // stored length 5, complement does not match
            [0xFD, 0xFF, 0xFF],                       // dynamic block with 288 literal codes (> 286)
            [0x05, 0x00, 0x00, 0x00, 0x00, 0x00],     // dynamic block whose code-length code has no codes at all
        ]
        for stream in invalid {
            #expect(throws: DecodingError.corruptData, "\(stream)") { try inflate(stream) }
        }
    }

    @Test func randomAndMutatedInputNeverTraps() {
        var rng = SeededRandom(seed: 42)
        let valid = [DeflateFixtures.storedText, DeflateFixtures.fixedText, DeflateFixtures.dynamicText, Fixtures.deflate(DeflateFixtures.dynamicPlain)]
        for round in 0..<3000 {
            var input: [UInt8]
            if round % 2 == 0 {
                input = (0..<Int.random(in: 0...400, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            } else {
                input = valid[round % valid.count]
                for _ in 0..<Int.random(in: 1...6, using: &rng) where !input.isEmpty {
                    input[Int.random(in: 0..<input.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng)
                }
            }
            var output: [UInt8] = []
            if let result = try? Inflate.decode(input, from: 0, into: &output, windowStart: 0, maxOutput: 100_000) {
                #expect(output.count <= 100_000)
                if let end = result.end { #expect(end <= input.count) }
            }
        }
    }

    @Test func adler32() {
        #expect(Inflate.adler32([][...]) == 1)
        #expect(Inflate.adler32(Array("Wikipedia".utf8)[...]) == 0x11E6_0398)
        let big = [UInt8](repeating: 0xFF, count: 100_000)
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in big {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        #expect(Inflate.adler32(big[...]) == b << 16 | a)
    }
}

@Suite("Content decoding (gzip, deflate, br)")
struct ContentDecodingTests {
    static let page = Array(String(repeating: "<p>Předplatné 99 Kč/týden, účtováno operátorem.</p>\n", count: 300).utf8)

    /// Appends `input` in random pieces and finishes.
    private func decode(_ coding: ContentCoding, _ input: [UInt8], complete: Bool = true, seed: UInt64 = 1, max: Int = 512 * 1024)
        throws(DecodingError) -> (output: [UInt8], completion: BodyDecoder.Completion) {
        var decoder = BodyDecoder(coding: coding, maxOutput: max)
        for piece in fragments(input, seed: seed, maxPiece: 997) { decoder.append(piece) }
        let completion = try decoder.finish(bodyComplete: complete)
        return (decoder.output, completion)
    }

    @Test(arguments: [UInt64(1), 2, 3, 99])
    func gzipWithAllHeaderFields(seed: UInt64) throws {
        let body = Fixtures.gzip(Self.page, extra: [1, 2, 3, 4, 5], name: "page.html", comment: "made in a test", headerCRC: true)
        let result = try decode(.gzip, body, seed: seed)
        #expect(result.output == Self.page)
        #expect(result.completion == .complete)
    }

    @Test func gzipChecksumsAreVerified() {
        #expect(throws: DecodingError.checksumMismatch) { try decode(.gzip, Fixtures.gzip(Self.page, corruptCRC: true)) }
        #expect(throws: DecodingError.sizeMismatch) { try decode(.gzip, Fixtures.gzip(Self.page, corruptSize: true)) }
        #expect(throws: DecodingError.invalidHeader) { try decode(.gzip, Fixtures.gzip(Self.page, reservedFlag: true)) }
        var badHeaderCRC = Fixtures.gzip(Self.page, name: "x", headerCRC: true)
        badHeaderCRC[12] ^= 0xFF // inside the stored CRC16
        #expect(throws: DecodingError.invalidHeader) { try decode(.gzip, badHeaderCRC) }
        #expect(throws: DecodingError.invalidHeader) { try decode(.gzip, [0x1F, 0x8C] + Array(repeating: 0, count: 20)) }
    }

    @Test func everyGzipMemberIsDecodedAndVerified() throws {
        // A harmless first member cannot hide a second one.
        let two = try decode(.gzip, DeflateFixtures.twoMembers)
        #expect(String(decoding: two.output, as: UTF8.self) == "<p>Menu dne</p><p>Zadejte cislo karty</p>")
        #expect(two.completion == .complete)
        // Built in-test as well, with an empty member in between.
        let members = Fixtures.gzip(Array("A".utf8)) + Fixtures.gzip([]) + Fixtures.gzip(Self.page)
        #expect(try decode(.gzip, members).output == Array("A".utf8) + Self.page)
        // The first member's trailer is checked at its exact end, before the next member.
        var badFirst = DeflateFixtures.twoMembers
        badFirst[30] ^= 0x01 // inside member 1's CRC32
        #expect(throws: DecodingError.checksumMismatch) { try decode(.gzip, badFirst) }
        // Each member's back-references stay inside that member.
        #expect(throws: DecodingError.corruptData) { try decode(.gzip, DeflateFixtures.memberThenDictRef) }
        // Bounded number of members.
        let many = (0...BodyDecoder.maxGzipMembers).flatMap { _ in Fixtures.gzip(Array("x".utf8)) }
        #expect(throws: DecodingError.tooManyMembers) { try decode(.gzip, many) }
    }

    @Test func gzipTrailingDataAndTruncation() throws {
        let body = Fixtures.gzip(Self.page)
        #expect(throws: DecodingError.trailingData) { try decode(.gzip, body + Array("\n\n".utf8)) }
        #expect(throws: DecodingError.trailingData) { try decode(.gzip, body + [0]) }
        // A body the framing calls complete must hold complete gzip data.
        #expect(throws: DecodingError.corruptData) { try decode(.gzip, Array(body.dropLast(8))) }
        #expect(throws: DecodingError.corruptData) { try decode(.gzip, Array(body.dropLast(3))) }
        #expect(throws: DecodingError.self) { try decode(.gzip, Array(body.prefix(body.count / 2))) }
        // A body cut short (cap, deadline, broken connection) keeps what decodes.
        let partial = try decode(.gzip, Array(body.prefix(body.count / 2)), complete: false)
        #expect(partial.completion == .partial)
        #expect(!partial.output.isEmpty)
        #expect(Self.page.starts(with: partial.output))
        #expect(try decode(.gzip, Array(body.dropLast(3)), complete: false).completion == .partial)
    }

    @Test func zlibAdler32IsVerified() throws {
        let wrapped = Fixtures.zlib(Self.page)
        let ok = try decode(.deflate, wrapped)
        #expect(ok.output == Self.page)
        #expect(ok.completion == .complete)
        var bad = wrapped
        bad[bad.count - 1] ^= 0x01
        #expect(throws: DecodingError.checksumMismatch) { try decode(.deflate, bad) }
        #expect(throws: DecodingError.corruptData) { try decode(.deflate, Array(wrapped.dropLast(4))) } // no Adler-32
        #expect(throws: DecodingError.trailingData) { try decode(.deflate, wrapped + [0]) }
        #expect(try decode(.deflate, Array(wrapped.dropLast(2)), complete: false).completion == .partial)
        // Preset dictionaries are refused.
        #expect(throws: DecodingError.invalidHeader) { try decode(.deflate, [0x78, 0xBB] + Array(wrapped.dropFirst(2))) }
    }

    @Test func rawDeflateOnlyWithoutAZlibHeader() throws {
        let raw = Fixtures.deflate(Self.page)
        #expect(!ZlibHeader.isValid(raw[0], raw[1]))
        let result = try decode(.deflate, raw)
        #expect(result.output == Self.page)
        #expect(result.completion == .complete)
        #expect(throws: DecodingError.trailingData) { try decode(.deflate, raw + [1, 2, 3, 4]) }
    }

    @Test func brotli() throws {
        let encoded = Fixtures.brotli(Self.page)
        #expect(!encoded.isEmpty)
        let result = try decode(.brotli, encoded, seed: 7)
        #expect(result.output == Self.page)
        #expect(result.completion == .complete)
        #expect(throws: DecodingError.self) { try decode(.brotli, Array(encoded.prefix(encoded.count / 2))) }
        #expect(try decode(.brotli, Array(encoded.prefix(encoded.count / 2)), complete: false).completion == .partial)
    }

    @Test func corruptDataNeverVerifies() throws {
        #expect(throws: DecodingError.corruptData) { try decode(.deflate, [0x07, 0x00, 0x00, 0x00]) }
        var gzip = Fixtures.gzip(Self.page)
        for i in 12..<40 { gzip[i] = 0xFF }
        #expect(throws: DecodingError.self) { try decode(.gzip, gzip) }
        if let result = try? decode(.brotli, Array(repeating: 0xFF, count: 64)) {
            #expect(result.completion != .complete)
        }
    }

    @Test func decompressionBombStopsAtTheCap() throws {
        let zeros = [UInt8](repeating: 0, count: 20 * 1024 * 1024)
        for (coding, encoded) in [(ContentCoding.gzip, Fixtures.gzip(zeros)), (.brotli, Fixtures.brotli(zeros)), (.deflate, Fixtures.zlib(zeros))] {
            #expect(encoded.count < 100 * 1024)
            let result = try decode(coding, encoded, max: 512 * 1024)
            #expect(result.output.count == 512 * 1024)
            #expect(result.completion == .truncated)
        }
    }

    @Test func emptyBodiesAreComplete() throws {
        for coding in [ContentCoding.identity, .gzip, .deflate, .brotli] {
            var decoder = BodyDecoder(coding: coding, maxOutput: 100)
            #expect(try decoder.finish(bodyComplete: true) == .complete)
            #expect(decoder.output.isEmpty)
        }
    }

    @Test func identityIsCapped() throws {
        let result = try decode(.identity, Self.page, max: 100)
        #expect(result.output == Array(Self.page.prefix(100)))
        #expect(result.completion == .truncated)
        #expect(try decode(.identity, Self.page, complete: false).completion == .partial)
    }

    @Test func contentEncodingHeader() {
        #expect(ContentCoding.parse([]) == .identity)
        #expect(ContentCoding.parse(["identity"]) == .identity)
        #expect(ContentCoding.parse(["GZIP"]) == .gzip)
        #expect(ContentCoding.parse(["x-gzip"]) == .gzip)
        #expect(ContentCoding.parse(["deflate"]) == .deflate)
        #expect(ContentCoding.parse([" br "]) == .brotli)
        #expect(ContentCoding.parse(["gzip, br"]) == nil)
        #expect(ContentCoding.parse(["zstd"]) == nil)
        #expect(ContentCoding.parse(["compress"]) == nil)
    }
}
