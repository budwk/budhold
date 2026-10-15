// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BudHold",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "BudHoldCore", targets: ["BudHoldCore"]),
        .executable(name: "BudHoldApp", targets: ["BudHoldApp"]),
        .executable(name: "budhold", targets: ["BudHoldCLI"])
    ],
    targets: [
        .target(
            name: "BudHoldCore",
            path: "Sources/BudHoldCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "BudHoldApp",
            dependencies: ["BudHoldCore"],
            path: "Sources/BudHoldApp",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "BudHoldCLI",
            dependencies: ["BudHoldCore"],
            path: "Sources/BudHoldCLI"
        )
    ]
)
