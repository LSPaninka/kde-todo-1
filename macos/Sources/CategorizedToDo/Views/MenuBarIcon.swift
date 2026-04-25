import SwiftUI

/// Menu-bar label.
///
/// Per the spec: a single white rounded square with a number in the middle.
/// Stays compact (uses 22 pt — the standard menu-bar item height on macOS).
///
/// If `useSingleSquare` is false, falls back to the multi-swatch panel layout
/// (one mini-square per visible category, colored).
struct MenuBarIcon: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        if settings.menuBarUseSingleSquare {
            singleSquare
        } else {
            multiSwatch
        }
    }

    // MARK: - Single white square

    private var singleSquare: some View {
        let count = store.totalPending
        return ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(settings.menuBarBackground)
                .frame(width: 20, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                )
            Text("\(count)")
                .font(.system(size: count > 99 ? 9 : 11,
                              weight: .semibold,
                              design: .rounded))
                .foregroundColor(settings.menuBarTextColor.color)
                .monospacedDigit()
        }
        .padding(.horizontal, 1)
    }

    // MARK: - Multi-swatch (KDE-like)

    private var multiSwatch: some View {
        HStack(spacing: 4) {
            ForEach(0..<settings.categoryCount, id: \.self) { i in
                let n = store.pendingCount(category: i)
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(settings.categoryColor(i))
                        .frame(width: 16, height: 16)
                    Text("\(n)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(
                            (settings.popupCounterTextColors.indices.contains(i)
                             ? settings.popupCounterTextColors[i]
                             : .white).color
                        )
                        .monospacedDigit()
                }
            }
        }
    }
}
