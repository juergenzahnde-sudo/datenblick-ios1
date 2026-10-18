import SwiftUI
import Charts

private struct HistorySample: Identifiable {
    let id: Int
    let value: UsageSnapshot

    var gb: Double { value.usedBytes / 1_000_000_000 }

    /// Unknown cycles remain separate points; never draw a false line through a reset.
    var cycleID: String {
        if let start = value.cycleStart { return "start.\(Calendar.current.startOfDay(for: start).timeIntervalSince1970)" }
        if let end = value.cycleEnd {
            return "end.\(Calendar.current.startOfDay(for: end.addingTimeInterval(12 * 60 * 60)).timeIntervalSince1970)"
        }
        return "unknown.\(id)"
    }
}

@MainActor
struct HistoryView: View {
    @ObservedObject var model: AppModel

    private var samples: [HistorySample] {
        Array(model.selectedHistory.suffix(100)).enumerated().map { HistorySample(id: $0.offset, value: $0.element) }
    }

    private var showsTime: Bool {
        guard let first = samples.first?.value.fetchedAt, let last = samples.last?.value.fetchedAt else { return false }
        return last.timeIntervalSince(first) < 86_400
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dein Verbrauch im Verlauf")
                        .font(.title2.weight(.bold))
                    Text("Gespeicherte Abfragen aus der Quelle „\(model.sourceTitle)“.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if case .demo = model.settings.mode {
                    MessageCard(title: "Beispielverlauf", message: "Diese Einträge stammen aus dem Demomodus und zeigen keinen echten Verbrauch.")
                }
                if samples.isEmpty {
                    ContentUnavailableView("Noch kein Verlauf", systemImage: "chart.xyaxis.line", description: Text("Nach der ersten erfolgreichen Abfrage oder manuellen Eingabe erscheint hier dein Verbrauch."))
                        .padding(.vertical, 40)
                } else {
                    chart
                    Text("Jeder Punkt ist ein gespeicherter Stand. Linien verbinden nur Abfragen mit bekanntem, gleichem Abrechnungszeitraum. Es findet keine lückenlose Messung statt.")
                        .font(.caption).foregroundStyle(.secondary)
                    recentReadings
                }
            }
            .padding(20)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chart: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Verbrauch in GB").font(.headline)
                    Spacer()
                    Text("\(samples.count) \(samples.count == 1 ? "Stand" : "Stände")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Chart(samples) { sample in
                    LineMark(
                        x: .value("Zeitpunkt", sample.value.fetchedAt),
                        y: .value("Verbraucht in GB", sample.gb),
                        series: .value("Abrechnungszeitraum", sample.cycleID)
                    )
                    .foregroundStyle(Color.telekomMagenta.opacity(0.6))
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value("Zeitpunkt", sample.value.fetchedAt),
                        y: .value("Verbraucht in GB", sample.gb)
                    )
                    .foregroundStyle(Color.telekomMagenta)
                    .symbolSize(40)
                    .accessibilityLabel(UsageFormat.timestamp(sample.value.fetchedAt))
                    .accessibilityValue("\(UsageFormat.gb(sample.value.usedBytes)) verbraucht")
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { axis in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = axis.as(Date.self) {
                                Text(showsTime ? date.formatted(.dateTime.hour().minute()) : date.formatted(.dateTime.day().month(.abbreviated)))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { axis in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = axis.as(Double.self) {
                                Text(number.formatted(.number.precision(.fractionLength(0...1))))
                            }
                        }
                    }
                }
                .frame(height: 230)
            }
        }
    }

    private var recentReadings: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Letzte Einträge").font(.headline)
                ForEach(Array(samples.suffix(20).reversed())) { sample in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(UsageFormat.timestamp(sample.value.fetchedAt))
                                .font(.subheadline)
                            Spacer(minLength: 12)
                            Text(UsageFormat.gb(sample.value.usedBytes))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        Text("Verbraucht · \(UsageFormat.source(sample.value.source))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    if sample.id != samples.suffix(20).first?.id { Divider() }
                }
            }
        }
    }
}
