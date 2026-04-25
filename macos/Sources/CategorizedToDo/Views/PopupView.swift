import SwiftUI

/// Main popup. Tabs across the top: one per visible category + Archive.
/// Toolbar at the bottom: settings, quit.
struct PopupView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings
    var onOpenSettings: () -> Void

    @State private var selection: Int = 0   // 0..<categoryCount, .max → archive
    private let archiveTag: Int = .max

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            toolbar
        }
        .frame(width: CGFloat(settings.popupWidth),
               height: CGFloat(settings.popupHeight))
        .onAppear { clampSelection() }
        .onChange(of: settings.categoryCount) { _ in clampSelection() }
    }

    private func clampSelection() {
        if selection != archiveTag && selection >= settings.categoryCount {
            selection = max(0, settings.categoryCount - 1)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<settings.categoryCount, id: \.self) { i in
                tabButton(index: i, isArchive: false)
            }
            tabButton(index: archiveTag, isArchive: true)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func tabButton(index: Int, isArchive: Bool) -> some View {
        let selected = (selection == index)
        let title = isArchive ? "Archivo" : settings.categoryName(index)
        let count = isArchive ? store.archived.count : store.pendingCount(category: index)
        let color = isArchive ? Color.gray : settings.categoryColor(index)

        Button {
            selection = index
        } label: {
            HStack(spacing: 5) {
                if !isArchive {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(width: 8, height: 12)
                }
                Text(title)
                    .lineLimit(1)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                badge(count: count, color: color, isArchive: isArchive, index: index)
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
