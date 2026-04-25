import Foundation

struct Subtask: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var priority: Priority
    var done: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, priority, done
    }

    init(id: Int, title: String, priority: Priority = .m, done: Bool = false) {
        self.id = id
        self.title = title
        self.priority = priority
        self.done = done
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        let raw = (try? c.decode(String.self, forKey: .priority)) ?? "M"
        self.priority = Priority(rawValue: raw) ?? .m
        self.done = (try? c.decode(Bool.self, forKey: .done)) ?? false
    }
}

struct TodoTask: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var description: String
    var category: Int
    var priority: Priority
    var done: Bool
    var createdAt: TimeInterval
    var archivedAt: TimeInterval
    var subtasks: [Subtask]

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, priority, done, createdAt, archivedAt, subtasks
    }

    init(id: Int,
         title: String,
         description: String = "",
         category: Int = 0,
         priority: Priority = .m,
         done: Bool = false,
         createdAt: TimeInterval = Date().timeIntervalSince1970 * 1000,
         archivedAt: TimeInterval = 0,
         subtasks: [Subtask] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.priority = priority
        self.done = done
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.subtasks = subtasks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.description = (try? c.decode(String.self, forKey: .description)) ?? ""
        self.category = (try? c.decode(Int.self, forKey: .category)) ?? 0
        let raw = (try? c.decode(String.self, forKey: .priority)) ?? "M"
        self.priority = Priority(rawValue: raw) ?? .m
        self.done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        self.createdAt = (try? c.decode(TimeInterval.self, forKey: .createdAt)) ?? Date().timeIntervalSince1970 * 1000
        self.archivedAt = (try? c.decode(TimeInterval.self, forKey: .archivedAt)) ?? 0
        self.subtasks = (try? c.decode([Subtask].self, forKey: .subtasks)) ?? []
    }

    var pendingSubtasks: Int {
        subtasks.reduce(0) { $0 + ($1.done ? 0 : 1) }
    }
}
