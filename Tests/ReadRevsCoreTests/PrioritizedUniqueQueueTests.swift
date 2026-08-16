import Testing
@testable import ReadRevsCore

@Test
func prioritizedQueuePromotesPendingItemsAndKeepsRequestedOrder() {
    var queue = PrioritizedUniqueQueue<String, String>(key: { $0.lowercased() })
    #expect(queue.enqueue(["alpha", "beta", "gamma"], prioritize: false) == 3)

    #expect(queue.enqueue(["beta", "delta"], prioritize: true) == 1)
    #expect(queue.pendingElements == ["beta", "delta", "alpha", "gamma"])
}

@Test
func prioritizedQueueDeduplicatesPendingItemsWithoutMovingNormalEnqueues() {
    var queue = PrioritizedUniqueQueue<String, String>(key: { $0.lowercased() })
    #expect(queue.enqueue(["alpha", "beta"], prioritize: false) == 2)

    #expect(queue.enqueue(["ALPHA", "gamma", "gamma"], prioritize: false) == 1)
    #expect(queue.pendingElements == ["alpha", "beta", "gamma"])
}

@Test
func dequeuedItemCanBeEnqueuedAgainForRetry() {
    var queue = PrioritizedUniqueQueue<String, String>(key: { $0.lowercased() })
    _ = queue.enqueue(["alpha"], prioritize: false)

    #expect(queue.popFirst() == "alpha")
    #expect(queue.enqueue(["ALPHA"], prioritize: true) == 1)
    #expect(queue.popFirst() == "ALPHA")
}
