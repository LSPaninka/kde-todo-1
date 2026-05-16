import SwiftUI
import AppKit

struct NotionPageRow: View {
    let page: NotionPage
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .lineLimit(2)
                    .strikethrough(page.archived)
                    .foregroundColor(page.archived ? .secondary : .primary)
                if !page.parentType.isEmpty || !page.lastEditedTime.isEmpty {
                    Text(footerText())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Editar título o contenido")

            Button {
                if let url = URL(string: page.url) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help("Abrir en Notion")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconView: some View {
        if !page.icon.isEmpty, !page.icon.hasPrefix("http") {
            Text(page.icon)
                .font(.system(size: 18))
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: page.object == "database" ? "rectangle.stack" : "doc.text")
                .frame(width: 22, height: 22)
                .foregroundColor(.secondary)
        }
    }

    private func footerText() -> String {
        var parts: [String] = []
        if !page.object.isEmpty { parts.append(page.object) }
        if !page.parentType.isEmpty { parts.append("padre: \(page.parentType)") }
        if !page.lastEditedTime.isEmpty { parts.append("editado: \(page.lastEditedTime.prefix(10))") }
        return parts.joined(separator: " · ")
    }
}
