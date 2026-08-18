import AppKit
import SwiftUI

/// Pestaña de Preferencias para Google Calendar (read-only).
///
/// El flujo de autorización usa el client type "TV and Limited Input
/// devices" (device-code): pegás Client ID + Secret, apretás "Autorizar",
/// se abre google.com/device con un código, y la app poll-ea hasta que
/// aprobás.  Resultado: un refresh token guardado en el Keychain.
struct GoogleSettingsView: View {
    @ObservedObject var google: GoogleCalendarStore
    @ObservedObject var settings: AppSettings

    @State private var showSecret = false
    @State private var status: (text: String, isError: Bool) = ("", false)

    // Estado del device flow.
    @State private var deviceCode: String = ""
    @State private var userCode: String = ""
    @State private var verificationUrl: String = ""
    @State private var pollInterval: Int = 5
    @State private var expiresAt: Date = .distantPast
    @State private var polling: Bool = false

    @State private var loadingCalendars = false

    /// Paleta de colores para asignar a cada calendario.
    private let palette: [String] = [
        "#e74c3c", "#e67e22", "#f1c40f", "#2ecc71",
        "#1abc9c", "#3498db", "#9b59b6", "#95a5a6"
    ]

    var body: some View {
        Form {
            Section("Eventos") {
                Toggle("Mostrar eventos de Google Calendar en el calendario",
                       isOn: $settings.googleCalEnabled)
                Text("Los eventos se dibujan como bloques translúcidos de fondo: no se pueden mover ni seleccionar, y podés cargar worklogs por encima.")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Section("Credenciales OAuth") {
                TextField("Client ID", text: $settings.googleClientId)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                HStack {
                    if showSecret {
                        TextField("Client Secret", text: $settings.googleClientSecret)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Client Secret", text: $settings.googleClientSecret)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { showSecret.toggle() } label: {
                        Image(systemName: showSecret ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                Text("Creá un OAuth client de tipo «TV and Limited Input devices» en Google Cloud Console (gratis) y habilitá la Calendar API. Se guarda en el Keychain.")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Section("Autorización") {
                if settings.googleRefreshToken.isEmpty {
                    Text("Sin autorizar.")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Label("Autorizado — refresh token guardado.", systemImage: "checkmark.seal")
                        .font(.caption).foregroundColor(.green)
                }

                if polling {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ingresá este código en \(verificationUrl):")
                            .font(.caption)
                        Text(userCode)
                            .font(.system(.title2, design: .monospaced)).bold()
                            .textSelection(.enabled)
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Esperando tu aprobación…")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Button("Cancelar") { stopPolling("") }
                        }
                    }
                } else {
                    HStack {
                        Button {
                            startDeviceFlow()
                        } label: {
                            Label(settings.googleRefreshToken.isEmpty
                                  ? "Autorizar" : "Volver a autorizar",
                                  systemImage: "person.badge.key")
                        }
                        .disabled(settings.googleClientId.trimmingCharacters(in: .whitespaces).isEmpty)

                        if !settings.googleRefreshToken.isEmpty {
                            Button(role: .destructive) {
                                settings.googleRefreshToken = ""
                                status = ("Autorización revocada localmente.", false)
                            } label: {
                                Label("Desautorizar", systemImage: "trash")
                            }
                        }
                    }
                }

                if !status.text.isEmpty {
                    Text(status.text)
                        .font(.callout)
                        .foregroundColor(status.isError ? .red : .green)
                }
            }

            Section("Calendarios (hasta 3)") {
                HStack {
                    Button {
                        loadCalendars()
                    } label: {
                        if loadingCalendars {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Cargar mis calendarios", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(settings.googleRefreshToken.isEmpty || loadingCalendars)
                    if !google.calendars.isEmpty {
                        Text("\(google.calendars.count) disponibles")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }

                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 8) {
                        Picker("Calendario \(i + 1)", selection: calendarBinding(i)) {
                            Text("(ninguno)").tag("")
                            ForEach(google.calendars) { c in
                                Text(c.primary ? "\(c.summary) (principal)" : c.summary)
                                    .tag(c.id)
                            }
                            // Si el id guardado no está en la lista
                            // (todavía no cargaron), lo mostramos igual
                            // para no perderlo.
                            let saved = calendarBinding(i).wrappedValue
                            if !saved.isEmpty && !google.calendars.contains(where: { $0.id == saved }) {
                                Text(saved).tag(saved)
                            }
                        }
                        .pickerStyle(.menu)

                        colorSwatchPicker(i)
                    }
                }
                Text("Cada calendario puede tener su color; los bloques siempre se dibujan translúcidos.")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Section("Diagnóstico") {
                Toggle("NSLog detallado de cada request", isOn: $settings.googleCalDebug)
            }
        }
        .formStyle(.grouped)
    }

    /// Swatch + menú de paleta para el color del calendario `i`.
    @ViewBuilder
    private func colorSwatchPicker(_ i: Int) -> some View {
        let current = colorBinding(i).wrappedValue
        Menu {
            ForEach(palette, id: \.self) { hex in
                Button {
                    colorBinding(i).wrappedValue = hex
                } label: {
                    Label(hex, systemImage: hex == current ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: current) ?? .red)
                .frame(width: 22, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .frame(width: 46)
        .help("Color del calendario \(i + 1)")
    }

    // MARK: - Bindings a los arrays paralelos

    private func calendarBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: {
                settings.googleCalendarIds.indices.contains(i)
                    ? settings.googleCalendarIds[i] : ""
            },
            set: { newValue in
                var ids = settings.googleCalendarIds
                while ids.count < 3 { ids.append("") }
                ids[i] = newValue
                settings.googleCalendarIds = ids
                // Aseguramos color paralelo.
                var cols = settings.googleCalendarColors
                while cols.count < 3 { cols.append(palette[cols.count % palette.count]) }
                settings.googleCalendarColors = cols
            })
    }

    private func colorBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: {
                settings.googleCalendarColors.indices.contains(i)
                    ? settings.googleCalendarColors[i]
                    : AppSettings.googleDefaultColor
            },
            set: { newValue in
                var cols = settings.googleCalendarColors
                while cols.count < 3 { cols.append(AppSettings.googleDefaultColor) }
                cols[i] = newValue
                settings.googleCalendarColors = cols
            })
    }

    // MARK: - Device flow

    private func startDeviceFlow() {
        status = ("Solicitando código…", false)
        google.requestDeviceCode(clientId: settings.googleClientId) { result in
            switch result {
            case .failure(let err):
                status = (err.message, true)
            case .success(let info):
                deviceCode = info.deviceCode
                userCode = info.userCode
                verificationUrl = info.verificationUrl
                pollInterval = info.interval
                expiresAt = info.expiresAt
                polling = true
                status = ("", false)
                if let url = URL(string: info.verificationUrl) {
                    NSWorkspace.shared.open(url)
                }
                schedulePoll()
            }
        }
    }

    /// Un poll cada `pollInterval` segundos hasta que el usuario aprueba,
    /// se cancela, o expira el código.
    private func schedulePoll() {
        guard polling else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(pollInterval)) {
            guard polling else { return }
            if Date() > expiresAt {
                stopPolling("El código expiró. Volvé a intentar.", isError: true)
                return
            }
            google.pollDeviceToken(clientId: settings.googleClientId,
                                   clientSecret: settings.googleClientSecret,
                                   deviceCode: deviceCode) { outcome in
                switch outcome {
                case .pending:
                    schedulePoll()
                case .slowDown:
                    pollInterval += 2
                    schedulePoll()
                case .success(let refresh):
                    settings.googleRefreshToken = refresh
                    stopPolling("¡Listo! Google Calendar autorizado. Cargá tus calendarios abajo.")
                case .failed(let msg):
                    stopPolling(msg, isError: true)
                }
            }
        }
    }

    private func stopPolling(_ message: String, isError: Bool = false) {
        polling = false
        deviceCode = ""; userCode = ""
        if !message.isEmpty { status = (message, isError) }
    }

    private func loadCalendars() {
        loadingCalendars = true
        google.fetchCalendarList { result in
            loadingCalendars = false
            switch result {
            case .success(let n): status = ("\(n) calendario(s) cargados.", false)
            case .failure(let err): status = (err.message, true)
            }
        }
    }
}
