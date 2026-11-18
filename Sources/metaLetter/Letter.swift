import Foundation
import CoreGraphics

/// Ein Brief. Alle Textfelder dürfen einfaches Markdown enthalten.
struct Letter: Codable, Equatable {
    var sender: String = ""
    var recipient: String = ""
    var placeDate: String = ""
    var subject: String = ""
    var body: String = ""

    init() {}

    // Tolerantes Laden: fehlende Felder führen nicht zu einem Fehler.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sender = try c.decodeIfPresent(String.self, forKey: .sender) ?? ""
        recipient = try c.decodeIfPresent(String.self, forKey: .recipient) ?? ""
        placeDate = try c.decodeIfPresent(String.self, forKey: .placeDate) ?? ""
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
    }
}

/// Schlüssel für die Einstellungen (UserDefaults / @AppStorage).
enum Prefs {
    static let folderPath = "folderPath"
    static let defaultSender = "defaultSender"
    static let defaultPlace = "defaultPlace"
    static let fontName = "fontName"
    static let fontSize = "fontSize"
    static let showReturnLine = "showReturnLine"
    static let showMarks = "showMarks"

    static func register() {
        UserDefaults.standard.register(defaults: [
            fontName: "Helvetica",
            fontSize: 11.0,
            showReturnLine: true,
            showMarks: true,
            defaultPlace: "",
            defaultSender: "",
            folderPath: ""
        ])
    }
}

/// Gestaltungsoptionen für die PDF-Erzeugung.
struct RenderOptions {
    var fontName: String
    var fontSize: CGFloat
    var showReturnLine: Bool
    var showMarks: Bool

    static var current: RenderOptions {
        let d = UserDefaults.standard
        let size = d.double(forKey: Prefs.fontSize)
        return RenderOptions(
            fontName: d.string(forKey: Prefs.fontName) ?? "Helvetica",
            fontSize: CGFloat(size > 0 ? size : 11),
            showReturnLine: d.bool(forKey: Prefs.showReturnLine),
            showMarks: d.bool(forKey: Prefs.showMarks)
        )
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { trimmed.isEmpty ? nil : self }
}
