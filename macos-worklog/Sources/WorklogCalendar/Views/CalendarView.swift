import AppKit
import SwiftUI

/// Resultado de un drag sobre una columna: día (índice 0..6), hora de
/// inicio y hora de fin en ms epoch.  El lado izquierdo / derecho sólo
/// importa en modo combinado.
struct DragSelection {
    let dayIndex: Int
    let startMs: Double
    let endMs: Double
    let pressLeft: Bool
}

/// Grid semanal Domingo→Sábado con header de totales, columna de horas
/// a la izquierda y 7 columnas de día.  Internamente cada columna es un
/// `DayColumnView` con su propio drag-to-create.
struct CalendarView: View {
    let weekStart: Date
    let jiraBlocks: [CalendarBlock]      // ya filtrados por modo
    let clockifyBlocks: [CalendarBlock]
    let source: WorklogSource
    let viewMode: ViewHourMode
    let dailyTargetHours: Double

    let onCreateJira: (DragSelection) -> Void
    let onCreateClockify: (DragSelection) -> Void
    let onEditJira: (CalendarBlock) -> Void
    let onEditClockify: (CalendarBlock) -> Void
    /// Llamados cuando el usuario suelta un drag-to-move o un resize.
    /// El padre recibe `(bloque, newStartMs, newDurationSec)` ya
    /// snappeados al slot y clampeados a la semana visible.  Una sola
    /// signatura cubre las tres gesturas (move, resize-top, resize-bottom).
    let onMoveJira: (CalendarBlock, Double, Int) -> Void
    let onMoveClockify: (CalendarBlock, Double, Int) -> Void
    /// Llamados al click en el botón "duplicar" de un bloque.  El padre
    /// crea una copia idéntica vía `createWorklog` / `createEntry`.
    let onDuplicateJira: (CalendarBlock) -> Void
    let onDuplicateClockify: (CalendarBlock) -> Void
    /// Eliminar definitivamente el bloque (menú contextual).
    let onDeleteJira: (CalendarBlock) -> Void
    let onDeleteClockify: (CalendarBlock) -> Void

    private let rowHeight: CGFloat = 22
    private let hourColumnWidth: CGFloat = 56
    private let headerRowHeight: CGFloat = 22
    private let totalsRowHeight: CGFloat = 22

    private var combined: Bool { source == .jiraClockify }
    private var showJira: Bool { source == .jira || source == .jiraClockify }
    private var showClockify: Bool { source == .clockify || source == .jiraClockify }

    private var slots: Int { viewMode.slotsPerDay }

    /// `true` si la columna `idx` representa el día de hoy.
    private func isToday(_ idx: Int) -> Bool {
        let day = weekStart.addingTimeInterval(Double(idx) * 86_400)
        return Calendar.current.isDateInToday(day)
    }

    /// `weekStart` es Domingo → idx 0 (Dom) y 6 (Sáb) son fin de semana.
    private func isWeekend(_ idx: Int) -> Bool { idx == 0 || idx == 6 }

    /// IDs de bloques que se pisan en el tiempo con otro del mismo
    /// origen.  Lo usamos para que `EntryBlockView` los borde de naranja
    /// (Jira) o amarillo (Clockify) y el usuario detecte duplicados.
    private func overlappingIds(in blocks: [CalendarBlock]) -> Set<String> {
        var out: Set<String> = []
        for i in 0..<blocks.count {
            let a = blocks[i]
            let aEnd = a.startedMs + Double(a.durationSec) * 1000
            for j in (i + 1)..<blocks.count {
                let b = blocks[j]
                let bEnd = b.startedMs + Double(b.durationSec) * 1000
                if a.startedMs < bEnd && b.startedMs < aEnd {
                    out.insert(a.id)
                    out.insert(b.id)
                }
            }
        }
        return out
    }

    /// Único punto de salida hacia el padre para los tres gestos.
    /// Clampea al rango visible (Domingo→Sábado siguiente) y obliga un
    /// piso de 10 min de duración (antes 30; bajó con la granularidad
    /// fina por Shift).  No clampea por día: bloques que cruzan la
    /// medianoche son legales en Jira y Clockify.
    private func emitChange(block: CalendarBlock,
                            newStartMs: Double,
                            newDurationSec: Int,
                            isJira: Bool) {
        let wsMs = weekStart.timeIntervalSince1970 * 1000
        let weMs = wsMs + 7 * 86_400_000
        var start = newStartMs
        let dur = Swift.max(600, newDurationSec)         // 10 min floor
        let durMs = Double(dur) * 1000
        if start < wsMs            { start = wsMs }
        if start + durMs > weMs    { start = weMs - durMs }
        if start == block.startedMs && dur == block.durationSec { return }
        if isJira { onMoveJira(block, start, dur) }
        else      { onMoveClockify(block, start, dur) }
    }

    /// Convierte un offset en píxeles a una cantidad de minutos
    /// snappeada al step actual (10 con Shift, 30 sin Shift).
    private func pxToSnappedMin(_ px: CGFloat, fine: Bool) -> Int {
        let g = fine ? 10 : 30
        let rawMin = (px / rowHeight) * 30
        return Int((rawMin / CGFloat(g)).rounded()) * g
    }

    /// Drag X+Y dentro del calendario.  X se snappea al ancho de columna
    /// (= cambio de día) e Y al step actual (30 min, o 10 min con Shift).
    fileprivate func handleMove(block: CalendarBlock,
                                deltaX: CGFloat, deltaY: CGFloat,
                                columnWidth: CGFloat,
                                isJira: Bool,
                                fine: Bool) {
        let stepMin = pxToSnappedMin(deltaY, fine: fine)
        let days    = columnWidth > 0 ? Int(round(deltaX / columnWidth)) : 0
        if stepMin == 0 && days == 0 { return }
        let newStart = block.startedMs
            + Double(days) * 86_400_000
            + Double(stepMin) * 60_000
        emitChange(block: block,
                   newStartMs: newStart,
                   newDurationSec: block.durationSec,
                   isJira: isJira)
    }

    /// Resize del borde superior: deltaY positivo = inicio más tarde,
    /// duración baja por la misma cantidad.
    fileprivate func handleResizeTop(block: CalendarBlock, deltaY: CGFloat,
                                      isJira: Bool, fine: Bool) {
        let stepMin = pxToSnappedMin(deltaY, fine: fine)
        if stepMin == 0 { return }
        let newStart = block.startedMs + Double(stepMin) * 60_000
        let newDur   = block.durationSec - stepMin * 60
        emitChange(block: block,
                   newStartMs: newStart,
                   newDurationSec: newDur,
                   isJira: isJira)
    }

    /// Resize del borde inferior: sólo cambia la duración.
    fileprivate func handleResizeBottom(block: CalendarBlock, deltaH: CGFloat,
                                         isJira: Bool, fine: Bool) {
        let stepMin = pxToSnappedMin(deltaH, fine: fine)
        if stepMin == 0 { return }
        let newDur = block.durationSec + stepMin * 60
        emitChange(block: block,
                   newStartMs: block.startedMs,
                   newDurationSec: newDur,
                   isJira: isJira)
    }

    /// Devuelve los bloques que caen en el día `idx` (0..6).
    private func blocks(_ list: [CalendarBlock], dayIndex idx: Int) -> [CalendarBlock] {
        let dayStartMs = weekStart.timeIntervalSince1970 * 1000 + Double(idx) * 86_400_000
        let dayEndMs = dayStartMs + 86_400_000
        return list.filter { $0.startedMs >= dayStartMs && $0.startedMs < dayEndMs }
    }

    private func totalSecForDay(_ idx: Int) -> Int {
        // Total prioriza Jira cuando se muestra (más cercano a lo "loggeable").
        let list = showJira ? blocks(jiraBlocks, dayIndex: idx) : blocks(clockifyBlocks, dayIndex: idx)
        return list.reduce(0) { $0 + $1.durationSec }
    }

    private func formatTotal(_ sec: Int) -> String {
        if sec <= 0 { return "—" }
        let h = sec / 3600
        let m = (sec % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func formatDiff(_ sec: Int) -> String {
        let target = Int(dailyTargetHours * 3600)
        let diff = sec - target
        if diff == 0 { return "" }
        let sign = diff > 0 ? "+" : "-"
        let abs = Swift.abs(diff)
        let h = abs / 3600
        let m = (abs % 3600) / 60
        var body = sign
        if h > 0 { body += "\(h)h" }
        if m > 0 { body += (h > 0 ? " " : "") + "\(m)m" }
        return "(" + body + ")"
    }

    private func dayHeader(_ idx: Int) -> String {
        let dayStart = weekStart.addingTimeInterval(Double(idx) * 86400)
        let names = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]
        let months = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"]
        let cal = Calendar.current
        let day = cal.component(.day, from: dayStart)
        let m = cal.component(.month, from: dayStart) - 1
        return "\(names[idx]), \(day)/\(months[m])"
    }

    private func slotLabel(_ slot: Int) -> String {
        let minutes = viewMode.startHour * 60 + slot * 30
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%02d:%02d", h, m)
    }

    var body: some View {
        ScrollView([.vertical]) {
            VStack(spacing: 0) {
                headerRow
                bodyGrid
            }
        }
    }

    // MARK: - Header (totals)

    private var headerRow: some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.08))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                Text("total")
                    .font(.system(size: 9))
                    .opacity(0.6)
            }
            .frame(width: hourColumnWidth, height: headerRowHeight + totalsRowHeight)

            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 0) {
                    ZStack {
                        // Hoy gana sobre weekend; weekend gana sobre weekday normal.
                        Rectangle()
                            .fill(isToday(i)
                                  ? Color.accentColor.opacity(0.22)
                                  : (isWeekend(i)
                                     ? Color.black.opacity(0.18)
                                     : Color.white.opacity(0.04)))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                        Text(dayHeader(i))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(height: headerRowHeight)

                    ZStack {
                        Rectangle()
                            .fill(totalsBackgroundFor(i))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                        let s = totalSecForDay(i)
                        Text(s <= 0 ? "—" : "Loggeado: \(formatTotal(s)) \(formatDiff(s))")
                            .font(.system(size: 9))
                    }
                    .frame(height: totalsRowHeight)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func totalsBackgroundFor(_ idx: Int) -> Color {
        let s = totalSecForDay(idx)
        if s <= 0 { return Color.white.opacity(0.02) }
        let target = Int(dailyTargetHours * 3600)
        return s >= target
            ? Color(red: 46/255, green: 204/255, blue: 113/255).opacity(0.18)
            : Color(red: 241/255, green: 196/255, blue: 15/255).opacity(0.18)
    }

    // MARK: - Body (hour col + 7 day cols)

    private var bodyGrid: some View {
        // Computamos los IDs de bloques con overlap UNA vez por render
        // (no por columna) — abrimos el cálculo a toda la semana así
        // un overlap que cruza la medianoche también se marca.
        let jiraOverlap = overlappingIds(in: jiraBlocks)
        let clockifyOverlap = overlappingIds(in: clockifyBlocks)
        return HStack(spacing: 0) {
            hourColumn
            ForEach(0..<7, id: \.self) { i in
                DayColumnView(
                    dayIndex: i,
                    weekStart: weekStart,
                    viewMode: viewMode,
                    rowHeight: rowHeight,
                    jiraBlocks: showJira ? blocks(jiraBlocks, dayIndex: i) : [],
                    clockifyBlocks: showClockify ? blocks(clockifyBlocks, dayIndex: i) : [],
                    combined: combined,
                    sourcePure: source,
                    isToday: isToday(i),
                    isWeekend: isWeekend(i),
                    onCreateJira: onCreateJira,
                    onCreateClockify: onCreateClockify,
                    onEditJira: onEditJira,
                    onEditClockify: onEditClockify,
                    onMoveJira: { b, dx, dy, w, fine in
                        handleMove(block: b, deltaX: dx, deltaY: dy,
                                   columnWidth: w, isJira: true, fine: fine)
                    },
                    onMoveClockify: { b, dx, dy, w, fine in
                        handleMove(block: b, deltaX: dx, deltaY: dy,
                                   columnWidth: w, isJira: false, fine: fine)
                    },
                    onResizeTopJira:        { b, dy, fine in handleResizeTop(block: b, deltaY: dy, isJira: true,  fine: fine) },
                    onResizeTopClockify:    { b, dy, fine in handleResizeTop(block: b, deltaY: dy, isJira: false, fine: fine) },
                    onResizeBottomJira:     { b, dh, fine in handleResizeBottom(block: b, deltaH: dh, isJira: true,  fine: fine) },
                    onResizeBottomClockify: { b, dh, fine in handleResizeBottom(block: b, deltaH: dh, isJira: false, fine: fine) },
                    onDuplicateJira:        onDuplicateJira,
                    onDuplicateClockify:    onDuplicateClockify,
                    onDeleteJira:           onDeleteJira,
                    onDeleteClockify:       onDeleteClockify,
                    jiraOverlapIds:         jiraOverlap,
                    clockifyOverlapIds:     clockifyOverlap
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var hourColumn: some View {
        // Las etiquetas se alinean al TOPE de cada slot — esto es lo
        // que esperan ver los usuarios: un bloque que arranca a las
        // 09:00 tiene su borde superior justo en la línea "09:00".
        // (Antes estaban centradas verticalmente y el bloque parecía
        // "salir" de la grilla.)
        VStack(spacing: 0) {
            ForEach(0..<slots, id: \.self) { slot in
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .fill(slot % 2 == 0 ? Color.white.opacity(0.02) : Color.clear)
                    Text(slotLabel(slot))
                        .font(.system(size: 9, design: .monospaced))
                        .opacity(slot % 2 == 0 ? 0.85 : 0.45)
                        .padding(.trailing, 4)
                        .offset(y: -5)        // que el baseline caiga sobre el borde superior del slot
                }
                .frame(height: rowHeight)
            }
        }
        .frame(width: hourColumnWidth)
    }
}

/// Una columna-día con su grid de fondo, divisor para modo combinado,
/// drag-to-create y los bloques de Jira/Clockify posicionados.
private struct DayColumnView: View {
    let dayIndex: Int
    let weekStart: Date
    let viewMode: ViewHourMode
    let rowHeight: CGFloat
    let jiraBlocks: [CalendarBlock]
    let clockifyBlocks: [CalendarBlock]
    let combined: Bool
    let sourcePure: WorklogSource
    let isToday: Bool
    let isWeekend: Bool
    let onCreateJira: (DragSelection) -> Void
    let onCreateClockify: (DragSelection) -> Void
    let onEditJira: (CalendarBlock) -> Void
    let onEditClockify: (CalendarBlock) -> Void
    /// Drag-to-move:  recibimos `(bloque, dx, dy, anchoColumna, fine)`.
    /// `fine == true` ⇔ Shift estaba apretado al iniciar el drag, lo
    /// que baja la granularidad de 30 min a 10 min.
    let onMoveJira:     (CalendarBlock, CGFloat, CGFloat, CGFloat, Bool) -> Void
    let onMoveClockify: (CalendarBlock, CGFloat, CGFloat, CGFloat, Bool) -> Void
    /// Resize del borde superior / inferior:  `(bloque, delta px, fine)`.
    let onResizeTopJira:        (CalendarBlock, CGFloat, Bool) -> Void
    let onResizeTopClockify:    (CalendarBlock, CGFloat, Bool) -> Void
    let onResizeBottomJira:     (CalendarBlock, CGFloat, Bool) -> Void
    let onResizeBottomClockify: (CalendarBlock, CGFloat, Bool) -> Void
    /// Botón "duplicar" del bloque.
    let onDuplicateJira:        (CalendarBlock) -> Void
    let onDuplicateClockify:    (CalendarBlock) -> Void
    /// Menú contextual "Eliminar" del bloque.
    let onDeleteJira:           (CalendarBlock) -> Void
    let onDeleteClockify:       (CalendarBlock) -> Void
    /// IDs de bloques que pisan a otro del mismo origen (overlap visual
    /// para destacar duplicados pre-sync Jira → Clockify).
    let jiraOverlapIds:         Set<String>
    let clockifyOverlapIds:     Set<String>

    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var pressLeft: Bool = true
    /// Shift apretado al iniciar el drag-to-create → snap a 10 min.
    @State private var pressFine: Bool = false

    /// Flash visual del click-to-create (35 0ms) — mismo formato que el
    /// rectángulo del drag-to-create para dar feedback inmediato.
    @State private var clickFlash: ClickFlash? = nil
    struct ClickFlash {
        let top: CGFloat
        let bottom: CGFloat
        let leftX: CGFloat
        let width: CGFloat
        let label: String
    }

    private var totalHeight: CGFloat { CGFloat(viewMode.slotsPerDay) * rowHeight }

    /// Píxeles por slot del paso actual: una fila completa (30 min)
    /// normalmente, un tercio de fila (10 min) si Shift estaba apretado.
    private var stepPx: CGFloat { pressFine ? rowHeight / 3 : rowHeight }

    private var snappedTop: CGFloat {
        guard let s = dragStart, let c = dragCurrent else { return 0 }
        let raw = min(s.y, c.y)
        let maxPx = totalHeight
        return Swift.max(0, Swift.min(maxPx, CGFloat((raw / stepPx).rounded()) * stepPx))
    }

    private var snappedBottom: CGFloat {
        guard let s = dragStart, let c = dragCurrent else { return stepPx }
        let raw = max(s.y, c.y)
        let maxPx = totalHeight
        let snapped = Swift.max(0, Swift.min(maxPx, CGFloat((raw / stepPx).rounded()) * stepPx)) + stepPx
        return Swift.max(snapped, snappedTop + stepPx)
    }

    /// Convierte un offset en px dentro del día a ms absolutos.
    private func pxToMs(_ px: CGFloat) -> Double {
        let dayStart = weekStart.timeIntervalSince1970 * 1000 + Double(dayIndex) * 86_400_000
        let minFromStart = Double(px / rowHeight) * 30
        return dayStart + (Double(viewMode.startHour) * 60 + minFromStart) * 60_000
    }

    /// Click izquierdo en vacío → crea un worklog de 30 min anclado al
    /// slot del cursor.  En modo combinado el lado izquierdo del día
    /// dispara crear en Jira, el derecho en Clockify.
    private func createBlockAt(location: CGPoint, width: CGFloat) {
        let slot = Int(floor(location.y / rowHeight))
        guard slot >= 0, slot < viewMode.slotsPerDay else { return }
        let top    = CGFloat(slot) * rowHeight
        let bottom = top + rowHeight
        let startMs = pxToMs(top)
        let endMs   = startMs + 30 * 60 * 1000
        let pressLeft = combined ? location.x < width / 2 : true

        // Flash visual del rectángulo azul antes de abrir el modal.  Se
        // auto-dismiss después de 400 ms — para entonces el sheet ya
        // está montado y el feedback se pisa con el modal.
        let leftX: CGFloat = combined ? (pressLeft ? 0 : width / 2) : 0
        let flashW: CGFloat = combined ? width / 2 : width
        clickFlash = ClickFlash(top: top, bottom: bottom,
                                leftX: leftX, width: flashW,
                                label: "\(timeOf(startMs))–\(timeOf(endMs))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Sólo limpiamos si todavía es este flash (evita race con un
            // nuevo click rápido).
            self.clickFlash = nil
        }

        let sel = DragSelection(dayIndex: dayIndex,
                                startMs: startMs, endMs: endMs,
                                pressLeft: pressLeft)
        if combined {
            if pressLeft { onCreateJira(sel) } else { onCreateClockify(sel) }
        } else if sourcePure == .jira {
            onCreateJira(sel)
        } else {
            onCreateClockify(sel)
        }
    }

    /// Formato compacto "HH:MM" para las etiquetas del drag selection.
    private func timeOf(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// Posición Y de un bloque con precisión de minutos — así un bloque
    /// creado con Shift (10 min) se ve a 1/3 de fila en vez de 1 fila
    /// entera.
    private func yFor(_ b: CalendarBlock) -> CGFloat {
        let dayStart = weekStart.timeIntervalSince1970 * 1000 + Double(dayIndex) * 86_400_000
        let minFromViewStart = (b.startedMs - dayStart) / 60_000 - Double(viewMode.startHour) * 60
        return CGFloat(minFromViewStart / 30) * rowHeight
    }
    private func heightFor(_ b: CalendarBlock) -> CGFloat {
        let h = CGFloat(Double(b.durationSec) / 1800) * rowHeight  // 1800s = 30min = rowHeight
        return Swift.max(rowHeight / 3, h)                         // floor visual ≈ 10 min
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                // Tinte de fin de semana debajo del de "hoy" (así un
                // sábado-que-es-hoy se ve con el acento, no oscuro).
                if isWeekend {
                    Rectangle()
                        .fill(Color.black.opacity(0.18))
                }
                // Tinte del día actual debajo del grid, así el patrón de
                // filas alternadas sigue siendo visible por encima.
                if isToday {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.10))
                }

                // Background grid.
                VStack(spacing: 0) {
                    ForEach(0..<viewMode.slotsPerDay, id: \.self) { i in
                        Rectangle()
                            .fill(i % 2 == 0 ? Color.white.opacity(0.03) : Color.clear)
                            .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
                            .frame(height: rowHeight)
                    }
                }

                // Vertical divider en modo combinado.
                if combined {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1)
                        .offset(x: width / 2 - 0.5)
                }

                // Drag selection rectangle — con etiqueta del rango
                // horario al centro para que el usuario vea "10:00–10:30"
                // mientras arrastra.
                if dragStart != nil, dragCurrent != nil {
                    let leftX: CGFloat = combined ? (pressLeft ? 0 : width / 2) : 0
                    let w: CGFloat = combined ? width / 2 : width
                    let label = "\(timeOf(pxToMs(snappedTop)))–\(timeOf(pxToMs(snappedBottom)))"
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.30))
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                        .overlay(
                            Text(label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.black.opacity(0.55))
                                )
                        )
                        .frame(width: w, height: snappedBottom - snappedTop)
                        .offset(x: leftX, y: snappedTop)
                        .allowsHitTesting(false)
                }

                // Flash de click izquierdo: mismo formato que el drag,
                // pero auto-dismiss después de ~350 ms para dar
                // feedback visual de que se creó el bloque.
                if let f = clickFlash {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.30))
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                        .overlay(
                            Text(f.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.black.opacity(0.55))
                                )
                        )
                        .frame(width: f.width, height: f.bottom - f.top)
                        .offset(x: f.leftX, y: f.top)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Jira blocks.
                ForEach(jiraBlocks) { b in
                    EntryBlockView(
                        block: b,
                        compactLayout: combined,
                        useProjectColor: false,
                        onTap: { onEditJira(b) },
                        onMove:          { dx, dy, fine in onMoveJira(b, dx, dy, width, fine) },
                        onResizeTop:     { dy, fine in onResizeTopJira(b, dy, fine) },
                        onResizeBottom:  { dh, fine in onResizeBottomJira(b, dh, fine) },
                        onDuplicate:     { onDuplicateJira(b) },
                        onDelete:        { onDeleteJira(b) },
                        overlapping:     jiraOverlapIds.contains(b.id),
                        rowHeight: rowHeight,
                        columnWidth: width,
                        columnHeight: totalHeight,
                        blockYInColumn: yFor(b)
                    )
                    .frame(width: combined ? (width / 2) - 3 : width - 4,
                           height: heightFor(b))
                    .offset(x: combined ? 2 : 2, y: yFor(b))
                }

                // Clockify blocks.
                ForEach(clockifyBlocks) { b in
                    EntryBlockView(
                        block: b,
                        compactLayout: combined,
                        useProjectColor: !combined,
                        onTap: { onEditClockify(b) },
                        onMove:          { dx, dy, fine in onMoveClockify(b, dx, dy, width, fine) },
                        onResizeTop:     { dy, fine in onResizeTopClockify(b, dy, fine) },
                        onResizeBottom:  { dh, fine in onResizeBottomClockify(b, dh, fine) },
                        onDuplicate:     { onDuplicateClockify(b) },
                        onDelete:        { onDeleteClockify(b) },
                        overlapping:     clockifyOverlapIds.contains(b.id),
                        rowHeight: rowHeight,
                        columnWidth: width,
                        columnHeight: totalHeight,
                        blockYInColumn: yFor(b)
                    )
                    .frame(width: combined ? (width / 2) - 3 : width - 4,
                           height: heightFor(b))
                    .offset(x: combined ? (width / 2) + 1 : 2, y: yFor(b))
                }
            }
            .frame(width: width, height: totalHeight)
            .contentShape(Rectangle())
            // Click izquierdo en vacío → crea un worklog de 30 min en el
            // slot clickeado.  El DragGesture(minimumDistance: 2) NO se
            // dispara para taps sin movimiento, así que llegan acá.  Si
            // hacés click sobre un bloque, su `.onTapGesture` interno
            // gana por hit-test (siempre hijo > padre en SwiftUI).
            .onTapGesture(coordinateSpace: .local) { location in
                createBlockAt(location: location, width: width)
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                            pressLeft = combined ? value.startLocation.x < width / 2 : true
                            // Capturamos Shift una sola vez al arrancar:
                            // cambiar el modificador en pleno drag no
                            // toggleea la granularidad, igual que el
                            // plasmoide.
                            pressFine = NSEvent.modifierFlags.contains(.shift)
                        }
                        dragCurrent = value.location
                    }
                    .onEnded { _ in
                        guard dragStart != nil, dragCurrent != nil else {
                            dragStart = nil; dragCurrent = nil; pressFine = false; return
                        }
                        // El visual ya está snappeado al step actual
                        // (`snappedTop` / `snappedBottom` usan `stepPx`),
                        // así que convertimos esos px directo a ms.
                        let startMs = pxToMs(snappedTop)
                        var endMs   = pxToMs(snappedBottom)
                        let minStepMs: Double = pressFine ? 10 * 60_000 : 30 * 60_000
                        if endMs <= startMs { endMs = startMs + minStepMs }
                        let sel = DragSelection(dayIndex: dayIndex,
                                                startMs: startMs,
                                                endMs: endMs,
                                                pressLeft: pressLeft)
                        dragStart = nil; dragCurrent = nil; pressFine = false
                        if combined {
                            if sel.pressLeft { onCreateJira(sel) } else { onCreateClockify(sel) }
                        } else if sourcePure == .jira {
                            onCreateJira(sel)
                        } else {
                            onCreateClockify(sel)
                        }
                    }
            )
        }
        .frame(height: totalHeight)
    }
}
