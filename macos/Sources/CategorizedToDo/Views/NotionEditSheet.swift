import SwiftUI

/// Edit dialog for a Notion page: title and (lazily-loaded) Markdown content.
/// Uses `ntn pages get/update` to roundtrip content.
struct NotionEditSheet: View {
    @ObservedObject var notion: NotionStore
    let page: NotionPage
    var onClose: () -> Void

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var loadingContent: Bool = true
    @State private var error: String? = nil
    @State private var saving: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Editar página de Notion").font(.title2).bold()

            Form {
                TextField("Título", text: $title)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Contenido (Markdown)")
                        if loadingContent {
                            ProgressView().controlSize(.small)
                        }
                    }
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 240, maxHeight: 380)
                        .border(Color.secondary.opacity(0.3))
                }
            }

            if let e = error {
                Label(e, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancelar", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(saving ? "Guardando…" : "Guardar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 600)
        .onAppear {
            title = page.title
            loadContent()
        }
    }

    private func loadContent() {
        loadingContent = true
        notion.fetchContent(pageId: page.id) { result in
            loadingContent = false
            switch result {
            case .success(let s): content = s
            case .failure(let m): error = m
            }
        }
    }

    private func save() {
        saving = true
        error = nil
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        notion.updateTitle(pageId: page.id, newTitle: trimmed) { result in
            switch result {
            case .failure(let m):
                saving = false
                error = "Error guardando título: \(m)"
                return
            case .success:
                notion.updateContent(pageId: page.id, markdown: content) { result2 in
                    saving = false
                    switch result2 {
                    case .success:
                        // Refresh the listing so the new title appears.
                        notion.fetch()
                        onClose()
                    case .failure(let m):
                        error = "Error guardando contenido: \(m)"
                    }
                }
            }
        }
    }
}
