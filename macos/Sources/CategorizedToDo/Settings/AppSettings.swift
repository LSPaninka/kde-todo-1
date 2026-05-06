import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// Per-category counter text color used in the menu bar / popup.
enum CounterTextColor: String, Codable, CaseIterable, Identifiable {
    case white, black
    var id: String { rawValue }

    var color: Color {
        self == .white ? .white : .black
    }
}

/// Layout of the menu-bar / panel counter.
///
///  - `.right`  : swatch + number to the right
///  - `.inside` : number drawn inside the swatch (single bigger square)
enum CounterLayout: String, Codable, CaseIterable, Identifiable {
    case right, inside
    var id: String { rawValue }
}

/// Whether the popup shows the local todo list ("todo") or pulls from a
/// Jira instance ("jira"). Mirrors the KDE plasmoid's `mode` setting.
enum AppMode: String, Codable, CaseIterable, Identifiable {
    case todo, jira
    var id: String { rawValue }
}

/// Field used to filter Jira issues into a tab.
///
/// Values must match those used by the KDE plasmoid for cross-compatibility.
enum JiraFilterField: String, Codable, CaseIterable, Identifiable {
    case none = ""
    case statusCategory
    case status
    case issuetype
    case priority

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:           return "(sin filtro)"
        case .statusCategory: return "statusCategory"
        case .status:         return "status"
        case .issuetype:      return "issuetype"
        case .priority:       return "priority"
        }
    }

    var placeholderHint: String {
        switch self {
        case .none:           return "muestra todos los issues"
        case .statusCategory: return "new ; indeterminate ; done"
        case .status:         return "To Do ; In Progress ; Code Review"
        case .issuetype:      return "Story ; Bug ; Task ; Sub-task ; Epic"
        case .priority:       return "Highest ; High ; Medium ; Low"
        }
    }
}

/// All user-configurable settings for the app. Persisted to UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - General

    @Published var categoryCount: Int {
        didSet {
            categoryCount = max(1, min(4, categoryCount))
            ud.set(categoryCount, forKey: K.categoryCount)
        }
    }

    @Published var categoryNames: [String] {
        didSet { ud.set(categoryNames, forKey: K.categoryNames) }
    }

    /// Hex strings, e.g. "#2ecc71".
    @Published var categoryColorsHex: [String] {
        didSet { ud.set(categoryColorsHex, forKey: K.categoryColors) }
    }

    @Published var showPriorityIcons: Bool {
        didSet { ud.set(showPriorityIcons, forKey: K.showPriorityIcons) }
    }

    @Published var confirmDelete: Bool {
        didSet { ud.set(confirmDelete, forKey: K.confirmDelete) }
    }

    @Published var popupWidth: Int {
        didSet { ud.set(popupWidth, forKey: K.popupWidth) }
    }

    @Published var popupHeight: Int {
        didSet { ud.set(popupHeight, forKey: K.popupHeight) }
    }

    // MARK: - Menu bar appearance

    /// Color used for the digits inside the menu-bar square.
    /// "white" or "black".
    @Published var menuBarTextColor: CounterTextColor {
        didSet { ud.set(menuBarTextColor.rawValue, forKey: K.menuBarTextColor) }
    }

    /// Background color of the menu-bar square. The user requested a white
    /// square, but we keep this configurable.
    @Published var menuBarBackgroundHex: String {
        didSet { ud.set(menuBarBackgroundHex, forKey: K.menuBarBackground) }
    }

    /// If true the menu-bar square shows ONE number (total pending);
    /// if false it shows one mini-swatch per category like the KDE panel.
    @Published var menuBarUseSingleSquare: Bool {
        didSet { ud.set(menuBarUseSingleSquare, forKey: K.menuBarSingleSquare) }
    }

    // MARK: - Popup appearance (per-category counters inside popup tabs)

    @Published var popupCounterLayout: CounterLayout {
        didSet { ud.set(popupCounterLayout.rawValue, forKey: K.popupCounterLayout) }
    }

    @Published var popupCounterTextColors: [CounterTextColor] {
        didSet {
            ud.set(popupCounterTextColors.map { $0.rawValue }, forKey: K.popupCounterTextColors)
        }
    }

    @Published var popupShowZero: Bool {
        didSet { ud.set(popupShowZero, forKey: K.popupShowZero) }
    }

    // MARK: - Mode

    @Published var mode: AppMode {
        didSet { ud.set(mode.rawValue, forKey: K.mode) }
    }

    // MARK: - Jira (general)

    /// Base URL of the Jira Cloud instance, e.g. https://acme.atlassian.net
    @Published var jiraSite: String {
        didSet { ud.set(jiraSite, forKey: K.jiraSite) }
    }

    /// Account email used for Basic auth.
    @Published var jiraEmail: String {
        didSet { ud.set(jiraEmail, forKey: K.jiraEmail) }
    }

    /// API token from id.atlassian.com/manage-profile/security/api-tokens.
    /// Stored in the macOS Keychain (NOT in UserDefaults).
    @Published var jiraToken: String {
        didSet { Keychain.set(jiraToken, for: "jira.token") }
    }

    @Published var jiraJql: String {
        didSet { ud.set(jiraJql, forKey: K.jiraJql) }
    }

    /// Auto-refresh interval in minutes. 0 disables auto-refresh.
    @Published var jiraRefreshMinutes: Int {
        didSet {
            jiraRefreshMinutes = max(0, min(1440, jiraRefreshMinutes))
            ud.set(jiraRefreshMinutes, forKey: K.jiraRefreshMinutes)
        }
    }

    @Published var jiraMaxResults: Int {
        didSet {
            jiraMaxResults = max(10, min(200, jiraMaxResults))
            ud.set(jiraMaxResults, forKey: K.jiraMaxResults)
        }
    }

    @Published var jiraDebug: Bool {
        didSet { ud.set(jiraDebug, forKey: K.jiraDebug) }
    }

    // MARK: - Jira (categories)

    @Published var jiraCategoryCount: Int {
        didSet {
            jiraCategoryCount = max(1, min(4, jiraCategoryCount))
            ud.set(jiraCategoryCount, forKey: K.jiraCategoryCount)
        }
    }

    @Published var jiraCategoryNames: [String] {
        didSet { ud.set(jiraCategoryNames, forKey: K.jiraCategoryNames) }
    }

    @Published var jiraCategoryColorsHex: [String] {
        didSet { ud.set(jiraCategoryColorsHex, forKey: K.jiraCategoryColors) }
    }

    @Published var jiraCategoryTextColors: [CounterTextColor] {
        didSet {
            ud.set(jiraCategoryTextColors.map { $0.rawValue },
                   forKey: K.jiraCategoryTextColors)
        }
    }

    /// Filter dimension per category (statusCategory / status / issuetype /
    /// priority / "" for none).
    @Published var jiraCategoryFilterFields: [JiraFilterField] {
        didSet {
            ud.set(jiraCategoryFilterFields.map { $0.rawValue },
                   forKey: K.jiraCategoryFilterFields)
        }
    }

    /// Filter values per category, semicolon-separated for OR matching.
    @Published var jiraCategoryFilterValues: [String] {
        didSet { ud.set(jiraCategoryFilterValues, forKey: K.jiraCategoryFilterValues) }
    }

    // MARK: - Internals

    private let ud = UserDefaults.standard

    private struct K {
        static let categoryCount        = "categoryCount"
        static let categoryNames        = "categoryNames"
        static let categoryColors       = "categoryColors"
        static let showPriorityIcons    = "showPriorityIcons"
        static let confirmDelete        = "confirmDelete"
        static let popupWidth           = "popupWidth"
        static let popupHeight          = "popupHeight"
        static let menuBarTextColor     = "menuBarTextColor"
        static let menuBarBackground    = "menuBarBackground"
        static let menuBarSingleSquare  = "menuBarSingleSquare"
        static let popupCounterLayout   = "popupCounterLayout"
        static let popupCounterTextColors = "popupCounterTextColors"
        static let popupShowZero        = "popupShowZero"

        // Mode
        static let mode                 = "mode"

        // Jira
        static let jiraSite                 = "jiraSite"
        static let jiraEmail                = "jiraEmail"
        static let jiraJql                  = "jiraJql"
        static let jiraRefreshMinutes       = "jiraRefreshMinutes"
        static let jiraMaxResults           = "jiraMaxResults"
        static let jiraDebug                = "jiraDebug"
        static let jiraCategoryCount        = "jiraCategoryCount"
        static let jiraCategoryNames        = "jiraCategoryNames"
        static let jiraCategoryColors       = "jiraCategoryColors"
        static let jiraCategoryTextColors   = "jiraCategoryTextColors"
        static let jiraCategoryFilterFields = "jiraCategoryFilterFields"
        static let jiraCategoryFilterValues = "jiraCategoryFilterValues"
    }

    private init() {
        let defaultsRegistration: [String: Any] = [
            K.categoryCount: 4,
            K.categoryNames: ["Personal", "Trabajo", "Estudio", "Otros"],
            K.categoryColors: ["#2ecc71", "#f1c40f", "#3498db", "#e74c3c"],
            K.showPriorityIcons: true,
            K.confirmDelete: true,
            K.popupWidth: 420,
            K.popupHeight: 540,
            K.menuBarTextColor: CounterTextColor.black.rawValue,
            K.menuBarBackground: "#ffffff",
            K.menuBarSingleSquare: true,
            K.popupCounterLayout: CounterLayout.right.rawValue,
            K.popupCounterTextColors: ["white", "black", "white", "white"],
            K.popupShowZero: true,

            K.mode: AppMode.todo.rawValue,

            K.jiraSite: "",
            K.jiraEmail: "",
            K.jiraJql: "assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated DESC",
            K.jiraRefreshMinutes: 5,
            K.jiraMaxResults: 50,
            K.jiraDebug: false,
            K.jiraCategoryCount: 3,
            K.jiraCategoryNames:        ["Por hacer", "En curso", "Hechas", "Otras"],
            K.jiraCategoryColors:       ["#42526e", "#f5a623", "#2ecc71", "#9b59b6"],
            K.jiraCategoryTextColors:   ["white", "white", "white", "white"],
            K.jiraCategoryFilterFields: ["statusCategory", "statusCategory", "statusCategory", ""],
            K.jiraCategoryFilterValues: ["new", "indeterminate", "done", ""]
        ]
        ud.register(defaults: defaultsRegistration)

        self.categoryCount         = ud.integer(forKey: K.categoryCount)
        self.categoryNames         = (ud.array(forKey: K.categoryNames) as? [String]) ?? defaultsRegistration[K.categoryNames] as! [String]
        self.categoryColorsHex     = (ud.array(forKey: K.categoryColors) as? [String]) ?? defaultsRegistration[K.categoryColors] as! [String]
        self.showPriorityIcons     = ud.bool(forKey: K.showPriorityIcons)
        self.confirmDelete         = ud.bool(forKey: K.confirmDelete)
        self.popupWidth            = ud.integer(forKey: K.popupWidth)
        self.popupHeight           = ud.integer(forKey: K.popupHeight)
        self.menuBarTextColor      = CounterTextColor(rawValue: ud.string(forKey: K.menuBarTextColor) ?? "black") ?? .black
        self.menuBarBackgroundHex  = ud.string(forKey: K.menuBarBackground) ?? "#ffffff"
        self.menuBarUseSingleSquare = ud.bool(forKey: K.menuBarSingleSquare)
        self.popupCounterLayout    = CounterLayout(rawValue: ud.string(forKey: K.popupCounterLayout) ?? "right") ?? .right
        self.popupCounterTextColors = ((ud.array(forKey: K.popupCounterTextColors) as? [String]) ?? ["white","black","white","white"])
            .map { CounterTextColor(rawValue: $0) ?? .white }
        self.popupShowZero         = ud.bool(forKey: K.popupShowZero)

        self.mode                  = AppMode(rawValue: ud.string(forKey: K.mode) ?? "todo") ?? .todo

        self.jiraSite              = ud.string(forKey: K.jiraSite) ?? ""
        self.jiraEmail             = ud.string(forKey: K.jiraEmail) ?? ""
        self.jiraToken             = Keychain.get("jira.token") ?? ""
        self.jiraJql               = ud.string(forKey: K.jiraJql) ?? ""
        self.jiraRefreshMinutes    = ud.integer(forKey: K.jiraRefreshMinutes)
        self.jiraMaxResults        = ud.integer(forKey: K.jiraMaxResults)
        self.jiraDebug             = ud.bool(forKey: K.jiraDebug)

        self.jiraCategoryCount     = ud.integer(forKey: K.jiraCategoryCount)
        self.jiraCategoryNames     = (ud.array(forKey: K.jiraCategoryNames) as? [String])
            ?? defaultsRegistration[K.jiraCategoryNames] as! [String]
        self.jiraCategoryColorsHex = (ud.array(forKey: K.jiraCategoryColors) as? [String])
            ?? defaultsRegistration[K.jiraCategoryColors] as! [String]
        self.jiraCategoryTextColors = ((ud.array(forKey: K.jiraCategoryTextColors) as? [String]) ?? ["white","white","white","white"])
            .map { CounterTextColor(rawValue: $0) ?? .white }
        self.jiraCategoryFilterFields = ((ud.array(forKey: K.jiraCategoryFilterFields) as? [String])
            ?? ["statusCategory","statusCategory","statusCategory",""])
            .map { JiraFilterField(rawValue: $0) ?? .none }
        self.jiraCategoryFilterValues = (ud.array(forKey: K.jiraCategoryFilterValues) as? [String])
            ?? ["new","indeterminate","done",""]

        // Pad arrays so we always have 4 entries even after manual edits.
        while categoryNames.count             < 4 { categoryNames.append("Categoría \(categoryNames.count + 1)") }
        while categoryColorsHex.count         < 4 { categoryColorsHex.append("#888888") }
        while popupCounterTextColors.count    < 4 { popupCounterTextColors.append(.white) }
        while jiraCategoryNames.count         < 4 { jiraCategoryNames.append("Slot \(jiraCategoryNames.count + 1)") }
        while jiraCategoryColorsHex.count     < 4 { jiraCategoryColorsHex.append("#888888") }
        while jiraCategoryTextColors.count    < 4 { jiraCategoryTextColors.append(.white) }
        while jiraCategoryFilterFields.count  < 4 { jiraCategoryFilterFields.append(.none) }
        while jiraCategoryFilterValues.count  < 4 { jiraCategoryFilterValues.append("") }
    }

    // MARK: - Helpers

    func categoryColor(_ index: Int) -> Color {
        guard index >= 0, index < categoryColorsHex.count else { return .gray }
        return Color(hex: categoryColorsHex[index]) ?? .gray
    }

    func categoryName(_ index: Int) -> String {
        guard index >= 0, index < categoryNames.count else { return "?" }
        return categoryNames[index]
    }

    var menuBarBackground: Color {
        Color(hex: menuBarBackgroundHex) ?? .white
    }

    // MARK: - Helpers (Jira)

    func jiraCategoryColor(_ index: Int) -> Color {
        guard index >= 0, index < jiraCategoryColorsHex.count else { return .gray }
        return Color(hex: jiraCategoryColorsHex[index]) ?? .gray
    }

    func jiraCategoryName(_ index: Int) -> String {
        guard index >= 0, index < jiraCategoryNames.count else { return "?" }
        return jiraCategoryNames[index]
    }

    func jiraCategoryTextColor(_ index: Int) -> Color {
        guard index >= 0, index < jiraCategoryTextColors.count else { return .white }
        return jiraCategoryTextColors[index].color
    }
}

// MARK: - Color hex helpers

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8)  & 0xFF) / 255.0
            b = Double(v         & 0xFF) / 255.0
            a = 1.0
        } else {
            r = Double((v >> 24) & 0xFF) / 255.0
            g = Double((v >> 16) & 0xFF) / 255.0
            b = Double((v >> 8)  & 0xFF) / 255.0
            a = Double(v         & 0xFF) / 255.0
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }

    /// Best-effort conversion back to "#rrggbb".
    func toHex() -> String {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = Int((ns.redComponent   * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent  * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
        #else
        return "#888888"
        #endif
    }
}
