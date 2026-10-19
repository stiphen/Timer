import Foundation
import AVFoundation
import UserNotifications

@MainActor
final class AlertSoundPlayer {
    static let shared = AlertSoundPlayer()

    private var player: AVAudioPlayer?
    private var stopTimer: Foundation.Timer?

    // UNUserNotificationCenter raises outside an app bundle (e.g. `swift run`).
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func fireAlert() {
        playSound()
        postNotification()
    }

    private func playSound() {
        stopTimer?.invalidate()
        player?.stop()

        let name = AppSettings.soundName
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        guard let audioPlayer = try? AVAudioPlayer(contentsOf: url) else { return }

        audioPlayer.volume = Float(AppSettings.volume)
        audioPlayer.numberOfLoops = -1
        audioPlayer.prepareToPlay()
        audioPlayer.play()
        player = audioPlayer

        let duration = max(1.0, AppSettings.signalDuration)
        let timer = Foundation.Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.player?.stop()
                self?.player = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        stopTimer = timer
    }

    private func postNotification() {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = "Таймер завершён"
        content.body = "Заданное время истекло"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func stop() {
        stopTimer?.invalidate()
        stopTimer = nil
        player?.stop()
        player = nil
    }
}
