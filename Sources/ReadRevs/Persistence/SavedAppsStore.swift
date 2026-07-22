import Foundation
import Observation

@MainActor
@Observable
final class SavedAppsStore {
    private(set) var apps: [AppMetadata]
    var selectedAppID: Int64? {
        didSet { persistSelection() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let appsKey = "savedApps.v1"
    @ObservationIgnored private let selectionKey = "selectedAppID.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedApps: [AppMetadata]
        if
            let data = defaults.data(forKey: appsKey),
            let decoded = try? JSONDecoder().decode([AppMetadata].self, from: data)
        {
            loadedApps = decoded
        } else {
            loadedApps = []
        }
        apps = loadedApps

        let storedSelection = defaults.object(forKey: selectionKey) as? NSNumber
        let candidate = storedSelection?.int64Value
        selectedAppID = candidate.flatMap { id in
            loadedApps.contains { $0.appID == id } ? id : nil
        }

        if selectedAppID == nil {
            selectedAppID = apps.first?.appID
        }
    }

    var selectedApp: AppMetadata? {
        guard let selectedAppID else { return nil }
        return apps.first { $0.appID == selectedAppID }
    }

    func upsert(_ app: AppMetadata, select: Bool = true) {
        if let index = apps.firstIndex(where: { $0.appID == app.appID }) {
            apps[index] = app
        } else {
            apps.append(app)
        }
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persistApps()

        if select {
            selectedAppID = app.appID
        }
    }

    func remove(appID: Int64) {
        apps.removeAll { $0.appID == appID }
        persistApps()
        if selectedAppID == appID {
            selectedAppID = apps.first?.appID
        }
    }

    private func persistApps() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        defaults.set(data, forKey: appsKey)
    }

    private func persistSelection() {
        if let selectedAppID {
            defaults.set(NSNumber(value: selectedAppID), forKey: selectionKey)
        } else {
            defaults.removeObject(forKey: selectionKey)
        }
    }
}
