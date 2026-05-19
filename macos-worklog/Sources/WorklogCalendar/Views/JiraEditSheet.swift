import SwiftUI

/// Sheet para crear / editar / borrar un worklog Jira.
struct JiraEditSheet: View {
    @ObservedObject var store: JiraWorklogStore
    @Binding var presented: Bool

    /// Si `editing == nil` estamos creando; si está seteado estamos
    /// editando ese worklog.
    let editing: JiraWorklog?

    @State var startDate: Date
    @State var endDate: Date
    @State var comment: String
    @State private var selectedIssueKey: String = ""
    @State private var selectedIssueSummary: String = ""
    @State private var search: String = ""
    @State private var loading: Bool = false
    @State private var status: (text: String, isError: Bool) = ("", false)

    let onSaved: () -> Void
    let onDeleted: () -> Void

    init(store: JiraWorklogStore,
         presented: Binding<Bool>,
         editing: JiraWorklog?,
         start: Date,
         end: Date,
         onSaved: @escaping () -> Void,
         onDeleted: @escaping () -> Void) {
        self.store = store
        self._presented = presented
        self.editing = editing
        self._startDate = State(initialValue: start)
        self._endDate = State(initialValue: end)
        self._comment = State(initialValue: editing?.comment ?? "")
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    private var isEdit: Bool { editing != nil }

    private var durationSec: Int {
        max(60, Int(endDate.timeIntervalSince(startDate)))
    }

    private var filteredIssues: [JiraAssignableIssue] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return store.assignableIssues }
        return store.assignableIssues.filter { iss in
            let hay = "\(iss.key) \(iss.summary) \(iss.issuetype) \(iss.status)".lowercased()
            return hay.contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isEdit ? "Editar worklog" : "Nuevo worklog")
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
                Text("(\(CalendarBlock.fmtDur(durationSec)))").opacity(0.7)
            }

            Divider()

            if isEdit, let e = editing {
                Text("Issue").opacity(0.7).font(.caption)
                Text("[\(e.issueKey)] \(e.issueSummary)")
                    .font(.headline)
            } else {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Filtrar issues por texto…", text: $search)
                        .textFieldStyle(.roundedBorder)
                    Button(action: refreshPicker) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
                pickerList
                if !selectedIssueKey.isEmpty {
                    Text("Seleccionada: \(selectedIssueKey) — \(selectedIssueSummary)")
                        .font(.caption).opacity(0.85)
                }
            }

            Text("Comentario").opacity(0.7).font(.caption)
            TextEditor(text: $comment)
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
                    .disabled(loading || (!isEdit && selectedIssueKey.isEmpty) || endDate <= startDate)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { if !isEdit { refreshPicker() } }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var pickerList: some View {
        List(filteredIssues) { iss in
            HStack(spacing: 8) {
                Text(iss.key)
                    .font(.system(.body, design: .monospaced)).bold()
                    .frame(width: 92, alignment: .leading)
                Text(iss.summary).lineLimit(1)
                Spacer()
                Text("\(iss.issuetype) · \(iss.status)")
                    .font(.caption).opacity(0.6)
            }
            .padding(.vertical, 2)
            .background(selectedIssueKey == iss.key
                        ? Color.accentColor.opacity(0.25)
                        : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedIssueKey = iss.key
                selectedIssueSummary = iss.summary
            }
        }
        .frame(minHeight: 160, maxHeight: 220)
        .overlay {
            if filteredIssues.isEmpty && !loading {
                Text("Sin resultados. Ajustá el JQL en Preferencias → Jira.")
                    .font(.caption).opacity(0.55)
            }
            if loading {
                ProgressView().controlSize(.small)
            }
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

    // MARK: - Actions

    private func refreshPicker() {
        loading = true
        store.fetchAssignableIssues { result in
            loading = false
            if case .failure(let err) = result {
                status = (err.message, true)
            }
        }
    }

    private func save() {
        loading = true
        status = (isEdit ? "Guardando…" : "Creando…", false)
        if let e = editing {
            store.updateWorklog(
                issueKey: e.issueKey,
                worklogId: e.id,
                started: startDate,
                durationSec: durationSec,
                comment: comment
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
            store.createWorklog(
                issueKey: selectedIssueKey,
                started: startDate,
                durationSec: durationSec,
                comment: comment
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
        store.deleteWorklog(issueKey: e.issueKey, worklogId: e.id) { result in
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
