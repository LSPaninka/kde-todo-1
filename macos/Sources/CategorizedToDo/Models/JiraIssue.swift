import SwiftUI

/// Normalized Jira issue used by the UI and persisted to disk as cache.
///
/// Mirrors the shape produced by the KDE plasmoid's JiraStore.qml so the
/// JSON cache files are interchangeable.
struct JiraIssue: Codable, Identifiable, Hashable {
    var key: String              // "PROJ-123"
    var summary: String
    var statusName: String       // "To Do", "In Progress", "Done"
    var statusCat: String        // "new" | "indeterminate" | "done"
    var statusColor: String      // Jira's colorName (blue-gray, yellow, green, …)
    var priority: String         // "Highest" | "High" | "Medium" | "Low" | "Lowest" | ""
    var issuetype: String        // "Story" | "Bug" | "Task" | "Sub-task" | "Epic" | …
    var isSubtask: Bool
    var parentKey: String        // "" if not a subtask
    var parentSummary: String
    var updated: String          // ISO 8601
    var url: String              // full browse URL

    var id: String { key }

    /// Color for the issuetype badge.
    var issueTypeColor: Color {
        switch issuetype.lowercased() {
        case "story":          return Color(red: 0.40, green: 0.73, blue: 0.42) // green
        case "bug":            return Color(red: 0.91, green: 0.30, blue: 0.24) // red
        case "task":           return Color(red: 0.26, green: 0.59, blue: 0.86) // blue
        case "sub-task":       return Color(red: 0.40, green: 0.73, blue: 0.42).opacity(0.85)
        case "epic":           return Color(red: 0.61, green: 0.35, blue: 0.71) // purple
        default:               return Color.gray
        }
    }

    var issueTypeBadgeChar: String {
        switch issuetype.lowercased() {
        case "story":     return "S"
        case "bug":       return "B"
        case "task":      return "T"
        case "epic":      return "E"
        case "sub-task":  return "↳"
        default:          return "•"
        }
    }

    /// Pill color for the status chip (mirrors Jira's `statusCategory.colorName`).
    var statusPillColor: Color {
        switch statusCat.lowercased() {
        case "new":           return Color(red: 0.50, green: 0.55, blue: 0.62) // blue-gray
        case "indeterminate": return Color(red: 0.96, green: 0.65, blue: 0.13) // yellow/orange
        case "done":          return Color(red: 0.40, green: 0.73, blue: 0.42) // green
        default:              return Color.gray
        }
    }
}

// MARK: - Category matching

extension JiraIssue {
    /// Returns true if this issue matches the (field, value) pair, where
    /// `value` is a semicolon-separated list parsed as OR.
    func matches(field: JiraFilterField, value: String) -> Bool {
        guard field != .none else { return true }
        let needles = value
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        if needles.isEmpty { return true }

        let haystack: String
        switch field {
        case .statusCategory: haystack = statusCat.lowercased()
        case .status:         haystack = statusName.lowercased()
        case .issuetype:      haystack = issuetype.lowercased()
        case .priority:       haystack = priority.lowercased()
        case .none:           return true
        }
        return needles.contains(haystack)
    }
}
