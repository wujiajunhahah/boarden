import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var exhibits: [Exhibit] = []
    @Published var recentExhibitIds: [String] = []
    @Published private(set) var artifactPhotoURLs: [String: URL] = [:]
    @Published private(set) var exhibitLocations: [String: LocationRecord] = [:]
    
    /// 待跳转的展品详情（用于导航）
    @Published var pendingExhibitForDetail: Exhibit?
    
    /// 用户添加的展品（持久化存储）
    private var userExhibits: [Exhibit] = []

    private let exhibitService: ExhibitProviding
    private let recentsKey = "recentExhibitIds"
    private let artifactKey = "artifactPhotoURLs"
    private let locationKey = "exhibitLocations"
    private let userExhibitsKey = "userExhibits"
    private let locationService = LocationService()
    
    /// 用户展品存储文件路径
    private var userExhibitsURL: URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return folder.appendingPathComponent("user_exhibits.json")
    }

    init(exhibitService: ExhibitProviding = ExhibitService()) {
        self.exhibitService = exhibitService
        loadRecents()
        loadArtifacts()
        loadLocations()
        loadUserExhibits()
    }

    func loadExhibits() async {
        do {
            // 加载预置展品
            let bundleExhibits = try await exhibitService.loadExhibits()
            // 合并用户展品（用户展品优先显示在前面，且不会被预置展品覆盖）
            var merged: [Exhibit] = userExhibits
            for exhibit in bundleExhibits {
                if !merged.contains(where: { $0.id == exhibit.id }) {
                    merged.append(exhibit)
                }
            }
            exhibits = merged
        } catch {
            // 即使加载预置展品失败，仍显示用户展品
            exhibits = userExhibits
        }
    }

    func exhibit(by id: String) -> Exhibit? {
        exhibits.first { $0.id == id }
    }

    func upsertExhibit(_ exhibit: Exhibit) {
        // 更新 exhibits 数组
        if let index = exhibits.firstIndex(where: { $0.id == exhibit.id }) {
            exhibits[index] = exhibit
        } else {
            exhibits.insert(exhibit, at: 0)
        }
        
        // 同步更新用户展品并持久化
        if let index = userExhibits.firstIndex(where: { $0.id == exhibit.id }) {
            userExhibits[index] = exhibit
        } else {
            userExhibits.insert(exhibit, at: 0)
        }
        saveUserExhibits()
    }

    func addRecent(exhibit: Exhibit) {
        recentExhibitIds.removeAll { $0 == exhibit.id }
        recentExhibitIds.insert(exhibit.id, at: 0)
        if recentExhibitIds.count > 10 {
            recentExhibitIds = Array(recentExhibitIds.prefix(10))
        }
        saveRecents()
    }

    private func loadRecents() {
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            recentExhibitIds = ids
        }
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recentExhibitIds) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    func saveArtifactPhoto(data: Data, exhibitId: String) -> URL? {
        let filename = "artifact_\(exhibitId)_\(UUID().uuidString).jpg"
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let url = folder?.appendingPathComponent(filename) else { return nil }
        do {
            try data.write(to: url)
            artifactPhotoURLs[exhibitId] = url
            saveArtifacts()
            return url
        } catch {
            return nil
        }
    }

    func artifactPhotoURL(for exhibitId: String) -> URL? {
        artifactPhotoURLs[exhibitId]
    }

    func captureLocation(for exhibitId: String) async {
        if let record = await locationService.fetchCurrentLocation() {
            exhibitLocations[exhibitId] = record
            saveLocations()
        }
    }

    func locationRecord(for exhibitId: String) -> LocationRecord? {
        exhibitLocations[exhibitId]
    }

    private func loadArtifacts() {
        if let data = UserDefaults.standard.data(forKey: artifactKey),
           let entries = try? JSONDecoder().decode([String: String].self, from: data) {
            var urls: [String: URL] = [:]
            for (key, value) in entries {
                if let url = URL(string: value) {
                    urls[key] = url
                }
            }
            artifactPhotoURLs = urls
        }
    }

    private func saveArtifacts() {
        let entries = artifactPhotoURLs.mapValues { $0.absoluteString }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: artifactKey)
        }
    }

    private func loadLocations() {
        if let data = UserDefaults.standard.data(forKey: locationKey),
           let entries = try? JSONDecoder().decode([String: LocationRecord].self, from: data) {
            exhibitLocations = entries
        }
    }

    private func saveLocations() {
        if let data = try? JSONEncoder().encode(exhibitLocations) {
            UserDefaults.standard.set(data, forKey: locationKey)
        }
    }
    
    // MARK: - 用户展品持久化
    
    /// 加载用户添加的展品
    private func loadUserExhibits() {
        guard FileManager.default.fileExists(atPath: userExhibitsURL.path) else {
            print("[AppState] 用户展品文件不存在，跳过加载")
            return
        }
        
        do {
            let data = try Data(contentsOf: userExhibitsURL)
            userExhibits = try JSONDecoder().decode([Exhibit].self, from: data)
            print("[AppState] 已加载 \(userExhibits.count) 个用户展品")
        } catch {
            print("[AppState] 加载用户展品失败: \(error)")
            userExhibits = []
        }
    }
    
    /// 保存用户添加的展品
    private func saveUserExhibits() {
        do {
            let data = try JSONEncoder().encode(userExhibits)
            try data.write(to: userExhibitsURL)
            print("[AppState] 已保存 \(userExhibits.count) 个用户展品")
        } catch {
            print("[AppState] 保存用户展品失败: \(error)")
        }
    }
    
    /// 删除用户展品
    func deleteUserExhibit(_ exhibitId: String) {
        exhibits.removeAll { $0.id == exhibitId }
        userExhibits.removeAll { $0.id == exhibitId }
        recentExhibitIds.removeAll { $0 == exhibitId }
        artifactPhotoURLs.removeValue(forKey: exhibitId)
        exhibitLocations.removeValue(forKey: exhibitId)
        
        saveUserExhibits()
        saveRecents()
        saveArtifacts()
        saveLocations()
        
        print("[AppState] 已删除展品: \(exhibitId)")
    }
    
    /// 获取用户展品数量
    var userExhibitCount: Int {
        userExhibits.count
    }
}
