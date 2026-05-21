import SwiftUI

/// Sheet para crear / editar / borrar una time entry de Clockify.
struct ClockifyEditSheet: View {
    @ObservedObject var store: ClockifyStore
    @Binding var presented: Bool

    /// `nil` = crear; seteado = editar.
    let editing: ClockifyEntry?

    @State var startDate: Date
    @State var endDate: Date
    @State var description: String
    @State var selectedProjectId: String
    @State var selectedTagIds: [String]
    @State var billable: Bool

    @State private var loading: Bool = false
    @State private var status: (text: String, isError: Bool) = ("", false)

    let onSaved: () -> Void
    let onDeleted: () -> Void

    init(store: ClockifyStore,
         presented: Binding<Bool>,
         editing: ClockifyEntry?,
         start: Date,
         end: Date,
         defaultProjectId: String,
         defaultBillable: Bool,
         onSaved: @escaping () -> Void,
         onDeleted: @escaping () -> Void) {
        self.store = store
        self._presented = presented
        self.editing = editing
        self._startDate = State(initialValue: start)
        self._endDate = State(initialValue: end)
        self._description = State(initialValue: editing?.description ?? "")
        self._selectedProjectId = State(initialValue: editing?.projectId ?? defaultProjectId)
        self._selectedTagIds = State(initialValue: editing?.tagIds ?? [])
        self._billable = State(initialValue: editing?.billable ?? defaultBillable)
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    private var isEdit: Bool { editing != nil }

    private var durationSec: Int {
        max(60, Int(endDate.timeIntervalSince(startDate)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isEdit ? "Editar entrada Clockify" : "Nueva entrada Clockify")
                    .font(.title3).bold()
                Spacer()
                Button(action: { presented = false }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(loading)
            }

            HStack(alignment: .center, spacing: 12) {
                Text(formatHeaderDate(startDate)).font(.headline)
                Spacer()
                timePicker("Inicio:", date: $startDate, isStart: true)
                timePicker("Fin:", date: $endDate, isStart: false)
            }
            Text("Duración: \(CalendarBlock.fmtDur(durationSec))")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Divider()

            Text("Proyecto").opacity(0.7).font(.caption)
            HStack(spacing: 8) {
                if let p = store.projects.first(where: { $0.id == selectedProjectId }),
                   let c = Color(hex: p.color) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(c)
                        .frame(width: 14, height: 14)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.secondary.opacity(0.4))
                        .frame(width: 14, height: 14)
                }
                Picker("", selection: $selectedProjectId) {
                    Text("(sin proyecto)").tag("")
                    ForEach(store.projects) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Text("Tags" + (store.tags.isEmpty ? "  (no hay tags)" : ""))
                .opacity(0.7).font(.caption)
            if !store.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(store.tags) { t in
                            let isOn = selectedTagIds.contains(t.id)
                            Text(t.name)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(isOn ? Color.accentColor : Color.gray.opacity(0.15))
                                .foregroundColor(isOn ? .white : .primary)
                                .clipShape(Capsule())
                                .onTapGesture {
                                    if let i = selectedTagIds.firstIndex(of: t.id) {
                                        selectedTagIds.remove(at: i)
                                    } else {
                                        selectedTagIds.append(t.id)
                                    }
                                }
                        }
                    }
                }
            }

            Toggle("Facturable (billable)", isOn: $billable)

            Text("Descripción").opacity(0.7).font(.caption)
            TextEditor(text: $description)
                .font(.body)
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            if !status.text.isEmpty {
                Text(status.text)
                    .font(.callout)
                    .foregroundColor(status.isError ? .red : .green)
            }

            HStack {
                if loading {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if isEdit {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                    .disabled(loading)
                }
                Button("Cancelar") { presented = false }
                    .disabled(loading)
                Button(isEdit ? "Guardar" : "Crear", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || endDate <= startDate)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 480)
        .onAppear {
            // Asegurarnos de tener proyectos / tags cargados.
            store.ensureContext { _ in }
        }
    }

    private func timePicker(_ label: String, date: Binding<Date>, isStart: Bool) -> some View {
        HStack(spacing: 2) {
            Text(label).opacity(0.7)
            Button {
                let next = date.wrappedValue.addingTimeInterval(-30 * 60)
                if isStart || next > startDate { date.wrappedValue = next }
            } label: {
                Image(systemName: "minus.circle")
            }.buttonStyle(.borderless)
            Text(formatTime(date.wrappedValue))
                .font(.system(.body, design: .monospaced))
                .frame(width: 52)
            Button {
                let next = date.wrappedValue.addingTimeInterval(30 * 60)
                if !isStart || next < endDate { date.wrappedValue = next }
            } label: {
                Image(systemName: "plus.circle")
            }.buttonStyle(.borderless)
        }
    }

    private func save() {
        loading = true
        status = (isEdit ? "Guardando…" : "Creando…", false)
        if let e = editing {
            store.updateEntry(
                id: e.id,
                start: startDate,
                end: endDate,
                description: description,
                projectId: selectedProjectId,
                tagIds: selectedTagIds,
                billable: billable
            ) { result in
                loading = false
                switch result {
                case .success:
                    presented = false
                    onSaved()
                case .failure(let err):
                    status = (err.message, true)
                }
            }
        } else {
            store.createEntry(
                start: startDate,
                end: endDate,
                description: description,
                projectId: selectedProjectId,
                tagIds: selectedTagIds,
                billable: billable
            ) { result in
                loading = false
                switch result {
                case .success:
                    presented = false
                    onSaved()
                case .failure(let err):
                    status = (err.message, true)
                }
            }
        }
    }

    private func delete() {
        guard let e = editing else { return }
        loading = true
        status = ("Eliminando…", false)
        store.deleteEntry(id: e.id) { result in
            loading = false
            switch result {
            case .success:
                presented = false
                onDeleted()
            case .failure(let err):
                status = (err.message, true)
            }
        }
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func formatHeaderDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE d/MM/yyyy"
        return f.string(from: d).capitalized
    }
}
