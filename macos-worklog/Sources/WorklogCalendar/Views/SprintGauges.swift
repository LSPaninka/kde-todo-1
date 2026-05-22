import SwiftUI

/// Dos `RingGauge` al pie del calendario, con líneas decorativas y
/// leyendas debajo de cada uno.
///
/// - **Sprint**: % de tiempo transcurrido del sprint activo.
///   Escala de colores celeste/amarillo/naranja/rojo/rojo-oscuro en
///   los thresholds 0/75/85/90/100.
/// - **Horas**: % de horas seteadas (disponibles + consumidas) que ya
///   fueron quemadas por el usuario.  Verde claro por defecto, verde
///   más fuerte al 100%.  Fade lento por defecto; rápido si el sprint
///   está ≥85% y todavía no se completó al 99% (vas atrasado).
struct SprintGauges: View {
    @ObservedObject var jira: JiraWorklogStore

    private var hasSprint: Bool { jira.currentSprint != nil }

    private var sprintPct: Double {
        guard let s = jira.currentSprint, s.endMs > s.startMs else { return 0 }
        let now = Date().timeIntervalSince1970 * 1000
        if now <= s.startMs { return 0 }
        if now >= s.endMs   { return 100 }
        return ((now - s.startMs) / (s.endMs - s.startMs)) * 100
    }

    /// "Consumido sobre el total seteado (disponibles + consumidas)".
    /// El denominador es la suma para que el % camine de 0 → 100 a
    /// medida que loguás horas contra el sprint.
    private var hoursPct: Double {
        let avail = Double(jira.sprintAvailableSec)
        let consumed = Double(jira.sprintConsumedSec)
        let total = avail + consumed
        if total <= 0 { return 0 }
        return max(0, min(100, consumed / total * 100))
    }

    private var sprintColor: Color {
        let p = sprintPct
        if p >= 100 { return Color(red: 183/255, green: 28/255, blue: 28/255) }   // dark red
        if p >= 90  { return Color(red: 229/255, green: 57/255, blue: 53/255) }   // red
        if p >= 85  { return Color(red: 251/255, green: 140/255, blue: 0/255) }   // orange
        if p >= 75  { return Color(red: 251/255, green: 192/255, blue: 45/255) }  // yellow
        return Color(red: 41/255, green: 182/255, blue: 246/255)                  // celeste
    }
    private var hoursBase: Color {
        hoursPct >= 100
            ? Color(red:  76/255, green: 175/255, blue:  80/255)   // #4CAF50
            : Color(red: 129/255, green: 199/255, blue: 132/255)   // #81C784
    }

    private var hoursIntermittent: Bool { sprintPct >= 85 && hoursPct < 99 }

    var body: some View {
        HStack(spacing: 16) {
            decorativeLine
            VStack(spacing: 4) {
                Text("Sprint").font(.headline)
                RingGauge(value: sprintPct,
                          baseColor: sprintColor,
                          useFadeLoop: false)
                Text(sprintLegend)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 160)

            decorativeLine

            VStack(spacing: 4) {
                Text("Horas").font(.headline)
                RingGauge(value: hoursPct,
                          baseColor: hoursBase,
                          useFadeLoop: true,
                          intermittent: hoursIntermittent)
                Text(hoursLegend)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 160)

            decorativeLine
        }
        .padding(.vertical, 4)
    }

    private var decorativeLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private var sprintLegend: String {
        guard let s = jira.currentSprint else { return "Sin sprint activo" }
        return "Inicio: \(fmtDate(s.startDate))\nFin: \(fmtDate(s.endDate))"
    }

    private var hoursLegend: String {
        "Disponible: \(fmtHours(jira.sprintAvailableSec))\nQuemadas: \(fmtHours(jira.sprintConsumedSec))"
    }

    private func fmtDate(_ iso: String) -> String {
        guard let ms = JiraWorklogStore.parseJiraDateMs(iso) else { return "—" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.dateFormat = "d/M"
        return f.string(from: d)
    }

    private func fmtHours(_ sec: Int) -> String {
        if sec <= 0 { return "0h" }
        let h = sec / 3600
        let m = (sec % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}
