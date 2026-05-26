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

    /// Único punto de salida hacia el padre para los tres gestos.
    /// Clampea al rango visible (Domingo→Sábado siguiente) y obliga un
    /// piso de 30 min de duración.  No clampea por día: bloques que
    /// cruzan la medianoche son legales en Jira y Clockify.
    private func emitChange(block: CalendarBlock,
                            newStartMs: Double,
                            newDurationSec: Int,
                            isJira: Bool) {
        let wsMs = weekStart.timeIntervalSince1970 * 1000
        let weMs = wsMs + 7 * 86_400_000
        var start = newStartMs
        let dur = Swift.max(1800, newDurationSec)         // 30 min floor
        let durMs = Double(dur) * 1000
        if start < wsMs            { start = wsMs }
        if start + durMs > weMs    { start = weMs - durMs }
        if start == block.startedMs && dur == block.durationSec { return }
        if isJira { onMoveJira(block, start, dur) }
        else      { onMoveClockify(block, start, dur) }
    }

    /// Drag X+Y dentro del calendario.  X se snappea al ancho de columna
    /// (= cambio de día) e Y al alto de fila (= slot de 30 min).
    fileprivate func handleMove(block: CalendarBlock,
                                deltaX: CGFloat, deltaY: CGFloat,
                                columnWidth: CGFloat,
                                isJira: Bool) {
        let slots = Int(round(deltaY / rowHeight))
        let days  = columnWidth > 0 ? Int(round(deltaX / columnWidth)) : 0
        if slots == 0 && days == 0 { return }
        let newStart = block.startedMs
            + Double(days) * 86_400_000
            + Double(slots) * 30 * 60 * 1000
        emitChange(block: block,
                   newStartMs: newStart,
                   newDurationSec: block.durationSec,
                   isJira: isJira)
    }

    /// Resize del borde superior: deltaY positivo = inicio más tarde,
    /// duración baja por la misma cantidad.
    fileprivate func handleResizeTop(block: CalendarBlock, deltaY: CGFloat, isJira: Bool) {
        let slots = Int(round(deltaY / rowHeight))
        if slots == 0 { return }
        let newStart = block.startedMs + Double(slots) * 30 * 60 * 1000
        let newDur   = block.durationSec - slots * 1800
        emitChange(block: block,
                   newStartMs: newStart,
                   newDurationSec: newDur,
                   isJira: isJira)
    }

    /// Resize del borde inferior: sólo cambia la duración.
    fileprivate func handleResizeBottom(block: CalendarBlock, deltaH: CGFloat, isJira: Bool) {
        let slots = Int(round(deltaH / rowHeight))
        if slots == 0 { return }
        let newDur = block.durationSec + slots * 1800
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
        HStack(spacing: 0) {
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
                    onMoveJira: { b, dx, dy, w in
                        handleMove(block: b, deltaX: dx, deltaY: dy,
                                   columnWidth: w, isJira: true)
                    },
                    onMoveClockify: { b, dx, dy, w in
                        handleMove(block: b, deltaX: dx, deltaY: dy,
                                   columnWidth: w, isJira: false)
                    },
                    onResizeTopJira:        { b, dy in handleResizeTop(block: b, deltaY: dy, isJira: true) },
                    onResizeTopClockify:    { b, dy in handleResizeTop(block: b, deltaY: dy, isJira: false) },
                    onResizeBottomJira:     { b, dh in handleResizeBottom(block: b, deltaH: dh, isJira: true) },
                    onResizeBottomClockify: { b, dh in handleResizeBottom(block: b, deltaH: dh, isJira: false) },
                    onDuplicateJira:        onDuplicateJira,
                    onDuplicateClockify:    onDuplicateClockify
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var hourColumn: some View {
        VStack(spacing: 0) {
            ForEach(0..<slots, id: \.self) { slot in
                ZStack {
                    Rectangle()
                        .fill(slot % 2 == 0 ? Color.white.opacity(0.02) : Color.clear)
                    HStack {
                        Spacer()
                        Text(slotLabel(slot))
                            .font(.system(size: 9, design: .monospaced))
                            .opacity(slot % 2 == 0 ? 0.85 : 0.45)
                            .padding(.trailing, 4)
                    }
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
    /// Drag-to-move:  recibimos `(bloque, dx, dy, anchoColumna)`.  El padre
    /// (CalendarView) usa el ancho para convertir dx → días.
    let onMoveJira:     (CalendarBlock, CGFloat, CGFloat, CGFloat) -> Void
    let onMoveClockify: (CalendarBlock, CGFloat, CGFloat, CGFloat) -> Void
    /// Resize del borde superior / inferior:  el delta vertical en px.
    let onResizeTopJira:        (CalendarBlock, CGFloat) -> Void
    let onResizeTopClockify:    (CalendarBlock, CGFloat) -> Void
    let onResizeBottomJira:     (CalendarBlock, CGFloat) -> Void
    let onResizeBottomClockify: (CalendarBlock, CGFloat) -> Void
    /// Botón "duplicar" del bloque.
    let onDuplicateJira:        (CalendarBlock) -> Void
    let onDuplicateClockify:    (CalendarBlock) -> Void

    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var pressLeft: Bool = true

    private var totalHeight: CGFloat { CGFloat(viewMode.slotsPerDay) * rowHeight }

    private var snappedTop: CGFloat {
        guard let s = dragStart, let c = dragCurrent else { return 0 }
        let raw = min(s.y, c.y)
        return CGFloat(max(0, Int(round(raw / rowHeight)))) * rowHeight
    }

    private var snappedBottom: CGFloat {
        guard let s = dragStart, let c = dragCurrent else { return rowHeight }
        let raw = max(s.y, c.y)
        let snapped = CGFloat(max(0, Int(round(raw / rowHeight)))) * rowHeight + rowHeight
        return Swift.max(snapped, snappedTop + rowHeight)
    }

    private func msAtSlot(_ slot: Int) -> Double {
        let dayStart = weekStart.timeIntervalSince1970 * 1000 + Double(dayIndex) * 86_400_000
        return dayStart + Double(viewMode.startHour * 3600 + slot * 1800) * 1000
    }

    private func slotOfMs(_ ms: Double) -> Int {
        let dayStart = weekStart.timeIntervalSince1970 * 1000 + Double(dayIndex) * 86_400_000
        let local = ms - dayStart
        let slotsFromMidnight = Int(floor(local / (30 * 60 * 1000)))
        return slotsFromMidnight - viewMode.startHour * 2
    }

    private func yFor(_ b: CalendarBlock) -> CGFloat {
        CGFloat(slotOfMs(b.startedMs)) * rowHeight
    }
    private func heightFor(_ b: CalendarBlock) -> CGFloat {
        CGFloat(max(1, Int(round(Double(b.durationSec) / 1800)))) * rowHeight
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

                // Drag selection rectangle.
                if dragStart != nil, dragCurrent != nil {
                    let leftX: CGFloat = combined ? (pressLeft ? 0 : width / 2) : 0
                    let w: CGFloat = combined ? width / 2 : width
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.30))
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                        .frame(width: w, height: snappedBottom - snappedTop)
                        .offset(x: leftX, y: snappedTop)
                        .allowsHitTesting(false)
                }

                // Jira blocks.
                ForEach(jiraBlocks) { b in
                    EntryBlockView(
                        block: b,
                        compactLayout: combined,
                        useProjectColor: false,
                        onTap: { onEditJira(b) },
                        onMove:          { dx, dy in onMoveJira(b, dx, dy, width) },
                        onResizeTop:     { dy in onResizeTopJira(b, dy) },
                        onResizeBottom:  { dh in onResizeBottomJira(b, dh) },
                        onDuplicate:     { onDuplicateJira(b) },
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
                        onMove:          { dx, dy in onMoveClockify(b, dx, dy, width) },
                        onResizeTop:     { dy in onResizeTopClockify(b, dy) },
                        onResizeBottom:  { dh in onResizeBottomClockify(b, dh) },
                        onDuplicate:     { onDuplicateClockify(b) },
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
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                            pressLeft = combined ? value.startLocation.x < width / 2 : true
                        }
                        dragCurrent = value.location
                    }
                    .onEnded { _ in
                        guard let s = dragStart, let c = dragCurrent else {
                            dragStart = nil; dragCurrent = nil; return
                        }
                        let topSlot = max(0, Int(round(min(s.y, c.y) / rowHeight)))
                        let botSlot = max(topSlot + 1, Int(round(max(s.y, c.y) / rowHeight)) + 1)
                        let startMs = msAtSlot(topSlot)
                        var endMs = msAtSlot(botSlot)
                        if endMs <= startMs { endMs = startMs + 30 * 60 * 1000 }
                        let sel = DragSelection(dayIndex: dayIndex,
                                                startMs: startMs,
                                                endMs: endMs,
                                                pressLeft: pressLeft)
                        dragStart = nil; dragCurrent = nil
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
