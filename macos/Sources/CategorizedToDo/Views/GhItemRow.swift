import SwiftUI
import AppKit

struct GhItemRow: View {
    let item: GhItem
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                typeBadge

                if item.number > 0 {
                    Text("#\(item.number)")
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .foregroundColor(.secondary)
                }

                Text(item.title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !item.statusName.isEmpty {
                    Text(item.statusName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(statusColor))
                }
            }

            if !item.repo.isEmpty {
                Text(item.repo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 30)
            }

            if !item.labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(item.labels.prefix(6), id: \.self) { l in
                        Text(l.name)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color(hex: l.colorHex) ?? .gray)
                            )
                            .foregroundColor(.white)
                    }
                    if item.labels.count > 6 {
                        Text("+\(item.labels.count - 6)").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 30)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !item.url.isEmpty, let url = URL(string: item.url) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private var typeBadge: some View {
        Text(item.typeBadgeChar)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(item.typeBadgeColor)
            )
    }

    /// Pill color derived from the status field name. Picks something
    /// reasonable; the user can always override category colors.
    private var statusColor: Color {
        let s = item.statusName.lowercased()
        if s.contains("done") || s.contains("merged") {
            return Color(red: 0.40, green: 0.73, blue: 0.42)
        }
        if s.contains("progress") || s.contains("doing") || s.contains("review") {
            return Color(red: 0.96, green: 0.65, blue: 0.13)
        }
        if s.contains("backlog") || s.contains("todo") || s.contains("triage") {
            return Color(red: 0.50, green: 0.55, blue: 0.62)
        }
        return Color.gray
    }
}
