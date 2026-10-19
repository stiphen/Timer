import SwiftUI
import AVFoundation

struct SettingsView: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var soundName = AppSettings.soundName
    @State private var volume = AppSettings.volume
    @State private var signalDuration = AppSettings.signalDuration
    @State private var shiftSnap = AppSettings.shiftSnap

    private let sounds = AppSettings.availableSounds()
    @State private var previewPlayer = PreviewPlayer()

    var body: some View {
        Form {
            Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.setEnabled(newValue)
                }

            Toggle("Shift при протяжке: шаг 5 минут (00, 05, 10…)", isOn: $shiftSnap)
                .onChange(of: shiftSnap) { _, newValue in
                    AppSettings.shiftSnap = newValue
                }

            Picker("Звук", selection: $soundName) {
                ForEach(sounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .onChange(of: soundName) { _, newValue in
                AppSettings.soundName = newValue
                previewPlayer.play(sound: newValue, volume: volume)
            }

            VStack(alignment: .leading) {
                Text("Громкость сигнала")
                Slider(value: $volume, in: 0...1) { editing in
                    if !editing {
                        AppSettings.volume = volume
                        previewPlayer.play(sound: soundName, volume: volume)
                    }
                }
            }

            VStack(alignment: .leading) {
                Text("Длительность сигнала: \(Int(signalDuration)) сек")
                Slider(value: $signalDuration, in: 1...60, step: 1) { editing in
                    if !editing {
                        AppSettings.signalDuration = signalDuration
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

final class PreviewPlayer {
    private var player: AVAudioPlayer?

    func play(sound: String, volume: Double) {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(sound).aiff")
        guard let audioPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        audioPlayer.volume = Float(volume)
        audioPlayer.prepareToPlay()
        audioPlayer.play()
        player = audioPlayer
    }
}
