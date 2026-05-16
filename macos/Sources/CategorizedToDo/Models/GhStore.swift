import Foundation
import Combine

/// Read-only client for GitHub Projects v2 via the GraphQL API.
///
/// Mirrors `GhStore.qml` from the KDE plasmoid: single `POST` to
/// `https://api.github.com/graphql` with a Bearer token, custom-fields
/// extraction (SingleSelect / Text / Number / Iteration), and a JSON cache
/// in Application Support.
final class GhStore: ObservableObject {
    static let shared = GhStore(settings: AppSettings.shared)

    // MARK: - Published state

    @Published private(set) var items: [GhItem] = []
    @Published private(set) var lastFetchedAt: Date? = nil
    @Published private(set) var isFetching: Bool = false
    @Published private(set) var lastError: String? = nil

    // MARK: - Private state

    private let settings: AppSettings
    private let cacheURL: URL
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let urlSession: URLSession

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
        self.cacheURL = dir.appendingPathComponent("gh-cache.json")

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 40
        self.urlSession = URLSession(configuration: cfg)

        loadCache()

        settings.$ghRefreshMinutes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyRefreshSchedule() }
            .store(in: &cancellables)

        settings.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                if mode == .gh && self.items.isEmpty { self.fetch() }
            }
            .store(in: &cancellables)

        applyRefreshSchedule()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Cache

    private struct CachePayload: Codable {
        var items: [GhItem]
        var lastFetchedAt: Date?
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let p = try? dec.decode(CachePayload.self, from: data) {
            items = p.items
            lastFetchedAt = p.lastFetchedAt
        }
    }

    private func saveCache() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(CachePayload(items: items, lastFetchedAt: lastFetchedAt)) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: - Auto-refresh

    func applyRefreshSchedule() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let minutes = settings.ghRefreshMinutes
        guard minutes > 0 else {
            log("auto-refresh disabled"); return
        }
        let t = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes) * 60,
                                     repeats: true) { [weak self] _ in
            self?.fetch()
        }
        refreshTimer = t
        RunLoop.main.add(t, forMode: .common)
        log("auto-refresh scheduled every \(minutes) min")
    }

    // MARK: - Queries

    func items(forCategory index: Int) -> [GhItem] {
        guard index >= 0, index < settings.ghCategoryFilterFields.count else { return [] }
        let field = settings.ghCategoryFilterFields[index]
        let value = settings.ghCategoryFilterValues.indices.contains(index)
            ? settings.ghCategoryFilterValues[index]
            : ""
        let base = settings.ghIncludeClosed
            ? items
            : items.filter { $0.state.uppercased() != "CLOSED" && $0.state.uppercased() != "MERGED" }
        return base.filter { $0.matches(field: field, value: value) }
    }

    func count(forCategory index: Int) -> Int { items(forCategory: index).count }

    // MARK: - GraphQL fetch

    /// Build a one-shot GraphQL request to fetch project items.
    private func graphQLBody() -> Data? {
        let ownerKind = settings.ghOwnerType.lowercased() == "organization"
            ? "organization" : "user"
        let query = """
        query($login: String!, $number: Int!, $first: Int!) {
          \(ownerKind)(login: $login) {
            projectV2(number: $number) {
              title
              items(first: $first) {
                totalCount
                nodes {
                  id
                  type
                  updatedAt
                  fieldValues(first: 20) {
                    nodes {
                      __typename
                      ... on ProjectV2ItemFieldSingleSelectValue {
                        name
                        optionId
                        field { ... on ProjectV2SingleSelectField { name } }
                      }
                      ... on ProjectV2ItemFieldTextValue {
                        text
                        field { ... on ProjectV2Field { name } }
                      }
                      ... on ProjectV2ItemFieldNumberValue {
                        number
                        field { ... on ProjectV2Field { name } }
                      }
                      ... on ProjectV2ItemFieldIterationValue {
                        title
                        field { ... on ProjectV2IterationField { name } }
                      }
                    }
                  }
                  content {
                    __typename
                    ... on DraftIssue { title body }
                    ... on Issue {
                      number title url state
                      repository { nameWithOwner }
                      labels(first: 20) { nodes { name color } }
                    }
                    ... on PullRequest {
                      number title url state isDraft
                      repository { nameWithOwner }
                      labels(first: 20) { nodes { name color } }
                    }
                  }
                }
              }
            }
          }
        }
        """
        let payload: [String: Any] = [
            "query": query,
            "variables": [
                "login": settings.ghOwner,
                "number": settings.ghProjectNumber,
                "first": settings.ghMaxResults
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    func fetch() {
        let token = settings.ghToken
        guard !token.isEmpty, !settings.ghOwner.isEmpty else {
            self.lastError = "Configurá owner, número de proyecto y token en Preferencias."
            return
        }
        guard let body = graphQLBody(), let url = URL(string: "https://api.github.com/graphql") else {
            self.lastError = "No pude armar la consulta GraphQL"
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("CategorizedToDo-macOS/1.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = body

        log("fetch start: POST https://api.github.com/graphql (owner=\(settings.ghOwner) #\(settings.ghProjectNumber))")
        let started = Date()
        DispatchQueue.main.async { self.isFetching = true; self.lastError = nil }

        urlSession.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                defer { self.isFetching = false }
                if let error = error {
                    self.lastError = "Error de red: \(error.localizedDescription)"
                    self.log("network error: \(error.localizedDescription)")
                    return
                }
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                guard let data = data else {
                    self.lastError = "Respuesta vacía (HTTP \(status))"; return
                }
                switch status {
                case 200:
                    do {
                        let parsed = try Self.parseGraphQLResponse(data: data,
                                                                   statusField: self.settings.ghStatusField)
                        self.items = parsed
                        self.lastFetchedAt = Date()
                        self.saveCache()
                        self.log("fetch ok in \(Int(Date().timeIntervalSince(started) * 1000))ms — \(parsed.count) item(s)")
                    } catch {
                        self.lastError = "GraphQL: \(error.localizedDescription)"
                        self.log("parse error: \(error)")
                    }
                case 401:
                    self.lastError = "Token rechazado (HTTP 401). Revisá los scopes."
                case 403:
                    self.lastError = "Sin permiso para leer este Project (HTTP 403). Faltan scopes 'project' / 'read:org'."
                default:
                    self.lastError = "HTTP \(status)"
                }
            }
        }.resume()
    }

    /// Validate a token against `GET https://api.github.com/user`.
    func testConnection(token: String,
                        completion: @escaping (Result<String, String>) -> Void) {
        guard !token.isEmpty,
              let url = URL(string: "https://api.github.com/user") else {
            completion(.failure("Token vacío")); return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("CategorizedToDo-macOS/1.0", forHTTPHeaderField: "User-Agent")

        urlSession.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error.localizedDescription)); return
                }
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                guard status == 200, let data = data else {
                    completion(.failure(status == 401 || status == 403
                                        ? "Credenciales inválidas (HTTP \(status))"
                                        : "HTTP \(status)"))
                    return
                }
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let login = obj["login"] as? String {
                    completion(.success(login))
                } else {
                    completion(.success("OK"))
                }
            }
        }.resume()
    }

    // MARK: - Parsing

    private static func parseGraphQLResponse(data: Data, statusField: String) throws -> [GhItem] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "GhStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Respuesta no JSON"])
        }
        if let errors = obj["errors"] as? [[String: Any]], !errors.isEmpty {
            let msg = errors.compactMap { $0["message"] as? String }.joined(separator: "; ")
            throw NSError(domain: "GhStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let data0 = (obj["data"] as? [String: Any]) ?? [:]
        let owner = (data0["user"] as? [String: Any]) ?? (data0["organization"] as? [String: Any]) ?? [:]
        let project = (owner["projectV2"] as? [String: Any]) ?? [:]
        let itemsBlock = (project["items"] as? [String: Any]) ?? [:]
        let nodes = (itemsBlock["nodes"] as? [[String: Any]]) ?? []

        let statusFieldLower = statusField.lowercased()

        return nodes.compactMap { node -> GhItem? in
            let id = (node["id"] as? String) ?? ""
            let rawType = (node["type"] as? String) ?? ""
            let updated = (node["updatedAt"] as? String) ?? ""
            let content = (node["content"] as? [String: Any]) ?? [:]
            let typeName = (content["__typename"] as? String) ?? rawType

            // Custom fields
            var statusName = ""
            var customFields: [String: String] = [:]
            if let fv = node["fieldValues"] as? [String: Any],
               let fvNodes = fv["nodes"] as? [[String: Any]] {
                for fnode in fvNodes {
                    let typename = (fnode["__typename"] as? String) ?? ""
                    let fieldName = ((fnode["field"] as? [String: Any])?["name"] as? String) ?? ""
                    if fieldName.isEmpty { continue }
                    var value = ""
                    switch typename {
                    case "ProjectV2ItemFieldSingleSelectValue":
                        value = (fnode["name"] as? String) ?? ""
                    case "ProjectV2ItemFieldTextValue":
                        value = (fnode["text"] as? String) ?? ""
                    case "ProjectV2ItemFieldNumberValue":
                        if let n = fnode["number"] as? Double { value = String(n) }
                    case "ProjectV2ItemFieldIterationValue":
                        value = (fnode["title"] as? String) ?? ""
                    default: continue
                    }
                    customFields[fieldName] = value
                    if fieldName.lowercased() == statusFieldLower {
                        statusName = value
                    }
                }
            }

            // Content union
            let title: String
            let number: Int
            let url: String
            let state: String
            let isDraft: Bool
            let repo: String
            let labels: [GhItem.GhLabel]

            switch typeName {
            case "DraftIssue":
                title = (content["title"] as? String) ?? ""
                number = 0
                url = ""
                state = "DRAFT"
                isDraft = true
                repo = ""
                labels = []
            case "Issue", "PullRequest":
                title = (content["title"] as? String) ?? ""
                number = (content["number"] as? Int) ?? 0
                url = (content["url"] as? String) ?? ""
                let rawState = (content["state"] as? String) ?? ""
                isDraft = (content["isDraft"] as? Bool) ?? false
                state = isDraft ? "DRAFT" : rawState.uppercased()
                repo = ((content["repository"] as? [String: Any])?["nameWithOwner"] as? String) ?? ""
                if let lb = content["labels"] as? [String: Any],
                   let lbNodes = lb["nodes"] as? [[String: Any]] {
                    labels = lbNodes.map {
                        GhItem.GhLabel(name: ($0["name"] as? String) ?? "",
                                       colorHex: "#" + (($0["color"] as? String) ?? "888888"))
                    }
                } else {
                    labels = []
                }
            default:
                return nil
            }

            return GhItem(id: id,
                          type: typeName,
                          title: title,
                          url: url,
                          number: number,
                          state: state,
                          isDraft: isDraft,
                          repo: repo,
                          updated: updated,
                          statusName: statusName,
                          labels: labels,
                          customFields: customFields)
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        guard settings.ghDebug else { return }
        NSLog("[GhStore] \(message)")
    }
}
