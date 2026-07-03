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
