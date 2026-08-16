import ReadRevsCore
import Foundation
import Testing
@testable import ReadRevsApp

@Test("Removing a tracked app clears focus references and selects the next app")
@MainActor
func removingTrackedAppClearsFocusAndSelectsNextApp() throws {
    let firstApp = removalTestApp(id: 1, name: "Alpha")
    let secondApp = removalTestApp(id: 2, name: "Beta")
    let project = ResearchProject(
        name: "Research",
        topic: "",
        targets: [StoreTarget(language: "en", store: "us")],
        genres: [],
        seedKeywords: [],
        focusAppAdamID: firstApp.adamID
    )
    let store = try removalTestStore(
        library: ASOLibrary(projects: [project], apps: [firstApp, secondApp])
    )
    store.selection = .app(firstApp.adamID)

    store.removeApp(adamID: firstApp.adamID)

    #expect(store.library.apps.map(\.adamID) == [secondApp.adamID])
    #expect(store.project(id: project.id)?.focusAppAdamID == nil)
    #expect(store.selection == .app(secondApp.adamID))
}

@Test("Removing research apps chooses a nearby remaining selection")
@MainActor
func removingResearchAppChoosesNearbySelection() throws {
    let firstProject = removalTestProject(name: "Alpha")
    let secondProject = removalTestProject(name: "Beta")
    let app = removalTestApp(id: 7, name: "Tracked App")
    let store = try removalTestStore(
        library: ASOLibrary(projects: [firstProject, secondProject], apps: [app])
    )
    store.selection = .project(firstProject.id)

    store.removeProject(id: firstProject.id)

    #expect(store.library.projects.map(\.id) == [secondProject.id])
    #expect(store.selection == .project(secondProject.id))

    store.removeProject(id: secondProject.id)

    #expect(store.library.projects.isEmpty)
    #expect(store.selection == .app(app.adamID))
}

@MainActor
private func removalTestStore(library: ASOLibrary) throws -> LibraryStore {
    let fileURL = URL(fileURLWithPath: "/private/tmp/aso-removal-tests-\(UUID().uuidString)/library.json")
    let persistence = LibraryPersistence(fileURL: fileURL)
    try persistence.save(library)
    return LibraryStore(persistence: persistence)
}

private func removalTestProject(name: String) -> ResearchProject {
    ResearchProject(
        name: name,
        topic: "",
        targets: [StoreTarget(language: "en", store: "us")],
        genres: [],
        seedKeywords: []
    )
}

private func removalTestApp(id: Int64, name: String) -> TrackedApp {
    TrackedApp(
        adamID: id,
        name: name,
        developerName: "Studio",
        bundleID: "com.example.\(id)",
        primaryStore: "us",
        kind: .owned
    )
}
