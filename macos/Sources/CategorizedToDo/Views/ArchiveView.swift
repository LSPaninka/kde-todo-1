import SwiftUI

struct ArchiveView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings

    @State private var pendingDeleteId: Int? = nil
    @State private var showClearConfirm: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "archivebox.fill")
                Text("Archivo")
                    .font(.headline)
                Text("(\(store.archived.count))")
                    .foregroundColor(.secondary)
                Spacer()
                Button(role: .destructive) {
                    if settings.confirmDelete {
                        showClearConfirm = true
                    } else {
                        store.clearArchive()
                    }
                } label: {
                    Label("Vaciar", systemImage: "trash")
                }
                .controlSize(.small)
                .disabled(store.archived.isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.archived.isEmpty {
                        Text("El archivo está vacío.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(store.archived) { t in
                            row(for: t)
                                .padding(.horizontal, 8)
                            Divider()
                        }
                    }
                }
            }
        }
        .alert("¿Vaciar el archivo?", isPresented: $showClearConfirm) {
            Button("Cancelar", role: .cancel) { }
            Button("Vaciar", role: .destructive) { store.clearArchive() }
        } message: {
            Text("Las tareas archivadas se borrarán permanentemente.")
        }
        .alert("¿Borrar permanentemente?",
               isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } })) {
            Button("Cancelar", role: .cancel) { pendingDeleteId = nil }
            Button("Borrar", role: .destructive) {
                if let id = pendingDeleteId { store.deleteArchived(id: id) }
                pendingDeleteId = nil
            }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
    }

    @ViewBuilder
    private func row(for task: TodoTask) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(settings.categoryColor(task.category))
                .frame(width: 4, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(true)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                if task.archivedAt > 0 {
                    Text(dateString(task.archivedAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if settings.showPriorityIcons {
                PriorityBadge(priority: task.priority)
            }
            Button {
                store.restoreArchived(id: task.id)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Restaurar")

            Button(role: .destructive) {
                if settings.confirmDelete {
                    pendingDeleteId = task.id
                } else {
                    store.deleteArchived(id: task.id)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Borrar permanentemente")
        }
        .padding(.vertical, 4)
    }

    private func dateString(_ ms: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000.0)
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}
