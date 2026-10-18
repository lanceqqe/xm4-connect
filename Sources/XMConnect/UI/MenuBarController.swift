import AppKit
import Combine
import SwiftUI
import SonyProtocolKit

/// A borderless panel that can take key focus (for Escape) without activating the app.
private final class FloatingPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Owns the status item and the drop-down glass panel.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: FloatingPanel
    private let model: HeadphonesModel
    private let settings: AppSettings
    private let state = PanelState()
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?
    private var hideWork: DispatchWorkItem?

    init(model: HeadphonesModel, settings: AppSettings) {
        self.model = model
        self.settings = settings

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: Theme.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()

        configurePanel()
        configureStatusItem()
        observeModel()
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onEscape = { [weak self] in self?.hidePanel() }

        // Blur behind the window, clipped to the panel's rounded shape.
        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: Theme.panelHeight))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.roundedMask(radius: Theme.corner)
        blur.autoresizingMask = [.width, .height]

        let root = PanelView(model: model, settings: settings, state: state,
                             onQuit: { NSApp.terminate(nil) })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        panel.contentView = blur
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshStatusItem()
    }

    private func observeModel() {
        model.objectWillChange
            .merge(with: settings.objectWillChange)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self, self.panel.isVisible else { return }
                self.positionPanel()
            }
            .store(in: &cancellables)
    }

    // MARK: - Status item

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if !model.isConnected {
            symbol = "headphones"
        } else {
            switch model.mode {
            case .noiseCancelling: symbol = "headphones.circle.fill"
            case .ambient: symbol = "headphones.circle"
            case .off: symbol = "headphones"
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "XM Connect")
            ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: "XM Connect")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !model.isConnected

        if settings.showBatteryInMenuBar, model.isConnected, let level = model.batteryLevel {
            button.title = " \(level) %"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            button.title = ""
        }

        let modeName = ListeningLook(mode: model.mode, connected: model.isConnected).title
        button.toolTip = model.isConnected
            ? "XM Connect — \(model.displayName)\n\(modeName) · \(L("Battery", "Batterie")) \(model.batteryText)"
            : "XM Connect — \(model.statusText)"
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        if model.isConnected && model.hasNoiseControls {
            var modes: [(NcAmbMode, String)] = []
            if model.hasNcChip { modes.append((NcAmbMode.noiseCancelling, L("Noise cancelling", "Réduction de bruit"))) }
            modes.append((NcAmbMode.ambient, L("Ambient sound", "Son ambiant")))
            modes.append((NcAmbMode.off, L("Off", "Désactivé")))
            for (mode, title) in modes {
                let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
                item.target = self
                item.state = model.mode == mode ? .on : .off
                item.representedObject = mode == .noiseCancelling ? 0 : (mode == .ambient ? 1 : 2)
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let demo = NSMenuItem(title: model.isDemo ? L("Use the real headphones", "Utiliser le vrai casque") : L("Demo mode", "Mode démo"),
                              action: #selector(toggleDemo), keyEquivalent: "")
        demo.target = self
        menu.addItem(demo)
        let login = NSMenuItem(title: L("Open at login", "Ouvrir au démarrage"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = settings.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("Quit XM Connect", "Quitter XM Connect"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // keep left-click for the panel
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        model.mode = [NcAmbMode.noiseCancelling, .ambient, .off][index]
    }

    @objc private func toggleDemo() {
        NotificationCenter.default.post(name: .auraToggleDemo, object: nil)
    }

    @objc private func toggleLaunchAtLogin() { settings.launchAtLogin.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Panel

    func togglePanel() {
        if panel.isVisible && state.isVisible { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        hideWork?.cancel()
        positionPanel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.highlight(true)
        // Let the window appear first so SwiftUI animates the content in.
        DispatchQueue.main.async { self.state.isVisible = true }

        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.hidePanel() }
            }
        }
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        state.isVisible = false
        statusItem.button?.highlight(false)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.isVisible else { return }
            self.panel.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func positionPanel() {
        guard let buttonWindow = statusItem.button?.window else { return }
        let anchor = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.midX - Theme.panelWidth / 2
        x = min(max(x, visible.minX + 8), visible.maxX - Theme.panelWidth - 8)
        let y = anchor.minY - Theme.panelHeight - 6
        panel.setFrame(NSRect(x: x, y: max(y, visible.minY + 8),
                              width: Theme.panelWidth, height: Theme.panelHeight), display: true)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
