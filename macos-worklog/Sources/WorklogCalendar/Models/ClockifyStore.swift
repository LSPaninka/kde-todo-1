import Foundation
import Combine
import AppKit

/// Cliente REST de Clockify (https://api.clockify.me/api/v1).
/// Auth: header `X-Api-Key`.  Resuelve `userId` + `workspaceId` en la
/// primera sync vía `GET /user` y los cachea en `AppSettings`.
final class ClockifyStore: ObservableObject {

    @Published private(set) var projects: [ClockifyProject] = []
    @Published private(set) var tags: [ClockifyTag] = []
    @Published private(set) var entries: [ClockifyEntry] = []

    @Published private(set) var loading: Bool = false
    @Published var lastError: String = ""
    @Published private(set) var lastFetchedAt: Date? = nil

    @Published private(set) var debugLog: String = ""

    var settings: AppSettings

    init(settings: AppSettings) { self.settings = settings }

    private var apiKey: String { settings.clockifyApiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    var ready: Bool { !apiKey.isEmpty }

    // MARK: - API pública

    /// Resuelve `userId` + `workspaceId` + lista de proyectos y tags.
    /// El `completion` recibe `true` cuando todo el árbol está listo.
    func ensureContext(completion: @escaping (Bool) -> Void) {
        guard !apiKey.isEmpty else {
            lastError = "Falta la API key de Clockify."
            warn("Falta API key.")
            completion(false)
            return
        }
        // Refrescamos los ids cacheados, descartando valores inválidos
        // (un nombre de workspace en vez del ObjectId daría 403 contra
        // /workspaces/<wid>/*).
        let rawWid = settings.clockifyWorkspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawUid = settings.clockifyUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        var workspaceId = AppSettings.isValidObjectId(rawWid) ? rawWid : ""
        let userId      = AppSettings.isValidObjectId(rawUid) ? rawUid : ""
        if !rawWid.isEmpty && workspaceId.isEmpty {
            warn("Workspace ID guardado ('\(rawWid)') no es ObjectId hex 24; usando default.")
        }

        // Si ya tenemos todo, no hacemos nada.
        if !workspaceId.isEmpty, !userId.isEmpty, !projects.isEmpty {
            completion(true)
            return
        }
        log("Resolviendo usuario + workspace + proyectos…")
        let url = URL(string: "https://api.clockify.me/api/v1/user")!
        send(.get, url: url, body: nil) { [weak self] code, body in
            guard let self else { completion(false); return }
            if code != 200 {
                self.lastError = "HTTP \(code) contra /user."
                self.warn("/user exit=\(code): \(body.prefix(200))")
                completion(false)
                return
            }
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.lastError = "Respuesta inválida de /user."
                completion(false)
                return
            }
            let resolvedUserId = (json["id"] as? String) ?? ""
            if workspaceId.isEmpty {
                let defaultWs = (json["defaultWorkspace"] as? String) ?? ""
                let activeWs  = (json["activeWorkspace"]  as? String) ?? ""
                workspaceId = !defaultWs.isEmpty ? defaultWs : activeWs
            }
            self.settings.clockifyUserId      = resolvedUserId
            self.settings.clockifyWorkspaceId = workspaceId
            self.log("user=\(resolvedUserId) workspace=\(workspaceId)")
            if !AppSettings.isValidObjectId(workspaceId) {
                self.lastError = "No pude resolver un workspace válido desde /user."
                completion(false)
                return
            }
            self.loadProjects(workspaceId: workspaceId) { ok in
                if !ok { completion(false); return }
                self.loadTags(workspaceId: workspaceId) { _ in
                    completion(true)
                }
            }
        }
    }

    func fetchWeek(starting weekStart: Date) {
        if loading { warn("[abort] fetch en curso."); return }
        loading = true
        lastError = ""
        appendDebug("=== Clockify fetch \(timestamp()) ===")
        ensureContext { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.loading = false
                return
            }
            let wid = self.settings.clockifyWorkspaceId
            let uid = self.settings.clockifyUserId
            let startMs = weekStart.timeIntervalSince1970 * 1000
            let endMs   = startMs + 7 * 86_400_000
            let startISO = Self.utcIso(Date(timeIntervalSince1970: startMs / 1000))
            let endISO   = Self.utcIso(Date(timeIntervalSince1970: endMs / 1000))
            let urlStr = "https://api.clockify.me/api/v1/workspaces/\(wid)/user/\(uid)/time-entries" +
                "?start=\(startISO)&end=\(endISO)&page-size=200"
            guard let escaped = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: escaped) else {
                self.loading = false
                self.lastError = "URL inválida para time-entries."
                return
            }
            self.log("GET \(url.absoluteString)")
            self.send(.get, url: url, body: nil) { [weak self] code, body in
                guard let self else { return }
                if code != 200 {
                    self.loading = false
                    self.lastError = "HTTP \(code) al traer time entries."
                    self.warn("time-entries exit=\(code): \(body.prefix(240))")
                    return
                }
                self.processEntries(body: body)
            }
        }
    }

    // MARK: - Month totals (heatmap)

    /// Agrega mis segundos de time-entries por día-del-mes (1-indexed)
    /// para el mes `monthIndex` (0..11).  Pagina hasta agotar y no
    /// toca el array `entries[]`.  El callback recibe el dict o `nil`.
    func fetchMonthTotals(year: Int,
                          monthIndex: Int,
                          completion: @escaping ([Int: Int]?) -> Void) {
        ensureContext { [weak self] ok in
            guard let self, ok else { completion(nil); return }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            var startComps = DateComponents()
            startComps.year = year; startComps.month = monthIndex + 1; startComps.day = 1
            var nextComps = DateComponents()
            nextComps.year = year; nextComps.month = monthIndex + 2; nextComps.day = 1
            guard let startD = cal.date(from: startComps),
                  let nextD  = cal.date(from: nextComps) else {
                completion(nil); return
            }

            let wid = self.settings.clockifyWorkspaceId
            let uid = self.settings.clockifyUserId
            var totals: [Int: Int] = [:]
            let pageSize = 200
            var page = 1

            var fetchPage: () -> Void = {}
            fetchPage = {
                let urlStr = "https://api.clockify.me/api/v1/workspaces/\(wid)/user/\(uid)/time-entries" +
                    "?start=\(Self.utcIso(startD))&end=\(Self.utcIso(nextD))" +
                    "&page-size=\(pageSize)&page=\(page)"
                guard let escaped = urlStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: escaped) else {
                    completion(nil); return
                }
                self.log("Month(Clockify) GET \(url.absoluteString)")
                self.send(.get, url: url, body: nil) { code, body in
                    if code != 200 {
                        self.warn("month totals exit=\(code): \(body.prefix(200))")
                        completion(nil); return
                    }
                    guard let data = body.data(using: .utf8),
                          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                        completion(nil); return
                    }
                    for e in arr {
                        guard let ti = e["timeInterval"] as? [String: Any],
                              let startStr = ti["start"] as? String,
                              let endStr   = ti["end"]   as? String,
                              let s = Self.parseUtcIsoMs(startStr),
                              let n = Self.parseUtcIsoMs(endStr),
                              n > s else { continue }
                        let d = Date(timeIntervalSince1970: s / 1000)
                        let comps = cal.dateComponents([.year, .month, .day], from: d)
                        if comps.year == year, comps.month == monthIndex + 1,
                           let day = comps.day {
                            totals[day, default: 0] += Int(round((n - s) / 1000))
                        }
                    }
                    // Si la página vino llena, pedimos la siguiente.
                    if arr.count >= pageSize {
                        page += 1
                        fetchPage()
                    } else {
                        self.log("Month(Clockify) \(monthIndex + 1)/\(year): \(totals.count) días con entries.")
                        completion(totals)
                    }
                }
            }
            fetchPage()
        }
    }

    // MARK: - Create / Update / Delete

    func createEntry(start: Date,
                     end: Date,
                     description: String,
                     projectId: String,
                     tagIds: [String],
                     billable: Bool,
                     completion: @escaping (Result<String, StringError>) -> Void) {
        guard contextReady() else {
            completion(.failure(StringError("Sincronizá primero para resolver workspace/usuario.")))
            return
        }
        let wid = settings.clockifyWorkspaceId
        let url = URL(string: "https://api.clockify.me/api/v1/workspaces/\(wid)/time-entries")!
        var body: [String: Any] = [
            "start": Self.utcIso(start),
            "end":   Self.utcIso(end),
            "description": description,
            "billable": billable
        ]
        if !projectId.isEmpty { body["projectId"] = projectId }
        if !tagIds.isEmpty { body["tagIds"] = tagIds }

        log("POST \(url.absoluteString)")
        sendJson(.post, url: url, body: body) { code, respBody in
            if (200..<300).contains(code) {
                completion(.success(""))
            } else {
                completion(.failure(StringError("HTTP \(code): \(Self.extractError(respBody))")))
            }
        }
    }

    func updateEntry(id: String,
                     start: Date,
                     end: Date,
                     description: String,
                     projectId: String,
                     tagIds: [String],
                     billable: Bool,
                     completion: @escaping (Result<String, StringError>) -> Void) {
        guard contextReady() else {
            completion(.failure(StringError("Sincronizá primero para resolver workspace/usuario.")))
            return
        }
        let wid = settings.clockifyWorkspaceId
        let escapedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = URL(string: "https://api.clockify.me/api/v1/workspaces/\(wid)/time-entries/\(escapedId)")!
        var body: [String: Any] = [
            "start": Self.utcIso(start),
            "end":   Self.utcIso(end),
            "description": description,
            "billable": billable,
            "tagIds": tagIds
        ]
        if !projectId.isEmpty { body["projectId"] = projectId }

        log("PUT \(url.absoluteString)")
        sendJson(.put, url: url, body: body) { code, respBody in
            if (200..<300).contains(code) {
                completion(.success(""))
            } else {
                completion(.failure(StringError("HTTP \(code): \(Self.extractError(respBody))")))
            }
        }
    }

    func deleteEntry(id: String, completion: @escaping (Result<String, StringError>) -> Void) {
        guard contextReady() else {
            completion(.failure(StringError("Sincronizá primero para resolver workspace/usuario.")))
            return
        }
        let wid = settings.clockifyWorkspaceId
        let escapedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = URL(string: "https://api.clockify.me/api/v1/workspaces/\(wid)/time-entries/\(escapedId)")!
        log("DELETE \(url.absoluteString)")
        send(.delete, url: url, body: nil) { code, respBody in
            if code == 200 || code == 204 {
                completion(.success(""))
            } else {
                completion(.failure(StringError("HTTP \(code): \(Self.extractError(respBody))")))
            }
        }
    }

    // MARK: - Sync Jira → Clockify

    /// Para cada `JiraWorklog` de la semana, crea una entrada Clockify
    /// con `description = "<key>: <summary>"` si no existe ya una
    /// idéntica (mismo `description`, mismo start ±1 min, misma duración
    /// ±1 min).  El callback recibe `(created, skipped, failed)`.
    func syncFromJira(_ jiraWorklogs: [JiraWorklog],
                      defaultProjectId: String,
                      defaultBillable: Bool,
                      completion: @escaping (Int, Int, Int) -> Void) {
        guard !jiraWorklogs.isEmpty else {
            completion(0, 0, 0)
            return
        }
        ensureContext { [weak self] ok in
            guard let self, ok else { completion(0, 0, 0); return }

            var toCreate: [(start: Date, end: Date, desc: String)] = []
            for j in jiraWorklogs {
                let desc = j.issueSummary.isEmpty ? j.issueKey : "\(j.issueKey): \(j.issueSummary)"
                let alreadyThere = self.entries.contains { c in
                    c.description == desc &&
                    abs(c.startedMs - j.startedMs) <= 60_000 &&
                    abs(c.durationSec - j.durationSec) <= 60
                }
                if alreadyThere { continue }
                let start = Date(timeIntervalSince1970: j.startedMs / 1000)
                let end   = start.addingTimeInterval(Double(j.durationSec))
                toCreate.append((start, end, desc))
            }
            let skipped = jiraWorklogs.count - toCreate.count
            self.log("Sync: \(toCreate.count) entries a crear, \(skipped) ya estaban.")
            if toCreate.isEmpty {
                completion(0, jiraWorklogs.count, 0)
                return
            }
            var created = 0
            var failed = 0
            var idx = 0
            var run: () -> Void = {}
            run = {
                if idx >= toCreate.count {
                    completion(created, skipped, failed)
                    return
                }
                let t = toCreate[idx]
                let entryIdx = idx
                idx += 1
                let wid = self.settings.clockifyWorkspaceId
                let url = URL(string: "https://api.clockify.me/api/v1/workspaces/\(wid)/time-entries")!
                var body: [String: Any] = [
                    "start": Self.utcIso(t.start),
                    "end":   Self.utcIso(t.end),
                    "description": t.desc,
                    "billable": defaultBillable
                ]
                if !defaultProjectId.isEmpty { body["projectId"] = defaultProjectId }
                // Loguemos el body del primer request: si todos fallan
                // con 400 esto se puede pegar en curl para reproducir.
                if entryIdx == 0,
                   let data = try? JSONSerialization.data(withJSONObject: body, options: []),
                   let json = String(data: data, encoding: .utf8) {
                    self.log("Sync POST body sample: \(json)")
                }
                self.sendJson(.post, url: url, body: body) { code, respBody in
                    if (200..<300).contains(code) {
                        created += 1
                    } else {
                        failed += 1
                        let detail = Self.extractError(respBody)
                        self.warn("Sync create exit=\(code) (\(t.desc)) — \(detail)")
                    }
                    run()
                }
            }
            run()
        }
    }

    // MARK: - Probar conexión

    func testApiKey(_ key: String,
                    completion: @escaping (Result<String, StringError>) -> Void) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            completion(.failure(StringError("Pegá una API key antes de probar.")))
            return
        }
        let url = URL(string: "https://api.clockify.me/api/v1/user")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(key, forHTTPHeaderField: "X-Api-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err {
                    completion(.failure(StringError("Error de red: \(err.localizedDescription)")))
                    return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code != 200 {
                    completion(.failure(StringError("Credenciales rechazadas (HTTP \(code)).")))
                    return
                }
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let name = (json["name"] as? String) ?? (json["email"] as? String) ?? ""
                    let ws   = (json["defaultWorkspace"] as? String) ?? ""
                    let label = ws.isEmpty ? name : "\(name) (workspace: \(ws))"
                    completion(.success(label))
                } else {
                    completion(.success("OK"))
                }
            }
        }.resume()
    }

    // MARK: - Loading helpers

    private func loadProjects(workspaceId: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string:
            "https://api.clockify.me/api/v1/workspaces/\(workspaceId)/projects?archived=false&page-size=200")
        else { completion(false); return }

        send(.get, url: url, body: nil) { [weak self] code, body in
            guard let self else { completion(false); return }
            if code != 200 {
                self.warn("GET projects exit=\(code)")
                completion(false)
                return
            }
            guard let data = body.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                completion(false)
                return
            }
            var out: [ClockifyProject] = []
            for r in arr {
                out.append(.init(
                    id: (r["id"] as? String) ?? "",
                    name: (r["name"] as? String) ?? "",
                    color: (r["color"] as? String) ?? "",
                    billable: (r["billable"] as? Bool) ?? false
                ))
            }
            self.projects = out
            self.log("Proyectos: \(out.count).")
            completion(true)
        }
    }

    private func loadTags(workspaceId: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string:
            "https://api.clockify.me/api/v1/workspaces/\(workspaceId)/tags?archived=false&page-size=200")
        else { completion(false); return }

        send(.get, url: url, body: nil) { [weak self] code, body in
            guard let self else { completion(false); return }
            if code != 200 {
                self.warn("GET tags exit=\(code)")
                self.tags = []
                completion(true)
                return
            }
            guard let data = body.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                self.tags = []
                completion(true)
                return
            }
            var out: [ClockifyTag] = []
            for r in arr {
                out.append(.init(id: (r["id"] as? String) ?? "", name: (r["name"] as? String) ?? ""))
            }
            self.tags = out
            self.log("Tags: \(out.count).")
            completion(true)
        }
    }

    private func processEntries(body: String) {
        guard let data = body.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            loading = false
            lastError = "Respuesta inválida de time-entries."
            return
        }
        var out: [ClockifyEntry] = []
        for e in arr {
            guard let ti = e["timeInterval"] as? [String: Any],
                  let startStr = ti["start"] as? String,
                  let endStr   = ti["end"]   as? String,
                  let startMs = Self.parseUtcIsoMs(startStr),
                  let endMs   = Self.parseUtcIsoMs(endStr),
                  endMs > startMs else { continue }
            let pid = (e["projectId"] as? String) ?? ""
            let p = projects.first { $0.id == pid }
            let tagIds = (e["tagIds"] as? [String]) ?? []
            let tagNames = tagIds.compactMap { id in tags.first { $0.id == id }?.name }
            out.append(.init(
                id: (e["id"] as? String) ?? "",
                startedMs: startMs,
                durationSec: Int(round((endMs - startMs) / 1000)),
                description: (e["description"] as? String) ?? "",
                projectId: pid,
                projectName: p?.name ?? "",
                projectColor: p?.color ?? "",
                tagIds: tagIds,
                tagNames: tagNames,
                billable: (e["billable"] as? Bool) ?? false
            ))
        }
        out.sort { $0.startedMs < $1.startedMs }
        entries = out
        lastFetchedAt = Date()
        loading = false
        log("Entries: \(out.count).")
    }

    // MARK: - HTTP plumbing

    private enum Method: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

    private func send(_ method: Method,
                      url: URL,
                      body: Data?,
                      completion: @escaping (Int, String) -> Void) {
        guard !apiKey.isEmpty else {
            warn("send abortado: no hay API key.")
            completion(0, "")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err {
                    self.warn("HTTP \(method.rawValue) error: \(err.localizedDescription)")
                    completion(0, "")
                    return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(code, text)
            }
        }.resume()
    }

    private func sendJson(_ method: Method,
                          url: URL,
                          body: [String: Any],
                          completion: @escaping (Int, String) -> Void) {
        let data = try? JSONSerialization.data(withJSONObject: body, options: [])
        send(method, url: url, body: data, completion: completion)
    }

    private func contextReady() -> Bool {
        let wid = settings.clockifyWorkspaceId
        let uid = settings.clockifyUserId
        if AppSettings.isValidObjectId(wid), AppSettings.isValidObjectId(uid) { return true }
        warn("workspace/user no resueltos todavía.")
        return false
    }

    // MARK: - Logging

    func clearDebugLog() { debugLog = "" }

    private func log(_ msg: String) {
        appendDebug(msg)
        if settings.debug { NSLog("[Clockify] %@", msg) }
    }
    private func warn(_ msg: String) {
        appendDebug("[!] " + msg)
        NSLog("[Clockify] %@", msg)
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

    // MARK: - Helpers estáticos

    /// "2026-05-12T15:00:00.000Z" — la docs de Clockify (y todos los
    /// ejemplos de su reference) incluyen los milisegundos.  Algunos
    /// endpoints rechazan la forma corta sin millis con HTTP 400, así
    /// que los emitimos siempre.
    static func utcIso(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f.string(from: d)
    }

    static func parseUtcIsoMs(_ s: String) -> Double? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
        ]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d.timeIntervalSince1970 * 1000 }
        }
        return nil
    }

    static func extractError(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return String(body.prefix(240)) }
        if let m = json["message"] as? String { return m }
        if let e = json["error"] as? String   { return e }
        if let e = json["error"]               { return "\(e)" }
        return String(body.prefix(240))
    }
}
