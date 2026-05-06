import SwiftUI

/// Menu-bar label.
///
/// Per the spec: a single white rounded square with a number in the middle.
/// Stays compact (uses ~22 pt — the standard menu-bar item height on macOS).
///
/// In `.todo` mode the number is the count of pending tasks; in `.jira` mode
/// it's the total count of cached issues.
///
/// If `useSingleSquare` is false, falls back to the multi-swatch panel layout
/// (one mini-square per visible category, colored).
struct MenuBarIcon: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var jira: JiraStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        if settings.menuBarUseSingleSquare {
            singleSquare
        } else {
            multiSwatch
        }
    }

    private var totalCount: Int {
        switch settings.mode {
        case .todo: return store.totalPending
        case .jira: return jira.issues.count
        }
    }

    // MARK: - Single white square

    private var singleSquare: some View {
        let count = totalCount
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
            switch settings.mode {
            case .todo:
                ForEach(0..<settings.categoryCount, id: \.self) { i in
                    cell(color: settings.categoryColor(i),
                         count: store.pendingCount(category: i),
                         textColor: settings.popupCounterTextColors.indices.contains(i)
                            ? settings.popupCounterTextColors[i]
                            : .white)
                }
            case .jira:
                ForEach(0..<settings.jiraCategoryCount, id: \.self) { i in
                    cell(color: settings.jiraCategoryColor(i),
                         count: jira.count(forCategory: i),
                         textColor: settings.jiraCategoryTextColors.indices.contains(i)
                            ? settings.jiraCategoryTextColors[i]
                            : .white)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(color: Color, count: Int, textColor: CounterTextColor) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 16, height: 16)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(textColor.color)
                .monospacedDigit()
        }
    }
}
