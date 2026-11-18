import SwiftUI
import AppKit
import PDFKit

// MARK: - Hauptfenster

struct ContentView: View {
    @EnvironmentObject var store: LetterStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 380)
        } detail: {
            DetailView()
        }
        .navigationTitle(store.windowTitle)
        .navigationSubtitle(store.isDirty ? "Nicht gesichert" : "")
        .alert("Hinweis",
               isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

// MARK: - Seitenleiste

struct SidebarView: View {
    @EnvironmentObject var store: LetterStore
    @AppStorage(Prefs.folderPath) private var folderPath = ""
    @State private var search = ""

    private var filtered: [LetterFile] {
        guard !search.isEmpty else { return store.files }
        return store.files.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List(selection: Binding(get: { store.currentURL },
                                set: { if let url = $0 { store.open(url) } })) {
            ForEach(filtered) { file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title).lineLimit(1)
                    if !file.subtitle.isEmpty {
                        Text(file.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .tag(file.url)
                .contextMenu {
                    Button("Duplizieren") { store.duplicate(file.url) }
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                    Divider()
                    Button("In den Papierkorb legen", role: .destructive) { store.delete(file.url) }
                }
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Briefe durchsuchen")
        .overlay {
            if folderPath.isEmpty {
                ContentUnavailableView {
                    Label("Kein Ablage-Ordner", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Lege in den Einstellungen fest, wo deine Briefe gespeichert werden.")
                } actions: {
                    SettingsLink { Text("Einstellungen öffnen") }
                }
            } else if store.files.isEmpty {
                ContentUnavailableView("Noch keine Briefe", systemImage: "envelope",
                                       description: Text("Gesicherte Briefe erscheinen hier."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button { store.newLetter() } label: {
                    Label("Neuer Brief", systemImage: "square.and.pencil")
                }
                .help("Neuer Brief (⌘N)")
            }
        }
    }
}

// MARK: - Editor + Vorschau

struct DetailView: View {
    @EnvironmentObject var store: LetterStore
    // Damit die Vorschau auf Änderungen in den Einstellungen reagiert:
    @AppStorage(Prefs.fontName) private var fontName = "Helvetica"
    @AppStorage(Prefs.fontSize) private var fontSize = 11.0
    @AppStorage(Prefs.showReturnLine) private var showReturnLine = true
    @AppStorage(Prefs.showMarks) private var showMarks = true

    var body: some View {
        let options = RenderOptions(fontName: fontName, fontSize: CGFloat(fontSize),
                                    showReturnLine: showReturnLine, showMarks: showMarks)
        HSplitView {
            EditorView()
                .frame(minWidth: 380, idealWidth: 480)
            PDFPreview(data: DIN5008.pdf(for: store.letter, options: options))
                .frame(minWidth: 380)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { _ = store.save() } label: {
                    Label("Sichern", systemImage: "square.and.arrow.down")
                }
                .help("Sichern (⌘S)")
                .disabled(!store.isDirty && store.currentURL != nil)

                Button { store.exportPDF() } label: {
                    Label("Als PDF", systemImage: "doc.richtext")
                }
                .help("Als PDF exportieren (⌘E)")

                Button { store.printLetter() } label: {
                    Label("Drucken", systemImage: "printer")
                }
                .help("Drucken (⌘P)")
            }
        }
    }
}

struct EditorView: View {
    @EnvironmentObject var store: LetterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Field("Absender") { MarkdownEditor(text: $store.letter.sender) }
                Field("Empfänger") { MarkdownEditor(text: $store.letter.recipient) }
            }
            .frame(height: 130)

            HStack(alignment: .bottom, spacing: 8) {
                Field("Ort, Datum") {
                    TextField("", text: $store.letter.placeDate)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Heute") { store.setToday() }
            }

            Field("Betreff") {
                TextField("", text: $store.letter.subject, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
            }

            Field("Brieftext  ·  **fett**  *kursiv*  - Liste  1. Aufzählung  > Einzug") {
                MarkdownEditor(text: $store.letter.body)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
    }
}

struct Field<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct MarkdownEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
    }
}

// MARK: - PDF-Vorschau

struct PDFPreview: NSViewRepresentable {
    let data: Data

    final class Coordinator { var lastData: Data? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .underPageBackgroundColor
        view.document = PDFDocument(data: data)
        context.coordinator.lastData = data
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.lastData != data else { return }
        context.coordinator.lastData = data
        let pageIndex = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        view.document = PDFDocument(data: data)
        if let doc = view.document, doc.pageCount > 0, let page = doc.page(at: min(pageIndex, doc.pageCount - 1)) {
            view.go(to: page)
        }
    }
}

// MARK: - Einstellungen

struct SettingsView: View {
    @EnvironmentObject var store: LetterStore
    @AppStorage(Prefs.folderPath) private var folderPath = ""
    @AppStorage(Prefs.defaultSender) private var defaultSender = ""
    @AppStorage(Prefs.defaultPlace) private var defaultPlace = ""
    @AppStorage(Prefs.fontName) private var fontName = "Helvetica"
    @AppStorage(Prefs.fontSize) private var fontSize = 11.0
    @AppStorage(Prefs.showReturnLine) private var showReturnLine = true
    @AppStorage(Prefs.showMarks) private var showMarks = true

    private var fonts: [String] {
        let wanted = ["Helvetica", "Helvetica Neue", "Arial", "Avenir Next", "Verdana",
                      "Times New Roman", "Georgia", "Palatino"]
        let available = Set(NSFontManager.shared.availableFontFamilies)
        var list = wanted.filter { available.contains($0) }
        if !list.contains(fontName) { list.insert(fontName, at: 0) }
        return list
    }

    var body: some View {
        Form {
            Section("Ablage") {
                LabeledContent("Ordner") {
                    HStack {
                        Text(folderPath.isEmpty ? "Nicht festgelegt"
                                                : (folderPath as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(folderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Auswählen …") { chooseFolder() }
                        if !folderPath.isEmpty {
                            Button { store.revealFolder() } label: { Image(systemName: "folder") }
                                .help("Im Finder öffnen")
                        }
                    }
                }
            }

            Section("Vorgaben für neue Briefe") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Absender (Markdown)")
                    MarkdownEditor(text: $defaultSender)
                        .frame(height: 90)
                }
                TextField("Ort", text: $defaultPlace, prompt: Text("z. B. Friesoythe"))
            }

            Section("Layout (DIN 5008, Form B)") {
                Picker("Schrift", selection: $fontName) {
                    ForEach(fonts, id: \.self) { Text($0).tag($0) }
                }
                Stepper(value: $fontSize, in: 10...14, step: 0.5) {
                    Text("Schriftgröße: \(fontSize.formatted(.number.precision(.fractionLength(0...1)))) pt")
                }
                Toggle("Rücksendeangabe über der Anschrift", isOn: $showReturnLine)
                Toggle("Falz- und Lochmarken", isOn: $showMarks)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 520)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        if !folderPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: folderPath) }
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            store.refresh()
        }
    }
}
