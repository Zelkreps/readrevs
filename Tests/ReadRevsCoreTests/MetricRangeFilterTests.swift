import Testing
@testable import ReadRevsCore

@Test
func inactiveMetricRangeIncludesKnownAndUnavailableValues() {
    let filter = MetricRangeFilter()

    #expect(filter.matches(nil))
    #expect(filter.matches(0))
    #expect(filter.matches(100))
    #expect(!filter.isActive)
}

@Test
func activeMetricRangeUsesInclusiveBoundsAndHidesUnavailableByDefault() {
    let filter = MetricRangeFilter(minimum: 25, maximum: 70)

    #expect(!filter.matches(nil))
    #expect(!filter.matches(24))
    #expect(filter.matches(25))
    #expect(filter.matches(70))
    #expect(!filter.matches(71))
    #expect(filter.isActive)
}

@Test
func metricRangeCanIncludeUnavailableValuesAndNormalizesReversedBounds() {
    let filter = MetricRangeFilter(minimum: 70, maximum: 25, includesUnavailable: true)

    #expect(filter.matches(nil))
    #expect(filter.matches(25))
    #expect(filter.matches(50))
    #expect(filter.matches(70))
    #expect(!filter.matches(71))
}
