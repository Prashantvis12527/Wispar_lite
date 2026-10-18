import AppKit

/// Feedback sounds when listening starts and ends. Change the names to any file in /System/Library/Sounds
/// (Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink).
enum Sounds {
    static let start = NSSound(named: "Bottle")
    static let stop = NSSound(named: "Blow")

    static func play(_ sound: NSSound?) {
        sound?.volume = 0.5
        sound?.stop()
        sound?.play()
    }
}
