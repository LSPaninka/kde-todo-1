// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorklogCalendar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "WorklogCalendar",
            path: "Sources/WorklogCalendar",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
