import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// main.swift's top-level code is not main-actor isolated; this init touches no isolated state.
    nonisolated override init() { super.init() }

    private var model: HeadphonesModel?
    private var settings: AppSettings?
    private var menuBar: MenuBarController?
    private var demoObserver: NSObjectProtocol?
    private var connectVolume: ConnectVolume?
    private var volumeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.echoToConsole = CommandLine.arguments.contains("--verbose")
        let startInDemo = CommandLine.arguments.contains("--demo")
        Log.info("XM4 Connect starting\(startInDemo ? " (demo)" : "")")

        let settings = AppSettings()
        let session: HeadphonesControlling = startInDemo ? DemoSession() : HeadphonesSession()
        let model = HeadphonesModel(session: session, isDemo: startInDemo)
        self.settings = settings
        self.model = model
        let connectVolume = ConnectVolume(settings: settings)
        connectVolume.start()
        self.connectVolume = connectVolume
        menuBar = MenuBarController(model: model, settings: settings)
        volumeObserver = NotificationCenter.default.addObserver(
            forName: .applyConnectVolume, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.connectVolume?.applyNow() }
        }

        demoObserver = NotificationCenter.default.addObserver(
            forName: .toggleDemo, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.toggleDemo() }
        }

        model.start()

        if startInDemo || CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.menuBar?.showPanel()
            }
        }
    }

    private func toggleDemo() {
        guard let model else { return }
        if model.isDemo {
            model.switchTo(HeadphonesSession(), isDemo: false)
        } else {
            model.switchTo(DemoSession(), isDemo: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }
}
