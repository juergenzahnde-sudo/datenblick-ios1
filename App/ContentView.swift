import SwiftUI

private enum AppTab: Hashable {
    case overview, history, settings
}

@MainActor
struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab: AppTab = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(model: model) { selectedTab = .settings }
            }
            .tabItem { Label("Übersicht", systemImage: "circle.dotted.circle.fill") }
            .tag(AppTab.overview)

            NavigationStack { HistoryView(model: model) }
                .tabItem { Label("Verlauf", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.history)

            NavigationStack { SettingsView(model: model) }
                .tabItem { Label("Einstellungen", systemImage: "slider.horizontal.3") }
                .tag(AppTab.settings)
        }
    }
}

@MainActor
struct DashboardView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let snapshot = model.snapshot {
                    if case .demo = snapshot.source {
                        MessageCard(title: "Demomodus", message: "Du siehst Beispieldaten. Verbinde Telekom oder trage deinen Verbrauch in den Einstellungen ein.")
                    }
                    UsageHero(snapshot: snapshot, fallbackName: model.settings.planName)
                    if snapshot.isStale {
                        MessageCard(title: "Ältere Abfrage", message: "Diese Anzeige wurde vor mehr als zwei Stunden gespeichert. Aktualisiere den Verbrauch für einen neueren Abruf.")
                    }
                    metricCards(snapshot)
                    refreshAction(snapshot)
                } else {
                    welcomeCard
                }

                if let error = model.lastError {
                    MessageCard(title: "Abruf nicht möglich", message: error, isError: true)
                    if model.snapshot != nil {
                        Text("Die letzte erfolgreiche Abfrage bzw. Eingabe bleibt sichtbar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if case .telekom = model.settings.mode { connectionHint }
                }
                if let notice = model.notice {
                    MessageCard(title: "Hinweis", message: notice)
                }
                widgetCard
                Text("Unabhängige App für deinen Datenüberblick. Kein offizielles Angebot der Telekom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(20)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle("Datenblick")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALLES IM BLICK")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(Color.telekomMagenta)
            Text("Dein Datenvolumen.")
                .font(.largeTitle.weight(.bold))
                .tracking(-1)
            Text("Mehr Überblick. Mehr unterwegs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var welcomeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.telekomMagenta)
                    .padding(16)
                    .background(Color.telekomMagenta.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                Text("Einrichten. Durchatmen.")
                    .font(.title2.weight(.bold))
                Text("Rufe dein verfügbares Datenvolumen über deine Telekom-Verbindung ab. Für den ersten Abruf kann es helfen, WLAN auszuschalten und mobile Daten deiner Telekom-SIM zu nutzen.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryAction(title: "Telekom-Verbrauch abrufen", isBusy: model.isRefreshing) {
                    Task { await model.useTelekom(planName: model.settings.planName) }
                }
                Button("Manuell einrichten", action: openSettings)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                Button("Mit Beispieldaten ansehen") { model.useDemo() }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
        }
    }

    @ViewBuilder
    private func refreshAction(_ value: UsageSnapshot) -> some View {
        if case .manual = value.source {
            PrimaryAction(title: "Verbrauch eintragen", symbol: "pencil", action: openSettings)
        } else {
            PrimaryAction(title: isDemo(value) ? "Beispieldaten aktualisieren" : "Jetzt aktualisieren", isBusy: model.isRefreshing) {
                Task { await model.refresh() }
            }
        }
    }

    private func isDemo(_ value: UsageSnapshot) -> Bool {
        if case .demo = value.source { return true }
        return false
    }

    @ViewBuilder
    private func metricCards(_ value: UsageSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                dailyBudget(value)
                cycleCard(value)
            }
            VStack(spacing: 12) {
                dailyBudget(value)
                cycleCard(value)
            }
        }
    }

    private func dailyBudget(_ value: UsageSnapshot) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Tagesbudget", systemImage: "sun.max")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if value.isUnlimited {
                    Text("Unbegrenzt").font(.title3.weight(.bold))
                    Text("Ohne festes Datenlimit").font(.caption).foregroundStyle(.secondary)
                } else if let remaining = value.remainingBytes, let days = value.daysRemaining, days > 0 {
                    Text(UsageFormat.gb(remaining / Double(days)))
                        .font(.title2.weight(.bold)).monospacedDigit()
                    Text("pro verbleibendem Tag")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("–").font(.title2.weight(.bold))
                    Text("Zeitraum oder Limit fehlt")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func cycleCard(_ value: UsageSnapshot) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Zeitraum", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let end = value.cycleEnd, let days = value.daysRemaining, days > 0 {
                    Text("\(days) \(days == 1 ? "Tag" : "Tage")")
                        .font(.title2.weight(.bold)).monospacedDigit()
                    Text("bis \(end.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Offen").font(.title2.weight(.bold))
                    Text("Kein zukünftiges Ende bekannt")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionHint: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Verbindung prüfen", systemImage: "cellularbars")
                    .font(.headline)
                Text("Nutze mobile Daten deiner Telekom-SIM und teste den Abruf ohne WLAN. Bei Dual-SIM muss die Telekom-SIM für mobile Daten ausgewählt sein. Prüfe bei Bedarf, ob VPN oder iCloud Privat-Relay die Erkennung beeinflusst.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://pass.telekom.de")!) {
                    Label("Telekom-Datenseite öffnen", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var widgetCard: some View {
        NavigationLink {
            WidgetHelpView()
        } label: {
            AppCard {
                HStack(spacing: 14) {
                    Image(systemName: "square.grid.2x2")
                        .font(.title2)
                        .foregroundStyle(Color.telekomMagenta)
                        .padding(12)
                        .background(Color.telekomMagenta.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Direkt auf deinem Bildschirm")
                            .font(.headline)
                        Text("Home- und Sperrbildschirm-Widgets einrichten")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct UsageHero: View {
    let snapshot: UsageSnapshot
    let fallbackName: String
    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 58

    private var hasLimit: Bool { (snapshot.totalBytes ?? 0) > 0 && !snapshot.isUnlimited }

    private var mainValue: String {
        if snapshot.isUnlimited { return "∞" }
        return UsageFormat.numberGB(hasLimit ? (snapshot.remainingBytes ?? 0) : snapshot.usedBytes)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.planName ?? fallbackName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(snapshot.isUnlimited ? "Unlimitiertes Datenvolumen" : "Dein mobiler Freiraum")
                        .font(.caption).foregroundStyle(.white.opacity(0.62))
                }
                Spacer(minLength: 8)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.white.opacity(0.75))
                    .accessibilityHidden(true)
            }

            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 15)
                Circle()
                    .trim(from: 0, to: snapshot.isUnlimited ? 1 : (hasLimit ? 1 - min(1, max(0, snapshot.usedFraction)) : 0))
                    .stroke(AngularGradient(colors: [.telekomMagenta, Color(red: 1, green: 0.42, blue: 0.72)], center: .center), style: StrokeStyle(lineWidth: 15, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 5) {
                    Text(snapshot.isUnlimited ? "Einfach weitersurfen" : (hasLimit ? "Noch verfügbar" : "Verbraucht"))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    Text(mainValue)
                        .font(.system(size: snapshot.isUnlimited ? valueFontSize * 1.3 : valueFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .foregroundStyle(.white)
                    if !snapshot.isUnlimited {
                        Text("GB").font(.headline).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(25)
            }
            .frame(maxWidth: 265)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.isUnlimited ? "Unbegrenztes Datenvolumen" : "\(hasLimit ? "Noch verfügbar" : "Verbraucht"): \(mainValue) Gigabyte")

            VStack(spacing: 8) {
                if let total = snapshot.totalBytes, total > 0, !snapshot.isUnlimited {
                    Text("\(UsageFormat.gb(snapshot.usedBytes)) von \(UsageFormat.gb(total)) verbraucht")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                } else if snapshot.isUnlimited {
                    Text("Bisher \(UsageFormat.gb(snapshot.usedBytes)) verbraucht")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("Kein nutzbares Datenlimit verfügbar.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                }
                SourceBadge(source: snapshot.source, onDark: true)
                Text("\(timestampLabel): \(UsageFormat.timestamp(snapshot.fetchedAt))")
                    .font(.caption2).foregroundStyle(.white.opacity(0.58))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.1, blue: 0.15), Color(red: 0.07, green: 0.07, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Color.telekomMagenta.opacity(0.13)).frame(width: 160, height: 160).blur(radius: 35).offset(x: 25, y: -25)
                }
                .clipShape(RoundedRectangle(cornerRadius: 30))
        }
    }

    private var timestampLabel: String {
        switch snapshot.source {
        case .telekom: return "Zuletzt abgerufen"
        case .manual: return "Gespeichert"
        case .demo: return "Beispiel erzeugt"
        }
    }
}
