// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "IR2Studio",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "IR2Studio", targets: ["IR2Studio"])],
    targets: [
        .executableTarget(name: "IR2Studio", resources: [.process("Resources")]),
        .testTarget(name: "IR2StudioTests", dependencies: ["IR2Studio"])
    ]
)
