import SwiftUI

struct ResearchProjectDetailView: View {
    let projectID: UUID

    var body: some View {
        KeywordWorkspaceView(projectID: projectID)
    }
}
