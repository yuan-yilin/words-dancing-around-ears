// swift-tools-version: 5.9
import PackageDescription

// 本地 vendored 二进制依赖（离线构建, 不访问网络）
//
// 来源（与官方 Package.swift 的远程 checksum 一致, 见 scripts/setup-vendor.sh）:
//   - k2-fsa/sherpa-onnx release xcframework v1.13.8 (macos-static / ios-static)
//   - csukuangfj/onnxruntime-libs release v1.28.2 (macos-static / ios-static)
// Swift wrapper 为官方 swift-api-examples/SherpaOnnx.swift 的原样拷贝
// (Sources/Core/Vendored/SherpaOnnx.swift)。
let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    targets: [
        // --- sherpa-onnx 预编译库 ---
        .binaryTarget(
            name: "SherpaOnnxMacOS",
            path: "Vendor/SherpaOnnxMacOS.xcframework"
        ),
        .binaryTarget(
            name: "SherpaOnnxIOS",
            path: "Vendor/SherpaOnnxIOS.xcframework"
        ),
        // --- onnxruntime 预编译库 ---
        .binaryTarget(
            name: "OnnxruntimeMacOS",
            path: "Vendor/OnnxruntimeMacOS.xcframework"
        ),
        .binaryTarget(
            name: "OnnxruntimeIOS",
            path: "Vendor/OnnxruntimeIOS.xcframework"
        ),
        .target(
            name: "Core",
            dependencies: [
                .target(name: "SherpaOnnxMacOS", condition: .when(platforms: [.macOS])),
                .target(name: "OnnxruntimeMacOS", condition: .when(platforms: [.macOS])),
                .target(name: "SherpaOnnxIOS", condition: .when(platforms: [.iOS])),
                .target(name: "OnnxruntimeIOS", condition: .when(platforms: [.iOS])),
            ],
            path: "Sources/Core",
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        )
    ]
)
