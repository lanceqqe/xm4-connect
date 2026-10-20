// swift-tools-version: 5.9
// For browsing and editing in Xcode. Build the runnable app with `make` (an .app bundle with an
// Info.plist is required for the Bluetooth permission prompt).
import PackageDescription

let package = Package(
    name: "XMConnect",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SonyProtocolKit", targets: ["SonyProtocolKit"]),
        .executable(name: "XMConnect", targets: ["XMConnect"]),
    ],
    targets: [
        .target(name: "SonyProtocolKit"),
        .executableTarget(
            name: "XMConnect",
            dependencies: ["SonyProtocolKit"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreAudio"),
            ]
        ),
        .executableTarget(name: "SonyProtocolTests", dependencies: ["SonyProtocolKit"]),
    ]
)
