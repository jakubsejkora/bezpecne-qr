import BQCore
import Foundation

/// Finds a recurring charge on a page (§4.3b, dcb.json patterns) and a "free / prize" promise that
/// the charge contradicts. Matching runs on folded (deaccented, lower-case) text; quotes are the
/// page's own words. A price is never invented: without a match there is no offer.
struct OfferDetector: Sendable {
    struct Match: Equatable {
        /// The sentence with the charge, verbatim (≤ 160 characters).
        var text: String
        /// Index of the text block (line) it came from.
        var block: Int
        var promise: String?
        var promiseBlock: Int?
    }

    private let price: NSRegularExpression
    private let interval: NSRegularExpression
    private let subscription: NSRegularExpression
    private let operatorBilling: NSRegularExpression

    /// Price and interval must be this close (characters between them) to read as a rate.
    static let proximity = 40
    static let maxQuote = 160

    init?(patterns: DCBRules.Patterns) {
        // The interval pattern has no leading boundary in dcb.json ("den" would match in "jeden").
        guard let price = try? NSRegularExpression(pattern: patterns.price),
              let interval = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:\(patterns.interval))"),
              let subscription = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:\(patterns.subscription))"),
              let billing = try? NSRegularExpression(pattern: patterns.operatorBilling) else { return nil }
        self.price = price
        self.interval = interval
        self.subscription = subscription
        self.operatorBilling = billing
    }

    // Exclusions and promise cues (folded text).
    private static let negation = regex("\\b(?:bez|zadne|zadneho|neni|nejedna\\s+se\\s+o|no|not\\s+a)\\s+(?:\\w+\\s+)?(?:predplatn|subscription)")
    private static let cancellation = regex("\\b(?:zrus\\w*|stop|odhlas\\w*|ukonc\\w*|deaktiv\\w*|cancel\\w*|unsubscribe\\w*)\\b")
    private static let trial = regex("\\b(?:zkusebn\\w*|zkousk\\w*|vyzkous\\w*|trial)\\b")
    private static let promiseTiers: [NSRegularExpression] = [
        regex("\\b(?:zdarma|gratis|free)\\b"),
        regex("\\b(?:vyhr\\w*|vyherc\\w*|win|winner|won)\\b"),
        regex("\\b(?:darek|darku|darkem|darky|gift)\\b"),
        regex("\\b(?:gratulujeme|blahoprejeme|congratulations)\\b"),
    ]
    private static let negatedPromise = regex("\\b(?:neni|nejsou|neni\\s+to|not)\\s+$")

    /// - Parameters:
    ///   - blocks: visible text lines in reading order (buttons included).
    ///   - asksForPhoneOrCode: the page has a phone or SMS-code field (a sign-up context).
    ///   - budget: when it runs out, detection stops without a match (the caller reports truncation).
    func detect(blocks: [String], asksForPhoneOrCode: Bool, budget: AnalysisBudget = .unlimited) -> Match? {
        var subscriptionOnly: (match: Match, sentence: String)?
        for (index, block) in blocks.enumerated() {
            for sentence in OfferDetector.sentences(block) {
                if budget.spend() { return nil }
                let folded = sentence.folded
                if let rate = rateLocation(folded) {
                    var match = Match(text: OfferDetector.quote(sentence, around: rate), block: index)
                    attachPromise(to: &match, blocks: blocks, chargeSentence: sentence, budget: budget)
                    return match
                }
                if subscriptionOnly == nil, OfferDetector.matches(subscription, folded),
                   !OfferDetector.matches(OfferDetector.negation, folded),
                   !OfferDetector.matches(OfferDetector.cancellation, folded) {
                    // A bare "Předplatné" (a newspaper menu item) is not an offer: it needs a price
                    // or operator billing in the same block, or a sign-up form on the page.
                    let blockFolded = block.folded
                    if asksForPhoneOrCode || OfferDetector.matches(price, blockFolded) || OfferDetector.matches(operatorBilling, blockFolded) {
                        subscriptionOnly = (Match(text: OfferDetector.quote(sentence), block: index), sentence)
                    }
                }
            }
        }
        guard var candidate = subscriptionOnly else { return nil }
        attachPromise(to: &candidate.match, blocks: blocks, chargeSentence: candidate.sentence, budget: budget)
        return candidate.match
    }

    /// Where a price and a billing interval sit close together ("99 Kč/týden", "týdně jen 99 Kč"):
    /// the price's character offset in the folded sentence, or nil.
    private func rateLocation(_ folded: String) -> Int? {
        let range = NSRange(folded.startIndex..., in: folded)
        let prices = price.matches(in: folded, range: range).map(\.range)
        guard !prices.isEmpty else { return nil }
        let intervals = interval.matches(in: folded, range: range).map(\.range)
        guard !intervals.isEmpty else { return nil }
        // Both lists are in text order, so one walk finds each price's nearest intervals (the last
        // one starting before it and the first one starting after it): linear, not prices × intervals.
        var j = 0
        for p in prices {
            while j < intervals.count, intervals[j].location < p.location { j += 1 }
            for k in [j - 1, j] where k >= 0 && k < intervals.count {
                let i = intervals[k]
                let gap = max(i.location - (p.location + p.length), p.location - (i.location + i.length))
                if gap <= OfferDetector.proximity, let r = Range(p, in: folded) {
                    return folded.distance(from: folded.startIndex, to: r.lowerBound)
                }
            }
        }
        return nil
    }

    /// The first promise on the page, strongest kind first. None when the charge (or the promise
    /// itself) is plainly presented as a trial, and a "free" claim in the charge's own sentence
    /// ("zdarma, poté 99 Kč týdně") is a disclosure, not a contradicting promise.
    private func attachPromise(to match: inout Match, blocks: [String], chargeSentence: String, budget: AnalysisBudget) {
        if OfferDetector.matches(OfferDetector.trial, chargeSentence.folded) { return }
        for tier in OfferDetector.promiseTiers {
            for (index, block) in blocks.enumerated() {
                for sentence in OfferDetector.sentences(block) where !(index == match.block && sentence == chargeSentence) {
                    if budget.spend() { return }
                    for clause in OfferDetector.clauses(sentence) {
                        let folded = clause.folded
                        let range = NSRange(folded.startIndex..., in: folded)
                        guard let m = tier.firstMatch(in: folded, range: range), let r = Range(m.range, in: folded) else { continue }
                        if OfferDetector.matches(OfferDetector.negatedPromise, String(folded[..<r.lowerBound])) { continue }
                        // "Vyzkoušejte 7 dní zdarma" is a disclosed trial, not a deceptive promise.
                        if OfferDetector.matches(OfferDetector.trial, sentence.folded) { return }
                        match.promise = OfferDetector.quote(clause)
                        match.promiseBlock = index
                        return
                    }
                }
            }
        }
    }

    // MARK: - Text helpers

    /// Sentences of a block: split after . ! ? ; when followed by a space and an upper-case letter
    /// (so "99.90 Kč" and "č. 1234" stay whole).
    static func sentences(_ block: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(block)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            if ".!?;".contains(c) {
                var j = i + 1
                while j < chars.count, chars[j] == " " { j += 1 }
                if j >= chars.count || (j > i + 1 && (chars[j].isUppercase || c == ";")) {
                    result.append(current)
                    current = ""
                    i = j
                    continue
                }
            }
            i += 1
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Clauses of a sentence, split at commas, colons and spaced dashes.
    static func clauses(_ sentence: String) -> [String] {
        var parts = [sentence]
        for separator in [" — ", " – ", " - ", ", ", ": "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Trims surrounding whitespace and trailing punctuation. A sentence longer than the quote
    /// limit is cut at word boundaries around `focus` (a character offset, e.g. the price).
    static func quote(_ s: String, around focus: Int = 0) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        while let last = t.last, ".,;:!?".contains(last) { t.removeLast() }
        guard t.count > maxQuote else { return t }
        let chars = Array(t)
        var start = max(0, min(focus - 50, chars.count - (maxQuote - 2)))
        if start > 0, let space = chars[start...].firstIndex(of: " "), space - start < 20 { start = space + 1 }
        var end = min(chars.count, start + maxQuote - 2)
        if end < chars.count, let space = chars[start..<end].lastIndex(of: " "), end - space < 30 { end = space }
        return (start > 0 ? "…" : "") + String(chars[start..<end]) + (end < chars.count ? "…" : "")
    }

    static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants in this file; a typo must fail tests, not ship silently.
        try! NSRegularExpression(pattern: pattern)
    }
}
