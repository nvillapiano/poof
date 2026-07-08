// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Poof",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Poof",
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-reflection-metadata"])
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
