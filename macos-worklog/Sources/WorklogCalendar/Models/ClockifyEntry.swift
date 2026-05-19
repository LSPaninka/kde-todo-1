import Foundation

/// Time entry de Clockify, normalizada al mismo shape de duración que
/// usamos para Jira para que el grid pueda renderlas con un solo helper.
struct ClockifyEntry: Identifiable, Equatable {
    var id: String
    var startedMs: Double
    var durationSec: Int
    var description: String
    var projectId: String
    var projectName: String
    var projectColor: String   // hex "#RRGGBB" (string vacío = sin color)
    var tagIds: [String]
    var tagNames: [String]
    var billable: Bool
}

/// Proyecto de Clockify (para el picker del modal y el tinte por color).
struct ClockifyProject: Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
    var billable: Bool
}

/// Tag de Clockify.
struct ClockifyTag: Identifiable, Hashable {
    var id: String
    var name: String
}
