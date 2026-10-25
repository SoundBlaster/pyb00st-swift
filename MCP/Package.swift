// swift-tools-version: 6.1
import PackageDescription
import Foundation

let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Sources/MoveHubMCP/Info.plist").path

let package = Package(
    name: "pyb00st-mcp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "pyb00stMCP", targets: ["pyb00stMCP"]),
        .executable(name: "pyb00st-mcp", targets: ["MoveHubMCP"]),
    ],
    traits: [.trait(name: "MCP", description: "Enable the official MCP SDK and Move Hub tools.")],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", "0.12.1"..<"0.13.0"),
    ],
    targets: [
        .target(name: "pyb00stMCP", dependencies: [
            .product(name: "pyb00st", package: "pyb00st-swift", condition: .when(traits: ["MCP"])),
            .product(name: "MCP", package: "swift-sdk", condition: .when(traits: ["MCP"])),
        ]),
        .executableTarget(name: "MoveHubMCP", dependencies: ["pyb00stMCP"], exclude: ["Info.plist"], linkerSettings: [
            .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist], .when(platforms: [.macOS])),
        ]),
        .testTarget(name: "pyb00stMCPTests", dependencies: [
            "pyb00stMCP",
            .product(name: "pyb00st", package: "pyb00st-swift", condition: .when(traits: ["MCP"])),
            .product(name: "MCP", package: "swift-sdk", condition: .when(traits: ["MCP"])),
        ]),
    ]
)
