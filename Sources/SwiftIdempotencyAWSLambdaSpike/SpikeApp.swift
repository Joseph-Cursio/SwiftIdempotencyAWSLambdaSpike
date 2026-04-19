import Foundation
import AWSLambdaEvents
import AWSLambdaRuntime
import SwiftIdempotency

// Lambda-shaped counterpart to the Hummingbird and Vapor spikes.
// The handler processes an SQSEvent (AWS retries on at-least-once
// semantics, so every message needs idempotency). Business logic is
// factored into pure async functions so tests can call them directly
// without spinning up the LambdaRuntime event loop.

public actor PaymentStore {
    private var processed: [String: ChargeResult] = [:]
    public init() {}

    public func recordIfAbsent(
        key: String,
        result: ChargeResult
    ) -> ChargeResult {
        if let existing = processed[key] { return existing }
        processed[key] = result
        return result
    }
}

public struct ChargeResult: Codable, Equatable, Sendable {
    public let status: String
    public let amount: Int
    public let key: String
}

public struct OrderCommand: Codable, Sendable {
    public let amount: Int
}

/// Per-message handler. Takes `messageId` and `body` directly rather
/// than the whole `SQSEvent.Message` — two reasons:
///
/// 1. Split-handler pattern (Hummingbird finding #2): the idempotency
///    key is nested inside the SQS envelope, and
///    `@ExternallyIdempotent(by:)` can only name top-level parameter
///    labels. Pulling the key out into its own parameter lets the
///    downstream `@ExternallyIdempotent(by: "idempotencyKey")` on
///    `processCharge` do its job.
///
/// 2. `SQSEvent.Message` has no public memberwise initialiser — it's
///    `Decodable`-only. Tests would have to construct JSON fixtures
///    just to exercise this function. Taking primitives restores
///    direct testability.
///
/// The SQS message id is guaranteed stable across retries by AWS, so
/// `IdempotencyKey(fromAuditedString:)` is safe here; the audit
/// signal is the SQS contract itself.
@Idempotent
func processOrderMessage(
    messageId: String,
    body: String,
    store: PaymentStore
) async throws -> ChargeResult {
    let key = IdempotencyKey(fromAuditedString: messageId)
    let decoder = JSONDecoder()
    let command = try decoder.decode(
        OrderCommand.self,
        from: Data(body.utf8)
    )
    return try await processCharge(
        amount: command.amount,
        idempotencyKey: key,
        store: store
    )
}

/// Inner worker — takes the typed `IdempotencyKey` directly, so the
/// linter's `MissingIdempotencyKey` rule can verify call sites that
/// pass raw strings (legacy adopters) at the `idempotencyKey:` label.
@ExternallyIdempotent(by: "idempotencyKey")
func processCharge(
    amount: Int,
    idempotencyKey: IdempotencyKey,
    store: PaymentStore
) async throws -> ChargeResult {
    let result = ChargeResult(
        status: "succeeded",
        amount: amount,
        key: idempotencyKey.rawValue
    )
    return await store.recordIfAbsent(key: idempotencyKey.rawValue, result: result)
}

/// Batch handler — the full SQSEvent contains multiple records. The
/// Lambda runtime hands us the whole batch; we fan out per-message. No
/// idempotency annotation at this level because the per-message work
/// is what carries the semantic; the batch wrapping is mechanical.
public func handleSQSBatch(
    _ event: SQSEvent,
    store: PaymentStore
) async throws -> [ChargeResult] {
    var results: [ChargeResult] = []
    for message in event.records {
        let result = try await processOrderMessage(
            messageId: message.messageId,
            body: message.body,
            store: store
        )
        results.append(result)
    }
    return results
}

/// Non-idempotent counterpart — retry-unsafe. Annotated so the linter's
/// `NonIdempotentInRetryContext` rule would fire if anything declared
/// `@lint.context replayable` calls it directly.
@NonIdempotent
func sendOrderConfirmationEmail(for result: ChargeResult) async throws {
    _ = result
}
