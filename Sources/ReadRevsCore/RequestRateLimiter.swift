import Foundation

actor RequestRateLimiter {
    private let minimumInterval: TimeInterval
    private var nextRequestDate = Date.distantPast

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = max(minimumInterval, 0)
    }

    func waitForTurn() async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            let delay = nextRequestDate.timeIntervalSince(now)

            if delay <= 0 {
                nextRequestDate = now.addingTimeInterval(minimumInterval)
                return
            }

            let nanoseconds = UInt64((delay * 1_000_000_000).rounded(.up))
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    func deferRequests(by interval: TimeInterval) {
        nextRequestDate = max(nextRequestDate, Date().addingTimeInterval(max(interval, 0)))
    }
}

extension HTTPURLResponse {
    func retryAfterDelay(fallback: TimeInterval) -> TimeInterval {
        value(forHTTPHeaderField: "Retry-After")
            .flatMap(TimeInterval.init)
            .map { max($0, 0) } ?? fallback
    }
}
