import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var anchorWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let engine = TimerEngine()
    private let popoverActions = PopoverActions()
    private var engineObserver: AnyCancellable?
    private var trayDragController: TrayDragController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AlertSoundPlayer.shared.requestNotificationPermission()

        engine.onFinished = { AlertSoundPlayer.shared.fireAlert() }
        // objectWillChange fires before the new value lands; hop to the next runloop turn to read it.
        engineObserver = engine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateStatusTitle() }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem(item)
        statusItem = item
        trayDragController = TrayDragController(
            statusItem: item,
            engine: engine,
            onClick: { [weak self] in self?.togglePopover() }
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(
            rootView: TimerPopoverView(
                engine: engine,
                actions: popoverActions,
                onOpenSettings: { [weak self] in self?.openSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        self.popover = popover
    }

    private func configureStatusItem(_ item: NSStatusItem) {
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Таймер")
        // Icon on the right: the bar is right-aligned, so the title ("12:00") grows to the left
        // and the icon (and the popover anchored under it) stays put.
        button.imagePosition = .imageRight
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func makeRightClickMenu() -> NSMenu {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        switch engine.state {
        case .running, .paused:
            button.attributedTitle = Self.monospacedTitle(" \(engine.formattedRemaining)")
        default:
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    /// A monospaced-digit title so the status item's width stays constant tick to
    /// tick — a proportional font's digits shift slightly in width every second,
    /// which otherwise makes the tray icon (and anything anchored to it) jitter.
    private static func monospacedTitle(_ string: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        return NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ])
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showRightClickMenu()
        }
        // Left-click is handled by TrayDragController's onClick callback, since it
        // intercepts leftMouseDown to distinguish a plain click from a drag gesture.
    }

    private func showRightClickMenu() {
        guard let button = statusItem?.button else { return }
        popover?.performClose(nil)
        let menu = makeRightClickMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            // macOS 26 draws status items at positions that don't match the button window's frame,
            // so anchor to the icon's center (derived from the click) via a tiny invisible window.
            let anchor = makeAnchorWindow(atScreenX: trayDragController?.iconCenterScreenX ?? NSEvent.mouseLocation.x, y: button.window?.frame.minY ?? 0)
            popover.show(relativeTo: anchor.contentView!.bounds, of: anchor.contentView!, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            // Fired only after the popover's window is key, so makeFirstResponder
            // calls triggered by this (e.g. focusing the minutes field) actually land.
            popoverActions.onDidShow?()
        }
    }

    private func makeAnchorWindow(atScreenX x: CGFloat, y: CGFloat) -> NSWindow {
        let window = anchorWindow ?? {
            let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.level = .statusBar
            return w
        }()
        window.setFrame(NSRect(x: x - 10, y: y, width: 20, height: 1), display: false)
        window.orderFrontRegardless()
        anchorWindow = window
        return window
    }

    func popoverDidClose(_ notification: Notification) {
        anchorWindow?.orderOut(nil)
    }

    private func openSettings() {
        popover?.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Настройки"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
