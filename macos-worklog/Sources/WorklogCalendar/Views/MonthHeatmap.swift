import AppKit
import SwiftUI

/// Heatmap mensual con una columna por día y 4 filas:
///   1. letra de día de la semana (D L M Mi J V S) — gris en finde
///   2. número del día — gris en finde
///   3. horas de Clockify ese día (decimal)
///   4. horas de Jira ese día (decimal)
///
/// Las celdas se gradan rojo → amarillo → verde de 0 a 4h.  Hover sube
/// el alpha de la celda para resaltar.
///
/// Los totales vienen taggeados con el mes al que pertenecen
/// (`clockifyKey`, `jiraKey`); al navegar mes, una respuesta tardía del
/// mes anterior se ignora vía `_curKey()` para no pintar valores stale.
struct MonthHeatmap: View {
    @ObservedObject var jira: JiraWorklogStore
    @ObservedObject var clockify: ClockifyStore

    /// Click sobre una celda de día → el padre salta el calendario a
    /// esa semana.  Si es `nil`, las celdas no son clickeables.
    var onDaySelected: ((Date) -> Void)? = nil

    /// Trigger externo de refresh:  el padre lo incrementa cuando aprieta
    /// el botón global ↻ y observamos el cambio con `.onChange` para
    /// recargar los totales del mes.
    var refreshTrigger: Int = 0

    /// 0 = mes actual, -1 = mes anterior.
    @State private var monthOffset: Int = 0

    @State private var clockifyTotals: [Int: Int] = [:]
    @State private var jiraTotals: [Int: Int] = [:]
    @State private var clockifyKey: String = ""
    @State private var jiraKey: String = ""
    /// Se incrementa con cada `refresh()`; las respuestas con `reqId`
    /// distinto al actual se descartan.
    @State private var reqId: Int = 0

    private let letterRowH: CGFloat = 13
    private let numberRowH: CGFloat = 14
    private let cellRowH: CGFloat = 18

    private let monthNames = ["Enero","Febrero","Marzo","Abril","Mayo","Junio",
                              "Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"]
    private let dowLetters = ["D","L","M","Mi","J","V","S"]

    /// Fecha de referencia del 1° del mes visible.
    private var refDate: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = Date()
        var comps = cal.dateComponents([.year, .month], from: today)
        comps.day = 1
        let firstOfThisMonth = cal.date(from: comps) ?? today
        return cal.date(byAdding: .month, value: monthOffset, to: firstOfThisMonth)
            ?? firstOfThisMonth
    }

    private var year: Int {
        Calendar.current.component(.year, from: refDate)
    }
    private var monthIndex: Int {
        Calendar.current.component(.month, from: refDate) - 1   // 0..11
    }
    private var daysInMonth: Int {
        let cal = Calendar.current
        return cal.range(of: .day, in: .month, for: refDate)?.count ?? 30
    }

    private var curKey: String { "\(year)-\(monthIndex)" }

    private func dayOfWeek(_ day: Int) -> Int {
        var comps = DateComponents(); comps.year = year; comps.month = monthIndex + 1; comps.day = day
        guard let d = Calendar(identifier: .gregorian).date(from: comps) else { return 0 }
        return Calendar(identifier: .gregorian).component(.weekday, from: d) - 1   // 0=Dom
    }
    private func isWeekend(_ day: Int) -> Bool {
        let dow = dayOfWeek(day); return dow == 0 || dow == 6
    }
    private func weekdayLetter(_ day: Int) -> String { dowLetters[dayOfWeek(day)] }

    private func hoursDecimal(_ sec: Int) -> Double {
        if sec <= 0 { return 0 }
        return (Double(sec) / 3600 * 10).rounded() / 10
    }
    private func clkHours(_ day: Int) -> Double {
        guard clockifyKey == curKey else { return 0 }
        return hoursDecimal(clockifyTotals[day] ?? 0)
    }
    private func jiraHours(_ day: Int) -> Double {
        guard jiraKey == curKey else { return 0 }
        return hoursDecimal(jiraTotals[day] ?? 0)
    }
    private func fmtNum(_ h: Double) -> String {
        if h <= 0 { return "" }
        if h == floor(h) { return String(format: "%.0f", h) }
        return String(format: "%.1f", h)
    }

    // Totales del mes visible (en segundos), con la misma guarda de mes
    // que los lookups por día: si la data cargada pertenece a otro mes
    // (respuesta tardía), devolvemos 0 en vez de sumar valores stale.
    private var monthClockifySec: Int {
        guard clockifyKey == curKey else { return 0 }
        return clockifyTotals.values.reduce(0, +)
    }
    private var monthJiraSec: Int {
        guard jiraKey == curKey else { return 0 }
        return jiraTotals.values.reduce(0, +)
    }
    private func fmtHM(_ sec: Int) -> String {
        if sec <= 0 { return "0h" }
        let h = sec / 3600, m = (sec % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// Gradiente rojo → amarillo → verde, 0 a 4h.  Más de 4h queda verde.
    private func cellColor(_ h: Double) -> Color {
        if h <= 0 { return Color.white.opacity(0.06) }
        let red    = (231.0, 76.0, 60.0)
        let yellow = (241.0, 196.0, 15.0)
        let green  = (129.0, 199.0, 132.0)
        let c = min(4.0, h)
        let mix: (Double, (Double,Double,Double), (Double,Double,Double)) -> Color = { t, a, b in
            Color(red:   (a.0 + (b.0 - a.0) * t) / 255,
                  green: (a.1 + (b.1 - a.1) * t) / 255,
                  blue:  (a.2 + (b.2 - a.2) * t) / 255)
        }
        return c <= 2 ? mix(c / 2, red, yellow) : mix((c - 2) / 2, yellow, green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            grid
            monthTotalsFooter
        }
        .onAppear  { refresh() }
        .onChange(of: monthOffset)   { refresh() }
        .onChange(of: refreshTrigger) { refresh() }
    }

    /// Pie con el total de horas consumidas en el mes visible, por
    /// origen (Clockify / Jira).  Mismos íconos que la columna
    /// izquierda de la grilla.
    private var monthTotalsFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(fmtHM(monthClockifySec))
                .font(.caption2).bold()
            Spacer().frame(width: 6)
            Image(systemName: "checkmark.square")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(fmtHM(monthJiraSec))
                .font(.caption2).bold()
            Spacer()
            Text("Total del mes")
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(0.55)
        }
        .padding(.top, 2)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Horas del mes").font(.headline)
            Spacer()
            Button { monthOffset = -1 } label: { Image(systemName: "chevron.left") }
                .disabled(monthOffset <= -1)
                .help("Mes anterior")
            Text("\(monthNames[monthIndex]) \(String(year))")
                .font(.headline)
                .frame(minWidth: 130)
                .multilineTextAlignment(.center)
            Button { monthOffset = 0 } label: { Image(systemName: "chevron.right") }
                .disabled(monthOffset >= 0)
                .help("Mes actual")
        }
    }

    private var grid: some View {
        HStack(spacing: 1) {
            // Columna de íconos (mismo ancho que cada día).
            VStack(spacing: 1) {
                Spacer().frame(height: letterRowH)
                Spacer().frame(height: numberRowH)
                ZStack {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .help("Clockify")
                }
                .frame(height: cellRowH, alignment: .center)
                ZStack {
                    Image(systemName: "checkmark.square")
                        .font(.system(size: 12))
                        .help("Jira")
                }
                .frame(height: cellRowH, alignment: .center)
            }
            .frame(maxWidth: .infinity)

            ForEach(1...daysInMonth, id: \.self) { day in
                dayColumn(day)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayColumn(_ day: Int) -> some View {
        let weekend = isWeekend(day)
        let textColor: Color = weekend ? .secondary : .primary
        VStack(spacing: 1) {
            Text(weekdayLetter(day))
                .font(.system(size: 9))
                .foregroundColor(textColor)
                .opacity(weekend ? 0.8 : 1)
                .frame(height: letterRowH)
            Text("\(day)")
                .font(.system(size: 10, weight: weekend ? .regular : .bold))
                .foregroundColor(textColor)
                .frame(height: numberRowH)
            HoursCell(hours: clkHours(day), height: cellRowH,
                      onClick: clickHandler(forDay: day))
            HoursCell(hours: jiraHours(day), height: cellRowH,
                      onClick: clickHandler(forDay: day))
        }
    }

    /// Devuelve el handler que la `HoursCell` ejecuta al click — `nil`
    /// si el padre no quiere recibir clicks (la celda queda no
    /// interactiva).
    private func clickHandler(forDay day: Int) -> (() -> Void)? {
        guard let onDaySelected else { return nil }
        return {
            var comps = DateComponents()
            comps.year = year; comps.month = monthIndex + 1; comps.day = day
            if let d = Calendar(identifier: .gregorian).date(from: comps) {
                onDaySelected(d)
            }
        }
    }

    /// Una celda con número de horas (decimal) y fondo gradado.  Hover
    /// pone un overlay blanco para resaltar.
    struct HoursCell: View {
        let hours: Double
        let height: CGFloat
        /// `nil` = sin click handler → la celda no es interactiva (la
        /// versión read-only del heatmap).
        let onClick: (() -> Void)?
        @State private var hovered: Bool = false

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(MonthHeatmap.staticCellColor(hours))
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.black.opacity(0.15), lineWidth: 1))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .opacity(hovered ? 0.28 : 0)
                    .animation(.easeOut(duration: 0.18), value: hovered)
                Text(MonthHeatmap.staticFmtNum(hours))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(hours > 0 ? Color(white: 0.10) : .primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
            .onHover { isHovering in
                hovered = isHovering
                if onClick != nil {
                    if isHovering { NSCursor.pointingHand.set() }
                    else          { NSCursor.arrow.set() }
                }
            }
            .onTapGesture { onClick?() }
        }
    }

    /// Helpers static para que la subview `HoursCell` los pueda usar
    /// sin tener que recibir un binding al padre.
    fileprivate static func staticCellColor(_ h: Double) -> Color {
        if h <= 0 { return Color.white.opacity(0.06) }
        let red    = (231.0, 76.0, 60.0)
        let yellow = (241.0, 196.0, 15.0)
        let green  = (129.0, 199.0, 132.0)
        let c = min(4.0, h)
        let mix: (Double, (Double,Double,Double), (Double,Double,Double)) -> Color = { t, a, b in
            Color(red:   (a.0 + (b.0 - a.0) * t) / 255,
                  green: (a.1 + (b.1 - a.1) * t) / 255,
                  blue:  (a.2 + (b.2 - a.2) * t) / 255)
        }
        return c <= 2 ? mix(c / 2, red, yellow) : mix((c - 2) / 2, yellow, green)
    }
    fileprivate static func staticFmtNum(_ h: Double) -> String {
        if h <= 0 { return "" }
        if h == floor(h) { return String(format: "%.0f", h) }
        return String(format: "%.1f", h)
    }

    /// Limpia los totales del mes anterior, bumpea reqId y dispara los
    /// dos fetchs en paralelo.  Calcula el mes target a partir de
    /// `monthOffset` localmente (no de las computed-props `year` /
    /// `monthIndex`) para evitar el riesgo de stale state si `refresh`
    /// se llama desde dentro de un `.onChange(of: monthOffset)`.
    func refresh() {
        clockifyTotals = [:]; jiraTotals = [:]
        clockifyKey = "";     jiraKey = ""
        reqId += 1
        let myReq = reqId

        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        var comps = cal.dateComponents([.year, .month], from: Date())
        comps.day = 1
        let first = cal.date(from: comps) ?? Date()
        let target = cal.date(byAdding: .month, value: monthOffset, to: first) ?? first
        let y = cal.component(.year, from: target)
        let m = cal.component(.month, from: target) - 1
        let key = "\(y)-\(m)"

        clockify.fetchMonthTotals(year: y, monthIndex: m) { totals in
            guard myReq == reqId, let t = totals else { return }
            clockifyTotals = t; clockifyKey = key
        }
        jira.fetchMonthTotals(year: y, monthIndex: m) { totals in
            guard myReq == reqId, let t = totals else { return }
            jiraTotals = t; jiraKey = key
        }
    }
}
