import AppKit
import CoreText

/// Erzeugt ein DIN-A4-PDF nach DIN 5008, Form B.
///
/// Maße (vom oberen/linken Blattrand):
/// - Briefkopf (Absender):         0 – 45 mm
/// - Anschriftfeld:                x 20 mm, y 45 mm, 85 × 45 mm
///   - Rücksendeangabe:            unterer Teil der Zusatz-/Vermerkzone (bis 62,7 mm)
///   - Anschriftzone:              62,7 – 90 mm, Text ab x 25 mm
/// - Informationsblock (Ort, Datum): x 125 mm, ab y 50 mm
/// - Betreff:                      ab 98,46 mm (zwei Leerzeilen nach dem Anschriftfeld), fett
/// - Brieftext:                    zwei Leerzeilen nach dem Betreff
/// - Ränder:                       links 25 mm, rechts 20 mm
/// - Falzmarken 105 / 210 mm, Lochmarke 148,5 mm
@MainActor
enum DIN5008 {
    static let pageSize = CGSize(width: 595.2756, height: 841.8898) // 210 × 297 mm

    static func mm(_ v: CGFloat) -> CGFloat { v * 72.0 / 25.4 }

    static let leftMargin: CGFloat = 25
    static let rightMargin: CGFloat = 20
    static let bottomMargin: CGFloat = 25
    static let followPageTop: CGFloat = 20

    static func font(_ family: String, size: CGFloat) -> NSFont {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? NSFont(name: family, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    static func pdf(for letter: Letter, options: RenderOptions = .current) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var box = CGRect(origin: .zero, size: pageSize)
        let info: [String: Any] = [
            kCGPDFContextTitle as String: letter.subject.trimmed.isEmpty ? "Brief" : MarkdownRenderer.plain(letter.subject),
            kCGPDFContextCreator as String: "metaLetter"
        ]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return Data() }

        let size = options.fontSize
        let lh = size * 1.15
        let style = MarkdownStyle(font: font(options.fontName, size: size), lineHeight: lh)
        let left = mm(leftMargin)
        let width = pageSize.width - left - mm(rightMargin)

        // Betreff
        let subjectTop = mm(98.46)
        let subjectAttr = MarkdownRenderer.render(letter.subject.trimmed, style: style, boldAll: true)
        let subjectHeight = letter.subject.trimmed.isEmpty ? 0 : textHeight(subjectAttr, width: width)
        let bodyTop = subjectHeight > 0 ? subjectTop + subjectHeight + 2 * lh : subjectTop

        // Brieftext seitenweise umbrechen
        let bodyText = letter.body.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        let bodyAttr = MarkdownRenderer.render(bodyText, style: style)
        let framesetter = CTFramesetterCreateWithAttributedString(bodyAttr as CFAttributedString)
        var frames: [CTFrame] = []
        var location = 0
        var pageIndex = 0
        repeat {
            let top = pageIndex == 0 ? bodyTop : mm(followPageTop)
            let height = max(pageSize.height - top - mm(bottomMargin), lh)
            let rect = CGRect(x: left, y: mm(bottomMargin), width: width, height: height)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0),
                                                 CGPath(rect: rect, transform: nil), nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            frames.append(frame)
            if visible.length == 0 {
                if pageIndex == 0 && bodyAttr.length > 0 { pageIndex += 1; continue }
                break
            }
            location += visible.length
            pageIndex += 1
        } while location < bodyAttr.length && pageIndex < 200

        let pageCount = frames.count
        for (i, frame) in frames.enumerated() {
            ctx.beginPDFPage(nil)
            ctx.textMatrix = .identity
            if i == 0 {
                drawFirstPage(ctx, letter: letter, options: options, style: style,
                              subject: subjectAttr, subjectTop: subjectTop, subjectHeight: subjectHeight)
            }
            CTFrameDraw(frame, ctx)
            if pageCount > 1 {
                let footStyle = MarkdownStyle(font: font(options.fontName, size: 8), lineHeight: 10, alignment: .right)
                let foot = MarkdownRenderer.render("Seite \(i + 1) von \(pageCount)", style: footStyle)
                draw(foot, in: ctx, x: left, top: pageSize.height - mm(15), width: width, height: 12)
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    // MARK: - Erste Seite

    private static func drawFirstPage(_ ctx: CGContext, letter: Letter, options: RenderOptions, style: MarkdownStyle,
                                      subject: NSAttributedString, subjectTop: CGFloat, subjectHeight: CGFloat) {
        let left = mm(leftMargin)
        let width = pageSize.width - left - mm(rightMargin)

        // Briefkopf: Absender rechtsbündig
        if !letter.sender.trimmed.isEmpty {
            let s = max(options.fontSize - 1.5, 8)
            let headStyle = MarkdownStyle(font: font(options.fontName, size: s), lineHeight: s * 1.2, alignment: .right)
            draw(MarkdownRenderer.render(letter.sender.trimmed, style: headStyle),
                 in: ctx, x: left, top: mm(12), width: width, height: mm(31))
        }

        // Rücksendeangabe (eine Zeile, klein)
        if options.showReturnLine {
            let parts = MarkdownRenderer.plain(letter.sender)
                .components(separatedBy: .newlines)
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                let rStyle = MarkdownStyle(font: font(options.fontName, size: 7), lineHeight: 8.5)
                let attr = NSMutableAttributedString(attributedString:
                    MarkdownRenderer.render(parts.joined(separator: " · "), style: rStyle))
                attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                  range: NSRange(location: 0, length: attr.length))
                draw(attr, in: ctx, x: left, top: mm(58.2), width: mm(80), height: mm(4.5))
            }
        }

        // Anschriftzone
        draw(MarkdownRenderer.render(letter.recipient.trimmed, style: style),
             in: ctx, x: left, top: mm(62.7), width: mm(80), height: mm(27.3))

        // Informationsblock: Ort, Datum
        if !letter.placeDate.trimmed.isEmpty {
            draw(MarkdownRenderer.render(letter.placeDate.trimmed, style: style),
                 in: ctx, x: mm(125), top: mm(50), width: pageSize.width - mm(125) - mm(rightMargin), height: mm(12))
        }

        // Betreff
        if subjectHeight > 0 {
            draw(subject, in: ctx, x: left, top: subjectTop, width: width, height: subjectHeight + 2)
        }

        // Falz- und Lochmarken
        if options.showMarks {
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
            ctx.setLineWidth(0.4)
            for (y, length) in [(CGFloat(105), CGFloat(5)), (148.5, 8), (210, 5)] {
                let yy = pageSize.height - mm(y)
                ctx.move(to: CGPoint(x: mm(4), y: yy))
                ctx.addLine(to: CGPoint(x: mm(4 + length), y: yy))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: - Hilfen

    /// Zeichnet Text in ein Rechteck, das vom oberen Blattrand aus angegeben wird.
    static func draw(_ attr: NSAttributedString, in ctx: CGContext, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) {
        guard attr.length > 0 else { return }
        let rect = CGRect(x: x, y: pageSize.height - top - height, width: width, height: height)
        let fs = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, ctx)
    }

    static func textHeight(_ attr: NSAttributedString, width: CGFloat) -> CGFloat {
        guard attr.length > 0 else { return 0 }
        let fs = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            fs, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(size.height)
    }
}
