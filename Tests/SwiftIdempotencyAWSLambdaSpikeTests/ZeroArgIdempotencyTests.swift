import Testing
@testable import SwiftIdempotencyAWSLambdaSpike
import SwiftIdempotency

// Cross-framework confirmation that `@IdempotencyTests` + the
// effect-aware expansion from finding #5 still generate warning-clean
// auto-tests in a Lambda adopter project.

@Suite
@IdempotencyTests
struct LambdaSpikeHealthChecks {

    @Idempotent
    func currentRuntimeRegion() -> String { "us-east-1" }

    @Idempotent
    func configurationHash() -> String { "cfg-v1" }

    /// Unmarked — should NOT appear in the generated tests.
    func forbiddenHelper() -> Int { 0 }
}
