import Foundation

/// User-editable list of names and terms (one per line) at ~/.wisprlite/vocabulary.txt.
enum Vocabulary {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".wisprlite/vocabulary.txt")

    static func ensureFile() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "WisprLite\n".write(to: url, atomically: true, encoding: .utf8)
    }

    static func words() -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
