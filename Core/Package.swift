// swift-tools-version: 5.9
import PackageDescription

// YushiKit：模型 / SSE 解析 / 网关客户端。
// 纯 Swift、零第三方依赖 —— Linux（CI ubuntu 容器）与 macOS 都能 swift test。
let package = Package(
    name: "YushiKit",
    platforms: [.iOS("26.0"), .macOS(.v14)], // 字符串形式：tools 5.9 尚无 .v26 枚举
    products: [
        .library(name: "YushiKit", targets: ["YushiKit"])
    ],
    targets: [
        .target(name: "YushiKit"),
        .testTarget(name: "YushiKitTests", dependencies: ["YushiKit"]),
    ]
)
