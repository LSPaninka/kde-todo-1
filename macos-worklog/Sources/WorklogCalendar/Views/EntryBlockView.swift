import AppKit
import SwiftUI

/// Modelo "polimórfico" que el grid renderiza en cualquier slot.  Sirve
/// tanto para worklogs Jira como para entries Clockify; cada uno expone
/// sus textos y colores con sus propios initializers.
struct CalendarBlock: Identifiable, Equatable {
    enum Kind { case jira, jira2, clockify }

    let id: String
    let kind: Kind
    let startedMs: Double
    let durationSec: Int
    let topText: String
    let bottomText: String
    /// Tercera línea opcional (sólo Clockify la usa, para mostrar
    /// proyecto arriba y descripción debajo).  `""` = no se renderiza.
    let extraText: String
    let compactText: String
    let projectHex: String   // solo Clockify; "" si no aplica

    static func == (lhs: CalendarBlock, rhs: CalendarBlock) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.startedMs == rhs.startedMs &&
            lhs.durationSec == rhs.durationSec
    }
}

extension CalendarBlock {
    init(jira w: JiraWorklog, showSummary: Bool, instanceId: Int = 1) {
        self.id = instanceId == 2 ? "jira2-\(w.id)" : "jira-\(w.id)"
        self.kind = instanceId == 2 ? .jira2 : .jira
        self.startedMs = w.startedMs
        self.durationSec = w.durationSec
        let top = Self.fmtRange(startMs: w.startedMs, durationSec: w.durationSec)
        let bottom = showSummary && !w.issueSummary.isEmpty
            ? "\(w.issueKey): \(w.issueSummary)"
            : w.issueKey
        self.topText = top
        self.bottomText = bottom
        self.extraText = ""
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
        // En multi-línea queremos el nombre del proyecto solo en su
        // propia línea (matchea el plasmoide de KDE).  Si no hay
        // proyecto, la descripción ocupa la línea principal y `extra`
        // queda vacía.
        if e.projectName.isEmpty {
            self.bottomText = desc
            self.extraText = ""
        } else {
            self.bottomText = e.projectName
            self.extraText = desc
        }
        let compactLabel = !e.description.isEmpty ? e.description
            : (!e.projectName.isEmpty ? e.projectName : "(sin descripción)")
        self.topText = top
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
///
/// Maneja tres interacciones con una sola gesture, decidida al iniciar
/// el drag según la Y del punto de press:
///   - top 5 px      → resize del borde superior (cambia inicio + duración)
///   - bottom 5 px   → resize del borde inferior (cambia duración)
///   - centro        → click (tap) o move X+Y (cross-day permitido)
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
    /// Move: el padre snappea Y a slots y X al ancho de columna.  El
    /// flag `fine` es `true` si Shift estaba apretado al iniciar el
    /// drag → granularidad de 10 min en vez de 30.
    let onMove: (_ dx: CGFloat, _ dy: CGFloat, _ fine: Bool) -> Void
    /// Resize del borde superior: el padre cambia `started + duration`.
    let onResizeTop: (_ dy: CGFloat, _ fine: Bool) -> Void
    /// Resize del borde inferior: el padre cambia sólo `duration`.
    let onResizeBottom: (_ dh: CGFloat, _ fine: Bool) -> Void
    /// Menú contextual "Duplicar" (esquina superior derecha del bloque y
    /// segundo item del right-click).
    let onDuplicate: () -> Void
    /// Menú contextual "Eliminar" del right-click.  El padre llama a
    /// `deleteWorklog` / `deleteEntry` según corresponda.
    let onDelete: () -> Void
    /// `true` cuando este bloque pisa en el tiempo a otro del mismo
    /// origen (Jira-Jira o Clockify-Clockify).  Cuando es así, lo
    /// teñimos:  naranja para Jira, amarillo para Clockify, así el
    /// usuario detecta visualmente duplicados pre-sync.
    let overlapping: Bool
    /// Color base (hex) del bloque cuando es de Jira — depende de la
    /// instancia (jira1BlockColor / jira2BlockColor).
    var jiraColorHex: String = "#9b91e6"
    /// Altura de cada fila de 30 min (necesaria para snappear el offset
    /// visual al soltar y para detectar el zonado top/bottom).
    let rowHeight: CGFloat
    /// Ancho de la columna del día — usado para snappear el offset X
    /// durante el drag-move, así el bloque "salta" de día en día en
    /// lugar de seguir suavemente al cursor (matchea el "más estático"
    /// del plasmoide).
    let columnWidth: CGFloat
    /// Alto total de la columna del día (= slotsPerDay × rowHeight).
    /// Sirve para clampear el bloque dentro de las horas visibles —
    /// sin esto, en modo 9h el bloque podía escaparse por debajo de
    /// las 18:00.
    let columnHeight: CGFloat
    /// Y del bloque dentro de la columna (lo que pone el padre con
    /// `.offset(y: yFor(b))`).  El bloque lo necesita para calcular
    /// los límites válidos del drag y del resize.
    let blockYInColumn: CGFloat

    @State private var dragMode: DragMode = .none
    @State private var dragOffsetX: CGFloat = 0
    @State private var dragOffsetY: CGFloat = 0
    @State private var resizeTopDy: CGFloat = 0
    @State private var resizeHeightDelta: CGFloat = 0
    @State private var hovered: Bool = false
    /// Captura del estado de Shift al iniciar el drag — congelamos para
    /// que cambiar el modificador en medio no toggleée la granularidad.
    @State private var dragFine: Bool = false

    enum DragMode { case none, move, resizeTop, resizeBottom }

    private let edgePx: CGFloat = 5

    private var isShort: Bool { block.durationSec <= 30 * 60 }
    /// Sólo los bloques cortos (≤30 min) caben en una sola línea.  El
    /// modo combinado *no* fuerza single-line: encogemos el font pero
    /// dejamos que un bloque alto muestre rango + título.
    private var single: Bool { isShort }
    /// Tamaño base del texto: 8 en modo combinado (columnas a mitad),
    /// 9 en modo lleno.
    private var blockFontSize: CGFloat { compactLayout ? 8 : 9 }

    private var fillColor: Color {
        if block.kind == .jira || block.kind == .jira2 {
            // Color por instancia (configurable), siempre translúcido.
            if let c = Color(hex: jiraColorHex) { return c.opacity(0.55) }
            return Color(red: 155/255, green: 145/255, blue: 230/255).opacity(0.55)
        }
        if useProjectColor, let c = Color(hex: block.projectHex) {
            return c.opacity(0.65)
        }
        return Color(red: 120/255, green: 215/255, blue: 145/255).opacity(0.55)
    }

    private var borderColor: Color {
        if overlapping {
            // Warning visual de dos worklogs / entries del mismo origen
            // que se pisan en el tiempo.  Mismos colores que el
            // plasmoide KDE: dark orange (#FF8C00) para Jira-Jira,
            // gold (#FFD700) para Clockify-Clockify.
            return block.kind == .clockify
                ? Color(red: 255/255, green: 215/255, blue: 0/255)     // #FFD700 gold
                : Color(red: 255/255, green: 140/255, blue: 0/255)     // #FF8C00 dark orange
        }
        if block.kind == .jira || block.kind == .jira2 {
            if let c = Color(hex: jiraColorHex) { return c.opacity(0.95) }
            return Color(red: 120/255, green: 110/255, blue: 200/255)
        }
        if useProjectColor, let c = Color(hex: block.projectHex) {
            return c.opacity(0.95)
        }
        return Color(red: 70/255, green: 170/255, blue: 100/255)
    }

    /// Cuando el bloque está en overlap, engrosamos el borde a 2 px para
    /// que sea bien visible.
    private var borderWidth: CGFloat { overlapping ? 2 : 1 }

    var body: some View {
        // Color.clear claims the parent-given frame for layout / hit-testing,
        // y arriba ponemos el bloque visual real cuyo tamaño y posición
        // pueden cambiar libremente durante el drag/resize sin afectar al
        // padre.  Ojo: las gestures van sobre la Color.clear (no se mueve),
        // así que `value.startLocation` es estable.
        GeometryReader { geo in
            let baseHeight = geo.size.height
            Color.clear
                .overlay(alignment: .topLeading) {
                    visualBlock(width: geo.size.width,
                                height: Swift.max(rowHeight / 3, baseHeight + resizeHeightDelta))
                        .offset(x: dragOffsetX, y: dragOffsetY + resizeTopDy)
                }
                .overlay(alignment: .topTrailing) {
                    if hovered {
                        duplicateButton
                            .padding(2)   // 2 px desde la esquina
                    }
                }
                .contentShape(Rectangle())
                // `.onHover` para tracking del estado (mostrar el botón
                // duplicar).  El cursor lo manejamos con
                // `.onContinuousHover` para saber la Y exacta y elegir
                // entre las 4-flechas (mover, centro) o las 2-flechas
                // verticales (resize, top/bottom 5 px).
                .onHover { isHovering in
                    hovered = isHovering
                    if !isHovering { NSCursor.arrow.set() }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        if loc.y < edgePx || loc.y > baseHeight - edgePx {
                            NSCursor.resizeUpDown.set()
                        } else {
                            Self.moveAllDirections.set()
                        }
                    case .ended:
                        NSCursor.arrow.set()
                    }
                }
                // El bloque arrastrado se dibuja arriba de los demás del
                // mismo padre (no llega a tapar columnas vecinas, pero al
                // menos no queda detrás de bloques contiguos).
                .zIndex(dragMode == .move ? 999 : 0)
                .onTapGesture(perform: onTap)
                // Right-click: menú con duplicar / eliminar.
                .contextMenu {
                    Button {
                        onDuplicate()
                    } label: {
                        Label("Duplicar", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                }
                // `highPriorityGesture` (en vez de `gesture`) es el
                // equivalente al `preventStealing: true` del MouseArea
                // QML: gana frente al pan del ScrollView que envuelve
                // al calendario, así un drag sobre un bloque no termina
                // scrolleando la grilla.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .local)
                        .onChanged { value in
                            if dragMode == .none {
                                let y = value.startLocation.y
                                if y < edgePx                       { dragMode = .resizeTop }
                                else if y > baseHeight - edgePx     { dragMode = .resizeBottom }
                                else                                 { dragMode = .move }
                                // Capturamos Shift una sola vez al
                                // iniciar el drag (el plasmoide hace lo
                                // mismo).  Cambiar el modificador en
                                // medio del drag no toggleea.
                                dragFine = NSEvent.modifierFlags.contains(.shift)
                            }
                            apply(translation: value.translation, baseHeight: baseHeight)
                        }
                        .onEnded { value in
                            // dragOffset*/resize* ya quedaron snappeados
                            // del último `apply()`.  Sólo emitimos hacia
                            // el padre con la translation cruda + el
                            // `fine` capturado — su propio handler
                            // re-snappea con el mismo step.
                            let mode = dragMode
                            let fine = dragFine
                            dragMode = .none
                            dragFine = false
                            switch mode {
                            case .move:           onMove(value.translation.width, value.translation.height, fine)
                            case .resizeTop:      onResizeTop(value.translation.height, fine)
                            case .resizeBottom:   onResizeBottom(value.translation.height, fine)
                            case .none: break
                            }
                        }
                )
                // El refetch del padre actualizó la posición/duración del
                // bloque: ya lo está pintando bien, así que limpiamos los
                // deltas locales para no quedar offset el doble.
                .onChange(of: block.startedMs) {
                    dragOffsetX = 0
                    dragOffsetY = 0
                }
                .onChange(of: block.durationSec) {
                    resizeTopDy = 0
                    resizeHeightDelta = 0
                }
        }
    }

    /// Aplica el `translation` del DragGesture al estado visual del
    /// bloque según el modo activo.  El cursor SE SNAPPEA EN CADA
    /// `onChanged` (no sólo al soltar), así el bloque salta de celda
    /// en celda en lugar de seguir suavemente al cursor.
    ///
    /// Para move y resize-bottom clampamos al rango de la columna
    /// (`[0, columnHeight]`) para que el bloque no se escape por
    /// debajo de las 18:00 en modo 9h.
    private func apply(translation: CGSize, baseHeight: CGFloat) {
        // Paso vertical en px del snap actual: una fila completa
        // (30 min) o un tercio (10 min) con Shift.  `minH` es lo más
        // chico que puede medir el bloque visualmente.
        let stepPx: CGFloat = dragFine ? rowHeight / 3 : rowHeight
        let minH: CGFloat = stepPx
        switch dragMode {
        case .move:
            let snappedX = columnWidth > 0
                ? (translation.width / columnWidth).rounded() * columnWidth
                : 0
            var snappedY = (translation.height / stepPx).rounded() * stepPx
            if columnHeight > 0 {
                // newY (= blockYInColumn + snappedY) ∈ [0, columnHeight − height]
                let maxOffset = Swift.max(0, columnHeight - blockYInColumn - baseHeight)
                let minOffset = -blockYInColumn
                if snappedY < minOffset { snappedY = minOffset }
                if snappedY > maxOffset { snappedY = maxOffset }
            }
            dragOffsetX = snappedX
            dragOffsetY = snappedY
        case .resizeTop:
            // El delta se snappea al step actual para que el borde top
            // caiga sobre un boundary de 30 / 10 min.  Clampamos contra
            // el límite superior y el mínimo de altura.
            var dy = (translation.height / stepPx).rounded() * stepPx
            if baseHeight - dy < minH      { dy = baseHeight - minH }
            if blockYInColumn + dy < 0     { dy = -blockYInColumn }
            resizeTopDy = dy
            resizeHeightDelta = -dy
        case .resizeBottom:
            var dh = (translation.height / stepPx).rounded() * stepPx
            if baseHeight + dh < minH { dh = minH - baseHeight }
            if columnHeight > 0 {
                // newH = baseHeight + dh ≤ columnHeight - blockYInColumn
                let maxDh = Swift.max(minH - baseHeight,
                                      columnHeight - blockYInColumn - baseHeight)
                if dh > maxDh { dh = maxDh }
            }
            resizeHeightDelta = dh
        case .none:
            break
        }
    }

    /// El "render" del bloque sin gestures.  Se le pasa el width/height
    /// resultantes para que el ZStack tenga tamaño explícito y los textos
    /// se acomoden bien aún en modo resize.
    @ViewBuilder
    private func visualBlock(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )

            if single {
                // Bloque ≤30 min: sólo cabe una línea — truncamos al
                // final para que se vea al menos la hora + key.
                Text(block.compactText)
                    .font(.system(size: blockFontSize, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Bloque >30 min: rango en bold arriba, después la línea
                // principal con soft-wrap, y si es Clockify y tiene
                // proyecto, una tercera línea con la descripción.  El
                // modo combinado mantiene este layout (sólo cambia el
                // tamaño del font), matcheando el plasmoide KDE.
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.topText)
                        .font(.system(size: blockFontSize, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(block.bottomText)
                        .font(.system(size: blockFontSize, weight: .regular))
                        .lineLimit(block.extraText.isEmpty ? 3 : 1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !block.extraText.isEmpty {
                        Text(block.extraText)
                            .font(.system(size: blockFontSize, weight: .regular))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(0.85)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: width, height: height)
    }

    /// Cuadradito 16×16 con ícono de copia, en la esquina superior
    /// derecha.  El `.onTapGesture` propio impide que el click viaje al
    /// DragGesture del bloque (que arrancaría un resize-top), porque
    /// SwiftUI prioriza la gesture del overlay (más interno) sobre la
    /// del Color.clear que está abajo.
    private var duplicateButton: some View {
        Image(systemName: "doc.on.doc")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
            .onHover { isHovering in
                // Cuando el cursor sale del botón pero sigue dentro del
                // bloque, volvemos a resizeUpDown (que es lo que pinta
                // la onHover del bloque exterior).
                if isHovering { NSCursor.pointingHand.set() }
                else          { NSCursor.resizeUpDown.set() }
            }
            .onTapGesture { onDuplicate() }
            .help("Duplicar este worklog")
    }

    /// Cursor de "4 flechas" para el modo move.  Lo dibujamos a partir
    /// del SF Symbol `arrow.up.and.down.and.arrow.left.and.right` con
    /// fondo negro + relleno blanco para que se vea sobre cualquier
    /// fondo de bloque, igual que los cursores nativos de macOS.
    static let moveAllDirections: NSCursor = {
        let canvas = NSSize(width: 22, height: 22)
        let img = NSImage(size: canvas)
        img.lockFocus()

        // Outline negro (bold) un poquito más grande.
        let outlineConfig = NSImage.SymbolConfiguration(pointSize: 17, weight: .heavy)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        if let outline = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: "Mover bloque"
        )?.withSymbolConfiguration(outlineConfig) {
            let r = NSRect(x: (canvas.width - outline.size.width) / 2,
                           y: (canvas.height - outline.size.height) / 2,
                           width: outline.size.width, height: outline.size.height)
            outline.draw(in: r)
        }
        // Relleno blanco arriba.
        let fillConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let fill = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(fillConfig) {
            let r = NSRect(x: (canvas.width - fill.size.width) / 2,
                           y: (canvas.height - fill.size.height) / 2,
                           width: fill.size.width, height: fill.size.height)
            fill.draw(in: r)
        }

        img.unlockFocus()
        return NSCursor(image: img,
                        hotSpot: NSPoint(x: canvas.width / 2, y: canvas.height / 2))
    }()
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
