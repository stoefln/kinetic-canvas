// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "KineticCanvas",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KineticCanvas", targets: ["KineticCanvas"])
    ],
    targets: [
        .executableTarget(
            name: "KineticCanvas",
            path: "Sources/KineticCanvas",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreML"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(name: "KineticCanvasTests", dependencies: ["KineticCanvas"])
    ],
    swiftLanguageVersions: [.v5]
)
