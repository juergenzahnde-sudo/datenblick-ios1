import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedSource = "telekom"
    @State private var planName = ""
    @State private var totalGB = "40"
    @State private var usedGB = "0"
    @State private var cycleStartDay = 1
    @State private var threshold = 80
    @State private var notificationsEnabled = false
    @State private var changingPermission = false
    @State private var showDeleteConfirmation = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case plan, total, used }

    var body: some View {
        Form {
            Section {
                Picker("Datenquelle", selection: $selectedSource) {
                    Text("Telekom").tag("telekom")
                    Text("Manuell").tag("manual")
                    Text("Demo").tag("demo")
                }
                .pickerStyle(.segmented)
                TextField("Mein Telekom-Tarif", text: $planName)
                    .focused($focusedField, equals: .plan)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Name deines Tarifs")
            } header: {
                Text("Dein Tarif")
            } footer: {
                Text("Aktive Quelle: \(model.sourceTitle). Eine neue Auswahl wird mit dem Button darunter übernommen.")
            }

            if selectedSource == "telekom" {
                Section {
                    Label("Direkt über deine Telekom-Verbindung", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline.weight(.medium))
                    Text("Für den Abruf können mobile Daten der Telekom-SIM erforderlich sein. Die Unterstützung hängt von deinem Vertrag und der Verfügbarkeit der Telekom-Datenseite ab.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        focusedField = nil
                        Task { await model.useTelekom(planName: planName) }
                    } label: {
                        HStack {
                            Label("Speichern und Telekom abrufen", systemImage: "arrow.clockwise")
                            Spacer()
                            if model.isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(model.isRefreshing)
                    Link("Telekom-Datenseite öffnen", destination: URL(string: "https://pass.telekom.de")!)
                } header: {
                    Text("Telekom verbinden")
                } footer: {
                    Text("Die automatische Erkennung ist experimentell und kann sich durch Änderungen der Telekom-Seite ändern. Es werden weder Telekom-Passwort noch Kundencenter-Zugang gespeichert. Die Datenseite kann abhängig von Verbindung und Tarif nicht erreichbar sein.")
                }
            } else if selectedSource == "manual" {
                Section {
                    LabeledContent("Datenvolumen pro Monat") {
                        HStack {
                            TextField("40", text: $totalGB)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .total)
                                .accessibilityLabel("Datenvolumen pro Monat in Gigabyte")
                            Text("GB").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Bisher verbraucht") {
                        HStack {
                            TextField("0", text: $usedGB)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .used)
                                .accessibilityLabel("Bisher verbraucht in Gigabyte")
                            Text("GB").foregroundStyle(.secondary)
                        }
                    }
                    Picker("Monatsbeginn", selection: $cycleStartDay) {
                        ForEach(1...31, id: \.self) { day in Text("Am \(day). des Monats").tag(day) }
                    }
                    Button {
                        focusedField = nil
                        Task { _ = await model.saveManual(planName: planName, totalText: totalGB, usedText: usedGB, startDay: cycleStartDay) }
                    } label: {
                        Label("Manuellen Stand speichern", systemImage: "checkmark.circle")
                    }
                    .disabled(model.isRefreshing)
                } header: {
                    Text("Verbrauch eintragen")
                } footer: {
                    Text("Dezimalkomma und Dezimalpunkt sind erlaubt. 1 GB entspricht 1.000.000.000 Byte. In kurzen Monaten beginnt der Zeitraum am letzten Monatstag. Aktualisiere den Verbrauch selbst; iOS stellt Drittanbieter-Apps keinen verlässlichen Tarifzähler bereit.")
                }
            } else {
                Section {
                    Label("Die App unverbindlich ausprobieren", systemImage: "sparkles")
                        .font(.subheadline.weight(.medium))
                    Text("Dashboard und Widgets zeigen ausdrücklich markierte Beispieldaten. Dein echter Verbrauch wird in diesem Modus nicht abgefragt.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        focusedField = nil
                        model.useDemo()
                    } label: {
                        Label("Demomodus aktivieren", systemImage: "play.circle")
                    }
                    .disabled(model.isRefreshing)
                } header: { Text("Beispieldaten") }
            }

            if let error = model.lastError {
                Section {
                    Label("\(error)", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            if let notice = model.notice {
                Section { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            }

            Section {
                Toggle("Verbrauchswarnung", isOn: $notificationsEnabled)
                    .disabled(changingPermission)
                    .onChange(of: notificationsEnabled) { _, value in
                        guard value != model.settings.notificationsEnabled, !changingPermission else { return }
                        changingPermission = true
                        Task {
                            await model.setNotificationsEnabled(value)
                            notificationsEnabled = model.settings.notificationsEnabled
                            changingPermission = false
                        }
                    }
                Picker("Warnen ab", selection: $threshold) {
                    ForEach([50, 75, 80, 90, 95], id: \.self) { number in Text("\(number) % verbraucht").tag(number) }
                }
                .onChange(of: threshold) { _, value in model.setWarningThreshold(value) }
            } header: { Text("Mitteilungen") } footer: {
                Text("Nach deiner Zustimmung wird bei einer erfolgreichen Aktualisierung in der geöffneten App einmal pro Zeitraum gewarnt. Im Demomodus gibt es keine Warnung. Es gibt keine minutengenaue Hintergrundüberwachung.")
            }

            Section {
                NavigationLink { WidgetHelpView() } label: {
                    Label("Widgets hinzufügen", systemImage: "square.grid.2x2")
                }
                NavigationLink { PrivacyView() } label: {
                    Label("Datenschutz und Funktionsweise", systemImage: "hand.raised")
                }
            } header: { Text("Gut zu wissen") } footer: {
                Text("Widgets zeigen den zuletzt gespeicherten Stand. iOS entscheidet über Hintergrundlaufzeit und Widget-Aktualisierungen. Öffne die App für einen gezielten neuen Abruf.")
            }

            Section {
                Button("Lokale Daten löschen", role: .destructive) { showDeleteConfirmation = true }
                    .disabled(model.isRefreshing)
            } footer: {
                Text("Datenblick · Unabhängige App. Keine Verbindung zur Deutschen Telekom AG.")
            }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: loadSettings)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { focusedField = nil }
            }
        }
        .confirmationDialog("Alle lokalen Daten löschen?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Verbrauch und Einstellungen löschen", role: .destructive) {
                model.deleteLocalData()
                loadSettings()
            }
        } message: {
            Text("Gespeicherte Verbrauchsstände, Verlauf und Einstellungen werden auf diesem Gerät gelöscht. Dein Telekom-Vertrag bleibt davon unberührt.")
        }
    }

    private func loadSettings() {
        switch model.settings.mode {
        case .telekom: selectedSource = "telekom"
        case .manual: selectedSource = "manual"
        case .demo: selectedSource = "demo"
        }
        planName = model.settings.planName
        totalGB = model.settings.monthlyLimitGB.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
        cycleStartDay = model.settings.cycleStartDay
        threshold = model.settings.warningThreshold
        notificationsEnabled = model.settings.notificationsEnabled
        if let current = model.snapshot, case .manual = current.source {
            usedGB = (current.usedBytes / 1_000_000_000).formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
        } else {
            usedGB = "0"
        }
    }
}

struct WidgetHelpView: View {
    var body: some View {
        List {
            Section {
                Label("Dein Datenblick, ohne die App zu öffnen", systemImage: "square.grid.2x2")
                    .font(.title3.weight(.semibold))
                    .padding(.vertical, 8)
                Text("Richte zuerst eine Datenquelle ein und speichere einen Stand. Danach kannst du Datenblick als Widget hinzufügen.")
            }
            Section("Auf dem Home-Bildschirm") {
                instruction(1, "Halte eine freie Stelle auf deinem Home-Bildschirm gedrückt, bis die Symbole wackeln.")
                instruction(2, "Öffne die Widget-Auswahl über „Bearbeiten“ bzw. das Plus-Symbol und suche nach „Datenblick“.")
                instruction(3, "Wähle eine Größe und tippe auf „Widget hinzufügen“.")
            }
            Section("Auf dem Sperrbildschirm") {
                instruction(1, "Halte den Sperrbildschirm gedrückt und wähle „Anpassen“.")
                instruction(2, "Tippe in den Widget-Bereich unter der Uhr und wähle „Datenblick“.")
            }
            Section("Aktualität") {
                Text("Der Zeitstempel im Widget zeigt, wann der Verbrauch zuletzt erfolgreich abgerufen oder eingetragen wurde. Die Angaben des Anbieters können verzögert sein. iOS steuert die Aktualisierungszeitpunkte. Tippe das Widget an, um die App zu öffnen und einen neuen Abruf anzustoßen.")
                Text("Für Telekom-Abfragen kann eine Telekom-Mobilfunkverbindung nötig sein. Auf WLAN kann deshalb ein älterer gespeicherter Stand sichtbar bleiben.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.telekomMagenta)
                .frame(width: 28, height: 28)
                .background(Color.telekomMagenta.opacity(0.08), in: Circle())
                .accessibilityHidden(true)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 5)
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Auf deinem Gerät") {
                Text("Verbrauchsstände, Verlauf und Einstellungen werden lokal gespeichert und über eine App-Gruppe mit dem Widget geteilt. In der App gibt es kein Benutzerkonto, kein Werbe-SDK und keine Analyse-Tracker.")
                Text("In den Einstellungen kannst du die lokal gespeicherten App-Daten löschen.")
            }
            Section("Beim Telekom-Abruf") {
                Text("Die App sendet eine Netzwerkanfrage an die Telekom-Datenseite, um den verfügbaren Verbrauchsstand zu laden. Dabei erhält der Dienst technisch bedingt Verbindungsdaten, zum Beispiel deine IP-Adresse. Es werden keine Telekom-Zugangsdaten abgefragt oder gespeichert.")
                Link("Datenschutz bei der Telekom", destination: URL(string: "https://www.telekom.de/ueber-das-unternehmen/datenschutz")!)
            }
            Section("Was angezeigt wird") {
                Text("Die App zeigt den zuletzt übermittelten Stand. Tarifinformationen und Buchungen können beim Anbieter verzögert sein. Maßgeblich sind die Angaben der Telekom. Eine geräteweite Live-Messung aller mobilen Daten ist nicht Bestandteil der App.")
                Text("Manuelle Eingaben und Demodaten sind ausdrücklich gekennzeichnet. Das Tagesbudget teilt das verbleibende Volumen gleichmäßig auf die verbleibenden Tage auf und ist keine Verbrauchsprognose.")
            }
            Section("Mitteilungen") {
                Text("Mitteilungen sind freiwillig und benötigen deine iOS-Zustimmung. Eine Warnung wird nach einer erfolgreichen Aktualisierung in der geöffneten App geprüft, sobald die gewählte Verbrauchsgrenze erreicht ist. Für unbegrenzte Tarife und Demodaten gibt es keine Warnung.")
            }
            Section("Unabhängige App") {
                Text("Datenblick ist kein offizielles Produkt der Deutschen Telekom AG. Telekom und andere genannte Marken gehören ihren jeweiligen Rechteinhabern.")
            }
        }
        .navigationTitle("Datenschutz")
        .navigationBarTitleDisplayMode(.inline)
    }
}
