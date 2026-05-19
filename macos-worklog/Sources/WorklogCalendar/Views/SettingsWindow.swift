import SwiftUI

/// Preferencias.  Tres pestañas: General, Jira, Clockify.  Cada una con
/// un botón "Probar conexión".
struct SettingsWindow: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var jira: JiraWorklogStore
    @ObservedObject var clockify: ClockifyStore
    @Binding var presented: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }
                JiraTab(settings: settings, jira: jira)
                    .tabItem { Label("Jira", systemImage: "ant") }
                ClockifyTab(settings: settings, clockify: clockify)
                    .tabItem { Label("Clockify", systemImage: "clock") }
            }
            HStack {
                Spacer()
                Button("Cerrar") { presented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 620, height: 540)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Vista") {
                Picker("Modo horario", selection: $settings.viewMode) {
                    Text("9h (09:00 – 18:00)").tag(ViewHourMode.h9)
                    Text("24h (00:00 – 24:00)").tag(ViewHourMode.h24)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Objetivo diario (h)")
                    Spacer()
                    Stepper(value: $settings.dailyTargetHours, in: 0...24, step: 0.5) {
                        Text(String(format: "%.1f", settings.dailyTargetHours))
                            .monospacedDigit()
                    }
                }
            }

            Section("Bloques") {
                Toggle("Mostrar el título de la issue en bloques Jira", isOn: $settings.showIssueSummary)
            }

            Section("Picker de issues") {
                TextField("JQL", text: $settings.jiraIssueJql, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Text("Máx. issues")
                    Spacer()
                    Stepper(value: $settings.jiraIssueMax, in: 10...200, step: 10) {
                        Text("\(settings.jiraIssueMax)").monospacedDigit()
                    }
                }
            }

            Section("Diagnóstico") {
                Toggle("NSLog detallado de cada request", isOn: $settings.debug)
                Text("Visibles con: log stream --predicate 'process == \"WorklogCalendar\"' --info")
                    .font(.caption2).foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}

private struct JiraTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var jira: JiraWorklogStore

    @State private var showToken = false
    @State private var status: (text: String, isError: Bool) = ("", false)
    @State private var testing: Bool = false

    var body: some View {
        Form {
            Section("Cuenta") {
                TextField("Sitio Jira (ej. https://you.atlassian.net)",
                          text: $settings.jiraSite)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                TextField("Email", text: $settings.jiraEmail)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                HStack {
                    if showToken {
                        TextField("API token", text: $settings.jiraToken)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API token", text: $settings.jiraToken)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showToken.toggle() } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                Text("Token generado en id.atlassian.com → API tokens. Se guarda en el Keychain (servicio com.worklogcalendar.app, cuenta jira.token).")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Probar conexión") {
                HStack {
                    Button {
                        runTest()
                    } label: {
                        if testing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Probar", systemImage: "network")
                        }
                    }
                    .disabled(testing)
                    if !status.text.isEmpty {
                        Text(status.text)
                            .foregroundColor(status.isError ? .red : .green)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding()
    }

    private func runTest() {
        status = ("Conectando…", false)
        testing = true
        jira.testConnection(site: settings.jiraSite,
                            email: settings.jiraEmail,
                            token: settings.jiraToken) { result in
            testing = false
            switch result {
            case .success(let name): status = ("OK — autenticado como \(name)", false)
            case .failure(let err):  status = (err.message, true)
            }
        }
    }
}

private struct ClockifyTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var clockify: ClockifyStore

    @State private var showKey = false
    @State private var status: (text: String, isError: Bool) = ("", false)
    @State private var testing: Bool = false

    var body: some View {
        Form {
            Section("Cuenta") {
                HStack {
                    if showKey {
                        TextField("API key", text: $settings.clockifyApiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API key", text: $settings.clockifyApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                Text("Generala en Clockify → Profile → Settings → API. Se guarda en el Keychain (cuenta clockify.api-key).")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Workspace / usuario") {
                TextField("Workspace ID (24 chars hex; vacío = default)",
                          text: $settings.clockifyWorkspaceId)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .font(.system(.body, design: .monospaced))
                Text("Si dejás vacío o ponés un valor que no sea un ObjectId hex de 24 caracteres, la app va a auto-resolverlo desde /user en la primera sincronización.")
                    .font(.caption).foregroundColor(.secondary)

                TextField("User ID (auto-resuelto)", text: $settings.clockifyUserId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(true)
            }

            Section("Defaults para nuevas entradas") {
                TextField("Proyecto por defecto (ID, opcional)",
                          text: $settings.clockifyDefaultProjectId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Toggle("Facturable por defecto", isOn: $settings.clockifyBillableDefault)
            }

            Section("Probar conexión") {
                HStack {
                    Button {
                        runTest()
                    } label: {
                        if testing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Probar", systemImage: "network")
                        }
                    }
                    .disabled(testing)
                    if !status.text.isEmpty {
                        Text(status.text)
                            .foregroundColor(status.isError ? .red : .green)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding()
    }

    private func runTest() {
        status = ("Conectando…", false)
        testing = true
        clockify.testApiKey(settings.clockifyApiKey) { result in
            testing = false
            switch result {
            case .success(let label): status = ("OK — \(label)", false)
            case .failure(let err):   status = (err.message, true)
            }
        }
    }
}
