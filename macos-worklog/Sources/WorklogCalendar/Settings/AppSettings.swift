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

    // MARK: - Sprint (experimental)

    /// Habilita los anillos Sprint + Horas al pie del calendario.
    @Published var showSprintGauges: Bool = true { didSet { ud.set(showSprintGauges, forKey: "worklogShowSprintGauges") } }
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
        if let w = ud.object(forKey: "worklogWindowWidth")  as? Int { windowWidth  = w }
        if let h = ud.object(forKey: "worklogWindowHeight") as? Int { windowHeight = h }
        if let w = ud.object(forKey: "worklogModalWidth")   as? Int { modalWidth   = w }
        if let h = ud.object(forKey: "worklogModalHeight")  as? Int { modalHeight  = h }

        jiraSite  = ud.string(forKey: "jiraSite")  ?? ""
        jiraEmail = ud.string(forKey: "jiraEmail") ?? ""
        jiraToken = Keychain.get("jira.token") ?? ""
        if let s = ud.string(forKey: "worklogIssueJql") { jiraIssueJql = s }
        if let n = ud.object(forKey: "worklogIssueMax") as? Int { jiraIssueMax = n }

        if ud.object(forKey: "worklogShowSprintGauges") != nil {
            showSprintGauges = ud.bool(forKey: "worklogShowSprintGauges")
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
