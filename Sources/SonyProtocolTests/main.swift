// From sony-tray by Abhinav (abhiinhii) and contributors, MIT — see THIRD_PARTY_LICENSE_sony-tray.txt.
import Foundation

print("SonyProtocolKit — protocol conformance suite\n")

runFramingTests()
runCommandsTests()
runPayloadParserTests()
runFrameReassemblerTests()
runOptionsTests()
runTable2Tests()
runProtocolV1Tests()

exit(Harness.summary())
