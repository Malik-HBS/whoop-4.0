import Foundation

actor WorkoutSessionStore {
    let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "workout-sessions-v1.json") {
        self.url = Self.defaultURL(filename: filename)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    static func defaultURL(filename: String = "workout-sessions-v1.json") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("OpenWhoop", isDirectory: true)
        return directory.appendingPathComponent(filename)
    }

    func load() -> [WorkoutSession] {
        guard let data = try? Data(contentsOf: url),
              let sessions = try? decoder.decode([WorkoutSession].self, from: data) else {
            return []
        }
        return sessions
    }

    func save(_ sessions: [WorkoutSession]) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
