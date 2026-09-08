# BedrockForFoundationModels

A Swift package that lets you use [Amazon Bedrock](https://aws.amazon.com/bedrock/) as a backend for Apple's [FoundationModels](https://developer.apple.com/documentation/foundationmodels) framework.

It provides `BedrockLanguageModel`, a `LanguageModel` implementation backed by the Bedrock Converse API. Pass it to `LanguageModelSession` and use the FoundationModels APIs as usual — only inference is delegated to Bedrock.

## Features

- Uses the Bedrock Converse API (`POST /model/{modelId}/converse`)
- Supports both **Bedrock API keys** (bearer token) and **AWS SigV4** credentials, including temporary session tokens
- Supports tool calling
- Supports reasoning content, carrying the signature over to the next turn
- Retries `503` responses with exponential backoff (up to 3 retries)
- No external dependencies — only `Foundation` and `CommonCrypto`

## Requirements

- Swift 6.4+
- Deployment targets: iOS 18+ / macOS 14+ (as declared in `Package.swift`)

The package itself builds and links against those targets, so you can add it to a project with a lower deployment target. The APIs it exposes are annotated `@available(anyAppleOS 27, *)`, so guard their use with `if #available(...)` and only call them on OS version 27 or newer.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nnabeyang/bedrock-for-foundation-models.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "BedrockForFoundationModels", package: "bedrock-for-foundation-models"),
        ]
    ),
]
```

In Xcode, use **File > Add Package Dependencies…** with the same URL.

## Usage

Create a `BedrockLanguageModel` and hand it to FoundationModels. Everything after that is plain FoundationModels usage.

```swift
import FoundationModels
import BedrockForFoundationModels

let model = BedrockLanguageModel(
    modelId: "us.anthropic.claude-sonnet-5-20250929-v1:0",
    region: "us-east-1",
    auth: .apiKey(apiKey)
)

let session = LanguageModelSession(model: model)
```

### Authentication

Bedrock API key, sent as a bearer token:

```swift
let auth = BedrockAuth.apiKey("<bedrock api key>")
```

AWS SigV4 credentials, signed per request as `AWS4-HMAC-SHA256`:

```swift
let auth = BedrockAuth.sigV4(
    accessKeyId: "<AWS_ACCESS_KEY_ID>",
    secretKey: "<AWS_SECRET_ACCESS_KEY>",
    sessionToken: nil  // pass a session token when using temporary STS credentials
)
```

> [!NOTE]
> Do not hardcode credentials. Read them from the environment or the Keychain.

### Tool schemas

Tool definitions are translated into Bedrock's `toolConfig`. JSON Schema keys that Bedrock rejects (`additionalProperties`, `title`, `x-order`, and others) are stripped before the request is sent.

## Development

```sh
swift build
swift test
./format.sh   # formats with swift format
```

## License

[MIT](LICENSE)
