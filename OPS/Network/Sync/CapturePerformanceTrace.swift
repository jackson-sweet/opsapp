import os

/// Narrow local Instruments spans. No captured content, identities, or remote
/// telemetry. Pair device traces with synthetic work-count regression tests.
enum CapturePerformanceTrace {
    static let signposter = OSSignposter(subsystem: "com.ops.capture", category: "Persistence")
}
