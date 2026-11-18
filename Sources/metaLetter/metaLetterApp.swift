import SwiftUI

@main
struct MetaLetterApp: App {
    @StateObject private var store = LetterStore()

    var body: some Scene {
        Window("metaLetter", id: "main") {
            ContentView()
                .environmentObject(store)
                .tint(.plum)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .commands { LetterCommands(store: store) }

        Settings {
            SettingsView()
                .environmentObject(store)
                .tint(.plum)
        }
    }
}

struct LetterCommands: Commands {
    @ObservedObject var store: LetterStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Neuer Brief") { store.newLetter() }
                .keyboardShortcut("n")
            Button("Duplizieren") { store.duplicate() }
                .keyboardShortcut("d")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Sichern") { _ = store.save() }
                .keyboardShortcut("s")
            Button("Als PDF exportieren …") { store.exportPDF() }
                .keyboardShortcut("e")
        }
        CommandGroup(replacing: .printItem) {
            Button("Drucken …") { store.printLetter() }
                .keyboardShortcut("p")
        }
    }
}

extension Color {
    /// Hausfarbe (Pflaume)
    static let plum = Color(red: 0x6E / 255, green: 0x3B / 255, blue: 0x5C / 255)
}
