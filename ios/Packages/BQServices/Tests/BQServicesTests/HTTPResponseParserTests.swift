import Foundation
import Testing
@testable import BQServices

/// What a parse produced: the final head, the framed body, whether the message ended, the error.
struct ParseOutcome: Equatable {
    var status: Int?
    var headers: HTTPHeaders?
    var body: [UInt8] = []
    var ended = false
    var error: HTTPParseError?
}

func parse(_ pieces: [[UInt8]], eof: Bool = true, limits: HTTPResponseParser.Limits = .init()) -> ParseOutcome {
    var parser = HTTPResponseParser(limits: limits)
    var outcome = ParseOutcome()
    func apply(_ events: [HTTPResponseParser.Event]) {
        for event in events {
            switch event {
            case .head(let head):
                outcome.status = head.status
                outcome.headers = head.headers
            case .body(let bytes): outcome.body += bytes
            case .end: outcome.ended = true
            }
        }
    }
    for piece in pieces {
        var events: [HTTPResponseParser.Event] = []
        do {
            try parser.feed(piece, into: &events)
            apply(events)
        } catch {
            apply(events)
            outcome.error = error
            return outcome
        }
    }
    if eof {
        var events: [HTTPResponseParser.Event] = []
        do {
            try parser.finish(into: &events)
            apply(events)
        } catch {
            apply(events)
            outcome.error = error
        }
    }
    return outcome
}

struct ParserFixture: CustomTestStringConvertible, Sendable {
    var name: String
    var raw: String
    var status: Int?
    var body: String?
    var error: HTTPParseError?
    var testDescription: String { name }
}

@Suite("HTTP/1.1 response parser")
struct HTTPResponseParserTests {
    static let valid: [ParserFixture] = [
        ParserFixture(name: "content-length", raw: "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 5\r\n\r\nhello", status: 200, body: "hello"),
        ParserFixture(name: "chunked with extensions and trailers",
                      raw: "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5;name=value;x\r\nhello\r\n6 ; ext\r\n world\r\nA\r\n0123456789\r\n0\r\nX-Trailer: yes\r\nX-Other: 1\r\n\r\n",
                      status: 200, body: "hello world0123456789"),
        ParserFixture(name: "chunked lowercase TE and hex", raw: "HTTP/1.1 200 OK\r\ntransfer-encoding: Chunked\r\n\r\na\r\n0123456789\r\n0\r\n\r\n", status: 200, body: "0123456789"),
        ParserFixture(name: "read until close", raw: "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\nbody until the end", status: 200, body: "body until the end"),
        ParserFixture(name: "1xx interim responses are skipped",
                      raw: "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: </a.css>; rel=preload\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok",
                      status: 200, body: "ok"),
        ParserFixture(name: "status without reason", raw: "HTTP/1.1 204\r\n\r\n", status: 204, body: ""),
        ParserFixture(name: "status with empty reason", raw: "HTTP/1.1 302 \r\nLocation: /next\r\nContent-Length: 0\r\n\r\n", status: 302, body: ""),
        ParserFixture(name: "bare LF line endings", raw: "HTTP/1.1 301 Moved Permanently\nLocation: https://example.cz/\nContent-Length: 3\n\nabc", status: 301, body: "abc"),
        ParserFixture(name: "304 has no body despite Content-Length", raw: "HTTP/1.1 304 Not Modified\r\nContent-Length: 10\r\n\r\n", status: 304, body: ""),
        ParserFixture(name: "identical Content-Length values", raw: "HTTP/1.1 200 OK\r\nContent-Length: 3, 3\r\nContent-Length: 3\r\n\r\nabc", status: 200, body: "abc"),
        ParserFixture(name: "bytes after the message are ignored", raw: "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nokEXTRA GARBAGE", status: 200, body: "ok"),
        ParserFixture(name: "empty header value and OWS", raw: "HTTP/1.1 200 OK\r\nX-Empty:\r\nX-Pad: \t value \t\r\nContent-Length: 0\r\n\r\n", status: 200, body: ""),
        ParserFixture(name: "obs-text in reason and value", raw: "HTTP/1.1 200 V po\u{0159}\u{00E1}dku\r\nX-Text: \u{0159}\r\nContent-Length: 0\r\n\r\n", status: 200, body: ""),
    ]

    static let invalid: [ParserFixture] = [
        ParserFixture(name: "obs-fold", raw: "HTTP/1.1 200 OK\r\nX-A: 1\r\n  continued\r\nContent-Length: 0\r\n\r\n", error: .obsFold),
        ParserFixture(name: "space before colon", raw: "HTTP/1.1 200 OK\r\nContent-Length : 0\r\n\r\n", error: .invalidHeaderField),
        ParserFixture(name: "invalid field name", raw: "HTTP/1.1 200 OK\r\nX(A): 1\r\n\r\n", error: .invalidHeaderField),
        ParserFixture(name: "missing colon", raw: "HTTP/1.1 200 OK\r\nNoColonHere\r\n\r\n", error: .invalidHeaderField),
        ParserFixture(name: "bare CR in a value", raw: "HTTP/1.1 200 OK\r\nX-A: a\rInjected: b\r\n\r\n", error: .bareCR),
        ParserFixture(name: "NUL in a value", raw: "HTTP/1.1 200 OK\r\nX-A: a\u{0}b\r\n\r\n", error: .invalidHeaderField),
        ParserFixture(name: "TE with CL", raw: "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", error: .transferEncodingWithContentLength),
        ParserFixture(name: "conflicting Content-Length", raw: "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\nhello!", error: .conflictingContentLength),
        ParserFixture(name: "conflicting Content-Length list", raw: "HTTP/1.1 200 OK\r\nContent-Length: 5, 6\r\n\r\nhello!", error: .conflictingContentLength),
        ParserFixture(name: "invalid Content-Length", raw: "HTTP/1.1 200 OK\r\nContent-Length: +5\r\n\r\nhello", error: .invalidContentLength),
        ParserFixture(name: "TE in HTTP/1.0", raw: "HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", error: .transferEncodingInHTTP10),
        ParserFixture(name: "stacked transfer codings", raw: "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n", error: .unsupportedTransferEncoding),
        ParserFixture(name: "HTTP/2 status line", raw: "HTTP/2.0 200 OK\r\n\r\n", error: .unsupportedVersion),
        ParserFixture(name: "not HTTP", raw: "SSH-2.0-OpenSSH_9.6\r\n\r\n", error: .invalidStatusLine),
        ParserFixture(name: "status out of range", raw: "HTTP/1.1 999 Odd\r\n\r\n", error: .invalidStatusLine),
        ParserFixture(name: "two spaces after version", raw: "HTTP/1.1  200 OK\r\n\r\n", error: .invalidStatusLine),
        ParserFixture(name: "blank line before status", raw: "\r\nHTTP/1.1 200 OK\r\n\r\n", error: .invalidStatusLine),
        ParserFixture(name: "101 switching protocols", raw: "HTTP/1.1 101 Switching Protocols\r\nUpgrade: h2c\r\n\r\n", error: .switchingProtocols),
        ParserFixture(name: "invalid chunk size", raw: "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nhello\r\n0\r\n\r\n", status: 200, error: .invalidChunk),
        ParserFixture(name: "chunk data overrun", raw: "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhello\r\n0\r\n\r\n", status: 200, body: "he", error: .invalidChunk),
        ParserFixture(name: "premature EOF in fixed body", raw: "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello", status: 200, body: "hello", error: .prematureEOF),
        ParserFixture(name: "premature EOF in chunked body", raw: "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel", status: 200, body: "hel", error: .prematureEOF),
        ParserFixture(name: "EOF before head ends", raw: "HTTP/1.1 200 OK\r\nContent-Le", error: .incompleteHead),
        ParserFixture(name: "empty response", raw: "", error: .emptyResponse),
    ]

    @Test(arguments: valid + invalid)
    func fixture(_ f: ParserFixture) {
        let bytes = Array(f.raw.utf8)
        let whole = parse([bytes])
        #expect(whole.status == f.status, "status")
        if let body = f.body { #expect(String(decoding: whole.body, as: UTF8.self) == body) }
        #expect(whole.error == f.error)
        if f.error == nil { #expect(whole.ended) }

        // The same result for every fragmentation, including one byte at a time.
        var patterns = (1...40).map { fragments(bytes, seed: UInt64($0) &* 7919) }
        patterns.append(bytes.map { [$0] })
        for pieces in patterns {
            let split = parse(pieces)
            #expect(split.status == whole.status)
            #expect(split.body == whole.body)
            #expect(split.error == whole.error)
            #expect(split.ended == whole.ended)
        }
    }

    @Test func headersAreReadInOrderAndCaseInsensitively() {
        let outcome = parse([Array("HTTP/1.1 302 Found\r\nlocation: /a\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\nContent-Length: 0\r\n\r\n".utf8)])
        #expect(outcome.headers?["Location"] == "/a")
        #expect(outcome.headers?.values("set-cookie") == ["a=1", "b=2"])
    }

    @Test func oversizedHeadersAreRejected() {
        let big = "HTTP/1.1 200 OK\r\n" + (0..<1000).map { "X-Header-\($0): \(String(repeating: "v", count: 40))\r\n" }.joined() + "\r\n"
        #expect(parse([Array(big.utf8)]).error == .headerTooLarge)
        // Also when the blank line never comes.
        let endless = Array(("HTTP/1.1 200 OK\r\nX: " + String(repeating: "a", count: 40_000)).utf8)
        #expect(parse(fragments(endless, seed: 3, maxPiece: 4096), eof: false).error == .headerTooLarge)
        var limits = HTTPResponseParser.Limits()
        limits.maxHeaderFields = 3
        let many = "HTTP/1.1 200 OK\r\nA: 1\r\nB: 2\r\nC: 3\r\nD: 4\r\n\r\n"
        #expect(parse([Array(many.utf8)], limits: limits).error == .tooManyHeaders)
    }

    @Test func tooManyInterimResponses() {
        let raw = String(repeating: "HTTP/1.1 100 Continue\r\n\r\n", count: 9) + "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        #expect(parse([Array(raw.utf8)]).error == .tooManyInterimResponses)
    }

    @Test func trailersCountTowardsTheHeaderBudget() {
        var limits = HTTPResponseParser.Limits()
        limits.maxHeaderBytes = 200
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nX-Trailer: " + String(repeating: "t", count: 300) + "\r\n\r\n"
        #expect(parse([Array(raw.utf8)], limits: limits).error == .headerTooLarge)
    }

    @Test func overlongChunkLineIsRejected() {
        let raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5;" + String(repeating: "e", count: 5000) + "\r\nhello\r\n0\r\n\r\n"
        #expect(parse([Array(raw.utf8)]).error == .invalidChunk)
    }

    @Test func untilCloseBodyIsStreamed() {
        var parser = HTTPResponseParser()
        var events: [HTTPResponseParser.Event] = []
        try? parser.feed(Array("HTTP/1.1 200 OK\r\n\r\nabc".utf8), into: &events)
        #expect(events.count == 2) // head + body, no end before EOF
        events = []
        try? parser.finish(into: &events)
        #expect(events == [.end])
    }
}
