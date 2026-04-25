import SwiftUI

struct SubtaskEditSheet: View {
    @ObservedObject var store: TaskStore
    let taskId: Int
    let editing: Subtask
    var onClose: () -> Void

    @State private var title: String = ""
    @State private var priority: Priority = .m

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Editar subtarea").font(.title2).bold()

            Form {
                TextField("Título", text: $title)
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
                Button("Guardar") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            title = editing.title
            priority = editing.priority
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.updateSubtask(taskId: taskId, subId: editing.id,
                            title: trimmed, priority: priority)
        onClose()
    }
}
