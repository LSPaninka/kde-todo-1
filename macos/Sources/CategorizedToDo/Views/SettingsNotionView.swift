import SwiftUI

/// Settings tab — Notion CLI configuration. No tokens here: auth is owned
/// entirely by the `ntn` CLI.
struct NotionSettingsView: View {
    @ObservedObject var notion: NotionStore
    @ObservedObject var settings: AppSettings

    @State private var cliStatus: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle, running, ok(String), error(String)
    }

    var body: some View {
        Form {
            Section("CLI") {
                TextField("Ruta absoluta a `ntn` (opcional)",
                          text: $settings.notionCliPath)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled(true)
                Text("Si está vacío, se resuelve desde el PATH (incluye /opt/homebrew/bin, /usr/local/bin y ~/.local/bin). Instalá `ntn` con `npm install -g ntn` y autenticá con `ntn login`.")
                    .font(.caption).foregroundColor(.secondary)

                HStack {
                    Button { runCheck() } label: {
                        if case .running = cliStatus {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Verificar CLI", systemImage: "terminal")
                        }
                    }
                    .disabled(cliStatus == .running)

                    switch cliStatus {
                    case .idle: EmptyView()
                    case .running: Text("Ejecutando…").foregroundColor(.secondary)
                    case .ok(let v):
                        Label(v, systemImage: "checkmark.seal").foregroundColor(.green)
                    case .error(let m):
                        Label(m, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .lineLimit(3)
                    }
                }
            }

            Section("Búsqueda") {
                TextField("Query (vacío = todas)", text: $settings.notionQuery)
                Picker("Tipo", selection: $settings.notionFilter) {
                    Text("Páginas").tag("page")
                    Text("Bases de datos").tag("database")
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Máximo de resultados")
                    Spacer()
                    Stepper(value: $settings.notionMaxResults, in: 10...200, step: 10) {
                        Text("\(settings.notionMaxResults)").monospacedDigit()
                    }
                }
                HStack {
                    Text("Auto-refresh (min)")
                    Spacer()
                    Stepper(value: $settings.notionRefreshMinutes, in: 0...1440) {
                        Text("\(settings.notionRefreshMinutes)").monospacedDigit()
                    }
                }
            }

            Section("Diagnóstico") {
                Toggle("Logs detallados (NSLog)", isOn: $settings.notionDebug)
                Text("Visibles con: log stream --predicate 'process == \"CategorizedToDo\"' --info")
                    .font(.caption2).foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func runCheck() {
        cliStatus = .running
        notion.testCli { result in
            switch result {
            case .success(let v): cliStatus = .ok("ntn \(v)")
            case .failure(let m): cliStatus = .error(m)
            }
        }
    }
}
