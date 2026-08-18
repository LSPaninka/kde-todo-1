import AppKit
import Combine
import Foundation

/// Cliente **read-only** de la Google Calendar API v3.  Renderiza los
/// eventos como bloques de fondo inmóviles sobre el grid, así se ven las
/// reuniones mientras cargás horas (podés loggear "encima" de ellas).
///
/// Auth: OAuth 2.0 con el client type "TV and Limited Input devices"
/// (device-code flow, sin redirect URI ni servidor local).  La
/// autorización one-shot se hace desde Preferencias y devuelve un
/// *refresh token*; este store lo canjea por access tokens de corta
/// duración en runtime.  Sólo se pide el scope `calendar.readonly` — la
/// app nunca escribe en Google.
///
/// Endpoints:
///   - POST https://oauth2.googleapis.com/device/code       (device flow)
///   - POST https://oauth2.googleapis.com/token             (refresh → access)
///   - GET  https://www.googleapis.com/calendar/v3/users/me/calendarList
///   - GET  https://www.googleapis.com/calendar/v3/calendars/{id}/events
final class GoogleCalendarStore: ObservableObject {

    @Published private(set) var events: [GoogleCalendarEvent] = []
    /// Lista de calendarios de la cuenta — la llena `fetchCalendarList()`
    /// para el picker de Preferencias.
    @Published private(set) var calendars: [GoogleCalendarInfo] = []

    @Published private(set) var loading: Bool = false
    @Published var lastError: String = ""
    @Published private(set) var lastFetchedAt: Date? = nil
    @Published private(set) var debugLog: String = ""

    var settings: AppSettings

    /// Access token de corta duración + su expiración.  Se renueva solo
    /// cuando falta o está a menos de 60 s de vencer.
    private var accessToken: String = ""
    private var accessTokenExp: Date = .distantPast

    init(settings: AppSettings) { self.settings = settings }

    // MARK: - Credenciales

    private struct Creds {
        let clientId: String
        let clientSecret: String
        let refreshToken: String
    }

    private func credentials() -> Creds? {
        let id = settings.googleClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = settings.googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let refresh = settings.googleRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty || secret.isEmpty || refresh.isEmpty {
            lastError = "Falta autorizar Google Calendar (Preferencias → Google)."
            warn("Faltan credenciales: id=\(!id.isEmpty) secret=\(!secret.isEmpty) refresh=\(!refresh.isEmpty)")
            return nil
        }
        return Creds(clientId: id, clientSecret: secret, refreshToken: refresh)
    }

    /// Garantiza un access token válido, renovándolo con el refresh token
    /// cuando hace falta.
    private func ensureAccessToken(completion: @escaping (String?) -> Void) {
        if !accessToken.isEmpty, Date() < accessTokenExp.addingTimeInterval(-60) {
            completion(accessToken)
            return
        }
        guard let creds = credentials() else { completion(nil); return }

        let form = [
            "client_id": creds.clientId,
            "client_secret": creds.clientSecret,
            "refresh_token": creds.refreshToken,
            "grant_type": "refresh_token"
        ]
        log("POST oauth2 token (refresh)")
        Self.postForm(url: URL(string: "https://oauth2.googleapis.com/token")!,
                      fields: form) { [weak self] code, body in
            guard let self else { completion(nil); return }
            guard code == 200,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String, !token.isEmpty else {
                self.warn("token refresh exit=\(code): \(body.prefix(240))")
                self.lastError = "No se pudo renovar el token de Google (HTTP \(code))."
                completion(nil)
                return
            }
            let ttl = (json["expires_in"] as? Double) ?? 3600
            self.accessToken = token
            self.accessTokenExp = Date().addingTimeInterval(ttl)
            self.log("Access token renovado (expira en \(Int(ttl))s).")
            completion(token)
        }
    }

    // MARK: - Fetch de la semana

    /// Los hasta 3 calendarios configurados.  Si la lista está vacía cae
    /// al `googleCalendarId` legacy (compat con la config vieja).
    private func calendarIds() -> [String] {
        var ids = settings.googleCalendarIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if ids.isEmpty {
            let legacy = settings.googleCalendarId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !legacy.isEmpty { ids = [legacy] }
        }
        return Array(ids.prefix(3))
    }

    func fetchWeek(starting weekStart: Date) {
        guard settings.googleCalEnabled else {
            log("googleCalEnabled=false — no fetch.")
            return
        }
        if loading { warn("[abort] ya hay un fetch en curso."); return }

        appendDebug("=== Google fetch \(timestamp()) ===")
        loading = true
        lastError = ""

        ensureAccessToken { [weak self] token in
            guard let self else { return }
            guard let token else {
                self.loading = false
                return
            }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let startDate = cal.startOfDay(for: weekStart)
            let endDate = startDate.addingTimeInterval(7 * 86_400)

            let ids = self.calendarIds()
            if ids.isEmpty {
                self.events = []
                self.lastFetchedAt = Date()
                self.loading = false
                return
            }

            // Traemos todos los calendarios en paralelo y acumulamos.
            let group = DispatchGroup()
            var acc: [GoogleCalendarEvent] = []
            let lock = NSLock()
            for calId in ids {
                group.enter()
                self.fetchOne(token: token, calendarId: calId,
                              start: startDate, end: endDate) { evs in
                    lock.lock(); acc.append(contentsOf: evs); lock.unlock()
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.events = acc.sorted { $0.startedMs < $1.startedMs }
                self.lastFetchedAt = Date()
                self.loading = false
                self.log("Eventos totales: \(self.events.count) (\(ids.count) calendario(s)).")
            }
        }
    }

    private func fetchOne(token: String,
                          calendarId: String,
                          start: Date,
                          end: Date,
                          completion: @escaping ([GoogleCalendarEvent]) -> Void) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let escapedId = calendarId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? calendarId
        let timeMin = iso.string(from: start).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let timeMax = iso.string(from: end).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let urlStr = "https://www.googleapis.com/calendar/v3/calendars/\(escapedId)/events" +
            "?timeMin=\(timeMin)&timeMax=\(timeMax)" +
            "&singleEvents=true&orderBy=startTime&maxResults=250"
        guard let url = URL(string: urlStr) else { completion([]); return }

        log("GET \(urlStr)")
        Self.get(url: url, bearer: token) { [weak self] code, body in
            guard let self else { completion([]); return }
            guard code == 200 else {
                self.lastError = "HTTP \(code) al traer eventos de Google (\(calendarId))."
                self.warn("events[\(calendarId)] exit=\(code): \(body.prefix(240))")
                completion([])
                return
            }
            completion(self.parseEvents(body: body, calendarId: calendarId,
                                        start: start, end: end))
        }
    }

    private func parseEvents(body: String,
                             calendarId: String,
                             start: Date,
                             end: Date) -> [GoogleCalendarEvent] {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            warn("parse events[\(calendarId)] falló")
            return []
        }
        let startMs = start.timeIntervalSince1970 * 1000
        let endMs = end.timeIntervalSince1970 * 1000
        var out: [GoogleCalendarEvent] = []
        for ev in items {
            if (ev["status"] as? String) == "cancelled" { continue }
            // Saltamos los all-day (traen `date`, no `dateTime`): no
            // mapean a un bloque horario en la grilla.
            guard let s = ev["start"] as? [String: Any],
                  let e = ev["end"] as? [String: Any],
                  let sStr = s["dateTime"] as? String,
                  let eStr = e["dateTime"] as? String,
                  let sMs = Self.parseRFC3339Ms(sStr),
                  let eMs = Self.parseRFC3339Ms(eStr),
                  eMs > sMs else { continue }
            if eMs <= startMs || sMs >= endMs { continue }
            let eid = (ev["id"] as? String) ?? UUID().uuidString
            out.append(.init(
                id: "\(calendarId):\(eid)",
                summary: (ev["summary"] as? String) ?? "(sin título)",
                startedMs: sMs,
                durationSec: Int(((eMs - sMs) / 1000).rounded()),
                calendarId: calendarId
            ))
        }
        log("Eventos[\(calendarId)]: \(out.count).")
        return out
    }

    // MARK: - Lista de calendarios (para Preferencias)

    /// GET /users/me/calendarList → puebla `calendars`.
    func fetchCalendarList(completion: @escaping (Result<Int, StringError>) -> Void) {
        ensureAccessToken { [weak self] token in
            guard let self else { return }
            guard let token else {
                completion(.failure(StringError(self.lastError.isEmpty
                                                ? "No se pudo obtener un token de Google."
                                                : self.lastError)))
                return
            }
            let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250")!
            self.log("GET calendarList")
            Self.get(url: url, bearer: token) { code, body in
                guard code == 200,
                      let data = body.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["items"] as? [[String: Any]] else {
                    self.warn("calendarList exit=\(code): \(body.prefix(200))")
                    completion(.failure(StringError("HTTP \(code) al listar calendarios.")))
                    return
                }
                var out: [GoogleCalendarInfo] = []
                for c in items {
                    guard let id = c["id"] as? String else { continue }
                    out.append(.init(id: id,
                                     summary: (c["summary"] as? String) ?? id,
                                     primary: (c["primary"] as? Bool) ?? false))
                }
                // Primary primero, después alfabético.
                self.calendars = out.sorted {
                    if $0.primary != $1.primary { return $0.primary }
                    return $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending
                }
                self.log("Calendarios: \(out.count).")
                completion(.success(out.count))
            }
        }
    }

    // MARK: - Device-code flow (autorización one-shot)

    struct DeviceCodeInfo {
        let deviceCode: String
        let userCode: String
        let verificationUrl: String
        let interval: Int          // segundos entre polls
        let expiresAt: Date
    }

    /// Paso 1: pedir el código de dispositivo.  Devuelve el `user_code`
    /// que el usuario tipea en google.com/device.
    func requestDeviceCode(clientId: String,
                           completion: @escaping (Result<DeviceCodeInfo, StringError>) -> Void) {
        let id = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            completion(.failure(StringError("Pegá el Client ID primero.")))
            return
        }
        let form = [
            "client_id": id,
            "scope": "https://www.googleapis.com/auth/calendar.readonly"
        ]
        log("POST oauth2 device/code")
        Self.postForm(url: URL(string: "https://oauth2.googleapis.com/device/code")!,
                      fields: form) { [weak self] code, body in
            guard code == 200,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let deviceCode = json["device_code"] as? String,
                  let userCode = json["user_code"] as? String else {
                self?.warn("device/code exit=\(code): \(body.prefix(200))")
                completion(.failure(StringError("Error solicitando código (HTTP \(code)).")))
                return
            }
            let url = (json["verification_url"] as? String)
                ?? (json["verification_uri"] as? String)
                ?? "https://www.google.com/device"
            let interval = max(2, (json["interval"] as? Int) ?? 5)
            let expiresIn = (json["expires_in"] as? Double) ?? 600
            completion(.success(DeviceCodeInfo(
                deviceCode: deviceCode,
                userCode: userCode,
                verificationUrl: url,
                interval: interval,
                expiresAt: Date().addingTimeInterval(expiresIn)
            )))
        }
    }

    /// Resultado de un poll del device flow.
    enum PollOutcome {
        case pending                 // el usuario todavía no aprobó
        case slowDown                // hay que ampliar el intervalo
        case success(String)         // refresh token
        case failed(String)          // error terminal
    }

    /// Paso 2: pollear hasta que el usuario apruebe.  El caller repite
    /// según `interval` mientras reciba `.pending` / `.slowDown`.
    func pollDeviceToken(clientId: String,
                         clientSecret: String,
                         deviceCode: String,
                         completion: @escaping (PollOutcome) -> Void) {
        let form = [
            "client_id": clientId.trimmingCharacters(in: .whitespacesAndNewlines),
            "client_secret": clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]
        Self.postForm(url: URL(string: "https://oauth2.googleapis.com/token")!,
                      fields: form) { code, body in
            let json = (body.data(using: .utf8)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
            if code == 200, let refresh = json["refresh_token"] as? String, !refresh.isEmpty {
                completion(.success(refresh))
                return
            }
            switch (json["error"] as? String) ?? "" {
            case "authorization_pending": completion(.pending)
            case "slow_down":             completion(.slowDown)
            case "access_denied":         completion(.failed("Acceso denegado en Google."))
            case "expired_token":         completion(.failed("El código expiró. Volvé a intentar."))
            default:
                if code != 200 {
                    completion(.failed("Error autorizando (HTTP \(code))."))
                } else {
                    completion(.pending)
                }
            }
        }
    }

    // MARK: - HTTP helpers

    private static func postForm(url: URL,
                                 fields: [String: String],
                                 completion: @escaping (Int, String) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            DispatchQueue.main.async {
                completion((resp as? HTTPURLResponse)?.statusCode ?? 0,
                           data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
            }
        }.resume()
    }

    private static func get(url: URL,
                            bearer: String,
                            completion: @escaping (Int, String) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            DispatchQueue.main.async {
                completion((resp as? HTTPURLResponse)?.statusCode ?? 0,
                           data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
            }
        }.resume()
    }

    /// Google manda RFC-3339 con offset (`2026-06-19T10:00:00-03:00`) y a
    /// veces con fracción de segundo.
    static func parseRFC3339Ms(_ s: String) -> Double? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d.timeIntervalSince1970 * 1000 }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d.timeIntervalSince1970 * 1000 }
        return nil
    }

    // MARK: - Logging

    func clearDebugLog() { debugLog = "" }

    private func log(_ msg: String) {
        appendDebug(msg)
        if settings.googleCalDebug { NSLog("[GoogleCal] %@", msg) }
    }
    private func warn(_ msg: String) {
        appendDebug("[!] " + msg)
        NSLog("[GoogleCal] %@", msg)
    }
    private func appendDebug(_ line: String) {
        let next = (debugLog.isEmpty ? "" : debugLog + "\n") + line
        if next.count > 80_000 {
            let cut = next.index(next.endIndex, offsetBy: -40_000)
            debugLog = "[…log truncado…]\n" + String(next[cut...])
        } else {
            debugLog = next
        }
    }
    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
