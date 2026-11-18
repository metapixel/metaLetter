import AppKit

struct MarkdownStyle {
    var font: NSFont
    var lineHeight: CGFloat
    var alignment: NSTextAlignment = .left
}

/// Kleiner, bewusst einfacher Markdown-Renderer für Briefe.
/// Zeilenumbrüche bleiben erhalten (wie man es im Brief erwartet).
/// Unterstützt: **fett**, __fett__, *kursiv*, _kursiv_, `code`,
/// # Überschrift (fett), - / * / + Listen, 1. nummerierte Listen, > Einrückung, \ als Escape.
@MainActor
enum MarkdownRenderer {

    static func render(_ text: String, style: MarkdownStyle, boldAll: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (idx, raw) in lines.enumerated() {
            let line = renderLine(raw, style: style, boldAll: boldAll)
            out.append(line)
            if idx < lines.count - 1 {
                let attrs: [NSAttributedString.Key: Any] = line.length > 0
                    ? line.attributes(at: line.length - 1, effectiveRange: nil)
                    : baseAttributes(style, paragraph: paragraphStyle(style))
                out.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }
        return out
    }

    /// Entfernt Markdown-Zeichen (für Titel, Rücksendeangabe, Dateinamen).
    nonisolated static func plain(_ s: String) -> String {
        var r = s.replacingOccurrences(of: #"(?m)^\s*#{1,6}\s+"#, with: "", options: .regularExpression)
        r = r.replacingOccurrences(of: #"(\*\*|__|\*|`|\\)"#, with: "", options: .regularExpression)
        return r
    }

    // MARK: - Zeilen

    private static func renderLine(_ line: String, style: MarkdownStyle, boldAll: Bool) -> NSAttributedString {
        let hang = style.font.pointSize * 1.6
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let level = leading.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
        let content = String(line.dropFirst(leading.count))

        // Überschrift -> fett, gleiche Größe (Brief, kein Dokument)
        if let m = content.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            return inline(String(content[m.upperBound...]), style: style,
                          paragraph: paragraphStyle(style), bold: true)
        }
        // Aufzählung
        if let m = content.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
            let ps = paragraphStyle(style, indent: CGFloat(level) * hang, hanging: hang)
            let r = NSMutableAttributedString(string: "•\t", attributes: baseAttributes(style, paragraph: ps, bold: boldAll))
            r.append(inline(String(content[m.upperBound...]), style: style, paragraph: ps, bold: boldAll))
            return r
        }
        // Nummerierte Liste
        if let m = content.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) {
            let number = content[m].trimmingCharacters(in: .whitespaces)
            let ps = paragraphStyle(style, indent: CGFloat(level) * hang, hanging: hang)
            let r = NSMutableAttributedString(string: "\(number)\t", attributes: baseAttributes(style, paragraph: ps, bold: boldAll))
            r.append(inline(String(content[m.upperBound...]), style: style, paragraph: ps, bold: boldAll))
            return r
        }
        // Zitat / Einrückung
        if let m = content.range(of: #"^>\s?"#, options: .regularExpression) {
            let ps = paragraphStyle(style, indent: hang, hanging: 0)
            return inline(String(content[m.upperBound...]), style: style, paragraph: ps, bold: boldAll)
        }
        return inline(line, style: style, paragraph: paragraphStyle(style), bold: boldAll)
    }

    // MARK: - Inline-Formatierung

    private static func inline(_ text: String, style: MarkdownStyle, paragraph: NSParagraphStyle,
                               bold forceBold: Bool = false) -> NSAttributedString {
        let chars = Array(text)
        let out = NSMutableAttributedString()
        var bold = false, italic = false, code = false
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            out.append(NSAttributedString(string: buffer, attributes: [
                .font: font(style.font, bold: bold || forceBold, italic: italic, code: code),
                .paragraphStyle: paragraph
            ]))
            buffer = ""
        }
        func hasClosing(_ marker: [Character], from start: Int) -> Bool {
            guard start < chars.count else { return false }
            var j = start
            while j + marker.count <= chars.count {
                if Array(chars[j..<(j + marker.count)]) == marker { return j > start }
                j += 1
            }
            return false
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, !code {
                buffer.append(chars[i + 1]); i += 2; continue
            }
            if code {
                if c == "`" { flush(); code = false } else { buffer.append(c) }
                i += 1; continue
            }
            if c == "`", hasClosing(["`"], from: i + 1) {
                flush(); code = true; i += 1; continue
            }
            if c == "*" || c == "_" {
                // fett
                if i + 1 < chars.count, chars[i + 1] == c {
                    if bold || hasClosing([c, c], from: i + 2) {
                        flush(); bold.toggle(); i += 2; continue
                    }
                }
                // kursiv ("_" nur an Wortgrenzen, damit snake_case nicht kippt)
                if c == "_", !italic, i > 0, chars[i - 1].isLetter || chars[i - 1].isNumber {
                    buffer.append(c); i += 1; continue
                }
                if italic || hasClosing([c], from: i + 1) {
                    flush(); italic.toggle(); i += 1; continue
                }
            }
            buffer.append(c)
            i += 1
        }
        flush()
        if out.length == 0 {
            // leere Zeile: trotzdem Absatzformat mitgeben
            return NSAttributedString(string: "", attributes: baseAttributes(style, paragraph: paragraph))
        }
        return out
    }

    // MARK: - Hilfen

    static func paragraphStyle(_ style: MarkdownStyle, indent: CGFloat = 0, hanging: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = style.alignment
        p.minimumLineHeight = style.lineHeight
        p.maximumLineHeight = style.lineHeight
        p.lineBreakMode = .byWordWrapping
        p.firstLineHeadIndent = indent
        p.headIndent = indent + hanging
        if hanging > 0 {
            p.tabStops = [NSTextTab(textAlignment: .left, location: indent + hanging)]
            p.defaultTabInterval = hanging
        }
        return p
    }

    static func baseAttributes(_ style: MarkdownStyle, paragraph: NSParagraphStyle, bold: Bool = false) -> [NSAttributedString.Key: Any] {
        [.font: font(style.font, bold: bold, italic: false, code: false), .paragraphStyle: paragraph]
    }

    static func font(_ base: NSFont, bold: Bool, italic: Bool, code: Bool) -> NSFont {
        if code {
            return NSFont.monospacedSystemFont(ofSize: base.pointSize * 0.95, weight: bold ? .bold : .regular)
        }
        var f = base
        let fm = NSFontManager.shared
        if bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
        if italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }
}
