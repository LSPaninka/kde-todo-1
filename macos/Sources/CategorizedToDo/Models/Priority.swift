import SwiftUI

enum Priority: String, Codable, CaseIterable, Identifiable, Hashable {
    case xs = "XS"
    case s  = "S"
    case m  = "M"
    case l  = "L"
    case xl = "XL"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .xs: return Color(red: 0.36, green: 0.78, blue: 0.39)   // green
        case .s:  return Color(red: 0.40, green: 0.80, blue: 0.93)   // light blue
        case .m:  return Color(red: 0.95, green: 0.77, blue: 0.06)   // amber
        case .l:  return Color(red: 0.96, green: 0.55, blue: 0.13)   // orange
        case .xl: return Color(red: 0.91, green: 0.30, blue: 0.24)   // red
        }
    }

    var weight: Int {
        switch self {
        case .xs: return 1
        case .s:  return 2
        case .m:  return 3
        case .l:  return 4
        case .xl: return 5
        }
    }
}
