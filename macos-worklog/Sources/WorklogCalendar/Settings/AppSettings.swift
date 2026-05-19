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
    @Published var windowHeight: Int = 700 { didSet { ud.set(windowHeight, forKey: "worklogWindowHeight") } }

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

        jiraSite  = ud.string(forKey: "jiraSite")  ?? ""
        jiraEmail = ud.string(forKey: "jiraEmail") ?? ""
        jiraToken = Keychain.get("jira.token") ?? ""
        if let s = ud.string(forKey: "worklogIssueJql") { jiraIssueJql = s }
        if let n = ud.object(forKey: "worklogIssueMax") as? Int { jiraIssueMax = n }

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
