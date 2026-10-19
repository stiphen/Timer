import AppKit

/// Lets the user press-and-hold the tray icon, drag down/up, and wind the timer's
/// minutes up/down. Draws a line from the tray icon to the cursor while dragging.
@MainActor
final class TrayDragController {
    static let iconWidth: CGFloat = 21

    /// Pixels of cursor travel per +1/-1 minute step. Tune this constant to change sensitivity.
    private let pixelsPerMinuteStep: CGFloat = 15
    /// Total movement below this (in points) is still treated as a plain click, not a drag.
    private let clickMovementThreshold: CGFloat = 3

    private let statusItem: NSStatusItem
    private let engine: TimerEngine
    private let onClick: () -> Void

    private var mouseDownMonitor: Any?
    private var dragMonitor: Any?

    private var startScreenPoint: NSPoint = .zero
    /// Screen X of the icon's center, derived from where inside the icon the click landed.
    private(set) var iconCenterScreenX: CGFloat = 0
    /// Timer value when the drag began (remaining seconds; 0 while idle).
    private var baseSeconds: Int = 0
    /// Change applied so far relative to `baseSeconds`. While idle it is the length to start on release.
    private var deltaSeconds: Int = 0
    private var didExceedClickThreshold = false

    private var overlayWindow: NSWindow?
    private var lineView: DragLineView?

    init(statusItem: NSStatusItem, engine: TimerEngine, onClick: @escaping () -> Void) {
        self.statusItem = statusItem
        self.engine = engine
        self.onClick = onClick
        installMouseDownMonitor()
    }

    deinit {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
    }

    private func installMouseDownMonitor() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, let button = self.statusItem.button, event.window === button.window else {
                return event
            }
            // The icon is the rightmost 21pt of the button; the click's offset inside the button
            // gives the icon's center without relying on the window's screen frame.
            let clickX = button.convert(event.locationInWindow, from: nil).x
            self.iconCenterScreenX = NSEvent.mouseLocation.x + (button.bounds.width - Self.iconWidth / 2 - clickX)
            self.beginDrag()
            return nil
        }
    }

    private func beginDrag() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        startScreenPoint = NSEvent.mouseLocation
        switch engine.state {
        case .running, .paused: baseSeconds = engine.remainingSeconds
        case .idle, .finished: baseSeconds = 0
        }
        deltaSeconds = 0
        didExceedClickThreshold = false

        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseUp {
                self.endDrag()
            } else {
                self.updateDrag()
            }
            return nil
        }
    }

    private func updateDrag() {
        let current = NSEvent.mouseLocation
        let totalMovement = hypot(current.x - startScreenPoint.x, current.y - startScreenPoint.y)
        if totalMovement > clickMovementThreshold {
            didExceedClickThreshold = true
        }

        let deltaY = startScreenPoint.y - current.y
        let targetSteps = Int((deltaY / pixelsPerMinuteStep).rounded(.towardZero))
        let snap = AppSettings.shiftSnap && NSEvent.modifierFlags.contains(.shift)
        // The value is a pure function of the cursor position and Shift, so releasing Shift
        // immediately returns to the plain ±1 minute value.
        let newDelta = dragValue(steps: targetSteps, snap: snap) - baseSeconds
        if newDelta != deltaSeconds {
            switch engine.state {
            case .running, .paused: engine.adjustRemaining(bySeconds: newDelta - deltaSeconds)
            case .idle, .finished: break
            }
            deltaSeconds = newDelta
        }

        if didExceedClickThreshold {
            showOverlayIfNeeded()
            let fireTimeText: String? = currentFireDate().map { Self.fireTimeFormatter.string(from: $0) }
            lineView?.update(endPoint: current, minutes: Int((Double(deltaSeconds) / 60).rounded()), fireTimeText: fireTimeText)
        }
    }

    /// Timer value for the cursor being `steps` steps from the start: ±1 minute per step, or
    /// one jump to the next/previous 5-minute mark per step when snapping.
    private func dragValue(steps: Int, snap: Bool) -> Int {
        guard snap else { return max(0, min(86399, baseSeconds + steps * 60)) }
        var value = baseSeconds
        for _ in 0..<abs(steps) {
            value = snappedFiveMinuteStep(from: value, direction: steps > 0 ? 1 : -1)
        }
        return value
    }

    /// Момент, в который таймер сработает при текущем положении перетаскивания.
    private func currentFireDate() -> Date? {
        switch engine.state {
        case .running, .paused:
            guard engine.remainingSeconds > 0 else { return nil }
            return Date().addingTimeInterval(TimeInterval(engine.remainingSeconds))
        case .idle, .finished:
            guard deltaSeconds > 0 else { return nil }
            return Date().addingTimeInterval(TimeInterval(deltaSeconds))
        }
    }

    private static let fireTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func endDrag() {
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
        }
        hideOverlay()

        if !didExceedClickThreshold {
            onClick()
        } else if (engine.state == .idle || engine.state == .finished) && deltaSeconds > 0 {
            engine.start(hours: 0, minutes: 0, seconds: deltaSeconds)
        }
    }

    /// Where the line starts: under the icon at the menu bar's bottom edge. X is the icon's center,
    /// derived from the click, because on macOS 26 the status window's frame doesn't match where the icon is drawn.
    private func lineStartScreenPoint() -> NSPoint {
        let barBottom = statusItem.button?.window?.frame.minY ?? startScreenPoint.y
        return NSPoint(x: iconCenterScreenX, y: barBottom)
    }

    private func showOverlayIfNeeded() {
        guard overlayWindow == nil else { return }
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hasShadow = false

        let view = DragLineView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.screenOrigin = screen.frame.origin
        view.startPoint = lineStartScreenPoint()
        window.contentView = view

        window.orderFrontRegardless()
        overlayWindow = window
        lineView = view
    }

    private func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        lineView = nil
    }
}

/// Draws a line from the tray icon to the cursor, a handle at the cursor, and a "+N/-N мин" label
/// on a blurred rounded backdrop.
private final class DragLineView: NSView {
    private static let labelPadding = NSEdgeInsets(top: 1, left: 6, bottom: 4, right: 6)
    private static let lineSpacing: CGFloat = 3
    private static let cornerRadius: CGFloat = 8

    var screenOrigin: NSPoint = .zero
    var startPoint: NSPoint = .zero
    private var endPoint: NSPoint = .zero

    private let blur = NSVisualEffectView()
    private let labelContent = LabelContentView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Self.cornerRadius
        blur.layer?.cornerCurve = .continuous // iOS-style smoothed corners
        blur.layer?.masksToBounds = true
        blur.isHidden = true
        labelContent.isHidden = true
        addSubview(blur)
        addSubview(labelContent)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(endPoint: NSPoint, minutes: Int, fireTimeText: String?) {
        self.endPoint = endPoint
        needsDisplay = true
        layoutLabel(minutes: minutes, fireTimeText: fireTimeText)
    }

    private func layoutLabel(minutes: Int, fireTimeText: String?) {
        guard minutes != 0 else {
            blur.isHidden = true
            labelContent.isHidden = true
            return
        }

        var lines: [LabelContentView.Line] = [
            .init(text: String(format: "%+d мин", minutes), attributes: [
                .font: NSFont.boldSystemFont(ofSize: 15),
                .foregroundColor: NSColor.labelColor
            ])
        ]
        if let fireTimeText {
            lines.append(.init(text: "в \(fireTimeText)", attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }

        let textSize = LabelContentView.size(of: lines, spacing: Self.lineSpacing)
        let end = NSPoint(x: endPoint.x - screenOrigin.x, y: endPoint.y - screenOrigin.y)
        let pad = Self.labelPadding
        let boxSize = NSSize(width: textSize.width + pad.left + pad.right, height: textSize.height + pad.top + pad.bottom)
        let box = NSRect(x: end.x + 10 - pad.left, y: end.y - boxSize.height / 2, width: boxSize.width, height: boxSize.height)
        blur.frame = box
        // Not flipped: the bottom inset is the lower edge, so the text origin sits `bottom` above it.
        labelContent.frame = NSRect(x: box.minX + pad.left, y: box.minY + pad.bottom, width: textSize.width, height: textSize.height)
        labelContent.lines = lines
        labelContent.spacing = Self.lineSpacing
        labelContent.needsDisplay = true
        blur.isHidden = false
        labelContent.isHidden = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let start = NSPoint(x: startPoint.x - screenOrigin.x, y: startPoint.y - screenOrigin.y)
        let end = NSPoint(x: endPoint.x - screenOrigin.x, y: endPoint.y - screenOrigin.y)

        let line = NSBezierPath()
        line.move(to: start)
        line.line(to: end)
        line.lineWidth = 3
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        line.stroke()

        let handleRadius: CGFloat = 5
        let handleRect = NSRect(x: end.x - handleRadius, y: end.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: handleRect).fill()
    }
}

/// Draws the label's text lines, top to bottom.
private final class LabelContentView: NSView {
    struct Line {
        let text: String
        let attributes: [NSAttributedString.Key: Any]
    }

    var lines: [Line] = []
    var spacing: CGFloat = 0

    static func size(of lines: [Line], spacing: CGFloat) -> NSSize {
        let sizes = lines.map { $0.text.size(withAttributes: $0.attributes) }
        return NSSize(
            width: sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        var y = bounds.height
        for line in lines {
            let height = line.text.size(withAttributes: line.attributes).height
            y -= height
            line.text.draw(at: NSPoint(x: 0, y: y), withAttributes: line.attributes)
            y -= spacing
        }
    }
}
