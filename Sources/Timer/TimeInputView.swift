import SwiftUI
import AppKit

struct TimeInputView: View {
    @Binding var totalSeconds: Int
    var isEditable: Bool = true
    var displaySeconds: Int? = nil
    /// Bumped by the parent to request that the minutes field become first responder.
    var focusMinutesToken: Int = 0

    @StateObject private var hoursCtl = TimeUnitController()
    @StateObject private var minutesCtl = TimeUnitController()
    @StateObject private var secondsCtl = TimeUnitController()

    // Fixed regardless of `isEditable` — a size that changed with state used to
    // change TimeInputView's intrinsic size, which made the popover resize (and
    // visibly jump) whenever the timer started/stopped.
    private var colonFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .regular)
    }

    var body: some View {
        HStack(spacing: 4) {
            unitColumn(.hours, controller: hoursCtl, left: nil, right: minutesCtl)
            colon
            unitColumn(.minutes, controller: minutesCtl, left: hoursCtl, right: secondsCtl)
            colon
            unitColumn(.seconds, controller: secondsCtl, left: minutesCtl, right: nil)
        }
        .onChange(of: focusMinutesToken) { _, _ in
            minutesCtl.view?.window?.makeFirstResponder(minutesCtl.view)
        }
    }

    private var colon: some View {
        Text(":")
            .font(Font(colonFont))
            .foregroundStyle(.tertiary)
    }

    private func unitColumn(
        _ unit: TimeUnitView.Unit,
        controller: TimeUnitController,
        left: TimeUnitController?,
        right: TimeUnitController?
    ) -> some View {
        // The chevrons and digit frame stay mounted at a fixed size in every state
        // (only their visibility/interactivity toggles) so this column's height
        // never depends on `isEditable` — see the note on `colonFont` above.
        VStack(spacing: 2) {
            Button {
                controller.view?.stepUp()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(isEditable ? 1 : 0)
            .allowsHitTesting(isEditable)

            TimeUnitInputView(
                totalSeconds: $totalSeconds,
                unit: unit,
                controller: controller,
                leftController: left,
                rightController: right,
                isEditable: isEditable,
                displaySeconds: displaySeconds
            )
            .frame(width: 40, height: 36)

            Button {
                controller.view?.stepDown()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(isEditable ? 1 : 0)
            .allowsHitTesting(isEditable)
        }
    }
}

final class TimeUnitController: ObservableObject {
    weak var view: TimeUnitView?
}

struct TimeUnitInputView: NSViewRepresentable {
    @Binding var totalSeconds: Int
    let unit: TimeUnitView.Unit
    let controller: TimeUnitController
    var leftController: TimeUnitController?
    var rightController: TimeUnitController?
    var isEditable: Bool = true
    var displaySeconds: Int? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $totalSeconds)
    }

    func makeNSView(context: Context) -> TimeUnitView {
        let view = TimeUnitView(unit: unit)
        view.totalSeconds = isEditable ? totalSeconds : (displaySeconds ?? totalSeconds)
        view.isInteractive = isEditable
        view.onChange = { [coordinator = context.coordinator] newValue in
            coordinator.binding.wrappedValue = newValue
        }
        controller.view = view
        return view
    }

    func updateNSView(_ nsView: TimeUnitView, context: Context) {
        context.coordinator.binding = $totalSeconds

        if nsView.isInteractive != isEditable {
            nsView.isInteractive = isEditable
            if !isEditable, nsView.window?.firstResponder === nsView {
                nsView.window?.makeFirstResponder(nil)
            }
        }

        let effectiveValue = isEditable ? totalSeconds : (displaySeconds ?? totalSeconds)
        if nsView.totalSeconds != effectiveValue {
            nsView.totalSeconds = effectiveValue
        }

        nsView.previousUnitView = leftController?.view
        nsView.nextUnitView = rightController?.view
    }

    final class Coordinator {
        var binding: Binding<Int>
        init(binding: Binding<Int>) { self.binding = binding }
    }
}

final class TimeUnitView: NSView {
    enum Unit {
        case hours, minutes, seconds

        var multiplier: Int {
            switch self {
            case .hours: return 3600
            case .minutes: return 60
            case .seconds: return 1
            }
        }

        var maxValue: Int {
            switch self {
            case .hours: return 23
            case .minutes, .seconds: return 59
            }
        }
    }

    let unit: Unit

    var totalSeconds: Int = 0 {
        didSet { needsDisplay = true }
    }
    var onChange: ((Int) -> Void)?

    var isInteractive: Bool = true {
        didSet { needsDisplay = true }
    }

    weak var previousUnitView: NSView?
    weak var nextUnitView: NSView?

    private var typedBuffer: String = ""
    private var scrollAccumulator: CGFloat = 0
    private var lastStepTimestamp: TimeInterval = 0
    private let minStepInterval: TimeInterval = 0.07

    // Fixed regardless of `isInteractive` — see the note in TimeInputView.unitColumn.
    private var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
    }

    init(unit: Unit) {
        self.unit = unit
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        self.unit = .seconds
        super.init(coder: coder)
        wantsLayer = true
    }

    override var acceptsFirstResponder: Bool { isInteractive }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        typedBuffer = ""
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 40, height: 36)
    }

    private var currentValue: Int {
        switch unit {
        case .hours: return totalSeconds / 3600
        case .minutes: return (totalSeconds % 3600) / 60
        case .seconds: return totalSeconds % 60
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let isFocused = isInteractive && window?.firstResponder === self
        let text = String(format: "%02d", currentValue)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: isFocused ? NSColor.white : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attrs)
        let rect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )

        if isInteractive {
            let hitRect = bounds.insetBy(dx: 1, dy: 1)
            if isFocused {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: hitRect, xRadius: 4, yRadius: 4).fill()
            } else {
                NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: hitRect, xRadius: 4, yRadius: 4).fill()
            }
        }

        text.draw(in: rect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard isInteractive else { return }

        if event.phase == .began {
            scrollAccumulator = 0
        }

        // Momentum is the trackpad "coasting" after the finger lifts — ignore it
        // so the value doesn't keep changing on its own after the gesture ends.
        guard event.momentumPhase == [] else { return }

        if event.hasPreciseScrollingDeltas {
            scrollAccumulator += event.scrollingDeltaY
            let threshold: CGFloat = 20
            if scrollAccumulator >= threshold, canStep(at: event.timestamp) {
                stepUp()
                scrollAccumulator -= threshold
            } else if scrollAccumulator <= -threshold, canStep(at: event.timestamp) {
                stepDown()
                scrollAccumulator += threshold
            }
        } else {
            // A physical mouse wheel can fire several events per notch — rate-limit
            // so one notch always yields exactly one step, regardless of magnitude.
            guard canStep(at: event.timestamp) else { return }
            if event.scrollingDeltaY > 0 {
                stepUp()
            } else if event.scrollingDeltaY < 0 {
                stepDown()
            }
        }
    }

    private func canStep(at timestamp: TimeInterval) -> Bool {
        guard timestamp - lastStepTimestamp >= minStepInterval else { return false }
        lastStepTimestamp = timestamp
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isInteractive else { return }

        switch event.keyCode {
        case 123: // left arrow
            if let previousUnitView { window?.makeFirstResponder(previousUnitView) }
        case 124: // right arrow
            if let nextUnitView { window?.makeFirstResponder(nextUnitView) }
        case 125: // down arrow
            stepDown()
        case 126: // up arrow
            stepUp()
        case 48: // tab
            let target = event.modifierFlags.contains(.shift) ? previousUnitView : nextUnitView
            if let target { window?.makeFirstResponder(target) }
        default:
            if let chars = event.charactersIgnoringModifiers, chars.count == 1, let digit = Int(chars) {
                handleDigit(digit)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private func handleDigit(_ digit: Int) {
        typedBuffer = typedBuffer.count >= 2 ? String(digit) : typedBuffer + String(digit)
        let typedValue = Int(typedBuffer) ?? digit
        setValue(min(typedValue, unit.maxValue))
        if typedBuffer.count == 2 {
            typedBuffer = ""
            if let nextUnitView { window?.makeFirstResponder(nextUnitView) }
        }
    }

    private func setValue(_ value: Int) {
        var h = totalSeconds / 3600
        var m = (totalSeconds % 3600) / 60
        var s = totalSeconds % 60
        switch unit {
        case .hours: h = value
        case .minutes: m = value
        case .seconds: s = value
        }
        let newTotal = h * 3600 + m * 60 + s
        totalSeconds = newTotal
        onChange?(newTotal)
    }

    func stepUp() { adjust(by: 1) }
    func stepDown() { adjust(by: -1) }

    private func adjust(by step: Int) {
        guard isInteractive else { return }
        let newTotal = max(0, min(86399, totalSeconds + step * unit.multiplier))
        totalSeconds = newTotal
        onChange?(newTotal)
    }
}
