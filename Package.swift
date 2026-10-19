// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Timer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Timer",
            path: "Sources/Timer"
        ),
        .testTarget(
            name: "TimerTests",
            dependencies: ["Timer"],
            path: "Tests/TimerTests"
        )
    ]
)
