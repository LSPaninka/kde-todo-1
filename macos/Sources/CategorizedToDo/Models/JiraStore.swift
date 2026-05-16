import Foundation
import Combine

/// Read-only client for Atlassian Jira Cloud, mirrors `JiraStore.qml`.
///
/// - Auth: HTTP Basic, base64(email:token).
/// - Endpoint: `GET /rest/api/3/search?jql=…&maxResults=…&fields=summary,status,priority,issuetype,parent,updated`.
/// - Cache: JSON file in Application Support.
/// - Auto-refresh: a Foundation Timer scheduled every `jiraRefreshMinutes`.
/// - Debug logs go to NSLog (visible via `log stream`).
final class JiraStore: ObservableObject {
    static let shared = JiraStore(settings: AppSettings.shared)

    // MARK: - Published state

    @Published private(set) var issues: [JiraIssue] = []
    @Published private(set) var lastFetchedAt: Date? = nil
    @Published private(set) var isFetching: Bool = false
    @Published private(set) var lastError: String? = nil

    // MARK: - Private state

    private let settings: AppSettings
    private let cacheURL: URL
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let urlSession: URLSession

    // MARK: - Init

    init(settings: AppSettings) {
        self.settings = settings

        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory,
                                   in: .userDomainMask,
                                   appropriateFor: nil,
                                   create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("CategorizedToDo", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheURL = dir.appendingPathComponent("jira-cache.json")

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: cfg)

        loadCache()

        // React to config changes that affect the auto-refresh schedule.
        settings.$jiraRefreshMinutes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyRefreshSchedule() }
            .store(in: &cancellables)

        // When entering Jira mode for the first time, kick off a fetch
        // if the cache is empty.
        settings.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                if mode == .jira && self.issues.isEmpty {
                    self.fetch()
                }
            }
            .store(in: &cancellables)

        applyRefreshSchedule()

        log("init: \(issues.count) cached issue(s); lastFetchedAt=\(lastFetchedAt.map(String.init(describing:)) ?? "never")")
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Cache file

    private struct CachePayload: Codable {
        var issues: [JiraIssue]
        var lastFetchedAt: Date?
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let payload = try? dec.decode(CachePayload.self, from: data) {
            self.issues = payload.issues
            self.lastFetchedAt = payload.lastFetchedAt
        }
    }

    private func saveCache() {
        let payload = CachePayload(issues: issues, lastFetchedAt: lastFetchedAt)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(payload) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: - Auto-refresh

    func applyRefreshSchedule() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let minutes = settings.jiraRefreshMinutes
        guard minutes > 0 else {
            log("auto-refresh disabled")
            return
        }
        let t = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes) * 60.0,
                                     repeats: true) { [weak self] _ in
            self?.fetch()
        }
        refreshTimer = t
        RunLoop.main.add(t, forMode: .common)
        log("auto-refresh scheduled every \(minutes) min")
    }

    // MARK: - Queries

    /// Issues that match category `index` (uses settings.jiraCategoryFilter*).
    func issues(forCategory index: Int) -> [JiraIssue] {
        guard index >= 0,
              index < settings.jiraCategoryFilterFields.count else {
            return []
        }
        let field = settings.jiraCategoryFilterFields[index]
        let value = settings.jiraCategoryFilterValues.indices.contains(index)
            ? settings.jiraCategoryFilterValues[index]
            : ""
        return issues.filter { $0.matches(field: field, value: value) }
    }

    func count(forCategory index: Int) -> Int {
        issues(forCategory: index).count
    }

    // MARK: - HTTP

    /// Build the search URL for the configured site / JQL / fields.
    ///
    /// As of mid-2025 Atlassian removed `/rest/api/3/search`; the supported
    /// replacement is `/rest/api/3/search/jql` (same auth, same query params,
    /// slightly different response shape — no `total`, plus `isLast` and
    /// `nextPageToken`).
    private func searchURL() -> URL? {
        var site = settings.jiraSite.trimmingCharacters(in: .whitespacesAndNewlines)
        while site.hasSuffix("/") { site.removeLast() }
        guard !site.isEmpty,
              var components = URLComponents(string: site + "/rest/api/3/search/jql") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "jql", value: settings.jiraJql),
            URLQueryItem(name: "maxResults", value: String(settings.jiraMaxResults)),
            URLQueryItem(name: "fields",
                         value: "summary,status,priority,issuetype,parent,updated")
        ]
        return components.url
    }

    /// Build a Basic auth header.
    private func authHeader(email: String? = nil, token: String? = nil) -> String? {
        let e = email ?? settings.jiraEmail
        let t = token ?? settings.jiraToken
        guard !e.isEmpty, !t.isEmpty else { return nil }
        let raw = "\(e):\(t)"
        guard let data = raw.data(using: .utf8) else { return nil }
        return "Basic " + data.base64EncodedString()
    }

    /// Issue a fetch. UI bindings show `isFetching` while running.
    func fetch() {
        guard let url = searchURL(), let auth = authHeader() else {
            self.lastError = "Configurá la URL del Jira, el email y el token en Preferencias."
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        log("fetch start: GET \(url.absoluteString)")
        let started = Date()
        DispatchQueue.main.async { self.isFetching = true; self.lastError = nil }

        urlSession.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                defer { self.isFetching = false }

                if let error = error {
                    self.lastError = "Error de red: \(error.localizedDescription)"
                    self.log("fetch network error: \(error.localizedDescription)")
                    return
                }
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0

                guard let data = data else {
                    self.lastError = "Respuesta vacía (HTTP \(status))"
                    return
                }

                switch status {
                case 200:
                    do {
                        let parsed = try Self.parseSearchResponse(data: data, site: self.settings.jiraSite)
                        self.issues = parsed.issues
                        self.lastFetchedAt = Date()
                        self.saveCache()
                        self.log("fetch ok in \(Int(Date().timeIntervalSince(started) * 1000))ms — \(parsed.issues.count) issue(s) (total in JQL: \(parsed.total))")
                        for it in parsed.issues {
                            let parentSuffix = it.parentKey.isEmpty ? "" : "  [↳ parent=\(it.parentKey)]"
                            self.log("- \(it.key) [\(it.issuetype)] (\(it.statusName) / \(it.statusCat)) {\(it.priority)} — \(it.summary)\(parentSuffix)")
                        }
                        for i in 0..<self.settings.jiraCategoryCount {
                            let n = self.count(forCategory: i)
                            let f = self.settings.jiraCategoryFilterFields[i]
                            let v = self.settings.jiraCategoryFilterValues.indices.contains(i)
                                ? self.settings.jiraCategoryFilterValues[i] : ""
                            self.log("category #\(i) '\(self.settings.jiraCategoryName(i))' [\(f.rawValue) = \(v)]: \(n) issue(s)")
                        }
                    } catch {
                        self.lastError = "Respuesta JSON inesperada: \(error.localizedDescription)"
                        self.log("parse error: \(error)")
                    }
                case 401, 403:
                    self.lastError = "Autenticación inválida (HTTP \(status)). Revisá email y token."
                    self.log("auth error: HTTP \(status)")
                case 400:
                    let msg = String(data: data, encoding: .utf8) ?? ""
                    self.lastError = "JQL inválido (HTTP 400): \(msg.prefix(200))"
                    self.log("HTTP 400: \(msg)")
                default:
                    self.lastError = "HTTP \(status)"
                    self.log("unexpected HTTP \(status)")
                }
            }
        }.resume()
    }

    /// Manual connection test. Calls `/rest/api/3/myself` with the supplied
    /// credentials and returns the parsed displayName (or an error string).
    func testConnection(site: String,
                        email: String,
                        token: String,
                        completion: @escaping (Result<String, String>) -> Void) {
        var trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed + "/rest/api/3/myself") else {
            completion(.failure("URL inválida"))
            return
        }
        guard let auth = authHeader(email: email, token: token) else {
            completion(.failure("Email o token vacíos"))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        urlSession.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error.localizedDescription))
                    return
                }
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                guard status == 200, let data = data else {
                    if status == 401 || status == 403 {
                        completion(.failure("Credenciales inválidas (HTTP \(status))"))
                    } else {
                        completion(.failure("HTTP \(status)"))
                    }
                    return
                }
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = obj["displayName"] as? String {
                    completion(.success(name))
                } else {
                    completion(.success("Conexión OK"))
                }
            }
        }.resume()
    }

    // MARK: - Parsing

    private struct SearchResult {
        let issues: [JiraIssue]
        let total: Int
    }

    private static func parseSearchResponse(data: Data, site: String) throws -> SearchResult {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "JiraStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no es JSON"])
        }
        let raws = (obj["issues"] as? [[String: Any]]) ?? []
        // The new `/search/jql` endpoint no longer returns `total`; fall back
        // to the page size. We don't follow `nextPageToken` for now.
        let total = (obj["total"] as? Int) ?? raws.count
        var trimmed = site.trimmingCharacters(in: .whitespaces)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }

        let parsed: [JiraIssue] = raws.map { raw in
            let key = (raw["key"] as? String) ?? ""
            let fields = (raw["fields"] as? [String: Any]) ?? [:]
            let summary = (fields["summary"] as? String) ?? ""

            // status
            var statusName = ""; var statusCat = ""; var statusColor = ""
            if let st = fields["status"] as? [String: Any] {
                statusName = (st["name"] as? String) ?? ""
                if let sc = st["statusCategory"] as? [String: Any] {
                    statusCat = ((sc["key"] as? String)
                                 ?? (sc["name"] as? String)
                                 ?? "").lowercased()
                    statusColor = (sc["colorName"] as? String) ?? ""
                }
            }

            var priority = ""
            if let p = fields["priority"] as? [String: Any] {
                priority = (p["name"] as? String) ?? ""
            }

            var issuetype = ""; var isSubtask = false
            if let it = fields["issuetype"] as? [String: Any] {
                issuetype = (it["name"] as? String) ?? ""
                isSubtask = (it["subtask"] as? Bool) ?? false
            }

            var parentKey = ""; var parentSummary = ""
            if let parent = fields["parent"] as? [String: Any] {
                parentKey = (parent["key"] as? String) ?? ""
                if let pf = parent["fields"] as? [String: Any] {
                    parentSummary = (pf["summary"] as? String) ?? ""
                }
            }

            let updated = (fields["updated"] as? String) ?? ""
            let url = trimmed + "/browse/" + key

            return JiraIssue(
                key: key,
                summary: summary,
                statusName: statusName,
                statusCat: statusCat,
                statusColor: statusColor,
                priority: priority,
                issuetype: issuetype,
                isSubtask: isSubtask,
                parentKey: parentKey,
                parentSummary: parentSummary,
                updated: updated,
                url: url
            )
        }
        return SearchResult(issues: parsed, total: total)
    }

    // MARK: - Logging

    private func log(_ message: String) {
        guard settings.jiraDebug else { return }
        NSLog("[JiraStore] \(message)")
    }
}
