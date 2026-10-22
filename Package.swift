// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyPin",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "keypin",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "keypinTests", dependencies: ["keypin"]),
    ]
)
