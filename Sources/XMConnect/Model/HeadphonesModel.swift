import Combine
import Foundation
import SonyProtocolKit

/// One equalizer slider: label, allowed range, and current value (user scale).
struct BandModel: Identifiable, Equatable {
    let id: Int
    let label: String
    let minimum: Double
    let maximum: Double
    var value: Double
}

/// The app's single source of truth. Same contract as sony-tray's view model (MIT), which it is
/// adapted from: the UI applies a change immediately, sends it, and if the command fails it
/// re-queries the headset so the UI never shows a state the headset is not in.
///
/// The model stores states, not sentences: every label is produced on demand with `L(…)`, so
/// switching language updates everything at once.
@MainActor
final class HeadphonesModel: ObservableObject {
    private static let sixBandLayout: [(String, Double, Double)] = [
        ("Clear Bass", -10, 10), ("400", -10, 10), ("1k", -10, 10),
        ("2.5k", -10, 10), ("6.3k", -10, 10), ("16k", -10, 10),
    ]

    private static let tenBandLayout: [(String, Double, Double)] = [
        ("31", -6, 6), ("63", -6, 6), ("125", -6, 6), ("250", -6, 6), ("500", -6, 6),
        ("1k", -6, 6), ("2k", -6, 6), ("4k", -6, 6), ("8k", -6, 6), ("16k", -6, 6),
    ]

    static let knownPresets: [EqPreset] = [
        .off, .bright, .excited, .mellow, .relaxed, .vocal, .trebleBoost, .bassBoost, .speech,
        .manual, .custom1, .custom2,
    ]

    private static let timerChoices: [AutoPowerOff] = [
        .after5Minutes, .after15Minutes, .after30Minutes, .after60Minutes, .after180Minutes, .never,
    ]

    private let defaults = UserDefaults.standard
    private var session: HeadphonesControlling
    private var suppressSend = false // true while applying device state to the UI
    private var ambientDebounce: Task<Void, Never>?
    private var bandsDebounce: Task<Void, Never>?
    private var pendingNoiseEdit: UUID?
    private var pendingBandsEdit: UUID?
    private var pendingPresetEdit: (id: UUID, preset: EqPreset)?
    private var isTenBandEq = false
    private var nextBandID = 0
    private var capabilities: DeviceCapabilities?
    @Published private var commandFailed = false
    /// True when this app paused playback because the headset came off.
    private var pausedByRemoval = false

    // MARK: Connection

    @Published private(set) var connection: SessionState = .connecting
    @Published private(set) var deviceName = "WH-1000XM4"
    @Published private(set) var isDemo = false
    var isConnected: Bool { connection == .ready }
    var isConnecting: Bool { connection == .connecting }

    // MARK: Battery

    @Published private(set) var batteryLevel: Int?
    @Published private(set) var isCharging = false

    // MARK: Wearing

    @Published private(set) var wearing: WearingState = .unknown

    // MARK: Capabilities (shown until the headset says otherwise)

    @Published private(set) var hasNcChip = true
    @Published private(set) var hasNoiseControls = true
    @Published private(set) var hasEqSection = true
    @Published private(set) var powerOffVisible = true
    @Published private(set) var eqAvailable = true
    @Published private(set) var hasEqBandData = false
    @Published private(set) var hasSpeakToChat = false
    /// The headset itself has a "pause when taken off" setting.
    @Published private(set) var hasHeadsetAutoPause = false
    /// The headset reports when it is put on or taken off.
    @Published private(set) var hasWearingStatus = false
    @Published private(set) var hasDsee = false
    @Published private(set) var hasAutoPowerOff = false
    @Published private(set) var presets: [EqPreset] = HeadphonesModel.knownPresets
    @Published private(set) var autoPowerOffChoices: [AutoPowerOff] = HeadphonesModel.timerChoices

    var showsAutoPause: Bool { hasHeadsetAutoPause || hasWearingStatus }

    // WH-1000XM4 extras
    @Published private(set) var hasWindMode = false
    @Published private(set) var hasSpeakToChatConfig = false
    @Published private(set) var hasCustomButton = false
    @Published private(set) var hasVoiceGuidance = false
    @Published private(set) var hasSoundQualityPriority = false
    @Published private(set) var hasNcOptimizer = false
    @Published private(set) var hasDeviceInfo = false

    /// The listening modes this headset offers, in the order the NC/AMB button cycles them.
    var availableModes: [NcAmbMode] {
        var modes: [NcAmbMode] = []
        if hasNcChip { modes.append(.noiseCancelling) }
        if hasWindMode { modes.append(.windNoiseReduction) }
        modes.append(.ambient)
        modes.append(.off)
        return modes
    }

    // MARK: Noise control

    @Published var mode: NcAmbMode = .noiseCancelling {
        didSet {
            guard oldValue != mode else { return }
            if !suppressSend { scheduleMode(delay: 0) }
        }
    }

    @Published var ambientLevel: Double = 15 {
        didSet {
            guard oldValue != ambientLevel else { return }
            if !suppressSend { scheduleMode(delay: 250_000_000) }
        }
    }

    @Published var focusOnVoice = false {
        didSet {
            guard oldValue != focusOnVoice else { return }
            if !suppressSend { scheduleMode(delay: 0) }
        }
    }

    // MARK: Equalizer

    @Published var selectedPreset: EqPreset = .off {
        didSet {
            guard oldValue != selectedPreset else { return }
            bandsDebounce?.cancel() // a preset switch supersedes any pending band edit
            bandsDebounce = nil
            pendingBandsEdit = nil
            if !suppressSend {
                // A preset's curve must be read before it is edited, or an edit could write the
                // previous preset's values back.
                hasEqBandData = false
                let preset = selectedPreset
                let edit = UUID()
                pendingPresetEdit = (edit, preset)
                push({ try await self.session.setEqPreset(preset) }, onComplete: {
                    if self.pendingPresetEdit?.id == edit { self.pendingPresetEdit = nil }
                })
            }
        }
    }

    @Published var bands: [BandModel] = [] {
        didSet {
            guard oldValue.map(\.value) != bands.map(\.value) else { return }
            if !suppressSend { debounceBands() }
        }
    }

    // MARK: Options

    @Published var speakToChat = false {
        didSet {
            guard oldValue != speakToChat, !suppressSend else { return }
            let value = speakToChat
            push { try await self.session.setSpeakToChat(value) }
        }
    }

    /// Pause when the headset is taken off. Sent to the headset when it has the setting, and
    /// also applied by this app from the wearing sensor, so it works either way.
    @Published var autoPause = true {
        didSet {
            guard oldValue != autoPause else { return }
            defaults.set(autoPause, forKey: "pauseOnRemoval")
            guard !suppressSend, hasHeadsetAutoPause else { return }
            let value = autoPause
            push { try await self.session.setAutoPause(value) }
        }
    }

    /// Resume playback when the headset goes back on (only if this app paused it).
    @Published var resumeOnWear = true {
        didSet { defaults.set(resumeOnWear, forKey: "resumeOnWear") }
    }

    @Published var dsee = false {
        didSet {
            guard oldValue != dsee, !suppressSend else { return }
            let value = dsee
            push { try await self.session.setDsee(value) }
        }
    }

    @Published var speakToChatConfig = SpeakToChatConfig(sensitivity: .auto, voiceFocus: false, timeout: .standard) {
        didSet {
            guard oldValue != speakToChatConfig, !suppressSend else { return }
            let value = speakToChatConfig
            push { try await self.session.setSpeakToChatConfig(value) }
        }
    }

    @Published var customButton: CustomButtonFunction = .ambientSoundControl {
        didSet {
            guard oldValue != customButton, !suppressSend else { return }
            let value = customButton
            push { try await self.session.setCustomButton(value) }
        }
    }

    @Published var voiceGuidance = true {
        didSet {
            guard oldValue != voiceGuidance, !suppressSend else { return }
            let value = voiceGuidance
            push { try await self.session.setVoiceGuidance(value) }
        }
    }

    /// true: priority on sound quality, false: priority on a stable connection.
    @Published var soundQualityPriority = true {
        didSet {
            guard oldValue != soundQualityPriority, !suppressSend else { return }
            let value = soundQualityPriority
            push { try await self.session.setSoundQualityPriority(value) }
        }
    }

    @Published private(set) var codec: AudioCodec?
    @Published private(set) var firmware: String?
    @Published private(set) var optimizerStatus: NcOptimizerStatus = .notRunning
    @Published private(set) var optimizerPressure: Double?
    var optimizerRunning: Bool { optimizerStatus != .notRunning && optimizerStatus != .finished }

    func startNcOptimizer() {
        optimizerStatus = .checkingWearing
        push { try await self.session.runNcOptimizer(true) }
    }

    func cancelNcOptimizer() {
        push { try await self.session.runNcOptimizer(false) }
    }

    @Published var autoPowerOff: AutoPowerOff = .never {
        didSet {
            guard oldValue != autoPowerOff, !suppressSend else { return }
            let value = autoPowerOff
            push { try await self.session.setAutoPowerOff(value) }
        }
    }

    // Latest battery readings per announced kind.
    private var singleLevel: Int?
    private var singleCharging = ChargingStatus.notCharging
    private var leftLevel: Int?
    private var leftCharging = ChargingStatus.notCharging
    private var rightLevel: Int?
    private var rightCharging = ChargingStatus.notCharging
    private var cradleLevel: Int?
    private var cradleCharging = ChargingStatus.notCharging

    init(session: HeadphonesControlling, isDemo: Bool = false) {
        self.session = session
        self.isDemo = isDemo
        autoPause = UserDefaults.standard.object(forKey: "pauseOnRemoval") as? Bool ?? true
        resumeOnWear = UserDefaults.standard.object(forKey: "resumeOnWear") as? Bool ?? true
        attach(session)
    }

    /// Swaps between the real headset and the demo without restarting the app.
    func switchTo(_ newSession: HeadphonesControlling, isDemo: Bool) {
        session.onStateChanged = nil
        session.onDeviceEvent = nil
        session.onCapabilities = nil
        session.stop()
        apply(state: .disconnected)
        session = newSession
        self.isDemo = isDemo
        attach(newSession)
        newSession.start()
    }

    func start() { session.start() }
    func stop() { session.stop() }

    private func attach(_ session: HeadphonesControlling) {
        session.onStateChanged = { [weak self] state in self?.apply(state: state) }
        session.onDeviceEvent = { [weak self] event in self?.apply(event: event) }
        session.onCapabilities = { [weak self] caps in self?.apply(capabilities: caps) }
    }

    // MARK: Labels

    var displayName: String {
        isDemo ? deviceName + L(" (demo)", " (démo)") : deviceName
    }

    var statusText: String {
        if commandFailed && isConnected { return L("Command failed — resyncing…", "Échec de la commande — resynchronisation…") }
        switch connection {
        case .ready:
            if isDemo { return L("Demo mode", "Mode démo") }
            switch wearing {
            case .worn: return L("Connected · on your head", "Connecté · sur tes oreilles")
            case .removed: return L("Connected · taken off", "Connecté · retiré")
            case .unknown: return L("Connected", "Connecté")
            }
        case .connecting: return L("Connecting…", "Connexion…")
        case .bluetoothOff: return L("Bluetooth is off", "Le Bluetooth est désactivé")
        case .headsetNotConnected: return L("Connect the headphones to this Mac", "Connecte le casque à ce Mac")
        case .disconnected: return L("Headphones not found — are they on?", "Casque introuvable — est-il allumé ?")
        }
    }

    var batteryText: String {
        func part(_ level: Int, _ charging: ChargingStatus) -> String {
            charging == .charging ? "\(level) % ⚡︎" : "\(level) %"
        }
        let kinds = capabilities?.batteries
        var text: String
        if kinds?.contains(.leftRight) ?? true, let l = leftLevel, let r = rightLevel {
            text = "\(L("L", "G")) \(part(l, leftCharging)) · \(L("R", "D")) \(part(r, rightCharging))"
        } else if kinds?.contains(.single) ?? true, let s = singleLevel {
            text = part(s, singleCharging)
        } else {
            return "–"
        }
        if kinds?.contains(.cradle) ?? true, let c = cradleLevel {
            text += " · \(L("Case", "Boîtier")) \(part(c, cradleCharging))"
        }
        return text
    }

    static func name(of preset: EqPreset) -> String {
        switch preset {
        case .off: return L("Flat", "Neutre")
        case .bright: return L("Bright", "Brillant")
        case .excited: return L("Excited", "Énergique")
        case .mellow: return L("Mellow", "Doux")
        case .relaxed: return L("Relaxed", "Détendu")
        case .vocal: return L("Vocal", "Voix")
        case .trebleBoost: return L("Treble +", "Aigus +")
        case .bassBoost: return L("Bass +", "Basses +")
        case .speech: return L("Speech", "Parole")
        case .manual: return L("Manual", "Manuel")
        case .custom1: return L("Custom 1", "Perso 1")
        case .custom2: return L("Custom 2", "Perso 2")
        default: return String(format: "Preset 0x%02X", preset.rawValue)
        }
    }

    static func name(of timer: AutoPowerOff) -> String {
        switch timer {
        case .after5Minutes: return L("After 5 min", "Après 5 min")
        case .after15Minutes: return L("After 15 min", "Après 15 min")
        case .after30Minutes: return L("After 30 min", "Après 30 min")
        case .after60Minutes: return L("After 1 h", "Après 1 h")
        case .after180Minutes: return L("After 3 h", "Après 3 h")
        case .whenTakenOff: return L("When taken off", "Quand je le retire")
        case .never: return L("Never", "Jamais")
        default: return String(format: "0x%02X", timer.rawValue)
        }
    }

    static func name(of sensitivity: SpeakToChatSensitivity) -> String {
        switch sensitivity {
        case .auto: return L("Auto", "Auto")
        case .high: return L("High", "Haute")
        case .low: return L("Low", "Basse")
        }
    }

    static func name(of timeout: SpeakToChatTimeout) -> String {
        switch timeout {
        case .short: return L("Short (15 s)", "Court (15 s)")
        case .standard: return L("Standard (30 s)", "Standard (30 s)")
        case .long: return L("Long (1 min)", "Long (1 min)")
        case .off: return L("Don't end automatically", "Ne pas arrêter")
        }
    }

    static func name(of function: CustomButtonFunction) -> String {
        switch function {
        case .ambientSoundControl: return L("Ambient Sound Control", "Contrôle du son ambiant")
        case .googleAssistant: return "Google Assistant"
        case .amazonAlexa: return "Amazon Alexa"
        }
    }

    var optimizerText: String {
        switch optimizerStatus {
        case .checkingWearing: return L("Checking how they sit…", "Vérification du port…")
        case .measuringPressure: return L("Measuring air pressure…", "Mesure de la pression…")
        case .analyzing: return L("Analysing…", "Analyse…")
        case .finished: return L("Optimised", "Optimisé")
        case .notRunning:
            if let optimizerPressure {
                return String(format: L("Last run: %.1f atm", "Dernier passage : %.1f atm"), optimizerPressure)
            }
            return L("Tunes NC to your head and the air pressure", "Adapte la réduction de bruit à ta tête et à la pression")
        }
    }

    // MARK: Derived

    var ambientControlsEnabled: Bool { isConnected && hasNoiseControls && mode == .ambient }
    var eqBandsEditable: Bool {
        isConnected && hasEqSection && eqAvailable && hasEqBandData && selectedPreset >= .manual
    }
    var clearBass: BandModel? { hasEqBandData && !isTenBandEq ? bands.first : nil }
    var frequencyBands: [BandModel] {
        guard hasEqBandData else { return [] }
        return isTenBandEq ? bands : Array(bands.dropFirst())
    }

    func setBandValue(_ value: Double, id: Int) {
        guard eqBandsEditable, value.isFinite,
              let index = bands.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(value.rounded(), bands[index].minimum), bands[index].maximum)
        guard bands[index].value != clamped else { return }
        bands[index].value = clamped
    }

    /// Resets the current custom preset's curve to flat.
    func flattenBands() {
        guard eqBandsEditable else { return }
        var flat = bands
        for i in flat.indices { flat[i].value = 0 }
        bands = flat
    }

    func powerOff() {
        push { try await self.session.powerOff() }
    }

    // MARK: - Sending

    private func scheduleMode(delay: UInt64) {
        ambientDebounce?.cancel()
        let edit = UUID()
        pendingNoiseEdit = edit
        let mode = self.mode
        let level = Int(ambientLevel.rounded())
        let voice = focusOnVoice
        ambientDebounce = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled, let self, self.pendingNoiseEdit == edit else { return }
            self.ambientDebounce = nil
            self.push({
                try await self.session.setNcAmb(
                    mode: mode, ambientLevel: min(max(level, 0), 20), focusOnVoice: voice)
            }, onComplete: {
                if self.pendingNoiseEdit == edit { self.pendingNoiseEdit = nil }
            })
        }
    }

    private func debounceBands() {
        bandsDebounce?.cancel()
        bandsDebounce = nil
        pendingBandsEdit = nil
        guard eqBandsEditable else { return }
        let edit = UUID()
        pendingBandsEdit = edit
        let preset = selectedPreset
        let values = bands.map { Int($0.value.rounded()) }
        let tenBandEq = isTenBandEq
        bandsDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self, self.pendingBandsEdit == edit,
                  self.eqBandsEditable else { return }
            self.bandsDebounce = nil
            self.push({
                if tenBandEq {
                    try await self.session.setEqBands10(preset: preset, bands: values)
                } else {
                    let clearBass = values.first ?? 0
                    let rest = Array(values.dropFirst())
                    try await self.session.setEqBands(preset: preset, clearBass: clearBass, bands: rest)
                }
            }, onComplete: {
                if self.pendingBandsEdit == edit { self.pendingBandsEdit = nil }
            })
        }
    }

    /// Optimistic send; on failure re-sync the UI from the device so it never lies.
    private func push(_ send: @escaping () async throws -> Void, onComplete: @escaping () -> Void = {}) {
        Task { @MainActor in
            do {
                guard self.isConnected else { onComplete(); return }
                try await send()
            } catch {
                onComplete()
                guard self.isConnected else { return }
                Log.error("Command failed: \(error.localizedDescription)")
                commandFailed = true
                try? await session.refresh()
                commandFailed = false
                return
            }
            onComplete()
        }
    }

    // MARK: - Wearing → playback

    private func applyWearing(_ new: WearingState) {
        let previous = wearing
        wearing = new
        guard isConnected else { return }
        if new == .removed, previous == .worn, autoPause {
            if MediaControl.pause() { pausedByRemoval = true }
        } else if new == .worn, pausedByRemoval {
            pausedByRemoval = false
            if resumeOnWear { MediaControl.play() }
        }
    }

    /// Demo only: pretend the headset was taken off or put back on.
    func simulateWearing(_ state: WearingState) {
        guard isDemo else { return }
        applyWearing(state)
    }

    // MARK: - Applying device state

    private func apply(state: SessionState) {
        connection = state
        if state != .ready {
            ambientDebounce?.cancel()
            bandsDebounce?.cancel()
            ambientDebounce = nil
            bandsDebounce = nil
            pendingNoiseEdit = nil
            pendingBandsEdit = nil
            pendingPresetEdit = nil
            hasEqBandData = false
            wearing = .unknown
            pausedByRemoval = false
            singleLevel = nil
            leftLevel = nil
            rightLevel = nil
            cradleLevel = nil
            recomputeBattery()
        }
        objectWillChange.send()
    }

    private func apply(capabilities caps: DeviceCapabilities) {
        capabilities = caps
        deviceName = caps.deviceName
        hasNcChip = caps.hasNcMode
        hasNoiseControls = caps.ncVariant != nil
        hasEqSection = caps.hasEq
        powerOffVisible = caps.hasPowerOff
        hasSpeakToChat = caps.hasSpeakToChat
        hasHeadsetAutoPause = caps.hasAutoPause
        hasWearingStatus = caps.hasWearingStatus
        hasDsee = caps.hasDsee
        hasAutoPowerOff = caps.autoPowerOffWearingDetection != nil
        hasWindMode = caps.hasWindMode
        hasSpeakToChatConfig = caps.hasSpeakToChatConfig
        hasCustomButton = caps.hasCustomButton
        hasVoiceGuidance = caps.hasVoiceGuidance
        hasSoundQualityPriority = caps.hasSoundQualityPriority
        hasNcOptimizer = caps.hasNcOptimizer
        hasDeviceInfo = caps.hasDeviceInfo
        codec = nil
        firmware = nil
        optimizerStatus = .notRunning
        optimizerPressure = nil
        var timers = Self.timerChoices
        if !caps.hasAutoPowerOff15Minutes { timers.removeAll { $0 == .after15Minutes } }
        if caps.autoPowerOffWearingDetection == true { timers.insert(.whenTakenOff, at: 0) }
        autoPowerOffChoices = timers
        eqAvailable = true
        hasEqBandData = false

        // Reset cached battery readings before the capability queries repopulate them, so a
        // different headset never shows the previous one's numbers.
        singleLevel = nil
        leftLevel = nil
        rightLevel = nil
        cradleLevel = nil
        recomputeBattery()
    }

    private func apply(event: DeviceEvent) {
        suppressSend = true
        defer { suppressSend = false }

        switch event {
        case .ncAmb(let mode, let level, let voice):
            // A periodic read may still describe the state before a local debounced edit.
            guard pendingNoiseEdit == nil else { return }
            self.mode = mode
            if level >= 1 { ambientLevel = Double(level) }
            focusOnVoice = voice
            objectWillChange.send()
        case .battery(let level, let charging):
            singleLevel = level
            singleCharging = charging
            recomputeBattery()
        case .leftRightBattery(let l, let lc, let r, let rc):
            leftLevel = l
            leftCharging = lc
            rightLevel = r
            rightCharging = rc
            recomputeBattery()
        case .cradleBattery(let level, let charging):
            cradleLevel = level
            cradleCharging = charging
            recomputeBattery()
        case .eqStatus(let available):
            eqAvailable = available
            if !available {
                bandsDebounce?.cancel()
                bandsDebounce = nil
                pendingBandsEdit = nil
                hasEqBandData = false
            }
        case .eq(let preset, let clearBass, let bandValues):
            if pendingBandsEdit != nil {
                let changesFormat = (isTenBandEq && bandValues.count == 5)
                    || (!isTenBandEq && bandValues.count == 10)
                guard changesFormat else { return }
                bandsDebounce?.cancel()
                bandsDebounce = nil
                pendingBandsEdit = nil
            }
            if let pendingPresetEdit, preset != pendingPresetEdit.preset { return }
            applyEq(preset: preset, clearBass: clearBass, bandValues: bandValues)
        case .speakToChat(let enabled):
            speakToChat = enabled
        case .autoPause(let enabled):
            autoPause = enabled
        case .dsee(let enabled):
            dsee = enabled
        case .autoPowerOff(let value, _):
            if !autoPowerOffChoices.contains(value) { autoPowerOffChoices.append(value) }
            autoPowerOff = value
        case .wearing(let state):
            applyWearing(state)
        case .speakToChatConfig(let config):
            speakToChatConfig = config
        case .customButton(let function):
            customButton = function
        case .voiceGuidance(let enabled):
            voiceGuidance = enabled
        case .soundQualityPriority(let quality):
            soundQualityPriority = quality
        case .codec(let value):
            codec = value
        case .firmware(let value):
            firmware = value
        case .ncOptimizerStatus(let status):
            optimizerStatus = status
        case .ncOptimizerPressure(let pressure):
            optimizerPressure = pressure
        case .protocolInfo, .supportFunctions:
            break // handshake-only, consumed by the session
        }
    }

    private func applyEq(preset: EqPreset, clearBass: Int, bandValues: [Int]) {
        let presetChanged = selectedPreset != preset
        if !presets.contains(preset) { presets.append(preset) }
        selectedPreset = preset
        switch bandValues.count {
        case 5:
            guard (-10...10).contains(clearBass), bandValues.allSatisfy({ (-10...10).contains($0) }) else {
                hasEqBandData = false
                return
            }
            let rebuild = !hasEqBandData || isTenBandEq
            isTenBandEq = false
            let values = [Double(clearBass)] + bandValues.map(Double.init)
            if rebuild { setBands(layout: Self.sixBandLayout, values: values) } else { setBandValues(values) }
            hasEqBandData = true
        case 10:
            guard bandValues.allSatisfy({ (-6...6).contains($0) }) else {
                hasEqBandData = false
                return
            }
            let rebuild = !hasEqBandData || !isTenBandEq
            isTenBandEq = true
            let values = bandValues.map(Double.init)
            if rebuild { setBands(layout: Self.tenBandLayout, values: values) } else { setBandValues(values) }
            hasEqBandData = true
        default:
            if presetChanged || !bandValues.isEmpty { hasEqBandData = false }
        }
    }

    private func setBands(layout: [(String, Double, Double)], values: [Double]) {
        bands = layout.enumerated().map { index, entry in
            let id = nextBandID
            nextBandID += 1
            return BandModel(id: id, label: entry.0, minimum: entry.1, maximum: entry.2,
                             value: index < values.count ? values[index] : 0)
        }
    }

    private func setBandValues(_ values: [Double]) {
        for (index, value) in values.enumerated() where index < bands.count {
            bands[index].value = value
        }
    }

    private func recomputeBattery() {
        let kinds = capabilities?.batteries
        if kinds?.contains(.leftRight) ?? true, let l = leftLevel, let r = rightLevel {
            batteryLevel = min(l, r)
            isCharging = leftCharging == .charging || rightCharging == .charging
        } else if kinds?.contains(.single) ?? true, let s = singleLevel {
            batteryLevel = s
            isCharging = singleCharging == .charging
        } else {
            batteryLevel = nil
            isCharging = false
        }
    }
}
