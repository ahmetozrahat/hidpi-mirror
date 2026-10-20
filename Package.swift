// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HiDPIMirror",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CGVirtualDisplayPrivate",
            path: "Sources/CGVirtualDisplayPrivate"
        ),
        .executableTarget(
            name: "HiDPIMirror",
            dependencies: ["CGVirtualDisplayPrivate"],
            path: "Sources/HiDPIMirror",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
