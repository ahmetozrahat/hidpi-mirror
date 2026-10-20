// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HiDPIMirror",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PrivateAPIs",
            path: "Sources/PrivateAPIs"
        ),
        .executableTarget(
            name: "HiDPIMirror",
            dependencies: ["PrivateAPIs"],
            path: "Sources/HiDPIMirror",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
