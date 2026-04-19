import Testing
import Foundation
import AWSLambdaEvents
@testable import SwiftIdempotencyAWSLambdaSpike
import SwiftIdempotency
import SwiftIdempotencyTestSupport

/// Lambda tests are simpler than the Hummingbird/Vapor versions — there's
/// no HTTP round-trip. The per-message handler is tested directly against
/// primitive `messageId` + `body` values; the batch handler is tested
/// through JSON-decoded `SQSEvent` fixtures (the only construction path
/// `SQSEvent.Message` exposes, since its memberwise initialiser isn't
/// public).
///
/// `LambdaRuntime.run()` is deliberately *not* invoked in tests — that
/// would try to connect to the Lambda runtime API which isn't there in a
/// test environment. The business logic is factored out of `main.swift`
/// so tests exercise it without standing up the loop.
@Suite struct OrderIdempotencyTests {

    // MARK: - Per-message replay (primitives — no SQS event needed)

    @Test func messageProcessingReturnsSameResultOnReplay() async throws {
        let store = PaymentStore()
        let first = try await processOrderMessage(
            messageId: "msg_spike_1",
            body: #"{"amount": 100}"#,
            store: store
        )
        let second = try await processOrderMessage(
            messageId: "msg_spike_1",
            body: #"{"amount": 100}"#,
            store: store
        )

        #expect(first == second)
        #expect(first.amount == 100)
        #expect(first.key == "msg_spike_1")
    }

    @Test func batchHandlerIsReplaySafe() async throws {
        let store = PaymentStore()
        let event = try makeSQSEvent(
            messages: [
                ("msg_a", #"{\"amount\": 50}"#),
                ("msg_b", #"{\"amount\": 75}"#),
            ]
        )

        let first = try await handleSQSBatch(event, store: store)
        let second = try await handleSQSBatch(event, store: store)

        #expect(first == second)
        #expect(first.count == 2)
    }

    // MARK: - Async #assertIdempotent against the handler

    /// Lambda-shaped counterpart to Hummingbird's `webhookIdempotentViaMacroHTTP`
    /// and Vapor's equivalent — confirms async `#assertIdempotent`
    /// composes cleanly over a Lambda handler.
    @Test func messageIdempotentViaMacro() async throws {
        let store = PaymentStore()

        let result = try await #assertIdempotent {
            try await processOrderMessage(
                messageId: "msg_macro_1",
                body: #"{"amount": 999}"#,
                store: store
            )
        }

        #expect(result.status == "succeeded")
        #expect(result.amount == 999)
    }

    // MARK: - Helpers

    /// Builds an `SQSEvent` via JSON decoding — the only construction
    /// path the type exposes, since `SQSEvent.Message` has no public
    /// memberwise initialiser. Documented as a Lambda-testing friction
    /// point in FRICTION.md; encapsulated here so test bodies stay
    /// clean. `body` is embedded literally into the synthesized JSON,
    /// so its quotes must be escaped at the call site.
    private func makeSQSEvent(
        messages: [(id: String, body: String)]
    ) throws -> SQSEvent {
        let records = messages.map { message in
            """
            {
              "messageId": "\(message.id)",
              "receiptHandle": "receipt-\(message.id)",
              "body": "\(message.body)",
              "md5OfBody": "",
              "attributes": {},
              "messageAttributes": {},
              "eventSourceARN": "arn:aws:sqs:us-east-1:000000000000:spike-queue",
              "eventSource": "aws:sqs",
              "awsRegion": "us-east-1"
            }
            """
        }
        let json = #"{"Records": [\#(records.joined(separator: ","))]}"#
        return try JSONDecoder().decode(SQSEvent.self, from: Data(json.utf8))
    }
}
