import Foundation

/// BIP 21 (bitcoin and similar), EIP-681 (ethereum) and BOLT 11 / LNURL (lightning).
struct CryptoParser {
    static let schemes = ["bitcoin", "litecoin", "dogecoin", "bitcoincash", "ethereum", "lightning", "monero", "solana", "tron"]

    static let networkNames: [String: String] = [
        "bitcoin": "Bitcoin", "litecoin": "Litecoin", "dogecoin": "Dogecoin", "bitcoincash": "Bitcoin Cash",
        "ethereum": "Ethereum", "lightning": "Bitcoin Lightning", "monero": "Monero", "solana": "Solana", "tron": "TRON",
    ]

    static let units: [String: String] = [
        "bitcoin": "BTC", "litecoin": "LTC", "dogecoin": "DOGE", "bitcoincash": "BCH", "ethereum": "ETH",
        "lightning": "BTC", "monero": "XMR", "solana": "SOL", "tron": "TRX",
    ]

    /// Well-known ERC-20 contracts on Ethereum mainnet (lowercased address → symbol, decimals).
    static let tokens: [String: (symbol: String, decimals: Int)] = [
        "0xdac17f958d2ee523a2206206994597c13d831ec7": ("USDT", 6),
        "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": ("USDC", 6),
        "0x6b175474e89094c44da98b954eedeac495271d0f": ("DAI", 18),
        "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": ("WETH", 18),
    ]

    func parse(_ text: String, scheme: String) -> Parsed {
        let body = String(text.dropFirst(scheme.count + 1))
        switch scheme {
        case "ethereum": return ethereum(body, original: text)
        case "lightning": return lightning(body)
        default: return bip21(body, scheme: scheme)
        }
    }

    private func finish(_ info: CryptoInfo, invalidReason: LocalizedText? = nil, extra: [Finding] = []) -> Parsed {
        var parsed = Parsed(type: .crypto, content: .crypto(info))
        if let invalidReason {
            parsed.invalid = true
            parsed.consequences.append(Finding("csq.invalid_payment", ["reason": .localized(invalidReason)]))
        }
        parsed.consequences += extra
        parsed.consequences.append(Finding("csq.irreversible_crypto"))
        return parsed
    }

    private func query(_ s: String) -> [(String, String)] {
        s.split(separator: "&").compactMap { pair in
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = kv.first, !key.isEmpty else { return nil }
            let value = kv.count > 1 ? kv[1].replacingOccurrences(of: "+", with: " ").percentDecoded : ""
            return (key, value)
        }
    }

    // MARK: BIP 21

    func bip21(_ body: String, scheme: String) -> Parsed {
        let parts = body.split(separator: "?", maxSplits: 1).map(String.init)
        var info = CryptoInfo(scheme: scheme, network: CryptoParser.networkNames[scheme] ?? scheme.capitalized)
        info.address = parts.first.flatMap { $0.isEmpty ? nil : $0 }
        info.unit = CryptoParser.units[scheme]
        var unknownRequired: [String] = []
        for (key, value) in parts.count > 1 ? query(parts[1]) : [] {
            switch key.lowercased() {
            case "amount": info.amount = value
            case "label": info.label = value
            case "message": info.message = value
            case "lightning": break
            default:
                if key.lowercased().hasPrefix("req-") { unknownRequired.append(key) }
            }
        }
        var reason: LocalizedText?
        if !unknownRequired.isEmpty {
            reason = LocalizedText(cs: "Kód vyžaduje parametr, kterému nerozumíme (\(unknownRequired.joined(separator: ", "))).",
                                   en: "The code requires a parameter we don't understand (\(unknownRequired.joined(separator: ", "))).")
        } else if let amount = info.amount, Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) == nil {
            reason = LocalizedText(cs: "Částka „\(amount)“ není číslo.", en: "The amount “\(amount)” is not a number.")
        }
        return finish(info, invalidReason: reason)
    }

    // MARK: EIP-681

    func ethereum(_ body: String, original: String) -> Parsed {
        var info = CryptoInfo(scheme: "ethereum", network: "Ethereum")
        let parts = body.split(separator: "?", maxSplits: 1).map(String.init)
        var head = parts.first ?? ""
        if head.hasPrefix("pay-") { head = String(head.dropFirst(4)) }
        var function: String?
        if let slash = head.firstIndex(of: "/") {
            function = String(head[head.index(after: slash)...])
            head = String(head[..<slash])
        }
        if let at = head.firstIndex(of: "@") {
            info.chainId = Int(head[head.index(after: at)...])
            head = String(head[..<at])
        }
        let params = parts.count > 1 ? query(parts[1]) : []
        var extra: [Finding] = []
        if function?.lowercased() == "transfer" {
            info.contract = head
            info.recipient = params.first(where: { $0.0 == "address" })?.1
            let token = CryptoParser.tokens[head.lowercased()]
            info.token = token?.symbol ?? "ERC-20"
            info.unit = token?.symbol ?? "ERC-20"
            if let raw = params.first(where: { $0.0 == "uint256" })?.1 {
                info.amount = CryptoParser.scaled(raw, decimals: token?.decimals ?? 0)
            }
            var args: [String: ArgValue] = ["token": .text(info.token ?? "ERC-20")]
            args["amount"] = .text(info.amount ?? "?")
            args["recipient"] = .text(info.recipient.map(CryptoParser.shortAddress) ?? "?")
            extra.append(Finding("csq.token_contract", args))
        } else {
            info.address = head
            info.unit = "ETH"
            if let value = params.first(where: { $0.0 == "value" })?.1 {
                info.amount = CryptoParser.scaled(value, decimals: 18)
            }
        }
        return finish(info, extra: extra)
    }

    /// "250000000" with 6 decimals → "250"; accepts scientific notation ("2.014e18").
    static func scaled(_ raw: String, decimals: Int) -> String? {
        guard var value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if decimals > 0 {
            var divisor = Decimal(1)
            for _ in 0..<decimals { divisor *= 10 }
            value /= divisor
        }
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "en_US_POSIX")
        nf.maximumFractionDigits = 8
        nf.minimumFractionDigits = 0
        nf.usesGroupingSeparator = false
        return nf.string(from: value as NSDecimalNumber)
    }

    static func shortAddress(_ a: String) -> String {
        a.count > 12 ? "\(a.prefix(6))…\(a.suffix(4))" : a
    }

    // MARK: Lightning (BOLT 11)

    func lightning(_ body: String) -> Parsed {
        var info = CryptoInfo(scheme: "lightning", network: "Bitcoin Lightning")
        let invoice = body.lowercased()
        if invoice.hasPrefix("lnurl") {
            info.network = "Bitcoin Lightning (LNURL)"
            info.invoice = CryptoParser.shortInvoice(body)
            return finish(info)
        }
        info.unit = "BTC"
        info.invoice = CryptoParser.shortInvoice(invoice)
        if let decoded = Bech32.decode(invoice) {
            let hrp = decoded.hrp
            if let caps = hrp.captures("^ln(bc|tb|bcrt|tbs)([0-9]+)?([munp])?$") {
                if caps[1] != "bc" { info.network = "Bitcoin Lightning (testnet)" }
                if let digits = caps[2] {
                    let multiplier: Decimal
                    switch caps[3] {
                    case "m": multiplier = Decimal(string: "0.001")!
                    case "u": multiplier = Decimal(string: "0.000001")!
                    case "n": multiplier = Decimal(string: "0.000000001")!
                    case "p": multiplier = Decimal(string: "0.000000000001")!
                    default: multiplier = 1
                    }
                    if let n = Decimal(string: digits) {
                        info.amount = CryptoParser.scaled(NSDecimalNumber(decimal: n * multiplier).stringValue, decimals: 0)
                    }
                }
            }
            info.description = CryptoParser.bolt11Description(decoded.data)
        }
        return finish(info)
    }

    static func shortInvoice(_ s: String) -> String {
        s.count > 30 ? "\(s.prefix(17))…\(s.suffix(6))" : s
    }

    /// The `d` (description) tagged field of a BOLT 11 invoice.
    static func bolt11Description(_ data: [UInt8]) -> String? {
        // data = timestamp (7) + tagged fields + signature (104); checksum already removed.
        guard data.count > 7 + 104 else { return nil }
        var i = 7
        let end = data.count - 104
        while i + 3 <= end {
            let tag = data[i]
            let length = Int(data[i + 1]) << 5 | Int(data[i + 2])
            let start = i + 3
            guard start + length <= end else { return nil }
            if tag == 13 { // "d"
                guard let bytes = Bech32.convertBits(Array(data[start..<start + length]), from: 5, to: 8, pad: false) else { return nil }
                return String(bytes: bytes, encoding: .utf8)
            }
            i = start + length
        }
        return nil
    }
}

/// Bech32 decoding (BIP 173), without the 90-character limit (BOLT 11 invoices are longer).
enum Bech32 {
    static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    static func polymod(_ values: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = (chk & 0x1ff_ffff) << 5 ^ UInt32(v)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 { chk ^= gen[i] }
        }
        return chk
    }

    static func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    /// Returns the human-readable part and the data values without the checksum.
    static func decode(_ s: String) -> (hrp: String, data: [UInt8])? {
        let lower = s.lowercased()
        guard let sep = lower.lastIndex(of: "1") else { return nil }
        let hrp = String(lower[..<sep])
        let dataChars = lower[lower.index(after: sep)...]
        guard !hrp.isEmpty, dataChars.count >= 6 else { return nil }
        var data: [UInt8] = []
        for c in dataChars {
            guard let idx = charset.firstIndex(of: c) else { return nil }
            data.append(UInt8(idx))
        }
        guard polymod(hrpExpand(hrp) + data) == 1 else { return nil }
        return (hrp, Array(data.dropLast(6)))
    }

    static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var acc = 0, bits = 0
        var out: [UInt8] = []
        let maxv = (1 << to) - 1
        for value in data {
            guard Int(value) >> from == 0 else { return nil }
            acc = (acc << from) | Int(value)
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad, bits > 0 { out.append(UInt8((acc << (to - bits)) & maxv)) }
        return out
    }
}
