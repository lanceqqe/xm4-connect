import Foundation
import SonyProtocolKit

/// A simulated WH-1000XM4. It answers every command the way the real headset does (by sending
/// the matching notification back), so the interface can be explored without headphones.
@MainActor
final class DemoSession: HeadphonesControlling {
    var onStateChanged: ((SessionState) -> Void)?
    var onDeviceEvent: ((DeviceEvent) -> Void)?
    var onCapabilities: ((DeviceCapabilities) -> Void)?

    private var task: Task<Void, Never>?
    private var stopped = false
    private var battery = 82
    private var preset: EqPreset = .off
    private var speakToChatConfig = SpeakToChatConfig(sensitivity: .auto, voiceFocus: false, timeout: .standard)
    private var optimizerRun: Task<Void, Never>?
    private var customBands: [EqPreset: (Int, [Int])] = [
        .manual: (0, [0, 0, 0, 0, 0]),
        .custom1: (3, [2, 0, -1, 1, 3]),
        .custom2: (-2, [-1, 1, 3, 2, 0]),
    ]

    /// Curves shaped like Sony's presets, for show.
    private static let presetCurves: [EqPreset: (Int, [Int])] = [
        .off: (0, [0, 0, 0, 0, 0]),
        .bright: (0, [-1, 0, 2, 4, 5]),
        .excited: (3, [2, 0, 1, 3, 4]),
        .mellow: (1, [1, 0, -1, -2, -4]),
        .relaxed: (0, [1, 0, -2, -3, -3]),
        .vocal: (-2, [-1, 3, 4, 2, -1]),
        .trebleBoost: (0, [0, 0, 1, 4, 7]),
        .bassBoost: (6, [4, 1, 0, 0, 0]),
        .speech: (-4, [-3, 3, 5, 3, -2]),
    ]

    func start() {
        guard task == nil else { return }
        stopped = false
        task = Task { [weak self] in
            guard let self else { return }
            self.onStateChanged?(.connecting)
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }

            var caps = DeviceCapabilities(
                ncVariant: .dualSeamless, hasNcMode: true, batteries: [.single],
                hasEq: true, hasPowerOff: true, deviceName: "WH-1000XM4")
            caps.hasSpeakToChat = true
            caps.hasAutoPause = true
            caps.hasDsee = true
            caps.autoPowerOffWearingDetection = true
            caps.hasAutoPowerOff15Minutes = false
            caps.hasWindMode = true
            caps.hasSpeakToChatConfig = true
            caps.hasCustomButton = true
            caps.hasVoiceGuidance = true
            caps.hasSoundQualityPriority = true
            caps.hasNcOptimizer = true
            caps.hasDeviceInfo = true
            self.onCapabilities?(caps)
            self.onStateChanged?(.ready)

            self.emit(.ncAmb(mode: .noiseCancelling, ambientLevel: 14, focusOnVoice: false))
            self.emit(.eqStatus(available: true))
            self.emitEq()
            self.emit(.battery(level: self.battery, charging: .notCharging))
            self.emit(.speakToChat(enabled: false))
            self.emit(.autoPause(enabled: true))
            self.emit(.dsee(enabled: true))
            self.emit(.autoPowerOff(.whenTakenOff, wearingDetection: true))
            self.emit(.speakToChatConfig(self.speakToChatConfig))
            self.emit(.customButton(.ambientSoundControl))
            self.emit(.voiceGuidance(enabled: true))
            self.emit(.soundQualityPriority(true))
            self.emit(.ncOptimizerPressure(1.0))
            self.emit(.codec(.ldac))
            self.emit(.firmware("2.5.0"))

            // The battery drains slowly so the ring has something to do.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled else { return }
                self.battery = max(5, self.battery - 1)
                self.emit(.battery(level: self.battery, charging: .notCharging))
            }
        }
    }

    func stop() {
        stopped = true
        task?.cancel()
        task = nil
        onStateChanged?(.disconnected)
    }

    func refresh() async throws {}

    func setNcAmb(mode: NcAmbMode, ambientLevel: Int, focusOnVoice: Bool) async throws {
        await reply(.ncAmb(mode: mode, ambientLevel: ambientLevel, focusOnVoice: focusOnVoice))
    }

    func setEqPreset(_ preset: EqPreset) async throws {
        self.preset = preset
        try? await Task.sleep(nanoseconds: 120_000_000)
        emitEq()
    }

    func setEqBands(preset: EqPreset, clearBass: Int, bands: [Int]) async throws {
        customBands[preset] = (clearBass, bands)
        await reply(.eq(preset: preset, clearBass: clearBass, bands: bands))
    }

    func setEqBands10(preset: EqPreset, bands: [Int]) async throws {}

    func powerOff() async throws {
        try? await Task.sleep(nanoseconds: 300_000_000)
        task?.cancel()
        task = nil
        onStateChanged?(.disconnected)
        // Back on after a moment, like pressing the power button again.
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        if !stopped { start() }
    }

    func setSpeakToChat(_ enabled: Bool) async throws { await reply(.speakToChat(enabled: enabled)) }
    func setAutoPause(_ enabled: Bool) async throws { await reply(.autoPause(enabled: enabled)) }
    func setDsee(_ enabled: Bool) async throws { await reply(.dsee(enabled: enabled)) }
    func setAutoPowerOff(_ value: AutoPowerOff) async throws {
        await reply(.autoPowerOff(value, wearingDetection: true))
    }
    func setSpeakToChatConfig(_ config: SpeakToChatConfig) async throws {
        speakToChatConfig = config
        await reply(.speakToChatConfig(config))
    }
    func setCustomButton(_ function: CustomButtonFunction) async throws { await reply(.customButton(function)) }
    func setVoiceGuidance(_ enabled: Bool) async throws { await reply(.voiceGuidance(enabled: enabled)) }
    func setSoundQualityPriority(_ quality: Bool) async throws {
        await reply(.soundQualityPriority(quality))
        await reply(.codec(quality ? .ldac : .aac))
    }

    /// Walks through the same steps the real headset reports.
    func runNcOptimizer(_ start: Bool) async throws {
        optimizerRun?.cancel()
        guard start else { return await reply(.ncOptimizerStatus(.notRunning)) }
        optimizerRun = Task { [weak self] in
            for status: NcOptimizerStatus in [.checkingWearing, .measuringPressure, .analyzing, .finished] {
                self?.emit(.ncOptimizerStatus(status))
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
            }
            self?.emit(.ncOptimizerPressure(1.0))
            self?.emit(.ncOptimizerStatus(.notRunning))
        }
    }

    private func reply(_ event: DeviceEvent) async {
        try? await Task.sleep(nanoseconds: 60_000_000)
        emit(event)
    }

    private func emitEq() {
        let curve = customBands[preset] ?? Self.presetCurves[preset] ?? (0, [0, 0, 0, 0, 0])
        emit(.eq(preset: preset, clearBass: curve.0, bands: curve.1))
    }

    private func emit(_ event: DeviceEvent) {
        onDeviceEvent?(event)
    }
}
