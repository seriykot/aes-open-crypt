// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "aes-open-crypt",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AESCryptKit", targets: ["AESCryptKit"]),
        .executable(name: "aesopen", targets: ["aesopen"]),
        .executable(name: "AESOpenCrypt", targets: ["AESOpenCrypt"]),
    ],
    targets: [
        .target(name: "AESCryptKit"),
        .target(name: "AESOpenCore", dependencies: ["AESCryptKit"]),
        .target(name: "AESOpenCLI", dependencies: ["AESCryptKit"]),
        .executableTarget(name: "aesopen", dependencies: ["AESOpenCLI"]),
        .executableTarget(name: "AESOpenCrypt", dependencies: ["AESCryptKit", "AESOpenCore"]),
        .testTarget(
            name: "AESCryptKitTests",
            dependencies: ["AESCryptKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "AESOpenCoreTests",
            dependencies: ["AESOpenCore", "AESCryptKit"]
        ),
        .testTarget(
            name: "AESOpenCLITests",
            dependencies: ["AESOpenCLI", "AESCryptKit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
