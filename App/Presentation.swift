import SwiftUI

extension Color {
    static let telekomMagenta = Color(red: 0.886, green: 0, blue: 0.455)
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    static let appCard = Color(uiColor: .secondarySystemGroupedBackground)
}

enum UsageFormat {
    static func numberGB(_ bytes: Double) -> String {
        (max(0, bytes) / 1_000_000_000).formatted(.number.precision(.fractionLength(0...1)))
    }

    static func gb(_ bytes: Double) -> String { "\(numberGB(bytes)) GB" }

    static func timestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func source(_ source: UsageSource) -> String {
        switch source {
        case .telekom: return "Telekom-Abfrage"
        case .manual: return "Manuell eingetragen"
        case .demo: return "Demodaten"
        }
    }

    static func sameSource(_ first: UsageSource, _ second: UsageSource) -> Bool {
        switch (first, second) {
        case (.telekom, .telekom), (.manual, .manual), (.demo, .demo): return true
        default: return false
        }
    }
}

struct SourceBadge: View {
    let source: UsageSource
    var onDark = false

    private var symbol: String {
        switch source {
        case .telekom: return "antenna.radiowaves.left.and.right"
        case .manual: return "pencil"
        case .demo: return "sparkles"
        }
    }

    var body: some View {
        Label(UsageFormat.source(source), systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(onDark ? Color.white : .telekomMagenta)
            .background(onDark ? Color.white.opacity(0.13) : Color.telekomMagenta.opacity(0.09), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct AppCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct MessageCard: View {
    let title: String
    let message: String
    var isError = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? Color.orange : .telekomMagenta)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isError ? Color.orange.opacity(0.09) : Color.telekomMagenta.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct PrimaryAction: View {
    let title: String
    var symbol = "arrow.clockwise"
    var isBusy = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isBusy { ProgressView().tint(.white) }
                else { Image(systemName: symbol) }
                Text(isBusy ? "Wird aktualisiert …" : title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.telekomMagenta, in: RoundedRectangle(cornerRadius: 17))
        .disabled(isBusy)
    }
}
