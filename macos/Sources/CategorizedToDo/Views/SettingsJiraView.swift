import SwiftUI

/// Settings tab — Jira connection (site, email, token, JQL, refresh, debug).
struct JiraSettingsView: View {
    @ObservedObject var jira: JiraStore
    @ObservedObject var settings: AppSettings

    @State private var showToken: Bool = false
    @State private var testStatus: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle
        case running
        case ok(String)
        case error(String)
    }

    var body: some View {
        Form {
            Section("Conexión") {
                TextField("URL del Jira (ej: https://acme.atlassian.net)",
                          text: $settings.jiraSite)
                    .textContentType(.URL)
                    .autocorrectionDisabled(true)

                TextField("Email de la cuenta",
                          text: $settings.jiraEmail)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled(true)

                HStack {
                    if showToken {
                        TextField("API token", text: $settings.jiraToken)
                            .autocorrectionDisabled(true)
                    } else {
                        SecureField("API token", text: $settings.jiraToken)
                    }
                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showToken ? "Ocultar token" : "Mostrar token")
                }

                Text("El token se guarda en el Keychain (no en UserDefaults). Generalo en id.atlassian.com/manage-profile/security/api-tokens. Podés revocarlo en cualquier momento.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Consulta") {
                TextField("JQL", text: $settings.jiraJql, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(.body, design: .monospaced))

                HStack {
                    Text("Auto-refresh (min)")
                    Spacer()
                    Stepper(value: $settings.jiraRefreshMinutes, in: 0...1440) {
                        Text("\(settings.jiraRefreshMinutes)").monospacedDigit()
                    }
                }
                Text("0 desactiva el auto-refresh (solo manual).")
                    .font(.caption).foregroundColor(.secondary)

                HStack {
                    Text("Máximo de issues")
                    Spacer()
                    Stepper(value: $settings.jiraMaxResults, in: 10...200, step: 10) {
                        Text("\(settings.jiraMaxResults)").monospacedDigit()
                    }
                }
            }

            Section("Diagnóstico") {
                Toggle("Logs detallados (NSLog)", isOn: $settings.jiraDebug)
                Text("Visibles con: log stream --predicate 'process == \"CategorizedToDo\"' --info")
                    .font(.caption2).foregroundColor(.secondary)
                    .textSelection(.enabled)

                HStack {
                    Button {
                        runTest()
                    } label: {
                        if case .running = testStatus {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Probar conexión", systemImage: "wave.3.right")
                        }
                    }
                    .disabled(testStatus == .running)

                    switch testStatus {
                    case .idle:
                        EmptyView()
                    case .running:
                        Text("Verificando…").foregroundColor(.secondary)
                    case .ok(let name):
                        Label(name, systemImage: "checkmark.seal")
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
        jira.testConnection(site: settings.jiraSite,
                            email: settings.jiraEmail,
                            token: settings.jiraToken) { result in
            switch result {
            case .success(let name): testStatus = .ok("Conectado como \(name)")
            case .failure(let msg):  testStatus = .error(msg)
            }
        }
    }
}
