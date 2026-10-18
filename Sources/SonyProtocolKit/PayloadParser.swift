import Foundation

/// Typed events decoded from the headset's RET (reply) and NTFY (notification) payloads.
///
/// EQ bands are user-scale. 6-band devices (XM5-class): `clearBass` + 5 entries
/// (400/1k/2.5k/6.3k/16k Hz), range −10…+10. 10-band devices: `clearBass` is unused (0), `bands`
/// has 10 entries, range −6…+6. Empty `bands` means the reply carried no band data.
public enum DeviceEvent: Equatable, Sendable {
    case protocolInfo(version: Int, supportsTable1: Bool, supportsTable2: Bool)
    /// The raw set of announced function ids (priority byte ignored).
    case supportFunctions(Set<UInt8>)

    case ncAmb(mode: NcAmbMode, ambientLevel: Int, focusOnVoice: Bool)
    case eqStatus(available: Bool)
    case eq(preset: EqPreset, clearBass: Int, bands: [Int])
    case battery(level: Int, charging: ChargingStatus)
    case leftRightBattery(
        leftLevel: Int, leftCharging: ChargingStatus,
        rightLevel: Int, rightCharging: ChargingStatus)
    case cradleBattery(level: Int, charging: ChargingStatus)

    // XM5 options
    case speakToChat(enabled: Bool)
    case autoPause(enabled: Bool)
    case dsee(enabled: Bool)
    case autoPowerOff(AutoPowerOff, wearingDetection: Bool)

    // Table 2
    case wearing(WearingState)
}

/// Whether the headset is on someone's head (table-2 WearingStatusCode).
public enum WearingState: Equatable, Sendable {
    case worn
    case removed
    case unknown

    public init(code: UInt8) {
        switch code {
        case 0x00: self = .worn                 // NORMAL
        case 0x02, 0x03, 0x04: self = .removed  // LEFT / RIGHT / BOTH not worn
        default: self = .unknown                // ILLEGAL, OUT_OF_RANGE
        }
    }
}

/// Parses RET and NTFY payloads into typed events. Unknown/malformed → nil.
public enum PayloadParser {
    public static func parse(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 2 else { return nil }
        switch p[0] {
        case 0x01: return parseProtocolInfo(p)
        case 0x07: return parseSupportFunctions(p)
        case 0x67, 0x69: return parseNcAmb(p)
        case 0x53, 0x55: return parseEqStatus(p)
        case 0x57, 0x59: return parseEq(p)
        case 0x23, 0x25: return parsePower(p)
        case 0x27, 0x29: return parsePowerParam(p)
        case 0xE7, 0xE9: return parseAudioParam(p)
        case 0xF7, 0xF9: return parseSystemParam(p)
        default: return nil
        }
    }

    /// Table-2 payloads (MessageType.dataMdrNo2).
    public static func parseTable2(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 3 else { return nil }
        switch p[0] {
        case 0xF3, 0xF5: // SYSTEM_RET_STATUS / SYSTEM_NTFY_STATUS
            guard p[1] == 0x00 else { return nil } // WEARING_STATUS_CHECKER
            return .wearing(WearingState(code: p[2]))
        default:
            return nil
        }
    }

    private static func parseProtocolInfo(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 8, p[1] == 0x00 else { return nil }
        let version = Int(p[2]) << 24 | Int(p[3]) << 16 | Int(p[4]) << 8 | Int(p[5])
        return .protocolInfo(version: version, supportsTable1: p[6] == 0, supportsTable2: p[7] == 0)
    }

    private static func parseSupportFunctions(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 3, p[1] == 0x00 else { return nil }
        let count = Int(p[2])
        guard p.count >= 3 + count * 2 else { return nil }
        var functions = Set<UInt8>()
        for i in 0..<count {
            functions.insert(p[3 + i * 2]) // (fn, priority) pairs
        }
        return .supportFunctions(functions)
    }

    private static func parseNcAmb(_ p: [UInt8]) -> DeviceEvent? {
        switch p[1] {
        case 0x17, 0x19:
            // [cmd, type, vcs, effect, mode, voice, level, (adaptive fields…)]
            guard p.count >= 7 else { return nil }
            let mode: NcAmbMode = p[3] == 0 ? .off : (p[4] == 1 ? .ambient : .noiseCancelling)
            return .ncAmb(mode: mode, ambientLevel: Int(p[6]), focusOnVoice: p[5] == 1)
        case 0x22:
            // [cmd, type, vcs, effect, voice, level] — Off/Ambient only.
            guard p.count >= 6 else { return nil }
            let mode: NcAmbMode = p[3] == 0 ? .off : .ambient
            return .ncAmb(mode: mode, ambientLevel: Int(p[5]), focusOnVoice: p[4] == 1)
        default:
            return nil
        }
    }

    private static func parseEqStatus(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 3, p[1] == 0x00 else { return nil }
        return .eqStatus(available: p[2] == 0) // ON = 0
    }

    private static func parseEq(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 4, p[1] == 0x00 else { return nil }
        let preset = EqPreset(rawValue: p[2])
        let count = Int(p[3])
        guard p.count >= 4 + count else { return nil }
        switch count {
        case 6:
            let clearBass = Int(p[4]) - 10
            let bands = (5...9).map { Int(p[$0]) - 10 }
            return .eq(preset: preset, clearBass: clearBass, bands: bands)
        case 10:
            let bands = (4...13).map { Int(p[$0]) - 6 }
            return .eq(preset: preset, clearBass: 0, bands: bands)
        default:
            return .eq(preset: preset, clearBass: 0, bands: [])
        }
    }

    // BATTERY 0x00/0x08, LEFT_RIGHT 0x01/0x09, CRADLE 0x02/0x0A (threshold bytes ignored).
    private static func parsePower(_ p: [UInt8]) -> DeviceEvent? {
        switch p[1] {
        case 0x00, 0x08:
            guard p.count >= 4 else { return nil }
            return .battery(level: Int(p[2]), charging: ChargingStatus(rawValue: p[3]) ?? .unknown)
        case 0x01, 0x09:
            guard p.count >= 6 else { return nil }
            return .leftRightBattery(
                leftLevel: Int(p[2]), leftCharging: ChargingStatus(rawValue: p[3]) ?? .unknown,
                rightLevel: Int(p[4]), rightCharging: ChargingStatus(rawValue: p[5]) ?? .unknown)
        case 0x02, 0x0A:
            guard p.count >= 4 else { return nil }
            return .cradleBattery(level: Int(p[2]), charging: ChargingStatus(rawValue: p[3]) ?? .unknown)
        default:
            return nil
        }
    }

    // POWER_RET_PARAM / POWER_NTFY_PARAM: [cmd, type, current, lastSelected]
    private static func parsePowerParam(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 3 else { return nil }
        switch p[1] {
        case 0x04: return .autoPowerOff(AutoPowerOff(rawValue: p[2]), wearingDetection: false)
        case 0x05: return .autoPowerOff(AutoPowerOff(rawValue: p[2]), wearingDetection: true)
        default: return nil
        }
    }

    // AUDIO_RET_PARAM / AUDIO_NTFY_PARAM, UPSCALING(0x01): [cmd, type, OFF=0|AUTO=1]
    private static func parseAudioParam(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 3, p[1] == 0x01 else { return nil }
        return .dsee(enabled: p[2] == 0x01)
    }

    // SYSTEM_RET_PARAM / SYSTEM_NTFY_PARAM: [cmd, type, onOff(ON=0), …]
    private static func parseSystemParam(_ p: [UInt8]) -> DeviceEvent? {
        guard p.count >= 3 else { return nil }
        switch p[1] {
        case 0x01: return .autoPause(enabled: p[2] == 0x00)
        case 0x0C: return .speakToChat(enabled: p[2] == 0x00)
        default: return nil
        }
    }
}
