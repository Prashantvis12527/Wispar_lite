import Foundation

/// One finished dictation. `text` is empty when the user turned off "Save dictation text" (stats still count).
struct Session: Codable {
    let date: Date
    let text: String
    let words: Int
    let seconds: Double
}

/// Append-only log at ~/.wisprlite/history.jsonl, one JSON object per line.
/// Nothing is held in memory while idle; the file is read only when the window is open.
enum History {
    static var saveText: Bool {
        get { UserDefaults.standard.object(forKey: "saveHistoryText") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "saveHistoryText") }
    }

    static let url: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".wisprlite")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("history.jsonl")
    }()

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    static func add(text: String, seconds: Double) {
        let session = Session(date: Date(), text: saveText ? text : "", words: wordCount(text), seconds: seconds)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard var line = try? encoder.encode(session) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line); try? h.close()
        } else {
            try? line.write(to: url)
        }
    }

    /// Oldest first.
    static func load() -> [Session] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Session.self, from: Data($0)) }
    }

    /// Removes one dictation (it also stops counting towards stats) by rewriting the file without it.
    static func delete(date: Date) {
        let kept = load().filter { $0.date != date }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var data = Data()
        for s in kept {
            guard let line = try? encoder.encode(s) else { continue }
            data.append(line); data.append(0x0A)
        }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Numbers shown on the Insights tab.
struct Stats {
    let totalWords: Int
    let wpm: Int
    let todayWords: Int
    let weekWords: Int
    let currentStreak: Int
    let longestStreak: Int
    let wordsPerDay: [Date: Int]     // keyed by start of day
    let streakDays: Set<Date>        // the days making up the current streak

    init(_ sessions: [Session], calendar cal: Calendar = .current) {
        var perDay: [Date: Int] = [:]
        var words = 0, speechWords = 0
        var speechSeconds = 0.0
        for s in sessions {
            words += s.words
            perDay[cal.startOfDay(for: s.date), default: 0] += s.words
            // Very short clips give noisy rates, so they don't count towards speed.
            if s.seconds >= 2 && s.words >= 3 { speechWords += s.words; speechSeconds += s.seconds }
        }
        totalWords = words
        wpm = speechSeconds > 0 ? Int((Double(speechWords) / (speechSeconds / 60)).rounded()) : 0
        wordsPerDay = perDay

        let today = cal.startOfDay(for: Date())
        todayWords = perDay[today] ?? 0
        let weekAgo = cal.date(byAdding: .day, value: -6, to: today) ?? today
        weekWords = perDay.filter { $0.key >= weekAgo }.values.reduce(0, +)

        // A streak is still alive if you haven't dictated yet today but did yesterday.
        var day = perDay[today] != nil ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        var current = Set<Date>()
        while perDay[day] != nil {
            current.insert(day)
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        streakDays = current
        currentStreak = current.count

        var longest = 0, run = 0
        var last: Date?
        for d in perDay.keys.sorted() {
            if let l = last, cal.date(byAdding: .day, value: 1, to: l) == d { run += 1 } else { run = 1 }
            longest = max(longest, run)
            last = d
        }
        longestStreak = longest
    }
}
