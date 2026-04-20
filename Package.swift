// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetSpeed",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NetSpeed",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/NetSpeed/Info.plist",
                ]),
            ]
        )
    ]
)
