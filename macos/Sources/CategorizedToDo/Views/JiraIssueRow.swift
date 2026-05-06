import SwiftUI
import AppKit

/// Single row in the Jira list. Click → open issue URL in default browser.
struct JiraIssueRow: View {
    let issue: JiraIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                typeBadge
                Text(issue.key)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundColor(.primary)
                Text(issue.summary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !issue.priority.isEmpty {
                    Text(issue.priority)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.15))
                        )
                }
                if !issue.statusName.isEmpty {
                    Text(issue.statusName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(issue.statusPillColor)
                        )
                }
            }

            if issue.isSubtask && !issue.parentKey.isEmpty {
                Text("↳ Parent: \(issue.parentKey) — \(issue.parentSummary)")
                    .font(.caption)
                    .italic()
                    .foregroundColor(.secondary)
                    .padding(.leading, 30)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: issue.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var typeBadge: some View {
        Text(issue.issueTypeBadgeChar)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(issue.issueTypeColor)
            )
    }
}
