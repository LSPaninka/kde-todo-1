import SwiftUI

/// Tab content for one category. Quick-add row at the top, list below,
/// import / export buttons in the header.
struct CategoryView: View {
    let categoryIndex: Int
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings

    @State private var newTitle: String = ""
    @State private var newPriority: Priority = .m
    @State private var showAddSheet: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var showImportSheet: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            header

            // Inline quick-add
            HStack(spacing: 6) {
                TextField("Nueva tarea…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(quickAdd)
                PriorityPicker(priority: $newPriority)
                Button(action: quickAdd) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Nueva…") { showAddSheet = true }
                    .controlSize(.small)
            }
            .padding(.horizontal, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let items = store.tasksFor(category: categoryIndex)
                    if items.isEmpty {
                        Text("No hay tareas en esta categoría.")
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
        .sheet(isPresented: $showAddSheet) {
            TaskEditSheet(store: store,
                          settings: settings,
                          editing: nil,
                          defaultCategory: categoryIndex) {
                showAddSheet = false
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(jsonText: store.exportCategoryJson(categoryIndex)) {
                showExportSheet = false
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportSheet(store: store, category: categoryIndex) {
                showImportSheet = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(settings.categoryColor(categoryIndex))
                .frame(width: 14, height: 14)
            Text(settings.categoryName(categoryIndex))
                .font(.headline)
            Text("(\(store.pendingCount(category: categoryIndex)))")
                .foregroundColor(.secondary)
                .monospacedDigit()
            Spacer()
            Button {
                showImportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Importar JSON")

            Button {
                showExportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Exportar JSON")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func quickAdd() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.addTask(title: trimmed, category: categoryIndex, priority: newPriority)
        newTitle = ""
        newPriority = .m
    }
}
