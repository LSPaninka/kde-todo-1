import Foundation

/// Un evento de Google Calendar, normalizado al mismo shape
/// `started / durationSec` que usan `JiraWorklog` y `ClockifyEntry`,
/// así el grid los posiciona con la misma matemática.
struct GoogleCalendarEvent: Identifiable, Equatable {
    var id: String            // "<calendarId>:<eventId>"
    var summary: String
    var startedMs: Double
    var durationSec: Int
    /// Calendario del que vino — lo usamos para resolver el color.
    var calendarId: String
}

/// Un calendario de la cuenta (para el picker de Preferencias).
struct GoogleCalendarInfo: Identifiable, Hashable {
    var id: String            // calendarId
    var summary: String
    var primary: Bool
}
