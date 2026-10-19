import Foundation

enum AppSettings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let soundName = "soundName"
        static let volume = "volume"
        static let signalDuration = "signalDuration"
        static let lastTotalSeconds = "lastTotalSeconds"
        static let shiftSnap = "shiftSnap"
    }

    static var soundName: String {
        get {
            // Only accept names that exist in the system sounds dir (the value is used in a file path).
            guard let name = defaults.string(forKey: Key.soundName), availableSounds().contains(name) else { return "Glass" }
            return name
        }
        set { defaults.set(newValue, forKey: Key.soundName) }
    }

    static var volume: Double {
        get {
            defaults.object(forKey: Key.volume) == nil ? 0.8 : defaults.double(forKey: Key.volume)
        }
        set { defaults.set(newValue, forKey: Key.volume) }
    }

    static var signalDuration: Double {
        get {
            defaults.object(forKey: Key.signalDuration) == nil ? 5.0 : defaults.double(forKey: Key.signalDuration)
        }
        set { defaults.set(newValue, forKey: Key.signalDuration) }
    }

    static var lastTotalSeconds: Int {
        get {
            defaults.object(forKey: Key.lastTotalSeconds) == nil ? 300 : defaults.integer(forKey: Key.lastTotalSeconds)
        }
        set { defaults.set(newValue, forKey: Key.lastTotalSeconds) }
    }

    /// Holding Shift while dragging the tray icon steps by 5 minutes, snapped to :00 :05 :10 ...
    static var shiftSnap: Bool {
        get { defaults.object(forKey: Key.shiftSnap) == nil ? true : defaults.bool(forKey: Key.shiftSnap) }
        set { defaults.set(newValue, forKey: Key.shiftSnap) }
    }

    static func availableSounds() -> [String] {
        let fm = FileManager.default
        let path = "/System/Library/Sounds"
        guard let files = try? fm.contentsOfDirectory(atPath: path) else { return ["Glass"] }
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }
}
