import Testing
@testable import Timer

@MainActor
struct TimerEngineTests {
    @Test func zeroDurationStaysIdle() {
        let engine = TimerEngine()
        engine.start(hours: 0, minutes: 0, seconds: 0)
        #expect(engine.state == .idle)
    }

    @Test func startRuns() {
        let engine = TimerEngine()
        engine.start(hours: 0, minutes: 1, seconds: 0)
        #expect(engine.state == .running)
        #expect(engine.remainingSeconds == 60)
    }

    @Test func pauseResumeKeepsRemaining() {
        let engine = TimerEngine()
        engine.start(hours: 0, minutes: 1, seconds: 0)
        engine.pause()
        #expect(engine.state == .paused)
        engine.resume()
        #expect(engine.state == .running)
        #expect(engine.remainingSeconds == 60)
    }

    @Test func adjustRunningAddsMinutes() {
        let engine = TimerEngine()
        engine.start(hours: 0, minutes: 1, seconds: 0)
        engine.adjustRemaining(byMinutes: 2)
        #expect(engine.remainingSeconds == 180)
    }

    @Test func adjustRunningToZeroFinishes() {
        let engine = TimerEngine()
        var finished = 0
        engine.onFinished = { finished += 1 }
        engine.start(hours: 0, minutes: 1, seconds: 0)
        engine.adjustRemaining(byMinutes: -5)
        #expect(engine.state == .finished)
        #expect(finished == 1)
    }

    @Test func adjustPausedToZeroFinishes() {
        let engine = TimerEngine()
        engine.start(hours: 0, minutes: 1, seconds: 0)
        engine.pause()
        engine.adjustRemaining(byMinutes: -1)
        #expect(engine.state == .finished)
    }

    @Test func adjustIsCappedAtOneDay() {
        let engine = TimerEngine()
        engine.start(hours: 23, minutes: 59, seconds: 0)
        engine.adjustRemaining(byMinutes: 100)
        #expect(engine.remainingSeconds == 86399)
    }

    @Test func resetReturnsToIdle() {
        let engine = TimerEngine()
        engine.start(hours: 0, minutes: 1, seconds: 0)
        engine.reset()
        #expect(engine.state == .idle)
        #expect(engine.remainingSeconds == 0)
    }

    @Test func formatsRemaining() {
        let engine = TimerEngine()
        engine.start(hours: 0, minutes: 1, seconds: 5)
        #expect(engine.formattedRemaining == "1:05")
        engine.start(hours: 1, minutes: 1, seconds: 1)
        #expect(engine.formattedRemaining == "1:01:01")
    }

    @Test func adjustBySecondsMovesRunningTimer() {
        let engine = TimerEngine()
        engine.start(hours: 0, minutes: 1, seconds: 0)
        engine.adjustRemaining(bySeconds: 30)
        #expect(engine.remainingSeconds == 90)
    }

    @Test func snapStepGoesToNextFiveMinuteMark() {
        #expect(snappedFiveMinuteStep(from: 0, direction: 1) == 300)
        #expect(snappedFiveMinuteStep(from: 738, direction: 1) == 900)   // 12:18 -> 15:00
        #expect(snappedFiveMinuteStep(from: 900, direction: 1) == 1200)  // already on a mark -> +5
    }

    @Test func snapStepGoesToPreviousFiveMinuteMark() {
        #expect(snappedFiveMinuteStep(from: 738, direction: -1) == 600)  // 12:18 -> 10:00
        #expect(snappedFiveMinuteStep(from: 900, direction: -1) == 600)
        #expect(snappedFiveMinuteStep(from: 120, direction: -1) == 0)
        #expect(snappedFiveMinuteStep(from: 0, direction: -1) == 0)
    }

    @Test func snapStepIsCappedAtOneDay() {
        #expect(snappedFiveMinuteStep(from: 86399, direction: 1) == 86399)
    }
}
