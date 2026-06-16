import AppKit
import SwiftUI

/// Pantalla principal de la app.  Cabecera (modo + navegación de semana
/// + refresh + diag) + `CalendarView` + footer con totales y botón de
/// sync Jira→Clockify.
struct MainView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var jira: JiraWorklogStore
    @ObservedObject var clockify: ClockifyStore

    /// Si está seteado, estamos dentro del popover de la barra de menús:
    /// mostramos un botón "abrir aplicación" en el header.  En la
    /// ventana normal queda `nil` y el botón no aparece.
    var onOpenApp: (() -> Void)? = nil

    @State private var weekStart: Date = sundayOf(Date())

    // Sheets — usamos `.sheet(item:)` con structs `Identifiable` así el
    // `item` se inyecta sincrónicamente.  Con la API vieja
    // (`.sheet(isPresented:)` + `if let selection`) el primer open
    // mostraba el modal en blanco porque el estado todavía no había
    // propagado al cierre del builder.
    @State private var jiraSheetItem: JiraSheetItem? = nil
    @State private var clockifySheetItem: ClockifySheetItem? = nil
    @State private var subtaskSelection: JiraSubtask? = nil
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

    /// Panel inferior visible: el master toggle, y siempre cuando hay
    /// algo útil que mostrar (gauges piden Jira, heatmap acepta los dos).
    private var showBottomPanel: Bool { settings.showSprintGauges }

    /// Vistas disponibles del panel inferior, en orden del switch.  La
    /// del medio (subtareas) sólo aparece si está habilitada.
    private var bottomViews: [String] {
        var arr = ["rings"]
        if settings.showSubtaskTable { arr.append("subtasks") }
        arr.append("heatmap")
        return arr
    }

    /// Vista efectiva: cae a "rings" si la guardada ya no está disponible
    /// (ej. deshabilitaron la tabla de subtareas).
    private var bottomView: String {
        bottomViews.contains(settings.bottomView) ? settings.bottomView : "rings"
    }

    private var bottomIsRings: Bool { bottomView == "rings" }
    private var bottomIsSubtasks: Bool { bottomView == "subtasks" }
    private var bottomIsHeatmap: Bool { bottomView == "heatmap" }

    /// Los rings solo aportan cuando hay datos de Jira (modo Jira o
    /// combinado) y la vista es de 9h.  Si no, el switch al panel de
    /// rings queda inhabilitado.
    private var ringsAvailable: Bool {
        settings.viewMode == .h9 &&
            (settings.source == .jira || settings.source == .jiraClockify)
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
                onDuplicateClockify: { block in duplicateClockify(block) },
                onDeleteJira:        { block in deleteJira(block) },
                onDeleteClockify:    { block in deleteClockify(block) }
            )
            .frame(maxHeight: .infinity)

            if showBottomPanel {
                Divider()
                bottomPanel
            }

            footerBar
        }
        .padding(8)
        .onAppear {
            syncProjectId = settings.clockifyDefaultProjectId
            syncNow()
        }
        .onChange(of: settings.clockifyDefaultProjectId) {
            // Si editan el default en Preferencias, reflejarlo acá.
            syncProjectId = settings.clockifyDefaultProjectId
        }
        // Cambios en Preferencias del bloque "Sprint (experimental)" →
        // re-fetch sin esperar al ↻ (sólo si los rings están visibles).
        .onChange(of: settings.sprintStrategy) { if showBottomPanel && bottomIsRings { jira.fetchSprintInfo { _ in } } }
        .onChange(of: settings.sprintField)    { if showBottomPanel && bottomIsRings { jira.fetchSprintInfo { _ in } } }
        .onChange(of: settings.sprintBoardId)  { if showBottomPanel && bottomIsRings { jira.fetchSprintInfo { _ in } } }
        .onChange(of: settings.remainingMode)  { if showBottomPanel && bottomIsRings { jira.fetchSprintInfo { _ in } } }
        // Si recién encienden el panel inferior, traigamos los datos.
        .onChange(of: settings.showSprintGauges) { _, on in if on, bottomIsRings { jira.fetchSprintInfo { _ in } } }
        // Cambio de vista del panel inferior (botones del switch, wheel
        // o config) → refrescar la nueva vista.  El heatmap se refresca
        // sólo via `.onAppear`; rings y subtareas necesitan re-fetch.
        .onChange(of: settings.bottomView) { refreshBottomView() }
        // Si deshabilitan la tabla de subtareas mientras está visible,
        // caemos a "rings".
        .onChange(of: settings.showSubtaskTable) { _, on in
            if !on && settings.bottomView == "subtasks" { settings.bottomView = "rings" }
        }
        // Editar el JQL de subtareas con la tabla visible → recargar.
        .onChange(of: settings.subtaskJql) {
            if showBottomPanel && bottomIsSubtasks { jira.fetchSubtasks() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .worklogOpenPreferences)) { _ in
            showSettings = true
        }
        // Jira sheet — `item:` garantiza inyección sincrónica del valor.
        .sheet(item: $jiraSheetItem) { item in
            JiraEditSheet(
                store: jira,
                settings: settings,
                editing: item.editing,
                start: item.start,
                end: item.end,
                onSaved:   { jiraSheetItem = nil; syncNow() },
                onDeleted: { jiraSheetItem = nil; syncNow() }
            )
        }
        // Clockify sheet
        .sheet(item: $clockifySheetItem) { item in
            ClockifyEditSheet(
                store: clockify,
                settings: settings,
                editing: item.editing,
                start: item.start,
                end: item.end,
                defaultProjectId: settings.clockifyDefaultProjectId,
                defaultBillable: settings.clockifyBillableDefault,
                onSaved:   { clockifySheetItem = nil; syncNow() },
                onDeleted: { clockifySheetItem = nil; syncNow() }
            )
        }
        // Subtask detail sheet — JiraSubtask ya es Identifiable.
        .sheet(item: $subtaskSelection) { sub in
            SubtaskDetailSheet(
                jira: jira,
                settings: settings,
                subtask: sub
            )
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

            if let onOpenApp {
                Button(action: onOpenApp) {
                    Image(systemName: "macwindow")
                }
                .help("Abrir la aplicación completa (todos los modos)")
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

    /// Altura fija del panel inferior — la suficiente para los anillos
    /// (110 px de diámetro + label arriba + leyenda abajo).  Las otras
    /// vistas (subtareas, heatmap) se adaptan a este lienzo.  Tener un
    /// alto fijo evita que cambiar de modo desplace el calendario de
    /// arriba.
    private let bottomPanelHeight: CGFloat = 220

    /// Panel inferior: a la izquierda el contenido (anillos / subtareas /
    /// heatmap), a la derecha un switch vertical de hasta tres botones
    /// fijos en el centro vertical.  Scrollear con la rueda / trackpad
    /// cicla entre las vistas disponibles (down → hacia el heatmap, up
    /// → hacia los anillos).
    private var bottomPanel: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .topLeading) {
                switch bottomView {
                case "subtasks":
                    SubtaskTable(
                        jira: jira,
                        settings: settings,
                        onActivate: { sub in openSubtaskDetail(sub) },
                        onOpenInJira: { key in openInJira(key) },
                        onTransition: { sub, t in transitionSubtask(sub, t) }
                    )
                    .transition(.opacity)
                case "heatmap":
                    MonthHeatmap(
                        jira: jira,
                        clockify: clockify,
                        onDaySelected: { date in
                            weekStart = MainView.sundayOf(date)
                            syncNow()
                        },
                        refreshTrigger: heatmapRefreshTrigger
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                default:
                    SprintGauges(jira: jira)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: bottomView)

            // Switch vertical pinned al centro-derecha.  El `maxHeight:
            // .infinity` + `alignment: .center` lo deja siempre en el
            // mismo lugar, no importa qué vista esté activa.
            VStack(spacing: 4) {
                bottomViewButton(
                    target: "rings",
                    systemName: "circle.dashed",
                    label: "Anillos Sprint / Horas",
                    enabled: ringsAvailable
                )
                if settings.showSubtaskTable {
                    bottomViewButton(
                        target: "subtasks",
                        systemName: "list.bullet.rectangle",
                        label: "Tabla de subtareas",
                        enabled: true
                    )
                }
                bottomViewButton(
                    target: "heatmap",
                    systemName: "square.grid.3x3",
                    label: "Mapa mensual de horas",
                    enabled: true
                )
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: bottomPanelHeight)
        .background(WheelCatcher { dy in handleBottomPanelWheel(dy) })
    }

    /// Acumulador + cooldown para el wheel.  Umbral bajo (2 px) +
    /// cooldown de 250 ms para que con el trackpad sienta responsivo y
    /// con la rueda física dispare en un click — sin disparar 20 veces
    /// por swipe largo.
    @State private var wheelAccum: CGFloat = 0
    @State private var wheelLastFire: Date = .distantPast
    /// Bump cada vez que el usuario aprieta el botón global ↻ para que
    /// `MonthHeatmap` recargue sus totales del mes.
    @State private var heatmapRefreshTrigger: Int = 0
    private func handleBottomPanelWheel(_ dy: CGFloat) {
        // En la vista de Subtareas el wheel tiene que scrollear la lista
        // de filas, no cambiar de sección.  Para los demás (rings,
        // heatmap) no hay ScrollView interno, así que el wheel se
        // dedica al ciclo.
        if bottomIsSubtasks { return }

        let now = Date()
        if now.timeIntervalSince(wheelLastFire) < 0.25 {
            return                         // todavía en cooldown
        }
        wheelAccum += dy
        let threshold: CGFloat = 2
        if wheelAccum >= threshold {
            cycleBottomView(-1)            // scroll up → hacia los anillos
            wheelAccum = 0
            wheelLastFire = now
        } else if wheelAccum <= -threshold {
            cycleBottomView(+1)            // scroll down → hacia el heatmap
            wheelAccum = 0
            wheelLastFire = now
        }
    }

    /// Avanza/retrocede en `bottomViews`, sin wrap.
    private func cycleBottomView(_ delta: Int) {
        let views = bottomViews
        let idx = views.firstIndex(of: bottomView) ?? 0
        let next = Swift.max(0, Swift.min(views.count - 1, idx + delta))
        if next != idx { settings.bottomView = views[next] }
    }

    /// Botón-ícono individual del switch.  Marca el activo con relleno
    /// accent, los inactivos quedan transparentes.
    private func bottomViewButton(target: String,
                                   systemName: String,
                                   label: String,
                                   enabled: Bool) -> some View {
        let active = bottomView == target
        return Button {
            settings.bottomView = target
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .frame(width: 22, height: 22)
                .background(active ? Color.accentColor.opacity(0.25) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(label)
    }

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
            .onChange(of: settings.source) { syncNow() }
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
        .onChange(of: syncProjectId) { _, newValue in
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
        }
        if settings.source == .clockify || settings.source == .jiraClockify {
            clockify.fetchWeek(starting: weekStart)
        }
        refreshBottomView()
    }

    /// Refresca el contenido de la vista del panel inferior activa.
    private func refreshBottomView() {
        guard showBottomPanel else { return }
        if bottomIsRings, ringsAvailable {
            jira.fetchSprintInfo { _ in }
        } else if bottomIsSubtasks {
            jira.fetchSubtasks()
        } else if bottomIsHeatmap {
            // El heatmap se autoriza con `.onAppear`, pero cuando el
            // usuario toca el ↻ con el heatmap ya montado tenemos que
            // empujarle un trigger para que vuelva a pedir los totales
            // del mes.
            heatmapRefreshTrigger += 1
        }
    }

    // MARK: - Subtareas

    private func openSubtaskDetail(_ sub: JiraSubtask) {
        subtaskSelection = sub
    }

    private func openInJira(_ key: String) {
        if let url = jira.issueWebUrl(key) {
            NSWorkspace.shared.open(url)
        }
    }

    private func transitionSubtask(_ sub: JiraSubtask, _ t: JiraTransition) {
        setStatus("Cambiando estado de \(sub.key)…", isError: false, sticky: true)
        jira.transitionIssue(issueKey: sub.key, transitionId: t.id) { result in
            switch result {
            case .success:
                setStatus("Estado de \(sub.key) actualizado.", isError: false)
                jira.fetchSubtasks()
            case .failure(let err):
                setStatus("No se pudo cambiar el estado: \(err.message)", isError: true)
            }
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

    /// Menú contextual → "Eliminar" sobre un bloque Jira.
    private func deleteJira(_ block: CalendarBlock) {
        guard let w = jira.worklogs.first(where: { "jira-\($0.id)" == block.id }) else { return }
        setStatus("Eliminando worklog…", isError: false, sticky: true)
        jira.deleteWorklog(issueKey: w.issueKey, worklogId: w.id) { result in
            switch result {
            case .success:
                setStatus("Worklog eliminado.", isError: false)
                syncNow()
            case .failure(let err):
                setStatus("Error eliminando: \(err.message)", isError: true)
                syncNow()
            }
        }
    }

    /// Menú contextual → "Eliminar" sobre una entry Clockify.
    private func deleteClockify(_ block: CalendarBlock) {
        guard let e = clockify.entries.first(where: { "clockify-\($0.id)" == block.id }) else { return }
        setStatus("Eliminando entry…", isError: false, sticky: true)
        clockify.deleteEntry(id: e.id) { result in
            switch result {
            case .success:
                setStatus("Entry eliminada.", isError: false)
                syncNow()
            case .failure(let err):
                setStatus("Error eliminando: \(err.message)", isError: true)
                syncNow()
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
        jiraSheetItem = JiraSheetItem(editing: editing, start: start, end: end)
    }
    private func openClockifySheet(editing: ClockifyEntry?, start: Date, end: Date) {
        clockifySheetItem = ClockifySheetItem(editing: editing, start: start, end: end)
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

/// Envoltorios `Identifiable` para que los sheets se abran con el
/// `item` ya seteado (evita el bug del modal-en-blanco la primera vez).
struct JiraSheetItem: Identifiable {
    let id = UUID()
    let editing: JiraWorklog?
    let start: Date
    let end: Date
}

struct ClockifySheetItem: Identifiable {
    let id = UUID()
    let editing: ClockifyEntry?
    let start: Date
    let end: Date
}
