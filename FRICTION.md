# SwiftIdempotency × AWS Lambda — Friction Log

Third-framework road test. Hummingbird surfaced the 5 package-side
findings; Vapor cross-checked; this one validates against an
event-driven framework (not HTTP-shaped) where idempotency is
non-optional — Lambda retries failed invocations, and SQS/Kinesis/
DynamoDB Streams event sources all deliver at-least-once.

Runtime: `swift-aws-lambda-runtime` 2.x (current; the 1.x API was
superseded) + `swift-aws-lambda-events`. Platform `.macOS(.v15)`.

## TL;DR

- **All 5 package-side fixes carry over cleanly** — same signal as the
  Vapor cross-check, now across a structurally different framework.
  `IdempotencyKey`, the attributes, `@IdempotencyTests`, and async
  `#assertIdempotent` all work end-to-end against a Lambda handler.
- **1 new observation, not package-side**: AWSLambdaEvents event
  types (`SQSEvent.Message`) expose no public memberwise initialiser —
  they're `Decodable`-only — so tests can't synthesise synthetic
  events via a struct init, only via JSON decoding. This is an
  AWSLambdaEvents API shape, not a SwiftIdempotency concern; the
  implication for adopters is "factor your per-event business logic
  into functions that take primitive fields, then your tests don't
  need to build fixture events at all." Worth a line in the README
  alongside the Vapor/VaporTesting guidance.
- **Linter loop validates identically** — 3/3 planted negatives fire,
  same `"\(Date.now)"` bypass (L1) unchanged.
- **Stability: 10/10 runs green**.

## L1. Lambda's event types aren't test-synthesisable — fix is the
split-handler pattern we already recommend

**Observed.** The first test draft tried to build an `SQSEvent` via
`SQSEvent(records: [...])` and `SQSEvent.Message(messageId:, body:, ...)`.
Both fail to compile — the types expose only the `Decodable`
initialiser. So either:

- Construct JSON fixtures, decode them to produce the events, then
  hand those to the handler.
- Factor the handler's business logic into functions that take the
  specific fields they actually need (primitives, or custom structs
  that *are* memberwise-init-able), and push the `SQSEvent.Message`
  unwrapping up to the framework boundary.

The spike does both: `handleSQSBatch(_ event: SQSEvent, ...)` is the
framework boundary (tested with a JSON-fixture helper), and
`processOrderMessage(messageId:, body:, ...)` is the inner handler
(tested directly with primitives).

**Implication for SwiftIdempotency.** The package needed zero
changes. This observation reinforces the split-handler pattern that
landed out of finding #2 — if adopters structure their handlers this
way (and Lambda's own API shape pushes them to), the idempotency
annotations land naturally:

```swift
// Framework boundary — no SwiftIdempotency annotations, just unwrapping.
func handleSQSBatch(_ event: SQSEvent, store: PaymentStore) async throws -> [ChargeResult] { ... }

// Per-message — takes primitives, so @ExternallyIdempotent(by:) on the
// downstream call has a real parameter label to point at.
@Idempotent
func processOrderMessage(messageId: String, body: String, store: PaymentStore) async throws -> ChargeResult {
    let key = IdempotencyKey(fromAuditedString: messageId)
    return try await processCharge(amount: ..., idempotencyKey: key, store: store)
}

@ExternallyIdempotent(by: "idempotencyKey")
func processCharge(amount: Int, idempotencyKey: IdempotencyKey, ...) async throws -> ChargeResult { ... }
```

**Shipped.** Main SwiftIdempotency README gained a 9-line adopter
note in the Installation section right after the Vapor/VaporTesting
paragraph, telling Lambda adopters to factor per-event business logic
into primitive-argument functions. No code change in the package; the
observation is purely about how adopters structure their handlers.

## Package-side findings carrying over correctly

| Fix                                       | Lambda test that exercises it                   | Status |
|-------------------------------------------|-------------------------------------------------|--------|
| Async `#assertIdempotent`                 | `messageIdempotentViaMacro`                     | ✓      |
| `@ExternallyIdempotent(by:)` validation   | `processCharge` build-clean w/ real label       | ✓      |
| Effect-aware `@IdempotencyTests`          | `LambdaSpikeHealthChecks` auto-generated pair   | ✓      |
| Decode-then-compare canonical form        | N/A — no HTTP layer; `ChargeResult == ChargeResult` already stable | ✓ (trivially) |
| Tier-layering (`IdempotencyKey` subsumes) | Compile-level property                          | ✓      |

The decode-then-compare finding is a no-op here because Lambda tests
don't round-trip responses through a non-deterministic encoder — the
handler returns typed `ChargeResult` values directly. Useful
confirmation that the README's guidance is HTTP-specific, not
universal: Lambda adopters don't hit the JSON-key-ordering trap.

## Linter-integration loop

Positive cases: `handleSQSBatch`, `processOrderMessage`,
`processCharge`, `sendOrderConfirmationEmail` — **0 linter findings**.

Negative cases:

| Rule                          | Site in `SpikeNegatives.swift` | Fired? |
|-------------------------------|--------------------------------|--------|
| `MissingIdempotencyKey`       | line 15 — `UUID().uuidString`  | ✓      |
| `MissingIdempotencyKey`       | line 19 — `"\(Date.now)"`      | ✗ (L1 from Hummingbird) |
| `IdempotencyViolation`        | line 31                        | ✓      |
| `NonIdempotentInRetryContext` | line 38                        | ✓      |

Reproduction: `cd ~/xcode_projects/SwiftProjectLint && swift run CLI
<spike>/Sources --categories idempotency`.

## Conclusion

Lambda is the first structurally-different framework in the road test
series (event-driven, not HTTP-shaped). All 5 package-side fixes ship
as framework-agnostic. The new observation is about AWSLambdaEvents'
API design rather than SwiftIdempotency's — documented as a
README-level adopter hint, not a code change.
