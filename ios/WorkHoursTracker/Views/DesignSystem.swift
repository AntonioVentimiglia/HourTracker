import SwiftUI

// Small shared building blocks so the Calendar / Summary / Raw Data tabs share
// one consistent, readable visual language instead of each rolling its own.

/// A titled card container with generous padding and a soft background.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title).font(.subheadline.weight(.semibold))
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// The headline pairing: billed (what you invoice) shown prominently next to the
/// raw tracked time, so both sums are visible at a glance and clearly distinct.
struct BilledVsRawHero: View {
    var billedHuman: String
    var billedSeconds: Int
    var rawHuman: String
    var blockCount: Int

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BILLED").font(.caption2.weight(.bold)).foregroundStyle(.indigo)
                    Text(Format.decimalHours(billedSeconds))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.indigo)
                    Text(billedHuman).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(blockCount) × 15-min block\(blockCount == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Divider().frame(height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("RAW TRACKED").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(rawHuman)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("actual time").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A clean label/value line for stat lists.
struct InfoRow: View {
    var label: String
    var value: String
    var emphasized = false

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasized ? .headline : .body.weight(.medium))
                .foregroundStyle(emphasized ? .indigo : .primary)
        }
        .font(.subheadline)
    }
}

/// A small colored status/type chip.
struct Chip: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Icon indicating where an entry came from (Siri / web / phone).
struct SourceIcon: View {
    var source: String
    var body: some View {
        Image(systemName: source == "siri" ? "mic.fill" : source == "web" ? "desktopcomputer" : "iphone")
            .font(.caption).foregroundStyle(.tertiary)
    }
}

/// The shared brand hue. Raw sessions use it solid; billed blocks use a light
/// tint of it, so a raw block and the 15-minute billed block it caused read as
/// visibly related.
enum Palette {
    static let raw = Color.indigo
    static let billed = Color.indigo.opacity(0.22)
}

extension Color {
    /// Parse "#RRGGBB" (or "RRGGBB"). Falls back to the default hue if malformed.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        var v: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&v) else { self = .indigo; return }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

/// Optional per-activity colors. `nil`/empty = the default indigo, so existing
/// sessions and Siri clock-ins keep the original look.
enum ActivityPalette {
    /// Selectable non-default colors (the default is offered separately).
    static let options: [(name: String, hex: String)] = [
        ("Blue",   "#0A84FF"),
        ("Teal",   "#30B0C7"),
        ("Green",  "#34C759"),
        ("Orange", "#FF9500"),
        ("Red",    "#FF3B30"),
        ("Pink",   "#FF2D55"),
        ("Purple", "#AF52DE"),
    ]

    static func color(_ hex: String?) -> Color {
        guard let hex, !hex.isEmpty else { return Palette.raw }
        return Color(hex: hex)
    }
}
