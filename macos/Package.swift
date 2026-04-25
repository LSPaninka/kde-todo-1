// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CategorizedToDo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CategorizedToDo", targets: ["CategorizedToDo"])
    ],
    targets: [
        .executableTarget(
            name: "CategorizedToDo",
            path: "Sources/CategorizedToDo",
            exclude: ["Resources/Info.plist"],
            resources: []
        )
    ]
)
