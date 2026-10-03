import BQCore
import Foundation

/// What the link inspector learns from one HTML page.
public struct PageAnalysis: Sendable, Hashable {
    /// A `<meta http-equiv="refresh">` (or `Refresh` header) instruction.
    public struct Refresh: Sendable, Hashable {
        public var delay: Double
        /// Absolute target; nil means "reload this page".
        public var url: URL?
    }

    public var facts: PageFacts
    public var refresh: Refresh?
    /// Literal URLs that inline scripts or event handlers assign to `location`. Never executed;
    /// candidates, not observed hops.
    public var scriptRedirects: [URL]
    /// The page shows (almost) nothing but navigates by script: the next destination is unknown.
    /// (A page that merely renders its content with script is not script-only; its extract is
    /// just empty.)
    public var scriptOnly: Bool
    /// An analysis limit was reached, so part of the page was not examined.
    public var truncated: Bool
}

/// Turns a fetched HTML body into an inert `PageFacts` summary with a bounded tokenizer of our
/// own — no WebKit and no `NSAttributedString` HTML import, which can load resources. Nothing is
/// executed or fetched.
public struct PageAnalyzer: Sendable {
    public struct Limits: Sendable {
        /// Bytes of HTML examined; more is reported as `truncated`. Above the inspector's budgets.
        public var maxInputBytes = 4 * 1024 * 1024
        public var maxExtractLines = 40
        public var maxExtractLineLength = 200
        public var maxTitleLength = 200
        public init() {}
    }

    private let brands: [Brand]
    private let offers: OfferDetector?
    private let limits: Limits

    public init(rules: RuleSet = .bundled, limits: Limits = Limits()) {
        brands = rules.brands
        offers = OfferDetector(patterns: rules.dcb.patterns)
        self.limits = limits
    }

    /// - Parameters:
    ///   - body: the decoded (content-coding removed) response body.
    ///   - charset: the `Content-Type` charset parameter, if any.
    ///   - url: the page URL, for resolving links, forms and refresh targets.
    ///   - refreshHeader: the value of a `Refresh` response header, if any.
    public func analyze(_ body: Data, charset: String?, url: URL, refreshHeader: String? = nil) -> PageAnalysis {
        let text = TextDecoding.decode(body.prefix(limits.maxInputBytes), declaredCharset: charset)
        let page = PageStructureBuilder.build(html: Array(text.utf8))
        let base = PageAnalyzer.base(page.baseHref, page: url)

        // What the page asks for, in order of appearance.
        var asks: [AskKind] = []
        func add(_ kind: AskKind) { if !asks.contains(kind) { asks.append(kind) } }
        for line in page.lines {
            switch line.kind {
            case .field(let i): AskClassifier.classify(page.fields[i]).map(add)
            case .text: AskClassifier.instructions(in: line.text).forEach(add)
            case .button: break
            }
        }

        // Offer and promise, matched on text and button lines (field lines are blanked).
        let blocks = page.lines.map { line -> String in
            if case .field = line.kind { return "" }
            return line.text
        }
        let match = offers?.detect(blocks: blocks, asksForPhoneOrCode: asks.contains(.phone) || asks.contains(.otp))

        let (extract, extractIndex) = makeExtract(page.lines, keep: [match?.block, match?.promiseBlock].compactMap { $0 },
                                                  offerText: match?.text)
        let offer = match.map { m in
            Offer(text: m.text, promise: m.promise, highlight: extractIndex[m.block].map { [$0] } ?? [])
        }

        let refresh = (page.metaRefresh ?? refreshHeader).flatMap { PageAnalyzer.parseRefresh($0, base: base) }
        let scriptRedirects = ScriptRedirects.candidates(in: page.scripts, base: base)
        // At most a "Redirecting…" line besides the script redirect.
        let nearlyEmpty = page.lines.count <= 2 && page.lines.allSatisfy { $0.kind == .text && $0.text.count <= 60 }
        let scriptOnly = nearlyEmpty && !scriptRedirects.isEmpty

        let facts = PageFacts(
            title: title(page),
            extract: extract,
            asks: asks,
            offer: offer,
            brandClaim: PageAnalyzer.brandClaim(in: claimTexts(page), brands: brands),
            installLink: PageAnalyzer.installLink(page.links, base: base),
            remoteAccess: PageAnalyzer.remoteAccess(lines: page.lines.map(\.text), links: page.links),
            foreignFormHosts: PageAnalyzer.foreignFormHosts(page.formActions, base: base, pageHost: url.asciiHost)
        )
        return PageAnalysis(facts: facts, refresh: refresh, scriptRedirects: scriptRedirects, scriptOnly: scriptOnly,
                            truncated: page.truncated || body.count > limits.maxInputBytes)
    }

    // MARK: - Extract

    /// The first lines of the page; lines in `keep` (the offer and promise) are always included,
    /// replacing the last regular lines when they lie further down.
    private func makeExtract(_ lines: [PageStructure.Line], keep: [Int], offerText: String?) -> ([String], [Int: Int]) {
        let cap = limits.maxExtractLines
        let late = Set(keep.filter { $0 >= cap && $0 < lines.count }).sorted()
        let indexes = Array(0..<min(lines.count, cap - late.count)) + late
        var map: [Int: Int] = [:]
        var extract: [String] = []
        for i in indexes {
            map[i] = extract.count
            extract.append(shorten(lines[i].text, keeping: offerText))
        }
        return (extract, map)
    }

    /// Long lines are cut at a word boundary; a line holding the offer is cut around it.
    private func shorten(_ line: String, keeping quote: String?) -> String {
        let max = limits.maxExtractLineLength
        guard line.count > max else { return line }
        var start = line.startIndex
        if let quote, let r = line.range(of: quote.hasSuffix("…") ? String(quote.dropLast()) : quote),
           line.distance(from: line.startIndex, to: r.upperBound) > max - 1 {
            start = line.index(r.lowerBound, offsetBy: -min(20, line.distance(from: line.startIndex, to: r.lowerBound)))
        }
        let prefix = start == line.startIndex ? "" : "…"
        var cut = String(line[start...].prefix(max - 1 - prefix.count))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > max / 2 { cut = String(cut[..<space]) }
        return prefix + cut + "…"
    }

    private func title(_ page: PageStructure) -> String? {
        let candidates = [page.title, page.headings.first(where: { $0.level == 1 })?.text, page.ogTitle]
        for candidate in candidates {
            let t = PageStructureBuilder.normalize(candidate ?? "")
            if !t.isEmpty { return t.count > limits.maxTitleLength ? String(t.prefix(limits.maxTitleLength - 1)) + "…" : t }
        }
        return nil
    }

    /// Where a page presents its identity: title, h1, og:site_name, h2 and logo-like image alt
    /// texts (article photos — "Koncert v O2 areně" — are not identity claims).
    private func claimTexts(_ page: PageStructure) -> [String] {
        let logos = page.imageAlts.prefix(10).filter { alt in
            let words = AskClassifier.normalized(alt).split(separator: " ")
            return words.contains("logo") || words.count <= 4
        }
        return [page.title].compactMap { $0 }
            + page.headings.filter { $0.level == 1 }.map(\.text)
            + [page.ogSiteName].compactMap { $0 }
            + page.headings.filter { $0.level == 2 }.map(\.text)
            + logos
    }

    // MARK: - Interpretation helpers

    /// The first brand whose name, or one of its tokens, appears as whole words in the most
    /// prominent text that names any brand.
    static func brandClaim(in texts: [String], brands: [Brand]) -> String? {
        for text in texts {
            let haystack = AskClassifier.normalized(text)
            var best: (position: Int, length: Int, name: String)?
            for brand in brands {
                for needle in [brand.name] + brand.tokens {
                    let n = AskClassifier.normalized(needle)
                    guard n.count > 3, let r = haystack.range(of: n) else { continue }
                    let position = haystack.distance(from: haystack.startIndex, to: r.lowerBound)
                    if let b = best, position > b.position || (position == b.position && n.count <= b.length) { continue }
                    best = (position, n.count, brand.name)
                }
            }
            if let best { return best.name }
        }
        return nil
    }

    static let remoteTools: [(name: String, words: [String])] = [
        ("AnyDesk", ["anydesk"]),
        ("TeamViewer", ["teamviewer", "team viewer"]),
        ("QuickSupport", ["quicksupport", "quick support"]),
        ("RustDesk", ["rustdesk"]),
        ("Splashtop", ["splashtop"]),
    ]

    static func remoteAccess(lines: [String], links: [String]) -> [String] {
        var found: [String] = []
        let text = AskClassifier.normalized(lines.joined(separator: " "))
        let hrefs = links.joined(separator: " ").lowercased()
        for tool in remoteTools {
            let mentioned = tool.words.contains { text.contains(" \($0) ") }
            let linked = tool.words.contains { !$0.contains(" ") && hrefs.contains($0) }
            if mentioned || linked { found.append(tool.name) }
        }
        return found
    }

    static func installLink(_ links: [String], base: URL) -> String? {
        for raw in links {
            let href = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if href.lowercased().hasPrefix("itms-services:") { return href }
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
            let path = url.path().lowercased()
            if [".mobileconfig", ".apk", ".ipa"].contains(where: { path.hasSuffix($0) }) { return url.absoluteString }
        }
        return nil
    }

    static func foreignFormHosts(_ actions: [String], base: URL, pageHost: String?) -> [String] {
        var hosts: [String] = []
        for action in actions {
            let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.asciiHost, host != pageHost?.lowercased(), !hosts.contains(host) else { continue }
            hosts.append(host)
        }
        return hosts
    }

    /// `<base href>` when it is an absolute http(s) URL (relative ones resolve against the page).
    static func base(_ href: String?, page: URL) -> URL {
        guard let href, let url = URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: page)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return page }
        return url
    }

    /// WHATWG "shared declarative refresh steps": `5; url=…`, `0;URL='…'`, `3` (reload).
    static func parseRefresh(_ content: String, base: URL) -> PageAnalysis.Refresh? {
        var s = Substring(content).drop(while: { $0.isWhitespace })
        let integer = s.prefix(while: { $0.isASCII && $0.isNumber })
        guard !integer.isEmpty || s.first == "." else { return nil }
        let number = s.prefix(while: { $0.isASCII && ($0.isNumber || $0 == ".") })
        let delay = Double(integer.isEmpty ? "0" : String(integer.prefix(9))) ?? 0
        s = s.dropFirst(number.count)
        guard let first = s.first else { return Refresh(delay: delay, url: nil) }
        guard first == ";" || first == "," || first.isWhitespace else { return nil }
        s = s.drop(while: { $0.isWhitespace })
        if s.first == ";" || s.first == "," { s = s.dropFirst().drop(while: { $0.isWhitespace }) }
        let beforeURL = s
        if s.prefix(3).lowercased() == "url" {
            var t = s.dropFirst(3).drop(while: { $0.isWhitespace })
            if t.first == "=" {
                t = t.dropFirst().drop(while: { $0.isWhitespace })
                s = t
            } else {
                s = beforeURL
            }
        }
        var target: Substring
        if let quote = s.first, quote == "'" || quote == "\"" {
            target = s.dropFirst().prefix(while: { $0 != quote })
        } else {
            target = s
        }
        target = Substring(target.trimmingCharacters(in: .whitespaces))
        guard !target.isEmpty else { return Refresh(delay: delay, url: nil) }
        return Refresh(delay: delay, url: URL(string: String(target), relativeTo: base)?.absoluteURL)
    }

    typealias Refresh = PageAnalysis.Refresh
}

/// Literal navigation targets in inline JavaScript: `location = '…'`, `location.href = "…"`,
/// `location.replace('…')`, `location.assign('…')`, with or without a `window.`/`document.`/`top.`
/// prefix. Text matching only.
enum ScriptRedirects {
    private static let patterns: [NSRegularExpression] = [
        #"\blocation(?:\s*\.\s*href)?\s*=\s*["']([^"'\s]{1,2048})["']"#,
        #"\blocation\s*\.\s*(?:replace|assign)\s*\(\s*["']([^"'\s]{1,2048})["']\s*\)"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    static func candidates(in scripts: [String], base: URL, limit: Int = 5) -> [URL] {
        var urls: [URL] = []
        for script in scripts {
            let range = NSRange(script.startIndex..., in: script)
            for pattern in patterns {
                for m in pattern.matches(in: script, range: range) {
                    guard let r = Range(m.range(at: 1), in: script) else { continue }
                    let literal = script[r].replacingOccurrences(of: "\\/", with: "/")
                    guard let url = URL(string: literal, relativeTo: base)?.absoluteURL,
                          let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.asciiHost != nil,
                          !urls.contains(url) else { continue }
                    urls.append(url)
                    if urls.count >= limit { return urls }
                }
            }
        }
        return urls
    }
}
