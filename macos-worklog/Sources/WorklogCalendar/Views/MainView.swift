import SwiftUI

/// Pantalla principal de la app.  Cabecera (modo + navegación de semana
/// + refresh + diag) + `CalendarView` + footer con totales y botón de
/// sync Jira→Clockify.
struct MainView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var jira: JiraWorklogStore
    @ObservedObject var clockify: ClockifyStore

    @State private var weekStart: Date = sundayOf(Date())

    // Sheets.
    @State private var jiraSheet: Bool = false
    @State private var jiraSheetSelection: (editing: JiraWorklog?, start: Date, end: Date)? = nil

    @State private var clockifySheet: Bool = false
    @State private var clockifySheetSelection: (editing: ClockifyEntry?, start: Date, end: Date)? = nil

    @State private var showSettings: Bool = false
    @State private var showDebug: Bool = false

    // Status banner (auto-clear).
    @State private var statusBanner: (text: String, isError: Bool) = ("", false)
    @State private var bannerClearTask: DispatchWorkItem? = nil

    // Proyecto destino del botón "Jira → Clockify".  Se inicializa con
    // el default de Preferencias y se persiste de vuelta cuando el
    // usuario elige otro desde el ComboBox del footer.  Tenerlo acá
    // (y no leer Preferencias directo en `syncJiraIntoClockify`) hace
    // que muchos workspaces que tienen "project required" activado
    // dejen de devolver HTTP 400 sin tener que volver a Preferencias.
    @State private var syncProjectId: String = ""

    private var jiraBlocks: [CalendarBlock] {
        jira.worklogs.map { CalendarBlock(jira: $0, showSummary: settings.showIssueSummary) }
    }
    private var clockifyBlocks: [CalendarBlock] {
        clockify.entries.map { CalendarBlock(clockify: $0) }
    }

    /// Los gauges se muestran sólo cuando vale la pena: hay datos de
    /// Jira (modo Jira o combinado), el calendario está en 9h y el
    /// usuario los habilitó en preferencias.
    private var showGauges: Bool {
        guard settings.showSprintGauges else { return false }
        guard settings.viewMode == .h9 else { return false }
        return settings.source == .jira || settings.source == .jiraClockify
    }

    var body: some View {
        VStack(spacing: 6) {
            headerBar
            statusLine
            CalendarView(
                weekStart: weekStart,
                jiraBlocks: jiraBlocks,
                clockifyBlocks: clockifyBlocks,
                source: settings.source,
                viewMode: settings.viewMode,
                dailyTargetHours: settings.dailyTargetHours,
                onCreateJira: { sel in openJiraSheet(editing: nil,
                                                    start: msDate(sel.startMs),
                                                    end:   msDate(sel.endMs)) },
                onCreateClockify: { sel in openClockifySheet(editing: nil,
                                                             start: msDate(sel.startMs),
                                                             end:   msDate(sel.endMs)) },
                onEditJira: { block in
                    if let w = jira.worklogs.first(where: { "jira-\($0.id)" == block.id }) {
                        openJiraSheet(editing: w,
                                      start: Date(timeIntervalSince1970: w.startedMs / 1000),
                                      end:   Date(timeIntervalSince1970: (w.startedMs + Double(w.durationSec) * 1000) / 1000))
                    }
                },
                onEditClockify: { block in
                    if let e = clockify.entries.first(where: { "clockify-\($0.id)" == block.id }) {
                        openClockifySheet(editing: e,
                                          start: Date(timeIntervalSince1970: e.startedMs / 1000),
                                          end:   Date(timeIntervalSince1970: (e.startedMs + Double(e.durationSec) * 1000) / 1000))
                    }
                },
                onMoveJira:     { block, newStartMs, newDur in
                    applyJira(block, newStartMs: newStartMs, newDurationSec: newDur)
                },
                onMoveClockify: { block, newStartMs, newDur in
                    applyClockify(block, newStartMs: newStartMs, newDurationSec: newDur)
                },
                onDuplicateJira:     { block in duplicateJira(block) },
                onDuplicateClockify: { block in duplicateClockify(block) }
            )
            .frame(maxHeight: .infinity)

            if showGauges {
                Divider()
                SprintGauges(jira: jira)
            }

            footerBar
        }
        .padding(8)
        .onAppear {
            syncProjectId = settings.clockifyDefaultProjectId
            syncNow()
        }
        .onChange(of: settings.clockifyDefaultProjectId) { _ in
            // Si editan el default en Preferencias, reflejarlo acá.
            syncProjectId = settings.clockifyDefaultProjectId
        }
        // Cambios en Preferencias del bloque "Sprint (experimental)" →
        // re-fetch sin esperar al ↻.
        .onChange(of: settings.sprintStrategy)   { _ in if showGauges { jira.fetchSprintInfo { _ in } } }
        .onChange(of: settings.sprintField)      { _ in if showGauges { jira.fetchSprintInfo { _ in } } }
        .onChange(of: settings.sprintBoardId)    { _ in if showGauges { jira.fetchSprintInfo { _ in } } }
        .onChange(of: settings.remainingMode)    { _ in if showGauges { jira.fetchSprintInfo { _ in } } }
        // Si recién encienden los gauges, traigamos los datos.
        .onChange(of: settings.showSprintGauges) { on in if on { jira.fetchSprintInfo { _ in } } }
        .onReceive(NotificationCenter.default.publisher(for: .worklogOpenPreferences)) { _ in
            showSettings = true
        }
        // Jira sheet
        .sheet(isPresented: $jiraSheet) {
            if let sel = jiraSheetSelection {
                JiraEditSheet(
                    store: jira,
                    presented: $jiraSheet,
                    editing: sel.editing,
                    start: sel.start,
                    end: sel.end,
                    onSaved: { syncNow() },
                    onDeleted: { syncNow() }
                )
            }
        }
        // Clockify sheet
        .sheet(isPresented: $clockifySheet) {
            if let sel = clockifySheetSelection {
                ClockifyEditSheet(
                    store: clockify,
                    presented: $clockifySheet,
                    editing: sel.editing,
                    start: sel.start,
                    end: sel.end,
                    defaultProjectId: settings.clockifyDefaultProjectId,
                    defaultBillable: settings.clockifyBillableDefault,
                    onSaved: { syncNow() },
                    onDeleted: { syncNow() }
                )
            }
        }
        // Preferences
        .sheet(isPresented: $showSettings) {
            SettingsWindow(settings: settings, jira: jira, clockify: clockify, presented: $showSettings)
        }
        // Debug overlay
        .sheet(isPresented: $showDebug) {
            DebugSheet(jira: jira, clockify: clockify, presented: $showDebug)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
            Text(headerTitle).font(.title2).bold()

            Spacer().frame(width: 8)

            Button(action: { goWeek(-1) }) {
                Image(systemName: "chevron.left")
            }
            Button("Hoy") {
                weekStart = MainView.sundayOf(Date())
                syncNow()
            }
            Button(action: { goWeek(1) }) {
                Image(systemName: "chevron.right")
            }

            Text(formatWeekLabel(weekStart))
                .font(.headline)
                .frame(maxWidth: .infinity)

            Picker("", selection: $settings.viewMode) {
                Text("Modo 9h").tag(ViewHourMode.h9)
                Text("Modo 24h").tag(ViewHourMode.h24)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .labelsHidden()

            Button {
                syncNow()
            } label: {
                if jira.loading || clockify.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(jira.loading || clockify.loading)

            Button(action: { showDebug = true }) {
                Image(systemName: "info.circle")
            }

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
            }
        }
    }

    private var headerTitle: String {
        switch settings.source {
        case .jira:         return "Jira Worklog"
        case .jiraClockify: return "Jira / Clockify"
        case .clockify:     return "Clockify"
        }
    }

    /// El status text reserva espacio vertical siempre — usamos un
    /// non-breaking space cuando no hay mensaje y opacidad 0, para que
    /// el calendario no salte arriba/abajo cada vez que aparece o se
    /// limpia un mensaje.
    private var statusLine: some View {
        let text: String = {
            if !statusBanner.text.isEmpty { return statusBanner.text }
            if jira.loading { return "Jira: cargando…" }
            if clockify.loading { return "Clockify: cargando…" }
            if !jira.lastError.isEmpty { return "Jira: \(jira.lastError)" }
            if !clockify.lastError.isEmpty { return "Clockify: \(clockify.lastError)" }
            return ""
        }()
        let isErr: Bool = {
            if !statusBanner.text.isEmpty { return statusBanner.isError }
            return !jira.lastError.isEmpty || !clockify.lastError.isEmpty
        }()
        return Text(text.isEmpty ? "\u{00A0}" : text)
            .font(.caption)
            .foregroundColor(isErr ? .red : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(text.isEmpty ? 0 : 1)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 8) {
            Text(footerTotals).font(.caption).opacity(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            if settings.source == .jiraClockify {
                projectPicker
                Button {
                    syncJiraIntoClockify()
                } label: {
                    Label("Jira → Clockify", systemImage: "doc.on.doc")
                }
            }

            Picker("Fuente", selection: $settings.source) {
                ForEach(WorklogSource.allCases) { src in
                    Text(src.displayName).tag(src)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
            .onChange(of: settings.source) { _ in syncNow() }
        }
    }

    /// ComboBox de proyecto + swatch de color (sólo modo combinado).
    /// Persiste el `id` elegido en `settings.clockifyDefaultProjectId`
    /// para que sobreviva al cierre de la app.
    @ViewBuilder
    private var projectPicker: some View {
        let swatchColor: Color? = {
            guard let p = clockify.projects.first(where: { $0.id == syncProjectId })
            else { return nil }
            return Color(hex: p.color)
        }()
        RoundedRectangle(cornerRadius: 2)
            .fill(swatchColor ?? Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .frame(width: 12, height: 12)
        Picker("", selection: $syncProjectId) {
            Text("(sin proyecto)").tag("")
            ForEach(clockify.projects) { p in
                Text(p.name).tag(p.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 200)
        .help("Proyecto destino del sync Jira → Clockify")
        .onChange(of: syncProjectId) { newValue in
            // Persistir para próximas sesiones.
            settings.clockifyDefaultProjectId = newValue
        }
    }

    private var footerTotals: String {
        var parts: [String] = []
        if settings.source == .jira || settings.source == .jiraClockify {
            let total = jira.worklogs.reduce(0) { $0 + $1.durationSec }
            parts.append(String(format: "Jira: %dh %dm", total / 3600, (total % 3600) / 60))
        }
        if settings.source == .clockify || settings.source == .jiraClockify {
            let total = clockify.entries.reduce(0) { $0 + $1.durationSec }
            parts.append(String(format: "Clockify: %dh %dm", total / 3600, (total % 3600) / 60))
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - Actions

    private func syncNow() {
        if settings.source == .jira || settings.source == .jiraClockify {
            jira.fetchWeek(starting: weekStart)
            if showGauges {
                jira.fetchSprintInfo { _ in }
            }
        }
        if settings.source == .clockify || settings.source == .jiraClockify {
            clockify.fetchWeek(starting: weekStart)
        }
    }

    private func syncJiraIntoClockify() {
        setStatus("Copiando Jira → Clockify…", isError: false, sticky: true)
        let pid = syncProjectId
        let bill = settings.clockifyBillableDefault
        clockify.syncFromJira(jira.worklogs, defaultProjectId: pid, defaultBillable: bill) { created, skipped, failed in
            setStatus(
                "Sync terminado: \(created) creadas, \(skipped) ya existían, \(failed) fallaron.",
                isError: failed > 0
            )
            clockify.fetchWeek(starting: weekStart)
        }
    }

    /// Punto único de entrada para mover / redimensionar un bloque Jira.
    /// Preserva el comentario; cambia `started` y `durationSec`.
    private func applyJira(_ block: CalendarBlock,
                           newStartMs: Double,
                           newDurationSec: Int) {
        guard let w = jira.worklogs.first(where: { "jira-\($0.id)" == block.id }) else { return }
        let newStart = Date(timeIntervalSince1970: newStartMs / 1000)
        jira.updateWorklog(
            issueKey: w.issueKey,
            worklogId: w.id,
            started: newStart,
            durationSec: newDurationSec,
            comment: w.comment
        ) { result in
            switch result {
            case .success:
                syncNow()
            case .failure(let err):
                setStatus("Error actualizando worklog: \(err.message)", isError: true)
                // Refetch para que el bloque vuelva a su posición original
                // (el snap visual no se aplicó del lado del servidor).
                syncNow()
            }
        }
    }

    /// Botón "duplicar" de un bloque Jira: crea un worklog idéntico
    /// (misma issue, mismo started, misma durationSec, mismo comment).
    /// El refetch que dispara `applyJira` en success aparece el nuevo
    /// bloque al lado del original.
    private func duplicateJira(_ block: CalendarBlock) {
        guard let w = jira.worklogs.first(where: { "jira-\($0.id)" == block.id }) else { return }
        let started = Date(timeIntervalSince1970: w.startedMs / 1000)
        setStatus("Duplicando worklog Jira…", isError: false, sticky: true)
        jira.createWorklog(
            issueKey: w.issueKey,
            started: started,
            durationSec: w.durationSec,
            comment: w.comment
        ) { result in
            switch result {
            case .success:
                setStatus("Worklog duplicado.", isError: false)
                syncNow()
            case .failure(let err):
                setStatus("Error duplicando: \(err.message)", isError: true)
            }
        }
    }

    /// Botón "duplicar" de un bloque Clockify: crea una entry idéntica
    /// (mismo proyecto, tags, billable, description, start y end).
    private func duplicateClockify(_ block: CalendarBlock) {
        guard let e = clockify.entries.first(where: { "clockify-\($0.id)" == block.id }) else { return }
        let start = Date(timeIntervalSince1970: e.startedMs / 1000)
        let end = start.addingTimeInterval(Double(e.durationSec))
        setStatus("Duplicando entry Clockify…", isError: false, sticky: true)
        clockify.createEntry(
            start: start,
            end: end,
            description: e.description,
            projectId: e.projectId,
            tagIds: e.tagIds,
            billable: e.billable
        ) { result in
            switch result {
            case .success:
                setStatus("Entry duplicada.", isError: false)
                syncNow()
            case .failure(let err):
                setStatus("Error duplicando: \(err.message)", isError: true)
            }
        }
    }

    /// Idem para Clockify.  Preserva descripción, proyecto, tags y
    /// billable; sólo se desplaza start y se ajusta end por la nueva
    /// `durationSec`.
    private func applyClockify(_ block: CalendarBlock,
                               newStartMs: Double,
                               newDurationSec: Int) {
        guard let e = clockify.entries.first(where: { "clockify-\($0.id)" == block.id }) else { return }
        let newStart = Date(timeIntervalSince1970: newStartMs / 1000)
        let newEnd = newStart.addingTimeInterval(Double(newDurationSec))
        clockify.updateEntry(
            id: e.id,
            start: newStart,
            end: newEnd,
            description: e.description,
            projectId: e.projectId,
            tagIds: e.tagIds,
            billable: e.billable
        ) { result in
            switch result {
            case .success:
                syncNow()
            case .failure(let err):
                setStatus("Error actualizando entry: \(err.message)", isError: true)
                syncNow()
            }
        }
    }

    private func goWeek(_ delta: Int) {
        let cal = Calendar.current
        if let d = cal.date(byAdding: .day, value: delta * 7, to: weekStart) {
            weekStart = MainView.sundayOf(d)
            syncNow()
        }
    }

    private func setStatus(_ text: String, isError: Bool, sticky: Bool = false) {
        statusBanner = (text, isError)
        bannerClearTask?.cancel()
        if sticky { return }
        let task = DispatchWorkItem { [self] in
            self.statusBanner = ("", false)
        }
        bannerClearTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: task)
    }

    private func openJiraSheet(editing: JiraWorklog?, start: Date, end: Date) {
        jiraSheetSelection = (editing, start, end)
        jiraSheet = true
    }
    private func openClockifySheet(editing: ClockifyEntry?, start: Date, end: Date) {
        clockifySheetSelection = (editing, start, end)
        clockifySheet = true
    }

    // MARK: - Helpers

    private func msDate(_ ms: Double) -> Date {
        Date(timeIntervalSince1970: ms / 1000)
    }

    static func sundayOf(_ d: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1   // Sunday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return cal.date(from: comps) ?? d
    }

    private func formatWeekLabel(_ start: Date) -> String {
        let end = start.addingTimeInterval(6 * 86400)
        let months = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"]
        let cal = Calendar.current
        let sd = cal.component(.day, from: start)
        let sm = cal.component(.month, from: start) - 1
        let ed = cal.component(.day, from: end)
        let em = cal.component(.month, from: end) - 1
        let ey = cal.component(.year, from: end)
        return "\(sd) \(months[sm]) — \(ed) \(months[em]) \(ey)"
    }
}
