// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OrderlyCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(
            name: "OrderlyCore",
            targets: ["OrderlyCore"]
        )
    ],
    targets: [
        .target(
            name: "OrderlyCore",
            path: "Orderly",
            exclude: [
                "App",
                "Assets.xcassets",
                "DesignSystem",
                "UI"
            ],
            sources: [
                "AI/PCCFullPipeline.swift",
                "AI/PCCSmokeTest.swift",
                "Content",
                "FileSystem",
                "FoundationModel",
                "Intelligence",
                "Models"
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "OrderlyCoreTests",
            dependencies: ["OrderlyCore"],
            path: "Tests/OrderlyCoreTests",
            sources: [
                "ContentInspectionTests.swift",
                "ExecutionEngineHardeningTests.swift"
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
