import SonyProtocolKit

// Replies captured from a WH-1000XM4 on firmware 2.5.0.
func runProtocolV1Tests() {
    print("Protocol v1 (WH-1000XM4)")

    test("parses the v1 init reply") {
        let e = try expectNotNil(PayloadParserV1.parse([0x01, 0x00, 0x70, 0x00]))
        guard case .protocolInfo(_, let table1, let table2) = e else { return fail("got \(e)") }
        expectTrue(table1)
        expectTrue(table2, "voice guidance lives in table 2")
    }

    test("parses battery") {
        expectEqual(PayloadParserV1.parse([0x11, 0x00, 0x5A, 0x00]), .battery(level: 90, charging: .notCharging))
        expectEqual(PayloadParserV1.parse([0x13, 0x00, 0x32, 0x01]), .battery(level: 50, charging: .charging))
    }

    test("parses NC/ASM") {
        expectEqual(PayloadParserV1.parse([0x67, 0x02, 0x00, 0x02, 0x02, 0x01, 0x00, 0x00]),
                    .ncAmb(mode: .off, ambientLevel: 0, focusOnVoice: false))
        expectEqual(PayloadParserV1.parse([0x69, 0x02, 0x01, 0x02, 0x02, 0x01, 0x00, 0x00]),
                    .ncAmb(mode: .noiseCancelling, ambientLevel: 0, focusOnVoice: false))
        expectEqual(PayloadParserV1.parse([0x69, 0x02, 0x01, 0x02, 0x00, 0x01, 0x01, 0x0F]),
                    .ncAmb(mode: .ambient, ambientLevel: 15, focusOnVoice: true))
        expectEqual(PayloadParserV1.parse([0x69, 0x02, 0x01, 0x02, 0x01, 0x01, 0x00, 0x00]),
                    .ncAmb(mode: .windNoiseReduction, ambientLevel: 0, focusOnVoice: false))
    }

    test("parses EQ") {
        expectEqual(PayloadParserV1.parse([0x57, 0x01, 0xA0, 0x06, 0x14, 0x0B, 0x0F, 0x11, 0x11, 0x13]),
                    .eq(preset: .manual, clearBass: 10, bands: [1, 5, 7, 7, 9]))
    }

    test("parses options") {
        expectEqual(PayloadParserV1.parse([0xE7, 0x02, 0x00, 0x00]), .dsee(enabled: false))
        expectEqual(PayloadParserV1.parse([0xF7, 0x03, 0x00, 0x01]), .autoPause(enabled: true))
        expectEqual(PayloadParserV1.parse([0xF7, 0x04, 0x01, 0x10, 0x00]),
                    .autoPowerOff(.whenTakenOff, wearingDetection: true))
        expectEqual(PayloadParserV1.parse([0xF7, 0x05, 0x00, 0x00]), .speakToChat(enabled: false))
        expectEqual(PayloadParserV1.parse([0xF9, 0x05, 0x01, 0x01]), .speakToChat(enabled: true))
        expectNil(PayloadParserV1.parse([0xF9, 0x05, 0x02, 0x00]))
    }

    test("parses XM4 extras") {
        expectEqual(PayloadParserV1.parse([0xFB, 0x05, 0x00, 0x00, 0x00, 0x01]),
                    .speakToChatConfig(SpeakToChatConfig(sensitivity: .auto, voiceFocus: false, timeout: .standard)))
        expectEqual(PayloadParserV1.parse([0xD7, 0xD1, 0x01, 0x01]), .customButton(.googleAssistant))
        expectEqual(PayloadParserV1.parse([0xD9, 0xD1, 0x01, 0x00]), .customButton(.ambientSoundControl))
        expectNil(PayloadParserV1.parse([0xD7, 0xD2, 0x01, 0x01]))
        expectEqual(PayloadParserV1.parse([0xE7, 0x01, 0x00, 0x00]), .soundQualityPriority(true))
        expectEqual(PayloadParserV1.parse([0xE9, 0x01, 0x00, 0x01]), .soundQualityPriority(false))
        expectEqual(PayloadParserV1.parse([0x19, 0x00, 0x02]), .codec(.aac))
        expectEqual(PayloadParserV1.parse([0x1B, 0x00, 0x10]), .codec(.ldac))
        expectEqual(PayloadParserV1.parse([0x05, 0x02, 0x05, 0x32, 0x2E, 0x35, 0x2E, 0x30]), .firmware("2.5.0"))
        expectEqual(PayloadParserV1.parse([0x87, 0x01, 0x01, 0x01, 0x01, 0x0A]), .ncOptimizerPressure(1.0))
        expectEqual(PayloadParserV1.parse([0x85, 0x01, 0x01, 0x10]), .ncOptimizerStatus(.analyzing))
        expectEqual(PayloadParserV1.parseTable2([0x47, 0x01, 0x01, 0x01]), .voiceGuidance(enabled: true))
        expectEqual(PayloadParserV1.parseTable2([0x49, 0x01, 0x01, 0x00]), .voiceGuidance(enabled: false))
    }

    test("builds commands") {
        expectEqual(try CommandsV1.setNcAmb(mode: .noiseCancelling, ambientLevel: 12, focusOnVoice: true),
                    [0x68, 0x02, 0x11, 0x02, 0x02, 0x01, 0x00, 0x00])
        expectEqual(try CommandsV1.setNcAmb(mode: .ambient, ambientLevel: 12, focusOnVoice: true),
                    [0x68, 0x02, 0x11, 0x02, 0x00, 0x01, 0x01, 0x0C])
        expectEqual(try CommandsV1.setNcAmb(mode: .off, ambientLevel: 12, focusOnVoice: false),
                    [0x68, 0x02, 0x00, 0x02, 0x00, 0x01, 0x00, 0x0C])
        expectEqual(try CommandsV1.setEqBands(clearBass: 10, bands: [1, 5, 7, 7, 9]),
                    [0x58, 0x01, 0xFF, 0x06, 0x14, 0x0B, 0x0F, 0x11, 0x11, 0x13])
        expectEqual(try CommandsV1.setNcAmb(mode: .windNoiseReduction, ambientLevel: 12, focusOnVoice: true),
                    [0x68, 0x02, 0x11, 0x02, 0x01, 0x01, 0x00, 0x00])
        expectEqual(CommandsV1.setSpeakToChatConfig(
                        SpeakToChatConfig(sensitivity: .high, voiceFocus: false, timeout: .long)),
                    [0xFC, 0x05, 0x00, 0x01, 0x00, 0x02])
        expectEqual(CommandsV1.setCustomButton(.ambientSoundControl), [0xD8, 0xD1, 0x01, 0x00])
        expectEqual(CommandsV1.setSoundQualityPriority(false), [0xE8, 0x01, 0x00, 0x01])
        expectEqual(CommandsV1.setVoiceGuidance(false), [0x48, 0x01, 0x01, 0x00])
        expectEqual(CommandsV1.runNcOptimizer(true), [0x84, 0x01, 0x00, 0x01])
        expectEqual(CommandsV1.setAutoPowerOff(.after30Minutes) ?? [], [0xF8, 0x04, 0x01, 0x01, 0x01])
        expectEqual(CommandsV1.setAutoPowerOff(.never) ?? [], [0xF8, 0x04, 0x01, 0x11, 0x00])
        expectNil(CommandsV1.setAutoPowerOff(.after15Minutes))
        expectThrows { _ = try CommandsV1.setNcAmb(mode: .ambient, ambientLevel: 21, focusOnVoice: false) }
    }
}
