// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftIdempotencyAWSLambdaSpike",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-events.git", from: "0.5.0"),
        .package(path: "../SwiftIdempotency"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftIdempotencyAWSLambdaSpike",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
        .testTarget(
            name: "SwiftIdempotencyAWSLambdaSpikeTests",
            dependencies: [
                "SwiftIdempotencyAWSLambdaSpike",
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
                .product(name: "SwiftIdempotencyTestSupport", package: "SwiftIdempotency"),
            ]
        ),
    ]
)
