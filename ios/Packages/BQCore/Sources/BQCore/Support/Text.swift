import Foundation

extension String {
    /// Deaccented, case-folded form used for all keyword matching ("Převeďte" → "prevedte").
    public var folded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased()
    }

    /// The string with runs of whitespace collapsed to single spaces and trimmed.
    var collapsedWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Percent-decoded, or the original string when it isn't valid percent-encoding.
    var percentDecoded: String { removingPercentEncoding ?? self }

    /// First match of a regular expression (case-sensitive unless the pattern says otherwise).
    func firstMatch(_ pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let m = re.firstMatch(in: self, range: range), let r = Range(m.range, in: self) else { return nil }
        return String(self[r])
    }

    /// Capture groups of the first match.
    func captures(_ pattern: String, options: NSRegularExpression.Options = []) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        guard let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: self).map { String(self[$0]) }
        }
    }

    func matches(_ pattern: String, options: NSRegularExpression.Options = []) -> Bool {
        firstMatch(pattern, options: options) != nil
    }

    /// Whether the folded text contains `phrase` (already folded) as whole words.
    func containsFoldedPhrase(_ phrase: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return folded.matches("(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])")
    }

    /// The sentence (or clause) of `self` that contains the folded `phrase`, in original spelling.
    func sentence(containingFolded phrase: String) -> String? {
        let separators = CharacterSet(charactersIn: ".!?\n")
        for part in components(separatedBy: separators) {
            let t = part.trimmed()
            if !t.isEmpty, t.folded.contains(phrase) { return t }
        }
        return nil
    }

    /// Shannon entropy in bits per character.
    var entropy: Double {
        guard !isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for c in self { counts[c, default: 0] += 1 }
        let n = Double(count)
        return counts.values.reduce(0) { acc, k in
            let p = Double(k) / n
            return acc - p * log2(p)
        }
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
