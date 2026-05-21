import AppKit
import SwiftUI

/// Modelo "polimórfico" que el grid renderiza en cualquier slot.  Sirve
/// tanto para worklogs Jira como para entries Clockify; cada uno expone
/// sus textos y colores con sus propios initializers.
struct CalendarBlock: Identifiable, Equatable {
    enum Kind { case jira, clockify }

    let id: String
    let kind: Kind
    let startedMs: Double
    let durationSec: Int
    let topText: String
    let bottomText: String
    let compactText: String
    let projectHex: String   // solo Clockify; "" si no aplica

    static func == (lhs: CalendarBlock, rhs: CalendarBlock) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.startedMs == rhs.startedMs &&
            lhs.durationSec == rhs.durationSec
    }
}

extension CalendarBlock {
    init(jira w: JiraWorklog, showSummary: Bool) {
        self.id = "jira-\(w.id)"
        self.kind = .jira
        self.startedMs = w.startedMs
        self.durationSec = w.durationSec
        let top = Self.fmtRange(startMs: w.startedMs, durationSec: w.durationSec)
        let bottom = showSummary && !w.issueSummary.isEmpty
            ? "\(w.issueKey): \(w.issueSummary)"
            : w.issueKey
        self.topText = top
        self.bottomText = bottom
        self.compactText = "\(Self.fmtTime(w.startedMs))  \(w.issueKey)"
        self.projectHex = ""
    }

    init(clockify e: ClockifyEntry) {
        self.id = "clockify-\(e.id)"
        self.kind = .clockify
        self.startedMs = e.startedMs
        self.durationSec = e.durationSec
        let top = Self.fmtRange(startMs: e.startedMs, durationSec: e.durationSec)
        let desc = e.description.isEmpty ? "(sin descripción)" : e.description
        let bottom = e.projectName.isEmpty ? desc : "[\(e.projectName)] \(desc)"
        let compactLabel = !e.description.isEmpty ? e.description
            : (!e.projectName.isEmpty ? e.projectName : "(sin descripción)")
        self.topText = top
        self.bottomText = bottom
        self.compactText = "\(Self.fmtTime(e.startedMs))  \(compactLabel)"
        self.projectHex = e.projectColor
    }

    static func fmtTime(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func fmtRange(startMs: Double, durationSec: Int) -> String {
        let start = startMs
        let end = startMs + Double(durationSec) * 1000
        return "\(fmtTime(start)) - \(fmtTime(end))  (\(fmtDur(durationSec)))"
    }

    static func fmtDur(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

/// Rectángulo con texto que representa un único worklog/entry sobre el grid.
struct EntryBlockView: View {
    let block: CalendarBlock
    /// Cuando estamos en modo combinado (jira-clockify) o el bloque dura
    /// 30 min, forzamos un layout single-line con fuente más chica.
    let compactLayout: Bool
    /// Si es Clockify y el modo no es combinado, podemos teñir con el
    /// color del proyecto.  En el combinado siempre va verde para
    /// distinguirlo visualmente del lila de Jira.
    let useProjectColor: Bool
    let onTap: () -> Void
    /// Llamado al soltar un drag vertical sobre el bloque.  El callback
    /// recibe el delta en píxeles desde el punto de press (positivo =
    /// hacia abajo).  El padre se encarga del snap a slot y del clamp
    /// a límites del día.
    let onMove: (CGFloat) -> Void
    /// Altura de cada fila de 30 min (necesaria para snappear el offset
    /// visual al soltar).
    let rowHeight: CGFloat

    @State private var dragOffsetY: CGFloat = 0

    private var isShort: Bool { block.durationSec <= 30 * 60 }
    private var single: Bool { compactLayout || isShort }

    private var fillColor: Color {
        if block.kind == .jira {
            return Color(red: 155/255, green: 145/255, blue: 230/255).opacity(0.55)
        }
        if useProjectColor, let c = Color(hex: block.projectHex) {
            return c.opacity(0.65)
        }
        return Color(red: 120/255, green: 215/255, blue: 145/255).opacity(0.55)
    }

    private var borderColor: Color {
        if block.kind == .jira {
            return Color(red: 120/255, green: 110/255, blue: 200/255)
        }
        if useProjectColor, let c = Color(hex: block.projectHex) {
            return c.opacity(0.95)
        }
        return Color(red: 70/255, green: 170/255, blue: 100/255)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )

            if single {
                Text(block.compactText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(block.topText)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Text(block.bottomText)
                        .font(.system(size: 10, weight: .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .offset(y: dragOffsetY)
        // Cursor "double-arrow" mientras estás encima del bloque, para
        // advertir que se puede arrastrar.
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        // Tap-sólo → editar.  `DragGesture(minimumDistance: 4)` no
        // dispara nada si el usuario no se movió 4 px, así que clicks
        // cortos siguen yendo a `.onTapGesture`.
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .onChanged { value in
                    dragOffsetY = value.translation.height
                }
                .onEnded { value in
                    let dy = value.translation.height
                    if Swift.abs(dy) >= 1 {
                        // Snappeamos visualmente al múltiplo de fila más
                        // cercano y dejamos el bloque ahí hasta que el
                        // refetch traiga la nueva `startedMs` (el
                        // `.onChange` de abajo se encarga de resetear).
                        dragOffsetY = (dy / rowHeight).rounded() * rowHeight
                        onMove(dy)
                    } else {
                        dragOffsetY = 0
                    }
                }
        )
        // El padre actualizó el modelo (refetch tras un update OK, o un
        // refetch tras un fallo que revierte): el `yFor(b)` del padre ya
        // posiciona el bloque correctamente, así que limpiamos el offset
        // local para no quedar desplazados el doble.
        .onChange(of: block.startedMs) { _ in
            dragOffsetY = 0
        }
    }
}

extension Color {
    /// Parsea "#RRGGBB" o "RRGGBB".  Devuelve `nil` si la cadena no es
    /// hex de 6 caracteres.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
