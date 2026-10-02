// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DanceFX",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DanceFX", targets: ["DanceFX"])
    ],
    targets: [
        .executableTarget(
            name: "DanceFX",
            path: "Sources/DanceFX",
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
        .testTarget(name: "DanceFXTests", dependencies: ["DanceFX"])
    ],
    swiftLanguageVersions: [.v5]
)
