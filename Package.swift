// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "chatM",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "chatM",
            targets: ["chatM"]
        ),
    ],
    dependencies:[
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", exact: "0.21.1"),
    ],
    targets: [
        .executableTarget(
            name: "chatM",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1")
            ],
            path: "bitchat",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "bitchat.entitlements",
                "bitchat-macOS.entitlements",
                "LaunchScreen.storyboard"
            ]
        ),
    ]
)
