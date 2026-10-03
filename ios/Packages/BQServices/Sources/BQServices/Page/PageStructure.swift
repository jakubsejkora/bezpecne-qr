import Foundation

/// The visible structure of a page in reading order, before interpretation.
///
/// Lines are what a reader sees: text blocks, form fields rendered as `Label: [          ]` and
/// buttons as `[ Text ]`. Text in `head`, `script`, `style`, `noscript`, `template`, `svg`,
/// `select` and elements hidden with the `hidden` attribute or an inline `display:none` /
/// `visibility:hidden` style is not visible and is left out.
struct PageStructure {
    enum LineKind: Equatable {
        case text
        case field(Int)
        case button
    }

    struct Line: Equatable {
        var text: String
        var kind: LineKind
    }

    struct Field: Equatable {
        /// Input type ("text", "tel", "password"…), "select" or "textarea".
        var type: String
        var name: String?
        var id: String?
        var autocomplete: String?
        var ariaLabel: String?
        var placeholder: String?
        var title: String?
        /// Text of a `<label>` that wraps the field or points at it with `for`.
        var labelText: String?
        /// Short text right before the field in the same block, used when there is no label.
        var precedingText: String?

        /// The label a reader would associate with the field.
        var displayLabel: String {
            for candidate in [labelText, precedingText, ariaLabel, placeholder, title, name] {
                if let c = candidate.map(PageStructure.cleanLabel), !c.isEmpty { return c }
            }
            return ""
        }
    }

    static let fieldBox = "[          ]"

    var lines: [Line] = []
    var fields: [Field] = []
    var title: String?
    /// h1 and h2 texts, in order, with their level.
    var headings: [(level: Int, text: String)] = []
    var ogTitle: String?
    var ogSiteName: String?
    var imageAlts: [String] = []
    /// Noteworthy `href` values of `a` and `area` (install links, remote-access tools), unresolved.
    var links: [String] = []
    /// `action` values of every form ("" when absent), unresolved.
    var formActions: [String] = []
    /// A limit stopped reading before the end: lines, fields, labels or forms beyond it are missing.
    var truncated = false
    var baseHref: String?
    var metaRefresh: String?
    /// Inline JavaScript (bounded) and event-handler attribute values.
    var scripts: [String] = []

    /// A label without surrounding whitespace, a trailing colon or a required-field asterisk.
    static func cleanLabel(_ s: String) -> String {
        var t = PageStructureBuilder.normalize(s)
        while let last = t.last, last == ":" || last == "*" || last == " " { t.removeLast() }
        return t
    }
}

/// Builds a `PageStructure` from tokens. Bounded: element depth, line count and script bytes.
struct PageStructureBuilder {
    struct Limits {
        var maxDepth = 512
        var maxLines = 10_000
        /// Text blocks are kept whole for analysis (the extract shortens them for display).
        var maxLineLength = 100_000
        var maxScriptBytes = 256 * 1024
        var maxFields = 500
        var maxLabels = 1_000
        var maxForms = 200
        var maxLinks = 50
    }

    private enum Item {
        case text(String)
        case blockBreak
        case cellBreak
        case field(Int)
        case button(String)
        case label(Int)
    }

    private struct Frame {
        var name: String
        var hidden: Bool
        var skip: Bool
        var inert: Bool
    }

    private struct Label {
        var forID: String?
        var text = ""
        var wrapsField = false
    }

    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr", "keygen", "frame",
    ]
    static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "caption", "center", "dd", "details", "dialog", "dir", "div", "dl", "dt",
        "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "html",
        "legend", "li", "main", "menu", "nav", "ol", "p", "pre", "section", "summary", "table", "tbody", "tfoot", "thead", "tr", "ul",
    ]
    /// Elements whose text is not rendered as page text.
    static let skipElements: Set<String> = ["head", "svg", "math", "select", "datalist", "object", "canvas", "audio", "video", "map"]
    /// Elements allowed in `head`; anything else starts the body.
    static let headContent: Set<String> = ["title", "meta", "link", "base", "style", "script", "noscript", "template"]
    /// Start tags that implicitly close an open element of the same group.
    static let selfClosingGroups: [Set<String>] = [["p"], ["li"], ["dt", "dd"], ["tr"], ["td", "th"], ["option"]]

    let limits: Limits
    private var stack: [Frame] = []
    private var items: [Item] = []
    private var fields: [PageStructure.Field] = []
    /// The `<label>` wrapping each field, if any (parallel to `fields`).
    private var wrappingLabels: [Int?] = []
    private var labels: [Label] = []
    private var labelStack: [Int] = []
    private var button: String?
    private var heading: (level: Int, text: String)?
    private var scriptBytes = 0
    /// Whether the most recent `script` start tag holds JavaScript (not JSON or templates).
    private var scriptIsJavaScript = false
    private var out = PageStructure()

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    static func build(_ tokens: [HTMLTokenizer.Token], limits: Limits = Limits()) -> PageStructure {
        var builder = PageStructureBuilder(limits: limits)
        for token in tokens { builder.consume(token) }
        return builder.finish()
    }

    /// Tokenizes and builds in one pass, without holding the tokens.
    static func build(html: [UInt8], tokenizerLimits: HTMLTokenizer.Limits = HTMLTokenizer.Limits(),
                      limits: Limits = Limits()) -> PageStructure {
        var builder = PageStructureBuilder(limits: limits)
        let completed = HTMLTokenizer.tokenize(html, limits: tokenizerLimits) { builder.consume($0) }
        var page = builder.finish()
        if !completed { page.truncated = true }
        return page
    }

    /// Links worth keeping however many links a page has: app installs and remote-access tools.
    static func isNoteworthyLink(_ href: String) -> Bool {
        let lower = href.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("itms-services:") { return true }
        let path = lower.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? lower
        if [".mobileconfig", ".apk", ".ipa"].contains(where: path.hasSuffix) { return true }
        return PageAnalyzer.remoteTools.contains { tool in tool.words.contains { !$0.contains(" ") && lower.contains($0) } }
    }

    // MARK: - Pass 1: tokens to items

    private var inert: Bool { stack.last?.inert ?? false }
    private var hidden: Bool { stack.last?.hidden ?? false }
    private var skipping: Bool { stack.last?.skip ?? false }
    private var visible: Bool { !inert && !hidden && !skipping }

    private mutating func consume(_ token: HTMLTokenizer.Token) {
        switch token {
        case .text(let t): text(t)
        case .startTag(let tag): start(tag)
        case .endTag(let name): end(name)
        case .rawText(let tag, let content): rawText(tag, content)
        }
    }

    private mutating func text(_ t: String) {
        if stack.last?.name == "head", t.contains(where: { !$0.isWhitespace }) { closeHead() }
        guard visible else { return }
        if heading != nil { heading!.text += t }
        if button != nil {
            button! += t
        } else if let label = labelStack.last {
            labels[label].text += t
        } else {
            items.append(.text(t))
        }
    }

    private mutating func start(_ tag: HTMLTag) {
        let name = tag.name
        if stack.last?.name == "head", !PageStructureBuilder.headContent.contains(name) { closeHead() }
        if !inert { metadata(tag) }

        if PageStructureBuilder.blockElements.contains(name) || PageStructureBuilder.skipElements.contains(name) {
            if stack.last?.name == "p" { pop(through: stack.count - 1) } // block content closes an open p
        }
        if let group = PageStructureBuilder.selfClosingGroups.first(where: { $0.contains(name) }),
           let top = stack.last?.name, group.contains(top) {
            pop(through: stack.count - 1)
        }

        if visible, !PageStructureBuilder.isHidden(tag) { content(tag) }

        let isVoid = PageStructureBuilder.voidElements.contains(name) || tag.selfClosing && (name == "svg" || stack.contains { $0.name == "svg" || $0.name == "math" })
        let rawOrRCDATA = HTMLTokenizer.rawTextElements.contains(name) || HTMLTokenizer.rcdataElements.contains(name)
        guard !isVoid, !rawOrRCDATA, stack.count < limits.maxDepth else { return }

        let parent = stack.last
        stack.append(Frame(
            name: name,
            hidden: (parent?.hidden ?? false) || PageStructureBuilder.isHidden(tag),
            skip: (parent?.skip ?? false) || PageStructureBuilder.skipElements.contains(name),
            inert: (parent?.inert ?? false) || name == "template"
        ))
        if PageStructureBuilder.blockElements.contains(name) { blockBreak() }
        if name == "td" || name == "th" { items.append(.cellBreak) }
    }

    /// Visible content started by a tag: fields, buttons, labels, headings, images, line breaks.
    private mutating func content(_ tag: HTMLTag) {
        switch tag.name {
        case "br":
            blockBreak()
        case "input":
            let type = (tag["type"] ?? "text").lowercased()
            switch type {
            case "hidden", "checkbox", "radio", "file", "range", "color", "reset":
                break
            case "submit", "button", "image":
                let label = tag["value"] ?? tag["alt"] ?? tag["aria-label"] ?? (type == "submit" ? "Odeslat" : "")
                emitButton(label)
            default:
                addField(type: type, tag)
            }
        case "textarea":
            addField(type: "textarea", tag)
        case "select":
            addField(type: "select", tag)
        case "button":
            if let open = button { emitButton(open) } // buttons cannot nest
            button = ""
        case "label":
            guard labels.count < limits.maxLabels else {
                out.truncated = true
                return
            }
            labels.append(Label(forID: tag["for"]))
            items.append(.label(labels.count - 1))
            labelStack.append(labels.count - 1)
        case "h1", "h2":
            heading = (tag.name == "h1" ? 1 : 2, "")
        case "img":
            if let alt = tag["alt"], !alt.isEmpty, out.imageAlts.count < 50 { out.imageAlts.append(alt) }
        default:
            break
        }
    }

    /// Metadata collected regardless of visibility (but never inside `template`).
    private mutating func metadata(_ tag: HTMLTag) {
        switch tag.name {
        case "meta":
            let key = (tag["property"] ?? tag["name"])?.lowercased()
            if key == "og:title", out.ogTitle == nil { out.ogTitle = tag["content"] }
            if key == "og:site_name", out.ogSiteName == nil { out.ogSiteName = tag["content"] }
            if tag["http-equiv"]?.lowercased() == "refresh", out.metaRefresh == nil { out.metaRefresh = tag["content"] ?? "" }
        case "base":
            if out.baseHref == nil, let href = tag["href"] { out.baseHref = href }
        case "a", "area":
            if let href = tag["href"], out.links.count < limits.maxLinks, PageStructureBuilder.isNoteworthyLink(href) {
                out.links.append(href)
            }
        case "form":
            if out.formActions.count < limits.maxForms {
                out.formActions.append(tag["action"] ?? "")
            } else {
                out.truncated = true
            }
        case "script":
            let type = tag["type"]?.lowercased() ?? ""
            scriptIsJavaScript = type.isEmpty || type.contains("javascript") || type.contains("ecmascript") || type == "module"
        default:
            break
        }
        // Inline event handlers can navigate too (onload="location.href='…'").
        for (attribute, value) in tag.attributes where attribute.hasPrefix("on") && !value.isEmpty {
            addScript(value)
        }
    }

    private mutating func end(_ name: String) {
        if name == "br" { // "</br>" acts as "<br>"
            if visible { blockBreak() }
            return
        }
        guard let index = stack.lastIndex(where: { $0.name == name }) else { return }
        pop(through: index)
    }

    private mutating func rawText(_ tag: String, _ content: String) {
        guard !inert else { return }
        switch tag {
        case "title":
            if out.title == nil, !stack.contains(where: { $0.name == "svg" || $0.name == "math" }) { out.title = content }
        case "script":
            if scriptIsJavaScript { addScript(content) }
        default:
            break
        }
    }

    // MARK: - Stack

    private mutating func pop(through index: Int) {
        while stack.count > index {
            let frame = stack.removeLast()
            let wasVisible = !frame.inert && !frame.hidden && !frame.skip
            switch frame.name {
            case "label":
                if !labelStack.isEmpty { labelStack.removeLast() }
            case "button":
                if let open = button, wasVisible { emitButton(open) }
                if !wasVisible { button = nil }
            case "h1", "h2":
                if let h = heading, wasVisible {
                    let text = PageStructure.cleanLabel(h.text)
                    if !text.isEmpty, out.headings.count < 20 { out.headings.append((h.level, text)) }
                }
                heading = nil
            default:
                break
            }
            if PageStructureBuilder.blockElements.contains(frame.name), wasVisible { blockBreak() }
        }
    }

    private mutating func closeHead() {
        if let index = stack.lastIndex(where: { $0.name == "head" }) { pop(through: index) }
    }

    private mutating func blockBreak() {
        if button != nil {
            button! += " "
        } else if let label = labelStack.last {
            labels[label].text += " "
        } else {
            items.append(.blockBreak)
        }
    }

    private mutating func emitButton(_ label: String) {
        button = nil
        items.append(.button(label))
    }

    private mutating func addField(type: String, _ tag: HTMLTag) {
        guard fields.count < limits.maxFields else {
            out.truncated = true
            return
        }
        var field = PageStructure.Field(type: type)
        field.name = tag["name"]
        field.id = tag["id"]
        field.autocomplete = tag["autocomplete"]
        field.ariaLabel = tag["aria-label"]
        field.placeholder = tag["placeholder"]
        field.title = tag["title"]
        if let label = labelStack.last { labels[label].wrapsField = true }
        fields.append(field)
        wrappingLabels.append(labelStack.last)
        items.append(.field(fields.count - 1))
    }

    private mutating func addScript(_ content: String) {
        guard scriptBytes < limits.maxScriptBytes, !content.isEmpty else { return }
        let room = limits.maxScriptBytes - scriptBytes
        let piece = content.utf8.count <= room ? content : String(decoding: content.utf8.prefix(room), as: UTF8.self)
        scriptBytes += piece.utf8.count
        out.scripts.append(piece)
    }

    static func isHidden(_ tag: HTMLTag) -> Bool {
        if tag.attributes["hidden"] != nil { return true }
        if tag["type"]?.lowercased() == "hidden" { return true }
        guard let style = tag["style"]?.lowercased().filter({ !$0.isWhitespace }) else { return false }
        return style.contains("display:none") || style.contains("visibility:hidden")
    }

    // MARK: - Pass 2: items to lines

    private mutating func finish() -> PageStructure {
        if let open = button { emitButton(open) }
        // Resolve labels: `for` first, then wrapping.
        var labelByID: [String: String] = [:]
        for label in labels {
            if let id = label.forID, !id.isEmpty, labelByID[id] == nil { labelByID[id] = label.text }
        }
        let fieldIDs = Set(fields.compactMap(\.id))
        for i in fields.indices {
            fields[i].labelText = wrappingLabels[i].map { labels[$0].text }
            if let id = fields[i].id, let text = labelByID[id] { fields[i].labelText = text }
        }

        var lines: [PageStructure.Line] = []
        var current = ""
        var pendingSeparator = false
        var truncatedLines = false

        func flush() {
            let text = collapse(current)
            current = ""
            pendingSeparator = false
            guard !text.isEmpty else { return }
            append(PageStructure.Line(text: text, kind: .text))
        }
        func append(_ line: PageStructure.Line) {
            guard lines.count < limits.maxLines else {
                truncatedLines = true
                return
            }
            var l = line
            if l.text.count > limits.maxLineLength {
                l.text = String(l.text.prefix(limits.maxLineLength))
                truncatedLines = true
            }
            if lines.last != l { lines.append(l) }
        }

        for item in items {
            switch item {
            case .text(let t):
                if pendingSeparator, !collapse(t).isEmpty {
                    current += " · "
                    pendingSeparator = false
                }
                current += t
            case .blockBreak:
                flush()
            case .cellBreak:
                pendingSeparator = !collapse(current).isEmpty
            case .field(let i):
                let preceding = collapse(current)
                if fields[i].labelText == nil, !preceding.isEmpty, preceding.count <= 60 {
                    fields[i].precedingText = preceding
                    current = ""
                    pendingSeparator = false
                } else {
                    flush()
                }
                let label = fields[i].displayLabel
                append(PageStructure.Line(text: label.isEmpty ? PageStructure.fieldBox : "\(label): \(PageStructure.fieldBox)", kind: .field(i)))
            case .button(let t):
                flush()
                let label = collapse(t)
                if !label.isEmpty { append(PageStructure.Line(text: "[ \(label) ]", kind: .button)) }
            case .label(let i):
                let claimed = labels[i].wrapsField || (labels[i].forID.map { fieldIDs.contains($0) } ?? false)
                if !claimed {
                    flush()
                    let text = collapse(labels[i].text)
                    if !text.isEmpty { append(PageStructure.Line(text: text, kind: .text)) }
                }
            }
        }
        flush()
        out.lines = lines
        out.fields = fields
        if truncatedLines { out.truncated = true }
        return out
    }

    /// Collapses whitespace and drops invisible characters (soft hyphen, zero-width space and
    /// joiners, BOM) that pages use to break words up.
    private func collapse(_ s: String) -> String {
        PageStructureBuilder.normalize(s)
    }

    static func normalize(_ s: String) -> String {
        let invisible: Set<Unicode.Scalar> = ["\u{00AD}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.lazy.filter { !invisible.contains($0) })
        return String(scalars).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
