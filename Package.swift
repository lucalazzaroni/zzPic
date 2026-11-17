// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "zzPic",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "zzPic", targets: ["zzPic"]),
    ],
    targets: [
        // Pure imaging / file-system logic, unit-tested.
        .target(name: "ZZPicKit", path: "Sources/ZZPicKit"),
        // The AppKit + SwiftUI application.
        .executableTarget(name: "zzPic", dependencies: ["ZZPicKit"], path: "Sources/zzPic"),
        .testTarget(name: "ZZPicKitTests", dependencies: ["ZZPicKit"], path: "Tests/ZZPicKitTests"),
    ],
    swiftLanguageModes: [.v5]
)
