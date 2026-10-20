import Foundation

// Sony "MDR" protocol, version 1: the protocol of the WH-1000XM4. It uses the same framing,
// sequence numbers and ACKs as version 2, but a different RFCOMM service UUID and different
// command codes. Support-function discovery is not worth trusting here, so the capabilities are
// fixed for the model.
//
// The starting point was Gadgetbridge's SonyProtocolImplV1 (codeberg.org/Freeyourgadget/
// Gadgetbridge; only the message layouts were used, no code). Every command below was then
// checked against a WH-1000XM4 on firmware 2.5.0. Where the headset disagreed with that
// reference (the custom button, EQ bands), the headset wins.
// v1 booleans are ON = 0x01, which is the opposite of table-1 v2.

public enum SpeakToChatSensitivity: UInt8, CaseIterable, Sendable {
    case auto = 0x00
    case high = 0x01
    case low = 0x02
}

/// How long after you stop talking the music comes back.
public enum SpeakToChatTimeout: UInt8, CaseIterable, Sendable {
    case short = 0x00
    case standard = 0x01
    case long = 0x02
    case off = 0x03
}

public struct SpeakToChatConfig: Equatable, Sendable {
    public var sensitivity: SpeakToChatSensitivity
    /// "Voice focus" while Speak-to-Chat is active.
    public var voiceFocus: Bool
    public var timeout: SpeakToChatTimeout

    public init(sensitivity: SpeakToChatSensitivity, voiceFocus: Bool, timeout: SpeakToChatTimeout) {
        self.sensitivity = sensitivity
        self.voiceFocus = voiceFocus
        self.timeout = timeout
    }
}

/// What the CUSTOM (NC/AMB) button does.
public enum CustomButtonFunction: UInt8, CaseIterable, Sendable {
    case ambientSoundControl = 0x00
    case googleAssistant = 0x01
    case amazonAlexa = 0x02
}

public enum AudioCodec: UInt8, Sendable {
    case unknown = 0x00
    case sbc = 0x01
    case aac = 0x02
    case ldac = 0x10
    case aptX = 0x20
    case aptXHD = 0x21

    public var name: String {
        switch self {
        case .unknown: return "—"
        case .sbc: return "SBC"
        case .aac: return "AAC"
        case .ldac: return "LDAC"
        case .aptX: return "aptX"
        case .aptXHD: return "aptX HD"
        }
    }
}

public enum NcOptimizerStatus: UInt8, Sendable {
    case notRunning = 0x00
    case checkingWearing = 0x01
    case measuringPressure = 0x02
    case analyzing = 0x10
    case finished = 0x11
}

public enum CommandsV1 {
    private static func bool(_ on: Bool) -> UInt8 { on ? 0x01 : 0x00 }

    public static func getProtocolInfo() -> [UInt8] { [0x00, 0x00] }
    public static func getFirmware() -> [UInt8] { [0x04, 0x02] }
    public static func getCodec() -> [UInt8] { [0x18, 0x00] }
    public static func getBattery() -> [UInt8] { [0x10, 0x00] }
    public static func getNcAmb() -> [UInt8] { [0x66, 0x02] }
    public static func getEq() -> [UInt8] { [0x56, 0x01] }
    public static func getSoundQualityPriority() -> [UInt8] { [0xE6, 0x01] }
    public static func getDsee() -> [UInt8] { [0xE6, 0x02] }
    public static func getAutoPause() -> [UInt8] { [0xF6, 0x03] }
    public static func getAutoPowerOff() -> [UInt8] { [0xF6, 0x04] }
    public static func getSpeakToChat() -> [UInt8] { [0xF6, 0x05] }
    public static func getSpeakToChatConfig() -> [UInt8] { [0xFA, 0x05] }
    public static func getCustomButton() -> [UInt8] { [0xD6, 0xD1] }
    public static func getNcOptimizerState() -> [UInt8] { [0x86, 0x01] }
    /// Table 2 (MessageType.dataMdrNo2).
    public static func getVoiceGuidance() -> [UInt8] { [0x46, 0x01, 0x01] }

    public static func powerOff() -> [UInt8] { [0x22, 0x00, 0x01] }

    /// [0x68, 0x02, effect, 0x02 (wind-capable layout), ncSetting, 0x01, voice, level].
    /// ncSetting: NC = 2, wind reduction = 1, ambient/off = 0. Effect 0x11 = adjustment complete.
    /// The ambient level is only sent in ambient mode. In the other modes the headset keeps the
    /// level it already has.
    public static func setNcAmb(mode: NcAmbMode, ambientLevel: Int, focusOnVoice: Bool) throws -> [UInt8] {
        guard (0...20).contains(ambientLevel) else {
            throw CommandError.valueOutOfRange(name: "ambientLevel", value: ambientLevel, min: 0, max: 20)
        }
        let effect: UInt8 = mode == .off ? 0x00 : 0x11
        let nc: UInt8
        switch mode {
        case .noiseCancelling: nc = 0x02
        case .windNoiseReduction: nc = 0x01
        case .ambient, .off: nc = 0x00
        }
        let voice = bool(mode == .ambient && focusOnVoice)
        let level: UInt8 = mode == .ambient || mode == .off ? UInt8(ambientLevel) : 0
        return [0x68, 0x02, effect, 0x02, nc, 0x01, voice, level]
    }

    public static func setEqPreset(_ preset: EqPreset) -> [UInt8] {
        [0x58, 0x01, preset.rawValue, 0x00]
    }

    /// Clear Bass + 5 bands, −10…+10, written to the active preset. The headset only accepts
    /// 0xFF ("active preset") here: naming the preset explicitly is silently ignored.
    public static func setEqBands(clearBass: Int, bands: [Int]) throws -> [UInt8] {
        guard bands.count == 5 else {
            throw CommandError.bandCountMismatch(expected: 5, actual: bands.count)
        }
        for value in [clearBass] + bands where !(-10...10).contains(value) {
            throw CommandError.valueOutOfRange(name: "band", value: value, min: -10, max: 10)
        }
        return [0x58, 0x01, 0xFF, 0x06] + ([clearBass] + bands).map { UInt8($0 + 10) }
    }

    public static func setDsee(_ enabled: Bool) -> [UInt8] { [0xE8, 0x02, 0x00, bool(enabled)] }
    public static func setSoundQualityPriority(_ quality: Bool) -> [UInt8] {
        [0xE8, 0x01, 0x00, quality ? 0x00 : 0x01]
    }
    public static func setAutoPause(_ enabled: Bool) -> [UInt8] { [0xF8, 0x03, 0x00, bool(enabled)] }
    public static func setSpeakToChat(_ enabled: Bool) -> [UInt8] { [0xF8, 0x05, 0x01, bool(enabled)] }
    public static func setSpeakToChatConfig(_ config: SpeakToChatConfig) -> [UInt8] {
        [0xFC, 0x05, 0x00, config.sensitivity.rawValue, bool(config.voiceFocus), config.timeout.rawValue]
    }
    public static func setCustomButton(_ function: CustomButtonFunction) -> [UInt8] {
        [0xD8, 0xD1, 0x01, function.rawValue]
    }
    /// Table 2 (MessageType.dataMdrNo2).
    public static func setVoiceGuidance(_ enabled: Bool) -> [UInt8] { [0x48, 0x01, 0x01, bool(enabled)] }

    /// Starts (or cancels) the NC Optimizer. The headset plays test tones and reports progress
    /// with 0x85 notifications.
    public static func runNcOptimizer(_ start: Bool) -> [UInt8] { [0x84, 0x01, 0x00, bool(start)] }

    /// v1 sends two bytes: timers repeat their code, "when taken off" / "never" pair with 0x00.
    /// The 15-minute timer does not exist on v1 devices.
    public static func setAutoPowerOff(_ value: AutoPowerOff) -> [UInt8]? {
        switch value {
        case .after5Minutes, .after30Minutes, .after60Minutes, .after180Minutes:
            return [0xF8, 0x04, 0x01, value.rawValue, value.rawValue]
        case .whenTakenOff, .never:
            return [0xF8, 0x04, 0x01, value.rawValue, 0x00]
        default:
            return nil
        }
    }
}

public enum PayloadParserV1 {
    public static func parse(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 2 else { return nil }
        switch p[0] {
        case 0x01: // INIT_REPLY: [0x01, 0x00, version, …]
            guard p.count >= 3 else { return nil }
            return .protocolInfo(version: Int(p[2]), supportsTable1: true, supportsTable2: true)
        case 0x05: // FW_VERSION_REPLY: [0x05, 0x02, length, ascii…]
            guard p.count >= 3, p[1] == 0x02, p.count >= 3 + Int(p[2]) else { return nil }
            return .firmware(String(decoding: p[3..<(3 + Int(p[2]))], as: UTF8.self))
        case 0x11, 0x13: // BATTERY_LEVEL_REPLY / NOTIFY: [cmd, type, level, charging]
            guard p.count >= 4, p[1] == 0x00 else { return nil }
            return .battery(level: Int(p[2]), charging: p[3] == 0x01 ? .charging : .notCharging)
        case 0x19, 0x1B: // AUDIO_CODEC_REPLY / NOTIFY: [cmd, 0x00, codec]
            guard p.count >= 3, p[1] == 0x00 else { return nil }
            return .codec(AudioCodec(rawValue: p[2]) ?? .unknown)
        case 0x67, 0x69:
            return parseNcAmb(p)
        case 0x57, 0x59: // [cmd, 0x01, preset, count, clearBass, bands…]
            guard p.count >= 4, p[1] == 0x01 else { return nil }
            let preset = EqPreset(rawValue: p[2])
            guard p[3] == 6, p.count >= 10 else { return .eq(preset: preset, clearBass: 0, bands: []) }
            return .eq(preset: preset, clearBass: Int(p[4]) - 10, bands: (5...9).map { Int(p[$0]) - 10 })
        case 0x85: // NC optimizer progress: [0x85, 0x01, ?, status]
            guard p.count >= 4, let status = NcOptimizerStatus(rawValue: p[3]) else { return nil }
            return .ncOptimizerStatus(status)
        case 0x87, 0x89: // NC optimizer result: [cmd, 0x01, …, pressure × 10]
            guard p.count >= 6, p[5] > 0, p[5] <= 10 else { return nil }
            return .ncOptimizerPressure(Double(p[5]) / 10)
        case 0xD7, 0xD9: // [cmd, 0xD1 (custom button), 0x01, function]
            guard p.count >= 4, p[1] == 0xD1, let function = CustomButtonFunction(rawValue: p[3]) else { return nil }
            return .customButton(function)
        case 0xE7, 0xE9: // [cmd, type, 0x00, value]: 0x01 = LDAC priority (0 = quality), 0x02 = DSEE
            guard p.count >= 4 else { return nil }
            switch p[1] {
            case 0x01: return .soundQualityPriority(p[3] == 0x00)
            case 0x02: return .dsee(enabled: p[3] == 0x01)
            default: return nil
            }
        case 0xF7, 0xF9:
            return parseSystem(p)
        case 0xFB, 0xFD: // [cmd, 0x05, 0x00, sensitivity, voiceFocus, timeout]
            guard p.count >= 6, p[1] == 0x05,
                  let sensitivity = SpeakToChatSensitivity(rawValue: p[3]),
                  let timeout = SpeakToChatTimeout(rawValue: p[5]) else { return nil }
            return .speakToChatConfig(SpeakToChatConfig(
                sensitivity: sensitivity, voiceFocus: p[4] == 0x01, timeout: timeout))
        default:
            return nil
        }
    }

    /// Table-2 payloads (MessageType.dataMdrNo2).
    public static func parseTable2(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 4 else { return nil }
        switch p[0] {
        case 0x47, 0x49: // VOICE_NOTIFICATIONS: [cmd, 0x01, 0x01, on]
            guard p[1] == 0x01, p[2] == 0x01 else { return nil }
            return .voiceGuidance(enabled: p[3] == 0x01)
        default:
            return nil
        }
    }

    /// [cmd, 0x02, effect, layout, ncSetting, 0x01, voice, level]. Layout 0x02 means the device
    /// also has wind noise reduction (ncSetting 1).
    private static func parseNcAmb(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 8, p[1] == 0x02 else { return nil }
        let mode: NcAmbMode
        if p[2] == 0x00 {
            mode = .off
        } else if p[3] == 0x02 {
            switch p[4] {
            case 0x01: mode = .windNoiseReduction
            case 0x02: mode = .noiseCancelling
            default: mode = .ambient
            }
        } else {
            mode = p[4] == 0x01 ? .noiseCancelling : .ambient
        }
        return .ncAmb(mode: mode, ambientLevel: Int(p[7]), focusOnVoice: p[6] == 0x01)
    }

    private static func parseSystem(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 4 else { return nil }
        switch p[1] {
        case 0x03:
            return .autoPause(enabled: p[3] == 0x01)
        case 0x04:
            return .autoPowerOff(AutoPowerOff(rawValue: p[3]), wearingDetection: true)
        case 0x05:
            // Byte 2 is 0x00 on a read and 0x01 on a change. 0x02 follows a change and does not
            // carry the on/off flag.
            guard p[2] <= 0x01 else { return nil }
            return .speakToChat(enabled: p[3] == 0x01)
        default:
            return nil
        }
    }
}
