import SwiftUI

/// Sheet para crear / editar / borrar un worklog Jira.
struct JiraEditSheet: View {
    @ObservedObject var store: JiraWorklogStore
    @ObservedObject var settings: AppSettings
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
    /// Lo que el usuario está tipeando en los campos de hora.  Se
    /// re-sincroniza desde `start/endDate` cuando el campo no tiene
    /// foco (así los +/- los actualizan pero el cursor no se mueve
    /// mientras estás escribiendo).
    @State private var startTimeText: String = ""
    @State private var endTimeText: String = ""
    @FocusState private var startTimeFocused: Bool
    @FocusState private var endTimeFocused: Bool

    let onSaved: () -> Void
    let onDeleted: () -> Void

    init(store: JiraWorklogStore,
         settings: AppSettings,
         presented: Binding<Bool>,
         editing: JiraWorklog?,
         start: Date,
         end: Date,
         onSaved: @escaping () -> Void,
         onDeleted: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self._presented = presented
        self.editing = editing
        self._startDate = State(initialValue: start)
        self._endDate = State(initialValue: end)
        self._comment = State(initialValue: editing?.comment ?? "")
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self._startTimeText = State(initialValue: Self.format(start))
        self._endTimeText = State(initialValue: Self.format(end))
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
            }
            // La duración va en su propia línea para que cambiar
            // "3h" → "3h 30m" no empuje los +/- de la fila de arriba.
            Text("Duración: \(CalendarBlock.fmtDur(durationSec))")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

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
                    .keyboardShortcut(.cancelAction)   // ⎋ cierra el sheet
                    .disabled(loading)
                Button(isEdit ? "Guardar" : "Crear", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || (!isEdit && selectedIssueKey.isEmpty) || endDate <= startDate)
            }
        }
        .padding(16)
        .frame(
            minWidth: CGFloat(max(420, settings.modalWidth)),
            minHeight: CGFloat(max(360, settings.modalHeight))
        )
        .onAppear { if !isEdit { refreshPicker() } }
        // Cuando los +/- cambian start/endDate, refrescamos el texto
        // pero sólo si el campo no está siendo editado (para no
        // mover el cursor del usuario mientras tipea).
        .onChange(of: startDate) { newValue in
            if !startTimeFocused { startTimeText = Self.format(newValue) }
        }
        .onChange(of: endDate) { newValue in
            if !endTimeFocused { endTimeText = Self.format(newValue) }
        }
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
                Text(pickerTrailing(iss))
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

    private func pickerTrailing(_ iss: JiraAssignableIssue) -> String {
        var parts: [String] = []
        if !iss.issuetype.isEmpty { parts.append(iss.issuetype) }
        if !iss.status.isEmpty    { parts.append(iss.status) }
        if iss.remainingSec > 0   { parts.append(CalendarBlock.fmtDur(iss.remainingSec)) }
        return parts.joined(separator: " · ")
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
            timeTextField(isStart: isStart)
            Button {
                let next = date.wrappedValue.addingTimeInterval(30 * 60)
                if !isStart || next < endDate { date.wrappedValue = next }
            } label: {
                Image(systemName: "plus.circle")
            }.buttonStyle(.borderless)
        }
    }

    /// TextField "HH:MM" — el usuario puede tipear directamente.  En
    /// `onSubmit` parseamos; si la entrada es inválida, revertimos al
    /// valor formateado actual.
    @ViewBuilder
    private func timeTextField(isStart: Bool) -> some View {
        let textBinding = isStart ? $startTimeText : $endTimeText
        TextField("HH:MM",
                  text: textBinding,
                  prompt: Text("HH:MM"))
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 60)
            .textFieldStyle(.roundedBorder)
            .focused(isStart ? $startTimeFocused : $endTimeFocused)
            .onSubmit { applyTimeText(isStart: isStart) }
            .onChange(of: isStart ? startTimeFocused : endTimeFocused) { focused in
                // Al perder foco: aplicamos lo que esté tipeado, igual
                // que onSubmit (`Tab` / clic afuera vale).
                if !focused { applyTimeText(isStart: isStart) }
            }
    }

    /// Parsea `HH:MM`, valida 0–23 / 0–59 y aplica al `start/endDate`
    /// preservando la fecha.  Si es inválido o invierte el rango,
    /// revierte el texto al valor formateado actual.
    private func applyTimeText(isStart: Bool) {
        let text = (isStart ? startTimeText : endTimeText)
            .trimmingCharacters(in: .whitespaces)
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hh = Int(parts[0]), let mm = Int(parts[1]),
              (0...23).contains(hh), (0...59).contains(mm) else {
            bounce(isStart: isStart)
            return
        }
        let base = isStart ? startDate : endDate
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        guard let newDate = cal.date(bySettingHour: hh, minute: mm, second: 0, of: base) else {
            bounce(isStart: isStart)
            return
        }
        if isStart {
            guard newDate < endDate else { bounce(isStart: true); return }
            startDate = newDate
            startTimeText = Self.format(newDate)
        } else {
            guard newDate > startDate else { bounce(isStart: false); return }
            endDate = newDate
            endTimeText = Self.format(newDate)
        }
    }

    private func bounce(isStart: Bool) {
        if isStart { startTimeText = Self.format(startDate) }
        else       { endTimeText   = Self.format(endDate) }
    }

    static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
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

    private func formatHeaderDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE d/MM/yyyy"
        return f.string(from: d).capitalized
    }
}
