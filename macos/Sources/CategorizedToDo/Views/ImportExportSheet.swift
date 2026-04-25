import SwiftUI
import AppKit

/// Read-only export viewer with copy-to-clipboard.
struct ExportSheet: View {
    let jsonText: String
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exportar (JSON)").font(.title2).bold()
            Text("Copiá el contenido para guardarlo o compartirlo.")
                .foregroundColor(.secondary)
                .font(.callout)

            ScrollView {
                Text(jsonText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 320)
            .border(Color.secondary.opacity(0.3))

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(jsonText, forType: .string)
                } label: {
                    Label("Copiar al portapapeles", systemImage: "doc.on.doc")
                }
                Spacer()
                Button("Cerrar", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}

/// Paste JSON, hit "Importar" → tasks are appended to the chosen category.
struct ImportSheet: View {
    @ObservedObject var store: TaskStore
    let category: Int
    var onClose: () -> Void

    @State private var jsonText: String = ""
    @State private var error: String? = nil
    @State private var importedCount: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Importar (JSON)").font(.title2).bold()
            Text("Pegá un JSON exportado o un array plano de tareas.")
                .foregroundColor(.secondary)
                .font(.callout)

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 320)
                .border(Color.secondary.opacity(0.3))

            if let e = error {
                Label(e, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .font(.callout)
            }
            if let n = importedCount {
                Label("Importadas \(n) tarea(s).", systemImage: "checkmark.seal")
                    .foregroundColor(.green)
                    .font(.callout)
            }

            HStack {
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        jsonText = s
                    }
                } label: {
                    Label("Pegar desde portapapeles", systemImage: "doc.on.clipboard")
                }
                Spacer()
                Button("Cerrar", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Importar") {
                    runImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(jsonText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func runImport() {
        do {
            let n = try store.importCategoryJson(category, jsonText: jsonText)
            importedCount = n
            error = nil
        } catch {
            self.error = error.localizedDescription
            self.importedCount = nil
        }
    }
}
