// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AudioFlow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Shenglan", targets: ["Shenglan"])],
    targets: [
        .target(
            name: "ShenglanAudioEngine",
            path: "Sources/ShenglanAudioEngine",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .executableTarget(
            name: "Shenglan",
            dependencies: ["ShenglanAudioEngine"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
