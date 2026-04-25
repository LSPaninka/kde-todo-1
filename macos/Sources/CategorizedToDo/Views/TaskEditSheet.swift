import SwiftUI

struct TaskEditSheet: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings

    /// nil → creating a new task; non-nil → editing.
    let editing: TodoTask?
    var defaultCategory: Int = 0
    var onClose: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var category: Int = 0
    @State private var priority: Priority = .m

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? "Nueva tarea" : "Editar tarea")
                .font(.title2).bold()

            Form {
                TextField("Título", text: $title)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Descripción")
                    TextEditor(text: $description)
                        .frame(minHeight: 80, maxHeight: 160)
                        .border(Color.secondary.opacity(0.3))
                }

                Picker("Categoría", selection: $category) {
                    ForEach(0..<settings.categoryCount, id: \.self) { i in
                        HStack {
                            Circle().fill(settings.categoryColor(i)).frame(width: 10, height: 10)
                            Text(settings.categoryName(i))
                        }.tag(i)
                    }
                }

                Picker("Prioridad", selection: $priority) {
                    ForEach(Priority.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancelar", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Crear" : "Guardar") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear(perform: loadInitial)
    }

    private func loadInitial() {
        if let t = editing {
            title = t.title
            description = t.description
            category = max(0, min(settings.categoryCount - 1, t.category))
            priority = t.priority
        } else {
            category = max(0, min(settings.categoryCount - 1, defaultCategory))
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let t = editing {
            store.updateTask(id: t.id,
                             title: trimmed,
                             description: description,
                             category: category,
                             priority: priority)
        } else {
            store.addTask(title: trimmed,
                          category: category,
                          priority: priority,
                          description: description)
        }
        onClose()
    }
}
