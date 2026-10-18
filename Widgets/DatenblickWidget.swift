import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let refreshFailed: Bool
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .demo(), refreshFailed: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: context.isPreview ? .demo() : SharedStore().snapshot,
                              refreshFailed: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let store = SharedStore()
            let generation = store.generation
            var failed = false
            if store.settings.mode == .telekom {
                do {
                    let snapshot = try await TelekomClient().fetch()
                    // A simultaneous switch in the app must not change the widget's source.
                    if store.settings.mode == .telekom, store.generation == generation {
                        store.save(snapshot, recordHistory: false)
                    }
                } catch {
                    failed = true
                }
            }
            let entry = UsageEntry(date: Date(), snapshot: store.snapshot, refreshFailed: failed)
            // This is a request. iOS chooses the actual refresh time and may delay it.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry
    private let magenta = Color(red: 0.91, green: 0, blue: 0.45)

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .accessoryCircular: circular(snapshot)
                case .accessoryRectangular: rectangular(snapshot)
                default: home(snapshot)
                }
            } else {
                empty
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(URL(string: "datenblick://refresh"))
    }

    private func home(_ snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("DATENBLICK").tracking(1.3)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(magenta)
                Spacer(minLength: 2)
                Text(snapshot.isUnlimited ? "∞" : volume(snapshot.remainingBytes))
                    .font(.system(size: family == .systemMedium ? 38 : 33, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .monospacedDigit()
                Text(snapshot.isUnlimited ? "Unbegrenztes Volumen" : "noch verfügbar")
                    .font(.caption).foregroundStyle(.secondary)
                if !snapshot.isUnlimited {
                    ProgressView(value: snapshot.usedFraction)
                        .tint(snapshot.usedFraction >= 0.9 ? .orange : magenta)
                        .accessibilityLabel("Verbraucht")
                        .accessibilityValue("\(Int(snapshot.usedFraction * 100)) Prozent")
                }
                Spacer(minLength: 1)
                footer(snapshot)
            }
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 10) {
                    Label(volume(snapshot.usedBytes) + " verbraucht", systemImage: "arrow.up.right")
                    Label(snapshot.daysRemaining.map { "\($0) Tage übrig" } ?? "Laufzeit unbekannt", systemImage: "calendar")
                    Text("Tippen zum Aktualisieren")
                        .foregroundStyle(magenta).font(.caption2)
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private func circular(_ snapshot: UsageSnapshot) -> some View {
        let hasQuota = (snapshot.totalBytes ?? 0) > 0
        let fraction = snapshot.isUnlimited ? 1 : (hasQuota ? 1 - snapshot.usedFraction : 0)
        return Gauge(value: fraction) {
            Image(systemName: "antenna.radiowaves.left.and.right")
        } currentValueLabel: {
            Text(snapshot.isUnlimited ? "∞" : (hasQuota ? "\(Int(fraction * 100))" : "–"))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetLabel {
            if entry.refreshFailed || snapshot.isStale {
                Label("Alt: \(snapshot.fetchedAt.formatted(.dateTime.day().month()))", systemImage: "clock.badge.exclamationmark")
            } else {
                Text(snapshot.source == .telekom ? "Abruf \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))" : source(snapshot))
            }
        }
        .accessibilityLabel("\(source(snapshot)), \(snapshot.isUnlimited ? "unbegrenzt" : volume(snapshot.remainingBytes) + " verfügbar"), abgerufen \(snapshot.fetchedAt.formatted())\(entry.refreshFailed || snapshot.isStale ? ", gespeicherter älterer Wert" : "")")
    }

    private func rectangular(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.isUnlimited ? "Unbegrenztes Volumen" : volume(snapshot.remainingBytes) + " verfügbar")
                .font(.headline).minimumScaleFactor(0.7).lineLimit(1)
            HStack {
                Text(source(snapshot))
                Text(snapshot.fetchedAt.formatted(.dateTime.day().month().hour().minute()))
                if snapshot.isStale || entry.refreshFailed { Image(systemName: "clock.badge.exclamationmark") }
            }.font(.caption2)
        }
        .accessibilityElement(children: .combine)
    }

    private func footer(_ snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 4) {
            if snapshot.source != .telekom {
                Text(source(snapshot)).fontWeight(.semibold)
            } else if entry.refreshFailed || snapshot.isStale {
                Image(systemName: "clock.badge.exclamationmark")
                Text("Gespeichert")
            } else {
                Text("Abruf")
            }
            if snapshot.isStale {
                Text(snapshot.fetchedAt.formatted(.dateTime.day().month().hour().minute()))
            } else {
                Text(snapshot.fetchedAt, style: .time)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(magenta)
            Text("Datenblick").font(.headline)
            if family != .accessoryCircular {
                Text("App öffnen und Daten einrichten.").font(.caption)
            }
        }
        .padding(family == .systemSmall || family == .systemMedium ? 16 : 0)
    }

    private func source(_ snapshot: UsageSnapshot) -> String {
        switch snapshot.source {
        case .telekom: return "Telekom"
        case .manual: return "Manuell"
        case .demo: return "Demo"
        }
    }

    private func volume(_ bytes: Double?) -> String {
        guard let bytes else { return "–" }
        let gb = bytes / 1_000_000_000
        if gb < 1 && bytes > 0 {
            return (bytes / 1_000_000).formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0))) + " MB"
        }
        return gb.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(1))) + " GB"
    }
}

@main
struct DatenblickWidget: Widget {
    let kind = "DatenblickUsage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Dein Datenvolumen")
        .description("Restvolumen und letzter Abruf für deinen Telekom-Anschluss. Aktualisierungen plant iOS.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
