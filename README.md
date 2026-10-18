# Datenblick für iOS

Native, deutschsprachige SwiftUI-App für einen Telekom-Anschluss mit echter WidgetKit-Erweiterung. Ab iOS 17, auch für iPad. Eigenständiges Projekt, kein offizielles Telekom-Produkt.

**Lieferstand am 18.10.2026:** App und Widget wurden auf einem GitHub-Cloud-Mac mit Xcode 16.4 erfolgreich für ein echtes iPhone gebaut. Alle 53 Swift-Kerntests und die Prüfung der erzeugten IPA-Datei sind bestanden. [Erfolgreicher Build und Download](https://github.com/juergenzahnde-sudo/datenblick-ios1/actions/runs/39113125497). Die IPA ist noch nicht für ein persönliches Apple-Konto provisioniert; Installation, Bedienung und Telekom-Abruf auf einem iPhone sind noch nicht geprüft. Ein Simulatorlauf wurde nicht ausgeführt.

**Windows und 0-€-Budget:** Der Weg verwendet einen öffentlichen GitHub-Cloud-Build und AltStore Classic mit kostenloser persönlicher Apple-Signierung. App und Widget bleiben eigenständig. Die Signierung muss spätestens alle sieben Tage erneuert werden. Die vollständige Einrichtung steht in [WINDOWS-KOSTENLOS.md](WINDOWS-KOSTENLOS.md). Dafür ist kein TestFlight-Zugang erforderlich; nach dem erfolgreichen Cloud-Build steht jetzt die Installation auf deinem iPhone an.

## Enthaltene Funktionen

- Übersicht mit Restvolumen, verbrauchtem Volumen und Abrechnungsende, soweit der Anbieter es liefert.
- Tagesbudget aus Restvolumen und verbleibenden Tagen. Das ist eine Einteilung, keine Verbrauchsprognose.
- Verlauf tatsächlich gespeicherter Abfragen; bis zu 90 Einträge je Datenquelle. Der Verlauf wird durch die App geschrieben, Widgets aktualisieren nur den letzten Abruf.
- Kleine und mittlere Home-Bildschirm-Widgets sowie kreisförmige und rechteckige Sperrbildschirm-Widgets.
- Aktualisieren durch Öffnen, Herunterziehen oder Antippen des Widgets.
- Optionale lokale Verbrauchswarnung mit wählbarer Schwelle. Die Prüfung erfolgt bei Aktualisierungen in der App, nicht als permanente Hintergrundüberwachung.
- Getrennte Modi für Telekom, manuelle Einträge und ausdrücklich gekennzeichnete Demodaten. Ein fehlgeschlagener Live-Abruf erzeugt keine Beispielwerte.
- Manuelle Tarifgröße, Verbrauch, Tarifname und Abrechnungstag; lokale Speicherung über eine gemeinsame App-Gruppe.
- Helles/dunkles Erscheinungsbild, Dynamic Type und VoiceOver-Beschriftungen.
- Löschen der gespeicherten App-Daten in den Einstellungen. Keine Analytics, Werbung, Konten oder eigenen Server.

## Auf dem iPhone installieren

1. Den gesamten Projektordner auf einen Mac übertragen und `Datenblick.xcodeproj` in einer aktuellen Xcode-Version öffnen. Die Datei `Package.swift` allein öffnet nur die Kerntests.
2. In `Config/Project.xcconfig` `BASE_BUNDLE_IDENTIFIER` auf eine für dich eindeutige Kennung ändern, beispielsweise `de.deinname.datenblick`. `APP_GROUP_IDENTIFIER` leitet sich daraus ab und gilt für beide Targets.
3. Für **Datenblick** und **DatenblickWidget** unter **Signing & Capabilities** dasselbe Team auswählen. Alternativ `DEVELOPMENT_TEAM` in der Konfiguration eintragen. Automatische Signierung ist aktiviert. In beiden Targets muss dieselbe App-Gruppe registriert und in den Profilen enthalten sein. Xcode zeigt an, welche Berechtigungen dein Team unterstützt.
4. iPhone mit dem Mac koppeln, bei Bedarf den Entwicklermodus auf dem iPhone einschalten, das iPhone als Ziel wählen und **Run** drücken. Das Widget wird zusammen mit der App installiert.
5. Die App mindestens einmal öffnen, eine Datenquelle einrichten und einen Abruf beziehungsweise manuellen Eintrag speichern. Anschließend auf dem Home-Bildschirm die Widget-Auswahl öffnen und **Datenblick** hinzufügen. Auf dem Sperrbildschirm über **Anpassen → Widgets** auswählen.

Ein kostenloses Personal Team kann grundsätzlich Apps auf eigenen Geräten testen; seine Profile laufen nach sieben Tagen ab. Berechtigungen sind vom Team abhängig. Für Verteilung über TestFlight oder den App Store ist die Teilnahme am Apple Developer Program erforderlich. Ein ZIP mit Quellcode lässt sich auf dem iPhone nicht direkt als App installieren. Ein Mac-Build kann auch über eine entsprechend konfigurierte macOS-CI erstellt werden; für eine installierbare App werden weiterhin deine Signierung und Provisionierungsprofile benötigt.

## Telekom-Abfrage: experimentell

Die App verwendet ausschließlich HTTPS zu `pass.telekom.de`:

1. Den aus bestehenden Integrationen bekannten JSON-Pfad `/api/service/generic/v1/status`.
2. Wenn dieser nicht nutzbar ist, den HTML-Pfad `/home` mit einem streng validierenden, experimentellen Parser.

**Es wurde keine dokumentierte, offiziell unterstützte öffentliche Verbrauchs-API gefunden.** Die tatsächlichen Antworten deines Anschlusses konnten hier nicht getestet werden. Das JSON-Format ist ein älteres, undokumentiertes Format. Die HTML-Erkennung beruht auf öffentlich veröffentlichten Beobachtungen einer Drittintegration; ihre Testbeispiele sind künstliche Fixtures, keine erfassten Telekom-Kontodaten. Ändert die Telekom das Layout oder lädt die Werte nur per JavaScript, schlägt die Erkennung nachvollziehbar fehl. Unbekannte Einheiten, Anmeldeseiten und mehrdeutige Datentöpfe ersetzen keine gültigen Werte. Unlimited wird nur bei einem expliziten JSON-Merkmal erkannt; der HTML-Adapter rät es nicht.

Für einen echten Versuch mobile Daten über die Telekom-SIM verwenden und WLAN ausschalten. Bei Dual-SIM bestimmt die für mobile Daten gewählte SIM den Anschluss. VPN und Private Relay können die Telekom-Erkennung beeinflussen; beachte die Telekom-Hilfe für eine gegebenenfalls vorübergehende Änderung. Ein Browser-Login über den offiziellen SMS-Zugang wird nicht automatisch in die App oder das Widget übernommen: Safari und die App-Netzwerkanfragen teilen ihre Sitzung nicht. Der Link zur Telekom-Seite ist eine Hilfestellung und keine Anmeldung der App.

Die Bezeichnung **Abruf** meint den Zeitpunkt, zu dem die App erfolgreich Daten empfangen hat. Die Messung bei der Telekom kann selbst älter sein. Bei einem Fehler bleiben die zuletzt gespeicherten Werte sichtbar; ältere Abrufe werden markiert. Der manuelle Modus ist ein Eingabewerkzeug und zählt keinen Datenverkehr. Das Projekt misst auch keinen Verbrauch einzelner anderer Apps.

WidgetKit bestimmt, wann Hintergrundaktualisierungen laufen. Die Erweiterung bittet um einen weiteren Abruf nach 30 Minuten; das ist keine Zusage für diesen Zeitpunkt. Über WLAN oder ohne Netzerkennung kann der letzte gespeicherte Wert bestehen bleiben. Benötigst du einen gezielten Abruf, öffne die App im Telekom-Mobilfunknetz. App-Gruppe und Datenquelle gelten gemeinsam für alle Datenblick-Widgets.

## Bauen und prüfen

Keine externen Swift-Abhängigkeiten, kein Paketmanager für die iOS-App erforderlich. Auf einem Mac:

```sh
swift test
xcodebuild -project Datenblick.xcodeproj -scheme Datenblick \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Die Swift-Package-Tests prüfen Decoder, Einheiten, ungültige Antworten, Speichertrennung und Berechnungen. Sie sind separat vom App-Scheme auszuführen. Der Workflow `.github/workflows/ios.yml` führt diese Tests und einen Simulator-Build auf einem macOS-Runner aus. Er wird manuell gestartet und läuft nur in öffentlichen Repositories; dieser separate Simulator-Workflow wurde noch nicht ausgeführt. `.github/workflows/free-ipa.yml` baut eine iPhone-App mit Widget und paketiert sie für die persönliche Neusignierung unter Windows. Er startet beim Hochladen geänderter App-, Test-, Projekt- oder Build-Dateien auf `main` sowie manuell über **Actions → Free iPhone IPA → Run workflow**. Änderungen nur an der Dokumentation starten keinen Build. **Der iPhone-Workflow wurde am 18.10.2026 erfolgreich ausgeführt.** Die Download-Artefakte werden einen Tag aufbewahrt; spätere Downloads benötigen gegebenenfalls einen neuen manuellen Lauf.

Projektdateien und Icon sind bereits generiert. Falls Swift-Dateien hinzukommen, auf Windows oder macOS mit Node.js erneut ausführen:

```sh
node scripts/generate-project.mjs
node scripts/generate-icon.mjs
node scripts/verify-project.mjs
```

Der native Gerätebuild ist geprüft. Vor einer Weitergabe muss die Bedienung auf einem echten Gerät geprüft werden, insbesondere Telekom-Abfrage, Einheiten, Cache bei WLAN, Quellenwechsel, App-Gruppe, Widget-Galerie, große Schrift und Warnberechtigung. Zwei Prozesse teilen den Cache über UserDefaults; Snapshot und Verlauf sind keine gemeinsame Datenbanktransaktion. Die App schreibt den Verlauf, die Widget-Erweiterung nur den Snapshot. Das vermeidet konkurrierende Verlaufsschreiber, ersetzt jedoch keine transaktionale Datenbank.

Bei persönlicher Neusignierung mit AltStore Classic können App-Group-Kennungen um die Team-ID ergänzt werden. `AppGroupResolver` liest dafür ausschließlich die eigenen Provisionierungs-/Bundle-Metadaten, akzeptiert die konfigurierte Gruppe oder ihre eindeutig passende AltStore-Teamvariante und verwendet keine privaten APIs. Der Parser validiert keine CMS-Signatur; die Berechtigung für den gewählten Container erzwingt iOS anhand der tatsächlichen Signatur.

## Sinnvolle Erweiterungen

- **Monatsprognose:** aus ausreichend vielen echten Abfragen abschätzen, ob das Restvolumen reicht; erst bei brauchbarer Datenbasis anzeigen.
- **Roamingbudget:** getrenntes, zunächst manuell gepflegtes Reisebudget und Warnschwelle.
- **Mehrere Tarifprofile:** eigene Einstellungen und Widgets je Anschluss; automatische Erkennung bleibt von der aktiven Daten-SIM abhängig und benötigt zusätzliche Konzeption.
- **Siri und Kurzbefehle:** den zuletzt gespeicherten Verbrauch abfragen und einen Abruf über die App starten.
- **Apple Watch:** kompakte Restvolumenanzeige; dafür wären ein Watch-Target und eine Datensynchronisation zu ergänzen.

## Aufbau

| Pfad | Inhalt |
| --- | --- |
| `App/` | SwiftUI-Oberfläche, Zustandsverwaltung, lokale Warnungen |
| `Widgets/` | WidgetKit-Timeline und vier Widget-Formate |
| `Shared/` | Modelle, Telekom-Adapter, Validierung, App-Group-Speicher |
| `Tests/` | Foundation-basierte Swift-Package-Tests |
| `Config/` | Bundle-IDs, Info.plists, Entitlements, Privacy Manifest |
| `Datenblick.xcodeproj/` | eingechecktes Xcode-Projekt und gemeinsames Scheme |
| `scripts/` | reproduzierbare Projekt- und Icon-Erzeugung |

## Quellen

Geprüft am 17.10.2026:

- [Telekom: Datennutzung und Netz-/SMS-Zugang](https://pass.telekom.de/?lang=de_DE_TMDE)
- [Telekom: Warum öffnet sich pass.telekom.de nicht?](https://www.telekom.de/hilfe/mobilfunk/mobiles-internet/datenvolumen-seite-oeffnen)
- [Veröffentlichte Drittintegration: HTML-Klassennamen und Beobachtungen](https://www.reddit.com/r/Scriptable/comments/1wn9xwa/german_small_widget_for_telekom_mobile_data_usage/) – technische Beobachtung des Autors, kein API-Vertrag der Telekom
- [Ältere Drittintegration: JSON-Statuspfad](https://gist.github.com/Sillium/235dc9fd873b25e321b3299da64c9c38)
- [Apple: App auf Simulator oder Gerät ausführen](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Apple: Developer-Account und Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Apple: App-Gruppen konfigurieren](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple: Widget-Erweiterung erstellen](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Apple: Aktualität und Aktualisierungsbudgets von Widgets](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

