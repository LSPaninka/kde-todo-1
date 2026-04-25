import Foundation
import Combine

/// Central data store. Mirrors `TaskStore.qml` from the KDE plasmoid.
///
/// Persistence: a single JSON file in
/// `~/Library/Application Support/CategorizedToDo/data.json`.
///
/// SwiftUI views observe the store via `@ObservedObject` and re-render when
/// `objectWillChange` fires (which happens after every mutation).
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published private(set) var tasks: [TodoTask] = []
    @Published private(set) var archived: [TodoTask] = []

    private var nextId: Int = 1

    private let fileURL: URL
    private let queue = DispatchQueue(label: "categorizedtodo.store.io")

    private init() {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory,
                                   in: .userDomainMask,
                                   appropriateFor: nil,
                                   create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("CategorizedToDo", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("data.json")
        load()
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var tasks: [TodoTask]
        var archived: [TodoTask]
        var nextId: Int
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try JSONDecoder().decode(Persisted.self, from: data)
            self.tasks = decoded.tasks
            self.archived = decoded.archived
            self.nextId = max(1, decoded.nextId)
        } catch {
            // Try legacy KDE format: { "tasksJson": "...", "archivedJson": "..." }
            // (best-effort; safe to ignore on failure)
            NSLog("CategorizedToDo: store load failed: \(error)")
        }
    }

    func save() {
        let snapshot = Persisted(tasks: tasks, archived: archived, nextId: nextId)
        let url = fileURL
        queue.async {
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try enc.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("CategorizedToDo: store save failed: \(error)")
            }
        }
    }

    private func mutate(_ block: () -> Void) {
        block()
        save()
        // Trigger SwiftUI updates explicitly — @Published handles most cases
        // but we sometimes mutate in place via index helpers.
        objectWillChange.send()
    }

    // MARK: - Queries

    func tasksFor(category index: Int) -> [TodoTask] {
        tasks.filter { $0.category == index }
    }

    func pendingCount(category index: Int) -> Int {
        tasks.reduce(0) { $0 + (($1.category == index && !$1.done) ? 1 : 0) }
    }

    var totalPending: Int {
        tasks.reduce(0) { $0 + ($1.done ? 0 : 1) }
    }

    // MARK: - Mutations: tasks

    @discardableResult
    func addTask(title: String,
                 category: Int,
                 priority: Priority = .m,
                 description: String = "") -> Int {
        let id = nextId; nextId += 1
        let t = TodoTask(id: id,
                         title: title,
                         description: description,
                         category: category,
                         priority: priority,
                         done: false,
                         createdAt: Date().timeIntervalSince1970 * 1000)
        mutate { tasks.append(t) }
        return id
    }

    func updateTask(id: Int,
                    title: String? = nil,
                    description: String? = nil,
                    category: Int? = nil,
                    priority: Priority? = nil) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate {
            if let v = title       { tasks[i].title = v }
            if let v = description { tasks[i].description = v }
            if let v = category    { tasks[i].category = v }
            if let v = priority    { tasks[i].priority = v }
        }
    }

    func toggleTaskDone(id: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate { tasks[i].done.toggle() }
    }

    func archiveTask(id: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate {
            var t = tasks.remove(at: i)
            t.archivedAt = Date().timeIntervalSince1970 * 1000
            t.done = true
            archived.insert(t, at: 0)
        }
    }

    func restoreArchived(id: Int) {
        guard let i = archived.firstIndex(where: { $0.id == id }) else { return }
        mutate {
            var t = archived.remove(at: i)
            t.archivedAt = 0
            t.done = false
            tasks.append(t)
        }
    }

    func deleteArchived(id: Int) {
        guard let i = archived.firstIndex(where: { $0.id == id }) else { return }
        mutate { archived.remove(at: i) }
    }

    func clearArchive() {
        mutate { archived.removeAll() }
    }

    // MARK: - Mutations: subtasks

    @discardableResult
    func addSubtask(taskId: Int, title: String, priority: Priority = .m) -> Int? {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return nil }
        let id = nextId; nextId += 1
        mutate {
            tasks[i].subtasks.append(Subtask(id: id, title: title, priority: priority))
        }
        return id
    }

    func updateSubtask(taskId: Int, subId: Int,
                       title: String? = nil,
                       priority: Priority? = nil) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        guard let j = tasks[i].subtasks.firstIndex(where: { $0.id == subId }) else { return }
        mutate {
            if let v = title    { tasks[i].subtasks[j].title = v }
            if let v = priority { tasks[i].subtasks[j].priority = v }
        }
    }

    func toggleSubtaskDone(taskId: Int, subId: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        guard let j = tasks[i].subtasks.firstIndex(where: { $0.id == subId }) else { return }
        mutate { tasks[i].subtasks[j].done.toggle() }
    }

    func removeSubtask(taskId: Int, subId: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        mutate { tasks[i].subtasks.removeAll { $0.id == subId } }
    }

    // MARK: - Import / Export

    private struct ExportPayload: Codable {
        let schema: String
        let exportedAt: Double
        let category: Int
        let tasks: [TodoTask]
    }

    func exportCategoryJson(_ category: Int) -> String {
        let payload = ExportPayload(
            schema: "categorizedtodo.v1",
            exportedAt: Date().timeIntervalSince1970 * 1000,
            category: category,
            tasks: tasks.filter { $0.category == category }
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: enc.encode(payload), encoding: .utf8)) ?? "[]"
    }

    @discardableResult
    func importCategoryJson(_ category: Int, jsonText: String) throws -> Int {
        guard let data = jsonText.data(using: .utf8) else {
            throw NSError(domain: "CategorizedToDo", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Texto vacío o codificación inválida"])
        }
        let decoder = JSONDecoder()
        var imported: [TodoTask] = []
        if let payload = try? decoder.decode(ExportPayload.self, from: data) {
            imported = payload.tasks
        } else if let arr = try? decoder.decode([TodoTask].self, from: data) {
            imported = arr
        } else {
            throw NSError(domain: "CategorizedToDo", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Estructura JSON no reconocida"])
        }
        var count = 0
        mutate {
            for var t in imported {
                t.id = nextId; nextId += 1
                t.category = category
                t.archivedAt = 0
                t.subtasks = t.subtasks.map { sub in
                    var s = sub; s.id = nextId; nextId += 1; return s
                }
                tasks.append(t)
                count += 1
            }
        }
        return count
    }

    // MARK: - Categories

    /// When the user lowers `categoryCount`, bring orphan tasks back to the
    /// last visible slot so they remain reachable.
    func reassignOutOfRange(newCount: Int) {
        guard newCount >= 1 else { return }
        mutate {
            for i in tasks.indices where tasks[i].category >= newCount {
                tasks[i].category = newCount - 1
            }
            for i in archived.indices where archived[i].category >= newCount {
                archived[i].category = newCount - 1
            }
        }
    }
}
