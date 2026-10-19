import SwiftUI

/// Мост AppDelegate → SwiftUI: struct-view нельзя дёргать напрямую снаружи,
/// поэтому AppDelegate вызывает `onDidShow?()` (после того как попап реально
/// показан и его окно стало key), который TimerPopoverView регистрирует в
/// .onAppear.
final class PopoverActions: ObservableObject {
    var onDidShow: (() -> Void)?
}

struct TimerPopoverView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var actions: PopoverActions
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    @State private var totalSeconds: Int = AppSettings.lastTotalSeconds
    @State private var focusMinutesToken: Int = 0

    private var isEditable: Bool {
        engine.state == .idle || engine.state == .finished
    }

    /// Fills the slot under the buttons, so the popover keeps one height in every state.
    private var statusLine: String {
        switch engine.state {
        case .idle, .finished:
            return "клик — ввод с клавиатуры, скролл/стрелки — изменить"
        case .running:
            let end = Date().addingTimeInterval(TimeInterval(engine.remainingSeconds))
            return "Сработает в \(end.formatted(date: .omitted, time: .shortened))"
        case .paused:
            return "На паузе"
        }
    }

    private func togglePauseResume() {
        switch engine.state {
        case .running: engine.pause()
        case .paused: engine.resume()
        case .idle, .finished: break
        }
    }

    private func resetTimer() {
        AlertSoundPlayer.shared.stop()
        engine.reset()
        focusMinutesToken += 1
    }

    var body: some View {
        VStack(spacing: 12) {
            TimeInputView(
                totalSeconds: $totalSeconds,
                isEditable: isEditable,
                displaySeconds: isEditable ? nil : engine.remainingSeconds,
                focusMinutesToken: focusMinutesToken
            )
            .padding(.top, 8)

            HStack(spacing: 10) {
                switch engine.state {
                case .idle, .finished:
                    Button("Старт") {
                        AlertSoundPlayer.shared.stop()
                        AppSettings.lastTotalSeconds = totalSeconds
                        engine.start(
                            hours: totalSeconds / 3600,
                            minutes: (totalSeconds % 3600) / 60,
                            seconds: totalSeconds % 60
                        )
                    }
                    .keyboardShortcut(.defaultAction)
                    if engine.state == .finished {
                        Button("Сброс (C)") { resetTimer() }
                            .keyboardShortcut("c", modifiers: [])
                    }
                case .running:
                    Button("Пауза (H)") { engine.pause() }
                        .keyboardShortcut("h", modifiers: [])
                        .fixedSize()
                    Button("Сброс (C)") { resetTimer() }
                        .keyboardShortcut("c", modifiers: [])
                case .paused:
                    Button("Продолжить (H)") { engine.resume() }
                        .keyboardShortcut("h", modifiers: [])
                        .fixedSize()
                    Button("Сброс (C)") { resetTimer() }
                        .keyboardShortcut("c", modifiers: [])
                }
            }

            Text(statusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Кириллические дубли тех же хоткеев (физически те же клавиши H/C),
            // чтобы работало и при русской раскладке — keyEquivalent матчится по
            // символу, а не по коду клавиши. Всегда смонтированы (а не только в
            // running/paused), чтобы не менять число дочерних view в VStack —
            // иначе высота попапа скачет при смене состояния таймера.
            Button("") { togglePauseResume() }
                .keyboardShortcut("р", modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
            Button("") { resetTimer() }
                .keyboardShortcut("с", modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)

            Divider()

            HStack {
                Button("Настройки…") { onOpenSettings() }
                Spacer()
                Button("Выход") { onQuit() }
            }
        }
        .padding(14)
        .frame(width: 240)
        .onAppear {
            actions.onDidShow = {
                if isEditable { focusMinutesToken += 1 }
            }
        }
    }
}
