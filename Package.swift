// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pyb00st",
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [.library(name: "pyb00st", targets: ["pyb00st"])],
    targets: [
        .target(name: "pyb00st", path: "pyb00st", exclude: ["pyb00st.h"]),
        .testTarget(name: "pyb00stTests", dependencies: ["pyb00st"], path: "pyb00stTests"),
    ]
)
