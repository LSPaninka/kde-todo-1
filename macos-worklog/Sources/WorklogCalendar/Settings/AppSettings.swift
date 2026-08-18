import Foundation
import SwiftUI
import Combine

/// Modos visualizables del calendario.
enum WorklogSource: String, CaseIterable, Identifiable {
    case jira
    case jiraClockify = "jira-clockify"
    case clockify

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .jira:         return "Jira"
        case .jiraClockify: return "Jira / Clockify"
        case .clockify:     return "Clockify"
        }
    }
}

/// Modo de horas del grid.
enum ViewHourMode: String, CaseIterable, Identifiable {
    case h9 = "9h"     // 09:00 → 18:00
    case h24 = "24h"   // 00:00 → 24:00

    var id: String { rawValue }
    var startHour: Int { self == .h9 ? 9 : 0 }
    var endHour:   Int { self == .h9 ? 18 : 24 }
    var slotsPerDay: Int { (endHour - startHour) * 2 }
}

/// Estado persistente leído / escrito desde `UserDefaults` (excepto los
/// secretos, que viven en el Keychain). Es `ObservableObject` para que
/// SwiftUI se re-renderice automáticamente cuando algún campo cambia.
final class AppSettings: ObservableObject {

    // MARK: - General

    @Published var source: WorklogSource = .jira { didSet { ud.set(source.rawValue, forKey: "worklogSource") } }
    @Published var viewMode: ViewHourMode = .h9 { didSet { ud.set(viewMode.rawValue, forKey: "worklogViewMode") } }
    @Published var dailyTargetHours: Double = 8 { didSet { ud.set(dailyTargetHours, forKey: "worklogDailyTargetHours") } }
    @Published var showIssueSummary: Bool = false { didSet { ud.set(showIssueSummary, forKey: "worklogShowIssueSummary") } }
    @Published var debug: Bool = true { didSet { ud.set(debug, forKey: "worklogDebug") } }

    /// Si está apagado (default), la app corre como *agent app*: sólo el
    /// ícono de la barra de menús, sin ícono en el Dock ni en ⌘-Tab.
    /// Si está prendido, se comporta como app normal con ícono en el
    /// Dock.  El `AppDelegate` observa este flag y aplica la
    /// `NSApplication.ActivationPolicy` en caliente.
    @Published var showInDock: Bool = false { didSet { ud.set(showInDock, forKey: "worklogShowInDock") } }

    // Tamaño preferido de la ventana principal.
    @Published var windowWidth: Int = 1100 { didSet { ud.set(windowWidth, forKey: "worklogWindowWidth") } }
    @Published var windowHeight: Int = 800 { didSet { ud.set(windowHeight, forKey: "worklogWindowHeight") } }

    // Tamaño deseado de los sheets de edición (Jira / Clockify).  El
    // sheet los respeta como min y la ventana macOS los expande si hay
    // espacio.  Valores chicos quedan claustrofóbicos para el picker.
    @Published var modalWidth: Int = 720 { didSet { ud.set(modalWidth, forKey: "worklogModalWidth") } }
    @Published var modalHeight: Int = 600 { didSet { ud.set(modalHeight, forKey: "worklogModalHeight") } }

    // MARK: - Jira

    @Published var jiraSite: String = "" { didSet { ud.set(jiraSite, forKey: "jiraSite") } }
    @Published var jiraEmail: String = "" { didSet { ud.set(jiraEmail, forKey: "jiraEmail") } }
    @Published var jiraToken: String = "" {
        didSet { Keychain.set(jiraToken, for: "jira.token") }
    }
    @Published var jiraIssueJql: String =
        "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"
        { didSet { ud.set(jiraIssueJql, forKey: "worklogIssueJql") } }
    @Published var jiraIssueMax: Int = 50 { didSet { ud.set(jiraIssueMax, forKey: "worklogIssueMax") } }

    // MARK: - Segunda instancia de Jira

    /// Habilita una segunda cuenta/sitio de Jira.  Comparte el grid con
    /// la primera (los bloques pueden solaparse) y se distingue por color.
    @Published var jira2Enabled: Bool = false { didSet { ud.set(jira2Enabled, forKey: "jira2Enabled") } }
    @Published var jira2Site: String = "" { didSet { ud.set(jira2Site, forKey: "jira2Site") } }
    @Published var jira2Email: String = "" { didSet { ud.set(jira2Email, forKey: "jira2Email") } }
    @Published var jira2Token: String = "" { didSet { Keychain.set(jira2Token, for: "jira2.token") } }

    /// Color de los bloques por instancia (se dibujan translúcidos).
    @Published var jira1BlockColor: String = "#9b91e6" { didSet { ud.set(jira1BlockColor, forKey: "jira1BlockColor") } }
    @Published var jira2BlockColor: String = "#e69b91" { didSet { ud.set(jira2BlockColor, forKey: "jira2BlockColor") } }

    /// Proyecto de Clockify al que sincroniza cada instancia.  El dedup y
    /// la creación del sync quedan acotados a ese proyecto, así las dos
    /// instancias no se pisan entre sí.
    @Published var jira1ClockifyProjectId: String = "" { didSet { ud.set(jira1ClockifyProjectId, forKey: "jira1ClockifyProjectId") } }
    @Published var jira2ClockifyProjectId: String = "" { didSet { ud.set(jira2ClockifyProjectId, forKey: "jira2ClockifyProjectId") } }

    // MARK: - Sprint (experimental)

    /// Master toggle del panel inferior (anillos *o* heatmap, según
    /// `bottomView`).  Mantenemos la kcfg key vieja
    /// (`worklogShowSprintGauges`) para no perder la preferencia.
    @Published var showSprintGauges: Bool = true { didSet { ud.set(showSprintGauges, forKey: "worklogShowSprintGauges") } }
    /// Qué se muestra en el panel inferior: `"rings"` (gauges Sprint+
    /// Horas), `"subtasks"` (tabla de subtareas) o `"heatmap"` (mapa
    /// mensual de horas).
    @Published var bottomView: String = "rings" { didSet { ud.set(bottomView, forKey: "worklogBottomView") } }
    /// Habilita la vista de **anillos** (Sprint / Horas).  Por default
    /// está apagada porque hoy consume CPU constante (~20%); cuando
    /// está apagada el ícono del switch queda gris y no se puede
    /// seleccionar.  La orden de las vistas en el switch también
    /// cambia: con anillos = [rings, subtasks, heatmap]; sin anillos
    /// = [subtasks, heatmap, rings-gray].
    @Published var showRingsView: Bool = false { didSet { ud.set(showRingsView, forKey: "worklogShowRingsView") } }

    // MARK: - Google Calendar (read-only)

    /// Muestra los eventos de Google Calendar como bloques de fondo.
    @Published var googleCalEnabled: Bool = false { didSet { ud.set(googleCalEnabled, forKey: "googleCalEnabled") } }
    /// OAuth client "TV and Limited Input devices" (device-code flow).
    @Published var googleClientId: String = "" { didSet { ud.set(googleClientId, forKey: "googleClientId") } }
    /// El secret y el refresh token viven en el Keychain, no en UserDefaults.
    @Published var googleClientSecret: String = "" {
        didSet { Keychain.set(googleClientSecret, for: "google.client-secret") }
    }
    @Published var googleRefreshToken: String = "" {
        didSet { Keychain.set(googleRefreshToken, for: "google.refresh-token") }
    }
    /// Calendario legacy (config vieja de un solo calendario).  Se usa
    /// como fallback si `googleCalendarIds` está vacío.
    @Published var googleCalendarId: String = "primary" { didSet { ud.set(googleCalendarId, forKey: "googleCalendarId") } }
    /// Hasta 3 calendarios + su color (arrays paralelos).
    @Published var googleCalendarIds: [String] = [] { didSet { ud.set(googleCalendarIds, forKey: "googleCalendarIds") } }
    @Published var googleCalendarColors: [String] = [] { didSet { ud.set(googleCalendarColors, forKey: "googleCalendarColors") } }
    @Published var googleCalDebug: Bool = true { didSet { ud.set(googleCalDebug, forKey: "googleCalDebug") } }

    /// Color por defecto de los bloques de Google cuando el calendario no
    /// tiene uno asignado (el rojo translúcido de siempre).
    static let googleDefaultColor = "#e74c3c"

    /// Color base (hex) para un `calendarId`, resolviendo contra los
    /// arrays paralelos de configuración.
    func googleColor(for calendarId: String) -> String {
        if let idx = googleCalendarIds.firstIndex(of: calendarId),
           googleCalendarColors.indices.contains(idx) {
            let c = googleCalendarColors[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if !c.isEmpty { return c }
        }
        return Self.googleDefaultColor
    }
    /// Muestra la tercera vista del panel inferior: la tabla de subtareas.
    @Published var showSubtaskTable: Bool = true { didSet { ud.set(showSubtaskTable, forKey: "worklogShowSubtaskTable") } }
    /// JQL que alimenta la tabla de subtareas.
    @Published var subtaskJql: String =
        "issuetype in subTaskIssueTypes() AND assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"
        { didSet { ud.set(subtaskJql, forKey: "worklogSubtaskJql") } }
    /// Muestra la columna de issue padre en la tabla de subtareas.
    @Published var subtaskShowParent: Bool = true { didSet { ud.set(subtaskShowParent, forKey: "worklogSubtaskShowParent") } }
    /// Cómo descubrir el sprint activo.  Default
    /// `"subtask-customfield"` cubre el caso típico (usuario sólo dueño
    /// de subtareas).  `"agile-board"` necesita un boardId.
    /// `"assignee-jql"` es el fallback que pide al campo `sprint`
    /// top-level.
    @Published var sprintStrategy: String = "subtask-customfield" { didSet { ud.set(sprintStrategy, forKey: "worklogSprintStrategy") } }
    /// Nombre del custom field con el array de sprints.  En la mayoría
    /// de las instancias de Jira Cloud es `customfield_10020`.
    @Published var sprintField: String = "customfield_10020" { didSet { ud.set(sprintField, forKey: "worklogSprintField") } }
    /// ID del board para la estrategia `agile-board`.
    @Published var sprintBoardId: Int = 0 { didSet { ud.set(sprintBoardId, forKey: "worklogSprintBoardId") } }
    /// "api" usa `timetracking.remainingEstimateSeconds`.  "calculated"
    /// usa `max(0, originalEstimate − timeSpent)` para cuando la
    /// estimación no se mantiene al día en Jira.
    @Published var remainingMode: String = "api" { didSet { ud.set(remainingMode, forKey: "worklogRemainingMode") } }

    // MARK: - Clockify

    @Published var clockifyApiKey: String = "" {
        didSet { Keychain.set(clockifyApiKey, for: "clockify.api-key") }
    }
    @Published var clockifyWorkspaceId: String = "" { didSet { ud.set(clockifyWorkspaceId, forKey: "clockifyWorkspaceId") } }
    @Published var clockifyUserId: String = "" { didSet { ud.set(clockifyUserId, forKey: "clockifyUserId") } }
    @Published var clockifyDefaultProjectId: String = "" { didSet { ud.set(clockifyDefaultProjectId, forKey: "clockifyDefaultProjectId") } }
    @Published var clockifyBillableDefault: Bool = true { didSet { ud.set(clockifyBillableDefault, forKey: "clockifyBillableDefault") } }

    // MARK: - init

    private let ud = UserDefaults.standard

    init() {
        if let raw = ud.string(forKey: "worklogSource"),
           let s = WorklogSource(rawValue: raw) { source = s }
        if let raw = ud.string(forKey: "worklogViewMode"),
           let v = ViewHourMode(rawValue: raw) { viewMode = v }
        if ud.object(forKey: "worklogDailyTargetHours") != nil {
            dailyTargetHours = ud.double(forKey: "worklogDailyTargetHours")
        }
        showIssueSummary = ud.bool(forKey: "worklogShowIssueSummary")
        if ud.object(forKey: "worklogDebug") != nil { debug = ud.bool(forKey: "worklogDebug") }
        if ud.object(forKey: "worklogShowInDock") != nil { showInDock = ud.bool(forKey: "worklogShowInDock") }
        if let w = ud.object(forKey: "worklogWindowWidth")  as? Int { windowWidth  = w }
        if let h = ud.object(forKey: "worklogWindowHeight") as? Int { windowHeight = h }
        if let w = ud.object(forKey: "worklogModalWidth")   as? Int { modalWidth   = w }
        if let h = ud.object(forKey: "worklogModalHeight")  as? Int { modalHeight  = h }

        jiraSite  = ud.string(forKey: "jiraSite")  ?? ""
        jiraEmail = ud.string(forKey: "jiraEmail") ?? ""
        jiraToken = Keychain.get("jira.token") ?? ""
        if let s = ud.string(forKey: "worklogIssueJql") { jiraIssueJql = s }
        if let n = ud.object(forKey: "worklogIssueMax") as? Int { jiraIssueMax = n }

        if ud.object(forKey: "jira2Enabled") != nil { jira2Enabled = ud.bool(forKey: "jira2Enabled") }
        jira2Site  = ud.string(forKey: "jira2Site")  ?? ""
        jira2Email = ud.string(forKey: "jira2Email") ?? ""
        jira2Token = Keychain.get("jira2.token") ?? ""
        if let c = ud.string(forKey: "jira1BlockColor"), !c.isEmpty { jira1BlockColor = c }
        if let c = ud.string(forKey: "jira2BlockColor"), !c.isEmpty { jira2BlockColor = c }
        jira1ClockifyProjectId = ud.string(forKey: "jira1ClockifyProjectId") ?? ""
        jira2ClockifyProjectId = ud.string(forKey: "jira2ClockifyProjectId") ?? ""

        if ud.object(forKey: "worklogShowSprintGauges") != nil {
            showSprintGauges = ud.bool(forKey: "worklogShowSprintGauges")
        }
        if let s = ud.string(forKey: "worklogBottomView"),
           s == "rings" || s == "subtasks" || s == "heatmap" { bottomView = s }
        if ud.object(forKey: "worklogShowRingsView") != nil {
            showRingsView = ud.bool(forKey: "worklogShowRingsView")
        }
        if ud.object(forKey: "googleCalEnabled") != nil {
            googleCalEnabled = ud.bool(forKey: "googleCalEnabled")
        }
        googleClientId     = ud.string(forKey: "googleClientId") ?? ""
        googleClientSecret = Keychain.get("google.client-secret") ?? ""
        googleRefreshToken = Keychain.get("google.refresh-token") ?? ""
        if let s = ud.string(forKey: "googleCalendarId"), !s.isEmpty { googleCalendarId = s }
        googleCalendarIds    = ud.stringArray(forKey: "googleCalendarIds") ?? []
        googleCalendarColors = ud.stringArray(forKey: "googleCalendarColors") ?? []
        if ud.object(forKey: "googleCalDebug") != nil {
            googleCalDebug = ud.bool(forKey: "googleCalDebug")
        }
        if ud.object(forKey: "worklogShowSubtaskTable") != nil {
            showSubtaskTable = ud.bool(forKey: "worklogShowSubtaskTable")
        }
        if let s = ud.string(forKey: "worklogSubtaskJql"), !s.isEmpty { subtaskJql = s }
        if ud.object(forKey: "worklogSubtaskShowParent") != nil {
            subtaskShowParent = ud.bool(forKey: "worklogSubtaskShowParent")
        }
        if let s = ud.string(forKey: "worklogSprintStrategy"), !s.isEmpty { sprintStrategy = s }
        if let s = ud.string(forKey: "worklogSprintField"),    !s.isEmpty { sprintField = s }
        if let n = ud.object(forKey: "worklogSprintBoardId") as? Int { sprintBoardId = n }
        if let s = ud.string(forKey: "worklogRemainingMode"),  !s.isEmpty { remainingMode = s }

        clockifyApiKey           = Keychain.get("clockify.api-key") ?? ""
        clockifyWorkspaceId      = ud.string(forKey: "clockifyWorkspaceId") ?? ""
        clockifyUserId           = ud.string(forKey: "clockifyUserId") ?? ""
        clockifyDefaultProjectId = ud.string(forKey: "clockifyDefaultProjectId") ?? ""
        if ud.object(forKey: "clockifyBillableDefault") != nil {
            clockifyBillableDefault = ud.bool(forKey: "clockifyBillableDefault")
        }
    }

    // MARK: - Helpers

    /// Workspace ID válido = 24 chars hexadecimales.  Replicamos la
    /// validación del store QML para no enviar un nombre de workspace.
    static func isValidObjectId(_ s: String) -> Bool {
        guard s.count == 24 else { return false }
        return s.allSatisfy { $0.isHexDigit }
    }
}
