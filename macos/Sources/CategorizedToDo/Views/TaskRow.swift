import SwiftUI

/// One task row, with expand-collapse showing description and subtasks.
struct TaskRow: View {
    let task: TodoTask
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings

    @State private var expanded: Bool = false
    @State private var newSubtaskTitle: String = ""
    @State private var newSubtaskPriority: Priority = .m
    @State private var showEditSheet: Bool = false
    @State private var subtaskBeingEdited: Subtask? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                // Category color stripe
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(settings.categoryColor(task.category))
                    .frame(width: 4, height: 22)

                Toggle(isOn: Binding(
                    get: { task.done },
                    set: { _ in store.toggleTaskDone(id: task.id) }
                )) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()

                Text(task.title)
                    .strikethrough(task.done)
                    .foregroundColor(task.done ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if settings.showPriorityIcons {
                    PriorityBadge(priority: task.priority)
                }

                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .help(expanded ? "Contraer" : "Expandir")

                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Editar")

                Button {
                    store.archiveTask(id: task.id)
                } label: {
                    Image(systemName: "archivebox")
                }
                .buttonStyle(.borderless)
                .help("Archivar")
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !task.description.isEmpty {
                        Text(task.description)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(.leading, 16)
                    }

                    // Subtasks
                    ForEach(task.subtasks) { sub in
                        HStack(spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { sub.done },
                                set: { _ in store.toggleSubtaskDone(taskId: task.id, subId: sub.id) }
                            )) { EmptyView() }
                            .toggleStyle(.checkbox)
                            .labelsHidden()

                            Text(sub.title)
                                .strikethrough(sub.done)
                                .foregroundColor(sub.done ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if settings.showPriorityIcons {
                                PriorityBadge(priority: sub.priority, compact: true)
                            }

                            Button {
                                subtaskBeingEdited = sub
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help("Editar subtarea")

                            Button(role: .destructive) {
                                store.removeSubtask(taskId: task.id, subId: sub.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Eliminar subtarea")
                        }
                        .padding(.leading, 16)
                    }

                    // Inline add-subtask row
                    HStack(spacing: 6) {
                        TextField("Nueva subtarea…", text: $newSubtaskTitle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addSubtask)
                        PriorityPicker(priority: $newSubtaskPriority)
                        Button(action: addSubtask) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.leading, 16)
                }
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showEditSheet) {
            TaskEditSheet(store: store, settings: settings, editing: task) {
                showEditSheet = false
            }
        }
        .sheet(item: $subtaskBeingEdited) { sub in
            SubtaskEditSheet(store: store,
                             taskId: task.id,
                             editing: sub) {
                subtaskBeingEdited = nil
            }
        }
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.addSubtask(taskId: task.id, title: trimmed, priority: newSubtaskPriority)
        newSubtaskTitle = ""
        newSubtaskPriority = .m
    }
}
