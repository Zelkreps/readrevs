public struct MetricRangeFilter: Equatable, Sendable {
    public var minimum: Int?
    public var maximum: Int?
    public var includesUnavailable: Bool

    public init(
        minimum: Int? = nil,
        maximum: Int? = nil,
        includesUnavailable: Bool = false
    ) {
        self.minimum = minimum
        self.maximum = maximum
        self.includesUnavailable = includesUnavailable
    }

    public var isActive: Bool {
        minimum != nil || maximum != nil
    }

    public func matches(_ value: Int?) -> Bool {
        guard isActive else { return true }
        guard let value else { return includesUnavailable }

        let lowerBound = min(minimum ?? Int.min, maximum ?? Int.max)
        let upperBound = max(minimum ?? Int.min, maximum ?? Int.max)
        return lowerBound...upperBound ~= value
    }
}
