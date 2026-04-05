// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CAS",
    targets: [
        .target(name: "CAS", path: "Sources/CAS"),
        .executableTarget(name: "Demo", dependencies: ["CAS"], path: "Sources/Demo"),
        .testTarget(name: "CASTests", dependencies: ["CAS"], path: "Tests/CASTests"),
    ]
)
