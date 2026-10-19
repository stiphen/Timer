import Foundation
import Combine

/// The next (direction > 0) or previous (direction < 0) multiple of 5 minutes strictly beyond `seconds`,
/// clamped to 0...86399. Used for Shift-snapped drag steps.
func snappedFiveMinuteStep(from seconds: Int, direction: Int) -> Int {
    let grid = 300
    let remainder = seconds % grid
    let snapped = direction > 0 ? seconds - remainder + grid : (remainder == 0 ? seconds - grid : seconds - remainder)
    return max(0, min(86399, snapped))
}

enum TimerState {
    case idle
    case running
    case paused
    case finished
}

@MainActor
final class TimerEngine: ObservableObject {
    @Published private(set) var state: TimerState = .idle
    @Published private(set) var remainingSeconds: Int = 0

    private var endDate: Date?
    private var pausedRemaining: Int = 0
    private var tickTimer: Foundation.Timer?

    var onFinished: (() -> Void)?

    func start(hours: Int, minutes: Int, seconds: Int) {
        let total = hours * 3600 + minutes * 60 + seconds
        guard total > 0 else { return }
        remainingSeconds = total
        endDate = Date().addingTimeInterval(TimeInterval(total))
        state = .running
        scheduleTick()
    }

    func pause() {
        guard state == .running, let endDate else { return }
        pausedRemaining = max(0, Int(endDate.timeIntervalSinceNow.rounded()))
        state = .paused
        tickTimer?.invalidate()
        tickTimer = nil
    }

    func resume() {
        guard state == .paused else { return }
        endDate = Date().addingTimeInterval(TimeInterval(pausedRemaining))
        state = .running
        scheduleTick()
    }

    func adjustRemaining(byMinutes delta: Int) {
        adjustRemaining(bySeconds: delta * 60)
    }

    func adjustRemaining(bySeconds delta: Int) {
        switch state {
        case .running:
            guard let endDate else { return }
            let newRemaining = max(0, min(86399, Int(endDate.timeIntervalSinceNow.rounded()) + delta))
            self.endDate = Date().addingTimeInterval(TimeInterval(newRemaining))
            remainingSeconds = newRemaining
            if newRemaining == 0 { finish() }
        case .paused:
            pausedRemaining = max(0, min(86399, pausedRemaining + delta))
            remainingSeconds = pausedRemaining
            if pausedRemaining == 0 { finish() }
        case .idle, .finished:
            break
        }
    }

    func reset() {
        tickTimer?.invalidate()
        tickTimer = nil
        endDate = nil
        remainingSeconds = 0
        pausedRemaining = 0
        state = .idle
    }

    private func scheduleTick() {
        tickTimer?.invalidate()
        let timer = Foundation.Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        tick()
    }

    private func tick() {
        guard let endDate else { return }
        let remaining = Int(endDate.timeIntervalSinceNow.rounded())
        if remaining <= 0 {
            finish()
        } else {
            remainingSeconds = remaining
        }
    }

    private func finish() {
        remainingSeconds = 0
        pausedRemaining = 0
        tickTimer?.invalidate()
        tickTimer = nil
        state = .finished
        onFinished?()
    }

    var formattedRemaining: String {
        let h = remainingSeconds / 3600
        let m = (remainingSeconds % 3600) / 60
        let s = remainingSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
