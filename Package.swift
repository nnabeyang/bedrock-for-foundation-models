// swift-tools-version: 6.4

import PackageDescription

let package = Package(
  name: "BedrockForFoundationModels",
  platforms: [
    .iOS(.v18), .macOS(.v14),
  ],
  products: [
    .library(
      name: "BedrockForFoundationModels",
      targets: ["BedrockForFoundationModels"]
    )
  ],
  targets: [
    // Converse API wire types, HTTP client and SigV4 signing. No dependency on
    // FoundationModels, so it carries no availability constraint and can be
    // exercised on its own.
    .target(
      name: "BedrockRuntimeAPI",
      swiftSettings: [
        .enableUpcomingFeature("ApproachableConcurrency")
      ],
    ),

    // FoundationModels ↔ Converse API bridge.
    .target(
      name: "BedrockForFoundationModels",
      dependencies: ["BedrockRuntimeAPI"],
      swiftSettings: [
        .enableUpcomingFeature("ApproachableConcurrency")
      ],
    ),

    .testTarget(
      name: "BedrockRuntimeAPITests",
      dependencies: ["BedrockRuntimeAPI"],
      swiftSettings: [
        .enableUpcomingFeature("ApproachableConcurrency")
      ],
    ),
    .testTarget(
      name: "BedrockForFoundationModelsTests",
      dependencies: ["BedrockForFoundationModels"],
      swiftSettings: [
        .enableUpcomingFeature("ApproachableConcurrency")
      ],
    ),
  ]
)
