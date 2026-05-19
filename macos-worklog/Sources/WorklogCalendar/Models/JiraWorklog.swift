import Foundation

/// Un worklog Jira en el modelo "plano" que renderiza el calendario.
struct JiraWorklog: Identifiable, Equatable {
    var id: String          // worklog id como string
    var issueId: String
    var issueKey: String
    var issueSummary: String
    var startedMs: Double   // ms desde epoch (usamos Double para mantener compatibilidad con Date.timeIntervalSince1970 * 1000)
    var durationSec: Int
    var comment: String
}

/// Issue disponible para el picker del modal "nuevo worklog".
struct JiraAssignableIssue: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var summary: String
    var issuetype: String
    var status: String
}
