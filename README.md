# metaLetter

Schlanke Mac-App für Briefe nach **DIN 5008 (Form B)** auf DIN A4 – mit Live-Vorschau, PDF-Export und Direktdruck.

## Bauen
Voraussetzung: macOS 14+, Xcode oder Command Line Tools (`xcode-select --install`).

```bash
cd metaLetter
./build.sh
mv build/metaLetter.app /Applications/
```
Alternativ `Package.swift` in Xcode öffnen und starten.

## Bedienung
- **Einstellungen (⌘,)**: Ablage-Ordner, Standard-Absender, Ort, Schrift (10–14 pt), Rücksendeangabe, Falz-/Lochmarken.
- **⌘N** neuer Brief · **⌘S** sichern · **⌘D** duplizieren (Datum wird auf heute gesetzt) · **⌘E** PDF · **⌘P** drucken
- Seitenleiste: alle Briefe im Ablage-Ordner, Suche, Rechtsklick → Duplizieren / Im Finder / Papierkorb.
- Beim Wechsel des Briefs und beim Beenden wird automatisch gesichert.

## Markdown
`**fett**`, `*kursiv*`, `` `code` ``, `- Liste`, `1. Aufzählung`, `> Einzug`, `# Zeile fett`.
Zeilenumbrüche bleiben so, wie du sie tippst; eine Leerzeile = Absatz.
Auch Absender, Empfänger und Betreff dürfen Markdown enthalten (z. B. `**Kai Kranz**`).

## Layout (DIN 5008, Form B)
| Element | Position |
|---|---|
| Absender (Briefkopf) | oben rechts, bis 45 mm |
| Rücksendeangabe | automatisch aus dem Absender, über der Anschrift |
| Anschrift | ab 62,7 mm, x = 25 mm, max. 6 Zeilen |
| Ort, Datum | Informationsblock, x = 125 mm, ab 50 mm |
| Betreff | fett, ab 98,46 mm |
| Text | 2 Leerzeilen nach Betreff, Ränder 25 / 20 mm |
| Folgeseiten | „Seite x von y“ unten rechts |
| Marken | Falz 105 / 210 mm, Loch 148,5 mm |

## Mit Xcode bauen, signieren und notarisieren
Einmalig:
```bash
cp Xcode/Local.xcconfig.example Xcode/Local.xcconfig   # Team-ID eintragen
```
Projekt erzeugen und öffnen (nach jeder Änderung an `project.yml` oder neuen Dateien erneut):
```bash
xcodegen && open metaLetter.xcodeproj
```
Veröffentlichen: **Product → Archive** → **Distribute App** → **Direct Distribution**.
Xcode signiert mit „Developer ID Application“, notarisiert und heftet das Ticket an.
Danach im Organizer **Export**, um die fertige `metaLetter.app` zu erhalten.

Versionsnummer: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`.

## Automatische Releases (signiert & notarisiert)
Die GitHub Action `.github/workflows/release.yml` baut die App auf einem Mac-Runner, signiert sie mit Developer ID,
notarisiert sie und hängt `metaLetter-<Version>.zip` an ein GitHub-Release.

**Starten:** GitHub → *Actions* → *Release* → *Run workflow* → Versionsnummer eingeben.
(Alternativ einen Tag pushen: `git tag v1.0.1 && git push origin v1.0.1`.)

**Einmalig benötigte Secrets** (Settings → Secrets and variables → Actions):

| Secret | Inhalt |
|---|---|
| `DEVELOPER_ID_CERT_P12` | Developer-ID-Zertifikat als .p12, base64-kodiert (`base64 -i cert.p12 | pbcopy`) |
| `DEVELOPER_ID_CERT_PASSWORD` | Passwort, das beim Export der .p12 vergeben wurde |
| `TEAM_ID` | Team-ID (10 Zeichen) |
| `APPLE_ID` | Apple-ID des Developer Accounts |
| `APPLE_APP_PASSWORD` | App-spezifisches Passwort von appleid.apple.com |

## Dateiformat
Jeder Brief ist eine `.letter`-Datei (lesbares JSON) im Ablage-Ordner.

## Lizenz
[MIT](LICENSE) © 2026 Kai Kranz
