import Foundation

/// Turns an HTML body into text: BOM, then the `Content-Type` charset, then `<meta charset>` in
/// the first 1024 bytes, else UTF-8 — and when UTF-8 is invalid, the Central European legacy
/// encodings (windows-1250 or ISO-8859-2, whichever reads as more plausible Czech).
enum TextDecoding {
    static func decode(_ data: Data, declaredCharset: String?) -> String {
        let bytes = [UInt8](data)
        // A byte order mark wins over any declaration.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: bytes.dropFirst(3), as: UTF8.self) }
        if bytes.starts(with: [0xFE, 0xFF]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16BigEndian) ?? "" }
        if bytes.starts(with: [0xFF, 0xFE]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16LittleEndian) ?? "" }

        let label = declaredCharset ?? metaCharset(in: Array(bytes.prefix(1024)))
        if let label, let encoding = encoding(forLabel: label) {
            if encoding == .utf8 { return String(decoding: bytes, as: UTF8.self) }
            if let text = String(data: data, encoding: encoding) { return text }
        }
        if isValidUTF8(bytes) { return String(decoding: bytes, as: UTF8.self) }
        return centralEuropean(data)
    }

    /// Maps a charset label to an encoding (WHATWG: latin1 and ASCII labels mean windows-1252).
    static func encoding(forLabel label: String) -> String.Encoding? {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))).lowercased()
        switch l {
        case "utf-8", "utf8", "unicode-1-1-utf-8": return .utf8
        case "windows-1250", "cp1250", "x-cp1250": return .windowsCP1250
        case "iso-8859-2", "iso8859-2", "latin2", "l2", "iso_8859-2", "csisolatin2": return .isoLatin2
        case "iso-8859-1", "iso8859-1", "latin1", "l1", "us-ascii", "ascii", "windows-1252", "cp1252": return .windowsCP1252
        case "utf-16", "utf-16le": return .utf16LittleEndian
        case "utf-16be": return .utf16BigEndian
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(l as CFString)
            guard cf != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
    }

    /// The charset from `<meta charset>` or `<meta http-equiv="Content-Type" content="…charset=…">`.
    static func metaCharset(in prefix: [UInt8]) -> String? {
        for token in HTMLTokenizer.tokenize(prefix) {
            guard case .startTag(let tag) = token, tag.name == "meta" else { continue }
            if let charset = tag["charset"], !charset.isEmpty { return charset }
            if tag["http-equiv"]?.lowercased() == "content-type", let content = tag["content"],
               let charset = ContentType(content)?.charset {
                return charset
            }
        }
        return nil
    }

    /// Strict UTF-8 validation that tolerates a sequence cut off at the very end (a truncated body).
    static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        if String(validating: bytes, as: UTF8.self) != nil { return true }
        for cut in 1...3 where bytes.count > cut {
            if String(validating: bytes.dropLast(cut), as: UTF8.self) != nil { return true }
        }
        return false
    }

    /// windows-1250 and ISO-8859-2 differ mainly in where š, ž, ť, ś and ź live. Bytes 0x80–0x9F
    /// are controls in ISO-8859-2, so they decide for windows-1250; otherwise the decoding with
    /// more common Czech letters wins.
    static func centralEuropean(_ data: Data) -> String {
        let windows = String(data: data, encoding: .windowsCP1250)
        if data.contains(where: { (0x80...0x9F).contains($0) }) { return windows ?? String(decoding: data, as: UTF8.self) }
        let iso = String(data: data, encoding: .isoLatin2)
        switch (windows, iso) {
        case let (w?, i?): return czechScore(i) > czechScore(w) ? i : w
        case let (w?, nil): return w
        case let (nil, i?): return i
        default: return String(decoding: data, as: UTF8.self)
        }
    }

    private static let czechLetters = Set("ěščřžýáíéůúťďňĚŠČŘŽÝÁÍÉŮÚŤĎŇ")
    private static let unlikelyLetters = Set("ąśźĄŚŹľĽ")

    private static func czechScore(_ text: String) -> Int {
        var score = 0
        for c in text {
            if czechLetters.contains(c) { score += 1 } else if unlikelyLetters.contains(c) { score -= 2 }
        }
        return score
    }
}
