import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct LetterFile: Identifiable, Hashable {
    let url: URL
    let title: String
    let subtitle: String
    let modified: Date
    var id: URL { url }
}

@MainActor
final class LetterStore: ObservableObject {
    static let fileExtension = "letter"

    @Published var letter: Letter
    @Published private(set) var savedLetter: Letter
    @Published private(set) var currentURL: URL?
    @Published private(set) var files: [LetterFile] = []
    @Published var errorMessage: String?

    private var lastFolderPath: String?
    private var observers: [NSObjectProtocol] = []

    var isDirty: Bool { letter != savedLetter }

    var folderURL: URL? {
        guard let p = UserDefaults.standard.string(forKey: Prefs.folderPath), !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p, isDirectory: true)
    }

    var windowTitle: String {
        currentURL?.deletingPathExtension().lastPathComponent ?? "Neuer Brief"
    }

    init() {
        Prefs.register()
        let l = LetterStore.makeNewLetter()
        letter = l
        savedLetter = l
        lastFolderPath = UserDefaults.standard.string(forKey: Prefs.folderPath)
        refresh()

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.folderMaybeChanged() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.saveIfNeeded() }
        })
    }

    // MARK: - Neu / Öffnen / Sichern

    static func makeNewLetter() -> Letter {
        var l = Letter()
        let d = UserDefaults.standard
        l.sender = d.string(forKey: Prefs.defaultSender) ?? ""
        l.placeDate = placeDate(place: d.string(forKey: Prefs.defaultPlace) ?? "")
        return l
    }

    static func placeDate(place: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMMM yyyy"
        let date = f.string(from: Date())
        let p = place.trimmed
        return p.isEmpty ? date : "\(p), \(date)"
    }

    func setToday() {
        let current = letter.placeDate
        let place = current.contains(",")
            ? String(current.split(separator: ",", maxSplits: 1).first ?? "")
            : (UserDefaults.standard.string(forKey: Prefs.defaultPlace) ?? "")
        letter.placeDate = Self.placeDate(place: place)
    }

    func newLetter() {
        guard saveIfNeeded() else { return }
        let l = Self.makeNewLetter()
        letter = l
        savedLetter = l
        currentURL = nil
    }

    func open(_ url: URL) {
        guard url != currentURL else { return }
        guard saveIfNeeded() else { return }
        do {
            let l = try JSONDecoder().decode(Letter.self, from: Data(contentsOf: url))
            letter = l
            savedLetter = l
            currentURL = url
        } catch {
            errorMessage = "Der Brief konnte nicht geöffnet werden.\n\(error.localizedDescription)"
        }
    }

    /// Dupliziert einen Brief (z. B. als Vorlage); Datum wird auf heute gesetzt.
    func duplicate(_ url: URL? = nil) {
        var copy = letter
        if let url {
            guard saveIfNeeded() else { return }
            guard let l = try? JSONDecoder().decode(Letter.self, from: Data(contentsOf: url)) else { return }
            copy = l
        } else {
            guard saveIfNeeded() else { return }
        }
        letter = copy
        setToday()
        savedLetter = Letter()   // gilt als ungesichert
        currentURL = nil
    }

    @discardableResult
    func saveIfNeeded() -> Bool {
        isDirty ? save() : true
    }

    @discardableResult
    func save() -> Bool {
        guard let folder = folderURL else {
            errorMessage = "Bitte lege zuerst in den Einstellungen (⌘,) einen Ablage-Ordner fest."
            return false
        }
        let url = currentURL ?? uniqueURL(in: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try enc.encode(letter).write(to: url, options: .atomic)
            savedLetter = letter
            currentURL = url
            refresh()
            return true
        } catch {
            errorMessage = "Speichern fehlgeschlagen.\n\(error.localizedDescription)"
            return false
        }
    }

    func delete(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            if url == currentURL {
                let l = Self.makeNewLetter()
                letter = l
                savedLetter = l
                currentURL = nil
            }
            refresh()
        } catch {
            errorMessage = "Löschen fehlgeschlagen.\n\(error.localizedDescription)"
        }
    }

    // MARK: - PDF & Druck

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.directoryURL = folderURL
        panel.nameFieldStringValue = (currentURL?.deletingPathExtension().lastPathComponent ?? baseName()) + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DIN5008.pdf(for: letter).write(to: url, options: .atomic)
        } catch {
            errorMessage = "PDF konnte nicht gesichert werden.\n\(error.localizedDescription)"
        }
    }

    func printLetter() {
        guard let doc = PDFDocument(data: DIN5008.pdf(for: letter)) else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = DIN5008.pageSize
        info.orientation = .portrait
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        guard let op = doc.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else { return }
        op.jobTitle = windowTitle
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }

    // MARK: - Ordner

    func refresh() {
        guard let folder = folderURL else { files = []; return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let decoder = JSONDecoder()
        files = urls
            .filter { $0.pathExtension.lowercased() == Self.fileExtension }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let l = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Letter.self, from: $0) }
                let title = l.flatMap { MarkdownRenderer.plain($0.subject).nonEmpty?.trimmed }
                    ?? url.deletingPathExtension().lastPathComponent
                let recipient = MarkdownRenderer.plain(l?.recipient ?? "")
                    .components(separatedBy: .newlines).map { $0.trimmed }.first { !$0.isEmpty } ?? ""
                let subtitle = [recipient, l?.placeDate.trimmed ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                return LetterFile(url: url, title: title, subtitle: subtitle, modified: modified)
            }
            .sorted { $0.modified > $1.modified }
    }

    private func folderMaybeChanged() {
        let p = UserDefaults.standard.string(forKey: Prefs.folderPath)
        guard p != lastFolderPath else { return }
        lastFolderPath = p
        refresh()
    }

    func revealFolder() {
        guard let folder = folderURL else { return }
        NSWorkspace.shared.open(folder)
    }

    private func baseName() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let date = df.string(from: Date())
        var subject = MarkdownRenderer.plain(letter.subject)
            .components(separatedBy: .newlines).joined(separator: " ").trimmed
        subject = subject.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
        if subject.count > 60 { subject = String(subject.prefix(60)).trimmed }
        return subject.isEmpty ? "\(date) Brief" : "\(date) \(subject)"
    }

    private func uniqueURL(in folder: URL) -> URL {
        let base = baseName()
        var url = folder.appendingPathComponent(base).appendingPathExtension(Self.fileExtension)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(Self.fileExtension)
            n += 1
        }
        return url
    }
}
