import SwiftUI

/// One row in a GitHub Project v2, normalized so the SwiftUI views don't have
/// to deal with the polymorphic Issue/PullRequest/DraftIssue shape returned
/// by GraphQL.
///
/// Mirrors the structure produced by `GhStore.qml` in the KDE plasmoid so the
/// JSON cache is interchangeable.
struct GhItem: Codable, Identifiable, Hashable {
    var id: String              // GraphQL node id (stable)
    var type: String            // "Issue" | "PullRequest" | "DraftIssue"
    var title: String
    var url: String             // browse URL, empty for draft issues
    var number: Int             // 0 for draft issues
    var state: String           // "OPEN" | "CLOSED" | "MERGED" | "DRAFT"
    var isDraft: Bool           // PR-only flag
    var repo: String            // "owner/name", empty for draft issues
    var updated: String         // ISO 8601
    var statusName: String      // value of the configured status field
    var labels: [GhLabel]
    var customFields: [String: String]  // dynamic field-name → text value

    struct GhLabel: Codable, Hashable {
        var name: String
        var colorHex: String
    }

    var typeBadgeChar: String {
        switch type.lowercased() {
        case "issue":         return "I"
        case "pullrequest":   return "P"
        case "draftissue":    return "D"
        default:              return "•"
        }
    }

    var typeBadgeColor: Color {
        switch type.lowercased() {
        case "issue":
            return state.uppercased() == "CLOSED"
                ? Color(red: 0.61, green: 0.35, blue: 0.71)   // purple closed
                : Color(red: 0.40, green: 0.73, blue: 0.42)   // green open
        case "pullrequest":
            switch state.uppercased() {
            case "MERGED": return Color(red: 0.61, green: 0.35, blue: 0.71)
            case "CLOSED": return Color(red: 0.91, green: 0.30, blue: 0.24)
            default:       return Color(red: 0.40, green: 0.73, blue: 0.42)
            }
        case "draftissue":
            return Color.gray
        default:
            return Color.gray
        }
    }

    /// Returns true if this item matches the (field, value) filter pair.
    func matches(field: String, value: String) -> Bool {
        guard !field.isEmpty else { return true }
        let needles = value
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        if needles.isEmpty { return true }

        let haystacks: [String]
        switch field {
        case "status": haystacks = [statusName.lowercased()]
        case "type":   haystacks = [type.lowercased()]
        case "state":  haystacks = [state.lowercased()]
        case "repo":   haystacks = [repo.lowercased()]
        case "label":  haystacks = labels.map { $0.name.lowercased() }
        default:       return true
        }
        return needles.contains { needle in haystacks.contains(needle) }
    }
}
