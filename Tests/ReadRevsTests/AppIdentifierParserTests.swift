import Testing
@testable import ReadRevs

@Suite("App identifier parsing")
struct AppIdentifierParserTests {
    @Test("Parses a numeric App Store ID")
    func parsesNumericID() throws {
        #expect(try AppIdentifierParser.parse(" 284910350 ") == 284_910_350)
    }

    @Test("Parses IDs from modern App Store URLs")
    func parsesURL() throws {
        let input = "https://apps.apple.com/us/app/yelp-food-services-reviews/id284910350?platform=iphone"
        #expect(try AppIdentifierParser.parse(input) == 284_910_350)
    }

    @Test("Rejects input without an App Store ID")
    func rejectsInvalidInput() {
        #expect(throws: AppIdentifierParser.Error.invalidIdentifier) {
            try AppIdentifierParser.parse("Yelp")
        }
    }
}
