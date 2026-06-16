import AppKit
import SwiftUI

/// Modal read-only con el detalle de una subtarea Jira + botón
/// "Abrir en Jira".  Se siembra con lo que ya está en la fila y luego
/// enriquece con `fetchIssueDetail` (descripción, estimados, padre, etc.).
struct SubtaskDetailSheet: View {
    @ObservedObject var jira: JiraWorklogStore
    @ObservedObject var settings: AppSettings
    @Binding var presented: Bool

    /// La fila que disparó el modal (datos mínimos para arrancar).
    let subtask: JiraSubtask

    @State private var detail: JiraIssueDetail?
    @State private var loading: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            statusRow
            metaGrid
            estimatesRow
            Divider()

            Text("Descripción").font(.caption).foregroundColor(.secondary)
            ScrollView {
                Text(descriptionText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.25)))

            if let d = detail, !d.created.isEmpty || !d.updated.isEmpty {
                Text("Creada: \(fmtDate(d.created))    Actualizada: \(fmtDate(d.updated))")
                    .font(.caption2).foregroundColor(.secondary)
            }
            if !errorText.isEmpty {
                Text(errorText).font(.callout).foregroundColor(.red)
            }

            footer
        }
        .padding(16)
        .frame(
            minWidth: CGFloat(max(420, settings.modalWidth)),
            minHeight: CGFloat(max(360, settings.modalHeight))
        )
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("[\(activeKey)]").font(.system(.body, design: .monospaced)).bold()
            Text(activeSummary).font(.headline).lineLimit(2)
            Spacer()
            if loading { ProgressView().controlSize(.small) }
            Button(action: { presented = false }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
        }
    }

    /// Badge de estado solo, en su propia fila.
    private var statusRow: some View {
        HStack {
            if !activeStatus.isEmpty {
                Text(activeStatus)
                    .font(.caption2).bold()
                    .foregroundColor(Color(white: 0.10))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(JiraStatusBadge.color(for: activeStatusColor)))
            }
            Spacer()
        }
    }

    /// Grid de campos etiquetados: Tipo, Prioridad, Padre, Asignado a.
    /// Siempre los mostramos (con "—" cuando no hay valor), salvo Padre
    /// que sólo aparece si la issue es subtarea de algo.
    private var metaGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline,
             horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                Text("Tipo de actividad:").foregroundColor(.secondary)
                Text(detail?.issuetype.isEmpty == false ? detail!.issuetype : "—")
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow {
                Text("Prioridad:").foregroundColor(.secondary)
                Text(detail?.priority.isEmpty == false ? detail!.priority : "—")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !activeParentKey.isEmpty {
                GridRow {
                    Text("Padre:").foregroundColor(.secondary)
                    Text(parentDisplay)
                        .bold()
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GridRow {
                Text("Asignado a:").foregroundColor(.secondary)
                Text(detail?.assignee.isEmpty == false ? detail!.assignee : "—")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var parentDisplay: String {
        if activeParentSummary.isEmpty { return activeParentKey }
        return "\(activeParentKey)  —  \(activeParentSummary)"
    }

    private var estimatesRow: some View {
        HStack(alignment: .top, spacing: 24) {
            estimateCol("Original", detail?.originalEstimateSec)
            estimateCol("Quemadas", detail?.spentSec)
            estimateCol("Disponible", detail?.remainingSec ?? subtask.remainingSec)
            Spacer()
        }
    }

    private func estimateCol(_ label: String, _ sec: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(JiraStatusBadge.fmtHours(sec ?? 0))
                .font(.system(.body, design: .monospaced)).bold()
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cerrar") { presented = false }
                .keyboardShortcut(.cancelAction)
            Button("Abrir en Jira") {
                if let url = jira.issueWebUrl(activeKey) {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Datos efectivos (detail enriquecido o fallback a la fila)

    private var activeKey: String { detail?.key ?? subtask.key }
    private var activeSummary: String { detail?.summary ?? subtask.summary }
    private var activeStatus: String { detail?.status ?? subtask.status }
    private var activeStatusColor: String { detail?.statusColor ?? subtask.statusColor }
    private var activeParentKey: String { detail?.parentKey ?? subtask.parentKey }
    private var activeParentSummary: String { detail?.parentSummary ?? subtask.parentSummary }
    private var descriptionText: String {
        if loading && detail?.description.isEmpty != false { return "Cargando…" }
        let d = detail?.description ?? ""
        return d.isEmpty ? "(sin descripción)" : d
    }

    private func load() {
        loading = true
        errorText = ""
        jira.fetchIssueDetail(issueKey: subtask.key) { full in
            loading = false
            if let full { detail = full }
            else { errorText = "No se pudo cargar el detalle." }
        }
    }

    private func fmtDate(_ iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        // Jira manda "...+0000" sin dos puntos; reusamos el parser del
        // store que ya cubre esos formatos.
        guard let ms = JiraWorklogStore.parseJiraDateMs(iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "yyyy-MM-dd HH:mm"
        return out.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}
