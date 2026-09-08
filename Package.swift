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
    .target(
      name: "BedrockForFoundationModels",
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
