// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GHLive",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GHLiveCore", targets: ["GHLiveCore"]),
        .executable(name: "ghlive", targets: ["ghlive"]),
        .executable(name: "GHLiveApp", targets: ["GHLiveApp"]),
    ],
    targets: [
        .target(name: "GIPProtocol"),
        .target(name: "GuitarInput"),
        .target(name: "KeyMapping", dependencies: ["GuitarInput"]),
        .target(name: "KeyboardOutput", dependencies: ["GuitarInput", "KeyMapping"]),
        .target(name: "USBTransport"),
        .target(
            name: "GHLiveCore",
            dependencies: ["GIPProtocol", "GuitarInput", "KeyMapping", "KeyboardOutput", "USBTransport"]
        ),
        .target(
            name: "GHLiveCLI",
            dependencies: ["GHLiveCore", "GIPProtocol", "GuitarInput", "KeyMapping", "KeyboardOutput", "USBTransport"]
        ),
        .executableTarget(name: "ghlive", dependencies: ["GHLiveCLI"]),
        .target(
            name: "GHLiveAppKit",
            dependencies: ["GHLiveCore", "GuitarInput", "KeyMapping", "KeyboardOutput", "USBTransport"]
        ),
        .executableTarget(name: "GHLiveApp", dependencies: ["GHLiveAppKit"]),
        .testTarget(name: "GIPProtocolTests", dependencies: ["GIPProtocol"]),
        .testTarget(name: "GuitarInputTests", dependencies: ["GuitarInput"]),
        .testTarget(name: "KeyMappingTests", dependencies: ["KeyMapping", "GuitarInput"]),
        .testTarget(name: "KeyboardOutputTests", dependencies: ["KeyboardOutput", "KeyMapping", "GuitarInput"]),
        .testTarget(
            name: "GHLiveCoreTests",
            dependencies: ["GHLiveCore", "GIPProtocol", "GuitarInput", "KeyMapping", "KeyboardOutput", "USBTransport"]
        ),
        .testTarget(name: "USBTransportTests", dependencies: ["USBTransport"]),
        .testTarget(
            name: "GHLiveCLITests",
            dependencies: ["GHLiveCLI", "GHLiveCore", "GuitarInput", "KeyboardOutput", "USBTransport"]
        ),
        .testTarget(
            name: "GHLiveAppKitTests",
            dependencies: [
                "GHLiveAppKit", "GHLiveCore", "GIPProtocol", "GuitarInput", "KeyMapping", "KeyboardOutput",
                "USBTransport",
            ]
        ),
    ]
)
