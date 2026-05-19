import Foundation
import Combine
import AppKit

/// Cliente REST de Jira para worklogs.  Reproduce 1:1 lo que hacía el
/// store QML del plasmoide:
///
///   - `GET  /rest/api/3/myself` para resolver el `accountId` propio
///     (filtramos los worklogs por autor del lado nuestro porque la API
///     no acepta filtro de autor sobre `/issue/<key>/worklog`).
///   - `POST /rest/api/3/search/jql` con `fields=summary,worklog` (el
///     endpoint nuevo, tras la deprecación de `/search` en 2025).
///   - `POST|PUT|DELETE /rest/api/3/issue/<key>/worklog[/<id>]`.
final class JiraWorklogStore: ObservableObject {

    // MARK: - Estado observable

    @Published private(set) var worklogs: [JiraWorklog] = []
    @Published private(set) var assignableIssues: [JiraAssignableIssue] = []
    @Published private(set) var myAccountId: String = ""

    @Published private(set) var loading: Bool = false
    @Published var lastError: String = ""
    @Published private(set) var lastFetchedAt: Date? = nil

    @Published private(set) var debugLog: String = ""

    var settings: AppSettings

    init(settings: AppSettings) { self.settings = settings }

    // MARK: - API pública

    func fetchWeek(starting weekStart: Date) {
        if loading {
            log("[abort] ya hay un fetch en curso.")
            return
        }
        guard let creds = credentials() else { return }

        // Limites de la semana (Domingo 00:00 → siguiente Domingo 00:00).
        let weekStartMs = weekStart.timeIntervalSince1970 * 1000
        let weekEndMs   = weekStartMs + 7 * 86_400_000

        appendDebug("=== Worklog fetch \(timestamp()) ===")
        loading = true
        lastError = ""

        let runSearch: () -> Void = { [weak self] in
            self?.searchWorklogs(creds: creds, weekStartMs: weekStartMs, weekEndMs: weekEndMs)
        }

        if myAccountId.isEmpty {
            log("GET /rest/api/3/myself (cacheamos accountId)")
            let url = URL(string: creds.site + "/rest/api/3/myself")!
            send(.get, url: url, body: nil, creds: creds) { [weak self] code, body in
                guard let self else { return }
                if code != 200 {
                    self.loading = false
                    self.lastError = "No pude obtener el usuario actual (HTTP \(code))."
                    self.warn("myself exit=\(code): \(body.prefix(200))")
                    return
                }
                if let data = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["accountId"] as? String {
                    self.myAccountId = id
                    self.log("accountId = \(id)")
                    runSearch()
                } else {
                    self.loading = false
                    self.lastError = "Respuesta inválida de /myself."
                }
            }
        } else {
            runSearch()
        }
    }

    /// Cargar la lista de issues para el picker del modal "nuevo worklog".
    func fetchAssignableIssues(completion: @escaping (Result<Int, StringError>) -> Void) {
        guard let creds = credentials() else {
            completion(.failure(StringError(lastError)))
            return
        }
        let jql = settings.jiraIssueJql.trimmingCharacters(in: .whitespacesAndNewlines)
        let max = Swift.max(10, min(200, settings.jiraIssueMax))

        guard let url = jqlSearchURL(creds: creds,
                                     jql: jql,
                                     maxResults: max,
                                     fields: "summary,status,issuetype") else {
            completion(.failure(StringError("URL inválida del search.")))
            return
        }
        log("Picker GET \(url.absoluteString)")
        send(.get, url: url, body: nil, creds: creds) { [weak self] code, body in
            guard let self else { return }
            if code != 200 {
                self.warn("Picker exit=\(code): \(body.prefix(200))")
                completion(.failure(StringError("HTTP \(code) al listar issues.")))
                return
            }
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let issues = json["issues"] as? [[String: Any]] else {
                completion(.failure(StringError("Respuesta inválida del picker.")))
                return
            }
            var out: [JiraAssignableIssue] = []
            for r in issues {
                let key = (r["key"] as? String) ?? ""
                let f = (r["fields"] as? [String: Any]) ?? [:]
                let summary = (f["summary"] as? String) ?? ""
                let issuetype = ((f["issuetype"] as? [String: Any])?["name"] as? String) ?? ""
                let status = ((f["status"] as? [String: Any])?["name"] as? String) ?? ""
                out.append(.init(key: key, summary: summary, issuetype: issuetype, status: status))
            }
            self.assignableIssues = out
            self.log("Picker: \(out.count) issue(s).")
            completion(.success(out.count))
        }
    }

    // MARK: - Create / Update / Delete

    func createWorklog(issueKey: String,
                       started: Date,
                       durationSec: Int,
                       comment: String,
                       completion: @escaping (Result<String, StringError>) -> Void) {
        guard let creds = credentials() else {
            completion(.failure(StringError(lastError)))
            return
        }
        let escapedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        let url = URL(string: creds.site + "/rest/api/3/issue/\(escapedKey)/worklog")!
        var body: [String: Any] = [
            "started": Self.jiraStartedString(started),
            "timeSpentSeconds": durationSec
        ]
        if !comment.isEmpty { body["comment"] = Self.adfDoc(comment) }

        log("POST \(url.absoluteString) body=\(body)")
        sendJson(.post, url: url, body: body, creds: creds) { [weak self] code, body in
            guard let self else { return }
            if code == 200 || code == 201 {
                self.log("create OK.")
                completion(.success(""))
            } else {
                let msg = Self.extractError(body)
                self.warn("create exit=\(code): \(msg)")
                completion(.failure(StringError("HTTP \(code): \(msg)")))
            }
        }
    }

    func updateWorklog(issueKey: String,
                       worklogId: String,
                       started: Date,
                       durationSec: Int,
                       comment: String,
                       completion: @escaping (Result<String, StringError>) -> Void) {
        guard let creds = credentials() else {
            completion(.failure(StringError(lastError)))
            return
        }
        let escapedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        let escapedId  = worklogId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? worklogId
        let url = URL(string: creds.site + "/rest/api/3/issue/\(escapedKey)/worklog/\(escapedId)")!
        var body: [String: Any] = [
            "started": Self.jiraStartedString(started),
            "timeSpentSeconds": durationSec
        ]
        body["comment"] = Self.adfDoc(comment)

        log("PUT \(url.absoluteString) body=\(body)")
        sendJson(.put, url: url, body: body, creds: creds) { [weak self] code, body in
            guard let self else { return }
            if code == 200 {
                self.log("update OK.")
                completion(.success(""))
            } else {
                let msg = Self.extractError(body)
                self.warn("update exit=\(code): \(msg)")
                completion(.failure(StringError("HTTP \(code): \(msg)")))
            }
        }
    }

    func deleteWorklog(issueKey: String,
                       worklogId: String,
                       completion: @escaping (Result<String, StringError>) -> Void) {
        guard let creds = credentials() else {
            completion(.failure(StringError(lastError)))
            return
        }
        let escapedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        let escapedId  = worklogId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? worklogId
        let url = URL(string: creds.site + "/rest/api/3/issue/\(escapedKey)/worklog/\(escapedId)")!
        log("DELETE \(url.absoluteString)")
        send(.delete, url: url, body: nil, creds: creds) { [weak self] code, body in
            guard let self else { return }
            if code == 204 || code == 200 {
                self.log("delete OK.")
                completion(.success(""))
            } else {
                let msg = Self.extractError(body)
                self.warn("delete exit=\(code): \(msg)")
                completion(.failure(StringError("HTTP \(code): \(msg)")))
            }
        }
    }

    // MARK: - Probar conexión (para Settings)

    func testConnection(site: String,
                        email: String,
                        token: String,
                        completion: @escaping (Result<String, StringError>) -> Void) {
        let cleanSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard !cleanSite.isEmpty, !email.isEmpty, !token.isEmpty,
              let url = URL(string: cleanSite + "/rest/api/3/myself") else {
            completion(.failure(StringError("Completá los tres campos antes de probar.")))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Basic " + basicAuth(email: email, token: token), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err {
                    completion(.failure(StringError("Error de red: \(err.localizedDescription)")))
                    return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200, let data else {
                    completion(.failure(StringError("Credenciales rechazadas (HTTP \(code)).")))
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = json["displayName"] as? String {
                    completion(.success(name))
                } else {
                    completion(.success(email))
                }
            }
        }.resume()
    }

    // MARK: - Procesar la respuesta del search

    private func searchWorklogs(creds: Credentials, weekStartMs: Double, weekEndMs: Double) {
        let startDate = Date(timeIntervalSince1970: weekStartMs / 1000)
        let endDate   = Date(timeIntervalSince1970: (weekEndMs - 1) / 1000)
        let startJql = Self.jqlDate(startDate)
        let endJql   = Self.jqlDate(endDate)
        let jql = "worklogAuthor = currentUser() AND worklogDate >= \"\(startJql)\" AND worklogDate <= \"\(endJql)\""

        guard let url = jqlSearchURL(creds: creds,
                                     jql: jql,
                                     maxResults: 200,
                                     fields: "summary,worklog") else {
            loading = false
            lastError = "URL inválida del search."
            return
        }
        log("GET \(url.absoluteString)")
        send(.get, url: url, body: nil, creds: creds) { [weak self] code, body in
            guard let self else { return }
            if code != 200 {
                self.loading = false
                self.lastError = "HTTP \(code) al buscar issues con worklogs."
                self.warn("Search exit=\(code): \(body.prefix(300))")
                return
            }
            self.processWeek(body: body, weekStartMs: weekStartMs, weekEndMs: weekEndMs)
        }
    }

    private func processWeek(body: String, weekStartMs: Double, weekEndMs: Double) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let issues = json["issues"] as? [[String: Any]] else {
            loading = false
            lastError = "Respuesta inválida del search."
            warn("parse error")
            return
        }
        var out: [JiraWorklog] = []
        for iss in issues {
            let issueId  = "\(iss["id"] ?? "")"
            let issueKey = (iss["key"] as? String) ?? ""
            let fields = (iss["fields"] as? [String: Any]) ?? [:]
            let summary = (fields["summary"] as? String) ?? ""
            let wlContainer = (fields["worklog"] as? [String: Any]) ?? [:]
            let wls = (wlContainer["worklogs"] as? [[String: Any]]) ?? []
            for w in wls {
                guard let started = w["started"] as? String,
                      let ms = Self.parseJiraDateMs(started),
                      ms >= weekStartMs, ms < weekEndMs else { continue }
                if !myAccountId.isEmpty,
                   let author = w["author"] as? [String: Any],
                   let aid = author["accountId"] as? String,
                   aid != myAccountId { continue }
                let id = "\(w["id"] ?? "")"
                let dur = (w["timeSpentSeconds"] as? Int) ?? 0
                let comment = Self.extractAdfText(w["comment"])
                out.append(.init(
                    id: id, issueId: issueId, issueKey: issueKey,
                    issueSummary: summary, startedMs: ms,
                    durationSec: dur, comment: comment
                ))
            }
        }
        out.sort { $0.startedMs < $1.startedMs }
        worklogs = out
        lastFetchedAt = Date()
        loading = false
        log("Recibí \(issues.count) issue(s); filtré a \(out.count) worklog(s) propios en la semana.")
    }

    // MARK: - HTTP plumbing

    private struct Credentials {
        let site: String   // sin trailing slash
        let email: String
        let token: String
    }

    private func credentials() -> Credentials? {
        let site = settings.jiraSite
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let email = settings.jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.jiraToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if site.isEmpty || email.isEmpty || token.isEmpty {
            lastError = "Faltan credenciales (sitio, email o token). Configurá la pestaña Jira."
            warn("Faltan credenciales: site=\(!site.isEmpty) email=\(!email.isEmpty) token=\(!token.isEmpty)")
            return nil
        }
        return Credentials(site: site, email: email, token: token)
    }

    private func jqlSearchURL(creds: Credentials, jql: String, maxResults: Int, fields: String) -> URL? {
        guard let encoded = jql.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let s = creds.site + "/rest/api/3/search/jql?jql=\(encoded)&maxResults=\(maxResults)&fields=\(fields)"
        return URL(string: s)
    }

    private enum Method: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

    private func send(_ method: Method,
                      url: URL,
                      body: Data?,
                      creds: Credentials,
                      completion: @escaping (Int, String) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("Basic " + basicAuth(email: creds.email, token: creds.token),
                     forHTTPHeaderField: "Authorization")
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
                          creds: Credentials,
                          completion: @escaping (Int, String) -> Void) {
        let data = try? JSONSerialization.data(withJSONObject: body, options: [])
        send(method, url: url, body: data, creds: creds, completion: completion)
    }

    private func basicAuth(email: String, token: String) -> String {
        return Data("\(email):\(token)".utf8).base64EncodedString()
    }

    // MARK: - Logging

    func clearDebugLog() {
        debugLog = ""
    }

    private func log(_ msg: String) {
        appendDebug(msg)
        if settings.debug { NSLog("[JiraWorklog] %@", msg) }
    }
    private func warn(_ msg: String) {
        appendDebug("[!] " + msg)
        NSLog("[JiraWorklog] %@", msg)
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

    /// "2026-05-12" para usar dentro de las comillas del JQL.
    static func jqlDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// "2026-05-12T15:00:00.000+0000" con timezone local (formato exacto
    /// que pide la REST API de Jira en el campo `started`).
    static func jiraStartedString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZ"   // ZZZ = +0000
        return f.string(from: d)
    }

    static func parseJiraDateMs(_ s: String) -> Double? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXX"
        ]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: s) {
                return d.timeIntervalSince1970 * 1000
            }
        }
        return nil
    }

    /// Wrapper ADF mínimo de un comentario plain text.
    static func adfDoc(_ text: String) -> [String: Any] {
        return [
            "type": "doc",
            "version": 1,
            "content": [[
                "type": "paragraph",
                "content": [["type": "text", "text": text]]
            ]]
        ]
    }

    /// Recorre un árbol ADF y concatena cada nodo `text`.  Suficiente
    /// para mostrar como plain text los comentarios que enviamos.
    static func extractAdfText(_ raw: Any?) -> String {
        guard let raw else { return "" }
        if let s = raw as? String { return s }
        guard let dict = raw as? [String: Any] else { return "" }
        let type = (dict["type"] as? String) ?? ""
        if type == "text" { return (dict["text"] as? String) ?? "" }
        if type == "paragraph" {
            let inner = (dict["content"] as? [Any]) ?? []
            let txt = inner.map { extractAdfText($0) }.joined()
            return txt + "\n"
        }
        if let content = dict["content"] as? [Any] {
            return content.map { extractAdfText($0) }.joined()
        }
        return ""
    }

    static func extractError(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return String(body.prefix(240)) }
        if let arr = json["errorMessages"] as? [String], !arr.isEmpty {
            return arr.joined(separator: "; ")
        }
        if let errs = json["errors"] as? [String: String], !errs.isEmpty {
            return errs.map { "\($0): \($1)" }.joined(separator: "; ")
        }
        if let msg = json["message"] as? String { return msg }
        return String(body.prefix(240))
    }
}
