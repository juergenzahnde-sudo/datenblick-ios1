# Datenblick kostenlos mit Windows installieren

Du behältst eine eigenständige iOS-App mit Widget. Ein öffentlicher GitHub-Cloud-Mac erzeugt die App-Datei; AltStore Classic auf Windows signiert und installiert sie mit deinem kostenlosen Apple-Konto. Du brauchst keinen eigenen Mac und kein kostenpflichtiges Developer-Abonnement. **Dieser Weg ist vorbereitet, aber auf deinem iPhone noch nicht getestet.**

Der Aufwand: kostenlose Konten, einmalige Einrichtung auf Windows und eine Erneuerung der Signierung spätestens alle sieben Tage. Die Erneuerung benötigt keinen neuen Cloud-Build, solange sich der App-Code nicht ändert.

Die App selbst benötigt mindestens iOS 17; zusätzlich muss dein iPhone die aktuelle AltStore-Classic-Version unterstützen. Die jeweils geltende Anforderung steht in der offiziellen AltStore-Anleitung beziehungsweise den Release Notes.

## 1. Kostenloses GitHub-Konto erstellen

Öffne [github.com/signup](https://github.com/signup) und erstelle ein **GitHub-Free**-Konto. Für diesen Weg keine Zahlungsdaten hinterlegen und kein kostenpflichtiges Paket buchen. Laut GitHub wird eine ausgeschöpfte Nutzungsquote ohne hinterlegtes Zahlungsmittel blockiert. Standard-Cloud-Runner sind in öffentlichen Repositories kostenlos; Artefaktspeicher hat eigene Freigrenzen. Die vorbereitete Datei wird deshalb nur einen Tag aufbewahrt.

Erstelle danach unter [github.com/new](https://github.com/new) ein Repository namens `datenblick-ios` mit Sichtbarkeit **Public**. Aktiviere die Erstellung einer README, damit das Repository bereits einen ersten Commit hat. Öffentlich bedeutet: Andere können den hochgeladenen Quellcode lesen. Die Projektdateien enthalten keine Telekom-Verbrauchsdaten und keine Apple-Zugangsdaten.

## 2. Projekt im Browser hochladen

Entpacke `Datenblick-iOS.zip` auf Windows. Lade im neuen Repository über **Add file → Upload files** diese Ordner und Dateien aus dem entpackten Projekt hoch:

```text
App/
Assets.xcassets/
Config/
Datenblick.xcodeproj/
Shared/
Tests/
Widgets/
scripts/
Package.swift
README.md
WINDOWS-KOSTENLOS.md
```

Ziehe die ausgewählten Ordner und Dateien gemeinsam auf die Upload-Seite. Wichtig: `Package.swift` und die Ordner müssen direkt im Repository liegen, nicht noch innerhalb eines zusätzlichen Projektordners. Bestätige den Upload mit **Commit changes**. Lade das Projekt-ZIP selbst nicht als Ersatz für die entpackten Dateien hoch.

Der Workflow liegt im Punkt-Ordner `.github`, den einige Browser beim Ordner-Upload überspringen. Lege ihn deshalb zuverlässig über den GitHub-Editor an:

1. **Add file → Create new file** öffnen.
2. Als Dateinamen `.github/workflows/free-ipa.yml` eingeben.
3. Auf Windows die gleichnamige Datei aus dem entpackten Projekt mit dem Editor öffnen und ihren gesamten Inhalt kopieren.
4. In den GitHub-Editor einfügen und mit **Commit changes** speichern.

Alle Schritte funktionieren im Browser; Git oder GitHub Desktop müssen dafür nicht installiert werden.

## 3. App-Datei bauen lassen

Öffne im Repository **Actions** und wähle den Workflow **Free iPhone IPA**. Beim Hochladen geänderter App-, Test-, Projekt- oder Build-Dateien auf `main` startet er automatisch. Weitere Builds kannst du über **Run workflow** starten. Er läuft ausschließlich in einem öffentlichen Repository und benötigt keine Apple-Zugangsdaten, API-Schlüssel oder kostenpflichtigen Cloud-Runner. Änderungen nur an der Dokumentation starten keinen Build.

Der Lauf führt zuerst die Swift-Kerntests aus. Danach baut er App und Widget für ein echtes iPhone. Wenn der Lauf erfolgreich ist, findest du unten unter **Artifacts** das Paket **Datenblick-free-sideload**. Lade es herunter und entpacke das Download-ZIP. Darin liegt `Datenblick-unsigned.ipa`.

Die Datei heißt „unsigned“, weil sie noch nicht für dein Apple-Konto provisioniert ist. Technisch enthält sie eine lokale Ad-hoc-Signatur, damit AltStore die benötigte gemeinsame App-Gruppe erkennen kann. Sie wird im nächsten Schritt durch deine persönliche Signierung ersetzt. Die Datei lässt sich vor diesem Schritt nicht direkt auf dem iPhone öffnen/installieren.

Ein roter Workflow-Lauf erzeugt keine verlässliche Installationsdatei. In diesem Fall benötigen wir die Fehlermeldung aus dem betroffenen Schritt. Ein GitHub-Build kann erstmals echte Compilerfehler sichtbar machen, die unter Windows ohne Xcode nicht prüfbar waren.

## 4. AltStore Classic auf Windows einrichten

Verwende die [offizielle Windows-Anleitung für AltStore Classic](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Sie beschreibt die benötigten Apple-Komponenten, AltServer und die Ersteinrichtung mit einem USB-Kabel. Die Anleitung unterscheidet die unterstützten iTunes-/iCloud-Versionen; halte dich an deren aktuellen Angaben.

Verbinde dein entsperrtes iPhone mit dem PC und bestätige bei Bedarf das Vertrauen. Installiere AltStore über AltServer mit deinem normalen Apple-Konto. Die Anmeldung erfolgt in AltServer beziehungsweise AltStore, nicht im GitHub-Workflow. Erforderliche Bestätigungen und der iOS-Entwicklermodus sind in der offiziellen Anleitung beschrieben.

## 5. Datenblick mit Widget installieren

Übertrage `Datenblick-unsigned.ipa` in die Dateien-App deines iPhones, zum Beispiel über dein vorhandenes iCloud Drive. In AltStore Classic öffnest du **My Apps**, tippst auf **+** und wählst die IPA aus. AltServer auf dem Windows-PC muss für die Signierung erreichbar sein.

Falls AltStore nach enthaltenen Erweiterungen fragt, **Keep App Extensions** wählen. Die enthaltene Erweiterung ist das Datenblick-Widget; wird sie entfernt, fehlt das Widget. Die App und ihre Erweiterung belegen App-IDs aus dem kostenlosen Wochenkontingent. AltStore selbst und Datenblick zählen außerdem zum begrenzten Kontingent aktiver sideloaded Apps.

Öffne Datenblick nach der Installation mindestens einmal. Für den ersten Funktionstest kannst du ausdrücklich markierte Demodaten auswählen. Für echte Telekom-Daten anschließend auf **Telekom** wechseln, mobile Daten deiner Telekom-SIM verwenden und den Abruf starten. Die Telekom-Erkennung bleibt experimentell und muss mit deinem Anschluss geprüft werden.

Danach Datenblick über die Widget-Auswahl auf dem Home- oder Sperrbildschirm hinzufügen. Die App erkennt die von AltStore angepasste gemeinsame App-Gruppe aus ihren eigenen signierten Metadaten. Dieser Mechanismus basiert auf dem veröffentlichten AltStore-Quellcode; der komplette Weg benötigt noch den ersten Cloud-Build und Gerätetest.

## 6. Einmal pro Woche erneuern

Apps mit kostenloser persönlicher Signierung laufen nach sieben Tagen ab. Lass AltServer auf Windows laufen und stelle sicher, dass das iPhone den PC erreichen kann. Verwende in AltStore regelmäßig **Refresh All**, am besten vor Ablauf. Hintergrund-Erneuerung wird versucht, ist jedoch keine Garantie. Bei Bedarf per USB verbinden und erneut versuchen.

Eine neue IPA ist nur bei App-Updates nötig. Verwende für Erneuerungen dasselbe Apple-Konto. Wenn die App abgelaufen ist, folge der AltStore-Anleitung zur erneuten Signierung; lösche die App nicht vorschnell, damit ihre lokal gespeicherten Daten erhalten bleiben.

## Was weiterhin offen ist

Das Projekt ist lokal strukturell geprüft. Die zehn Selbsttests des IPA-Strukturprüfers wurden auf künstlichen Beispielen ausgeführt; sie sind kein iOS-Build. Der tatsächliche Stand des ersten Xcode-Builds ist unter **Actions** im Repository sichtbar. Persönliche Signierung, Widget-Anzeige und Telekom-Antworten müssen anschließend auf deinem iPhone geprüft werden.

## Quellen

- [GitHub: Kosten und kostenlose Nutzung von Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [GitHub: Dateien im Browser hinzufügen](https://docs.github.com/en/repositories/working-with-files/managing-files/adding-a-file-to-a-repository)
- [AltStore Classic: Windows-Einrichtung](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [AltStore Classic: Laufzeit und Erneuerung](https://faq.altstore.io/altstore-classic/your-altstore)
- [AltStore Classic: App-ID-Kontingent und Erweiterungen](https://faq.altstore.io/altstore-classic/app-ids)
- [AltStore-Quellcode: Profile und App-Gruppen](https://github.com/altstoreio/AltStore/blob/classic/AltStore/Operations/FetchProvisioningProfilesOperation.swift)
- [AltStore-Quellcode: Neusignierung und ALTAppGroups-Metadaten](https://github.com/altstoreio/AltStore/blob/classic/AltStore/Operations/ResignAppOperation.swift)

