import AWSLambdaEvents
import AWSLambdaRuntime

// Lambda 2.x uses top-level code + `LambdaRuntime { ... }` as the
// entry shape. Ties the business logic from `SpikeApp.swift` into the
// Lambda event loop. Deployed on AWS this would run the loop forever;
// locally, `swift run` exits cleanly when there's no runtime API to
// poll.

let store = PaymentStore()

let runtime = LambdaRuntime {
    (event: SQSEvent, context: LambdaContext) async throws -> [ChargeResult] in
    try await handleSQSBatch(event, store: store)
}

try await runtime.run()
