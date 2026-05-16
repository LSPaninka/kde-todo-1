import SwiftUI

/// Normalized Notion page (or database row) as returned by `ntn api v1/search`.
///
/// Mirrors the QML version's shape so caches and exports stay compatible.
struct NotionPage: Codable, Identifiable, Hashable {
    var id: String              // UUID
    var title: String           // best-effort from properties[*].title
    var url: String             // canonical Notion URL
    var createdTime: String     // ISO 8601
    var lastEditedTime: String  // ISO 8601
    var archived: Bool
    var parentType: String      // "workspace" | "page_id" | "database_id" | ""
    var object: String          // "page" | "database"
    var icon: String            // emoji or empty
}
