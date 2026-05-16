import Foundation
import Combine

/// Driver that delegates Notion auth and HTTP to the official `ntn` CLI.
///
/// The user runs `ntn login` once (or sets `NOTION_API_TOKEN` in their
/// environment). We invoke `ntn` via `/bin/sh -c '…'` and parse the JSON
/// stdout. No tokens are ever stored by this app.
///
/// Mirrors `NotionStore.qml` from the KDE plasmoid.
final class NotionStore: ObservableObject {
    static let shared = NotionStore(settings: AppSettings.shared)

    // MARK: - Published state

    @Published private(set) var pages: [NotionPage] = []
    @Published private(set) var lastFetchedAt: Date? = nil
    @Published private(set) var isFetching: Bool = false
    @Published private(set) var lastError: String? = nil

    // MARK: - Private state

    private let settings: AppSettings
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings

        settings.$notionRefreshMinutes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyRefreshSchedule() }
            .store(in: &cancellables)

        settings.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                if mode == .notion && self.pages.isEmpty { self.fetch() }
            }
            .store(in: &cancellables)

        applyRefreshSchedule()
    }

    deinit { refreshTimer?.invalidate() }

    // MARK: - Auto-refresh

    func applyRefreshSchedule() {
        refreshTimer?.invalidate(); refreshTimer = nil
        let minutes = settings.notionRefreshMinutes
        guard minutes > 0 else { log("auto-refresh disabled"); return }
        let t = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes) * 60,
                                     repeats: true) { [weak self] _ in self?.fetch() }
        refreshTimer = t
        RunLoop.main.add(t, forMode: .common)
        log("auto-refresh scheduled every \(minutes) min")
    }

    // MARK: - Public actions

    /// Run `ntn api v1/search` with the configured query, filter and limit.
    func fetch() {
        DispatchQueue.main.async { self.isFetching = true; self.lastError = nil }

        let body: [String: Any] = [
            "page_size": settings.notionMaxResults,
            "filter": ["property": "object", "value": settings.notionFilter],
            "query": settings.notionQuery
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyText = String(data: bodyData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isFetching = false
                self.lastError = "No pude serializar el body"
            }
            return
        }

        let command = "\(cliBinary()) api v1/search -X POST -d \(shellSingleQuote(bodyText))"
        runShell(command: command) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isFetching = false
                switch result {
                case .failure(let msg):
                    self.lastError = msg
                case .success(let stdout):
                    do {
                        self.pages = try Self.parseSearch(json: stdout)
                        self.lastFetchedAt = Date()
                        self.log("fetch ok: \(self.pages.count) page(s)")
                    } catch {
                        self.lastError = "Respuesta inesperada: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    /// PATCH a page's title. `ntn api v1/pages/<id> -X PATCH -d '{…}'`
    func updateTitle(pageId: String, newTitle: String,
                     completion: @escaping (Result<Void, String>) -> Void) {
        let body: [String: Any] = [
            "properties": [
                "title": [
                    "title": [
                        ["text": ["content": newTitle]]
                    ]
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let bodyText = String(data: data, encoding: .utf8) else {
            completion(.failure("body inválido")); return
        }
        let command = "\(cliBinary()) api v1/pages/\(pageId) -X PATCH -d \(shellSingleQuote(bodyText))"
        runShell(command: command) { result in
            DispatchQueue.main.async {
                switch result {
                case .success: completion(.success(()))
                case .failure(let msg): completion(.failure(msg))
                }
            }
        }
    }

    /// `ntn pages get <id>` → Markdown plaintext.
    func fetchContent(pageId: String,
                      completion: @escaping (Result<String, String>) -> Void) {
        let command = "\(cliBinary()) pages get \(shellSingleQuote(pageId))"
        runShell(command: command) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let s): completion(.success(s))
                case .failure(let m): completion(.failure(m))
                }
            }
        }
    }

    /// `ntn pages update <id> --content '<markdown>'`
    func updateContent(pageId: String, markdown: String,
                       completion: @escaping (Result<Void, String>) -> Void) {
        let command = "\(cliBinary()) pages update \(shellSingleQuote(pageId)) --content \(shellSingleQuote(markdown))"
        runShell(command: command) { result in
            DispatchQueue.main.async {
                switch result {
                case .success: completion(.success(()))
                case .failure(let m): completion(.failure(m))
                }
            }
        }
    }

    /// Lightweight diagnostic: run `ntn --version`.
    func testCli(completion: @escaping (Result<String, String>) -> Void) {
        let command = "\(cliBinary()) --version"
        runShell(command: command) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let s):
                    completion(.success(s.trimmingCharacters(in: .whitespacesAndNewlines)))
                case .failure(let m):
                    completion(.failure(m))
                }
            }
        }
    }

    // MARK: - Shell helpers

    /// Wrap a string in POSIX single quotes safely for `sh -c '…'`.
    private func shellSingleQuote(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Effective `ntn` invocation prefix (absolute path or bare name).
    private func cliBinary() -> String {
        let custom = settings.notionCliPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return shellSingleQuote(custom)
        }
        return "ntn"
    }

    /// Run a command via `/bin/sh -c …`, capturing stdout/stderr.
    private func runShell(command: String,
                          completion: @escaping (Result<String, String>) -> Void) {
        log("$ \(command)")
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin\" \(command)"]
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe
            do {
                try task.run()
            } catch {
                completion(.failure("No pude ejecutar /bin/sh: \(error.localizedDescription)"))
                return
            }
            task.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                completion(.success(stdout))
            } else {
                let msg: String
                let combined = (stdout + "\n" + stderr).lowercased()
                if task.terminationStatus == 127 || combined.contains("command not found") {
                    msg = "No encuentro `ntn` en el PATH. Instalalo con `npm install -g ntn` o configurá la ruta absoluta en Preferencias."
                } else if combined.contains("not logged in") {
                    msg = "`ntn` no tiene sesión iniciada. Corré `ntn login` en una terminal."
                } else if combined.contains("401") {
                    msg = "Token expirado. Corré `ntn login` de nuevo."
                } else {
                    msg = stderr.isEmpty
                        ? "exit \(task.terminationStatus): \(stdout.prefix(200))"
                        : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                completion(.failure(msg))
            }
        }
    }

    // MARK: - Parsing

    private static func parseSearch(json: String) throws -> [NotionPage] {
        guard let data = json.data(using: .utf8) else {
            throw NSError(domain: "NotionStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "stdout no es UTF-8"])
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "NotionStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "respuesta no es JSON"])
        }
        let results = (obj["results"] as? [[String: Any]]) ?? []
        return results.map { raw in
            let id = (raw["id"] as? String) ?? ""
            let url = (raw["url"] as? String) ?? ""
            let created = (raw["created_time"] as? String) ?? ""
            let edited = (raw["last_edited_time"] as? String) ?? ""
            let archived = (raw["archived"] as? Bool) ?? false
            let object = (raw["object"] as? String) ?? ""

            var parentType = ""
            if let parent = raw["parent"] as? [String: Any] {
                parentType = (parent["type"] as? String) ?? ""
            }

            var icon = ""
            if let i = raw["icon"] as? [String: Any] {
                if let emoji = i["emoji"] as? String { icon = emoji }
                else if let ext = i["external"] as? [String: Any],
                        let urlS = ext["url"] as? String { icon = urlS }
            }

            // Title can be found either as a top-level "title" array (for
            // databases) or as one of the "properties" of type "title" (for
            // pages).
            var title = "(sin título)"
            if let arr = raw["title"] as? [[String: Any]] {
                title = Self.plainText(richText: arr).ifEmpty(or: title)
            }
            if let props = raw["properties"] as? [String: Any] {
                for (_, v) in props {
                    if let vDict = v as? [String: Any],
                       (vDict["type"] as? String) == "title",
                       let arr = vDict["title"] as? [[String: Any]] {
                        let txt = Self.plainText(richText: arr)
                        if !txt.isEmpty { title = txt; break }
                    }
                }
            }

            return NotionPage(id: id, title: title, url: url,
                              createdTime: created, lastEditedTime: edited,
                              archived: archived, parentType: parentType,
                              object: object, icon: icon)
        }
    }

    private static func plainText(richText: [[String: Any]]) -> String {
        richText.compactMap { $0["plain_text"] as? String }.joined()
    }

    // MARK: - Logging

    private func log(_ message: String) {
        guard settings.notionDebug else { return }
        NSLog("[NotionStore] \(message)")
    }
}

private extension String {
    func ifEmpty(or other: String) -> String {
        isEmpty ? other : self
    }
}
