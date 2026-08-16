public struct PrioritizedUniqueQueue<Element, Key: Hashable> {
    public private(set) var pendingElements: [Element] = []

    private var pendingKeys: Set<Key> = []
    private let key: (Element) -> Key

    public init(key: @escaping (Element) -> Key) {
        self.key = key
    }

    public var isEmpty: Bool { pendingElements.isEmpty }
    public var count: Int { pendingElements.count }

    @discardableResult
    public mutating func enqueue(_ elements: [Element], prioritize: Bool) -> Int {
        guard prioritize else { return appendUnique(elements) }

        var promoted: [Element] = []
        var promotedKeys: Set<Key> = []
        var addedCount = 0

        for element in elements {
            let elementKey = key(element)
            guard promotedKeys.insert(elementKey).inserted else { continue }

            if let index = pendingElements.firstIndex(where: { key($0) == elementKey }) {
                promoted.append(pendingElements.remove(at: index))
                pendingKeys.remove(elementKey)
            } else {
                promoted.append(element)
                addedCount += 1
            }
        }

        pendingElements.insert(contentsOf: promoted, at: 0)
        pendingKeys.formUnion(promotedKeys)
        return addedCount
    }

    public mutating func popFirst() -> Element? {
        guard !pendingElements.isEmpty else { return nil }
        let element = pendingElements.removeFirst()
        pendingKeys.remove(key(element))
        return element
    }

    public mutating func removeAll() {
        pendingElements.removeAll()
        pendingKeys.removeAll()
    }

    private mutating func appendUnique(_ elements: [Element]) -> Int {
        var addedCount = 0
        for element in elements where pendingKeys.insert(key(element)).inserted {
            pendingElements.append(element)
            addedCount += 1
        }
        return addedCount
    }
}
