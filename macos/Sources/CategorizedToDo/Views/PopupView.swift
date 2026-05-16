import SwiftUI

/// Outer popup. Switches between ToDo / Jira / GitHub / Notion views based
/// on `settings.mode`. The fixed frame size from settings is applied here.
struct PopupView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var jira: JiraStore
    @ObservedObject var gh: GhStore
    @ObservedObject var notion: NotionStore
    var onOpenSettings: () -> Void

    var body: some View {
        Group {
            switch settings.mode {
            case .todo:
                TodoPopupView(store: store,
                              settings: settings,
                              onOpenSettings: onOpenSettings)
            case .jira:
                JiraView(jira: jira,
                         settings: settings,
                         onOpenSettings: onOpenSettings)
            case .gh:
                GhView(gh: gh,
                       settings: settings,
                       onOpenSettings: onOpenSettings)
            case .notion:
                NotionView(notion: notion,
                           settings: settings,
                           onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: CGFloat(settings.popupWidth),
               height: CGFloat(settings.popupHeight))
    }
}

/// The original local-todo popup (tabs per category + Archive). Identical to
/// the pre-Jira behavior; renamed so it can sit alongside `JiraView` inside
/// the new `PopupView` switcher.
struct TodoPopupView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings
    var onOpenSettings: () -> Void

    /// Tab selection. Special values:
    ///   - `archiveTag` (`.max`)        → Archive
    ///   - `globalTag`  (`.max - 1`)    → Global view
    @State private var selection: Int = 0
    private let archiveTag: Int = .max
    private let globalTag: Int = .max - 1

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            toolbar
        }
        .onAppear { clampSelection() }
        .onChange(of: settings.categoryCount) { _ in clampSelection() }
    }

    private func clampSelection() {
        if selection == archiveTag || selection == globalTag { return }
        if selection >= settings.categoryCount {
            selection = max(0, settings.categoryCount - 1)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                tabButton(index: globalTag, kind: .global)
                ForEach(0..<settings.categoryCount, id: \.self) { i in
                    tabButton(index: i, kind: .category)
                }
                tabButton(index: archiveTag, kind: .archive)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
    }

    private enum TabKind { case category, archive, global }

    @ViewBuilder
    private func tabButton(index: Int, kind: TabKind) -> some View {
        let selected = (selection == index)
        let title: String
        let count: Int
        let color: Color

        switch kind {
        case .category:
            title = settings.categoryName(index)
            count = store.pendingCount(category: index)
            color = settings.categoryColor(index)
        case .archive:
            title = "Archivo"
            count = store.archived.count
            color = .gray
        case .global:
            title = "Global"
            count = store.totalPending
            color = .accentColor
        }

        Button {
            selection = index
        } label: {
            HStack(spacing: 5) {
                switch kind {
                case .category:
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(width: 8, height: 12)
                case .global:
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10))
                        .foregroundColor(color)
                case .archive:
                    EmptyView()
                }
                Text(title)
                    .lineLimit(1)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                badge(count: count, color: color, isArchive: kind == .archive,
                      index: kind == .category ? index : -1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.5) : Color.clear,
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badge(count: Int, color: Color, isArchive: Bool, index: Int) -> some View {
        switch settings.popupCounterLayout {
        case .right:
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color.opacity(isArchive ? 0.2 : 1.0))
                    .frame(minWidth: 18, minHeight: 16)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(textColor(isArchive: isArchive, index: index))
                    .padding(.horizontal, 4)
                    .monospacedDigit()
            }
            .fixedSize(horizontal: true, vertical: false)
        case .inside:
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(isArchive ? 0.2 : 1.0))
                    .frame(width: 22, height: 18)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(textColor(isArchive: isArchive, index: index))
                    .monospacedDigit()
            }
        }
    }

    private func textColor(isArchive: Bool, index: Int) -> Color {
        if isArchive { return .primary }
        if index < 0 { return .white }     // Global tab badge
        if settings.popupCounterTextColors.indices.contains(index) {
            return settings.popupCounterTextColors[index].color
        }
        return .white
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if selection == archiveTag {
            ArchiveView(store: store, settings: settings)
        } else if selection == globalTag {
            GlobalView(store: store, settings: settings)
        } else {
            CategoryView(categoryIndex: selection,
                         store: store,
                         settings: settings)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button {
                onOpenSettings()
            } label: {
                Label("Configuración", systemImage: "gearshape")
            }
            Spacer()
            Text("Pendientes: \(store.totalPending)")
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Salir", systemImage: "power")
            }
        }
        .padding(8)
    }
}
