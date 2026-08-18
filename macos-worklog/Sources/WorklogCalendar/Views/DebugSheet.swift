import SwiftUI

/// Sheet de diagnóstico:  muestra el log combinado de los dos stores
/// (Jira + Clockify) y permite limpiarlo.
struct DebugSheet: View {
    @ObservedObject var jira: JiraWorklogStore
    @ObservedObject var jira2: JiraWorklogStore
    @ObservedObject var clockify: ClockifyStore
    @ObservedObject var google: GoogleCalendarStore
    @Binding var presented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diagnóstico (Jira + Clockify)").font(.title3).bold()
                Spacer()
                Button {
                    jira.clearDebugLog()
                    jira2.clearDebugLog()
                    clockify.clearDebugLog()
                    google.clearDebugLog()
                } label: {
                    Label("Limpiar", systemImage: "trash")
                }
                Button(action: { presented = false }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            }

            ScrollView {
                Text(combined)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 360)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
        }
        .padding(12)
        .frame(minWidth: 640, minHeight: 460)
    }

    private var combined: String {
        let j = jira.debugLog.isEmpty ? "(vacío)" : jira.debugLog
        let j2 = jira2.debugLog.isEmpty ? "(vacío)" : jira2.debugLog
        let c = clockify.debugLog.isEmpty ? "(vacío)" : clockify.debugLog
        let g = google.debugLog.isEmpty ? "(vacío)" : google.debugLog
        return "---- JIRA 1 ----\n\(j)\n\n---- JIRA 2 ----\n\(j2)\n\n---- CLOCKIFY ----\n\(c)\n\n---- GOOGLE ----\n\(g)"
    }
}
