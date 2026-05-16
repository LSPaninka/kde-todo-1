import SwiftUI

/// Settings tab — GitHub Projects connection (token, owner, project number,
/// status field, max results, auto-refresh).
struct GhSettingsView: View {
    @ObservedObject var gh: GhStore
    @ObservedObject var settings: AppSettings

    @State private var showToken: Bool = false
    @State private var testStatus: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle, running, ok(String), error(String)
    }

    var body: some View {
        Form {
            Section("Cuenta") {
                HStack {
                    if showToken {
                        TextField("Personal Access Token", text: $settings.ghToken)
                            .autocorrectionDisabled(true)
                    } else {
                        SecureField("Personal Access Token", text: $settings.ghToken)
                    }
                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                Text("Token clásico con scopes `project`, `read:org`, `repo`. Se guarda en el Keychain (servicio com.categorizedtodo.app, cuenta gh.token).")
                    .font(.caption).foregroundColor(.secondary)

                Picker("Tipo de owner", selection: $settings.ghOwnerType) {
                    Text("Usuario").tag("user")
                    Text("Organización").tag("organization")
                }
                .pickerStyle(.segmented)

                TextField("Login (owner)", text: $settings.ghOwner)
                    .autocorrectionDisabled(true)
            }

            Section("Project v2") {
                HStack {
                    Text("Número de proyecto")
                    Spacer()
                    Stepper(value: $settings.ghProjectNumber, in: 1...9999) {
                        Text("\(settings.ghProjectNumber)").monospacedDigit()
                    }
                }
                Text("Lo encontrás en la URL: github.com/<owner>/projects/<N>")
                    .font(.caption2).foregroundColor(.secondary)

                TextField("Nombre del campo de Status",
                          text: $settings.ghStatusField)
                Text("Matching case-insensitive contra los Single-select fields del proyecto. 'Status' es el default.")
                    .font(.caption2).foregroundColor(.secondary)

                Toggle("Incluir items cerrados / mergeados",
                       isOn: $settings.ghIncludeClosed)
            }

            Section("Carga") {
                HStack {
                    Text("Auto-refresh (min)")
                    Spacer()
                    Stepper(value: $settings.ghRefreshMinutes, in: 0...1440) {
                        Text("\(settings.ghRefreshMinutes)").monospacedDigit()
                    }
                }
                HStack {
                    Text("Máximo de items")
                    Spacer()
                    Stepper(value: $settings.ghMaxResults, in: 10...300, step: 10) {
                        Text("\(settings.ghMaxResults)").monospacedDigit()
                    }
                }
            }

            Section("Diagnóstico") {
                Toggle("Logs detallados (NSLog)", isOn: $settings.ghDebug)
                HStack {
                    Button { runTest() } label: {
                        if case .running = testStatus {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Probar token", systemImage: "wave.3.right")
                        }
                    }
                    .disabled(testStatus == .running)

                    switch testStatus {
                    case .idle:
                        EmptyView()
                    case .running:
                        Text("Verificando…").foregroundColor(.secondary)
                    case .ok(let name):
                        Label("Autenticado como \(name)", systemImage: "checkmark.seal")
                            .foregroundColor(.green)
                    case .error(let msg):
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func runTest() {
        testStatus = .running
        gh.testConnection(token: settings.ghToken) { result in
            switch result {
            case .success(let name): testStatus = .ok(name)
            case .failure(let msg):  testStatus = .error(msg)
            }
        }
    }
}
