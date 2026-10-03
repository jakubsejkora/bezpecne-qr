import Foundation

/// A start tag with lowercased name and attributes (the first of duplicate attributes wins).
struct HTMLTag: Equatable {
    var name: String
    var attributes: [String: String]
    var selfClosing: Bool

    subscript(_ attribute: String) -> String? { attributes[attribute] }
}

/// A small, bounded HTML tokenizer modelled on the WHATWG states that matter for reading text:
/// tags with quoted/unquoted attributes, comments, doctype and bogus comments, raw-text elements
/// (script, style…) and RCDATA (title, textarea). It works on bytes, decodes character references
/// and never fetches or executes anything. Input and output are capped.
enum HTMLTokenizer {
    enum Token: Equatable {
        case text(String)
        case startTag(HTMLTag)
        case endTag(String)
        /// The contents of a raw-text or RCDATA element; its start tag precedes it and its end tag
        /// is consumed.
        case rawText(tag: String, text: String)
    }

    struct Limits {
        /// Bounds the work on hostile input; reaching it is reported (the rest goes unread).
        var maxTokens = 1_000_000
        var maxAttributes = 64
        var maxAttributeValue = 8 * 1024
        var maxNameLength = 64
    }

    /// Elements whose content is not markup. `noscript` is raw text because browsers with
    /// scripting enabled (Safari) treat it so.
    static let rawTextElements: Set<String> = ["script", "style", "xmp", "iframe", "noembed", "noframes", "noscript"]
    static let rcdataElements: Set<String> = ["title", "textarea"]

    /// All tokens of `input` as an array (for small inputs and tests).
    static func tokenize(_ input: [UInt8], limits: Limits = Limits()) -> [Token] {
        var tokens: [Token] = []
        tokenize(input, limits: limits) { tokens.append($0) }
        return tokens
    }

    /// Hands each token to `emit` as it is read, so a large page never exists as a token array.
    /// Returns false when anything was lost: the token limit or the budget stopped it before the end,
    /// or a tag had more attributes, or a longer name or value, than the limits keep.
    @discardableResult
    static func tokenize(_ input: [UInt8], limits: Limits = Limits(), budget: AnalysisBudget = .unlimited,
                         emit: (Token) -> Void) -> Bool {
        var count = 0
        var lossy = false
        func emitToken(_ token: Token) {
            emit(token)
            count += 1
        }
        var text: [UInt8] = []
        var i = 0
        let n = input.count

        func flushText() {
            guard !text.isEmpty else { return }
            emitToken(.text(HTMLEntities.decode(text)))
            text.removeAll(keepingCapacity: true)
        }

        while i < n, count < limits.maxTokens, !budget.spend() {
            let b = input[i]
            guard b == 0x3C, i + 1 < n else { // '<'
                text.append(b)
                i += 1
                continue
            }
            let next = input[i + 1]
            if next == 0x21 { // "<!"
                flushText()
                if i + 3 < n, input[i + 2] == 0x2D, input[i + 3] == 0x2D { // "<!--"
                    i = skipComment(input, from: i + 4)
                } else {
                    i = skip(past: 0x3E, in: input, from: i + 2) // doctype, CDATA and bogus comments
                }
            } else if next == 0x3F { // "<?" bogus comment
                flushText()
                i = skip(past: 0x3E, in: input, from: i + 2)
            } else if next == 0x2F { // "</"
                if i + 2 < n, isASCIILetter(input[i + 2]) {
                    flushText()
                    let (tag, end, cut) = parseTag(input, from: i + 2, limits: limits)
                    i = end
                    if cut { lossy = true }
                    if let tag { emitToken(.endTag(tag.name)) }
                } else if i + 2 < n, input[i + 2] == 0x3E { // "</>" is ignored
                    flushText()
                    i += 3
                } else {
                    flushText()
                    i = skip(past: 0x3E, in: input, from: i + 2)
                }
            } else if isASCIILetter(next) {
                flushText()
                let (parsed, end, cut) = parseTag(input, from: i + 1, limits: limits)
                i = end
                if cut { lossy = true }
                guard let tag = parsed else { break } // EOF inside a tag: the tag is dropped
                emitToken(.startTag(tag))
                if rawTextElements.contains(tag.name) || rcdataElements.contains(tag.name) {
                    let (contentEnd, resume) = findEndTag(tag.name, in: input, from: i)
                    let bytes = Array(input[i..<contentEnd])
                    let content = rcdataElements.contains(tag.name)
                        ? HTMLEntities.decode(bytes)
                        : String(decoding: bytes, as: UTF8.self)
                    emitToken(.rawText(tag: tag.name, text: content))
                    i = resume
                } else if tag.name == "plaintext" {
                    emitToken(.text(String(decoding: input[i...], as: UTF8.self)))
                    i = n
                }
            } else {
                text.append(b)
                i += 1
            }
        }
        let completed = i >= n
        flushText()
        return completed && !lossy
    }

    // MARK: - Tags

    /// Parses a tag name and attributes starting at the name's first byte. Returns nil when the
    /// input ends inside the tag; `cut` when a name, value or attribute was dropped by a limit.
    private static func parseTag(_ b: [UInt8], from start: Int, limits: Limits) -> (HTMLTag?, Int, cut: Bool) {
        let n = b.count
        var i = start
        var name: [UInt8] = []
        var cut = false
        while i < n, !isSpace(b[i]), b[i] != 0x2F, b[i] != 0x3E {
            if name.count < limits.maxNameLength { name.append(lower(b[i])) } else { cut = true }
            i += 1
        }
        var attributes: [String: String] = [:]
        var selfClosing = false
        while i < n {
            while i < n, isSpace(b[i]) { i += 1 }
            guard i < n else { break }
            if b[i] == 0x3E { // '>'
                let tag = HTMLTag(name: String(decoding: name, as: UTF8.self), attributes: attributes, selfClosing: selfClosing)
                return (tag, i + 1, cut)
            }
            if b[i] == 0x2F { // '/'
                selfClosing = i + 1 < n && b[i + 1] == 0x3E
                i += 1
                continue
            }
            selfClosing = false
            // Attribute name (a leading '=' belongs to the name, as in the spec).
            var attrName: [UInt8] = [b[i]]
            i += 1
            while i < n, !isSpace(b[i]), b[i] != 0x2F, b[i] != 0x3E, b[i] != 0x3D {
                if attrName.count < limits.maxNameLength { attrName.append(lower(b[i])) } else { cut = true }
                i += 1
            }
            attrName[0] = lower(attrName[0])
            while i < n, isSpace(b[i]) { i += 1 }
            var value: [UInt8] = []
            if i < n, b[i] == 0x3D { // '='
                i += 1
                while i < n, isSpace(b[i]) { i += 1 }
                if i < n, b[i] == 0x22 || b[i] == 0x27 { // quoted
                    let quote = b[i]
                    i += 1
                    while i < n, b[i] != quote {
                        if value.count < limits.maxAttributeValue { value.append(b[i]) } else { cut = true }
                        i += 1
                    }
                    i += 1 // closing quote (or past the end)
                } else {
                    while i < n, !isSpace(b[i]), b[i] != 0x3E {
                        if value.count < limits.maxAttributeValue { value.append(b[i]) } else { cut = true }
                        i += 1
                    }
                }
            }
            let key = String(decoding: attrName, as: UTF8.self)
            // The first of duplicate attributes wins (as in browsers); that loses nothing.
            if attributes[key] == nil {
                if attributes.count < limits.maxAttributes {
                    attributes[key] = HTMLEntities.decode(value, inAttribute: true)
                } else {
                    cut = true
                }
            }
        }
        return (nil, n, cut)
    }

    /// Finds `</name` followed by whitespace, '/' or '>' (ASCII case-insensitive). Returns where the
    /// content ends and where tokenizing resumes (after the end tag's '>').
    private static func findEndTag(_ name: String, in b: [UInt8], from start: Int) -> (Int, Int) {
        let pattern = Array(name.utf8)
        let n = b.count
        var i = start
        while i + 1 + pattern.count < n {
            if b[i] == 0x3C, b[i + 1] == 0x2F {
                var matches = true
                for (k, p) in pattern.enumerated() where lower(b[i + 2 + k]) != p {
                    matches = false
                    break
                }
                let after = i + 2 + pattern.count
                if matches, after >= n || isSpace(b[after]) || b[after] == 0x2F || b[after] == 0x3E {
                    return (i, skip(past: 0x3E, in: b, from: after))
                }
            }
            i += 1
        }
        return (n, n)
    }

    /// Skips a comment body starting after "<!--". Handles "<!-->" and "<!--->".
    private static func skipComment(_ b: [UInt8], from start: Int) -> Int {
        let n = b.count
        if start < n, b[start] == 0x3E { return start + 1 }
        if start + 1 < n, b[start] == 0x2D, b[start + 1] == 0x3E { return start + 2 }
        var i = start
        while i + 2 < n {
            if b[i] == 0x2D, b[i + 1] == 0x2D, b[i + 2] == 0x3E { return i + 3 }
            i += 1
        }
        return n
    }

    private static func skip(past byte: UInt8, in b: [UInt8], from start: Int) -> Int {
        var i = start
        while i < b.count {
            if b[i] == byte { return i + 1 }
            i += 1
        }
        return b.count
    }

    static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D }
    static func isASCIILetter(_ b: UInt8) -> Bool { (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) }
    static func lower(_ b: UInt8) -> UInt8 { b >= 0x41 && b <= 0x5A ? b + 0x20 : b }
}
