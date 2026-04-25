import SwiftUI

/// Small pill showing the priority (XS/S/M/L/XL).
struct PriorityBadge: View {
    let priority: Priority
    var compact: Bool = false

    var body: some View {
        Text(priority.rawValue)
            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 1 : 2)
            .background(
                Capsule().fill(priority.color)
            )
    }
}

/// Compact dropdown that lets the user pick a priority. Used in the inline
/// "add task" rows.
struct PriorityPicker: View {
    @Binding var priority: Priority
    var body: some View {
        Picker("", selection: $priority) {
            ForEach(Priority.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 64)
    }
}
