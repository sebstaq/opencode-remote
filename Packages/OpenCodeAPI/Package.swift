// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OpenCodeAPI",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "OpenCodeAPI", targets: ["OpenCodeAPI"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.7.0"),
    .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.0"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.1.0"),
  ],
  targets: [
    .target(
      name: "OpenCodeAPI",
      dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
      ],
      plugins: [
        .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
      ]
    )
  ]
)
