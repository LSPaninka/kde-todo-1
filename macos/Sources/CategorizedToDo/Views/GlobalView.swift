import SwiftUI

/// "Global" tab in ToDo mode: shows every active task across all categories,
/// sorted by done/priority/recency, with a colored stripe per category.
struct GlobalView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 6) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let items = sortedTasks
                    if items.isEmpty {
                        Text("No hay tareas en ninguna categoría.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(items) { t in
                            TaskRow(task: t, store: store, settings: settings)
                                .padding(.horizontal, 8)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                Text("Global")
                    .font(.headline)
                Text("(\(store.totalPending) pendientes de \(visibleTasks.count) totales)")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(0..<settings.categoryCount, id: \.self) { i in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(settings.categoryColor(i))
                            .frame(width: 10, height: 10)
                        Text("\(settings.categoryName(i))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    // MARK: - Data

    /// Only tasks whose category index is currently visible.
    private var visibleTasks: [TodoTask] {
        store.tasks.filter { $0.category >= 0 && $0.category < settings.categoryCount }
    }

    /// done=false first, then by priority weight desc, then by createdAt desc.
    private var sortedTasks: [TodoTask] {
        visibleTasks.sorted { a, b in
            if a.done != b.done { return !a.done }
            if a.priority.weight != b.priority.weight {
                return a.priority.weight > b.priority.weight
            }
            return a.createdAt > b.createdAt
        }
    }
}
