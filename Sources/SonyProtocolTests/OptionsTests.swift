import Foundation
import SonyProtocolKit

/// XM5 options added on top of sony-tray: byte layouts from SonyHeadphonesClient's
/// ProtocolV2T1.hpp (OnOffSettingValue ON = 0x00, OFF = 0x01).
func runOptionsTests() {
    test("Speak-to-Chat get/set") {
        expectEqual(Commands.getSpeakToChat(), [0xF6, 0x0C])
        expectEqual(Commands.setSpeakToChat(true), [0xF8, 0x0C, 0x00, 0x01])
        expectEqual(Commands.setSpeakToChat(false), [0xF8, 0x0C, 0x01, 0x01])
    }
    test("Speak-to-Chat RET and NTFY parse") {
        expectEqual(PayloadParser.parse([0xF7, 0x0C, 0x00, 0x01]), .speakToChat(enabled: true))
        expectEqual(PayloadParser.parse([0xF9, 0x0C, 0x01, 0x01]), .speakToChat(enabled: false))
    }
    test("Pause on removal get/set/parse") {
        expectEqual(Commands.getAutoPause(), [0xF6, 0x01])
        expectEqual(Commands.setAutoPause(true), [0xF8, 0x01, 0x00])
        expectEqual(Commands.setAutoPause(false), [0xF8, 0x01, 0x01])
        expectEqual(PayloadParser.parse([0xF7, 0x01, 0x00]), .autoPause(enabled: true))
        expectEqual(PayloadParser.parse([0xF9, 0x01, 0x01]), .autoPause(enabled: false))
    }
    test("DSEE Extreme get/set/parse") {
        expectEqual(Commands.getDsee(), [0xE6, 0x01])
        expectEqual(Commands.setDsee(true), [0xE8, 0x01, 0x01])
        expectEqual(Commands.setDsee(false), [0xE8, 0x01, 0x00])
        expectEqual(PayloadParser.parse([0xE7, 0x01, 0x01]), .dsee(enabled: true))
        expectEqual(PayloadParser.parse([0xE9, 0x01, 0x00]), .dsee(enabled: false))
        expectNil(PayloadParser.parse([0xE7, 0x00, 0x01]), "connection-mode reply is not DSEE")
    }
    test("Auto power off get/set/parse") {
        expectEqual(Commands.getAutoPowerOff(wearingDetection: false), [0x26, 0x04])
        expectEqual(Commands.getAutoPowerOff(wearingDetection: true), [0x26, 0x05])
        expectEqual(Commands.setAutoPowerOff(.never, wearingDetection: false), [0x28, 0x04, 0x11, 0x00])
        expectEqual(Commands.setAutoPowerOff(.whenTakenOff, wearingDetection: true), [0x28, 0x05, 0x10, 0x00])
        expectEqual(PayloadParser.parse([0x27, 0x04, 0x02, 0x00]),
                    .autoPowerOff(.after60Minutes, wearingDetection: false))
        expectEqual(PayloadParser.parse([0x29, 0x05, 0x10, 0x00]),
                    .autoPowerOff(.whenTakenOff, wearingDetection: true))
    }
    test("Unknown system/power param types are ignored") {
        expectNil(PayloadParser.parse([0xF7, 0x03, 0x00]))
        expectNil(PayloadParser.parse([0x27, 0x0B, 0x00]))
        expectNil(PayloadParser.parse([0xF7, 0x0C]), "too short")
    }
    test("Options survive framing round-trip") {
        let packed = Framing.pack(.dataMdr, seq: 1, payload: Commands.setSpeakToChat(true))
        let frame = Framing.tryUnpack(packed)
        expectEqual(frame?.payload ?? [], [0xF8, 0x0C, 0x00, 0x01])
    }
}

func runTable2Tests() {
    test("Wearing status: query, reply and notifications") {
        expectEqual(Commands.getWearingStatus(), [0xF2, 0x00])
        expectEqual(PayloadParser.parseTable2([0xF3, 0x00, 0x00]), .wearing(.worn))
        expectEqual(PayloadParser.parseTable2([0xF5, 0x00, 0x04]), .wearing(.removed))
        expectEqual(PayloadParser.parseTable2([0xF5, 0x00, 0x02]), .wearing(.removed))
        expectEqual(PayloadParser.parseTable2([0xF5, 0x00, 0x01]), .wearing(.unknown))
        expectNil(PayloadParser.parseTable2([0xF5, 0x01, 0x00]), "other inquired type")
        expectNil(PayloadParser.parseTable2([0xF5, 0x00]), "too short")
    }
    test("Table-2 frames survive framing") {
        let packed = Framing.pack(.dataMdrNo2, seq: 0, payload: [0xF5, 0x00, 0x04])
        let frame = Framing.tryUnpack(packed)
        expectEqual(frame?.type, .dataMdrNo2)
        expectEqual(frame?.payload ?? [], [0xF5, 0x00, 0x04])
    }
}
