import Foundation

/// Character references: numeric ones and the named ones that occur in Czech and general pages.
enum HTMLEntities {
    static func decode(_ bytes: [UInt8], inAttribute: Bool = false) -> String {
        guard bytes.contains(0x26) else { return String(decoding: bytes, as: UTF8.self) } // no '&'
        var out = String()
        out.reserveCapacity(bytes.count)
        var run: [UInt8] = []
        var i = 0
        let n = bytes.count
        while i < n {
            guard bytes[i] == 0x26, let (scalarText, length) = reference(bytes, at: i, inAttribute: inAttribute) else {
                run.append(bytes[i])
                i += 1
                continue
            }
            if !run.isEmpty {
                out += String(decoding: run, as: UTF8.self)
                run.removeAll(keepingCapacity: true)
            }
            out += scalarText
            i += length
        }
        if !run.isEmpty { out += String(decoding: run, as: UTF8.self) }
        return out
    }

    /// The replacement text and the reference length for a reference at `start` ('&'), or nil.
    private static func reference(_ b: [UInt8], at start: Int, inAttribute: Bool) -> (String, Int)? {
        let n = b.count
        var i = start + 1
        guard i < n else { return nil }
        if b[i] == 0x23 { // '#'
            i += 1
            var hex = false
            if i < n, b[i] == 0x78 || b[i] == 0x58 { hex = true; i += 1 }
            var value: UInt32 = 0
            var digits = 0
            while i < n, digits < 8, let d = hex ? HTTPResponseParser.hexValue(b[i]) : (b[i] >= 0x30 && b[i] <= 0x39 ? Int(b[i] - 0x30) : nil) {
                value = value * (hex ? 16 : 10) + UInt32(d)
                digits += 1
                i += 1
            }
            guard digits > 0 else { return nil }
            if i < n, b[i] == 0x3B { i += 1 }
            return (String(numericScalar(value)), i - start)
        }
        var name: [UInt8] = []
        while i < n, name.count < 32, HTMLTokenizer.isASCIILetter(b[i]) || (b[i] >= 0x30 && b[i] <= 0x39) {
            name.append(b[i])
            i += 1
        }
        guard !name.isEmpty else { return nil }
        let key = String(decoding: name, as: UTF8.self)
        if i < n, b[i] == 0x3B, let value = named[key] { return (value, i + 1 - start) }
        // Legacy references without ';' — not inside attribute values followed by '=' or alphanumerics.
        if let value = legacy[key] {
            if inAttribute, i < n, b[i] == 0x3D || HTMLTokenizer.isASCIILetter(b[i]) || (b[i] >= 0x30 && b[i] <= 0x39) { return nil }
            return (value, i - start)
        }
        return nil
    }

    /// Numeric references, with the WHATWG replacements for C1 controls (Windows-1252 meaning).
    private static func numericScalar(_ value: UInt32) -> Character {
        if let mapped = c1Replacements[value] { return mapped }
        guard value != 0, value <= 0x10FFFF, !(0xD800...0xDFFF).contains(value), let scalar = Unicode.Scalar(value) else {
            return "\u{FFFD}"
        }
        return Character(scalar)
    }

    private static let c1Replacements: [UInt32: Character] = [
        0x80: "€", 0x82: "‚", 0x83: "ƒ", 0x84: "„", 0x85: "…", 0x86: "†", 0x87: "‡", 0x88: "ˆ", 0x89: "‰",
        0x8A: "Š", 0x8B: "‹", 0x8C: "Œ", 0x8E: "Ž", 0x91: "‘", 0x92: "’", 0x93: "“", 0x94: "”", 0x95: "•",
        0x96: "–", 0x97: "—", 0x98: "˜", 0x99: "™", 0x9A: "š", 0x9B: "›", 0x9C: "œ", 0x9E: "ž", 0x9F: "Ÿ",
    ]

    private static let legacy: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "nbsp": "\u{00A0}", "copy": "©", "reg": "®",
    ]

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "shy": "\u{00AD}",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwnj": "\u{200C}", "zwj": "\u{200D}",
        "ndash": "–", "mdash": "—", "hellip": "…", "middot": "·", "bull": "•", "laquo": "«", "raquo": "»",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„", "lsaquo": "‹", "rsaquo": "›",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°", "plusmn": "±", "times": "×", "divide": "÷",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "curren": "¤", "sect": "§", "para": "¶",
        "iexcl": "¡", "iquest": "¿", "ordf": "ª", "ordm": "º", "sup1": "¹", "sup2": "²", "sup3": "³",
        "frac12": "½", "frac14": "¼", "frac34": "¾", "micro": "µ", "uml": "¨", "acute": "´", "cedil": "¸",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "check": "✓", "star": "☆",
        // Latin-1 letters
        "Aacute": "Á", "aacute": "á", "Agrave": "À", "agrave": "à", "Acirc": "Â", "acirc": "â", "Auml": "Ä", "auml": "ä",
        "Atilde": "Ã", "atilde": "ã", "Aring": "Å", "aring": "å", "AElig": "Æ", "aelig": "æ", "Ccedil": "Ç", "ccedil": "ç",
        "Eacute": "É", "eacute": "é", "Egrave": "È", "egrave": "è", "Ecirc": "Ê", "ecirc": "ê", "Euml": "Ë", "euml": "ë",
        "Iacute": "Í", "iacute": "í", "Igrave": "Ì", "igrave": "ì", "Icirc": "Î", "icirc": "î", "Iuml": "Ï", "iuml": "ï",
        "Ntilde": "Ñ", "ntilde": "ñ", "Oacute": "Ó", "oacute": "ó", "Ograve": "Ò", "ograve": "ò", "Ocirc": "Ô", "ocirc": "ô",
        "Ouml": "Ö", "ouml": "ö", "Otilde": "Õ", "otilde": "õ", "Oslash": "Ø", "oslash": "ø", "Uacute": "Ú", "uacute": "ú",
        "Ugrave": "Ù", "ugrave": "ù", "Ucirc": "Û", "ucirc": "û", "Uuml": "Ü", "uuml": "ü", "Yacute": "Ý", "yacute": "ý",
        "yuml": "ÿ", "szlig": "ß", "ETH": "Ð", "eth": "ð", "THORN": "Þ", "thorn": "þ",
        // Latin Extended-A (Czech, Slovak, Polish, Hungarian)
        "Ccaron": "Č", "ccaron": "č", "Dcaron": "Ď", "dcaron": "ď", "Ecaron": "Ě", "ecaron": "ě", "Ncaron": "Ň", "ncaron": "ň",
        "Rcaron": "Ř", "rcaron": "ř", "Scaron": "Š", "scaron": "š", "Tcaron": "Ť", "tcaron": "ť", "Zcaron": "Ž", "zcaron": "ž",
        "Uring": "Ů", "uring": "ů", "Lcaron": "Ľ", "lcaron": "ľ", "Lacute": "Ĺ", "lacute": "ĺ", "Racute": "Ŕ", "racute": "ŕ",
        "Cacute": "Ć", "cacute": "ć", "Nacute": "Ń", "nacute": "ń", "Sacute": "Ś", "sacute": "ś", "Zacute": "Ź", "zacute": "ź",
        "Zdot": "Ż", "zdot": "ż", "Aogon": "Ą", "aogon": "ą", "Eogon": "Ę", "eogon": "ę", "Lstrok": "Ł", "lstrok": "ł",
        "Odblac": "Ő", "odblac": "ő", "Udblac": "Ű", "udblac": "ű", "OElig": "Œ", "oelig": "œ", "Yuml": "Ÿ", "fnof": "ƒ",
    ]
}
