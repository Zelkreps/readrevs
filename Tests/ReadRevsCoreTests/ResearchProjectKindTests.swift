import Foundation
import Testing
@testable import ReadRevsCore

@Test("Legacy research projects default to manual origin")
func legacyResearchProjectDefaultsToManualKind() throws {
    let projectID = UUID(uuidString: "80BA646C-BBA7-466A-B67E-3324F561E67A")!
    let payload = """
    {
      "id": "\(projectID.uuidString)",
      "name": "Legacy Research",
      "topic": "Geography",
      "targets": [{"language": "en", "store": "us"}],
      "genres": ["Education"],
      "seedKeywords": ["flags"],
      "keywords": [],
      "createdAt": 0,
      "updatedAt": 0
    }
    """

    let project = try JSONDecoder().decode(ResearchProject.self, from: Data(payload.utf8))

    #expect(project.id == projectID)
    #expect(project.kind == .manual)
}

@Test("App search presence origin survives persistence")
func appSearchPresenceKindRoundTrips() throws {
    let project = ResearchProject(
        name: "Example Flashcards Search Presence",
        topic: "Education",
        targets: [StoreTarget(language: "en", store: "us")],
        genres: ["Education"],
        seedKeywords: ["Example Flashcards"],
        focusAppAdamID: 42,
        kind: .appSearchPresence
    )

    let data = try JSONEncoder().encode(project)
    let decoded = try JSONDecoder().decode(ResearchProject.self, from: data)

    #expect(decoded.kind == .appSearchPresence)
    #expect(decoded.focusAppAdamID == 42)
}
