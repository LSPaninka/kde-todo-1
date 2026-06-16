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

    private var showParent: Bool { settings.subtaskShowParent }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            columnHeader
            Divider()
            if jira.subtasks.isEmpty {
                Spacer(minLength: 0)
                Text("Sin subtareas. Ajustá el JQL en Preferencias.")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(jira.subtasks) { row in
                            rowView(row)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Subtareas").font(.headline)
            if !jira.subtasks.isEmpty {
                Text("(\(jira.subtasks.count))")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button { jira.fetchSubtasks() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Recargar subtareas")
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 6) {
            Text("Subtarea").font(.caption2).bold().foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Estado").font(.caption2).bold().foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text("Disp.").font(.caption2).bold().foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
            if showParent {
                Text("Padre").font(.caption2).bold().foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
            }
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
                .frame(width: 110)
                .background(
                    Capsule().fill(JiraStatusBadge.color(for: row.statusColor))
                )

            // Horas disponibles
            Text(JiraStatusBadge.fmtHours(row.remainingSec))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 64, alignment: .trailing)

            // Padre (opcional)
            if showParent {
                Text(row.parentKey.isEmpty ? "—" : row.parentKey)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1).truncationMode(.tail)
                    .opacity(row.parentKey.isEmpty ? 0.35 : 0.85)
                    .frame(width: 90, alignment: .leading)
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
