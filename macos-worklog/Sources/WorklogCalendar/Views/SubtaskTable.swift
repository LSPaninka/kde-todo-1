import AppKit
import SwiftUI

/// Mapea el `statusCategory.colorName` de Jira a un color para el badge.
enum JiraStatusBadge {
    static func color(for colorName: String) -> Color {
        switch colorName.lowercased() {
        case "green":       return Color(red: 129/255, green: 199/255, blue: 132/255)
        case "yellow":      return Color(red: 241/255, green: 196/255, blue: 15/255)
        case "blue-gray":   return Color(red: 120/255, green: 144/255, blue: 156/255)
        case "warm-red":    return Color(red: 231/255, green: 76/255,  blue: 60/255)
        case "medium-gray": return Color(red: 158/255, green: 158/255, blue: 158/255)
        default:            return Color(red: 120/255, green: 144/255, blue: 156/255).opacity(0.75)
        }
    }

    static func fmtHours(_ sec: Int) -> String {
        if sec <= 0 { return "—" }
        let h = sec / 3600, m = (sec % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

/// Tercera vista del panel inferior: tabla de subtareas del usuario.
/// Columnas: código + título, badge de estado, horas disponibles y
/// (opcional) issue padre.  Click izquierdo → detalle; click derecho →
/// menú contextual (cambiar estado + abrir en Jira).
///
/// Click en un header ordena por esa columna; click de nuevo invierte.
/// Sin orden seleccionado, las filas mantienen el ORDER BY del JQL.
struct SubtaskTable: View {
    @ObservedObject var jira: JiraWorklogStore
    @ObservedObject var settings: AppSettings

    /// Click en una fila → abrir el detalle.
    let onActivate: (JiraSubtask) -> Void
    /// "Abrir en Jira" del menú contextual.
    let onOpenInJira: (String) -> Void
    /// Disparar una transición de estado.
    let onTransition: (JiraSubtask, JiraTransition) -> Void

    /// Cache de transiciones por key, pre-cargada al hacer hover sobre la
    /// fila para que el menú contextual de click-derecho ya las tenga.
    @State private var transitionsByKey: [String: [JiraTransition]] = [:]
    @State private var loadingKeys: Set<String> = []

    /// Columnas ordenables.  `nil` = mantener el orden del JQL.
    enum SortKey { case key, status, remaining, parent }
    @State private var sortKey: SortKey? = nil
    @State private var sortAsc: Bool = true

    /// Filtro inline (toggle de la lupa).  Match contra `key`, `summary`,
    /// `status`, `parentKey` y `parentSummary` (substring, case-insens.).
    @State private var searchOpen: Bool = false
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    private var showParent: Bool { settings.subtaskShowParent }

    // Geometría compartida entre header y filas para que el spacer (la
    // separación entre "Disp." y "Padre") evite el choque "— CP-2650".
    private let statusW: CGFloat = 110
    private let dispW:   CGFloat = 64
    private let gapW:    CGFloat = 16
    private let parentW: CGFloat = 90

    /// Filas con filtro + orden aplicados.  Sin filtro y sin orden,
    /// devolvemos `jira.subtasks` tal cual (orden del JQL).
    private var displayRows: [JiraSubtask] {
        var rows = jira.subtasks

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !q.isEmpty {
            rows = rows.filter { r in
                let hay = "\(r.key) \(r.summary) \(r.status) \(r.parentKey) \(r.parentSummary)"
                    .lowercased()
                return hay.contains(q)
            }
        }

        guard let key = sortKey else { return rows }
        let mult = sortAsc ? 1 : -1
        return rows.sorted { a, b in
            switch key {
            case .remaining:
                return (a.remainingSec - b.remainingSec) * mult < 0
            case .status:
                return a.status.localizedCompare(b.status) == (mult > 0 ? .orderedAscending : .orderedDescending)
            case .parent:
                return a.parentKey.localizedCompare(b.parentKey) == (mult > 0 ? .orderedAscending : .orderedDescending)
            case .key:
                return a.key.localizedCompare(b.key) == (mult > 0 ? .orderedAscending : .orderedDescending)
            }
        }
    }

    private func toggleSort(_ k: SortKey) {
        if sortKey == k { sortAsc.toggle() }
        else { sortKey = k; sortAsc = true }
    }
    private func sortGlyph(_ k: SortKey) -> String {
        guard sortKey == k else { return "" }
        return sortAsc ? "  ▲" : "  ▼"
    }

    var body: some View {
        // `maxHeight: .infinity` + alignment topLeading: ocupamos todo el
        // alto del panel inferior y arrancamos desde arriba, así no
        // queda el bloque centrado verticalmente con un hueco entre el
        // header y las filas.
        VStack(alignment: .leading, spacing: 0) {
            header
            columnHeader
                .padding(.top, 2)
            Divider().padding(.top, 1)
            if displayRows.isEmpty {
                Spacer(minLength: 0)
                Text(jira.subtasks.isEmpty
                     ? "Sin subtareas. Ajustá el JQL en Preferencias."
                     : "Sin resultados para «\(searchText)».")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 1) {
                        ForEach(displayRows) { row in
                            rowView(row)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Subtareas").font(.headline)

            // Cuando el filtro está abierto, el TextField ocupa el lugar
            // del contador + spacer.  Esc lo cierra y limpia.
            if searchOpen {
                TextField("Filtrar subtareas…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onKeyPress(.escape) {
                        searchOpen = false
                        searchText = ""
                        return .handled
                    }
                    .frame(maxWidth: .infinity)
            } else {
                if !displayRows.isEmpty {
                    Text("(\(displayRows.count))")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }

            Button {
                searchOpen.toggle()
                if !searchOpen { searchText = "" }
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(searchOpen ? .accentColor : .primary)
            }
            .buttonStyle(.borderless)
            .help("Buscar en la lista")

            Button { jira.fetchSubtasks() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Recargar subtareas")
        }
        // Foco automático al abrir el filtro.
        .onChange(of: searchOpen) { _, isOpen in
            if isOpen { searchFocused = true }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 6) {
            headerCell(title: "Subtarea", key: .key, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerCell(title: "Estado", key: .status, alignment: .leading)
                .frame(width: statusW, alignment: .leading)
            headerCell(title: "Disp.", key: .remaining, alignment: .trailing)
                .frame(width: dispW, alignment: .trailing)
            if showParent {
                Color.clear.frame(width: gapW)
                headerCell(title: "Padre", key: .parent, alignment: .leading)
                    .frame(width: parentW, alignment: .leading)
            }
        }
    }

    /// Header clickeable de una columna con su glifo de sort.
    @ViewBuilder
    private func headerCell(title: String,
                             key: SortKey,
                             alignment: TextAlignment) -> some View {
        let isActive = sortKey == key
        Text(title + sortGlyph(key))
            .font(.caption2).bold()
            .foregroundColor(.secondary)
            .opacity(isActive ? 0.95 : 0.6)
            .multilineTextAlignment(alignment)
            .lineLimit(1)
            .contentShape(Rectangle())
            .onTapGesture { toggleSort(key) }
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.set() }
                else        { NSCursor.arrow.set() }
            }
    }

    @ViewBuilder
    private func rowView(_ row: JiraSubtask) -> some View {
        HStack(spacing: 6) {
            // Código + título
            HStack(spacing: 6) {
                Text(row.key)
                    .font(.system(.body, design: .monospaced)).bold()
                Text(row.summary)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Badge de estado
            Text(row.status)
                .font(.caption2).bold()
                .foregroundColor(Color(white: 0.10))
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .frame(width: statusW)
                .background(
                    Capsule().fill(JiraStatusBadge.color(for: row.statusColor))
                )

            // Horas disponibles
            Text(JiraStatusBadge.fmtHours(row.remainingSec))
                .font(.system(.caption, design: .monospaced))
                .frame(width: dispW, alignment: .trailing)

            // Padre (opcional), con un spacer fijo antes para que no
            // choque con el "—" del Disp.
            if showParent {
                Color.clear.frame(width: gapW)
                Text(row.parentKey.isEmpty ? "—" : row.parentKey)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1).truncationMode(.tail)
                    .opacity(row.parentKey.isEmpty ? 0.35 : 0.85)
                    .frame(width: parentW, alignment: .leading)
                    .help(row.parentSummary.isEmpty ? "" : "\(row.parentKey) — \(row.parentSummary)")
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { onActivate(row) }
        .onHover { hovering in
            if hovering { prefetchTransitions(for: row.key) }
        }
        .contextMenu { contextMenu(for: row) }
    }

    @ViewBuilder
    private func contextMenu(for row: JiraSubtask) -> some View {
        let transitions = transitionsByKey[row.key] ?? []
        if transitions.isEmpty {
            Text(loadingKeys.contains(row.key) ? "Cargando estados…" : "(sin transiciones)")
        } else {
            Menu("Cambiar estado") {
                ForEach(transitions) { t in
                    Button(t.toStatus.isEmpty ? t.name : "\(t.name) → \(t.toStatus)") {
                        onTransition(row, t)
                    }
                }
            }
        }
        Divider()
        Button("Ver detalle") { onActivate(row) }
        Button("Ver en Jira") { onOpenInJira(row.key) }
    }

    private func prefetchTransitions(for key: String) {
        guard transitionsByKey[key] == nil, !loadingKeys.contains(key) else { return }
        loadingKeys.insert(key)
        jira.fetchTransitions(issueKey: key) { transitions in
            transitionsByKey[key] = transitions
            loadingKeys.remove(key)
        }
    }
}
