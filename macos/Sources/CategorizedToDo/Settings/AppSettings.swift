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
            K.popupShowZero: true
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

        // Pad arrays so we always have 4 entries even after manual edits.
        while categoryNames.count          < 4 { categoryNames.append("Categoría \(categoryNames.count + 1)") }
        while categoryColorsHex.count      < 4 { categoryColorsHex.append("#888888") }
        while popupCounterTextColors.count < 4 { popupCounterTextColors.append(.white) }
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
