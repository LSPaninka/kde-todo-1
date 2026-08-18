import SwiftUI

/// Sheet para crear / editar / borrar un worklog Jira.
struct JiraEditSheet: View {
    @ObservedObject var store: JiraWorklogStore
    /// Segunda instancia (o `nil` si está deshabilitada).  Cuando existe,
    /// el modal muestra tabs "Jira 1 / Jira 2" al crear.
    var store2: JiraWorklogStore?
    /// Instancia activa al abrir.  Al editar queda fija.
    var initialInstanceId: Int = 1
    @ObservedObject var settings: AppSettings
    /// Cerramos vía Environment.dismiss; el padre usa
    /// `.sheet(item:)` así el item se inyecta sincrónicamente y nunca
    /// queda en blanco la primera vez.
    @Environment(\.dismiss) private var dismiss

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

    /// Instancia seleccionada por el tab (1 o 2).
    @State private var activeInstance: Int
    /// Criterio de orden del picker de issues.
    enum PickerSort: String, CaseIterable, Identifiable {
        case hoursDesc, key, status
        var id: String { rawValue }
        var label: String {
            switch self {
            case .hoursDesc: return "Horas ↓"
            case .key:       return "Código"
            case .status:    return "Estado"
            }
        }
    }
    @State private var pickerSort: PickerSort = .hoursDesc

    init(store: JiraWorklogStore,
         store2: JiraWorklogStore? = nil,
         initialInstanceId: Int = 1,
         settings: AppSettings,
         editing: JiraWorklog?,
         start: Date,
         end: Date,
         onSaved: @escaping () -> Void,
         onDeleted: @escaping () -> Void) {
        self.store = store
        self.store2 = store2
        self.initialInstanceId = initialInstanceId
        self.settings = settings
        self.editing = editing
        self._activeInstance = State(initialValue: initialInstanceId)
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

    /// Store de la instancia activa — todas las llamadas (picker,
    /// create/update/delete) pasan por acá.
    private var activeStore: JiraWorklogStore {
        (activeInstance == 2 ? store2 : store) ?? store
    }
    /// `true` cuando hay una segunda instancia y estamos creando (al
    /// editar el modal queda fijo en la instancia del bloque).
    private var showsTabs: Bool { store2 != nil && !isEdit }

    private var filteredIssues: [JiraAssignableIssue] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        var rows = activeStore.assignableIssues
        if !q.isEmpty {
            rows = rows.filter { iss in
                let hay = "\(iss.key) \(iss.summary) \(iss.issuetype) \(iss.status)".lowercased()
                return hay.contains(q)
            }
        }
        switch pickerSort {
        case .hoursDesc:
            return rows.sorted { $0.remainingSec > $1.remainingSec }
        case .key:
            return rows.sorted { $0.key.localizedCompare($1.key) == .orderedAscending }
        case .status:
            return rows.sorted { $0.status.localizedCompare($1.status) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isEdit ? "Editar worklog" : "Nuevo worklog")
                    .font(.title3).bold()
                Spacer()
                Button(action: { dismiss() }) {
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
                // Tabs de instancia — sólo si la segunda Jira está activa.
                if showsTabs {
                    Picker("", selection: $activeInstance) {
                        Text("Jira 1").tag(1)
                        Text("Jira 2").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Filtrar issues por texto…", text: $search)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $pickerSort) {
                        ForEach(PickerSort.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                    .help("Ordenar la lista de issues")
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
                Button("Cancelar") { dismiss() }
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
        // Cambiar de instancia recarga el picker contra su propio store
        // y limpia la selección (una issue de Jira 1 no existe en Jira 2).
        .onChange(of: activeInstance) {
            selectedIssueKey = ""
            selectedIssueSummary = ""
            if !isEdit { refreshPicker() }
        }
        // Cuando los +/- cambian start/endDate, refrescamos el texto
        // pero sólo si el campo no está siendo editado (para no
        // mover el cursor del usuario mientras tipea).
        .onChange(of: startDate) { _, newValue in
            if !startTimeFocused { startTimeText = Self.format(newValue) }
        }
        .onChange(of: endDate) { _, newValue in
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
            .onChange(of: isStart ? startTimeFocused : endTimeFocused) { _, focused in
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
        activeStore.fetchAssignableIssues { result in
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
            activeStore.updateWorklog(
                issueKey: e.issueKey,
                worklogId: e.id,
                started: startDate,
                durationSec: durationSec,
                comment: comment
            ) { result in
                loading = false
                switch result {
                case .success:
                    dismiss()
                    onSaved()
                case .failure(let err):
                    status = (err.message, true)
                }
            }
        } else {
            activeStore.createWorklog(
                issueKey: selectedIssueKey,
                started: startDate,
                durationSec: durationSec,
                comment: comment
            ) { result in
                loading = false
                switch result {
                case .success:
                    dismiss()
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
        activeStore.deleteWorklog(issueKey: e.issueKey, worklogId: e.id) { result in
            loading = false
            switch result {
            case .success:
                dismiss()
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
